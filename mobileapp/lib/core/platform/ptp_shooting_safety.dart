import 'package:flutter/services.dart';

/// USB live receiving is observation-only. The photographer owns the
/// physical shutter; this app must never delete camera originals, initiate
/// a capture, or lock the camera's local controls.
///
/// Camera-specific *connection negotiation* opcodes are allowed, but the
/// following shutter/mode-locking and destructive commands are not.
/// This guard is mirrored at the iOS and Android PTP MethodChannel endpoints.
class PtpShootingSafety {
  const PtpShootingSafety._();

  static const Set<int> forbiddenCommands = <int>{
    0x100b, // Standard PTP DeleteObject
    0x100e, // InitiateCapture
    0x100f, // InitiateOpenCapture
    0x1010, // TerminateOpenCapture
    0x910f, // Canon EOS RemoteRelease
    0x911b, // Canon EOS UILock
    0x9128, // Canon EOS RemoteReleaseOn
    0x9129, // Canon EOS RemoteReleaseOff
    0x9151, // Canon EOS InitiateViewfinder
    0x9207, // Sony remote shutter / camera buttons
    0x1016, // Standard property writes (including shooting settings)
    0x9110, // Canon property writes
    0x9205, // Sony property writes
    0x9206, // Sony property writes
  };

  static bool isForbidden(int opcode) => forbiddenCommands.contains(opcode);

  static void requirePassive(int opcode) {
    if (!isForbidden(opcode)) return;
    throw PlatformException(
      code: 'PTP_SHOOTING_COMMAND_BLOCKED',
      message:
          'AirPix live USB only receives photos. The camera shutter, '
          'settings and local controls are not changed by this command.',
      details: <String, Object>{'opcode': opcode},
    );
  }
}
