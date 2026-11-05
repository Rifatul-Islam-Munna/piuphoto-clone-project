import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/canon_ccapi_camera.dart';

void main() {
  test(
    'discovery announcements survive polling/download failure until local acknowledgement',
    () async {
      final server = await _CcapiServer.start();
      server.events.addAll([
        const _Events({
          'addedcontents': ['/ccapi/ver140/contents/SHOT0001.JPG'],
        }),
        const _Events({}, status: 503),
        const _Events({
          'addedcontents': ['/ccapi/ver140/contents/SHOT0002.JPG'],
        }),
        const _Events({
          'addedcontents': [
            '/ccapi/ver140/contents/SHOT0001.JPG',
            '/ccapi/ver140/contents/SHOT0002.JPG',
          ],
        }),
      ]);
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });

      final first = (await camera.pollAddedContents()).single;
      expect(first.name, 'SHOT0001.JPG');
      server.failDownloads = 1;
      await expectLater(camera.download(first), throwsA(anything));
      final retried = await camera.pollAddedContents();
      expect(retried.map((content) => content.name), [
        'SHOT0001.JPG',
        'SHOT0002.JPG',
      ]);
      expect(await camera.download(retried.first), [1, 2, 3, 4]);
      // Only persistence acknowledgement removes an item, not download success.
      camera.acknowledgeContents([first.url]);
      final remaining = await camera.pollAddedContents();
      expect(remaining.single.name, 'SHOT0002.JPG');
      camera.acknowledgeContents(remaining.map((content) => content.url));
      expect(await camera.pollAddedContents(), isEmpty);
    },
  );

  test('concurrent callers share one destructive event poll', () async {
    final server = await _CcapiServer.start();
    final camera = await _connect(server);
    addTearDown(() async {
      await camera.close();
      await server.close();
    });
    server.events.add(
      const _Events({
        'addedcontents': ['/ccapi/ver140/contents/SHOT0003.JPG'],
      }),
    );
    server.holdPoll = Completer<void>();

    final first = camera.pollAddedContents();
    final second = camera.pollAddedContents();
    await server.pollStarted.future;
    expect(server.pollRequests, 2); // Discovery + one live poll.
    server.holdPoll!.complete();
    expect((await first).single.name, 'SHOT0003.JPG');
    expect((await second).single.name, 'SHOT0003.JPG');
    expect(server.pollRequests, 2);
  });

  test(
    'unacknowledged contents survive a successful poll with no new events',
    () async {
      final server = await _CcapiServer.start();
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });
      server.events.add(
        const _Events({
          'addedcontents': ['/ccapi/ver140/contents/SHOT0004.CR3'],
        }),
      );

      final pending = await camera.pollAddedContents();
      expect(pending.single.name, 'SHOT0004.CR3');
      expect(await camera.download(pending.single), hasLength(4));
      expect((await camera.pollAddedContents()).single.url, pending.single.url);
      camera.acknowledgeContents([pending.single.url]);
      expect(await camera.pollAddedContents(), isEmpty);
    },
  );

  test(
    'truncated HTTP file is never accepted and its announcement is retained',
    () async {
      final server = await _CcapiServer.start();
      server.events.add(
        const _Events({
          'addedcontents': ['/ccapi/ver140/contents/SHOT0005.JPG'],
        }),
      );
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });
      final photo = (await camera.pollAddedContents()).single;
      server.truncateDownload = true;

      List<int>? downloaded;
      try {
        downloaded = await camera.download(photo);
      } catch (_) {
        // Dio can reject the truncated HTTP body before application validation.
      }
      expect(downloaded, isNull);
      expect((await camera.pollAddedContents()).single.url, photo.url);
      server.truncateDownload = false;
      expect(await camera.download(photo), hasLength(4));
    },
  );

  test(
    'camera credentials and downloads are restricted to the camera origin',
    () async {
      final server = await _CcapiServer.start();
      server.events.add(
        const _Events({
          'addedcontents': [
            'http://unrelated.invalid/SHOT0006.JPG',
            '/ccapi/ver140/contents/SHOT0007.JPG',
          ],
        }),
      );
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });

      expect((await camera.pollAddedContents()).single.name, 'SHOT0007.JPG');
      expect(
        await camera.download(
          const CanonCcapiContent(
            url: 'http://unrelated.invalid/SHOT0006.JPG',
            name: 'SHOT0006.JPG',
          ),
        ),
        isNull,
      );
      expect(server.downloadRequests, 0);
    },
  );

  test(
    'closing cancels an active poll and prevents stale results or new requests',
    () async {
      final server = await _CcapiServer.start();
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });
      server.holdPoll = Completer<void>();
      final poll = camera.pollAddedContents();
      final failedPoll = expectLater(poll, throwsA(anything));
      await server.pollStarted.future;

      await camera.close();
      await failedPoll;
      expect(camera.isClosed, isTrue);
      await expectLater(camera.pollAddedContents(), throwsStateError);
      expect(server.pollRequests, 2);
    },
  );
}

Future<CanonCcapiCamera> _connect(_CcapiServer server) async {
  final camera = await CanonCcapiCamera.discover([
    Uri(
      scheme: 'http',
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
    ),
  ], timeout: const Duration(seconds: 2));
  expect(camera, isNotNull);
  return camera!;
}

class _Events {
  const _Events(this.payload, {this.status = 200});
  final Object payload;
  final int status;
}

class _CcapiServer {
  _CcapiServer(this._server);
  final HttpServer _server;
  final events = Queue<_Events>();
  final pollStarted = Completer<void>();
  Completer<void>? holdPoll;
  int pollRequests = 0;
  int downloadRequests = 0;
  int failDownloads = 0;
  bool truncateDownload = false;

  int get port => _server.port;

  static Future<_CcapiServer> start() async {
    final server = _CcapiServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    server._server.listen((request) {
      unawaited(server._request(request));
    });
    return server;
  }

  Future<void> _request(HttpRequest request) async {
    try {
      if (request.uri.path.endsWith('/event/polling')) {
        pollRequests++;
        if (pollRequests > 1 && !pollStarted.isCompleted) {
          pollStarted.complete();
        }
        await holdPoll?.future;
        final event = events.isEmpty ? const _Events({}) : events.removeFirst();
        request.response.statusCode = event.status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(event.payload));
      } else {
        downloadRequests++;
        if (failDownloads > 0) {
          failDownloads--;
          request.response.statusCode = 503;
        } else if (truncateDownload) {
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.contentLength = 10;
          final socket = await request.response.detachSocket(
            writeHeaders: true,
          );
          socket.add([1, 2, 3, 4]);
          await socket.flush();
          await socket.close();
          return;
        } else {
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.contentLength = 4;
          request.response.add([1, 2, 3, 4]);
        }
      }
      await request.response.close();
    } catch (_) {
      // The client may cancel a held response or deliberately reject a body.
    }
  }

  Future<void> close() async {
    if (holdPoll != null && !holdPoll!.isCompleted) {
      holdPoll!.complete();
    }
    await _server.close(force: true);
  }
}
