import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/debug_pc_camera_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('PC simulator only allows private/local network addresses', () {
    expect(
      parseDebugPcSimulatorUrl('192.168.0.197').toString(),
      'http://192.168.0.197:8765',
    );
    expect(parseDebugPcSimulatorUrl('172.20.10.2:9988').port, 9988);
    expect(parseDebugPcSimulatorUrl('10.0.0.5').host, '10.0.0.5');
    expect(parseDebugPcSimulatorUrl('localhost').port, 8765);
    expect(parseDebugPcSimulatorUrl('airpix.local').port, 8765);
    for (final input in <String>[
      '',
      'https://192.168.0.197:8765',
      'http://8.8.8.8:8765',
      'https://example.com',
      'http://192.168.0.10:8765/photo',
      'http://192.168.0.10:8765?foo=bar',
      'http://user@192.168.0.10',
    ]) {
      expect(
        () => parseDebugPcSimulatorUrl(input),
        throwsFormatException,
        reason: 'Should reject $input',
      );
    }
  });

  test('simulator photo events download to phone and acknowledge', () async {
    const imageBytes = <int>[0xff, 0xd8, 0xff, 0xd9];
    final temp = await Directory.systemTemp.createTemp('airpix-pc-sim-test-');
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (_) async => temp.path);

    var sequence = 0;
    var acked = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      switch (path) {
        case '/health':
          request.response.write(jsonEncode({'ok': true}));
        case '/events':
          final after =
              int.tryParse(request.uri.queryParameters['after'] ?? '') ?? 0;
          if (sequence <= after) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          request.response.write(jsonEncode({'seq': sequence}));
        case '/pending':
          request.response.write(
            jsonEncode({
              'photos': acked
                  ? []
                  : [
                      {
                        'id': 'mock-001',
                        'name': 'NEW-SHOT.JPG',
                        'size': imageBytes.length,
                      },
                    ],
            }),
          );
        case '/photo/mock-001':
          request.response.headers.set('x-photo-name', 'NEW-SHOT.JPG');
          request.response.headers.contentType = ContentType('image', 'jpeg');
          request.response.add(imageBytes);
        case '/ack':
          final body = await utf8.decoder.bind(request).join();
          acked = (jsonDecode(body)['ids'] as List).contains('mock-001');
          request.response.write(jsonEncode({'ok': true}));
        default:
          request.response.statusCode = HttpStatus.notFound;
          request.response.write('{}');
      }
      await request.response.close();
    });
    final transport = DebugPcCameraTransport(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      eventTimeout: const Duration(seconds: 1),
    );
    try {
      final eventFuture = transport
          .eventsForSession('test-session')
          .firstWhere((event) => event.type == 'photosAvailable');
      final session = await transport.start('test-session');
      expect(session.physicalShutter, 'unknown');
      expect(session.name, contains('test only'));
      sequence = 1;
      final received = await eventFuture.timeout(const Duration(seconds: 4));
      expect(received.sessionId, 'test-session');
      final pending = await transport.pending('test-session');
      expect(pending, hasLength(1));
      expect(pending.single.name, 'NEW-SHOT.JPG');
      final photo = await transport.download('test-session', 'mock-001');
      expect(await File(photo.path).readAsBytes(), imageBytes);
      await transport.acknowledge('test-session', ['mock-001']);
      expect(acked, isTrue);
      expect(await transport.pending('test-session'), isEmpty);
      await transport.stop('test-session');
    } finally {
      await server.close(force: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathChannel, null);
      await temp.delete(recursive: true);
    }
  });
}
