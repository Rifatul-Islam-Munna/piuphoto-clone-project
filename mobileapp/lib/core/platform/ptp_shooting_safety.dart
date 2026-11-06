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
    0x100f, // FormatStore
    0x1010, // ResetDevice
    0x100c, 0x100d, // SendObjectInfo / SendObject
    0x1011, 0x1012, 0x1013, // SelfTest / protection / PowerDown
    0x1017, 0x1018, // ResetDevicePropValue / TerminateOpenCapture
    0x1019, 0x101a, 0x101c, // Move / Copy / InitiateOpenCapture
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

  static const _readOperations = <int>{
    0x1001,
    0x1004,
    0x1005,
    0x1007,
    0x1008,
    0x1009,
    0x100a,
    0x1014,
    0x1015,
    0x101b,
  };

  static bool isAllowed(
    int opcode, {
    int vendorId = 0,
    List<int> params = const [],
    Uint8List? data,
  }) {
    final olympus = vendorId == 0x07b4 || vendorId == 0x33a2;
    // The only writable property exception is the reversible OM connection
    // handshake. Capture destination, settings and control buttons stay blocked.
    if (olympus && opcode == 0x1016) {
      return params.length == 1 &&
          params.single == 0xd052 &&
          data != null &&
          data.length == 2 &&
          (data[0] == 1 || data[0] == 2) &&
          data[1] == 0;
    }
    if (isForbidden(opcode) || (data != null && data.isNotEmpty)) return false;
    if (_readOperations.contains(opcode)) return true;
    // Default-deny vendor operations, including unknown USB identities.
    // A command number can mean a read on one brand and a mode change on another.
    bool exact(List<int> expected) {
      if (params.length != expected.length) return false;
      for (var i = 0; i < params.length; i++) {
        if (params[i] != expected[i]) return false;
      }
      return true;
    }

    switch (vendorId) {
      case 0x04a9: // Canon EOS: connection, events and transfer acknowledgement.
        return switch (opcode) {
          0x9114 || 0x9115 => exact([0]) || exact([1]),
          0x9116 => params.isEmpty,
          0x9127 => exact([0xd11c]),
          0x9117 =>
            params.length == 1 &&
                params.single > 0 &&
                params.single < 0xffffffff,
          0x9107 =>
            true, // Partial file read; native download validates ranges.
          _ => false,
        };
      case 0x04b0: // Nikon: body priority only, never host control.
        return (opcode == 0x90c2 && exact([0])) ||
            (const {0x90c7, 0x941c}.contains(opcode) && params.isEmpty);
      case 0x054c: // Sony: connect handshake and read-only queue inspection.
        return (opcode == 0x9201 &&
                (exact([1, 0, 0]) || exact([2, 0, 0]) || exact([3, 0, 0]))) ||
            (opcode == 0x9202 && exact([0x12c, 1])) ||
            (opcode == 0x9209 && params.isEmpty);
      case 0x04da:
        return opcode == 0x940a && exact([0x08000090]);
      default:
        return false;
    }
  }

  static void requirePassive(
    int opcode, {
    int vendorId = 0,
    List<int> params = const [],
    Uint8List? data,
  }) {
    if (isAllowed(opcode, vendorId: vendorId, params: params, data: data)) {
      return;
    }
    throw PlatformException(
      code: 'PTP_SHOOTING_COMMAND_BLOCKED',
      message:
          'This command is not approved for receiving photos from this '
          'camera. Receiving stops; AirPix will not switch USB modes.',
      details: <String, Object>{'opcode': opcode},
    );
  }
}
