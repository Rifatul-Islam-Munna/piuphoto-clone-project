import Flutter
import ImageCaptureCore
import Photos
import UIKit
import UniformTypeIdentifiers
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
  private enum PhotoAccessMode {
    case addOnly
    case readWrite
  }

  private let otgChannelName = "airpix/otg_picker"
  private let settingsChannelName = "airpix/device_settings"
  private let galleryChannelName = "airpix/gallery_import"
  private let downloadsChannelName = "airpix/image_downloads"
  private var otgResult: FlutterResult?
  private var otgSourceResult: FlutterResult?
  private var otgAllowsMultipleSelection = false
  private var otgSourceBookmark: Data?
  private let cameraBrowser = ICDeviceBrowser()
  // iOS has no public, general-purpose USB host inventory for arbitrary OTG
  // adapters. ImageCaptureCore can report compatible camera devices only.
  private let wiredVisibilityNote = "iPhone does not expose a list of arbitrary OTG cables, hubs or adapters to AirPix. This check uses ImageCaptureCore to detect supported cameras, not the adapter alone."
  private var connectedCameras: [ICCameraDevice] = []
  private var readyCameras: Set<ObjectIdentifier> = []
  private var cameraCatalogWaiters: [() -> Void] = []
  private var cameraDeviceWaiters: [() -> Void] = []
  private var cameraSessionRetries: [ObjectIdentifier: Int] = [:]
  private var cameraSessionErrors: [ObjectIdentifier: String] = [:]
  private var cameraAccessRestricted: Set<ObjectIdentifier> = []

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    cameraBrowser.delegate = self
    if #available(iOS 15.2, *) {
      cameraBrowser.browsedDeviceTypeMask = .camera
    }
    cameraBrowser.start()

    return didFinish
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // A camera may be attached while the app is inactive or before iOS
    // grants external-camera access; retry discovery when returning.
    if connectedCameras.isEmpty {
      cameraBrowser.stop()
      cameraBrowser.start()
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // With the UIScene lifecycle, `window` is nil during didFinishLaunching, so method
    // channels MUST be registered here or Dart gets MissingPluginException.
    registerNativeChannels(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerNativeChannels(messenger: FlutterBinaryMessenger) {
    let otgChannel = FlutterMethodChannel(
      name: otgChannelName,
      binaryMessenger: messenger
    )
    otgChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "pickImage", "pickImages":
        self.pickExternalImage(
          allowsMultipleSelection: call.method == "pickImages",
          result: result
        )
      case "connectedCameraDevices":
        self.listConnectedCameraDevices(result: result)
      case "cameraConnectionDiagnostics":
        self.cameraConnectionDiagnostics(result: result)
      case "connectedCameraImages":
        let arguments = call.arguments as? [String: Any]
        let limit = (arguments?["limit"] as? NSNumber)?.intValue
        self.listConnectedCameraImages(limit: limit, result: result)
      case "importConnectedCameraImages":
        let arguments = call.arguments as? [String: Any]
        let ids = arguments?["ids"] as? [String] ?? []
        self.importConnectedCameraImages(ids: ids, result: result)
      case "pickSource":
        self.pickExternalSource(result: result)
      case "recentSourceImages":
        let arguments = call.arguments as? [String: Any]
        let excludeIds = Set(arguments?["excludeIds"] as? [String] ?? [])
        self.fetchRecentSourceImages(excludeIds: excludeIds, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let settingsChannel = FlutterMethodChannel(
      name: settingsChannelName,
      binaryMessenger: messenger
    )
    settingsChannel.setMethodCallHandler { call, result in
      guard call.method == "openWifiSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }

      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(
          FlutterError(
            code: "OPEN_SETTINGS_FAILED",
            message: "Unable to create settings URL",
            details: nil
          )
        )
        return
      }

      UIApplication.shared.open(url) { success in
        if success {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "OPEN_SETTINGS_FAILED",
              message: "Unable to open settings",
              details: nil
            )
          )
        }
      }
    }

    let galleryChannel = FlutterMethodChannel(
      name: galleryChannelName,
      binaryMessenger: messenger
    )
    galleryChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleGalleryCall(call, result: result)
    }

    let downloadsChannel = FlutterMethodChannel(
      name: downloadsChannelName,
      binaryMessenger: messenger
    )
    downloadsChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleDownloadsCall(call, result: result)
    }
  }

  /// Finds the view controller to present pickers from. With UIScene, the
  /// AppDelegate's `window` is nil, so look it up through the connected scenes.
  private func topViewController() -> UIViewController? {
    let sceneWindows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    let fallbackWindow: UIWindow? = window
    let hostWindow = sceneWindows.first(where: { $0.isKeyWindow }) ?? sceneWindows.first ?? fallbackWindow
    var top = hostWindow?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }

  private func handleGalleryCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "recentImages":
      let arguments = call.arguments as? [String: Any]
      let sinceMs = (arguments?["sinceMs"] as? NSNumber)?.doubleValue ?? 0
      let excludeIds = Set(arguments?["excludeIds"] as? [String] ?? [])
      fetchRecentImages(sinceMs: sinceMs, excludeIds: excludeIds, result: result)
    case "deleteImage":
      let arguments = call.arguments as? [String: Any]
      guard let id = arguments?["id"] as? String, !id.isEmpty else {
        result(FlutterError(code: "INVALID_ID", message: "Image id is required", details: nil))
        return
      }
      deleteGalleryImage(id: id, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleDownloadsCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "saveImage" else {
      result(FlutterMethodNotImplemented)
      return
    }

    let arguments = call.arguments as? [String: Any]
    guard
      let typedBytes = arguments?["bytes"] as? FlutterStandardTypedData
    else {
      result(
        FlutterError(code: "INVALID_BYTES", message: "Image bytes are required", details: nil)
      )
      return
    }

    let filename = arguments?["filename"] as? String ?? "event-image.jpg"
    saveImageToLibrary(bytes: typedBytes.data, filename: filename, result: result)
  }

  private func cameraFileId(_ camera: ICCameraDevice, _ file: ICCameraFile) -> String {
    let deviceId = camera.uuidString ?? camera.name ?? "camera"
    return "\(deviceId)|\(file.ptpObjectHandle)"
  }

  private func isCameraImageFile(_ file: ICCameraFile) -> Bool {
    let filename = (file.originalFilename ?? file.name ?? "").lowercased()
    let extensions: Set<String> = [
      "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "tif", "tiff",
      "dng", "arw", "cr2", "cr3", "nef", "nrw", "raf", "rw2", "orf", "pef",
    ]
    guard let ext = filename.split(separator: ".").last else { return false }
    return extensions.contains(String(ext))
  }

  private func isCameraCatalogReady(_ camera: ICCameraDevice) -> Bool {
    readyCameras.contains(ObjectIdentifier(camera)) || camera.contentCatalogPercentCompleted >= 100
  }

  private func isClearlyWirelessCamera(_ camera: ICCameraDevice) -> Bool {
    let transport = (camera.transportType ?? "").lowercased()
    return transport.contains("tcp") || transport.contains("bonjour") ||
      transport.contains("bluetooth") || transport.contains("wifi") ||
      transport.contains("proximity")
  }

  private func hasWiredCameraEvidence(_ camera: ICCameraDevice) -> Bool {
    let transport = (camera.transportType ?? "").lowercased()
    return transport.contains("usb") || transport.contains("massstorage") ||
      camera.usbVendorID != 0 || camera.usbProductID != 0
  }

  private func allCameraFiles() -> [(ICCameraDevice, ICCameraFile)] {
    var files: [(ICCameraDevice, ICCameraFile)] = []
    for camera in connectedCameras {
      for item in camera.mediaFiles ?? [] {
        if let file = item as? ICCameraFile, isCameraImageFile(file) {
          files.append((camera, file))
        }
      }
    }
    return files.sorted {
      ($0.1.fileCreationDate ?? .distantPast) > ($1.1.fileCreationDate ?? .distantPast)
    }
  }

  private func listConnectedCameraDevices(result: @escaping FlutterResult) {
    ensureCameraContentsAccess { [weak self] granted in
      guard let self else { return }
      guard granted else {
        result(FlutterError(
          code: "CAMERA_ACCESS_DENIED",
          message: "Permission to read the connected camera was denied",
          details: nil
        ))
        return
      }
      self.waitForCameraDevice(timeout: 6) { [weak self] in
        guard let self else { return }
        result(self.connectedCameras.enumerated().map { index, camera in
          let id = camera.uuidString ?? "camera-\(index)"
          let name = camera.name ?? "Connected camera"
          return [
            "id": id,
            "name": name,
            "hasPermission": true,
            "directSupported": true,
          ] as [String: Any]
        })
      }
    }
  }

  /// Returns the actual iOS PTP transport state, without opening Photos/Files.
  private func cameraConnectionDiagnostics(result: @escaping FlutterResult) {
    ensureCameraContentsAccess { [weak self] granted in
      guard let self else { return }
      guard granted else {
        result([
          "status": "permission-denied",
          "message": "External camera access is blocked. Check AirPix permissions in iPhone Settings.",
          "cameras": [] as [[String: Any]],
          "totalImages": 0,
          "usbEnumerationAvailable": false,
          "connectionNote": self.wiredVisibilityNote,
        ] as [String: Any])
        return
      }

      self.waitForCameraDevice(timeout: 6) { [weak self] in
        guard let self else { return }
        guard !self.connectedCameras.isEmpty else {
          result([
            "status": "no-camera",
            "message": "No USB/PTP camera found. Check the data cable, iPhone adapter and camera USB transfer mode.",
            "cameras": [] as [[String: Any]],
            "totalImages": 0,
            "usbEnumerationAvailable": false,
            "connectionNote": self.wiredVisibilityNote,
          ] as [String: Any])
          return
        }

        self.waitForCameraCatalog(timeout: 12) { [weak self] in
          guard let self else { return }
          let cameras: [[String: Any]] = self.connectedCameras.map { camera in
            [
              "name": camera.name ?? "Connected camera",
              "id": camera.uuidString ?? "camera",
              "sessionOpen": camera.hasOpenSession,
              "catalogReady": self.isCameraCatalogReady(camera),
              "catalogProgress": camera.contentCatalogPercentCompleted,
              "sessionError": self.cameraSessionErrors[ObjectIdentifier(camera)] ?? "",
              "transportType": camera.transportType ?? "unknown",
              "usbVendorId": Int(camera.usbVendorID),
              "usbProductId": Int(camera.usbProductID),
              "wiredConfirmed": self.hasWiredCameraEvidence(camera),
              "imageCount": (camera.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
                .filter { self.isCameraImageFile($0) }.count,
            ] as [String: Any]
          }
          let ready = !cameras.isEmpty && cameras.allSatisfy { $0["catalogReady"] as? Bool == true }
          let anySessionOpen = self.connectedCameras.contains { $0.hasOpenSession }
          let locked = self.connectedCameras.contains {
            self.cameraAccessRestricted.contains(ObjectIdentifier($0))
          }
          let sessionIssue = self.connectedCameras.compactMap {
            self.cameraSessionErrors[ObjectIdentifier($0)]
          }.first
          let count = cameras.reduce(0) { $0 + ($1["imageCount"] as? Int ?? 0) }
          let message: String
          let status: String
          if cameras.isEmpty {
            status = "no-camera"
            message = "The USB camera disconnected during scanning. Reconnect and retry."
          } else if locked {
            status = "camera-locked"
            message = "The connected camera or device is locked and has not allowed access to its photos. Unlock it and approve access on the device, then retry."
          } else if !anySessionOpen {
            status = "session-failed"
            message = "Camera detected, but iOS could not open its USB photo-transfer session. \(sessionIssue ?? "Check camera PTP mode, cable, power and whether another app is using it.")"
          } else if !ready && count == 0 {
            status = "catalog-loading"
            message = "USB session opened, but the camera has not finished listing photos. Keep it awake and retry."
          } else if count == 0 {
            status = "empty-media"
            message = "Camera connected, but no supported image files were found. Check its memory card and photo-transfer mode."
          } else {
            status = "ready"
            message = "Camera connection ready. \(count) image(s) available for direct import."
          }
          result([
            "status": status,
            "message": message,
            "cameras": cameras,
            "totalImages": count,
            "usbEnumerationAvailable": false,
            "connectionNote": self.wiredVisibilityNote,
          ] as [String: Any])
        }
      }
    }
  }

  private func listConnectedCameraImages(limit: Int?, result: @escaping FlutterResult) {
    ensureCameraContentsAccess { [weak self] granted in
      guard let self else { return }
      guard granted else {
        result(
          FlutterError(
            code: "CAMERA_ACCESS_DENIED",
            message: "Connected camera access was denied",
            details: nil
          )
        )
        return
      }

      self.waitForCameraDevice(timeout: 6) { [weak self] in
        guard let self else { return }
        guard !self.connectedCameras.isEmpty else {
          result(FlutterError(
            code: "NO_CAMERA_CONNECTED",
            message: "No USB/PTP camera detected. Check cable, adapter and USB mode.",
            details: nil
          ))
          return
        }
        // The app shows a cancellable loading screen, so allow big memory cards time.
        self.waitForCameraCatalog(timeout: 25) { [weak self] in
          guard let self else { return }
          guard !self.connectedCameras.isEmpty else {
            result(FlutterError(
              code: "NO_CAMERA_CONNECTED",
              message: "USB camera disconnected during scanning.",
              details: nil
            ))
            return
          }
          let allFiles = self.allCameraFiles()
          if self.connectedCameras.contains(where: {
            self.cameraAccessRestricted.contains(ObjectIdentifier($0))
          }) {
            result(FlutterError(
              code: "CAMERA_DEVICE_LOCKED",
              message: "The connected camera/device is locked. Unlock it and approve photo access, then retry.",
              details: nil
            ))
            return
          }
          if !self.connectedCameras.contains(where: { $0.hasOpenSession }) {
            let reason = self.connectedCameras.compactMap {
              self.cameraSessionErrors[ObjectIdentifier($0)]
            }.first ?? "Camera refused to open a USB photo-transfer session."
            result(FlutterError(
              code: "CAMERA_SESSION_FAILED",
              message: "\(reason) Check PTP mode, cable/adapter and camera power.",
              details: nil
            ))
            return
          }
          if allFiles.isEmpty && self.connectedCameras.contains(where: {
            !self.isCameraCatalogReady($0)
          }) {
            result(FlutterError(
              code: "CAMERA_CATALOG_LOADING",
              message: "Camera detected, but its photos have not finished loading. Keep the camera on and try again.",
              details: nil
            ))
            return
          }
          let files: ArraySlice<(ICCameraDevice, ICCameraFile)>
          if let limit, limit > 0 {
            files = allFiles.prefix(limit)
          } else {
            files = allFiles[allFiles.startIndex..<allFiles.endIndex]
          }
          result(files.map { camera, file in
            [
              "id": self.cameraFileId(camera, file),
              "name": file.originalFilename ?? file.name ?? "camera-image.jpg",
              "size": String(file.fileSize),
            ]
          })
        }
      }
    }
  }

  /// A camera plugged in moments ago (or before permission was granted) may not be
  /// reported yet. Re-scan and wait briefly for one to appear.
  private func waitForCameraDevice(timeout: TimeInterval, _ completion: @escaping () -> Void) {
    if !connectedCameras.isEmpty {
      completion()
      return
    }

    cameraBrowser.stop()
    cameraBrowser.start()

    var finished = false
    let finish: () -> Void = {
      if finished { return }
      finished = true
      completion()
    }
    cameraDeviceWaiters.append(finish)
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
  }

  /// iOS requires explicit permission before an app can read a USB camera's files.
  /// Only an explicit denial blocks; other states still attempt the read.
  private func ensureCameraContentsAccess(_ completion: @escaping (Bool) -> Void) {
    if #available(iOS 14.0, *) {
      let current = cameraBrowser.contentsAuthorizationStatus
      if current == .authorized {
        completion(true)
        return
      }
      if current == .denied || current == .restricted {
        completion(false)
        return
      }
      cameraBrowser.requestContentsAuthorization { status in
        DispatchQueue.main.async {
          completion(status == .authorized)
        }
      }
      return
    }
    completion(true)
  }

  /// A freshly plugged-in camera reports no files until its catalog is loaded.
  /// Wait (bounded) for every connected camera to become ready.
  private func waitForCameraCatalog(timeout: TimeInterval, _ completion: @escaping () -> Void) {
    let notReady = connectedCameras.filter { !isCameraCatalogReady($0) }
    if notReady.isEmpty {
      completion()
      return
    }

    for camera in notReady where !camera.hasOpenSession {
      camera.requestOpenSession()
    }

    var finished = false
    let finish: () -> Void = {
      if finished { return }
      finished = true
      completion()
    }
    cameraCatalogWaiters.append(finish)
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
  }

  private func flushCameraCatalogWaitersIfReady() {
    let allReady = connectedCameras.allSatisfy { isCameraCatalogReady($0) }
    guard allReady, !cameraCatalogWaiters.isEmpty else { return }
    let waiters = cameraCatalogWaiters
    cameraCatalogWaiters.removeAll()
    waiters.forEach { $0() }
  }

  private func importConnectedCameraImages(ids: [String], result: @escaping FlutterResult) {
    let wanted = Set(ids)
    guard !wanted.isEmpty else { result([]); return }
    let files = allCameraFiles().filter { wanted.contains(cameraFileId($0.0, $0.1)) }
    guard !files.isEmpty else {
      result(FlutterError(
        code: "CAMERA_FILES_MISSING",
        message: "The selected photos are no longer available on the USB camera. Reconnect it, refresh the photo list and retry.",
        details: nil
      ))
      return
    }
    // PTP cameras commonly support only one data transfer at a time.
    // Serial downloads also avoid exhausting memory on large RAW batches.
    downloadCameraFiles(files, at: 0, downloaded: [], result: result)
  }

  private func downloadCameraFiles(
    _ files: [(ICCameraDevice, ICCameraFile)],
    at index: Int,
    downloaded: [[String: String]],
    failures: [String] = [],
    result: @escaping FlutterResult
  ) {
    guard index < files.count else {
      if downloaded.isEmpty && !failures.isEmpty {
        result(FlutterError(
          code: "CAMERA_IMPORT_FAILED",
          message: "Camera photo transfer failed: \(failures.first ?? "Unknown error"). Check the cable, camera power, available iPhone storage and camera USB mode.",
          details: ["failedCount": failures.count]
        ))
      } else {
        result(downloaded)
      }
      return
    }

    let (camera, file) = files[index]
    let imageId = cameraFileId(camera, file)
    let filename = sanitizeFilename(file.originalFilename ?? file.name ?? "camera-image.jpg")
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("camera_import", isDirectory: true)
      .appendingPathComponent(sanitizeFilename(imageId), isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      NSLog("[AirPix USB] Unable to create import folder for %@: %@", filename, String(describing: error))
      downloadCameraFiles(files, at: index + 1, downloaded: downloaded,
                          failures: failures + ["Unable to create the download folder: \(error.localizedDescription)"], result: result)
      return
    }

    let options: [ICDownloadOption: Any] = [
      .downloadsDirectoryURL: directory,
      .saveAsFilename: filename,
      .overwrite: true,
    ]
    file.requestDownload(options: options) { [weak self] path, error in
      DispatchQueue.main.async {
        guard let self else {
          result(downloaded)
          return
        }
        var updated = downloaded
        var updatedFailures = failures
        if let error {
          NSLog("[AirPix USB] Camera download failed for %@: %@", filename, String(describing: error))
          updatedFailures.append("\(filename): \(error.localizedDescription)")
        } else {
          // ImageCaptureCore may supply an absolute path, a file URL, or a filename.
          let returnedURL = path.flatMap { URL(string: $0) }
          let resolvedPath: String = returnedURL?.isFileURL == true
            ? (returnedURL?.path ?? "")
            : (path?.hasPrefix("/") == true ? path! : directory.appendingPathComponent(path ?? filename).path)
          let fallback = directory.appendingPathComponent(filename).path
          let existing = [resolvedPath, fallback].first {
            !$0.isEmpty && FileManager.default.fileExists(atPath: $0)
          }
          if let existing {
            updated.append(["id": imageId, "path": existing, "name": filename])
          } else {
            NSLog("[AirPix USB] Camera download returned no file for %@ (path: %@)", filename, path ?? "nil")
            updatedFailures.append("\(filename): no downloaded file was saved")
          }
        }
        self.downloadCameraFiles(files, at: index + 1, downloaded: updated,
                                 failures: updatedFailures, result: result)
      }
    }
  }

  private func pickExternalImage(
    allowsMultipleSelection: Bool,
    result: @escaping FlutterResult
  ) {
    if otgResult != nil {
      result(
        FlutterError(
          code: "PICK_IN_PROGRESS",
          message: "A file picker is already open",
          details: nil
        )
      )
      return
    }

    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "NO_PRESENTER",
          message: "Unable to open the file picker",
          details: nil
        )
      )
      return
    }

    otgResult = result
    otgAllowsMultipleSelection = allowsMultipleSelection
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.image"], in: .import)
    }
    picker.delegate = self
    picker.allowsMultipleSelection = allowsMultipleSelection
    presenter.present(picker, animated: true)
  }

  private func pickExternalSource(result: @escaping FlutterResult) {
    if otgSourceResult != nil {
      result(
        FlutterError(
          code: "PICK_IN_PROGRESS",
          message: "A source picker is already open",
          details: nil
        )
      )
      return
    }

    guard let presenter = topViewController() else {
      result(
        FlutterError(
          code: "NO_PRESENTER",
          message: "Unable to open the folder picker",
          details: nil
        )
      )
      return
    }

    otgSourceResult = result
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
    }
    picker.delegate = self
    picker.allowsMultipleSelection = false
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard !urls.isEmpty else {
      otgResult?(nil)
      otgResult = nil
      otgAllowsMultipleSelection = false
      otgSourceResult?(nil)
      otgSourceResult = nil
      return
    }

    if let sourceResult = otgSourceResult {
      otgSourceResult = nil
      let url = urls[0]
      do {
        let bookmark = try url.bookmarkData(
          options: .minimalBookmark,
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        otgSourceBookmark = bookmark
        sourceResult([
          "id": url.absoluteString,
          "name": url.lastPathComponent.isEmpty ? "OTG source" : url.lastPathComponent,
        ])
      } catch {
        sourceResult(
          FlutterError(code: "PICK_FAILED", message: error.localizedDescription, details: nil)
        )
      }
      return
    }

    guard let result = otgResult else { return }
    otgResult = nil
    let allowsMultipleSelection = otgAllowsMultipleSelection
    otgAllowsMultipleSelection = false

    do {
      let payloads = try urls.map { url in
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
          if didAccess {
            url.stopAccessingSecurityScopedResource()
          }
        }

        let fileName = url.lastPathComponent.isEmpty ? "external-image.jpg" : url.lastPathComponent
        let target = FileManager.default.temporaryDirectory
          .appendingPathComponent("otg_\(Int(Date().timeIntervalSince1970 * 1000))_\(fileName)")

        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }

        try FileManager.default.copyItem(at: url, to: target)
        return [
          "path": target.path,
          "name": fileName,
        ]
      }

      if allowsMultipleSelection {
        result(payloads)
      } else {
        result(payloads.first)
      }
    } catch {
      result(FlutterError(code: "PICK_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    otgResult?(nil)
    otgResult = nil
    otgAllowsMultipleSelection = false
    otgSourceResult?(nil)
    otgSourceResult = nil
  }

  private func fetchRecentSourceImages(
    excludeIds: Set<String>,
    result: @escaping FlutterResult
  ) {
    guard let bookmark = otgSourceBookmark else {
      result([])
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      var stale = false

      do {
        let url = try URL(
          resolvingBookmarkData: bookmark,
          options: [.withoutUI],
          relativeTo: nil,
          bookmarkDataIsStale: &stale
        )
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
          if didAccess {
            url.stopAccessingSecurityScopedResource()
          }
        }

        let files = self.copyRecentImagesFromFolder(url: url, excludeIds: excludeIds)
        DispatchQueue.main.async {
          result(files)
        }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "SOURCE_READ_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func copyRecentImagesFromFolder(
    url: URL,
    excludeIds: Set<String>
  ) -> [[String: String]] {
    var keys: [URLResourceKey] = [
      .isRegularFileKey,
      .isDirectoryKey,
      .nameKey,
      .fileSizeKey,
      .contentModificationDateKey,
    ]
    if #available(iOS 14.0, *) {
      keys.append(.contentTypeKey)
    }
    guard let enumerator = FileManager.default.enumerator(
      at: url,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var copied: [[String: String]] = []
    for case let fileURL as URL in enumerator {
      if copied.count >= 10 {
        break
      }

      guard
        let values = try? fileURL.resourceValues(forKeys: Set(keys)),
        values.isDirectory != true,
        values.isRegularFile == true
      else {
        continue
      }

      let isImage: Bool
      if #available(iOS 14.0, *) {
        isImage = values.contentType?.conforms(to: .image) == true
      } else {
        let ext = fileURL.pathExtension.lowercased()
        isImage = ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext)
      }
      if !isImage {
        continue
      }

      let modified = Int((values.contentModificationDate ?? .distantPast).timeIntervalSince1970)
      let size = values.fileSize ?? 0
      let id = "\(fileURL.absoluteString)|\(modified)|\(size)"
      if excludeIds.contains(id) {
        continue
      }

      let rawName = values.name ?? fileURL.lastPathComponent
      let safeName = sanitizeFilename(rawName)
      let target = FileManager.default.temporaryDirectory
        .appendingPathComponent("otg_auto_\(Int(Date().timeIntervalSince1970 * 1000))_\(safeName)")

      do {
        if FileManager.default.fileExists(atPath: target.path) {
          try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: fileURL, to: target)
        copied.append([
          "id": id,
          "path": target.path,
          "name": safeName,
          "modifiedMs": "\(modified)",
        ])
      } catch {
        continue
      }
    }

    return copied.sorted {
      (Int($0["modifiedMs"] ?? "0") ?? 0) > (Int($1["modifiedMs"] ?? "0") ?? 0)
    }
  }

  private func fetchRecentImages(
    sinceMs: Double,
    excludeIds: Set<String>,
    result: @escaping FlutterResult
  ) {
    requestPhotoAccess(mode: .readWrite) { [weak self] granted in
      guard let self else { return }
      guard granted else {
        result(
          FlutterError(
            code: "PHOTO_ACCESS_DENIED",
            message: "Photo library access is required",
            details: nil
          )
        )
        return
      }

      DispatchQueue.global(qos: .userInitiated).async {
        let options = PHFetchOptions()
        options.sortDescriptors = [
          NSSortDescriptor(key: "creationDate", ascending: false),
        ]
        let sinceDate = Date(timeIntervalSince1970: sinceMs / 1000)
        options.predicate = NSPredicate(
          format: "mediaType == %d AND creationDate >= %@",
          PHAssetMediaType.image.rawValue,
          sinceDate as NSDate
        )

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        var copied: [[String: String]] = []
        let group = DispatchGroup()

        assets.enumerateObjects { asset, _, stop in
          if copied.count >= 10 {
            stop.pointee = true
            return
          }

          let identifier = asset.localIdentifier
          if excludeIds.contains(identifier) {
            return
          }

          group.enter()
          self.copyAssetToTemporaryDirectory(asset: asset) { payload in
            if let payload {
              copied.append(payload)
            }
            group.leave()
          }
        }

        group.wait()
        DispatchQueue.main.async {
          result(copied)
        }
      }
    }
  }

  private func copyAssetToTemporaryDirectory(
    asset: PHAsset,
    completion: @escaping ([String: String]?) -> Void
  ) {
    let resources = PHAssetResource.assetResources(for: asset)
    guard let resource = resources.first(where: {
      $0.type == .photo || $0.type == .fullSizePhoto
    }) ?? resources.first else {
      completion(nil)
      return
    }

    let rawName = resource.originalFilename.isEmpty
      ? "gallery-image-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
      : resource.originalFilename
    let safeName = sanitizeFilename(rawName)
    let target = FileManager.default.temporaryDirectory
      .appendingPathComponent("gallery_\(Int(Date().timeIntervalSince1970 * 1000))_\(safeName)")

    if FileManager.default.fileExists(atPath: target.path) {
      try? FileManager.default.removeItem(at: target)
    }

    PHAssetResourceManager.default().writeData(for: resource, toFile: target, options: nil) { error in
      guard error == nil else {
        completion(nil)
        return
      }

      completion([
        "id": asset.localIdentifier,
        "path": target.path,
        "name": safeName,
      ])
    }
  }

  private func deleteGalleryImage(id: String, result: @escaping FlutterResult) {
    requestPhotoAccess(mode: .readWrite) { granted in
      guard granted else {
        result(
          FlutterError(
            code: "PHOTO_ACCESS_DENIED",
            message: "Photo library access is required",
            details: nil
          )
        )
        return
      }

      let assets = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil)
      guard let asset = assets.firstObject else {
        result(false)
        return
      }

      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.deleteAssets([asset] as NSArray)
      }) { success, error in
        DispatchQueue.main.async {
          if let error {
            result(
              FlutterError(code: "DELETE_FAILED", message: error.localizedDescription, details: nil)
            )
          } else {
            result(success)
          }
        }
      }
    }
  }

  private func saveImageToLibrary(bytes: Data, filename: String, result: @escaping FlutterResult) {
    requestPhotoAccess(mode: .addOnly) { granted in
      guard granted else {
        result(
          FlutterError(
            code: "PHOTO_ACCESS_DENIED",
            message: "Photo library add access is required",
            details: nil
          )
        )
        return
      }

      PHPhotoLibrary.shared().performChanges({
        let request = PHAssetCreationRequest.forAsset()
        let options = PHAssetResourceCreationOptions()
        options.originalFilename = self.sanitizeFilename(filename)
        request.addResource(with: .photo, data: bytes, options: options)
      }) { success, error in
        DispatchQueue.main.async {
          if let error {
            result(
              FlutterError(code: "SAVE_FAILED", message: error.localizedDescription, details: nil)
            )
          } else {
            result(success)
          }
        }
      }
    }
  }

  private func requestPhotoAccess(
    mode: PhotoAccessMode,
    completion: @escaping (Bool) -> Void
  ) {
    let resolvedCompletion: (PHAuthorizationStatus) -> Void = { status in
      let granted: Bool
      switch status {
      case .authorized, .limited:
        granted = true
      default:
        granted = false
      }

      DispatchQueue.main.async {
        completion(granted)
      }
    }

    if #available(iOS 14, *) {
      let level: PHAccessLevel = mode == .addOnly ? .addOnly : .readWrite
      let status = PHPhotoLibrary.authorizationStatus(for: level)
      switch status {
      case .authorized, .limited:
        completion(true)
      case .notDetermined:
        PHPhotoLibrary.requestAuthorization(for: level, handler: resolvedCompletion)
      default:
        completion(false)
      }
      return
    }

    let status = PHPhotoLibrary.authorizationStatus()
    switch status {
    case .authorized:
      completion(true)
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization(resolvedCompletion)
    default:
      completion(false)
    }
  }

  private func sanitizeFilename(_ value: String) -> String {
    let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let parts = value.components(separatedBy: invalidCharacters)
    let cleaned = parts.joined(separator: "-").trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? "event-image.jpg" : cleaned
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
    guard let camera = device as? ICCameraDevice else { return }
    // Do not confuse an ImageCaptureCore network camera with USB/OTG.
    if isClearlyWirelessCamera(camera) {
      NSLog("[AirPix USB] Ignoring wireless camera in wired-only browser: %@ (%@)",
            camera.name ?? "Camera", camera.transportType ?? "unknown")
      return
    }
    DispatchQueue.main.async {
      if !self.connectedCameras.contains(where: { $0 === camera }) {
        self.connectedCameras.append(camera)
        NSLog("[AirPix USB] Detected camera: %@", camera.name ?? "Unnamed USB camera")
      }
      camera.delegate = self
      if !camera.hasOpenSession {
        camera.requestOpenSession()
      }

      let waiters = self.cameraDeviceWaiters
      self.cameraDeviceWaiters.removeAll()
      waiters.forEach { $0() }
    }
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    forgetCamera(device)
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    let key = ObjectIdentifier(device)
    guard let error else {
      NSLog("[AirPix USB] Opened camera session: %@", device.name ?? "Camera")
      DispatchQueue.main.async {
        self.cameraSessionRetries[key] = nil
        self.cameraSessionErrors[key] = nil
      }
      return
    }
    NSLog("[AirPix USB] Failed to open session for %@: %@", device.name ?? "Camera", String(describing: error))
    DispatchQueue.main.async {
      self.cameraSessionErrors[key] = error.localizedDescription
    }
    // Cameras that are waking up or busy often refuse the first session; retry a few times.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
      let attempts = self.cameraSessionRetries[key] ?? 0
      guard attempts < 3,
            self.connectedCameras.contains(where: { $0 === device }),
            !device.hasOpenSession
      else { return }
      self.cameraSessionRetries[key] = attempts + 1
      device.requestOpenSession()
    }
  }
  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
  func didRemove(_ device: ICDevice) {
    forgetCamera(device)
  }

  private func forgetCamera(_ device: ICDevice) {
    DispatchQueue.main.async {
      self.connectedCameras.removeAll { $0 === device }
      self.readyCameras.remove(ObjectIdentifier(device))
      self.cameraSessionRetries[ObjectIdentifier(device)] = nil
      self.cameraSessionErrors[ObjectIdentifier(device)] = nil
      self.cameraAccessRestricted.remove(ObjectIdentifier(device))
      self.flushCameraCatalogWaitersIfReady()
    }
  }

  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    DispatchQueue.main.async {
      NSLog("[AirPix USB] Catalog ready: %@; media items: %d",
            device.name ?? "Camera", device.mediaFiles?.count ?? 0)
      self.readyCameras.insert(ObjectIdentifier(device))
      self.flushCameraCatalogWaitersIfReady()
    }
  }

  func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}

  func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}

  func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}

  func cameraDevice(
    _ camera: ICCameraDevice,
    didReceiveMetadata metadata: [AnyHashable: Any]?,
    for item: ICCameraItem,
    error: Error?
  ) {}

  func cameraDevice(
    _ camera: ICCameraDevice,
    didReceiveThumbnail thumbnail: CGImage?,
    for item: ICCameraItem,
    error: Error?
  ) {}

  func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}

  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
    DispatchQueue.main.async {
      self.cameraAccessRestricted.insert(ObjectIdentifier(device))
      NSLog("[AirPix USB] Photo access restricted by connected device: %@", device.name ?? "Camera")
    }
  }

  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
    DispatchQueue.main.async {
      self.cameraAccessRestricted.remove(ObjectIdentifier(device))
      NSLog("[AirPix USB] Photo access restriction cleared: %@", device.name ?? "Camera")
    }
  }

  func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
}
