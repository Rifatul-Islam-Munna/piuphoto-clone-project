import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's next USB session preference. A running receiver keeps
/// its own frozen mode, so changing this preference never widens its scope.
class UsbCameraUploadModeStorage {
  UsbCameraUploadModeStorage._();

  static const _key = 'usb_camera_upload_mode_v1';

  static SharedPreferences get _prefs => getIt<SharedPreferences>();

  static LiveCameraUploadMode read() {
    // Unknown, missing or malformed values must never select the broader
    // existing-photo upload mode without the user's choice.
    return _prefs.get(_key) == LiveCameraUploadMode.existingAndNew.name
        ? LiveCameraUploadMode.existingAndNew
        : LiveCameraUploadMode.newShotsOnly;
  }

  static Future<void> save(LiveCameraUploadMode mode) async {
    final prefs = _prefs;
    final previous = read();
    try {
      final saved = await prefs.setString(_key, mode.name);
      if (!saved) {
        throw StateError('Could not save the USB photo selection');
      }
    } catch (_) {
      // SharedPreferences updates its cache before the platform write finishes.
      // Restore the prior choice even if the failed write changed that cache.
      try {
        await prefs.setString(_key, previous.name);
      } catch (_) {}
      rethrow;
    }
  }
}
