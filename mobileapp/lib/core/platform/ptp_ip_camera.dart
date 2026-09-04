import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class PtpIpImage {
  const PtpIpImage({
    required this.handle,
    required this.name,
    required this.size,
  });

  final int handle;
  final String name;
  final int size;

  String get fingerprint => '$handle|$size|$name';
}

class PtpIpCamera {
  PtpIpCamera._(
    this.host,
    this.port,
    this._commandSocket,
    this._eventSocket,
    this._commandReader,
  );

  static const int defaultPort = 15740;
  static const int _protocolVersion = 0x00010000;
  static const int _responseOk = 0x2001;

  final String host;
  final int port;
  final Socket _commandSocket;
  final Socket _eventSocket;
  final _PtpPacketReader _commandReader;
  int _transactionId = 1;
  bool _closed = false;

  static Future<PtpIpCamera?> connect(
    String host, {
    int port = defaultPort,
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    Socket? command;
    Socket? event;
    try {
      command = await Socket.connect(host, port, timeout: timeout);
      command.setOption(SocketOption.tcpNoDelay, true);
      final reader = _PtpPacketReader(command);
      final guid = Uint8List.fromList(
        List<int>.generate(16, (_) => Random.secure().nextInt(256)),
      );
      final initPayload = _joinBytes([
        guid,
        _utf16NullTerminated('Airpix'),
        _u32(_protocolVersion),
      ]);
      command.add(_packet(1, initPayload));
      await command.flush();

      final ack = await reader.readPacket().timeout(timeout);
      if (ack.type != 2 || ack.payload.length < 4) {
        throw const SocketException('PTP/IP command handshake rejected');
      }
      final connectionNumber = _readU32(ack.payload, 0);

      event = await Socket.connect(host, port, timeout: timeout);
      event.setOption(SocketOption.tcpNoDelay, true);
      final eventReader = _PtpPacketReader(event);
      event.add(_packet(3, _u32(connectionNumber)));
      await event.flush();
      final eventAck = await eventReader.readPacket().timeout(timeout);
      if (eventAck.type != 4) {
        throw const SocketException('PTP/IP event handshake rejected');
      }
      final camera = PtpIpCamera._(host, port, command, event, reader);
      final opened = await camera._operation(
        0x1002,
        params: const [1],
        transactionId: 0,
      );
      if (opened.responseCode != _responseOk) {
        throw const SocketException('PTP session rejected');
      }
      return camera;
    } catch (_) {
      command?.destroy();
      event?.destroy();
      return null;
    }
  }

  Future<List<PtpIpImage>> recentImages({int limit = 40}) async {
    final storageResponse = await _operation(0x1004, expectsData: true);
    if (storageResponse.responseCode != _responseOk) return const [];
    final storageIds = _decodeU32Array(storageResponse.data);
    final handles = <int>[];
    for (final storageId in storageIds) {
      final response = await _operation(
        0x1007,
        // PTP GetObjectHandles: association=0 means all objects in the store.
        // 0xFFFFFFFF means only objects in the storage root, which misses
        // normal camera folders such as DCIM/100CANON or DCIM/100MSDCF.
        params: [storageId, 0, 0],
        expectsData: true,
      );
      if (response.responseCode == _responseOk) {
        handles.addAll(_decodeU32Array(response.data));
      }
    }

    handles.sort((a, b) => b.compareTo(a));
    final results = <PtpIpImage>[];
    for (final handle in handles.take(max(limit * 3, 60))) {
      try {
        final infoResponse = await _operation(
          0x1008,
          params: [handle],
          expectsData: true,
        );
        if (infoResponse.responseCode != _responseOk) continue;
        final image = _decodeObjectInfo(handle, infoResponse.data);
        if (image != null && _isImageName(image.name)) {
          results.add(image);
          if (results.length >= limit) break;
        }
      } catch (_) {}
    }
    return results;
  }

  Future<Uint8List?> downloadImage(int handle) async {
    final response = await _operation(
      0x1009,
      params: [handle],
      expectsData: true,
    );
    if (response.responseCode != _responseOk || response.data.isEmpty) {
      return null;
    }
    return response.data;
  }

  Future<void> close() async {
    if (_closed) return;
    try {
      await _operation(0x1003);
    } catch (_) {
    } finally {
      _closed = true;
      _commandSocket.destroy();
      _eventSocket.destroy();
    }
  }

  Future<_PtpOperationResult> _operation(
    int opcode, {
    List<int> params = const [],
    bool expectsData = false,
    int? transactionId,
  }) async {
    if (_closed) throw const SocketException('PTP/IP camera is closed');
    final tx = transactionId ?? _transactionId++;
    final payload = ByteData(10 + params.length * 4);
    payload.setUint32(0, 1, Endian.little);
    payload.setUint16(4, opcode, Endian.little);
    payload.setUint32(6, tx, Endian.little);
    for (var index = 0; index < params.length; index++) {
      payload.setUint32(10 + index * 4, params[index], Endian.little);
    }
    _commandSocket.add(_packet(6, payload.buffer.asUint8List()));
    await _commandSocket.flush();
    final data = BytesBuilder(copy: false);

    while (true) {
      final packet = await _commandReader.readPacket().timeout(
        const Duration(seconds: 30),
      );
      if (packet.type == 9) {
        if (packet.payload.length < 12 || _readU32(packet.payload, 0) != tx) {
          throw const SocketException('Invalid PTP/IP start-data packet');
        }
        if (packet.payload.length > 12) {
          data.add(packet.payload.sublist(12));
        }
        continue;
      }
      if (packet.type == 10 || packet.type == 12) {
        if (packet.payload.length < 4 || _readU32(packet.payload, 0) != tx) {
          throw const SocketException('Invalid PTP/IP data packet');
        }
        if (packet.payload.length > 4) {
          data.add(packet.payload.sublist(4));
        }
        continue;
      }
      if (packet.type != 7 || packet.payload.length < 6) continue;
      final responseCode = _readU16(packet.payload, 0);
      final responseTx = _readU32(packet.payload, 2);
      if (responseTx != tx) continue;
      return _PtpOperationResult(
        responseCode: responseCode,
        data: expectsData ? data.takeBytes() : Uint8List(0),
      );
    }
  }

  static List<int> _decodeU32Array(Uint8List data) {
    if (data.length < 4) return const [];
    final count = _readU32(data, 0);
    final available = (data.length - 4) ~/ 4;
    final actual = min(count, available);
    return [
      for (var index = 0; index < actual; index++)
        _readU32(data, 4 + index * 4),
    ];
  }

  static PtpIpImage? _decodeObjectInfo(int handle, Uint8List data) {
    if (data.length < 53) return null;
    final size = _readU32(data, 8);
    final name = _readPtpString(data, 52);
    if (name == null || name.isEmpty) return null;
    return PtpIpImage(handle: handle, name: name, size: size);
  }

  static bool _isImageName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = name.substring(dot + 1).toLowerCase();
    return const {
      'jpg',
      'jpeg',
      'png',
      'heic',
      'heif',
      'webp',
      'gif',
      'tif',
      'tiff',
      'dng',
      'arw',
      'cr2',
      'cr3',
      'nef',
      'nrw',
      'raf',
      'rw2',
      'orf',
      'pef',
    }.contains(ext);
  }

  static String? _readPtpString(Uint8List data, int offset) {
    if (offset >= data.length) return null;
    final count = data[offset];
    if (count == 0) return '';
    final byteLength = (count - 1) * 2;
    if (offset + 1 + byteLength > data.length) return null;
    final units = <int>[];
    for (var index = 0; index < byteLength; index += 2) {
      units.add(_readU16(data, offset + 1 + index));
    }
    return String.fromCharCodes(units);
  }

  static Uint8List _utf16NullTerminated(String value) {
    final data = ByteData((value.length + 1) * 2);
    for (var index = 0; index < value.length; index++) {
      data.setUint16(index * 2, value.codeUnitAt(index), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Uint8List _packet(int type, Uint8List payload) {
    final header = ByteData(8);
    header.setUint32(0, payload.length + 8, Endian.little);
    header.setUint32(4, type, Endian.little);
    return _joinBytes([header.buffer.asUint8List(), payload]);
  }

  static Uint8List _u32(int value) {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.buffer.asUint8List();
  }

  static int _readU16(Uint8List data, int offset) {
    return ByteData.sublistView(
      data,
      offset,
      offset + 2,
    ).getUint16(0, Endian.little);
  }

  static int _readU32(Uint8List data, int offset) {
    return ByteData.sublistView(
      data,
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
  }

  static Uint8List _joinBytes(List<Uint8List> chunks) {
    final builder = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

class _PtpOperationResult {
  const _PtpOperationResult({required this.responseCode, required this.data});

  final int responseCode;
  final Uint8List data;
}

class _PtpPacket {
  const _PtpPacket(this.type, this.payload);

  final int type;
  final Uint8List payload;
}

class _PtpPacketReader {
  _PtpPacketReader(Stream<Uint8List> stream)
    : _iterator = StreamIterator<Uint8List>(stream);

  final StreamIterator<Uint8List> _iterator;
  final List<int> _buffer = [];

  Future<_PtpPacket> readPacket() async {
    final header = await _readExact(8);
    final view = ByteData.sublistView(header);
    final length = view.getUint32(0, Endian.little);
    final type = view.getUint32(4, Endian.little);
    if (length < 8 || length > 512 * 1024 * 1024) {
      throw const SocketException('Invalid PTP/IP packet length');
    }
    final payload = await _readExact(length - 8);
    return _PtpPacket(type, payload);
  }

  Future<Uint8List> _readExact(int length) async {
    if (length == 0) return Uint8List(0);
    while (_buffer.length < length) {
      final hasNext = await _iterator.moveNext();
      if (!hasNext) {
        throw const SocketException('PTP/IP socket closed');
      }
      _buffer.addAll(_iterator.current);
    }
    final result = Uint8List.fromList(_buffer.sublist(0, length));
    _buffer.removeRange(0, length);
    return result;
  }
}
