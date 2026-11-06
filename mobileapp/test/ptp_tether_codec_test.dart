import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/ptp_tether_codec.dart';

void main() {
  group('standard PTP datasets', () {
    test(
      'DeviceInfo reads capabilities and camera identity at wire offsets',
      () {
        final info = PtpTetherCodec.decodeDeviceInfo(_deviceInfo());
        expect(info.standardVersion, 100);
        expect(info.vendorExtensionId, 11);
        expect(info.vendorExtensionVersion, 100);
        expect(info.operations, {0x1001, 0x9114, 0x9116});
        expect(info.events, {0x4002});
        expect(info.properties, {0xd11c});
        expect(info.imageFormats, {0x3801, 0xb111});
        expect(info.manufacturer, 'Canon');
        expect(info.model, 'EOS R8');
        expect(info.deviceVersion, '1');
        expect(info.serial, 'ABC');
        expect(() => info.operations.add(0x911b), throwsUnsupportedError);
      },
    );

    test('no prefix of a DeviceInfo packet is a successful discovery', () {
      final data = _deviceInfo();
      for (var end = 0; end < data.length; end++) {
        expect(
          () => PtpTetherCodec.decodeDeviceInfo(
            Uint8List.sublistView(data, 0, end),
          ),
          throwsFormatException,
          reason: 'truncation at byte $end',
        );
      }
      final forged = Uint8List.fromList(data);
      ByteData.sublistView(forged).setUint32(11, 0xffffffff, Endian.little);
      expect(
        () => PtpTetherCodec.decodeDeviceInfo(forged),
        throwsFormatException,
      );
    });

    test(
      'ObjectInfo uses the 52-byte fixed header and preserves raw dates',
      () {
        final data = _hex('''
        01 00 01 00  01 38  00 00  00 10 00 00  01 38
        20 00 00 00  40 00 00 00  30 00 00 00
        80 07 00 00  38 04 00 00  18 00 00 00
        02 00 00 00  00 00  00 00 00 00  2a 00 00 00
        0d 49 00 4d 00 47 00 5f 00 30 00 30 00 30 00 31 00
        2e 00 4a 00 50 00 47 00 00 00
        10 32 00 30 00 32 00 36 00 31 00 31 00 30 00 35 00
        54 00 31 00 32 00 30 00 30 00 30 00 30 00 00 00
        00 00
      ''');
        final info = PtpTetherCodec.decodeObjectInfo(data, handle: 7);
        expect(info.handle, 7);
        expect(info.storage, 0x10001);
        expect(info.format, 0x3801);
        expect(info.size, 4096);
        expect(info.parent, 2);
        expect(info.sequenceNumber, 42);
        expect(info.name, 'IMG_0001.JPG');
        expect(info.captureDate, '20261105T120000');
        expect(info.modificationDate, '');
        expect(
          () => PtpTetherCodec.decodeObjectInfo(
            Uint8List.sublistView(data, 0, data.length - 1),
          ),
          throwsFormatException,
        );
      },
    );

    test('handle arrays reject forged counts and trailing bytes', () {
      expect(
        PtpTetherCodec.decodeUint32Array(
          _hex('02 00 00 00 01 00 00 00 ff ff ff ff'),
        ),
        [1, 0xffffffff],
      );
      for (final bad in [
        'ff ff ff ff',
        '02 00 00 00 01 00 00 00',
        '00 00 00 00 00',
      ]) {
        expect(
          () => PtpTetherCodec.decodeUint32Array(_hex(bad)),
          throwsFormatException,
        );
      }
    });

    test('standard property enumerations retain type and access semantics', () {
      final property = PtpTetherCodec.decodeProperty(
        _hex('0f 50 04 00 01 64 00 c8 00 02 03 00 64 00 c8 00 90 01'),
      );
      expect(property.code, 0x500f);
      expect(property.type, 4);
      expect(property.writable, isTrue);
      expect(property.defaultValue, 100);
      expect(property.intValue, 200);
      expect(property.values, [100, 200, 400]);
      expect(
        () => PtpTetherCodec.decodeProperty(
          _hex('0f 50 04 00 01 64 00 c8 00 02 04 00 64 00 c8 00 90 01'),
        ),
        throwsFormatException,
      );
    });

    test(
      'signed property range and array value consume exact field widths',
      () {
        final range = PtpTetherCodec.decodeProperty(
          _hex('10 50 03 00 01 00 00 fe ff 01 f6 ff 0a 00 02 00'),
        );
        expect(range.current, -2);
        expect(range.min, -10);
        expect(range.max, 10);
        expect(range.step, 2);
        expect(
          PtpTetherCodec.decodeValue(0x4003, _hex('02 00 00 00 ff ff 34 12')),
          [-1, 0x1234],
        );
        expect(
          () => PtpTetherCodec.decodeValue(0x4003, _hex('ff ff ff ff')),
          throwsFormatException,
        );
      },
    );
  });

  group('typed values', () {
    test(
      'encodes signed and unsigned integers without narrowing or wrapping',
      () {
        expect(PtpTetherCodec.encodeValue(3, -2), _hex('fe ff'));
        expect(PtpTetherCodec.encodeValue(6, 0xffffffff), _hex('ff ff ff ff'));
        final large = BigInt.parse('18446744073709551615');
        expect(
          PtpTetherCodec.decodeValue(8, _hex('ff ff ff ff ff ff ff ff')),
          large,
        );
        expect(
          PtpTetherCodec.encodeValue(8, large),
          _hex('ff ff ff ff ff ff ff ff'),
        );
        expect(
          PtpTetherCodec.decodeValue(
            9,
            Uint8List.fromList(List.filled(16, 255)),
          ),
          BigInt.from(-1),
        );
        for (final pair in <(int, Object)>[
          (2, -1),
          (2, 256),
          (1, 128),
          (3, -32769),
          (6, 0x100000000),
          (2, true),
          (4, 17.0),
        ]) {
          expect(
            () => PtpTetherCodec.encodeValue(pair.$1, pair.$2),
            throwsArgumentError,
          );
        }
      },
    );

    test('PTP strings require their UTF-16 terminator', () {
      expect(PtpTetherCodec.decodeValue(0xffff, _hex('02 41 00 00 00')), 'A');
      expect(PtpTetherCodec.encodeValue(0xffff, 'A'), _hex('02 41 00 00 00'));
      expect(PtpTetherCodec.decodeValue(0xffff, _hex('00')), '');
      expect(
        () => PtpTetherCodec.decodeValue(0xffff, _hex('02 41 00 42 00')),
        throwsFormatException,
      );
      expect(
        () => PtpTetherCodec.encodeValue(0xffff, 'A\u0000B'),
        throwsArgumentError,
      );
      expect(
        () => PtpTetherCodec.encodeValue(0xffff, 'A' * 255),
        throwsArgumentError,
      );
    });

    test(
      'Canon property DATA is framed separately from normal typed values',
      () {
        expect(
          PtpTetherCodec.encodeCanonProperty(0xd11c, 2),
          _hex('0c 00 00 00 1c d1 00 00 02 00 00 00'),
        );
      },
    );
  });

  group('Sony extension datasets', () {
    test('extension version precedes two counted uint16 lists', () {
      final extension = PtpTetherCodec.decodeSonyExtensionInfo(
        _hex('2c 01 02 00 00 00 01 92 09 92 02 00 00 00 5a d2 01 c2'),
      );
      expect(extension.version, 0x12c);
      expect(extension.codes, {0x9201, 0x9209, 0xd25a, 0xc201});
    });

    test('parses priority, destination, readiness and selectable subset', () {
      final properties = PtpTetherCodec.decodeSonyProperties(
        _sonyProperties(),
        protocolVersion: 0x12c,
      );
      final priority = properties[0xd25a]!;
      expect(priority.current, 0);
      expect(priority.defaultValue, 1);
      expect(priority.type, 2);
      expect(priority.writable, isTrue);
      expect(priority.values, [0, 1]);
      final destination = properties[0xd222]!;
      expect(destination.type, 4);
      expect(destination.current, 17);
      expect(destination.values, [16, 17]);
      expect(destination.writable, isTrue);
      expect(properties[0xd215]!.current, 0x8001);
      expect(properties[0xd215]!.writable, isFalse);
    });

    test('old Sony enabled flag and protocol 3 access flag differ', () {
      final bytes = _hex('''
        01 00 00 00 00 00 00 00
        5a d2 02 00 00 01 01 00 02 02 00 00 01
      ''');
      expect(
        PtpTetherCodec.decodeSonyProperties(
          bytes,
          protocolVersion: 2,
        )[0xd25a]!.writable,
        isTrue,
      );
      expect(
        PtpTetherCodec.decodeSonyProperties(
          bytes,
          protocolVersion: 3,
        )[0xd25a]!.writable,
        isFalse,
      );
      final disabled = Uint8List.fromList(bytes)..[13] = 0;
      expect(
        PtpTetherCodec.decodeSonyProperties(
          disabled,
          protocolVersion: 2,
        )[0xd25a]!.writable,
        isFalse,
      );
    });

    test('every truncated Sony property dataset fails as a whole', () {
      final data = _sonyProperties();
      for (var end = 0; end < data.length; end++) {
        expect(
          () => PtpTetherCodec.decodeSonyProperties(
            Uint8List.sublistView(data, 0, end),
            protocolVersion: 3,
          ),
          throwsFormatException,
          reason: 'truncation at byte $end',
        );
      }
      expect(
        () => PtpTetherCodec.decodeSonyProperties(data, protocolVersion: 400),
        throwsFormatException,
      );
      final unsupportedType = Uint8List.fromList(data);
      unsupportedType[10] = 0;
      unsupportedType[11] = 0;
      expect(
        () => PtpTetherCodec.decodeSonyProperties(
          unsupportedType,
          protocolVersion: 3,
        ),
        throwsFormatException,
      );
    });

    test('a forged secondary list cannot consume the next property', () {
      final data = _sonyProperties();
      // Destination's secondary choices count is at byte 40.
      final forged = Uint8List.fromList(data);
      forged[40] = 0xff;
      expect(
        () => PtpTetherCodec.decodeSonyProperties(forged, protocolVersion: 3),
        throwsFormatException,
      );
    });
  });

  group('Canon event blocks', () {
    test('card and host events retain their distinct delivery semantics', () {
      final events = PtpTetherCodec.decodeCanonEvents(
        _hex('''
        2e 00 00 00 81 c1 00 00  07 00 00 00 01 00 01 00
        01 38 00 00 00 00 00 00 00 00 00 00 00 10 00 00
        02 00 00 00 00 00 00 00 41 2e 4a 50 47 00
        22 00 00 00 86 c1 00 00  09 00 00 00 01 38 00 00
        00 00 00 00 00 20 00 00 00 00 00 00 42 2e 4a 50 47 00
        08 00 00 00 00 00 00 00
      '''),
      );
      expect(events, hasLength(2));
      expect(events[0].kind, PtpTetherEventKind.objectAdded);
      expect(events[0].handle, 7);
      expect(events[0].storage, 0x10001);
      expect(events[0].size, 4096);
      expect(events[0].parent, 2);
      expect(events[0].name, 'A.JPG');
      expect(events[1].kind, PtpTetherEventKind.objectTransfer);
      expect(events[1].handle, 9);
      expect(events[1].storage, 0);
      expect(events[1].size, 8192);
      expect(events[1].name, 'B.JPG');
    });

    test(
      '64-bit variant never claims an uncertain low-word size is complete',
      () {
        final event = PtpTetherCodec.decodeCanonEvents(
          _hex('''
        32 00 00 00 a7 c1 00 00  07 00 00 00 01 00 01 00
        01 38 00 00 00 00 00 00 00 00 00 00 ff ff ff ff
        02 00 00 00 03 00 00 00 00 00 00 00 41 2e 4a 50 47 00
      '''),
        ).single;
        expect(event.handle, 7);
        expect(event.parent, 3);
        expect(event.name, 'A.JPG');
        expect(event.size, isNull);
        expect(event.requiresObjectInfo, isTrue);
      },
    );

    test(
      '64-bit host events use authoritative metadata instead of guessing a filename offset',
      () {
        final event = PtpTetherCodec.decodeCanonEvents(
          _hex('''
        1d 00 00 00 a9 c1 00 00 07 00 00 00
        ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff ff
      '''),
        ).single;
        expect(event.kind, PtpTetherEventKind.objectTransfer);
        expect(event.handle, 7);
        expect(event.storage, 0);
        expect(event.name, isNull);
        expect(event.size, isNull);
        expect(event.requiresObjectInfo, isTrue);
      },
    );

    test(
      'card destination comes from its value and supported-choice events',
      () {
        final events = PtpTetherCodec.decodeCanonEvents(
          _hex('''
        10 00 00 00 89 c1 00 00 1c d1 00 00 02 00 00 00
        20 00 00 00 8a c1 00 00 1c d1 00 00 03 00 00 00
        03 00 00 00 01 00 00 00 02 00 00 00 04 00 00 00
      '''),
        );
        expect(events.first.propertyCode, 0xd11c);
        expect(events.first.propertyValue, 2);
        expect(events.last.propertyValues, [1, 2, 4]);
        expect(events.last.kind, PtpTetherEventKind.propertyChoices);
      },
    );

    test('unknown property bytes are preserved without assuming a uint32', () {
      final event = PtpTetherCodec.decodeCanonEvents(
        _hex('0d 00 00 00 89 c1 00 00 ff d1 00 00 07'),
      ).single;
      expect(event.propertyCode, 0xd1ff);
      expect(event.propertyValue, isNull);
      expect(event.propertyData, [7]);
    });

    test('truncated event batch does not return its earlier valid event', () {
      for (final bad in [
        '07 00 00 00 89 c1 00 00',
        'ff ff ff ff 89 c1 00 00',
        '10 00 00 00 89 c1 00 00 1c d1 00 00 02 00 00 00 10 00',
        '14 00 00 00 8a c1 00 00 1c d1 00 00 03 00 00 00 ff ff ff ff',
        '08 00 00 00 00 00 00 00 01',
      ]) {
        expect(
          () => PtpTetherCodec.decodeCanonEvents(_hex(bad)),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('Nikon and USB events', () {
    test('legacy Nikon records have one 32-bit parameter', () {
      final events = PtpTetherCodec.decodeNikonEvents(
        _hex('02 00 02 40 2a 00 00 00 01 c1 01 00 ff ff'),
      );
      expect(events[0].kind, PtpTetherEventKind.objectAdded);
      expect(events[0].handle, 42);
      expect(events[1].kind, PtpTetherEventKind.objectTransfer);
      expect(events[1].handle, 0xffff0001);
    });

    test(
      'extended Nikon records preserve parameters and validate boundaries',
      () {
        final events = PtpTetherCodec.decodeNikonEvents(
          _hex('''
          02 00 00 00
          02 40 02 00 2a 00 00 00 01 00 01 00
          06 40 01 00 0f 50 00 00
        '''),
          extended: true,
        );
        expect(events[0].params, [42, 0x10001]);
        expect(events[1].propertyCode, 0x500f);
        for (final bad in [
          '01 00 00 00 02 40 06 00',
          '01 00 00 00 02 40 01 00 2a 00',
          '01 00 00 00 02 40 00 00',
          '00 00 00 00 00',
        ]) {
          expect(
            () => PtpTetherCodec.decodeNikonEvents(_hex(bad), extended: true),
            throwsFormatException,
          );
        }
      },
    );

    test(
      'vendor event collisions never turn modes or properties into photos',
      () {
        Uint8List event(int code) => Uint8List.fromList([
          16,
          0,
          0,
          0,
          4,
          0,
          code & 255,
          code >> 8,
          0,
          0,
          0,
          0,
          42,
          0,
          0,
          0,
        ]);
        final lumix = PtpTetherCodec.decodeUsbEvent(
          event(0xc108),
          vendorExtensionId: 28,
        );
        final om = PtpTetherCodec.decodeUsbEvent(
          event(0xc108),
          vendorExtensionId: 0xfffd,
        );
        expect(lumix.kind, PtpTetherEventKind.objectAdded);
        expect(lumix.handle, 42);
        expect(om.kind, PtpTetherEventKind.propertyChanged);
        expect(om.handle, isNull);
        for (final code in [0xc004, 0xc101, 0xc104]) {
          expect(
            PtpTetherCodec.decodeUsbEvent(
              event(code),
              vendorExtensionId: 0xfffd,
            ).handle,
            isNull,
          );
        }
        expect(
          PtpTetherCodec.decodeUsbEvent(
            event(0xc004),
            vendorExtensionId: 14,
          ).handle,
          42,
        );
        expect(
          PtpTetherCodec.decodeUsbEvent(
            event(0xc101),
            vendorExtensionId: 10,
          ).kind,
          PtpTetherEventKind.objectTransfer,
        );
        for (final code in [0xc004, 0xc101, 0xc108, 0xc201]) {
          expect(
            PtpTetherCodec.decodeUsbEvent(event(code)).kind,
            PtpTetherEventKind.unknown,
          );
        }
        for (final code in [0xc002, 0xc102]) {
          expect(
            PtpTetherCodec.decodeUsbEvent(
              event(code),
              vendorExtensionId: 0xfffd,
            ).handle,
            42,
          );
        }
      },
    );

    test('LUMIX target packets require exact type, field size and payload', () {
      final valid = _hex('91 00 00 08 02 00 00 00 02 00');
      expect(PtpTetherCodec.decodePanasonicCaptureTarget(valid), 2);
      for (final bad in [
        Uint8List.fromList(valid)..[0] = 0,
        Uint8List.fromList(valid)..[4] = 4,
        Uint8List.fromList(valid.take(9).toList()),
        Uint8List.fromList([...valid, 0]),
      ]) {
        expect(
          () => PtpTetherCodec.decodePanasonicCaptureTarget(bad),
          throwsFormatException,
        );
      }
    });

    test(
      'USB events require an exact event container, never DATA or RESPONSE',
      () {
        final bytes = _hex('10 00 00 00 04 00 02 40 ff ff ff ff 2a 00 00 00');
        expect(PtpTetherCodec.decodeUsbEvent(bytes).handle, 42);
        for (final type in [1, 2, 3]) {
          final wrong = Uint8List.fromList(bytes)..[4] = type;
          expect(
            () => PtpTetherCodec.decodeUsbEvent(wrong),
            throwsFormatException,
          );
        }
        expect(
          () => PtpTetherCodec.decodeUsbEvent(
            _hex('0c 00 00 00 04 00 02 40 ff ff ff ff'),
          ),
          throwsFormatException,
        );
      },
    );
  });
}

Uint8List _deviceInfo() => _hex('''
  64 00 0b 00 00 00 64 00 00 00 00
  03 00 00 00 01 10 14 91 16 91
  01 00 00 00 02 40
  01 00 00 00 1c d1
  01 00 00 00 01 38
  02 00 00 00 01 38 11 b1
  06 43 00 61 00 6e 00 6f 00 6e 00 00 00
  07 45 00 4f 00 53 00 20 00 52 00 38 00 00 00
  02 31 00 00 00
  04 41 00 42 00 43 00 00 00
''');

Uint8List _sonyProperties() => _hex('''
  03 00 00 00 00 00 00 00
  5a d2 02 00 01 01 01 00 02 02 00 00 01
  22 d2 04 00 01 01 01 00 11 00 02 03 00 01 00 10 00 11 00
  02 00 10 00 11 00
  15 d2 04 00 00 02 00 00 01 80 00
''');

Uint8List _hex(String source) => Uint8List.fromList(
  source
      .trim()
      .split(RegExp(r'\s+'))
      .map((byte) => int.parse(byte, radix: 16))
      .toList(),
);
