import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/ptp_shooting_safety.dart';

void main() {
  test(
    'live USB blocks remote shutter, UI lock and camera-original deletion',
    () {
      expect(PtpShootingSafety.forbiddenCommands.length, 10);
      for (final opcode in PtpShootingSafety.forbiddenCommands) {
        expect(PtpShootingSafety.isForbidden(opcode), isTrue);
        expect(
          () => PtpShootingSafety.requirePassive(opcode),
          throwsA(
            isA<PlatformException>()
                .having(
                  (error) => error.code,
                  'code',
                  'PTP_SHOOTING_COMMAND_BLOCKED',
                )
                .having(
                  (error) => error.details,
                  'details',
                  containsPair('opcode', opcode),
                ),
          ),
        );
      }
    },
  );

  test(
    'live USB still allows standard metadata/photo reads and vendor setup',
    () {
      for (final opcode in <int>[
        0x1001, // GetDeviceInfo
        0x1004, // GetStorageIDs
        0x1007, // GetObjectHandles
        0x1008, // GetObjectInfo
        0x1009, // GetObject (native streamed download)
        0x101b, // GetPartialObject
        0x9114, // EOS RemoteModeOn/Off (without UI lock)
        0x9115, // EOS EventMode
        0x9116, // EOS GetEvent
        0x90c2, // Nikon camera body control mode
        0x90c7, // Nikon GetEvent
        0x941c, // Nikon GetExtendedEvent
        0x9201, // Sony Connect
        0x9202, // Sony GetExtensionInfo
        0x9205, // Sony SetProperty
        0x9209, // Sony GetAllPropertyData
        0x1015, // GetDevicePropValue
      ]) {
        expect(PtpShootingSafety.isForbidden(opcode), isFalse);
        expect(() => PtpShootingSafety.requirePassive(opcode), returnsNormally);
      }
    },
  );
}
