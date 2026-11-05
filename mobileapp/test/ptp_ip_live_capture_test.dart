import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/ptp_ip_camera.dart';

void main() {
  test(
    'full multi-card baseline skips old photos and retains a burst larger than 50',
    () async {
      final server = await _PtpServer.start();
      server.stores[1] = List.generate(180, (index) => index + 1);
      server.stores[2] = List.generate(140, (index) => index + 1000);
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });

      expect(await camera.establishLiveBaseline(), 320);
      expect(server.infoRequests, isEmpty);
      expect(await camera.pendingImages(), isEmpty);
      for (var handle = 2000; handle < 2075; handle++) {
        server.stores[handle.isEven ? 1 : 2]!.add(handle);
        server.objects[handle] = _Object('$handle.JPG', 8);
      }

      final pending = await camera.pendingImages();
      expect(pending, hasLength(75));
      expect(server.infoRequests.every((handle) => handle >= 2000), isTrue);
      expect(await camera.pendingImages(), hasLength(75));
      camera.acknowledgeImages(pending.take(74).map((image) => image.handle));
      expect((await camera.pendingImages()).single.handle, 2074);
      camera.acknowledgeImages([2074]);
      expect(await camera.pendingImages(), isEmpty);
      expect(await camera.establishLiveBaseline(), 320);
      expect(
        server.handleParameters.every(
          (params) => params[1] == 0 && params[2] == 0,
        ),
        isTrue,
      );
    },
  );

  test(
    'busy and temporary metadata is retried without acknowledging a new shot',
    () async {
      final server = await _PtpServer.start();
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });
      await camera.establishLiveBaseline();
      server.stores[1]!.add(5);
      server.objects[5] = _Object('WRITING.TMP', 8);
      server.busyInfo.add(5);

      expect(await camera.pendingImages(), isEmpty);
      server.busyInfo.clear();
      expect(await camera.pendingImages(), isEmpty);
      server.objects[5] = _Object('SHOT0005.JPG', 8);
      expect((await camera.pendingImages()).single.name, 'SHOT0005.JPG');
      // A caller that failed to persist has not acknowledged anything.
      expect((await camera.pendingImages()).single.handle, 5);
      camera.acknowledgeImages([5]);
      expect(await camera.pendingImages(), isEmpty);
    },
  );

  test('a partial catalog never becomes the baseline', () async {
    final server = await _PtpServer.start();
    server.stores[1] = [1, 2, 3];
    server.malformedCatalog = true;
    final camera = await _connect(server);
    addTearDown(() async {
      await camera.close();
      await server.close();
    });

    await expectLater(camera.establishLiveBaseline(), throwsFormatException);
    await expectLater(camera.pendingImages(), throwsStateError);
    server.malformedCatalog = false;
    expect(await camera.establishLiveBaseline(), 3);
    expect(await camera.pendingImages(), isEmpty);
  });

  test(
    'download length mismatch stays pending until the complete file is available',
    () async {
      final server = await _PtpServer.start();
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });
      await camera.establishLiveBaseline();
      server.stores[1]!.add(7);
      server.objects[7] = _Object('SHOT0007.JPG', 10, actualBytes: 6);
      final shot = (await camera.pendingImages()).single;

      expect(
        await camera.downloadImage(shot.handle, expectedSize: shot.size),
        isNull,
      );
      expect(await camera.pendingImages(), hasLength(1));
      server.objects[7] = _Object('SHOT0007.JPG', 10);
      expect(
        await camera.downloadImage(shot.handle, expectedSize: shot.size),
        hasLength(10),
      );
      camera.acknowledgeImages([shot.handle]);
      expect(await camera.pendingImages(), isEmpty);
    },
  );

  test(
    'a truncated PTP data phase closes the connection instead of publishing bytes',
    () async {
      final server = await _PtpServer.start();
      server.objects[7] = _Object('SHOT0007.JPG', 8);
      server.truncateTransactionFor = 7;
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });

      await expectLater(
        camera.downloadImage(7),
        throwsA(isA<SocketException>()),
      );
      expect(camera.isClosed, isTrue);
    },
  );

  test(
    'concurrent downloads serialize ownership of the command stream',
    () async {
      final server = await _PtpServer.start();
      server.objects[7] = _Object('SHOT0007.JPG', 8);
      server.objects[8] = _Object('SHOT0008.JPG', 9);
      server.holdDownload = Completer<void>();
      final camera = await _connect(server);
      addTearDown(() async {
        if (!server.holdDownload!.isCompleted) server.holdDownload!.complete();
        await camera.close();
        await server.close();
      });

      final first = camera.downloadImage(7);
      await server.downloadStarted.future;
      final second = camera.downloadImage(8);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.downloadRequests, [7]);
      server.holdDownload!.complete();
      expect(await first, hasLength(8));
      expect(await second, hasLength(9));
      expect(server.downloadRequests, [7, 8]);
    },
  );

  test(
    'close waits behind an in-flight transaction without stealing its response',
    () async {
      final server = await _PtpServer.start();
      server.objects[7] = _Object('SHOT0007.JPG', 8);
      server.holdDownload = Completer<void>();
      final camera = await _connect(server);
      addTearDown(() async {
        if (!server.holdDownload!.isCompleted) server.holdDownload!.complete();
        await camera.close();
        await server.close();
      });

      final download = camera.downloadImage(7);
      await server.downloadStarted.future;
      final closing = camera.close();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.operations, [0x1002, 0x1009]);
      server.holdDownload!.complete();
      expect(await download, hasLength(8));
      await closing;
      expect(server.operations, [0x1002, 0x1009, 0x1003]);
      expect(camera.isClosed, isTrue);
    },
  );

  test(
    'a transaction timeout closes the socket before any queued request starts',
    () async {
      final server = await _PtpServer.start();
      server.stallDownloads = true;
      final camera = await _connect(
        server,
        operationTimeout: const Duration(milliseconds: 80),
      );
      addTearDown(() async {
        await camera.close();
        await server.close();
      });

      final first = camera.downloadImage(7);
      final second = camera.downloadImage(8);
      await Future.wait([
        expectLater(first, throwsA(isA<TimeoutException>())),
        expectLater(second, throwsA(isA<SocketException>())),
      ]);
      expect(camera.isClosed, isTrue);
      expect(server.downloadRequests, [7]);
    },
  );
}

Future<PtpIpCamera> _connect(
  _PtpServer server, {
  Duration operationTimeout = const Duration(seconds: 2),
}) async {
  final camera = await PtpIpCamera.connect(
    InternetAddress.loopbackIPv4.address,
    port: server.port,
    timeout: const Duration(seconds: 2),
    operationTimeout: operationTimeout,
  );
  expect(camera, isNotNull);
  return camera!;
}

class _Object {
  const _Object(this.name, this.size, {this.actualBytes});

  final String name;
  final int size;
  final int? actualBytes;

  Uint8List get bytes => Uint8List.fromList(
    List.generate(actualBytes ?? size, (index) => index % 256),
  );

  Uint8List get info {
    final data = ByteData(53 + (name.length + 1) * 2);
    data.setUint16(4, 0x3801, Endian.little);
    data.setUint32(8, size, Endian.little);
    data.setUint8(52, name.length + 1);
    for (var index = 0; index < name.length; index++) {
      data.setUint16(53 + index * 2, name.codeUnitAt(index), Endian.little);
    }
    return data.buffer.asUint8List();
  }
}

class _PtpServer {
  _PtpServer(this._server);

  final ServerSocket _server;
  final List<Socket> _sockets = [];
  final stores = <int, List<int>>{1: []};
  final objects = <int, _Object>{};
  final busyInfo = <int>{};
  final operations = <int>[];
  final infoRequests = <int>[];
  final downloadRequests = <int>[];
  final handleParameters = <List<int>>[];
  final downloadStarted = Completer<void>();
  Completer<void>? holdDownload;
  bool malformedCatalog = false;
  bool stallDownloads = false;
  int? truncateTransactionFor;

  int get port => _server.port;

  static Future<_PtpServer> start() async {
    final server = _PtpServer(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen((socket) {
      server._sockets.add(socket);
      unawaited(server._connection(socket));
    });
    return server;
  }

  Future<void> _connection(Socket socket) async {
    final reader = _PacketReader(socket);
    try {
      final first = await reader.read();
      if (first.$1 == 1) {
        socket.add(_packet(2, _u32(99)));
        await socket.flush();
        while (true) {
          final packet = await reader.read();
          if (packet.$1 != 6) continue;
          final data = ByteData.sublistView(packet.$2);
          final opcode = data.getUint16(4, Endian.little);
          final tx = data.getUint32(6, Endian.little);
          final params = [
            for (var offset = 10; offset + 4 <= packet.$2.length; offset += 4)
              data.getUint32(offset, Endian.little),
          ];
          operations.add(opcode);
          // Continue reading commands while a response is deliberately held so
          // the test can detect clients that issue overlapping transactions.
          unawaited(
            _respond(socket, opcode, tx, params).catchError((Object _) {}),
          );
        }
      } else if (first.$1 == 3) {
        socket.add(_packet(4, Uint8List(0)));
        await socket.flush();
        while (true) {
          await reader.read();
        }
      }
    } catch (_) {
      // Test shutdown and intentional client aborts close the socket.
    } finally {
      await reader.close();
      socket.destroy();
    }
  }

  Future<void> _respond(
    Socket socket,
    int opcode,
    int tx,
    List<int> params,
  ) async {
    Uint8List? body;
    var response = 0x2001;
    int? announcedLength;
    switch (opcode) {
      case 0x1004:
        body = _array(stores.keys);
      case 0x1007:
        handleParameters.add(params);
        body = _array(stores[params.first] ?? []);
        if (malformedCatalog) {
          ByteData.sublistView(body).setUint32(0, 100000, Endian.little);
        }
      case 0x1008:
        final handle = params.first;
        infoRequests.add(handle);
        if (busyInfo.contains(handle)) {
          response = 0x2019;
        } else {
          body = objects[handle]?.info;
          if (body == null) response = 0x2009;
        }
      case 0x1009:
        final handle = params.first;
        downloadRequests.add(handle);
        if (!downloadStarted.isCompleted) downloadStarted.complete();
        if (stallDownloads) return;
        await holdDownload?.future;
        body = objects[handle]?.bytes;
        if (body == null) response = 0x2009;
        if (truncateTransactionFor == handle && body != null) {
          announcedLength = body.length + 3;
        }
    }
    if (body != null) {
      final start = ByteData(12)
        ..setUint32(0, tx, Endian.little)
        ..setUint32(4, announcedLength ?? body.length, Endian.little);
      socket.add(_packet(9, start.buffer.asUint8List()));
      socket.add(_packet(12, Uint8List.fromList([..._u32(tx), ...body])));
    }
    final result = ByteData(6)
      ..setUint16(0, response, Endian.little)
      ..setUint32(2, tx, Endian.little);
    socket.add(_packet(7, result.buffer.asUint8List()));
    await socket.flush();
  }

  Future<void> close() async {
    if (holdDownload != null && !holdDownload!.isCompleted) {
      holdDownload!.complete();
    }
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}

Uint8List _u32(int value) =>
    (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

Uint8List _array(Iterable<int> values) {
  final data = ByteData(4 + values.length * 4)
    ..setUint32(0, values.length, Endian.little);
  var offset = 4;
  for (final value in values) {
    data.setUint32(offset, value, Endian.little);
    offset += 4;
  }
  return data.buffer.asUint8List();
}

Uint8List _packet(int type, Uint8List payload) => Uint8List.fromList([
  ..._u32(payload.length + 8),
  ..._u32(type),
  ...payload,
]);

class _PacketReader {
  _PacketReader(Stream<Uint8List> stream) : _iterator = StreamIterator(stream);

  final StreamIterator<Uint8List> _iterator;
  final _buffer = <int>[];

  Future<(int, Uint8List)> read() async {
    final header = ByteData.sublistView(await _take(8));
    return (
      header.getUint32(4, Endian.little),
      await _take(header.getUint32(0, Endian.little) - 8),
    );
  }

  Future<Uint8List> _take(int length) async {
    while (_buffer.length < length) {
      if (!await _iterator.moveNext()) throw const SocketException('Closed');
      _buffer.addAll(_iterator.current);
    }
    final result = Uint8List.fromList(_buffer.take(length).toList());
    _buffer.removeRange(0, length);
    return result;
  }

  Future<void> close() async {
    await _iterator.cancel();
  }
}
