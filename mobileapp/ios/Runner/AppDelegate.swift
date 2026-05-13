import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private let otgChannelName = "piuphoto/otg_picker"
  private let settingsChannelName = "piuphoto/device_settings"
  private var otgResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: otgChannelName,
        binaryMessenger: controller.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "pickImage" else {
          result(FlutterMethodNotImplemented)
          return
        }

        self?.pickExternalImage(result: result)
      }

      let settingsChannel = FlutterMethodChannel(
        name: settingsChannelName,
        binaryMessenger: controller.binaryMessenger
      )

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
          if success {
            result(nil)
          } else {
            result(FlutterError(code: "OPEN_SETTINGS_FAILED", message: "Unable to open settings", details: nil))
          }
        }
      }
    }

    return didFinish
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func pickExternalImage(result: @escaping FlutterResult) {
    if otgResult != nil {
      result(FlutterError(code: "PICK_IN_PROGRESS", message: "A file picker is already open", details: nil))
      return
    }

    otgResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.image], asCopy: true)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    window?.rootViewController?.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let result = otgResult else { return }
    otgResult = nil

    guard let url = urls.first else {
      result(nil)
      return
    }

    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let fileName = url.lastPathComponent.isEmpty ? "external-image.jpg" : url.lastPathComponent
      let target = FileManager.default.temporaryDirectory
        .appendingPathComponent("otg_\(Int(Date().timeIntervalSince1970 * 1000))_\(fileName)")

      if FileManager.default.fileExists(atPath: target.path) {
        try FileManager.default.removeItem(at: target)
      }

      try FileManager.default.copyItem(at: url, to: target)
      result([
        "path": target.path,
        "name": fileName,
      ])
    } catch {
      result(FlutterError(code: "PICK_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    otgResult?(nil)
    otgResult = nil
  }
}
