import Flutter
import Foundation
import CoreFoundation
import ImageCaptureCore

/// Permission and camera shooting mode are separate. An unresolved iOS request
/// must never be reported as an explicit denial or treated as permission granted.
enum WiredCameraAuthorizationState: String {
  case authorized
  case denied
  case restricted
  case pending = "not-determined"
  case unavailable

  @available(iOS 14.0, *)
  init(_ status: ICAuthorizationStatus) {
    if status == .authorized { self = .authorized }
    else if status == .denied { self = .denied }
    else if status == .restricted { self = .restricted }
    else if status == .notDetermined { self = .pending }
    else { self = .unavailable }
  }

  var allowsContentsAccess: Bool { self == .authorized }

  var errorCode: String? {
    switch self {
    case .authorized: return nil
    case .denied: return "CAMERA_ACCESS_DENIED"
    case .restricted: return "CAMERA_ACCESS_RESTRICTED"
    case .pending: return "CAMERA_AUTHORIZATION_PENDING"
    case .unavailable: return "CAMERA_AUTHORIZATION_UNAVAILABLE"
    }
  }

  var message: String {
    switch self {
    case .authorized:
      return "External camera contents access is allowed."
    case .denied:
      return "External camera access is denied. Allow camera access for AirPix in iPhone Settings, then retry."
    case .restricted:
      return "iOS has restricted external camera access. Check Screen Time or device-management restrictions, then retry."
    case .pending:
      return "iOS has not completed external camera authorization. Keep the iPhone unlocked, respond to any access prompt, then retry the connection."
    case .unavailable:
      return "iOS could not determine external camera authorization. Reopen AirPix, reconnect the camera and retry."
    }
  }

}

/// One opt-in USB owner for either vendor tethering or explicit catalog import.
/// Vendor negotiation lives in Dart; ImageCaptureCore owns the USB session.
final class SimpleUsbCameraReceiver: NSObject, FlutterStreamHandler, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
  private let canStartSession: () -> Bool
  private let wakeLease: PtpTetherWakeLease
  private let ptpEvents = PtpTetherEventForwarder()
  private var browser: ICDeviceBrowser?
  private var camera: ICCameraDevice?
  private var sessionId: String?
  private var uploadMode = "newShotsOnly"
  private var waitingStart: FlutterResult?
  private var eventSink: FlutterEventSink?
  private var eventSessionId: String?
  private let listenerLease = PtpTetherListenerLease(schedule: {
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: $0)
  })
  private var ready = false
  private var stopping = false
  private var deadline: DispatchWorkItem?
  private var scanTimer: Timer?
  private var seen: Set<String> = []
  private var pending: [String: ICCameraFile] = [:]
  private var queue: [String] = []
  private var staged: [String: URL] = [:]
  private var downloading: [String: FlutterResult] = [:]
  private var tetherMode = false
  private var tether: PtpTetherTransport?
  private let tetherStaging = PtpTetherStagingStore()
  private var cameraOpening = false
  private var cameraConnected = false
  private var release: PtpTetherSessionRelease?

  init(canStartSession: @escaping () -> Bool = { true },
       setSessionAwake: @escaping (String, Bool) -> Void = { _, _ in }) {
    self.canStartSession = canStartSession
    self.wakeLease = PtpTetherWakeLease(change: setSessionAwake)
    super.init()
  }

  var hasSession: Bool { sessionId != nil }
  var hasCameraOwner: Bool { cameraConnected || cameraOpening }

  func stopForBackground(result: @escaping FlutterResult) {
    guard let id = sessionId else { result(nil); return }
    if !stopping {
      emit("disconnected", message: "USB receiving paused while AirPix is in the background. Keep AirPix open and start again before shooting.",
           code: "CAMERA_APP_BACKGROUNDED")
    }
    stop(sessionID: id, result: result)
  }

  func refreshReleaseState() { release?.cameraStateChanged() }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    listenerLease.attach()
    eventSessionId = (arguments as? [String: Any])?["sessionId"] as? String
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    // Flutter cancels its event listener BEFORE calling stop(). Give the
    // explicit stop method time to await the actual camera close. A lost
    // listener is still cleaned up after a short grace period.
    let token = eventSessionId ?? sessionId
    eventSessionId = nil
    listenerLease.detach { [weak self] in
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

  func start(arguments: [String: Any]?, tether: Bool = false, result: @escaping FlutterResult) {
    assert(Thread.isMainThread)
    guard let id = arguments?["sessionId"] as? String, !id.isEmpty else {
      result(failure("LIVE_CAMERA_INVALID_SESSION", "A camera session ID is required."))
      return
    }
    // Also checked on orphan recovery, so a delayed close cannot reopen USB
    // after the app has already entered the background.
    guard canStartSession() else {
      result(failure("CAMERA_APP_BACKGROUNDED", "Keep AirPix open before starting USB camera receiving."))
      return
    }
    // A hot restart can install a new event listener before the old listener's
    // grace timer fires. Release that orphan instead of retaining a camera the
    // new Dart session cannot stop. Wait for actual native close confirmation.
    if let previous = sessionId, previous != id, eventSessionId == id {
      stop(sessionID: previous) { [weak self] outcome in
        guard let self else { return }
        if let error = outcome as? FlutterError { result(error); return }
        guard self.eventSessionId == id, self.eventSink != nil else {
          result(self.failure("LIVE_CAMERA_CANCELLED", "Camera receiving was cancelled.")); return
        }
        self.start(arguments: arguments, tether: tether, result: result)
      }
      return
    }
    guard sessionId == nil && !stopping else {
      result(failure("LIVE_CAMERA_BUSY", "A USB camera session is already running or closing."))
      return
    }
    sessionId = id
    wakeLease.hold(sessionID: id)
    tetherMode = tether
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
    newBrowser.requestContentsAuthorization { [weak self, weak newBrowser] status in
      DispatchQueue.main.async {
        guard let self = self, self.sessionId == id, self.browser === newBrowser, !self.stopping else { return }
        let access = WiredCameraAuthorizationState(status)
        guard access.allowsContentsAccess else {
          self.abort(access.errorCode ?? "CAMERA_AUTHORIZATION_UNAVAILABLE", access.message)
          return
        }
        let begin = { [weak self, weak newBrowser] in
          guard let self, self.sessionId == id, self.browser === newBrowser,
                !self.stopping else { return }
          newBrowser?.start()
          self.scheduleTimeout(for: id, seconds: 20, message: "No supported USB camera was detected. Check cable, adapter, and camera connection mode.")
        }
        if tether {
          newBrowser?.requestControlAuthorization { [weak self, weak newBrowser] controlStatus in
            DispatchQueue.main.async {
              guard let self, self.sessionId == id, self.browser === newBrowser,
                    !self.stopping else { return }
              let control = WiredCameraAuthorizationState(controlStatus)
              guard control.allowsContentsAccess else {
                self.abort(control.errorCode ?? "CAMERA_AUTHORIZATION_UNAVAILABLE",
                           control.message + " USB tethering requires external-camera control access.")
                return
              }
              begin()
            }
          }
        } else { begin() }
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

  private func abort(_ code: String, _ message: String, detected: ICCameraDevice? = nil) {
    emit("error", message: message, code: code)
    if tetherMode, let sony = detected ?? camera, sony.usbVendorID == 0x054C {
      // Preserve the camera's actual USB identity even when discovery rejects
      // Mass Storage before assigning/opening the device. Dart can then show
      // the exact Alpha model's PC Remote setup, not generic USB advice.
      let details: [String: Any] = [
        "camera": sony.name ?? "Sony camera",
        "vendorId": Int(sony.usbVendorID),
        "productId": Int(sony.usbProductID),
        "transport": sony.transportType ?? ""
      ]
      waitingStart?(FlutterError(code: code, message: message, details: details))
    } else {
      waitingStart?(failure(code, message))
    }
    waitingStart = nil
    stop(sessionID: sessionId, result: { _ in })
  }

  // The catalog must be complete before determining which images are old.
  private func markReady(_ device: ICCameraDevice) {
    if tetherMode { completeTetherOpen(device); return }
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
    guard !tetherMode, ready, let camera = camera, !stopping else { return }
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
    if let release {
      release.wait { outcome in
        switch outcome {
        case .success: result(nil)
        case .failure(let error): result(self.ptpError(error))
        }
      }
      return
    }
    guard sessionId != nil else { result(nil); return }
    stopping = true
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
    if let id = sessionId { ptpEvents.close(sessionID: id) }
    tether?.close()
    let old = camera
    let lease = PtpTetherSessionRelease(
      sessionID: sessionId!,
      state: { [weak self] in
        .init(connected: self?.cameraConnected == true,
              opening: self?.cameraOpening == true, open: old?.hasOpenSession == true)
      },
      requestClose: { completion in
        old?.requestCloseSession(options: nil) { error in
          DispatchQueue.main.async { completion(error) }
        }
      },
      onReleased: { [weak self] _ in self?.finishStop() }
    )
    release = lease
    let closingId = sessionId!
    lease.wait { [weak self] outcome in
      // Release wake ownership even when native close times out. A failed USB
      // release must not leave the iPhone's idle timer disabled indefinitely.
      self?.wakeLease.release(sessionID: closingId)
      switch outcome {
      case .success: result(nil)
      case .failure(let error): result(self?.ptpError(error))
      }
    }
    lease.begin()
  }

  private func finishStop() {
    if let id = sessionId { wakeLease.release(sessionID: id) }
    browser?.stop()
    browser?.delegate = nil
    browser = nil
    // Discard late SDK packets instead of restoring delegate event delivery.
    // Each subsequent owner installs its own handler, including catalog mode.
    camera?.ptpEventHandler = { _ in }
    camera?.delegate = nil
    camera = nil
    sessionId = nil
    ready = false
    cameraOpening = false
    cameraConnected = false
    tether = nil
    tetherMode = false
    seen.removeAll()
    pending.removeAll()
    queue.removeAll()
    staged.removeAll()
    release = nil
    stopping = false
  }

  private func ptpError(_ error: PtpTetherFailure) -> FlutterError {
    FlutterError(code: error.code, message: error.message, details: error.diagnostics)
  }

  private func completeTetherOpen(_ device: ICCameraDevice) {
    guard tetherMode, camera === device, device.hasOpenSession,
          !stopping, !ready else { return }
    guard device.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) else {
      // Capabilities can arrive after didOpenSession. The startup deadline
      // remains armed until capability/catalog callbacks confirm readiness.
      return
    }
    guard let id = sessionId else { return }
    tether = PtpTetherTransport(sessionID: id, camera: device, staging: tetherStaging) { [weak self] error in
      guard let self, self.sessionId == id, !self.stopping else { return }
      self.emit("disconnected", message: error.message, code: error.code)
      self.abort(error.code, error.message)
    }
    ready = true
    deadline?.cancel()
    deadline = nil
    let callback = waitingStart
    waitingStart = nil
    callback?([
      "sessionId": id, "cameraId": device.uuidString ?? device.name ?? "USB camera",
      "name": device.name ?? "USB camera", "vendorId": Int(device.usbVendorID),
      "productId": Int(device.usbProductID),
      "physicalShutter": device.capabilities.contains(
        ICDeviceCapability.cameraDeviceCanTakePictureUsingShutterReleaseOnCamera.rawValue
      ) ? "supported" : "unknown"
    ])
  }

  private func unsigned(_ value: Any?) -> UInt32? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue >= 0, number.doubleValue <= Double(UInt32.max),
          number.doubleValue == Double(number.uint32Value) else { return nil }
    return number.uint32Value
  }

  func handlePtp(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let id = args?["sessionId"] as? String
    if call.method == "openPtpTetherSession" {
      start(arguments: args, tether: true, result: result)
      return
    }
    if call.method == "closePtpTetherSession" {
      stop(sessionID: id, result: result)
      return
    }
    guard let id, !id.isEmpty else {
      result(failure("PTP_INVALID_ARGUMENT", "A camera session ID is required.")); return
    }
    if call.method == "acknowledgePtpTetherFiles" {
      let ids = args?["ids"] as? [String] ?? []
      if id == sessionId, let tether { tether.acknowledge(ids) }
      else { tetherStaging.acknowledge(sessionID: id, transferIDs: ids) }
      result(nil)
      return
    }
    if call.method == "downloadPtpTetherObject" {
      guard let transferID = args?["transferId"] as? String, !transferID.isEmpty,
            transferID.utf8.count <= 2048,
            let handle = unsigned(args?["handle"]), handle > 0,
            let size = unsigned(args?["expectedSize"]), size > 0,
            size <= UInt32(PtpTetherCodec.fileLimit), let name = args?["name"] as? String else {
        result(failure("PTP_INVALID_ARGUMENT", "Invalid photo transfer arguments.")); return
      }
      var partial: UInt16?
      if let value = args?["partialOpcode"] {
        guard let opcode = unsigned(value), opcode == 0x101B || opcode == 0x9107 else {
          result(failure("PTP_INVALID_ARGUMENT", "Invalid partial photo operation.")); return
        }
        partial = UInt16(opcode)
      }
      do {
        if let cached = try tetherStaging.lookup(sessionID: id, transferID: transferID,
             handle: handle, name: PtpTetherTransport.safeName(name), expectedSize: Int(size)) {
          result(["id": transferID, "path": cached.path, "name": cached.name, "size": cached.size]); return
        }
      } catch let error as PtpTetherFailure { result(ptpError(error)); return }
        catch { result(failure("PTP_STAGING_FAILED", error.localizedDescription)); return }
      guard id == sessionId, ready, !stopping, let tether else {
        result(failure("PTP_SESSION_CLOSED", "The camera session has ended.")); return
      }
      tether.downloadObject(handle: handle, name: name, expectedSize: Int(size),
        transferID: transferID, partialOpcode: partial) { [weak self] outcome in
          switch outcome {
          case .success(let file): result(["id": transferID, "path": file.path, "name": file.name, "size": file.size])
          case .failure(let error): result(self?.ptpError(error))
          }
        }
      return
    }
    guard id == sessionId, ready, !stopping, let tether else {
      result(failure("PTP_SESSION_CLOSED", "The camera session has ended.")); return
    }
    guard let opcode = unsigned(args?["opcode"]), opcode > 0, opcode <= UInt32(UInt16.max) else {
      result(failure("PTP_INVALID_ARGUMENT", "Invalid camera operation.")); return
    }
    let raw = args?["params"] as? [Any] ?? []
    let params = raw.compactMap(unsigned)
    guard raw.count <= 5, params.count == raw.count,
          args?["outData"] == nil || args?["outData"] is FlutterStandardTypedData else {
      result(failure("PTP_INVALID_ARGUMENT", "Invalid camera command data.")); return
    }
    tether.send(opcode: UInt16(opcode), parameters: params,
      outgoing: (args?["outData"] as? FlutterStandardTypedData)?.data) { [weak self] outcome in
        switch outcome {
        case .success(let reply):
          result(["responseCode": Int(reply.responseCode), "parameters": reply.parameters.map { Int64($0) },
                  "data": FlutterStandardTypedData(bytes: reply.data)])
        case .failure(let error): result(self?.ptpError(error))
        }
      }
  }

  // MARK: Camera discovery (runs only after the session start button)
  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    guard browser === self.browser, sessionId != nil, !stopping, camera == nil,
          let found = device as? ICCameraDevice else { return }
    let transport = (found.transportType ?? "").lowercased()
    if transport.contains("network") || transport.contains("wifi") ||
       transport.contains("wireless") || transport.contains("tcp") { return }
    if WiredCameraLiveTransportPolicy.isKnownImportOnly(found.transportType) {
      abort("CAMERA_STORAGE_ONLY", "Camera is exposing only USB storage. Disconnect and choose a shooting-compatible USB mode.", detected: found)
      return
    }
    camera = found
    cameraConnected = true
    cameraOpening = true
    found.delegate = self
    if let id = sessionId {
      // ImageCaptureCore calls this instead of its delegate PTP callback.
      // Capture the owner token and marshal notifications onto our main queue.
      found.ptpEventHandler = ptpEvents.handler(sessionID: id) { [weak self, weak found] data in
        guard let self, let found, self.sessionId == id,
              self.camera === found, !self.stopping else { return }
        if self.tetherMode {
          self.eventSink?(["sessionId": id, "type": "ptpEvent",
                           "data": FlutterStandardTypedData(bytes: data)])
        } else { self.scan() }
      }
    }
    if let id = sessionId {
      scheduleTimeout(for: id, seconds: 30, message: "Camera did not expose the required USB protocol. Check its tether / PC Remote mode and iPhone camera permissions.")
    }
    emit("status", message: "Found \(found.name ?? "USB camera"). Opening photo access.")
    found.requestOpenSession()
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    if device === camera {
      cameraConnected = false
      cameraOpening = false
      release?.cameraStateChanged()
    }
    if device === camera && !stopping {
      emit("disconnected", message: "Camera unplugged. Stop and restart receiving.", code: "USB_CAMERA_DISCONNECTED")
      abort("USB_CAMERA_DISCONNECTED", "The USB camera was disconnected.")
    }
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    guard device === camera else { return }
    cameraOpening = false
    if stopping { release?.cameraStateChanged(); return }
    if let error = error {
      abort("CAMERA_SESSION_FAILED", error.localizedDescription)
    } else {
      if tetherMode, let device = device as? ICCameraDevice { completeTetherOpen(device) }
      else { emit("status", message: "Reading camera photo catalog. Keep the camera powered on.") }
    }
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    guard device === camera else { return }
    if stopping { release?.nativeCloseCompleted(error) }
    else {
      emit("disconnected", message: "Camera closed its USB session.", code: "USB_CAMERA_DISCONNECTED")
      abort("USB_CAMERA_DISCONNECTED", "Camera closed its USB session.")
    }
  }
  func didRemove(_ device: ICDevice) {
    guard device === camera else { return }
    cameraConnected = false
    cameraOpening = false
    if stopping { release?.cameraStateChanged() }
    else {
      emit("disconnected", message: "USB camera disconnected.", code: "USB_CAMERA_DISCONNECTED")
      abort("USB_CAMERA_DISCONNECTED", "USB camera disconnected.")
    }
  }
  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    markReady(device)
    if tetherMode, camera === device, ready, !stopping {
      emit("catalogReady")
    }
  }

  private func catalogFiles(_ items: [ICCameraItem]) -> [ICCameraFile] {
    items.flatMap { item -> [ICCameraFile] in
      if let file = item as? ICCameraFile { return [file] }
      if let folder = item as? ICCameraFolder { return catalogFiles(folder.contents ?? []) }
      return []
    }
  }

  private func emitCatalogHint(_ file: ICCameraFile, removed: Bool = false) {
    guard let id = sessionId, file.ptpObjectHandle > 0 else { return }
    eventSink?(["sessionId": id, "type": removed ? "catalogRemoved" : "catalogHint",
                "handle": Int64(file.ptpObjectHandle),
                "name": file.originalFilename ?? file.name ?? "",
                "size": max(0, file.fileSize)])
  }

  func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
    guard camera === self.camera, ready, !stopping else { return }
    if tetherMode {
      catalogFiles(items).forEach { emitCatalogHint($0) }
      return
    }
    items.compactMap { $0 as? ICCameraFile }.forEach(observe)
  }

  func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
    guard camera === self.camera, tetherMode, ready, !stopping else { return }
    // Removal is a discovery hint, never an ACK. Dart retains any undelivered
    // shot and generations the handle if the camera reuses it for a new photo.
    catalogFiles(items).forEach { emitCatalogHint($0, removed: true) }
  }
  func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
  func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) { completeTetherOpen(camera) }
  func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
  func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
  func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
    guard camera === self.camera, !stopping, sessionId != nil else { return }
    // Events use the per-session handler above, including empty and
    // vendor-shaped packets. Never deliver the same event via two paths.
    if !tetherMode { scan() }
  }
  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
    guard device === camera, !stopping else { return }
    emit("disconnected", message: "Camera restricted USB access. Releasing the camera; check its shooting mode before reconnecting.",
         code: "TETHER_ACCESS_RESTRICTED")
    abort("TETHER_ACCESS_RESTRICTED", "Camera restricted USB access. The current session is being released.")
  }
  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) { scan() }
}
