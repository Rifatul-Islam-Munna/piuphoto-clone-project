import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/ptp_shooting_safety.dart';

void main() {
  test(
    'vendor commands require the matching USB identity and safe parameters',
    () {
      final approved = <(int, int, List<int>)>[
        (0x4a9, 0x9114, <int>[0x0]),
        (0x4a9, 0x9114, <int>[0x1]),
        (0x4a9, 0x9115, <int>[0x0]),
        (0x4a9, 0x9115, <int>[0x1]),
        (0x4a9, 0x9116, <int>[]),
        (0x4a9, 0x9127, <int>[0xd11c]),
        (0x4a9, 0x9117, <int>[0x2a]),
        (0x4a9, 0x9107, <int>[]),
        (0x4b0, 0x90c2, <int>[0x0]),
        (0x4b0, 0x90c7, <int>[]),
        (0x4b0, 0x941c, <int>[]),
        (0x54c, 0x9201, <int>[0x1, 0x0, 0x0]),
        (0x54c, 0x9201, <int>[0x2, 0x0, 0x0]),
        (0x54c, 0x9201, <int>[0x3, 0x0, 0x0]),
        (0x54c, 0x9202, <int>[0x12c, 0x1]),
        (0x54c, 0x9209, <int>[]),
        (0x4da, 0x940a, <int>[0x8000090]),
      ];
      for (final (vendor, opcode, params) in approved) {
        expect(
          PtpShootingSafety.isAllowed(opcode, vendorId: vendor, params: params),
          isTrue,
        );
        for (final other in [
          0,
          0x1234,
          0x04a9,
          0x04b0,
          0x054c,
          0x04cb,
          0x04da,
          0x33a2,
          0x0a17,
        ]) {
          if (other == vendor) continue;
          expect(
            PtpShootingSafety.isAllowed(
              opcode,
              vendorId: other,
              params: params,
            ),
            isFalse,
            reason: 'Vendor command must not cross protocols',
          );
        }
      }
      for (final (vendor, opcode, params) in <(int, int, List<int>)>[
        (0x4a9, 0x9114, <int>[]),
        (0x4a9, 0x9114, <int>[0x2]),
        (0x4a9, 0x9115, <int>[0x2]),
        (0x4a9, 0x9117, <int>[0x0]),
        (0x4a9, 0x9127, <int>[0xd1b0]),
        (0x4b0, 0x90c2, <int>[0x1]),
        (0x4b0, 0x90c2, <int>[]),
        (0x54c, 0x9201, <int>[0x1, 0x1, 0x0]),
        (0x54c, 0x9201, <int>[0x4, 0x0, 0x0]),
        (0x54c, 0x9202, <int>[]),
        (0x54c, 0x9209, <int>[0x1]),
      ]) {
        expect(
          PtpShootingSafety.isAllowed(opcode, vendorId: vendor, params: params),
          isFalse,
        );
      }
    },
  );

  test('unreviewed commands and data writes are denied for every camera', () {
    for (final vendor in [
      0,
      0x1234,
      0x04a9,
      0x04b0,
      0x054c,
      0x04cb,
      0x04da,
      0x33a2,
      0x0a17,
    ]) {
      for (final opcode in [
        0x1002,
        0x1003,
        0x90c0,
        0x90c1,
        0x920a,
        0x920b,
        0x9152,
        0x9999,
      ]) {
        expect(PtpShootingSafety.isAllowed(opcode, vendorId: vendor), isFalse);
      }
      expect(
        PtpShootingSafety.isAllowed(
          0x1009,
          vendorId: vendor,
          data: Uint8List.fromList([1]),
        ),
        isFalse,
      );
    }
  });

  test(
    'new vendor receivers allow only reads and a precisely scoped OM handshake',
    () {
      for (final vendor in [0x04da, 0x07b4, 0x33a2, 0x0a17, 0x25fb]) {
        for (final opcode in [
          0x9403,
          0x9404,
          0x940b,
          0x9412,
          0x9704,
          0x9107,
          0x910b,
          0x9481,
          0x9489,
          0x948c,
          0x94be,
        ]) {
          expect(
            PtpShootingSafety.isAllowed(opcode, vendorId: vendor),
            isFalse,
          );
        }
        expect(PtpShootingSafety.isAllowed(0x1009, vendorId: vendor), isTrue);
        expect(PtpShootingSafety.isAllowed(0x101b, vendorId: vendor), isTrue);
      }
      expect(
        PtpShootingSafety.isAllowed(
          0x940a,
          vendorId: 0x04da,
          params: [0x08000090],
        ),
        isTrue,
      );
      expect(PtpShootingSafety.isAllowed(0x940a, vendorId: 0x04da), isFalse);
      for (final vendor in [0x07b4, 0x33a2]) {
        for (final value in [1, 2]) {
          expect(
            PtpShootingSafety.isAllowed(
              0x1016,
              vendorId: vendor,
              params: [0xd052],
              data: Uint8List.fromList([value, 0]),
            ),
            isTrue,
          );
        }
        for (final bytes in [
          <int>[],
          [0, 0],
          [3, 0],
          [1],
          [1, 1],
          [1, 0, 0],
        ]) {
          expect(
            PtpShootingSafety.isAllowed(
              0x1016,
              vendorId: vendor,
              params: [0xd052],
              data: Uint8List.fromList(bytes),
            ),
            isFalse,
          );
        }
        expect(
          PtpShootingSafety.isAllowed(
            0x1016,
            vendorId: vendor,
            params: [0xd0dc],
            data: Uint8List.fromList([2, 0]),
          ),
          isFalse,
        );
      }
      expect(
        PtpShootingSafety.isAllowed(
          0x1016,
          vendorId: 0x04da,
          params: [0xd052],
          data: Uint8List.fromList([1, 0]),
        ),
        isFalse,
      );
    },
  );

  test(
    'live USB blocks remote shutter, UI lock and camera-original deletion',
    () {
      expect(
        PtpShootingSafety.forbiddenCommands,
        containsAll([0x1016, 0x9110, 0x9205, 0x9206]),
      );
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
        0x1015, // GetDevicePropValue
      ]) {
        expect(PtpShootingSafety.isForbidden(opcode), isFalse);
        expect(() => PtpShootingSafety.requirePassive(opcode), returnsNormally);
      }
    },
  );
}
