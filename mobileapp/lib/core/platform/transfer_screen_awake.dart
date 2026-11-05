import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Foreground transfer ownership is token-scoped so a late stop cannot release
/// the wake state belonging to a new camera session.
class TransferScreenAwake {
  static const _channel = MethodChannel('airpix/otg_picker');

  static Future<void> setEnabled(String owner, bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setTransferScreenAwake', {
        'owner': owner,
        'enabled': enabled,
      });
    } on MissingPluginException {
      debugPrint('This build cannot keep the camera transfer screen awake.');
    } on PlatformException catch (error) {
      debugPrint('Camera transfer screen wake state: ${error.code}');
    }
  }
}
