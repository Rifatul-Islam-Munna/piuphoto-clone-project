import Flutter
import Foundation
import ImageCaptureCore

/// USB camera file receiver only. No shutter, remote-mode, or vendor PTP commands.
/// Constructed by AppDelegate; ICDeviceBrowser is started ONLY by start().
final class SimpleUsbCameraReceiver: NSObject, FlutterStreamHandler, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
  private var browser: ICDeviceBrowser?
  private var camera: ICCameraDevice?
  private var sessionId: String?
  private var uploadMode = "newShotsOnly"
  private var waitingStart: FlutterResult?
  private var eventSink: FlutterEventSink?
  private var ready = false
  private var stopping = false
  private var stopCallbacks: [FlutterResult] = []
  private var deadline: DispatchWorkItem?
  private var scanTimer: Timer?
  private var seen: Set<String> = []
  private var pending: [String: ICCameraFile] = [:]
  private var queue: [String] = []
  private var staged: [String: URL] = [:]
  private var downloading: [String: FlutterResult] = [:]

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    // Flutter cancels its event listener BEFORE calling stop(). Give the
    // explicit stop method time to await the actual camera close. A lost
    // listener is still cleaned up after a short grace period.
    let token = sessionId
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
      guard let self = self, self.eventSink == nil,
            let token = token, self.sessionId == token else { return }
      self.stop(sessionID: token, result: { _ in })
    }
    return nil
  }

  private func emit(_ type: String, message: String = "", code: String? = nil) {
    guard let sessionId = sessionId else { return }
    var payload: [String: Any] = ["sessionId": sessionId, "type": type, "message": message]
    if let code = code { payload["code"] = code }
    eventSink?(payload)
  }

  private func failure(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  func start(arguments: [String: Any]?, result: @escaping FlutterResult) {
    assert(Thread.isMainThread)
    guard sessionId == nil && !stopping else {
      result(failure("LIVE_CAMERA_BUSY", "A USB camera session is already running or closing."))
      return
    }
    guard let id = arguments?["sessionId"] as? String, !id.isEmpty else {
      result(failure("LIVE_CAMERA_INVALID_SESSION", "A camera session ID is required."))
      return
    }
    sessionId = id
    uploadMode = arguments?["uploadMode"] as? String == "existingAndNew" ? "existingAndNew" : "newShotsOnly"
    waitingStart = result
    ready = false
    seen.removeAll()
    pending.removeAll()
    queue.removeAll()
    staged.removeAll()

    let newBrowser = ICDeviceBrowser()
    browser = newBrowser
    newBrowser.delegate = self
    if #available(iOS 15.2, *) {
      newBrowser.browsedDeviceTypeMask = .camera
    }
    emit("status", message: "Checking permission and looking for a USB camera.")
    // Contents access is sufficient. Never request Control authorization,
    // use requestSendPTPCommand, or trigger the camera's shutter.
    newBrowser.requestContentsAuthorization { [weak self, weak newBrowser] status in
      DispatchQueue.main.async {
        guard let self = self, self.sessionId == id, self.browser === newBrowser, !self.stopping else { return }
        guard status == .authorized else {
          self.abort("CAMERA_ACCESS_DENIED", "Allow external-camera contents access in iPhone settings.")
          return
        }
        newBrowser?.start()
        self.scheduleTimeout(for: id, seconds: 20, message: "No supported USB camera was detected. Check cable, adapter, and camera connection mode.")
      }
    }
  }

  private func scheduleTimeout(for token: String, seconds: TimeInterval, message: String) {
    deadline?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self, self.sessionId == token, !self.ready else { return }
      self.abort("CAMERA_NOT_READY", message)
    }
    deadline = work
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
  }

  private func abort(_ code: String, _ message: String) {
    emit("error", message: message, code: code)
    waitingStart?(failure(code, message))
    waitingStart = nil
    stop(sessionID: sessionId, result: { _ in })
  }

  // The catalog must be complete before determining which images are old.
  private func markReady(_ device: ICCameraDevice) {
    guard camera === device, sessionId != nil, !stopping, !ready else { return }
    let originals = images(on: device)
    seen.formUnion(originals.map(identity))
    ready = true
    deadline?.cancel()
    deadline = nil
    if uploadMode == "existingAndNew" {
      originals.forEach { file in
        let id = identity(file)
        pending[id] = file
        queue.append(id)
      }
    }
    let id = sessionId!
    let existing = originals.count
    let physicalShutter = device.capabilities.contains(
      ICDeviceCapability.cameraDeviceCanTakePictureUsingShutterReleaseOnCamera.rawValue
    ) ? "supported" : "unknown"
    let response = waitingStart
    waitingStart = nil
    response?([
      "sessionId": id,
      "cameraId": device.uuidString ?? device.name ?? "USB camera",
      "name": device.name ?? "USB camera",
      "physicalShutter": physicalShutter,
      "message": "Camera files are available. Take a TEST photo with its physical shutter. If the display/shutter is locked, stop and select a shooting-compatible USB mode on the camera.",
      "baselineCount": existing,
      "uploadMode": uploadMode
    ])
    emit("status", message: "Camera connected. Watching for new saved photos.")
    if !queue.isEmpty { emit("photosAvailable") }
    scanTimer?.invalidate()
    scanTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
      self?.scan()
    }
  }

  private func images(on device: ICCameraDevice) -> [ICCameraFile] {
    (device.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }.filter { isPhoto($0) }
  }

  private func isPhoto(_ file: ICCameraFile) -> Bool {
    let name = (file.originalFilename ?? file.name ?? "").lowercased()
    return [".jpg", ".jpeg", ".heic", ".heif", ".png", ".tif", ".tiff",
            ".dng", ".cr2", ".cr3", ".nef", ".nrw", ".arw", ".raf",
            ".rw2", ".orf", ".pef", ".srw", ".3fr", ".iiq"].contains { name.hasSuffix($0) }
  }

  private func identity(_ file: ICCameraFile) -> String {
    let name = file.originalFilename ?? file.name ?? "image"
    // PTP object handles remain stable while metadata (date and file size) fills in.
    // Do not create a duplicate upload when the same camera file gains metadata.
    if file.ptpObjectHandle != 0 {
      return "ptp-\(file.ptpObjectHandle)"
    }
    let timestamp = file.fileCreationDate?.timeIntervalSince1970 ?? 0
    return "file-\(name)-\(Int64(timestamp * 1000))"
  }

  private func observe(_ file: ICCameraFile) {
    guard ready, isPhoto(file) else { return }
    let id = identity(file)
    guard seen.insert(id).inserted else { return }
    pending[id] = file
    queue.append(id)
    emit("photosAvailable")
  }

  private func scan() {
    guard ready, let camera = camera, !stopping else { return }
    images(on: camera).forEach(observe)
  }

  func pendingImages(sessionID: String?, result: @escaping FlutterResult) {
    guard let id = sessionId, id == sessionID, ready, !stopping else {
      result(failure("LIVE_CAMERA_NOT_RUNNING", "Start a USB receiving session first."))
      return
    }
    scan()
    let items: [[String: Any]] = queue.compactMap { key in
      guard let file = pending[key] else { return nil }
      return ["id": key, "name": file.originalFilename ?? file.name ?? "camera-image.jpg",
              "size": Int(max(0, file.fileSize))]
    }
    result(items)
  }

  func download(sessionID: String?, imageID: String?, result: @escaping FlutterResult) {
    guard sessionID == sessionId, ready, !stopping, let key = imageID,
          let file = pending[key] else {
      result(failure("CAMERA_IMAGE_NOT_FOUND", "This camera photo is no longer pending."))
      return
    }
    if let location = staged[key],
       let attributes = try? FileManager.default.attributesOfItem(atPath: location.path),
       let size = attributes[.size] as? NSNumber,
       size.int64Value > 0 {
      result(["id": key, "name": file.originalFilename ?? file.name ?? "camera-image.jpg", "path": location.path])
      return
    }
    guard downloading[key] == nil else {
      result(failure("CAMERA_DOWNLOAD_BUSY", "The photo is currently downloading."))
      return
    }
    downloading[key] = result
    let temp = FileManager.default.temporaryDirectory
    let raw = file.originalFilename ?? file.name ?? "camera-photo.jpg"
    let safe = (raw as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "_")
    let unique = "airpix_\(UUID().uuidString)_\(safe)"
    let options: [ICDownloadOption: Any] = [
      .downloadsDirectoryURL: temp,
      .saveAsFilename: unique,
      .overwrite: false,
      .deleteAfterSuccessfulDownload: false
    ]
    _ = file.requestDownload(options: options) { [weak self] savedFilename, error in
      DispatchQueue.main.async {
        guard let self = self, let callback = self.downloading.removeValue(forKey: key) else { return }
        guard self.sessionId == sessionID, !self.stopping else {
          callback(self.failure("LIVE_CAMERA_SESSION_ENDED", "The camera session was stopped."))
          return
        }
        if let error = error {
          callback(self.failure("CAMERA_IMPORT_FAILED", error.localizedDescription))
          return
        }
        guard let name = savedFilename else {
          callback(self.failure("CAMERA_IMPORT_FAILED", "The camera did not provide a saved filename."))
          return
        }
        let path = (name as NSString).isAbsolutePath ? URL(fileURLWithPath: name) : temp.appendingPathComponent(name)
        let base = temp.standardizedFileURL.path
        guard path.standardizedFileURL.path.hasPrefix(base + "/"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
          callback(self.failure("CAMERA_IMPORT_FAILED", "The downloaded camera photo was incomplete."))
          return
        }
        self.staged[key] = path
        callback(["id": key, "name": raw, "path": path.path])
      }
    }
  }

  func acknowledge(sessionID: String?, ids: [String], result: @escaping FlutterResult) {
    guard sessionID == self.sessionId, !stopping else {
      result(failure("LIVE_CAMERA_SESSION_ENDED", "The session has ended."))
      return
    }
    for id in ids {
      pending.removeValue(forKey: id)
      queue.removeAll { $0 == id }
      // Flutter has already copied the image to its durable upload queue.
      if let location = staged.removeValue(forKey: id) {
        try? FileManager.default.removeItem(at: location)
      }
    }
    result(nil)
  }

  func stop(sessionID wantedID: String?, result: @escaping FlutterResult) {
    if let wantedID = wantedID, let active = sessionId, wantedID != active {
      result(failure("LIVE_CAMERA_SESSION_MISMATCH", "A different USB session is active."))
      return
    }
    if stopping {
      stopCallbacks.append(result)
      return
    }
    guard sessionId != nil else { result(nil); return }
    stopping = true
    stopCallbacks.append(result)
    waitingStart?(failure("LIVE_CAMERA_CANCELLED", "Camera receiving was stopped."))
    waitingStart = nil
    deadline?.cancel()
    deadline = nil
    scanTimer?.invalidate()
    scanTimer = nil
    for callback in downloading.values {
      callback(failure("LIVE_CAMERA_CANCELLED", "Camera receiving was stopped."))
    }
    downloading.removeAll()
    let previousCamera = camera
    let finish: (Error?) -> Void = { [weak self] closeError in
      DispatchQueue.main.async {
        guard let self = self else { result(nil); return }
        self.browser?.stop()
        self.browser?.delegate = nil
        self.browser = nil
        self.camera?.delegate = nil
        self.camera = nil
        self.sessionId = nil
        self.ready = false
        self.seen.removeAll()
        self.pending.removeAll()
        self.queue.removeAll()
        self.staged.removeAll()
        self.stopping = false
        let callbacks = self.stopCallbacks
        self.stopCallbacks.removeAll()
        if let closeError = closeError {
          callbacks.forEach { $0(self.failure("CAMERA_CLOSE_FAILED", closeError.localizedDescription)) }
        } else {
          callbacks.forEach { $0(nil) }
        }
      }
    }
    guard let old = previousCamera, old.hasOpenSession else {
      finish(nil)
      return
    }
    old.requestCloseSession(options: nil) { error in finish(error) }
  }

  // MARK: Camera discovery (runs only after the session start button)
  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    guard browser === self.browser, sessionId != nil, !stopping, camera == nil,
          let found = device as? ICCameraDevice else { return }
    let transport = (found.transportType ?? "").lowercased()
    if transport.contains("network") || transport.contains("wifi") ||
       transport.contains("wireless") || transport.contains("tcp") { return }
    if transport.contains("mass") && transport.contains("storage") {
      abort("CAMERA_STORAGE_ONLY", "Camera is exposing only USB storage. Disconnect and choose a shooting-compatible USB mode.")
      return
    }
    camera = found
    found.delegate = self
    if let id = sessionId {
      scheduleTimeout(for: id, seconds: 30, message: "Camera file catalog did not become ready. Stop and check the camera's USB shooting mode.")
    }
    emit("status", message: "Found \(found.name ?? "USB camera"). Opening photo access.")
    found.requestOpenSession()
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    if device === camera && !stopping {
      emit("disconnected", message: "Camera unplugged. Stop and restart receiving.", code: "USB_CAMERA_DISCONNECTED")
      abort("USB_CAMERA_DISCONNECTED", "The USB camera was disconnected.")
    }
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    guard device === camera, !stopping else { return }
    if let error = error {
      abort("CAMERA_SESSION_FAILED", error.localizedDescription)
    } else {
      emit("status", message: "Reading camera photo catalog. Keep the camera powered on.")
    }
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
  func didRemove(_ device: ICDevice) {}
  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) { markReady(device) }

  func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
    guard camera === self.camera, ready, !stopping else { return }
    items.compactMap { $0 as? ICCameraFile }.forEach(observe)
  }

  func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
    // Do not ACK missing sources; an undelivered photo remains retryable.
  }
  func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
  func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
  func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
  func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
  func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
    // No raw command processing. Scan when the camera reports a new file.
    scan()
  }
  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
    emit("status", message: "The camera has restricted photo access. Unlock it or stop receiving.")
  }
  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) { scan() }
}
