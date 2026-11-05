import 'dart:convert';
import 'dart:typed_data';

/// Wire values and independently written parsers for USB PTP tethering.
///
/// Protocol facts were checked against libgphoto2 at commit
/// 26a57b27caeb865a6b1d415aa5a80b47837c9023 (ptp.h, ptp-pack.c, ptp.c):
/// https://github.com/gphoto/libgphoto2/tree/26a57b27caeb865a6b1d415aa5a80b47837c9023/camlibs/ptp2
/// No implementation from that LGPL project is incorporated here. Decoding a
/// capability does not establish that a camera supports physical-shutter use;
/// the session policy must check supported operations and verify mode changes.
abstract final class PtpTetherOperation {
  static const getDeviceInfo = 0x1001;
  static const openSession = 0x1002;
  static const closeSession = 0x1003;
  static const getStorageIds = 0x1004;
  static const getStorageInfo = 0x1005;
  static const getObjectHandles = 0x1007;
  static const getObjectInfo = 0x1008;
  static const getObject = 0x1009;
  static const getThumb = 0x100a;
  static const getPropertyDescription = 0x1014;
  static const getPropertyValue = 0x1015;
  static const setPropertyValue = 0x1016;
  static const getPartialObject = 0x101b;

  static const canonGetDeviceInfo = 0x9108;
  static const canonSetProperty = 0x9110;
  static const canonSetRemoteMode = 0x9114;
  static const canonSetEventMode = 0x9115;
  static const canonGetEvent = 0x9116;
  static const canonTransferComplete = 0x9117;
  static const canonCancelTransfer = 0x9118;

  static const nikonChangeCameraMode = 0x90c2;
  static const nikonGetEvent = 0x90c7;
  static const nikonGetEventEx = 0x941c;

  static const sonyConnect = 0x9201;
  static const sonyGetExtensionInfo = 0x9202;
  static const sonySetProperty = 0x9205;
  static const sonyGetAllProperties = 0x9209;
}

abstract final class PtpTetherPropertyCode {
  static const canonCaptureDestination = 0xd11c;
  static const fujiUsbMode = 0xd16e;
  static const sonyObjectInMemory = 0xd215;
  static const sonyStillImageStoreDestination = 0xd222;
  static const sonyPriorityMode = 0xd25a;
}

class PtpDeviceInfo {
  PtpDeviceInfo({
    required this.standardVersion,
    required this.vendorExtensionId,
    required this.vendorExtensionVersion,
    required this.vendorExtensionDescription,
    required this.functionalMode,
    required this.manufacturer,
    required this.model,
    required this.serial,
    required this.deviceVersion,
    required Set<int> operations,
    required Set<int> events,
    required Set<int> properties,
    required Set<int> captureFormats,
    required Set<int> imageFormats,
  }) : operations = Set.unmodifiable(operations),
       events = Set.unmodifiable(events),
       properties = Set.unmodifiable(properties),
       captureFormats = Set.unmodifiable(captureFormats),
       imageFormats = Set.unmodifiable(imageFormats);

  final int standardVersion;
  final int vendorExtensionId;
  final int vendorExtensionVersion;
  final String vendorExtensionDescription;
  final int functionalMode;
  final String manufacturer;
  final String model;
  final String serial;
  final String deviceVersion;
  final Set<int> operations;
  final Set<int> events;
  final Set<int> properties;
  final Set<int> captureFormats;
  final Set<int> imageFormats;
}

class PtpObjectInfo {
  const PtpObjectInfo({
    this.handle,
    required this.format,
    required this.size,
    required this.name,
    required this.captureDate,
    required this.modificationDate,
    required this.parent,
    required this.storage,
    this.protectionStatus = 0,
    this.sequenceNumber = 0,
  });

  final int? handle;
  final int format;
  final int size;
  final String name;
  // PTP dates do not always carry a timezone; preserve the camera's exact text.
  final String captureDate;
  final String modificationDate;
  final int parent;
  final int storage;
  final int protectionStatus;
  final int sequenceNumber;
}

class PtpProperty {
  PtpProperty({
    required this.code,
    required this.type,
    required this.writable,
    required this.current,
    required this.defaultValue,
    required this.form,
    List<Object> values = const [],
    this.min,
    this.max,
    this.step,
    this.getSet = 0,
    this.isEnabled,
  }) : values = List.unmodifiable(values);

  final int code;
  final int type;
  final bool writable;
  final Object current;
  final Object defaultValue;
  final int form;
  final List<Object> values;
  final Object? min;
  final Object? max;
  final Object? step;
  final int getSet;
  final int? isEnabled;

  int? get intValue => current is int ? current as int : null;
}

class SonyExtensionInfo {
  SonyExtensionInfo({required this.version, required Set<int> codes})
    : codes = Set.unmodifiable(codes);

  final int version;
  final Set<int> codes;
}

enum PtpTetherEventKind {
  objectAdded,
  objectTransfer,
  objectRemoved,
  propertyChanged,
  propertyChoices,
  unknown,
}

class PtpTetherEvent {
  PtpTetherEvent({
    required this.code,
    required this.kind,
    List<int> params = const [],
    this.handle,
    this.name,
    this.size,
    this.format,
    this.storage,
    this.parent,
    this.propertyCode,
    this.propertyValue,
    List<int> propertyValues = const [],
    Uint8List? propertyData,
    this.requiresObjectInfo = false,
  }) : params = List.unmodifiable(params),
       propertyValues = List.unmodifiable(propertyValues),
       propertyData = propertyData == null
           ? null
           : Uint8List.fromList(propertyData).asUnmodifiableView();

  final int code;
  final PtpTetherEventKind kind;
  final List<int> params;
  final int? handle;
  final String? name;
  final int? size;
  final int? format;
  final int? storage;
  final int? parent;
  final int? propertyCode;
  final int? propertyValue;
  final List<int> propertyValues;
  final Uint8List? propertyData;
  final bool requiresObjectInfo;
}

/// Parsers take a DATA payload, except [decodeUsbEvent], which takes a complete
/// USB event container. Every count and field is bounded before it is read.
abstract final class PtpTetherCodec {
  static PtpDeviceInfo decodeDeviceInfo(Uint8List bytes) {
    final reader = _Reader(bytes);
    final version = reader.u16();
    final vendorId = reader.u32();
    final vendorVersion = reader.u16();
    final vendorDescription = reader.string();
    final mode = reader.u16();
    final operations = reader.u16Array().toSet();
    final events = reader.u16Array().toSet();
    final properties = reader.u16Array().toSet();
    final captures = reader.u16Array().toSet();
    final images = reader.u16Array().toSet();
    final manufacturer = reader.string();
    final model = reader.string();
    final deviceVersion = reader.string();
    final serial = reader.string();
    reader.finish();
    return PtpDeviceInfo(
      standardVersion: version,
      vendorExtensionId: vendorId,
      vendorExtensionVersion: vendorVersion,
      vendorExtensionDescription: vendorDescription,
      functionalMode: mode,
      manufacturer: manufacturer,
      model: model,
      serial: serial,
      deviceVersion: deviceVersion,
      operations: operations,
      events: events,
      properties: properties,
      captureFormats: captures,
      imageFormats: images,
    );
  }

  static PtpObjectInfo decodeObjectInfo(Uint8List bytes, {int? handle}) {
    final reader = _Reader(bytes);
    final storage = reader.u32();
    final format = reader.u16();
    final protection = reader.u16();
    final size = reader.u32();
    // Thumbnail, image dimensions, and bit depth precede ParentObject.
    reader.skip(26);
    final parent = reader.u32();
    reader.skip(6); // AssociationType and AssociationDesc.
    final sequence = reader.u32();
    final name = reader.string();
    final captured = reader.string();
    final modified = reader.string();
    reader.string(); // Keywords.
    reader.finish();
    return PtpObjectInfo(
      handle: handle,
      format: format,
      size: size,
      name: name,
      captureDate: captured,
      modificationDate: modified,
      parent: parent,
      storage: storage,
      protectionStatus: protection,
      sequenceNumber: sequence,
    );
  }

  static List<int> decodeUint32Array(Uint8List bytes) {
    final reader = _Reader(bytes);
    final count = reader.u32();
    reader.checkCount(count, 4);
    final values = List<int>.generate(count, (_) => reader.u32());
    reader.finish();
    return List.unmodifiable(values);
  }

  static PtpProperty decodeProperty(Uint8List bytes) {
    final reader = _Reader(bytes);
    final property = _property(reader);
    reader.finish();
    return property;
  }

  static Object decodeValue(int type, Uint8List bytes) {
    final reader = _Reader(bytes);
    final value = reader.value(type);
    reader.finish();
    return value;
  }

  static SonyExtensionInfo decodeSonyExtensionInfo(Uint8List bytes) {
    final reader = _Reader(bytes);
    final version = reader.u16();
    final codes = <int>{...reader.u16Array(), ...reader.u16Array()};
    reader.finish();
    return SonyExtensionInfo(version: version, codes: codes);
  }

  static Map<int, PtpProperty> decodeSonyProperties(
    Uint8List bytes, {
    required int protocolVersion,
  }) {
    final version = switch (protocolVersion) {
      2 || 0xc8 => 2,
      3 || 0x12c => 3,
      _ => throw const FormatException('Unsupported Sony property version'),
    };
    final reader = _Reader(bytes);
    final count = reader.u32();
    reader.u32(); // Reserved header word, not another property count.
    reader.checkCount(count, 9); // Smallest record: 6 + 1 + 1 + 1.
    final result = <int, PtpProperty>{};
    for (var index = 0; index < count; index++) {
      final property = _property(reader, sonyVersion: version);
      if (result.containsKey(property.code)) {
        throw const FormatException('Duplicate Sony property');
      }
      result[property.code] = property;
    }
    reader.finish();
    return Map.unmodifiable(result);
  }

  static PtpProperty _property(_Reader reader, {int? sonyVersion}) {
    final code = reader.u16();
    if (sonyVersion != null && (code & 0x7000) != 0x5000) {
      throw const FormatException('Invalid Sony property code');
    }
    final type = reader.u16();
    final getSet = reader.u8();
    final isEnabled = sonyVersion == null ? null : reader.u8();
    final defaultValue = reader.value(type);
    final current = reader.value(type);
    final form = reader.u8();
    Object? min;
    Object? max;
    Object? step;
    var values = <Object>[];
    switch (form) {
      case 0:
        break;
      case 1:
        min = reader.value(type);
        max = reader.value(type);
        step = reader.value(type);
      case 2:
        values = reader.enumeration(type);
      default:
        throw const FormatException('Unknown property form');
    }
    // Newer Sony records append the currently selectable subset. A following
    // property starts with 0x5xxx/0xdxxx, never a small enumeration count.
    if (sonyVersion != null &&
        form == 2 &&
        reader.remaining >= 2 &&
        reader.peekU16() < 0x200) {
      values = reader.enumeration(type);
    }
    final bool writable;
    if (sonyVersion == null) {
      if (getSet != 0 && getSet != 1) {
        throw const FormatException('Invalid standard property access flag');
      }
      writable = getSet == 1;
    } else if (sonyVersion == 2) {
      writable = (getSet & 0x80) != 0 || isEnabled == 1;
    } else {
      writable = isEnabled == 1 && (getSet == 1 || (getSet & 0x80) != 0);
    }
    return PtpProperty(
      code: code,
      type: type,
      writable: writable,
      current: current,
      defaultValue: defaultValue,
      form: form,
      values: values,
      min: min,
      max: max,
      step: step,
      getSet: getSet,
      isEnabled: isEnabled,
    );
  }

  static Uint8List encodeValue(int type, Object value) {
    final builder = BytesBuilder(copy: false);
    _writeValue(builder, type, value);
    return builder.takeBytes();
  }

  /// Canon SetDevicePropValueEx has its own DATA framing and no parameters.
  static Uint8List encodeCanonProperty(int code, int value) {
    return Uint8List.fromList([
      ...encodeValue(6, 12),
      ...encodeValue(6, code),
      ...encodeValue(6, value),
    ]);
  }

  static List<PtpTetherEvent> decodeCanonEvents(Uint8List bytes) {
    final reader = _Reader(bytes);
    final events = <PtpTetherEvent>[];
    while (reader.remaining > 0) {
      reader.require(8);
      final length = reader.peekU32();
      if (length < 8) {
        throw const FormatException('Invalid Canon event block length');
      }
      final block = _Reader(reader.take(length));
      block.u32();
      final code = block.u32();
      if (code == 0) {
        if (length != 8 || reader.remaining != 0) {
          throw const FormatException('Invalid Canon event terminator');
        }
        break;
      }
      switch (code) {
        case 0xc181: // ObjectAddedEx: card object.
        case 0xc1a7: // ObjectAddedEx64: use authoritative ObjectInfo for size.
          final handle = block.u32();
          final storage = block.u32();
          final format = block.u16();
          block.skip(10);
          final sizeHint = block.u32();
          if (code == 0xc1a7) block.skip(4);
          final parent = block.u32();
          block.skip(4);
          final name = block.cString();
          events.add(
            PtpTetherEvent(
              code: code,
              kind: PtpTetherEventKind.objectAdded,
              handle: handle,
              params: [handle],
              storage: storage,
              format: format,
              size: code == 0xc181 ? sizeHint : null,
              parent: parent,
              name: name,
              requiresObjectInfo: true,
            ),
          );
        case 0xc186: // RequestObjectTransfer: host/RAM object.
          final handle = block.u32();
          final format = block.u16();
          block.skip(6);
          final sizeHint = block.u32();
          block.skip(4);
          final name = block.cString();
          events.add(
            PtpTetherEvent(
              code: code,
              kind: PtpTetherEventKind.objectTransfer,
              handle: handle,
              params: [handle],
              format: format,
              size: sizeHint,
              storage: 0,
              parent: 0,
              name: name,
              requiresObjectInfo: true,
            ),
          );
        case 0xc1a9: // RequestObjectTransfer64.
        case 0xc1b8: // RequestObjectTransfer64LFN.
          // The reference marks these 64-bit metadata layouts as incomplete.
          // Only the common handle is needed; fetch authoritative ObjectInfo.
          block.require(code == 0xc1a9 ? 21 : 29);
          final handle = block.u32();
          events.add(
            PtpTetherEvent(
              code: code,
              kind: PtpTetherEventKind.objectTransfer,
              handle: handle,
              params: [handle],
              storage: 0,
              parent: 0,
              requiresObjectInfo: true,
            ),
          );
        case 0xc182:
          final handle = block.u32();
          events.add(
            PtpTetherEvent(
              code: code,
              kind: PtpTetherEventKind.objectRemoved,
              handle: handle,
              params: [handle],
            ),
          );
        case 0xc189:
          final property = block.u32();
          final data = block.take(block.remaining);
          // EOS properties do not carry a type tag. Only decode the property
          // whose UINT32 layout this adapter actually needs and knows.
          final value =
              property == PtpTetherPropertyCode.canonCaptureDestination
              ? _decodeCanonDestination(data)
              : null;
          events.add(
            PtpTetherEvent(
              code: code,
              kind: PtpTetherEventKind.propertyChanged,
              propertyCode: property,
              propertyValue: value,
              propertyData: data,
            ),
          );
        case 0xc18a:
          final property = block.u32();
          final listType = block.u32();
          final count = block.u32();
          final data = block.take(block.remaining);
          var values = <int>[];
          if (listType == 3) _Reader(data).checkCount(count, 4);
          if (property == PtpTetherPropertyCode.canonCaptureDestination &&
              listType == 3) {
            final choices = _Reader(data);
            choices.checkCount(count, 4);
            values = List.generate(count, (_) => choices.u32());
            choices.finish();
          }
          events.add(
            PtpTetherEvent(
              code: code,
              kind: PtpTetherEventKind.propertyChoices,
              propertyCode: property,
              propertyValues: values,
              propertyData: data,
            ),
          );
        default:
          events.add(
            PtpTetherEvent(code: code, kind: PtpTetherEventKind.unknown),
          );
      }
    }
    return List.unmodifiable(events);
  }

  static int _decodeCanonDestination(Uint8List data) {
    final reader = _Reader(data);
    final value = reader.u32();
    reader.finish();
    return value;
  }

  static List<PtpTetherEvent> decodeNikonEvents(
    Uint8List bytes, {
    bool extended = false,
  }) {
    final reader = _Reader(bytes);
    final count = reader.u16();
    if (extended) reader.u16();
    reader.checkCount(count, extended ? 4 : 6);
    final events = <PtpTetherEvent>[];
    for (var index = 0; index < count; index++) {
      final code = reader.u16();
      final paramCount = extended ? reader.u16() : 1;
      if (paramCount > 5) {
        throw const FormatException('Too many Nikon event parameters');
      }
      reader.checkCount(paramCount, 4);
      final params = List<int>.generate(paramCount, (_) => reader.u32());
      events.add(_standardEvent(code, params));
    }
    reader.finish();
    return List.unmodifiable(events);
  }

  static PtpTetherEvent decodeUsbEvent(Uint8List bytes) {
    final reader = _Reader(bytes);
    final length = reader.u32();
    if (length != bytes.length || length < 12 || (length - 12) % 4 != 0) {
      throw const FormatException('Invalid USB PTP event length');
    }
    if (reader.u16() != 4) {
      throw const FormatException('PTP container is not an event');
    }
    final code = reader.u16();
    reader.u32(); // Transaction ID is transport-owned.
    final count = reader.remaining ~/ 4;
    if (count > 3) {
      throw const FormatException('Too many USB PTP event parameters');
    }
    return _standardEvent(code, List.generate(count, (_) => reader.u32()));
  }

  static PtpTetherEvent _standardEvent(int code, List<int> params) {
    final kind = switch (code) {
      0x4002 || 0xc004 || 0xc201 => PtpTetherEventKind.objectAdded,
      0xc101 => PtpTetherEventKind.objectTransfer,
      0x4003 || 0xc202 => PtpTetherEventKind.objectRemoved,
      0x4006 || 0xc203 => PtpTetherEventKind.propertyChanged,
      _ => PtpTetherEventKind.unknown,
    };
    if (kind != PtpTetherEventKind.unknown && params.isEmpty) {
      throw const FormatException('Known event is missing its parameter');
    }
    return PtpTetherEvent(
      code: code,
      kind: kind,
      params: params,
      handle:
          kind == PtpTetherEventKind.objectAdded ||
              kind == PtpTetherEventKind.objectTransfer ||
              kind == PtpTetherEventKind.objectRemoved
          ? params.first
          : null,
      propertyCode: kind == PtpTetherEventKind.propertyChanged
          ? params.first
          : null,
      requiresObjectInfo:
          kind == PtpTetherEventKind.objectAdded ||
          kind == PtpTetherEventKind.objectTransfer,
    );
  }

  static void _writeValue(BytesBuilder builder, int type, Object value) {
    if (type == 0xffff) {
      if (value is! String || value.contains('\u0000')) {
        throw ArgumentError('A PTP string must not contain NUL');
      }
      final units = value.codeUnits;
      if (units.length > 254) throw ArgumentError('PTP string is too long');
      if (units.isEmpty) {
        builder.addByte(0);
      } else {
        builder.addByte(units.length + 1);
        for (final unit in [...units, 0]) {
          builder.add([unit & 0xff, unit >> 8]);
        }
      }
      return;
    }
    if ((type & 0x4000) != 0) {
      final scalar = type & ~0x4000;
      _integerSpec(scalar);
      if (value is! List || value.length > _Reader.maxElements) {
        throw ArgumentError('Invalid PTP array');
      }
      _writeValue(builder, 6, value.length);
      for (final item in value) {
        if (item is! Object) throw ArgumentError('Null PTP array element');
        _writeValue(builder, scalar, item);
      }
      return;
    }
    final (width, signed) = _integerSpec(type);
    if (value is! int && value is! BigInt) {
      throw ArgumentError('A PTP integer requires int or BigInt');
    }
    var integer = value is BigInt ? value : BigInt.from(value as int);
    final bits = width * 8;
    final limit = BigInt.one << (signed ? bits - 1 : bits);
    final minimum = signed ? -limit : BigInt.zero;
    final maximum = limit - BigInt.one;
    if (integer < minimum || integer > maximum) {
      throw ArgumentError('PTP integer is outside its declared type');
    }
    if (integer.isNegative) integer += BigInt.one << bits;
    final result = Uint8List(width);
    for (var index = 0; index < width; index++) {
      result[index] = (integer & BigInt.from(0xff)).toInt();
      integer >>= 8;
    }
    builder.add(result);
  }
}

(int, bool) _integerSpec(int type) => switch (type) {
  1 => (1, true),
  2 => (1, false),
  3 => (2, true),
  4 => (2, false),
  5 => (4, true),
  6 => (4, false),
  7 => (8, true),
  8 => (8, false),
  9 => (16, true),
  10 => (16, false),
  _ => throw const FormatException('Unsupported PTP value type'),
};

class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);

  static const maxElements = 1000000;
  final Uint8List bytes;
  final ByteData data;
  int offset = 0;
  int get remaining => bytes.length - offset;

  void require(int count) {
    if (count < 0 || count > remaining) {
      throw const FormatException('Truncated PTP data');
    }
  }

  void checkCount(int count, int minimumSize) {
    if (count < 0 ||
        count > maxElements ||
        minimumSize < 1 ||
        count > remaining ~/ minimumSize) {
      throw const FormatException('Invalid PTP element count');
    }
  }

  void finish() {
    if (remaining != 0) {
      throw const FormatException('Unexpected trailing PTP data');
    }
  }

  int u8() {
    require(1);
    return bytes[offset++];
  }

  int u16() {
    final result = peekU16();
    offset += 2;
    return result;
  }

  int peekU16() {
    require(2);
    return data.getUint16(offset, Endian.little);
  }

  int u32() {
    final result = peekU32();
    offset += 4;
    return result;
  }

  int peekU32() {
    require(4);
    return data.getUint32(offset, Endian.little);
  }

  void skip(int count) {
    require(count);
    offset += count;
  }

  Uint8List take(int count) {
    require(count);
    final result = Uint8List.sublistView(bytes, offset, offset + count);
    offset += count;
    return result;
  }

  List<int> u16Array() {
    final count = u32();
    checkCount(count, 2);
    return List.generate(count, (_) => u16());
  }

  String string() {
    final count = u8();
    if (count == 0) return '';
    checkCount(count, 2);
    final units = List.generate(count, (_) => u16());
    if (units.last != 0 || units.take(count - 1).contains(0)) {
      throw const FormatException('Invalid PTP string terminator');
    }
    return String.fromCharCodes(units.take(count - 1));
  }

  String cString() {
    final start = offset;
    while (offset < bytes.length && bytes[offset] != 0) {
      offset++;
    }
    if (offset == bytes.length) {
      throw const FormatException('Unterminated Canon filename');
    }
    final result = utf8.decode(
      Uint8List.sublistView(bytes, start, offset),
      allowMalformed: true,
    );
    offset++;
    return result;
  }

  Object value(int type) {
    if (type == 0xffff) return string();
    if ((type & 0x4000) != 0) {
      final scalar = type & ~0x4000;
      final (width, _) = _integerSpec(scalar);
      final count = u32();
      checkCount(count, width);
      return List<Object>.unmodifiable(
        List.generate(count, (_) => value(scalar)),
      );
    }
    final (width, signed) = _integerSpec(type);
    final raw = take(width);
    var integer = BigInt.zero;
    for (var index = width - 1; index >= 0; index--) {
      integer = (integer << 8) | BigInt.from(raw[index]);
    }
    if (signed && (raw.last & 0x80) != 0) {
      integer -= BigInt.one << (width * 8);
    }
    // Dart native int is signed 64-bit. Keep UINT64's upper half and 128-bit
    // values losslessly represented instead of wrapping them into negatives.
    if (width > 8 || integer > BigInt.parse('9223372036854775807')) {
      return integer;
    }
    return integer.toInt();
  }

  List<Object> enumeration(int type) {
    final count = u16();
    final minimum = type == 0xffff
        ? 1
        : (type & 0x4000) != 0
        ? 4
        : _integerSpec(type).$1;
    checkCount(count, minimum);
    return List.generate(count, (_) => value(type));
  }
}
