import Flutter
import Photos
import UIKit
import UniformTypeIdentifiers

// Direct USB camera receiving is deliberately opt-in and isolated in
// SimpleUsbCameraReceiver. App launch never browses or opens cameras.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
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
  private var screenAwakeOwners: Set<String> = []
  private var previousScreenIdleTimerDisabled: Bool?
  private let cameraReceiver = SimpleUsbCameraReceiver()

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerNativeChannels(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func registerNativeChannels(messenger: FlutterBinaryMessenger) {
    FlutterEventChannel(name: "airpix/otg_live", binaryMessenger: messenger)
      .setStreamHandler(cameraReceiver)
    let otgChannel = FlutterMethodChannel(name: otgChannelName, binaryMessenger: messenger)
    otgChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "pickImage", "pickImages":
        self.pickExternalImage(allowsMultipleSelection: call.method == "pickImages", result: result)
      case "pickSource":
        self.pickExternalSource(result: result)
      case "recentSourceImages":
        let arguments = call.arguments as? [String: Any]
        let excludeIds = Set(arguments?["excludeIds"] as? [String] ?? [])
        self.fetchRecentSourceImages(excludeIds: excludeIds, result: result)
      case "setTransferScreenAwake":
        let arguments = call.arguments as? [String: Any]
        guard let owner = arguments?["owner"] as? String, !owner.isEmpty else {
          result(FlutterError(code: "INVALID_OWNER", message: "A transfer owner is required.", details: nil))
          return
        }
        self.setScreenAwake(owner: owner, enabled: arguments?["enabled"] as? Bool == true)
        result(nil)
      case "startLiveCameraSession":
        self.cameraReceiver.start(arguments: call.arguments as? [String: Any], result: result)
      case "stopLiveCameraSession":
        let arguments = call.arguments as? [String: Any]
        self.cameraReceiver.stop(sessionID: arguments?["sessionId"] as? String, result: result)
      case "pendingLiveCameraImages":
        let arguments = call.arguments as? [String: Any]
        self.cameraReceiver.pendingImages(sessionID: arguments?["sessionId"] as? String, result: result)
      case "downloadLiveCameraImage":
        let arguments = call.arguments as? [String: Any]
        self.cameraReceiver.download(sessionID: arguments?["sessionId"] as? String,
                                     imageID: arguments?["id"] as? String, result: result)
      case "acknowledgeLiveCameraImages":
        let arguments = call.arguments as? [String: Any]
        self.cameraReceiver.acknowledge(sessionID: arguments?["sessionId"] as? String,
                                        ids: arguments?["ids"] as? [String] ?? [], result: result)
      case "connectedCameraDevices":
        result([])
      case "cameraConnectionDiagnostics", "connectedCameraImages", "importConnectedCameraImages",
           "releaseCameraImportSession", "useUsbDeviceAsCamera", "openPtpTetherSession",
           "sendPtpTetherCommand", "downloadPtpTetherObject", "acknowledgePtpTetherFiles",
           "closePtpTetherSession":
        result(FlutterError(code: "USE_START_RECEIVING",
                            message: "Camera discovery starts only with Connect & start.",
                            details: nil))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let settingsChannel = FlutterMethodChannel(name: settingsChannelName, binaryMessenger: messenger)
    settingsChannel.setMethodCallHandler { call, result in
      guard call.method == "openWifiSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(FlutterError(code: "OPEN_SETTINGS_FAILED", message: "Unable to create settings URL", details: nil))
        return
      }
      UIApplication.shared.open(url) { success in
        if success { result(nil) }
        else { result(FlutterError(code: "OPEN_SETTINGS_FAILED", message: "Unable to open settings", details: nil)) }
      }
    }

    let galleryChannel = FlutterMethodChannel(name: galleryChannelName, binaryMessenger: messenger)
    galleryChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleGalleryCall(call, result: result)
    }

    let downloadsChannel = FlutterMethodChannel(name: downloadsChannelName, binaryMessenger: messenger)
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
  private func setScreenAwake(owner: String, enabled: Bool) {
    if enabled {
      if screenAwakeOwners.isEmpty {
        previousScreenIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
      }
      screenAwakeOwners.insert(owner)
      UIApplication.shared.isIdleTimerDisabled = true
    } else if screenAwakeOwners.remove(owner) != nil, screenAwakeOwners.isEmpty {
      UIApplication.shared.isIdleTimerDisabled = previousScreenIdleTimerDisabled ?? false
      previousScreenIdleTimerDisabled = nil
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

}
