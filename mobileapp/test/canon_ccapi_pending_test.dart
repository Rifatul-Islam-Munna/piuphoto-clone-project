import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:crypto/crypto.dart';
import 'package:mobileapp/core/platform/canon_ccapi_camera.dart';

void main() {
  test(
    'only event and content reads are allowed, even for camera-provided URLs',
    () async {
      final server = await _CcapiServer.start();
      server.events.add(
        const _Events({
          'addedcontents': [
            '/capture/SHOT.JPG',
            '/snapshot.JPG',
            '/live/SHOT.JPG',
            '/ccapi/ver140/shooting/control/shutterbutton.JPG',
            '/ccapi/ver140/contents/../../shooting/SHOT.JPG',
            '/ccapi/ver140/contents/SAFE.JPG',
          ],
        }),
      );
      final camera = await _connect(server);
      addTearDown(() async {
        await camera.close();
        await server.close();
      });
      final pending = await camera.pollAddedContents();
      expect(pending.map((p) => p.name), ['SAFE.JPG']);
      for (final path in [
        '/capture/SHOT.JPG',
        '/live.JPG',
        '/ccapi/ver140/shooting/control/shutterbutton.JPG',
      ]) {
        expect(
          await camera.download(
            CanonCcapiContent(
              url: camera.origin.resolve(path).toString(),
              name: 'SHOT.JPG',
            ),
          ),
          isNull,
        );
      }
      expect(server.downloadRequests, 0);
      expect(await camera.download(pending.single), hasLength(4));
      expect(
        server.requests.every(
          (r) =>
              r.method == 'GET' &&
              (r.uri.path.endsWith('/event/polling') ||
                  r.uri.path == '/ccapi/ver140/contents/SAFE.JPG'),
        ),
        isTrue,
      );
    },
  );

  test('a content redirect cannot invoke a capture or live-view URL', () async {
    final server = await _CcapiServer.start();
    server.events.add(
      const _Events({
        'addedcontents': ['/ccapi/ver140/contents/REDIRECT.JPG'],
      }),
    );
    final camera = await _connect(server);
    addTearDown(() async {
      await camera.close();
      await server.close();
    });
    final content = (await camera.pollAddedContents()).single;
    server.redirectDownloads = true;
    expect(await camera.download(content), isNull);
    expect(server.requests.where((r) => r.uri.path == '/capture'), isEmpty);
    expect((await camera.pollAddedContents()).single.url, content.url);
  });

  test(
    'event discovery redirects are refused without probing control URLs',
    () async {
      final server = await _CcapiServer.start();
      server.redirectEvents = true;
      addTearDown(server.close);
      final camera = await CanonCcapiCamera.discover([
        Uri.parse('http://127.0.0.1:${server.port}'),
      ], exactEndpoint: true);
      expect(camera, isNull);
      expect(server.requests, hasLength(5));
      expect(
        server.requests.every((r) => r.uri.path.endsWith('/event/polling')),
        isTrue,
      );
    },
  );

  test(
    'stopping while connecting cancels discovery without more probes',
    () async {
      final server = await _CcapiServer.start();
      server.holdPoll = Completer<void>();
      addTearDown(server.close);
      final token = CancelToken();
      final connecting = CanonCcapiCamera.discover(
        [Uri.parse('http://127.0.0.1:${server.port}')],
        exactEndpoint: true,
        cancellation: token,
      );
      await server.firstRequest.future;
      token.cancel('Stopped');
      expect(await connecting.timeout(const Duration(seconds: 2)), isNull);
      expect(server.requests, hasLength(1));
    },
  );

  for (final scheme in ['Basic', 'Digest']) {
    test(
      '$scheme login uses a camera challenge and only read endpoints',
      () async {
        final server = await _CcapiServer.start();
        server.authentication = scheme;
        addTearDown(server.close);
        final camera = await CanonCcapiCamera.discover(
          [Uri.parse('http://127.0.0.1:${server.port}')],
          exactEndpoint: true,
          username: 'photographer',
          password: 'test-password',
        );
        expect(camera, isNotNull);
        addTearDown(camera!.close);
        server.events.add(
          const _Events({
            'addedcontents': ['/ccapi/ver140/contents/AUTH.JPG'],
          }),
        );
        final photo = (await camera.pollAddedContents()).single;
        expect(await camera.download(photo), [1, 2, 3, 4]);
        expect(server.authenticatedRequests, greaterThanOrEqualTo(3));
        expect(server.firstAuthorization, isNull);
        expect(server.requests.every((r) => r.method == 'GET'), isTrue);
      },
    );
  }

  test('wrong camera login fails with bounded attempts', () async {
    final server = await _CcapiServer.start();
    server.authentication = 'Digest';
    addTearDown(server.close);
    final camera = await CanonCcapiCamera.discover(
      [Uri.parse('http://127.0.0.1:${server.port}')],
      exactEndpoint: true,
      username: 'photographer',
      password: 'wrong',
    );
    expect(camera, isNull);
    expect(server.requests.length, lessThanOrEqualTo(10));
    expect(server.authenticatedRequests, 0);
  });

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
  final requests = <HttpRequest>[];
  final firstRequest = Completer<void>();
  String? authentication;
  String? firstAuthorization;
  int authenticatedRequests = 0;
  bool redirectDownloads = false;
  bool redirectEvents = false;
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
      if (requests.isEmpty) {
        firstAuthorization = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        firstRequest.complete();
      }
      requests.add(request);
      if (authentication != null) {
        if (!_authorized(request)) {
          request.response.statusCode = 401;
          request.response.headers.set(
            HttpHeaders.wwwAuthenticateHeader,
            authentication == 'Basic'
                ? 'Basic realm="Camera"'
                : 'Digest realm="Camera", nonce="test-nonce", algorithm=MD5, qop="auth"',
          );
          await request.response.close();
          return;
        }
        authenticatedRequests++;
      }
      if (request.uri.path.endsWith('/event/polling')) {
        if (redirectEvents) {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, '/capture');
          await request.response.close();
          return;
        }
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
        if (redirectDownloads) {
          request.response.statusCode = 302;
          request.response.headers.set(HttpHeaders.locationHeader, '/capture');
          await request.response.close();
          return;
        }
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

  bool _authorized(HttpRequest request) {
    final header = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (authentication == 'Basic') {
      return header ==
          'Basic ${base64Encode(utf8.encode('photographer:test-password'))}';
    }
    if (!header.startsWith('Digest ')) return false;
    final fields = <String, String>{
      for (final match in RegExp(
        r'(\w+)=(?:"([^"]*)"|([^,\s]+))',
      ).allMatches(header))
        match.group(1)!: match.group(2) ?? match.group(3)!,
    };
    String hash(String value) => md5.convert(utf8.encode(value)).toString();
    final ha1 = hash('photographer:Camera:test-password');
    final ha2 = hash('GET:${request.uri}');
    final nc = fields['nc'];
    final cnonce = fields['cnonce'];
    final expected = hash('$ha1:test-nonce:$nc:$cnonce:auth:$ha2');
    return fields['username'] == 'photographer' &&
        fields['uri'] == request.uri.toString() &&
        fields['response'] == expected;
  }

  Future<void> close() async {
    if (holdPoll != null && !holdPoll!.isCompleted) {
      holdPoll!.complete();
    }
    await _server.close(force: true);
  }
}
