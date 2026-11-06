import Flutter
import CoreFoundation
import ImageCaptureCore
import Photos
import UIKit
import UniformTypeIdentifiers

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

  var diagnosticStatus: String {
    switch self {
    case .authorized: return "authorized"
    case .denied: return "permission-denied"
    case .restricted: return "permission-restricted"
    case .pending: return "authorization-pending"
    case .unavailable: return "authorization-unavailable"
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

  var flutterError: FlutterError {
    FlutterError(
      code: errorCode ?? "CAMERA_AUTHORIZATION_UNAVAILABLE",
      message: message,
      details: ["contentsAuthorization": rawValue]
    )
  }
}

/// The catalogue baseline and delivery acknowledgement are separate: discovering
/// a photo must never mark it delivered before Dart has saved a durable copy.
struct WiredCameraPhotoIdentity {
  let handle: String
  let name: String
  let createdMilliseconds: Int64?
}

final class WiredCameraPhotoIndex {
  private struct KnownPhoto {
    var identity: WiredCameraPhotoIdentity
    let id: String
  }

  private let cameraID: String
  private var currentByHandle: [String: KnownPhoto] = [:]
  private var removalGenerations: [String: Int] = [:]
  private var seenIDs: Set<String> = []
  private var pendingSet: Set<String> = []
  private(set) var pendingIDs: [String] = []

  init(cameraID: String) {
    self.cameraID = cameraID
  }

  func establishBaseline(_ identities: [WiredCameraPhotoIdentity]) {
    currentByHandle.removeAll()
    removalGenerations.removeAll()
    seenIDs.removeAll()
    pendingSet.removeAll()
    pendingIDs.removeAll()
    for identity in identities {
      let id = makeID(identity)
      currentByHandle[identity.handle] = KnownPhoto(identity: identity, id: id)
      seenIDs.insert(id)
    }
  }

  @discardableResult
  func observe(
    _ identity: WiredCameraPhotoIdentity,
    preserveIdentity: Bool = false
  ) -> (id: String, added: Bool) {
    if var known = currentByHandle[identity.handle] {
      let sameDate = known.identity.createdMilliseconds == nil ||
        identity.createdMilliseconds == nil ||
        known.identity.createdMilliseconds == identity.createdMilliseconds
      if preserveIdentity || (known.identity.name == identity.name && sameDate) {
        // Size and initially missing metadata can change while the camera is
        // finishing a file. Keep the delivery ID stable throughout that write.
        known.identity = WiredCameraPhotoIdentity(
          handle: identity.handle,
          name: identity.name,
          createdMilliseconds: identity.createdMilliseconds ?? known.identity.createdMilliseconds
        )
        currentByHandle[identity.handle] = known
        return (known.id, false)
      }
    }

    let id = makeID(identity)
    currentByHandle[identity.handle] = KnownPhoto(identity: identity, id: id)
    let added = seenIDs.insert(id).inserted
    if added {
      pendingSet.insert(id)
      pendingIDs.append(id)
    }
    return (id, added)
  }

  func isPending(_ id: String) -> Bool {
    pendingSet.contains(id)
  }

  func acknowledge(_ ids: Set<String>) {
    pendingSet.subtract(ids)
    pendingIDs.removeAll { ids.contains($0) }
  }

  func markRemoved(handle: String) {
    currentByHandle[handle] = nil
    removalGenerations[handle, default: 0] += 1
    // Keep unacknowledged IDs visible; a missing source is an error, not a
    // successful delivery. A later photo may reuse the deleted object's handle.
  }

  private func makeID(_ identity: WiredCameraPhotoIdentity) -> String {
    let timestamp = identity.createdMilliseconds.map { String($0) } ?? "unknown"
    let generation = removalGenerations[identity.handle, default: 0]
    return "\(cameraID)|\(identity.handle)|\(identity.name.utf8.count):\(identity.name)|\(timestamp)|\(generation)"
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate, ICDeviceBrowserDelegate, ICCameraDeviceDelegate, FlutterStreamHandler {
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
  private var cameraCatalogWaiters: [
    UUID: (cameras: [ICCameraDevice], finish: () -> Void)
  ] = [:]
  private var cameraDeviceWaiters: [UUID: () -> Void] = [:]
  private var cameraSessionRetries: [ObjectIdentifier: Int] = [:]
  private var cameraSessionErrors: [ObjectIdentifier: String] = [:]
  private var cameraAccessRestricted: Set<ObjectIdentifier> = []
  private var requestedCameraSessions: Set<ObjectIdentifier> = []
  private var openingCameraSessions: Set<ObjectIdentifier> = []
  private var closingCameraSessions: Set<ObjectIdentifier> = []
  private var liveEventChannel: FlutterEventChannel?
  private var liveEventSink: FlutterEventSink?
  private var liveEventSessionID: String?
  private var cameraDownloadInProgress = false
  private var cameraDownloadProgress: Progress?
  private var liveDownloadToken: UUID?
  private var cancelLiveCameraDownload: (() -> Void)?
  private var cancelManualCameraDownload: (() -> Void)?
  private var manualCameraGeneration = 0
  private var manualCameraSelectionActive = false
  private var screenAwakeOwners: Set<String> = []
  private var previousScreenIdleTimerDisabled: Bool?

  private final class LiveCameraSession {
    let id: String
    let uploadMode: String
    var camera: ICCameraDevice?
    var startResult: FlutterResult?
    var armed = false
    var index: WiredCameraPhotoIndex?
    var observedObjects: Set<ObjectIdentifier> = []
    var removedObjects: Set<ObjectIdentifier> = []
    var files: [String: ICCameraFile] = [:]
    var removedIDs: Set<String> = []
    var downloadedFiles: [String: [String: String]] = [:]
    var ptpEventCount = 0

    init(id: String, result: @escaping FlutterResult, uploadMode: String) {
      self.id = id
      self.uploadMode = uploadMode
      startResult = result
    }
  }

  private var liveCameraSession: LiveCameraSession?
  private final class PtpTetherSession {
    let id: String
    var camera: ICCameraDevice?
    var transport: PtpTetherTransport?
    var startResult: FlutterResult?
    var startupTimeout: DispatchWorkItem?
    let listenerLease = PtpTetherListenerLease()
    var ptpEventCount = 0
    var imageCaptureFallbackCount = 0
    var imageCaptureFallbackProgress: Progress?
    var imageCaptureFiles: [UInt32: ICCameraFile] = [:]

    init(id: String, result: @escaping FlutterResult) {
      self.id = id
      startResult = result
    }
  }
  private var ptpTetherSession: PtpTetherSession?
  private let ptpTetherStaging = PtpTetherStagingStore()
  private var ptpTetherReleases: [ObjectIdentifier: PtpTetherSessionRelease] = [:]

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
    let liveEvents = FlutterEventChannel(name: "airpix/otg_live", binaryMessenger: messenger)
    liveEvents.setStreamHandler(self)
    liveEventChannel = liveEvents

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
      case "releaseCameraImportSession":
        self.releaseCameraImportSession(result: result)
      case "setTransferScreenAwake":
        let arguments = call.arguments as? [String: Any]
        guard let owner = arguments?["owner"] as? String, !owner.isEmpty else {
          result(FlutterError(code: "INVALID_OWNER", message: "A transfer owner is required.", details: nil))
          return
        }
        self.setScreenAwake(owner: owner, enabled: arguments?["enabled"] as? Bool == true)
        result(nil)
      case "startLiveCameraSession":
        self.startLiveCameraSession(arguments: call.arguments as? [String: Any], result: result)
      case "openPtpTetherSession":
        self.openPtpTetherSession(arguments: call.arguments as? [String: Any], result: result)
      case "sendPtpTetherCommand":
        self.sendPtpTetherCommand(arguments: call.arguments as? [String: Any], result: result)
      case "downloadPtpTetherObject":
        self.downloadPtpTetherObject(arguments: call.arguments as? [String: Any], result: result)
      case "acknowledgePtpTetherFiles":
        self.acknowledgePtpTetherFiles(arguments: call.arguments as? [String: Any], result: result)
      case "closePtpTetherSession":
        let arguments = call.arguments as? [String: Any]
        self.closePtpTetherSession(sessionID: arguments?["sessionId"] as? String, result: result)
      case "stopLiveCameraSession":
        let arguments = call.arguments as? [String: Any]
        self.stopLiveCameraSession(sessionID: arguments?["sessionId"] as? String, result: result)
      case "pendingLiveCameraImages":
        let arguments = call.arguments as? [String: Any]
        self.pendingLiveCameraImages(sessionID: arguments?["sessionId"] as? String, result: result)
      case "downloadLiveCameraImage":
        let arguments = call.arguments as? [String: Any]
        self.downloadLiveCameraImage(
          sessionID: arguments?["sessionId"] as? String,
          imageID: arguments?["id"] as? String,
          result: result
        )
      case "acknowledgeLiveCameraImages":
        let arguments = call.arguments as? [String: Any]
        self.acknowledgeLiveCameraImages(
          sessionID: arguments?["sessionId"] as? String,
          ids: arguments?["ids"] as? [String] ?? [],
          result: result
        )
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

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    liveEventSink = events
    liveEventSessionID = (arguments as? [String: Any])?["sessionId"] as? String
    if let session = ptpTetherSession, liveEventSessionID == session.id {
      session.listenerLease.attach()
    }
    if let session = liveCameraSession, session.armed {
      emitLiveEvent(session, type: "status", status: "waiting-for-shot",
                    message: liveCameraMessage(session.camera))
      if session.index?.pendingIDs.isEmpty == false {
        emitLiveEvent(session, type: "photosAvailable")
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    // Flutter may supply nil for a hot-restart cancellation. In that case the
    // token belongs to the currently registered listener, not an arbitrary run.
    let cancelledID = (arguments as? [String: Any])?["sessionId"] as? String
      ?? liveEventSessionID
    guard cancelledID == liveEventSessionID else { return nil }
    liveEventSink = nil
    liveEventSessionID = nil
    if let session = ptpTetherSession, cancelledID == session.id {
      // The Dart protocol driver completes its shutdown commands before
      // cancelling its native listener. Give a receiver reattachment a short
      // grace period, but never leave a lost/hot-restarted owner open forever.
      session.listenerLease.detach { [weak self, weak session] in
        guard let self, let session, self.ptpTetherSession === session,
              session.listenerLease.isDetached else { return }
        self.endPtpTetherSession(session, error: FlutterError(
          code: "CAMERA_SESSION_ENDED",
          message: "The camera receiver closed. Start live shooting again to reconnect.",
          details: nil
        ), eventType: "disconnected")
      }
    }
    // A Flutter hot restart/disposed controller must not leave the camera held
    // in a photo-transfer session with nobody consuming its events.
    if let session = liveCameraSession, cancelledID == session.id {
      endLiveCameraSession(
        session,
        error: FlutterError(code: "LIVE_CAMERA_CANCELLED",
                            message: "Live camera capture stopped.", details: nil)
      )
    }
    return nil
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

  private func cameraIdentity(_ camera: ICCameraDevice) -> String {
    if let uuid = camera.uuidString, !uuid.isEmpty { return uuid }
    return "\(camera.usbVendorID):\(camera.usbProductID):\(camera.name ?? "camera")"
  }

  private func photoIdentity(_ file: ICCameraFile) -> WiredCameraPhotoIdentity {
    let name = file.originalFilename ?? file.name ?? "camera-image.jpg"
    return WiredCameraPhotoIdentity(
      handle: file.ptpObjectHandle == 0 ? "file:\(name)" : String(file.ptpObjectHandle),
      name: name,
      createdMilliseconds: file.fileCreationDate.map {
        Int64($0.timeIntervalSince1970 * 1000)
      }
    )
  }

  // USB and wireless share one baseline. A late teardown can only release its
  // own token, never the wake state of a newer receiving session.
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

  private func physicalShutterCapability(_ camera: ICCameraDevice) -> String {
    camera.capabilities.contains(
      ICDeviceCapability.cameraDeviceCanTakePictureUsingShutterReleaseOnCamera.rawValue
    ) ? "supported" : "unknown"
  }

  private func isLiveCameraReceiving(_ camera: ICCameraDevice) -> Bool {
    let key = ObjectIdentifier(camera)
    let ownerIsActive = (liveCameraSession?.camera === camera && liveCameraSession?.armed == true) ||
      (ptpTetherSession?.camera === camera && ptpTetherSession?.transport?.closed == false)
    return ownerIsActive &&
      connectedCameras.contains(where: { $0 === camera }) && camera.hasOpenSession &&
      requestedCameraSessions.contains(key) && !openingCameraSessions.contains(key) &&
      !closingCameraSessions.contains(key)
  }

  private func liveCameraMessage(_ camera: ICCameraDevice?) -> String {
    guard let camera else { return "Preparing the USB camera." }
    if physicalShutterCapability(camera) == "supported" {
      return "Camera shutter support reported. Take a test photo on the camera. New photos will be copied while AirPix stays open."
    }
    return "Camera connected; shooting over USB is unverified. Take one test photo. If the shutter is locked or the camera shows a transfer screen, stop and select a USB mode that supports shooting on this camera."
  }

  private func emitLiveEvent(
    _ session: LiveCameraSession,
    type: String,
    status: String? = nil,
    message: String? = nil,
    code: String? = nil
  ) {
    guard liveEventSessionID == nil || liveEventSessionID == session.id else { return }
    var event: [String: Any] = ["type": type, "sessionId": session.id]
    if let status { event["status"] = status }
    if let message { event["message"] = message }
    if let code { event["code"] = code }
    liveEventSink?(event)
  }

  private func ptpFlutterError(_ failure: PtpTetherFailure) -> FlutterError {
    FlutterError(code: failure.code, message: failure.message, details: nil)
  }

  private func ptpUnsigned32(_ value: Any?) -> UInt32? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    let raw = number.doubleValue
    guard raw.isFinite, raw >= 0, raw <= Double(UInt32.max), raw.rounded(.towardZero) == raw else { return nil }
    return UInt32(raw)
  }

  private func emitPtpTetherEvent(
    _ session: PtpTetherSession, type: String, message: String? = nil,
    code: String? = nil, data: Data? = nil
  ) {
    guard liveEventSessionID == session.id else { return }
    var payload: [String: Any] = ["type": type, "sessionId": session.id]
    if let message { payload["message"] = message }
    if let code { payload["code"] = code }
    if let data { payload["data"] = FlutterStandardTypedData(bytes: data) }
    liveEventSink?(payload)
  }

  /// ImageCaptureCore catalogue callbacks are secondary hints only. Dart still
  /// decides whether a handle is new by running the vendor/raw PTP workflow.
  private func emitPtpCatalogHint(_ session: PtpTetherSession, file: ICCameraFile) {
    guard liveEventSessionID == session.id, file.ptpObjectHandle > 0 else { return }
    session.imageCaptureFiles[file.ptpObjectHandle] = file
    liveEventSink?([
      "type": "catalogHint",
      "sessionId": session.id,
      "handle": Int64(file.ptpObjectHandle),
      "name": file.originalFilename ?? file.name ?? "camera-image.jpg",
      "size": file.fileSize,
    ] as [String: Any])
  }

  private func emitPtpCatalogRemoval(_ session: PtpTetherSession, file: ICCameraFile) {
    guard liveEventSessionID == session.id, file.ptpObjectHandle > 0 else { return }
    session.imageCaptureFiles[file.ptpObjectHandle] = nil
    liveEventSink?([
      "type": "catalogRemoved",
      "sessionId": session.id,
      "handle": Int64(file.ptpObjectHandle),
    ] as [String: Any])
  }

  /// Opens ImageCaptureCore's transport only. The shared camera driver then
  /// identifies supported operations and negotiates its actual tether protocol.
  private func openPtpTetherSession(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let id = arguments?["sessionId"] as? String, !id.isEmpty, id.utf8.count <= 256 else {
      result(FlutterError(code: "PTP_INVALID_ARGUMENT", message: "A valid tether session ID is required.", details: nil))
      return
    }
    if let orphan = ptpTetherSession, orphan.listenerLease.isDetached, orphan.id != id {
      // A Flutter hot restart can lose its driver before explicit teardown.
      // Release that exact owner before allowing another receiver to open it.
      endPtpTetherSession(orphan, error: FlutterError(code: "CAMERA_SESSION_ENDED",
        message: "The previous tether receiver was restarted.", details: nil), eventType: "disconnected")
    }
    if let releaseError = pendingPtpReleaseError() { result(releaseError); return }
    guard ptpTetherSession == nil, liveCameraSession == nil, !cameraDownloadInProgress,
          !manualCameraSelectionActive, cameraCatalogWaiters.isEmpty else {
      result(FlutterError(code: "LIVE_CAMERA_BUSY", message: "Stop the current camera transfer before starting a tether connection.", details: nil))
      return
    }
    let session = PtpTetherSession(id: id, result: result)
    ptpTetherSession = session
    let timeout = DispatchWorkItem { [weak self, weak session] in
      guard let self, let session, self.ptpTetherSession === session, session.startResult != nil else { return }
      self.endPtpTetherSession(session, error: FlutterError(
        code: "CAMERA_SESSION_FAILED",
        message: "The camera tether connection did not finish opening. Keep the iPhone unlocked, approve camera access and check the camera's shooting-capable USB mode.",
        details: nil
      ))
    }
    session.startupTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 45, execute: timeout)
    let wantedCameraID = arguments?["cameraId"] as? String
    ensureCameraContentsAccess { [weak self, weak session] access in
      guard let self, let session, self.ptpTetherSession === session else { return }
      guard access.allowsContentsAccess else {
        self.endPtpTetherSession(session, error: access.flutterError)
        return
      }
      self.waitForCameraDevice(timeout: 6) { [weak self, weak session] in
        guard let self, let session, self.ptpTetherSession === session else { return }
        let candidates = self.connectedCameras.filter {
          wantedCameraID == nil || self.cameraIdentity($0) == wantedCameraID
        }
        guard let camera = candidates.first else {
          self.endPtpTetherSession(session, error: FlutterError(
            code: "NO_CAMERA_CONNECTED", message: "No compatible wired camera found. Use a USB data cable and the camera's supported tethered-shooting mode.", details: nil
          ))
          return
        }
        guard candidates.count == 1 else {
          self.endPtpTetherSession(session, error: FlutterError(
            code: "MULTIPLE_CAMERAS", message: "Connect only the camera you want to shoot with before starting tether capture.", details: nil
          ))
          return
        }
        // Reject clearly labelled mass storage, card reader and streaming
        // transports before asking ImageCaptureCore to open a PTP session.
        // This label is only a hint: "USB" alone cannot prove PTP shooting.
        let transport = (camera.transportType ?? "").lowercased()
          .replacingOccurrences(of: " ", with: "")
          .replacingOccurrences(of: "-", with: "")
        let massStorage = transport.contains("massstorage") || transport.contains("exfat")
        // PTP/MTP is a valid camera control transport on some Canon, Nikon
        // and other bodies. Never reject MTP *solely by its OS label*:
        // check negotiated camera operations and confirm a test shutter shot.
        let transferOnly = massStorage || transport.contains("cardreader") ||
          transport.contains("filetransfer") || transport.contains("usbstreaming")
        guard !transferOnly else {
          let isSony = camera.usbVendorID == 0x054c
          self.endPtpTetherSession(session, error: FlutterError(
            code: (isSony && massStorage) ? "SONY_MASS_STORAGE_MODE" : "LIVE_CAMERA_TRANSFER_ONLY",
            message: isSony
              ? "The Sony camera is in a file-transfer/streaming USB mode, not Remote Shooting. Unplug USB, then select Setup > USB > USB Connection Mode > Remote Shooting and reconnect."
              : "The camera is exposing USB storage, media transfer or streaming, not a shooting-capable PTP connection. Unplug it and choose the model's tether/remote-shooting USB mode. Ordinary PTP/MTP import does not confirm a usable shutter.",
            details: ["camera": camera.name ?? "USB camera", "transport": camera.transportType ?? "unknown"]
          ))
          return
        }
        session.camera = camera
        self.ensureCameraControlAccess { [weak self, weak session] control in
          guard let self, let session, self.ptpTetherSession === session else { return }
          guard control.allowsContentsAccess else {
            let code: String
            let message: String
            switch control {
            case .denied:
              code = "CAMERA_CONTROL_ACCESS_DENIED"
              message = "iOS denied permission to control the connected camera. Allow external camera access in iPhone Settings, then retry."
            case .restricted:
              code = "CAMERA_ACCESS_RESTRICTED"
              message = "iOS has restricted external camera control. Check the iPhone's device restrictions."
            case .pending:
              code = "CAMERA_AUTHORIZATION_PENDING"
              message = "iOS has not completed camera-control authorization. Keep the phone unlocked, respond to its access prompt and retry."
            default:
              code = "CAMERA_AUTHORIZATION_UNAVAILABLE"
              message = "iOS could not determine external camera-control authorization. Reconnect the camera and retry."
            }
            self.endPtpTetherSession(session, error: FlutterError(
              code: code, message: message, details: ["controlAuthorization": control.rawValue]
            ))
            return
          }
          guard self.connectedCameras.contains(where: { $0 === camera }) else {
            self.endPtpTetherSession(session, error: FlutterError(code: "USB_CAMERA_DISCONNECTED", message: "The camera disconnected while permission was being granted.", details: nil))
            return
          }
          self.emitPtpTetherEvent(session, type: "status", message: "Opening the camera tether transport.")
          self.requestCameraSession(camera)
          self.completePtpTetherOpenIfReady(session)
        }
      }
    }
  }

  private func ensureCameraControlAccess(_ completion: @escaping (WiredCameraAuthorizationState) -> Void) {
    if #available(iOS 14.0, *) {
      let status = WiredCameraAuthorizationState(cameraBrowser.controlAuthorizationStatus)
      guard status == .pending else { completion(status); return }
      cameraBrowser.requestControlAuthorization { status in
        DispatchQueue.main.async { completion(WiredCameraAuthorizationState(status)) }
      }
    } else {
      completion(.authorized)
    }
  }

  private func completePtpTetherOpenIfReady(_ session: PtpTetherSession) {
    guard ptpTetherSession === session, session.transport == nil,
          let camera = session.camera, camera.hasOpenSession,
          connectedCameras.contains(where: { $0 === camera }),
          requestedCameraSessions.contains(ObjectIdentifier(camera)),
          !openingCameraSessions.contains(ObjectIdentifier(camera)),
          !closingCameraSessions.contains(ObjectIdentifier(camera)) else { return }
    guard camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) else {
      let isSony = camera.usbVendorID == 0x054c
      endPtpTetherSession(session, error: FlutterError(
        code: isSony ? "SONY_PTP_CONTROL_UNAVAILABLE" : "PTP_PASSTHROUGH_UNAVAILABLE",
        message: isSony
          ? "iOS detected the Sony camera but has not exposed the PTP commands needed for live shooting. On an Alpha 7 IV, disconnect USB and choose Remote Shooting instead of Mass Storage, MTP or USB Streaming. A compatible camera mode does not guarantee iOS exposes this vendor control interface."
          : "iOS has not exposed PTP camera control for this connection. Check the camera's supported tether mode.",
        details: [
          "camera": camera.name ?? "USB camera",
          "transport": camera.transportType ?? "unknown",
          "vendorId": Int(camera.usbVendorID),
          "productId": Int(camera.usbProductID),
          "capabilities": camera.capabilities,
        ]
      ))
      return
    }
    session.transport = PtpTetherTransport(sessionID: session.id, camera: camera, staging: ptpTetherStaging) {
      [weak self, weak session] failure in
      guard let self, let session, self.ptpTetherSession === session else { return }
      self.endPtpTetherSession(session, error: self.ptpFlutterError(failure), eventType: "disconnected")
    }
    session.startupTimeout?.cancel()
    session.startupTimeout = nil
    setScreenAwake(owner: "ptp:\(session.id)", enabled: true)
    let result = session.startResult
    session.startResult = nil
    result?([
      "sessionId": session.id,
      "cameraId": cameraIdentity(camera),
      "name": camera.name ?? "USB camera",
      "vendorId": Int(camera.usbVendorID),
      "productId": Int(camera.usbProductID),
      "physicalShutter": physicalShutterCapability(camera),
      "transport": "imagecapturecore-ptp",
    ] as [String: Any])
  }

  private func requirePtpTetherSession(_ id: String?, result: @escaping FlutterResult) -> PtpTetherSession? {
    guard let session = ptpTetherSession, session.id == id,
          let transport = session.transport, !transport.closed,
          let camera = session.camera else {
      result(FlutterError(code: "CAMERA_SESSION_ENDED", message: "This camera tether session has ended.", details: nil))
      return nil
    }
    guard camera.hasOpenSession, connectedCameras.contains(where: { $0 === camera }),
          requestedCameraSessions.contains(ObjectIdentifier(camera)),
          !closingCameraSessions.contains(ObjectIdentifier(camera)) else {
      let error = FlutterError(code: "USB_CAMERA_DISCONNECTED", message: "The camera tether connection was lost. Reconnect to continue shooting.", details: nil)
      endPtpTetherSession(session, error: error, eventType: "disconnected")
      result(error)
      return nil
    }
    return session
  }

  private func sendPtpTetherCommand(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let session = requirePtpTetherSession(arguments?["sessionId"] as? String, result: result),
          let transport = session.transport else { return }
    let rawParameters = arguments?["params"] as? [Any] ?? []
    let parameters = rawParameters.compactMap { ptpUnsigned32($0) }
    guard let rawOpcode = ptpUnsigned32(arguments?["opcode"]), rawOpcode > 0, rawOpcode <= UInt32(UInt16.max),
          rawParameters.count <= 5, parameters.count == rawParameters.count,
          arguments?["params"] == nil || arguments?["params"] is [Any] else {
      result(FlutterError(code: "PTP_INVALID_ARGUMENT", message: "Invalid PTP operation or parameters.", details: nil))
      return
    }
    var outgoing: Data?
    if let value = arguments?["outData"], !(value is NSNull) {
      guard let typed = value as? FlutterStandardTypedData, typed.data.count <= PtpTetherCodec.outgoingLimit else {
        result(FlutterError(code: "PTP_INVALID_ARGUMENT", message: "PTP outgoing data must be a byte array no larger than 64 KiB.", details: nil))
        return
      }
      outgoing = typed.data
    }
    transport.send(opcode: UInt16(rawOpcode), parameters: parameters, outgoing: outgoing) { outcome in
      switch outcome {
      case .success(let reply):
        result([
          "responseCode": Int(reply.responseCode),
          "parameters": reply.parameters.map { Int64($0) },
          "data": FlutterStandardTypedData(bytes: reply.data),
        ] as [String: Any])
      case .failure(let failure): result(self.ptpFlutterError(failure))
      }
    }
  }

  private func downloadPtpTetherObject(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let sessionID = arguments?["sessionId"] as? String, !sessionID.isEmpty, sessionID.utf8.count <= 256,
          let handle = ptpUnsigned32(arguments?["handle"]), handle > 0,
          let size = ptpUnsigned32(arguments?["expectedSize"]), size > 0, size <= UInt32(PtpTetherCodec.fileLimit),
          let name = arguments?["name"] as? String,
          let transferID = arguments?["transferId"] as? String, !transferID.isEmpty, transferID.utf8.count <= 2048 else {
      result(FlutterError(code: "PTP_INVALID_ARGUMENT", message: "A camera handle, filename, size and transfer identity are required.", details: nil))
      return
    }
    var partialOpcode: UInt16?
    if let value = arguments?["partialOpcode"], !(value is NSNull) {
      guard let opcode = ptpUnsigned32(value), opcode == 0x101B || opcode == 0x9107 else {
        result(FlutterError(code: "PTP_INVALID_ARGUMENT", message: "Unsupported partial-object operation.", details: nil))
        return
      }
      partialOpcode = UInt16(opcode)
    }
    do {
      if let file = try ptpTetherStaging.lookup(sessionID: sessionID, transferID: transferID,
                                              handle: handle, name: PtpTetherTransport.safeName(name), expectedSize: Int(size)) {
        // A completed transfer remains recoverable by its original token after
        // Stop/disconnect, even when Dart's durable queue copy needs a retry.
        result(["path": file.path, "name": file.name, "size": file.size])
        return
      }
    } catch let failure as PtpTetherFailure {
      result(ptpFlutterError(failure))
      return
    } catch {
      result(FlutterError(code: "PTP_STAGING_FAILED", message: error.localizedDescription, details: nil))
      return
    }
    guard let session = requirePtpTetherSession(sessionID, result: result),
          let transport = session.transport else { return }
    transport.downloadObject(handle: handle, name: name, expectedSize: Int(size), transferID: transferID,
                             partialOpcode: partialOpcode) { outcome in
      // Keep a fully completed in-flight file valid under its original token,
      // even if Stop/disconnect occurred while the final bytes reached disk.
      switch outcome {
      case .success(let file):
        result(["path": file.path, "name": file.name, "size": file.size])
      case .failure(let failure):
        guard PtpImageCaptureFallbackPolicy.shouldTry(
          code: failure.code, handle: handle, expectedSize: Int(size)
        ), let camera = session.camera,
           let fallbackFile = self.ptpImageCaptureFallbackFile(
             session: session,
             camera: camera,
             handle: handle,
             name: name,
             expectedSize: Int(size)
           ) else {
          result(self.ptpFlutterError(failure))
          return
        }
        self.downloadPtpObjectViaImageCapture(
          session: session,
          camera: camera,
          file: fallbackFile,
          handle: handle,
          name: name,
          expectedSize: Int(size),
          transferID: transferID,
          originalFailure: failure,
          result: result
        )
      }
    }
  }

  private func ptpImageCaptureFallbackFile(
    session: PtpTetherSession,
    camera: ICCameraDevice,
    handle: UInt32,
    name: String,
    expectedSize: Int
  ) -> ICCameraFile? {
    let safeName = PtpTetherTransport.safeName(name)
    var candidates: [ICCameraFile] = []
    if let cached = session.imageCaptureFiles[handle] { candidates.append(cached) }
    candidates.append(contentsOf: cameraImageFiles(camera).filter { $0.ptpObjectHandle == handle })
    return candidates.first { file in
      guard file.ptpObjectHandle == handle else { return false }
      let fileName = PtpTetherTransport.safeName(
        file.originalFilename ?? file.name ?? "camera-image.jpg"
      )
      guard fileName.caseInsensitiveCompare(safeName) == .orderedSame else { return false }
      let catalogueSize = Int(file.fileSize)
      return catalogueSize <= 0 || catalogueSize == expectedSize
    }
  }

  private func downloadPtpObjectViaImageCapture(
    session: PtpTetherSession,
    camera: ICCameraDevice,
    file: ICCameraFile,
    handle: UInt32,
    name: String,
    expectedSize: Int,
    transferID: String,
    originalFailure: PtpTetherFailure,
    result: @escaping FlutterResult
  ) {
    guard session.imageCaptureFallbackProgress == nil,
          camera.hasOpenSession,
          connectedCameras.contains(where: { $0 === camera }),
          !cameraAccessRestricted.contains(ObjectIdentifier(camera)) else {
      result(ptpFlutterError(originalFailure))
      return
    }

    let filename = PtpTetherTransport.safeName(name)
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("airpix_ptp_fallback", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    } catch {
      result(ptpFlutterError(originalFailure))
      return
    }

    let options: [ICDownloadOption: Any] = [
      .downloadsDirectoryURL: directory,
      .saveAsFilename: filename,
      .overwrite: true,
      .deleteAfterSuccessfulDownload: false,
    ]
    var completed = false
    let finish: (Any) -> Void = { payload in
      guard !completed else { return }
      completed = true
      session.imageCaptureFallbackProgress = nil
      result(payload)
    }
    let timeout = DispatchWorkItem { [weak self, weak session] in
      guard let self, let session, !completed else { return }
      session.imageCaptureFallbackProgress?.cancel()
      session.imageCaptureFallbackProgress = nil
      try? FileManager.default.removeItem(at: directory)
      finish(self.ptpFlutterError(originalFailure))
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)

    session.imageCaptureFallbackProgress = file.requestDownload(options: options) {
      [weak self, weak session] path, error in
      DispatchQueue.main.async {
        guard let self, let session, !completed else { return }
        timeout.cancel()
        if error != nil {
          try? FileManager.default.removeItem(at: directory)
          finish(self.ptpFlutterError(originalFailure))
          return
        }

        let returnedURL = path.flatMap { URL(string: $0) }
        let resolvedPath: String = returnedURL?.isFileURL == true
          ? (returnedURL?.path ?? "")
          : (path?.hasPrefix("/") == true
              ? path!
              : directory.appendingPathComponent(path ?? filename).path)
        let fallbackPath = directory.appendingPathComponent(filename).path
        let exactPath = [resolvedPath, fallbackPath].first { candidate in
          guard !candidate.isEmpty,
                let attributes = try? FileManager.default.attributesOfItem(atPath: candidate),
                let byteCount = (attributes[.size] as? NSNumber)?.intValue else {
            return false
          }
          return byteCount == expectedSize
        }
        guard let exactPath else {
          try? FileManager.default.removeItem(at: directory)
          finish(self.ptpFlutterError(originalFailure))
          return
        }

        let staged = PtpTetherStagedFile(
          path: exactPath,
          name: filename,
          size: expectedSize
        )
        self.ptpTetherStaging.save(
          staged,
          sessionID: session.id,
          transferID: transferID,
          handle: handle
        )
        session.imageCaptureFallbackCount += 1
        if session.imageCaptureFallbackCount == 1 {
          self.emitPtpTetherEvent(
            session,
            type: "status",
            message: "AirPix recovered this photo through ImageCaptureCore on the same PTP connection. The camera USB mode was not changed."
          )
        }
        finish(["path": staged.path, "name": staged.name, "size": staged.size])
      }
    }
  }

  private func acknowledgePtpTetherFiles(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let sessionID = arguments?["sessionId"] as? String, !sessionID.isEmpty,
          let ids = arguments?["ids"] as? [String], ids.count <= 5000 else {
      result(FlutterError(code: "PTP_INVALID_ARGUMENT", message: "A tether session and transfer identities are required.", details: nil))
      return
    }
    if let session = ptpTetherSession, session.id == sessionID, let transport = session.transport {
      transport.acknowledge(ids)
    } else {
      ptpTetherStaging.acknowledge(sessionID: sessionID, transferIDs: ids)
    }
    result(true)
  }

  private func closePtpTetherSession(sessionID: String?, result: @escaping FlutterResult) {
    let finished: (PtpTetherSessionRelease.Outcome) -> Void = { outcome in
      switch outcome {
      case .success: result(true)
      case .failure(let failure): result(self.ptpFlutterError(failure))
      }
    }
    if let release = ptpTetherReleases.values.first(where: { $0.includesOwner(sessionID) }) {
      release.cameraStateChanged()
      release.wait(finished)
      return
    }
    guard let session = ptpTetherSession, session.id == sessionID else { result(false); return }
    endPtpTetherSession(
      session,
      error: FlutterError(code: "CAMERA_SESSION_ENDED", message: "Camera tethering stopped.", details: nil),
      eventType: "status", releaseCompletion: finished
    )
  }

  private func endPtpTetherSession(
    _ session: PtpTetherSession, error: FlutterError, eventType: String = "error",
    releaseCompletion: ((PtpTetherSessionRelease.Outcome) -> Void)? = nil
  ) {
    guard ptpTetherSession === session else { return }
    ptpTetherSession = nil
    session.listenerLease.invalidate()
    session.startupTimeout?.cancel()
    session.startupTimeout = nil
    session.transport?.close()
    session.imageCaptureFallbackProgress?.cancel()
    session.imageCaptureFallbackProgress = nil
    setScreenAwake(owner: "ptp:\(session.id)", enabled: false)
    if let camera = session.camera {
      releasePtpCameraSession(camera, sessionID: session.id, completion: releaseCompletion)
    } else {
      // Permission/discovery was cancelled before any camera session opened.
      releaseCompletion?(.success(()))
    }
    let result = session.startResult
    session.startResult = nil
    result?(error)
    emitPtpTetherEvent(session, type: eventType, message: error.message, code: error.code)
  }

  private func pendingPtpReleaseError() -> FlutterError? {
    // An OS state change can precede its notification. Refresh the exact held
    // operations so an actually closed camera is not left unnecessarily blocked.
    Array(ptpTetherReleases.values).forEach { $0.cameraStateChanged() }
    guard let release = ptpTetherReleases.values.first else { return nil }
    if let failure = release.failure { return ptpFlutterError(failure) }
    return FlutterError(
      code: "PTP_CLOSE_PENDING",
      message: "The previous camera connection is still closing. Wait for release before starting another USB camera operation. If it cannot close, disconnect the cable before reconnecting.",
      details: nil
    )
  }

  private func releasePtpCameraSession(
    _ camera: ICCameraDevice, sessionID: String,
    completion: ((PtpTetherSessionRelease.Outcome) -> Void)?
  ) {
    let key = ObjectIdentifier(camera)
    requestedCameraSessions.remove(key)
    readyCameras.remove(key)
    cameraSessionRetries[key] = nil
    if let existing = ptpTetherReleases[key] {
      existing.includeEndedOwner(sessionID)
      existing.cameraStateChanged()
      if let completion { existing.wait(completion) }
      return
    }
    let release = PtpTetherSessionRelease(
      sessionID: sessionID,
      state: { [weak self, weak camera] in
        guard let self, let camera else {
          return .init(connected: false, opening: false, open: false)
        }
        return .init(
          connected: self.connectedCameras.contains(where: { $0 === camera }),
          opening: self.openingCameraSessions.contains(key), open: camera.hasOpenSession
        )
      },
      requestClose: { [weak camera] finished in
        guard let camera else { finished(nil); return }
        // Available since iOS 13. The completion belongs to this exact release
        // operation; a delayed old callback cannot release a newer owner.
        camera.requestCloseSession(options: nil) { error in
          DispatchQueue.main.async { finished(error) }
        }
      },
      onReleased: { [weak self, weak camera] released in
        guard let self, self.ptpTetherReleases[key] === released else { return }
        self.ptpTetherReleases[key] = nil
        self.closingCameraSessions.remove(key)
        self.cameraSessionErrors[key] = nil
        // An existing catalog/start request can reach requestCameraSession
        // while its predecessor is still closing. Resume only its current
        // request marker; cancelling that owner removes the marker.
        if let camera, self.requestedCameraSessions.contains(key),
           self.connectedCameras.contains(where: { $0 === camera }) {
          self.requestCameraSession(camera)
        }
      },
      onFailure: { [weak self] failed, failure in
        guard let self, self.ptpTetherReleases[key] === failed else { return }
        self.cameraSessionErrors[key] = failure.message
      }
    )
    // Retain the release after its deadline/error. Neither a manual importer
    // nor a new tether run may adopt an unconfirmed native session.
    ptpTetherReleases[key] = release
    closingCameraSessions.insert(key)
    if let completion { release.wait(completion) }
    release.begin()
  }

  private func startLiveCameraSession(
    arguments: [String: Any]?,
    result: @escaping FlutterResult
  ) {
    if let releaseError = pendingPtpReleaseError() { result(releaseError); return }
    guard liveCameraSession == nil, ptpTetherSession == nil,
          !cameraDownloadInProgress, !manualCameraSelectionActive,
          cameraCatalogWaiters.isEmpty else {
      result(FlutterError(code: "LIVE_CAMERA_BUSY",
                          message: "Stop the current camera session or wait for its transfer to finish.",
                          details: nil))
      return
    }

    // A caller-supplied token also permits cancellation while permission or
    // catalogue discovery is still pending. A stale stop can never stop a new run.
    let suppliedID = (arguments?["sessionId"] as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let uploadMode = (arguments?["uploadMode"] as? String) == "existingAndNew"
      ? "existingAndNew" : "newShotsOnly"
    let session = LiveCameraSession(
      id: suppliedID?.isEmpty == false ? suppliedID! : UUID().uuidString,
      result: result,
      uploadMode: uploadMode
    )
    liveCameraSession = session
    let wantedCameraID = arguments?["cameraId"] as? String

    ensureCameraContentsAccess { [weak self] access in
      guard let self, self.liveCameraSession === session else { return }
      guard access.allowsContentsAccess else {
        self.endLiveCameraSession(session, error: access.flutterError)
        return
      }
      self.waitForCameraDevice(timeout: 6) { [weak self] in
        guard let self, self.liveCameraSession === session else { return }
        let candidates = self.connectedCameras.filter {
          wantedCameraID == nil || self.cameraIdentity($0) == wantedCameraID
        }
        guard let camera = candidates.first else {
          self.endLiveCameraSession(session, error: FlutterError(
            code: "NO_CAMERA_CONNECTED",
            message: "No compatible wired camera found. Use a USB data cable and a camera USB mode that supports shooting while connected.",
            details: nil
          ))
          return
        }
        guard candidates.count == 1 else {
          self.endLiveCameraSession(session, error: FlutterError(
            code: "MULTIPLE_CAMERAS",
            message: "Connect only the camera you want to shoot with, then start live capture again.",
            details: nil
          ))
          return
        }
        let transport = (camera.transportType ?? "").lowercased()
        guard !transport.contains("massstorage"), !transport.contains("exfat") else {
          self.endLiveCameraSession(session, error: FlutterError(
            code: "LIVE_CAMERA_TRANSFER_ONLY",
            message: "The camera is exposing storage, not a live camera connection. Stop, unplug the cable and select the camera's shooting-capable USB mode. Mass Storage or a card reader cannot provide live shutter capture.",
            details: nil
          ))
          return
        }

        session.camera = camera
        session.index = WiredCameraPhotoIndex(cameraID: self.cameraIdentity(camera))
        self.emitLiveEvent(session, type: "status", status: "preparing",
                           message: "Reading the existing photo list. Wait for the camera-ready message before taking new photos.")
        self.requestCameraSession(camera)
        self.armLiveCameraSessionIfReady(session)
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self, weak session] in
          guard let self, let session, self.liveCameraSession === session, !session.armed else { return }
          let hasSession = camera.hasOpenSession
          self.endLiveCameraSession(session, error: FlutterError(
            code: hasSession ? "CAMERA_CATALOG_LOADING" : "CAMERA_SESSION_FAILED",
            message: hasSession
              ? "The initial camera photo list is not complete. Live capture was not started, so old photos will not be mistaken for new shots. Keep the camera awake, then retry."
              : "The camera did not open its USB session. Check its shooting-capable USB mode, power and any access prompt, then retry.",
            details: self.cameraSessionErrors[ObjectIdentifier(camera)]
          ))
        }
      }
    }
  }

  private func armLiveCameraSessionIfReady(_ session: LiveCameraSession) {
    guard liveCameraSession === session, !session.armed,
          let camera = session.camera, let index = session.index,
          connectedCameras.contains(where: { $0 === camera }),
          camera.hasOpenSession,
          requestedCameraSessions.contains(ObjectIdentifier(camera)),
          !openingCameraSessions.contains(ObjectIdentifier(camera)),
          !closingCameraSessions.contains(ObjectIdentifier(camera)),
          (readyCameras.contains(ObjectIdentifier(camera)) ||
           camera.contentCatalogPercentCompleted >= 100)
    else { return }
    guard !cameraAccessRestricted.contains(ObjectIdentifier(camera)) else {
      endLiveCameraSession(session, error: FlutterError(
        code: "CAMERA_DEVICE_LOCKED",
        message: "Unlock the connected camera or approve its access prompt, then try again.",
        details: nil
      ))
      return
    }

    let baseline = cameraImageFiles(camera)
    session.observedObjects = Set(baseline.map { ObjectIdentifier($0) })
    if session.uploadMode == "existingAndNew" {
      // Keep full card objects in the same passive ImageCaptureCore reader;
      // importing older files never requests a vendor-mode switch.
      index.establishBaseline([])
      session.armed = true
      collectLiveCameraFiles(session, files: baseline)
    } else {
      index.establishBaseline(baseline.map(photoIdentity))
      session.armed = true
    }
    setScreenAwake(owner: "usb:\(session.id)", enabled: true)
    let startResult = session.startResult
    session.startResult = nil
    let message = session.uploadMode == "existingAndNew"
      ? "Camera photo catalog ready. Existing and new photos will copy while AirPix stays open. Verify the physical shutter remains usable."
      : "Camera photo catalog ready. Existing photos skipped. AirPix checks for new photos every three seconds without changing the camera USB mode. Verify the physical shutter remains usable."
    startResult?([
      "sessionId": session.id,
      "cameraId": cameraIdentity(camera),
      "name": camera.name ?? "USB camera",
      "status": "waiting-for-shot",
      "physicalShutter": physicalShutterCapability(camera),
      "message": message,
      "baselineCount": baseline.count,
      "uploadMode": session.uploadMode,
    ] as [String: Any])
    emitLiveEvent(session, type: "status", status: "waiting-for-shot", message: message)
    NSLog("[AirPix USB] Live camera session armed; baseline files: %d; physical shutter: %@",
          baseline.count, physicalShutterCapability(camera))
  }

  private func stopLiveCameraSession(sessionID: String?, result: @escaping FlutterResult) {
    guard let session = liveCameraSession, session.id == sessionID else {
      result(false)
      return
    }
    endLiveCameraSession(session, error: FlutterError(
      code: "LIVE_CAMERA_CANCELLED", message: "Live camera capture stopped.", details: nil
    ), eventType: "status")
    result(true)
  }

  private func endLiveCameraSession(
    _ session: LiveCameraSession,
    error: FlutterError,
    eventType: String = "error"
  ) {
    guard liveCameraSession === session else { return }
    liveCameraSession = nil
    session.armed = false
    setScreenAwake(owner: "usb:\(session.id)", enabled: false)
    let startResult = session.startResult
    session.startResult = nil
    let cancelDownload = cancelLiveCameraDownload
    cancelLiveCameraDownload = nil
    cancelDownload?()
    if let camera = session.camera {
      closeCameraSession(camera)
    }
    startResult?(error)
    emitLiveEvent(session, type: eventType, status: "stopped",
                  message: error.message, code: error.code)
    // Camera originals are never deleted. Unacknowledged downloaded files are
    // left intact so an already-running Dart copy can finish safely.
  }

  private func requireLiveCameraSession(
    _ sessionID: String?,
    result: @escaping FlutterResult
  ) -> LiveCameraSession? {
    guard let session = liveCameraSession, session.id == sessionID, session.armed,
          let camera = session.camera
    else {
      result(FlutterError(code: "LIVE_CAMERA_SESSION_ENDED",
                          message: "This live camera session has ended. Start a new connection.",
                          details: nil))
      return nil
    }
    guard connectedCameras.contains(where: { $0 === camera }), camera.hasOpenSession else {
      let error = FlutterError(
        code: "USB_CAMERA_DISCONNECTED",
        message: "The wired camera session was lost. Reconnect the camera and start live capture again.",
        details: nil
      )
      endLiveCameraSession(session, error: error, eventType: "disconnected")
      result(error)
      return nil
    }
    return session
  }

  private func collectLiveCameraFiles(
    _ session: LiveCameraSession,
    files: [ICCameraFile],
    preserveIdentity: Bool = false
  ) {
    guard liveCameraSession === session, session.armed, let index = session.index else { return }
    var added = false
    for file in files {
      let object = ObjectIdentifier(file)
      guard !session.removedObjects.contains(object) else { continue }
      let observation = index.observe(
        photoIdentity(file),
        preserveIdentity: preserveIdentity || session.observedObjects.contains(object)
      )
      session.observedObjects.insert(object)
      if index.isPending(observation.id) {
        session.files[observation.id] = file
        session.removedIDs.remove(observation.id)
      }
      added = added || observation.added
    }
    if added {
      emitLiveEvent(session, type: "photosAvailable")
    }
  }

  private func pendingLiveCameraImages(sessionID: String?, result: @escaping FlutterResult) {
    guard let session = requireLiveCameraSession(sessionID, result: result),
          let camera = session.camera, let index = session.index else { return }
    // This reconciles ImageCaptureCore's current catalogue, without closing and
    // reopening PTP or truncating the new-shot backlog to a fixed page size.
    collectLiveCameraFiles(session, files: cameraImageFiles(camera))
    result(index.pendingIDs.compactMap { id -> [String: Any]? in
      guard let file = session.files[id] else { return nil }
      return [
        "id": id,
        "name": file.originalFilename ?? file.name ?? "camera-image.jpg",
        "size": file.fileSize,
      ]
    })
  }

  private func downloadLiveCameraImage(
    sessionID: String?,
    imageID: String?,
    result: @escaping FlutterResult
  ) {
    guard let session = requireLiveCameraSession(sessionID, result: result),
          let camera = session.camera else { return }
    guard let imageID, session.index?.isPending(imageID) == true,
          let file = session.files[imageID], !session.removedIDs.contains(imageID) else {
      result(FlutterError(code: "CAMERA_FILES_MISSING",
                          message: "This photo is no longer available on the camera.",
                          details: nil))
      return
    }
    if let cached = session.downloadedFiles[imageID],
       let path = cached["path"], isCompleteCameraDownload(path: path, file: file) {
      result(cached)
      return
    }
    guard !cameraDownloadInProgress else {
      result(FlutterError(code: "LIVE_CAMERA_BUSY",
                          message: "The previous camera photo is still transferring.", details: nil))
      return
    }
    guard !cameraAccessRestricted.contains(ObjectIdentifier(camera)) else {
      result(FlutterError(code: "CAMERA_DEVICE_LOCKED",
                          message: "Allow access on the camera, then retry this photo.", details: nil))
      return
    }

    let transferToken = UUID()
    liveDownloadToken = transferToken
    cameraDownloadInProgress = true
    var completed = false
    var cancellationRequested = false
    let finish: (Any?) -> Void = { [weak self] payload in
      guard !completed else { return }
      completed = true
      if self?.liveDownloadToken == transferToken {
        self?.liveDownloadToken = nil
        self?.cameraDownloadInProgress = false
        self?.cameraDownloadProgress = nil
        self?.cancelLiveCameraDownload = nil
      }
      result(payload)
    }
    cancelLiveCameraDownload = { [weak self] in
      cancellationRequested = true
      if self?.liveDownloadToken == transferToken {
        self?.cameraDownloadProgress?.cancel()
      }
      // Cancellation can race a successful native transfer whose callback is
      // already enqueued. Let that callback publish a complete file under its
      // original token, so Dart can finish saving it to the original event.
    }
    downloadCameraFiles(
      [(camera, file)], at: 0, downloaded: [],
      shouldContinue: { [weak self] in
        !completed && !cancellationRequested && self?.liveCameraSession === session
      },
      allowCompletedAfterCancellation: true
    ) { value in
      guard !completed else { return }
      if let error = value as? FlutterError {
        // No acknowledgement is recorded: the next poll can retry a file that
        // was announced before the camera finished writing it.
        finish(error)
        return
      }
      guard var photo = (value as? [[String: String]])?.first else {
        finish(FlutterError(code: "CAMERA_IMPORT_FAILED",
                            message: "The camera has not finished sending this photo. It will be retried.",
                            details: nil))
        return
      }
      photo["id"] = imageID
      session.downloadedFiles[imageID] = photo
      finish(photo)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
      guard !completed else { return }
      let error = FlutterError(
        code: cancellationRequested ? "LIVE_CAMERA_CANCELLED" : "LIVE_CAMERA_DOWNLOAD_TIMEOUT",
        message: cancellationRequested
          ? "Camera transfer stopped without a completed file. The original remains on the camera."
          : "The camera stopped responding during a photo transfer. Its original is safe; reconnect and retry.",
        details: nil
      )
      if let self, self.liveCameraSession === session {
        self.endLiveCameraSession(session, error: error)
      } else if self?.liveDownloadToken == transferToken {
        self?.cameraDownloadProgress?.cancel()
      }
      // This also resolves a driver that never calls back after cancellation.
      // Ownership checks in finish prevent a late callback touching a new run.
      finish(error)
    }
  }

  private func acknowledgeLiveCameraImages(
    sessionID: String?,
    ids: [String],
    result: @escaping FlutterResult
  ) {
    guard let session = liveCameraSession, session.id == sessionID, session.armed else {
      result(false)
      return
    }
    let acknowledged = Set(ids)
    session.index?.acknowledge(acknowledged)
    for id in acknowledged {
      session.files[id] = nil
      session.removedIDs.remove(id)
      session.downloadedFiles[id] = nil
    }
    result(true)
  }

  private func requestCameraSession(_ camera: ICCameraDevice) {
    let key = ObjectIdentifier(camera)
    requestedCameraSessions.insert(key)
    guard ptpTetherReleases[key] == nil else { return }
    guard !camera.hasOpenSession, !openingCameraSessions.contains(key),
          !closingCameraSessions.contains(key) else { return }
    readyCameras.remove(key)
    openingCameraSessions.insert(key)
    camera.requestOpenSession()
  }

  private func closeCameraSession(_ camera: ICCameraDevice) {
    // Manual import and the legacy receiver share the same native session.
    // Use a completion with an exact owner here too: an anonymous old delegate
    // callback must never clear a later close/open operation's state.
    releasePtpCameraSession(camera, sessionID: "camera-close:\(UUID().uuidString)", completion: nil)
  }

  private func imageFiles(in items: [ICCameraItem]) -> [ICCameraFile] {
    var files: [ICCameraFile] = []
    var visited: Set<ObjectIdentifier> = []
    var remaining = items
    while let item = remaining.popLast() {
      guard visited.insert(ObjectIdentifier(item)).inserted else { continue }
      if let file = item as? ICCameraFile, isCameraImageFile(file) {
        files.append(file)
      } else if let folder = item as? ICCameraFolder {
        remaining.append(contentsOf: folder.contents ?? [])
      }
    }
    return files.sorted {
      ($0.fileCreationDate ?? .distantPast) < ($1.fileCreationDate ?? .distantPast)
    }
  }

  private func cameraImageFiles(_ camera: ICCameraDevice) -> [ICCameraFile] {
    imageFiles(in: camera.mediaFiles ?? camera.contents ?? [])
  }

  private func cameraFileId(_ camera: ICCameraDevice, _ file: ICCameraFile) -> String {
    let identity = photoIdentity(file)
    let created = identity.createdMilliseconds.map { String($0) } ?? "unknown"
    return "\(cameraIdentity(camera))|\(identity.handle)|\(identity.name)|\(created)"
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
    let key = ObjectIdentifier(camera)
    return camera.hasOpenSession && !closingCameraSessions.contains(key) &&
      !openingCameraSessions.contains(key) &&
      (readyCameras.contains(key) || camera.contentCatalogPercentCompleted >= 100)
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
      for file in cameraImageFiles(camera) {
        files.append((camera, file))
      }
    }
    return files.sorted {
      ($0.1.fileCreationDate ?? .distantPast) > ($1.1.fileCreationDate ?? .distantPast)
    }
  }

  private func listConnectedCameraDevices(result: @escaping FlutterResult) {
    ensureCameraContentsAccess { [weak self] access in
      guard let self else { return }
      guard access.allowsContentsAccess else {
        result(access.flutterError)
        return
      }
      self.waitForCameraDevice(timeout: 6) { [weak self] in
        guard let self else { return }
        result(self.connectedCameras.map { camera in
          let id = self.cameraIdentity(camera)
          let name = camera.name ?? "Connected camera"
          return [
            "id": id,
            "name": name,
            "hasPermission": true,
            "directSupported": true,
            "physicalShutter": self.physicalShutterCapability(camera),
            "liveSessionActive": self.isLiveCameraReceiving(camera),
          ] as [String: Any]
        })
      }
    }
  }

  /// Discovery is passive: a cable check must not open a PTP import session.
  /// Inspect a catalogue only when an explicit live/import owner already opened
  /// it. Closed-session cached media must never imply that shooting is supported.
  private func cameraConnectionDiagnostics(result: @escaping FlutterResult) {
    ensureCameraContentsAccess { [weak self] access in
      guard let self else { return }
      let controlAuthorization: String
      if #available(iOS 14.0, *) {
        controlAuthorization = WiredCameraAuthorizationState(
          self.cameraBrowser.controlAuthorizationStatus
        ).rawValue
      } else {
        controlAuthorization = "not-required"
      }
      let finish: (String, String, [[String: Any]], Bool) -> Void = {
        status, message, cameras, discoveryOnly in
        result([
          "status": status,
          "message": message,
          "cameras": cameras,
          "totalImages": cameras.reduce(0) { $0 + ($1["imageCount"] as? Int ?? 0) },
          "discoveryOnly": discoveryOnly,
          "contentsAuthorization": access.rawValue,
          "controlAuthorization": controlAuthorization,
          "usbEnumerationAvailable": false,
          "connectionNote": self.wiredVisibilityNote,
        ] as [String: Any])
      }
      guard access.allowsContentsAccess else {
        finish(access.diagnosticStatus, access.message, [], true)
        return
      }

      self.waitForCameraDevice(timeout: 6) { [weak self] in
        guard let self else { return }
        guard !self.connectedCameras.isEmpty else {
          finish(
            "no-camera",
            "No compatible wired camera found. Check the data cable and adapter, and use the camera model's supported shooting mode for Live shooting.",
            [], true
          )
          return
        }

        let cameras: [[String: Any]] = self.connectedCameras.map { camera in
          let key = ObjectIdentifier(camera)
          let sessionRequested = self.requestedCameraSessions.contains(key)
          let sessionOpen = sessionRequested && camera.hasOpenSession &&
            !self.openingCameraSessions.contains(key) &&
            !self.closingCameraSessions.contains(key)
          return [
            "name": camera.name ?? "Connected camera",
            "id": self.cameraIdentity(camera),
            "sessionOpen": sessionOpen,
            "catalogReady": sessionOpen && self.isCameraCatalogReady(camera),
            "catalogProgress": sessionOpen ? camera.contentCatalogPercentCompleted : 0,
            "sessionError": self.ptpTetherReleases[key]?.failure?.message
              ?? (sessionRequested ? (self.cameraSessionErrors[key] ?? "") : ""),
            "releasePending": self.ptpTetherReleases[key] != nil,
            "transportType": camera.transportType ?? "unknown",
            "usbVendorId": Int(camera.usbVendorID),
            "usbProductId": Int(camera.usbProductID),
            "wiredConfirmed": self.hasWiredCameraEvidence(camera),
            "imageCount": sessionOpen ? self.cameraImageFiles(camera).count : 0,
            "physicalShutter": self.physicalShutterCapability(camera),
            "supportsCapture": camera.capabilities.contains(
              ICDeviceCapability.cameraDeviceCanTakePicture.rawValue
            ),
            "capabilities": camera.capabilities,
            "liveSessionActive": self.isLiveCameraReceiving(camera),
            "livePendingImages": self.liveCameraSession?.camera === camera
              ? (self.liveCameraSession?.index?.pendingIDs.count ?? 0) : 0,
            "livePTPEvents": self.liveCameraSession?.camera === camera
              ? (self.liveCameraSession?.ptpEventCount ?? 0)
              : (self.ptpTetherSession?.camera === camera ? (self.ptpTetherSession?.ptpEventCount ?? 0) : 0),
          ] as [String: Any]
        }
        let openCameras = cameras.filter { $0["sessionOpen"] as? Bool == true }
        let discoveryOnly = openCameras.isEmpty
        let liveSession = self.liveCameraSession
        let locked = self.connectedCameras.contains { camera in
          let key = ObjectIdentifier(camera)
          return self.requestedCameraSessions.contains(key) &&
            self.cameraAccessRestricted.contains(key)
        }
        let opening = self.connectedCameras.contains {
          self.requestedCameraSessions.contains(ObjectIdentifier($0)) &&
            self.openingCameraSessions.contains(ObjectIdentifier($0))
        }
        let sessionIssue = self.connectedCameras.compactMap { camera -> String? in
          let key = ObjectIdentifier(camera)
          guard self.requestedCameraSessions.contains(key) else { return nil }
          return self.cameraSessionErrors[key]
        }.first
        let count = openCameras.reduce(0) { $0 + ($1["imageCount"] as? Int ?? 0) }

        if let releaseError = self.pendingPtpReleaseError() {
          finish(releaseError.code, releaseError.message ?? "Camera release is not confirmed.", cameras, true)
        } else if locked {
          finish(
            "camera-locked",
            "The camera restricted access to its photos. Unlock it or approve its access prompt, then retry.",
            cameras, discoveryOnly
          )
        } else if let liveSession,
                  cameras.contains(where: { $0["liveSessionActive"] as? Bool == true }) {
          // An empty card is a valid live session waiting for its first shot.
          finish("live-ready", self.liveCameraMessage(liveSession.camera), cameras, discoveryOnly)
        } else if let tether = self.ptpTetherSession, tether.transport?.closed == false,
                  cameras.contains(where: { $0["liveSessionActive"] as? Bool == true }) {
          finish(
            "live-ready",
            "The camera tether connection is active. Camera transfers shows its current shooting setup and received photos.",
            cameras, discoveryOnly
          )
        } else if opening {
          finish(
            "catalog-loading",
            "The requested camera session is still opening. Keep the camera awake.",
            cameras, discoveryOnly
          )
        } else if discoveryOnly, let sessionIssue {
          finish("session-failed", sessionIssue, cameras, true)
        } else if discoveryOnly {
          finish(
            "camera-detected",
            "Camera detected. This check has not opened a photo-transfer session. Start Live shooting and take a test photo to check that the physical shutter remains usable.",
            cameras, true
          )
        } else if openCameras.contains(where: { $0["catalogReady"] as? Bool != true }) {
          finish(
            "catalog-loading",
            "The active camera session is still loading its photo list.",
            cameras, false
          )
        } else if count == 0 {
          finish(
            "empty-media",
            "The active camera session has no supported stored photos. An empty card can still receive new shots during Live shooting.",
            cameras, false
          )
        } else {
          finish(
            "ready",
            "The active camera session has \(count) stored image(s) available for import.",
            cameras, false
          )
        }
      }
    }
  }

  private func listConnectedCameraImages(limit: Int?, result: @escaping FlutterResult) {
    if let releaseError = pendingPtpReleaseError() { result(releaseError); return }
    guard liveCameraSession == nil, ptpTetherSession == nil, !cameraDownloadInProgress else {
      result(FlutterError(code: "LIVE_CAMERA_BUSY",
                          message: "Stop live capture before browsing stored camera photos.",
                          details: nil))
      return
    }
    manualCameraSelectionActive = true
    let generation = manualCameraGeneration
    ensureCameraContentsAccess { [weak self] access in
      guard let self else { return }
      guard generation == self.manualCameraGeneration else {
        result(FlutterError(code: "CAMERA_OPERATION_CANCELLED", message: "Camera import cancelled.", details: nil))
        return
      }
      guard access.allowsContentsAccess else {
        result(access.flutterError)
        return
      }

      self.waitForCameraDevice(timeout: 6) { [weak self] in
        guard let self else { return }
        guard generation == self.manualCameraGeneration else {
          result(FlutterError(code: "CAMERA_OPERATION_CANCELLED", message: "Camera import cancelled.", details: nil))
          return
        }
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
          guard generation == self.manualCameraGeneration else {
            result(FlutterError(code: "CAMERA_OPERATION_CANCELLED", message: "Camera import cancelled.", details: nil))
            return
          }
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

    let waiterID = UUID()
    var finished = false
    let finish: () -> Void = { [weak self] in
      if finished { return }
      finished = true
      self?.cameraDeviceWaiters[waiterID] = nil
      completion()
    }
    cameraDeviceWaiters[waiterID] = finish
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
  }

  /// iOS requires explicit permission before an app can read a USB camera's files.
  /// Preserve unresolved and restricted results so callers can offer the right
  /// recovery. Only an authorized result permits a content session to open.
  private func ensureCameraContentsAccess(
    _ completion: @escaping (WiredCameraAuthorizationState) -> Void
  ) {
    if #available(iOS 14.0, *) {
      let current = WiredCameraAuthorizationState(cameraBrowser.contentsAuthorizationStatus)
      guard current == .pending else {
        completion(current)
        return
      }
      cameraBrowser.requestContentsAuthorization { status in
        DispatchQueue.main.async {
          completion(WiredCameraAuthorizationState(status))
        }
      }
      return
    }
    completion(.authorized)
  }

  /// A freshly plugged-in camera reports no files until its catalog is loaded.
  /// Wait (bounded) for every connected camera to become ready.
  private func waitForCameraCatalog(timeout: TimeInterval, _ completion: @escaping () -> Void) {
    let cameras: [ICCameraDevice]
    if let liveCamera = liveCameraSession?.camera {
      cameras = [liveCamera]
    } else {
      cameras = connectedCameras
    }
    let notReady = cameras.filter { !isCameraCatalogReady($0) }
    if notReady.isEmpty {
      completion()
      return
    }

    for camera in notReady {
      requestCameraSession(camera)
    }

    let waiterID = UUID()
    var finished = false
    let finish: () -> Void = { [weak self] in
      if finished { return }
      finished = true
      self?.cameraCatalogWaiters[waiterID] = nil
      completion()
    }
    cameraCatalogWaiters[waiterID] = (cameras: cameras, finish: finish)
    DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: finish)
  }

  private func flushCameraCatalogWaitersIfReady() {
    let completed = cameraCatalogWaiters.values.filter { waiter in
      waiter.cameras.allSatisfy { camera in
        isCameraCatalogReady(camera) || !connectedCameras.contains(where: { $0 === camera })
      }
    }
    completed.forEach { $0.finish() }
  }

  private func importConnectedCameraImages(ids: [String], result: @escaping FlutterResult) {
    if let releaseError = pendingPtpReleaseError() { result(releaseError); return }
    guard liveCameraSession == nil, ptpTetherSession == nil, !cameraDownloadInProgress else {
      result(FlutterError(code: "LIVE_CAMERA_BUSY",
                          message: "Wait for the current camera transfer or stop live capture.",
                          details: nil))
      return
    }
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
    cameraDownloadInProgress = true
    let generation = manualCameraGeneration
    var completed = false
    let finish: (Any?) -> Void = { [weak self] payload in
      guard !completed else { return }
      completed = true
      self?.cameraDownloadInProgress = false
      self?.cameraDownloadProgress = nil
      self?.cancelManualCameraDownload = nil
      result(payload)
    }
    cancelManualCameraDownload = { [weak self] in
      self?.cameraDownloadProgress?.cancel()
      finish(FlutterError(code: "CAMERA_OPERATION_CANCELLED",
                          message: "Camera import cancelled. Originals remain on the camera.",
                          details: nil))
    }
    downloadCameraFiles(
      files, at: 0, downloaded: [],
      shouldContinue: { [weak self] in
        guard let self else { return false }
        return !completed && generation == self.manualCameraGeneration &&
          self.liveCameraSession == nil && self.ptpTetherSession == nil
      }
    ) { [weak self] payload in
      guard !completed else { return }
      // Keep the session for the Dart batch's failed-file retry. Its enclosing
      // picker releases the manual session in a finally block.
      guard self != nil else { return }
      finish(payload)
    }
  }

  private func releaseCameraImportSession(result: @escaping FlutterResult) {
    if let releaseError = pendingPtpReleaseError() { result(releaseError); return }
    guard liveCameraSession == nil, ptpTetherSession == nil else { result(false); return }
    manualCameraGeneration += 1
    manualCameraSelectionActive = false
    let cancelDownload = cancelManualCameraDownload
    cancelManualCameraDownload = nil
    cancelDownload?()
    for camera in connectedCameras {
      closeCameraSession(camera)
    }
    // Complete canceled catalogue waits now, rather than leaving the old
    // platform-method future alive for its full timeout.
    let waiters = Array(cameraCatalogWaiters.values)
    waiters.forEach { $0.finish() }
    result(true)
  }

  private func isCompleteCameraDownload(path: String, file: ICCameraFile) -> Bool {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
          let size = (attributes[.size] as? NSNumber)?.int64Value,
          size > 0 else { return false }
    return file.fileSize <= 0 || size >= file.fileSize
  }

  private func downloadCameraFiles(
    _ files: [(ICCameraDevice, ICCameraFile)],
    at index: Int,
    downloaded: [[String: String]],
    failures: [String] = [],
    shouldContinue: @escaping () -> Bool = { true },
    allowCompletedAfterCancellation: Bool = false,
    result: @escaping FlutterResult
  ) {
    guard shouldContinue() || (allowCompletedAfterCancellation && index >= files.count) else {
      removeUnreturnedCameraDownloads(downloaded)
      result(FlutterError(code: "CAMERA_OPERATION_CANCELLED",
                          message: "Camera transfer cancelled.", details: nil))
      return
    }
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
    guard camera.hasOpenSession, requestedCameraSessions.contains(ObjectIdentifier(camera)),
          connectedCameras.contains(where: { $0 === camera }) else {
      if downloaded.isEmpty {
        result(FlutterError(code: "USB_CAMERA_DISCONNECTED",
                            message: "The camera session ended before this photo finished transferring.",
                            details: nil))
      } else {
        result(downloaded)
      }
      return
    }
    let imageId = cameraFileId(camera, file)
    let filename = sanitizeFilename(file.originalFilename ?? file.name ?? "camera-image.jpg")
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("camera_import", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      NSLog("[AirPix USB] Unable to create import folder for %@: %@", filename, String(describing: error))
      downloadCameraFiles(files, at: index + 1, downloaded: downloaded,
                          failures: failures + ["Unable to create the download folder: \(error.localizedDescription)"],
                          shouldContinue: shouldContinue,
                          allowCompletedAfterCancellation: allowCompletedAfterCancellation,
                          result: result)
      return
    }

    let options: [ICDownloadOption: Any] = [
      .downloadsDirectoryURL: directory,
      .saveAsFilename: filename,
      .overwrite: true,
      .deleteAfterSuccessfulDownload: false,
    ]
    cameraDownloadProgress = file.requestDownload(options: options) { [weak self] path, error in
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
          try? FileManager.default.removeItem(at: directory)
        } else {
          // ImageCaptureCore may supply an absolute path, a file URL, or a filename.
          let returnedURL = path.flatMap { URL(string: $0) }
          let resolvedPath: String = returnedURL?.isFileURL == true
            ? (returnedURL?.path ?? "")
            : (path?.hasPrefix("/") == true ? path! : directory.appendingPathComponent(path ?? filename).path)
          let fallback = directory.appendingPathComponent(filename).path
          let existing = [resolvedPath, fallback].first {
            !$0.isEmpty && self.isCompleteCameraDownload(path: $0, file: file)
          }
          if let existing {
            updated.append(["id": imageId, "path": existing, "name": filename])
          } else {
            NSLog("[AirPix USB] Camera download returned no file for %@ (path: %@)", filename, path ?? "nil")
            updatedFailures.append("\(filename): no complete, non-empty photo was saved; the camera may still be writing it")
            try? FileManager.default.removeItem(at: directory)
          }
        }
        self.downloadCameraFiles(files, at: index + 1, downloaded: updated,
                                 failures: updatedFailures, shouldContinue: shouldContinue,
                                 allowCompletedAfterCancellation: allowCompletedAfterCancellation,
                                 result: result)
      }
    }
  }

  private func removeUnreturnedCameraDownloads(_ photos: [[String: String]]) {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("camera_import", isDirectory: true).path + "/"
    for photo in photos {
      guard let path = photo["path"], path.hasPrefix(root) else { continue }
      try? FileManager.default.removeItem(atPath: path)
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
      // Discovery alone must not lock a camera into USB transfer mode. A
      // photographer explicitly starts a live session, manual import or test.

      let waiters = Array(self.cameraDeviceWaiters.values)
      self.cameraDeviceWaiters.removeAll()
      waiters.forEach { $0() }
    }
  }

  func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
    forgetCamera(device)
  }

  func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
    DispatchQueue.main.async {
      let key = ObjectIdentifier(device)
      self.openingCameraSessions.remove(key)
      guard let camera = device as? ICCameraDevice else { return }
      if let release = self.ptpTetherReleases[key] {
        // Stop won while the native open was pending. Do not arm a receiver;
        // the exact old owner must finish releasing this late-opened session.
        release.cameraStateChanged()
        return
      }
      guard let error else {
        NSLog("[AirPix USB] Opened camera session: %@", device.name ?? "Camera")
        self.cameraSessionRetries[key] = nil
        self.cameraSessionErrors[key] = nil
        guard self.requestedCameraSessions.contains(key) else {
          // A stop or permission-dialog cancellation can win the race with the
          // native open callback. Release that late session immediately.
          self.closeCameraSession(camera)
          return
        }
        if let session = self.ptpTetherSession, session.camera === camera {
          self.completePtpTetherOpenIfReady(session)
        }
        if let session = self.liveCameraSession, session.camera === camera {
          self.armLiveCameraSessionIfReady(session)
        }
        return
      }
      let nativeError = error as NSError
      let cameraName = camera.name ?? "USB camera"
      let isSony = camera.usbVendorID == 0x054c
      let reason = "\(cameraName): \(nativeError.localizedDescription) (\(nativeError.domain) \(nativeError.code))."
      NSLog("[AirPix USB] Failed to open session for %@: %@", cameraName, String(describing: error))
      self.cameraSessionErrors[key] = reason
      if let session = self.ptpTetherSession, session.camera === camera {
        self.endPtpTetherSession(session, error: FlutterError(
          code: isSony ? "SONY_CAMERA_SESSION_FAILED" : "CAMERA_SESSION_FAILED",
          message: reason,
          details: [
            "camera": cameraName,
            "transport": camera.transportType ?? "unknown",
            "vendorId": Int(camera.usbVendorID),
            "productId": Int(camera.usbProductID),
            "nativeDomain": nativeError.domain,
            "nativeCode": nativeError.code,
          ]
        ))
        return
      }
      // Retry only while an explicit owner still wants this session.
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let attempts = self.cameraSessionRetries[key] ?? 0
        guard attempts < 3,
              self.requestedCameraSessions.contains(key),
              self.connectedCameras.contains(where: { $0 === camera }),
              !camera.hasOpenSession else { return }
        self.cameraSessionRetries[key] = attempts + 1
        self.requestCameraSession(camera)
      }
    }
  }

  func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
    DispatchQueue.main.async {
      let key = ObjectIdentifier(device)
      guard let camera = device as? ICCameraDevice else { return }
      if let release = self.ptpTetherReleases[key] {
        self.readyCameras.remove(key)
        // The block callback carries the exact request identity. A delegate
        // notification may confirm actual closure, but cannot fail a newer
        // close merely because an old delegate callback arrived late.
        release.cameraStateChanged()
        return
      }
      if camera.hasOpenSession || self.openingCameraSessions.contains(key) {
        // A delayed duplicate from a completed release is not evidence that a
        // newly opened/opening owner lost its native session.
        return
      }
      self.readyCameras.remove(key)
      self.openingCameraSessions.remove(key)
      if let session = self.ptpTetherSession, session.camera === camera {
        self.endPtpTetherSession(session, error: FlutterError(
          code: "CAMERA_SESSION_ENDED", message: error?.localizedDescription ?? "The camera closed its tether connection. Reconnect to continue shooting.", details: nil
        ), eventType: "disconnected")
      }
      if let session = self.liveCameraSession, session.camera === camera {
        self.endLiveCameraSession(session, error: FlutterError(
          code: "LIVE_CAMERA_SESSION_ENDED",
          message: error?.localizedDescription ?? "The camera closed its USB session. Reconnect and start live capture again.",
          details: nil
        ), eventType: "disconnected")
      }
      self.requestedCameraSessions.remove(key)
    }
  }
  func didRemove(_ device: ICDevice) {
    forgetCamera(device)
  }

  private func forgetCamera(_ device: ICDevice) {
    DispatchQueue.main.async {
      self.connectedCameras.removeAll { $0 === device }
      if let session = self.ptpTetherSession, session.camera === device {
        self.endPtpTetherSession(session, error: FlutterError(
          code: "USB_CAMERA_DISCONNECTED", message: "Camera disconnected. Completed photos remain saved; reconnect to continue shooting.", details: nil
        ), eventType: "disconnected")
      }
      if let session = self.liveCameraSession, session.camera === device {
        self.endLiveCameraSession(session, error: FlutterError(
          code: "USB_CAMERA_DISCONNECTED",
          message: "Camera disconnected. Photos already saved on the phone remain queued; reconnect to continue shooting.",
          details: nil
        ), eventType: "disconnected")
      }
      self.readyCameras.remove(ObjectIdentifier(device))
      self.requestedCameraSessions.remove(ObjectIdentifier(device))
      self.openingCameraSessions.remove(ObjectIdentifier(device))
      self.closingCameraSessions.remove(ObjectIdentifier(device))
      self.cameraSessionRetries[ObjectIdentifier(device)] = nil
      self.cameraSessionErrors[ObjectIdentifier(device)] = nil
      self.cameraAccessRestricted.remove(ObjectIdentifier(device))
      self.ptpTetherReleases[ObjectIdentifier(device)]?.cameraStateChanged()
      self.flushCameraCatalogWaitersIfReady()
    }
  }

  func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
    DispatchQueue.main.async {
      let key = ObjectIdentifier(device)
      guard self.requestedCameraSessions.contains(key),
            !self.openingCameraSessions.contains(key),
            !self.closingCameraSessions.contains(key),
            device.hasOpenSession else { return }
      NSLog("[AirPix USB] Catalog ready: %@; media items: %d",
            device.name ?? "Camera", device.mediaFiles?.count ?? 0)
      self.readyCameras.insert(ObjectIdentifier(device))
      self.flushCameraCatalogWaitersIfReady()
      if let session = self.liveCameraSession, session.camera === device {
        self.armLiveCameraSessionIfReady(session)
      }
      if let session = self.ptpTetherSession, session.camera === device {
        // Cache exact framework objects for download fallback only. This never
        // establishes the live-shot baseline; raw/vendor PTP still owns that.
        for file in self.cameraImageFiles(device) where file.ptpObjectHandle > 0 {
          session.imageCaptureFiles[file.ptpObjectHandle] = file
        }
        self.emitPtpTetherEvent(session, type: "catalogReady")
      }
    }
  }

  func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
    DispatchQueue.main.async {
      let files = self.imageFiles(in: items)
      if let session = self.ptpTetherSession, session.camera === camera,
         self.isCameraCatalogReady(camera) {
        files.forEach { self.emitPtpCatalogHint(session, file: $0) }
      }
      if let session = self.liveCameraSession, session.camera === camera {
        self.collectLiveCameraFiles(session, files: files)
      }
    }
  }

  func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {
    DispatchQueue.main.async {
      let files = self.imageFiles(in: items)
      if let session = self.ptpTetherSession, session.camera === camera,
         self.isCameraCatalogReady(camera) {
        files.forEach { self.emitPtpCatalogRemoval(session, file: $0) }
      }
      guard let session = self.liveCameraSession, session.camera === camera,
            let index = session.index else { return }
      for file in files {
        for (id, pendingFile) in session.files where pendingFile === file {
          session.removedIDs.insert(id)
        }
        index.markRemoved(handle: self.photoIdentity(file).handle)
        session.observedObjects.remove(ObjectIdentifier(file))
        session.removedObjects.insert(ObjectIdentifier(file))
      }
    }
  }

  func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {
    DispatchQueue.main.async {
      let files = self.imageFiles(in: items)
      if let session = self.ptpTetherSession, session.camera === camera,
         self.isCameraCatalogReady(camera) {
        files.forEach { self.emitPtpCatalogHint(session, file: $0) }
      }
      if let session = self.liveCameraSession, session.camera === camera {
        self.collectLiveCameraFiles(session, files: files, preserveIdentity: true)
      }
    }
  }

  func cameraDevice(
    _ camera: ICCameraDevice,
    didReceiveMetadata metadata: [AnyHashable: Any]?,
    for item: ICCameraItem,
    error: Error?
  ) {
    guard error == nil else { return }
    DispatchQueue.main.async {
      let files = self.imageFiles(in: [item])
      if let session = self.ptpTetherSession, session.camera === camera,
         self.isCameraCatalogReady(camera) {
        files.forEach { self.emitPtpCatalogHint(session, file: $0) }
      }
      if let session = self.liveCameraSession, session.camera === camera {
        self.collectLiveCameraFiles(session, files: files)
      }
    }
  }

  func cameraDevice(
    _ camera: ICCameraDevice,
    didReceiveThumbnail thumbnail: CGImage?,
    for item: ICCameraItem,
    error: Error?
  ) {}

  func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
    DispatchQueue.main.async {
      guard let session = self.liveCameraSession, session.camera === camera, session.armed else { return }
      self.emitLiveEvent(session, type: "status", status: "waiting-for-shot",
                         message: self.liveCameraMessage(camera))
    }
  }

  func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
    DispatchQueue.main.async {
      self.cameraAccessRestricted.insert(ObjectIdentifier(device))
      NSLog("[AirPix USB] Photo access restricted by connected device: %@", device.name ?? "Camera")
      if let session = self.ptpTetherSession, session.camera === device {
        self.endPtpTetherSession(session, error: FlutterError(
          code: "CAMERA_DEVICE_LOCKED", message: "The camera restricted access. Unlock it or approve its access prompt, then reconnect.", details: nil
        ), eventType: "disconnected")
      }
      if let session = self.liveCameraSession, session.camera === device {
        self.emitLiveEvent(session, type: "error",
                           message: "The camera restricted photo access. Unlock it or approve access to continue.",
                           code: "CAMERA_DEVICE_LOCKED")
      }
    }
  }

  func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
    DispatchQueue.main.async {
      self.cameraAccessRestricted.remove(ObjectIdentifier(device))
      NSLog("[AirPix USB] Photo access restriction cleared: %@", device.name ?? "Camera")
      if let session = self.liveCameraSession, session.camera === device,
         let camera = session.camera {
        self.armLiveCameraSessionIfReady(session)
        self.collectLiveCameraFiles(session, files: self.cameraImageFiles(camera))
      }
    }
  }

  func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {
    // ImageCaptureCore remains the transport owner. The raw tether driver reads
    // vendor packets through the same token-scoped delegate; never replace this
    // with ptpEventHandler, which would suppress the delegate's events.
    guard eventData.count >= 8 else { return }
    DispatchQueue.main.async {
      if let session = self.ptpTetherSession, session.camera === camera,
         session.transport?.closed == false, PtpTetherCodec.validEvent(eventData) {
        session.ptpEventCount += 1
        self.emitPtpTetherEvent(session, type: "ptpEvent", data: eventData)
      }
      guard let session = self.liveCameraSession, session.camera === camera, session.armed else { return }
      session.ptpEventCount += 1
      self.collectLiveCameraFiles(session, files: self.cameraImageFiles(camera))
      // A PTP event may arrive just before the framework updates mediaFiles.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
        guard let self, self.liveCameraSession === session else { return }
        self.collectLiveCameraFiles(session, files: self.cameraImageFiles(camera))
      }
    }
  }
}
