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
    this._eventReader,
    this._operationTimeout,
  );

  static const int defaultPort = 15740;
  static const int _protocolVersion = 0x00010000;
  static const int _responseOk = 0x2001;
  static const int _maxDataLength = 512 * 1024 * 1024;

  final String host;
  final int port;
  final Socket _commandSocket;
  final Socket _eventSocket;
  final _PtpPacketReader _commandReader;
  final _PtpPacketReader _eventReader;
  final Duration _operationTimeout;
  Future<void> _operationChain = Future<void>.value();
  Future<void>? _closingFuture;
  Future<int>? _baselineFuture;
  Future<List<PtpIpImage>>? _scanFuture;
  final Set<int> _knownHandles = {};
  final Map<int, PtpIpImage> _pending = {};
  final Map<int, int> _imageSizes = {};
  Set<int>? _baselineStores;
  int _baselineCount = 0;
  int _transactionId = 1;
  bool _closing = false;
  bool _closed = false;

  bool get isClosed => _closed || _closing;

  static Future<PtpIpCamera?> connect(
    String host, {
    int port = defaultPort,
    Duration timeout = const Duration(milliseconds: 900),
    Duration operationTimeout = const Duration(seconds: 30),
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
      final camera = PtpIpCamera._(
        host,
        port,
        command,
        event,
        reader,
        eventReader,
        operationTimeout,
      );
      // Keep consuming the dedicated event channel. Leaving its stream iterator
      // idle buffers camera events indefinitely and can stall the camera.
      unawaited(camera._consumeEvents());
      final opened = await camera._operation(
        0x1002,
        params: const [1],
        transactionId: 0,
        timeout: timeout,
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

  /// Establishes the complete card baseline without downloading metadata for
  /// every old photo. It is idempotent for this connection and never resets an
  /// already-armed session, which would otherwise swallow new shots.
  Future<int> establishLiveBaseline() {
    if (_baselineStores != null) return Future.value(_baselineCount);
    final existing = _baselineFuture;
    if (existing != null) return existing;
    late final Future<int> operation;
    operation = _establishLiveBaseline().whenComplete(() {
      if (identical(_baselineFuture, operation)) _baselineFuture = null;
    });
    _baselineFuture = operation;
    return operation;
  }

  Future<int> _establishLiveBaseline() async {
    final catalog = await _catalog();
    if (catalog.stores.isEmpty) {
      throw const SocketException(
        'No camera storage is ready for live shooting',
      );
    }
    _knownHandles.addAll(catalog.handles);
    _baselineStores = catalog.stores;
    _baselineCount = catalog.handles.length;
    return _baselineCount;
  }

  /// Returns every new image until the caller acknowledges its durable local
  /// save. A busy camera or incomplete object metadata is retried on the next
  /// poll; neither advances the baseline nor discards retained photos.
  Future<List<PtpIpImage>> pendingImages() {
    if (_baselineStores == null) {
      return Future.error(StateError('Establish the camera baseline first'));
    }
    final existing = _scanFuture;
    if (existing != null) return existing;
    late final Future<List<PtpIpImage>> operation;
    operation = _refreshPending().whenComplete(() {
      if (identical(_scanFuture, operation)) _scanFuture = null;
    });
    _scanFuture = operation;
    return operation;
  }

  Future<List<PtpIpImage>> _refreshPending() async {
    final _PtpCatalog catalog;
    try {
      catalog = await _catalog();
    } catch (_) {
      if (isClosed || _pending.isEmpty) rethrow;
      return _pendingSnapshot();
    }
    final stores = _baselineStores!;
    if (stores.length != catalog.stores.length ||
        !stores.containsAll(catalog.stores)) {
      _abort();
      throw const SocketException(
        'Camera storage changed. Reconnect to start a new shooting session.',
      );
    }
    // A removed object may reuse its handle later in this PTP session.
    _knownHandles.retainAll(catalog.handles);
    _pending.removeWhere((handle, _) => !catalog.handles.contains(handle));
    _imageSizes.removeWhere((handle, _) => !catalog.handles.contains(handle));
    final candidates =
        catalog.handles
            .where((handle) => !_knownHandles.contains(handle))
            .toList()
          ..sort();
    for (final handle in candidates) {
      final response = await _operation(
        0x1008,
        params: [handle],
        expectsData: true,
      );
      // A pending save may be acknowledged while this metadata request runs.
      if (_knownHandles.contains(handle)) continue;
      if (response.responseCode != _responseOk) continue;
      final data = response.data;
      if (data.length < 53) continue;
      if (_readU16(data, 4) == 0x3001) {
        // Association objects are folders, not an unfinished image.
        _knownHandles.add(handle);
        _pending.remove(handle);
        continue;
      }
      final image = _decodeObjectInfo(handle, data);
      if (image == null) continue;
      if (!_isImageName(image.name)) {
        // Unknown/temporary names can become JPEG/RAW once the camera finishes
        // writing. Only classify an explicit non-photo file as handled.
        if (_isNonImageName(image.name)) {
          _knownHandles.add(handle);
          _pending.remove(handle);
        }
        continue;
      }
      if (image.size <= 0) continue;
      _pending[handle] = image;
      _imageSizes[handle] = image.size;
    }
    return _pendingSnapshot();
  }

  List<PtpIpImage> _pendingSnapshot() {
    final images = _pending.values.toList()
      ..sort((a, b) => a.handle.compareTo(b.handle));
    return List<PtpIpImage>.unmodifiable(images);
  }

  void acknowledgeImages(Iterable<int> handles) {
    for (final handle in handles) {
      if (_pending.remove(handle) != null) _knownHandles.add(handle);
    }
  }

  Future<_PtpCatalog> _catalog() async {
    final storageResponse = await _operation(0x1004, expectsData: true);
    if (storageResponse.responseCode != _responseOk) {
      throw const SocketException(
        'Camera storage is not ready; retry the connection',
      );
    }
    final stores = _decodeU32Array(storageResponse.data).toSet();
    final handles = <int>{};
    for (final storageId in stores) {
      final response = await _operation(
        0x1007,
        // Association=0 includes DCIM subfolders. 0xFFFFFFFF is root-only.
        params: [storageId, 0, 0],
        expectsData: true,
      );
      if (response.responseCode != _responseOk) {
        throw const SocketException('The complete camera catalog is not ready');
      }
      handles.addAll(_decodeU32Array(response.data));
    }
    return _PtpCatalog(stores, handles);
  }

  Future<List<PtpIpImage>> recentImages({int limit = 40}) async {
    if (limit <= 0) return const [];
    final handles = (await _catalog()).handles.toList();
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
          _imageSizes[image.handle] = image.size;
          if (results.length >= limit) break;
        }
      } catch (_) {
        if (isClosed) rethrow;
      }
    }
    return results;
  }

  Future<Uint8List?> downloadImage(int handle, {int? expectedSize}) async {
    final response = await _operation(
      0x1009,
      params: [handle],
      expectsData: true,
    );
    if (response.responseCode != _responseOk || response.data.isEmpty) {
      return null;
    }
    final size = expectedSize ?? _imageSizes[handle];
    if (size != null &&
        size > 0 &&
        size != 0xffffffff &&
        response.data.length != size) {
      // The transaction is intact, but the camera may still be finishing this
      // file. Keep it pending so updated metadata/download can be retried.
      return null;
    }
    return response.data;
  }

  Future<void> close() => _closingFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closing = true;
    try {
      // CloseSession waits behind the current transaction; it must never steal
      // its response. If the camera is stuck, close the sockets themselves.
      await _operation(0x1003, allowClosing: true).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          _abort();
          throw TimeoutException('Closing the camera connection timed out');
        },
      );
    } catch (_) {
    } finally {
      _abort();
    }
  }

  Future<void> _consumeEvents() async {
    try {
      while (!_closed) {
        // Object reconciliation is authoritative. Vendor-specific events may
        // be hints, but no shot is acknowledged merely because an event arrived.
        await _eventReader.readPacket();
      }
    } catch (_) {
      if (!_closing) _abort();
    }
  }

  void _abort() {
    if (_closed) return;
    _closed = true;
    _commandSocket.destroy();
    _eventSocket.destroy();
    unawaited(_commandReader.close());
    unawaited(_eventReader.close());
  }

  Future<_PtpOperationResult> _operation(
    int opcode, {
    List<int> params = const [],
    bool expectsData = false,
    int? transactionId,
    bool allowClosing = false,
    Duration? timeout,
  }) {
    if (_closed || (_closing && !allowClosing)) {
      return Future.error(const SocketException('PTP/IP camera is closed'));
    }
    final operation = _operationChain.then(
      (_) => _performOperation(
        opcode,
        params: params,
        expectsData: expectsData,
        transactionId: transactionId,
        timeout: timeout ?? _operationTimeout,
      ),
    );
    _operationChain = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<_PtpOperationResult> _performOperation(
    int opcode, {
    required List<int> params,
    required bool expectsData,
    required int? transactionId,
    required Duration timeout,
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
    try {
      _commandSocket.add(_packet(6, payload.buffer.asUint8List()));
      await _commandSocket.flush().timeout(timeout);
      final data = BytesBuilder(copy: false);
      int? announcedLength;
      var dataStarted = false;
      var dataEnded = false;

      while (true) {
        final packet = await _commandReader.readPacket().timeout(timeout);
        if (packet.type == 9) {
          if (dataStarted ||
              !expectsData ||
              packet.payload.length != 12 ||
              _readU32(packet.payload, 0) != tx) {
            throw const SocketException('Invalid PTP/IP start-data packet');
          }
          dataStarted = true;
          final low = _readU32(packet.payload, 4);
          final high = _readU32(packet.payload, 8);
          if (high != 0 || low > _maxDataLength) {
            throw const SocketException(
              'The camera photo is too large to transfer',
            );
          }
          announcedLength = low;
          continue;
        }
        if (packet.type == 10 || packet.type == 12) {
          if (!dataStarted ||
              dataEnded ||
              packet.payload.length < 4 ||
              _readU32(packet.payload, 0) != tx) {
            throw const SocketException('Invalid PTP/IP data packet');
          }
          if (data.length + packet.payload.length - 4 > announcedLength!) {
            throw const SocketException(
              'PTP/IP data exceeds its announced length',
            );
          }
          data.add(Uint8List.sublistView(packet.payload, 4));
          dataEnded = packet.type == 12;
          continue;
        }
        if (packet.type != 7 ||
            packet.payload.length < 6 ||
            _readU32(packet.payload, 2) != tx) {
          throw const SocketException('Unexpected PTP/IP transaction response');
        }
        final responseCode = _readU16(packet.payload, 0);
        if (responseCode == _responseOk &&
            expectsData &&
            (!dataStarted || !dataEnded || data.length != announcedLength)) {
          throw const SocketException('Camera photo transfer was incomplete');
        }
        return _PtpOperationResult(
          responseCode: responseCode,
          data: expectsData ? data.takeBytes() : Uint8List(0),
        );
      }
    } catch (_) {
      // A timed-out read still owns its future. Closing both sockets prevents
      // any later caller from consuming that transaction's delayed response.
      _abort();
      rethrow;
    }
  }

  static List<int> _decodeU32Array(Uint8List data) {
    if (data.length < 4) throw const FormatException('Incomplete PTP array');
    final count = _readU32(data, 0);
    final available = (data.length - 4) ~/ 4;
    if (count != available || data.length != 4 + count * 4) {
      throw const FormatException('Incomplete PTP camera catalog');
    }
    return [
      for (var index = 0; index < count; index++) _readU32(data, 4 + index * 4),
    ];
  }

  static bool _isNonImageName(String name) => const {
    'mov',
    'mp4',
    'avi',
    'wav',
    'mp3',
    'txt',
  }.contains(name.split('.').last.toLowerCase());

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
    if (offset + 1 + count * 2 > data.length ||
        _readU16(data, offset + 1 + byteLength) != 0) {
      return null;
    }
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

class _PtpCatalog {
  const _PtpCatalog(this.stores, this.handles);

  final Set<int> stores;
  final Set<int> handles;
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

  Future<void> close() async {
    await _iterator.cancel();
  }

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
