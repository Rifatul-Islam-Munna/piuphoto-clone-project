import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/guest/guest_face_delivery.dart';
import 'package:mobileapp/core/network/dio_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const eventId = '0123456789abcdef01234567';
  late _GalleryAccessServer server;

  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://gallery.invalid');
    DioHelper.init();
    DioHelper.dio.interceptors.clear();
    server = _GalleryAccessServer();
    DioHelper.dio.httpClientAdapter = server;
  });

  tearDown(() => DioHelper.dio.close(force: true));

  test('an enabled guest QR can be shared without manage permission', () async {
    server
      ..faceSearchEnabled = true
      ..canManage = false;

    await ensureGuestFaceDeliveryEnabled(eventId);

    expect(server.requests.map((request) => request.method), ['GET']);
    expect(server.requests.single.path, '/gallery-access/info');
    expect(server.requests.single.queryParameters, {'eventId': eventId});
    expect(server.faceSearchEnabled, isTrue);
  });

  test('disabled delivery is enabled with consent and verified', () async {
    await ensureGuestFaceDeliveryEnabled(eventId);

    expect(server.requests.map((request) => request.method), [
      'GET',
      'PATCH',
      'GET',
    ]);
    expect(server.requests[1].path, '/gallery-access/settings');
    expect(_requestData(server.requests[1]), {
      'eventId': eventId,
      'faceSearchEnabled': true,
      'faceConsentRequired': true,
    });
    for (final request in server.requests.where(
      (item) => item.method == 'GET',
    )) {
      expect(request.path, '/gallery-access/info');
      expect(request.queryParameters, {'eventId': eventId});
    }
    expect(server.faceSearchEnabled, isTrue);
  });

  test(
    'denied settings permission propagates without claiming enabled',
    () async {
      server.canManage = false;

      await expectLater(
        ensureGuestFaceDeliveryEnabled(eventId),
        throwsA(
          isA<DioException>()
              .having((error) => error.response?.statusCode, 'status', 403)
              .having((error) => error.response?.data, 'response', {
                'message': 'You cannot manage this event',
              }),
        ),
      );

      expect(server.requests.map((request) => request.method), [
        'GET',
        'PATCH',
      ]);
      expect(server.faceSearchEnabled, isFalse);
    },
  );

  test(
    'a successful PATCH without enabled readback fails preparation',
    () async {
      server.persistChanges = false;

      await expectLater(
        ensureGuestFaceDeliveryEnabled(eventId),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Face delivery was not enabled',
          ),
        ),
      );

      expect(server.requests.map((request) => request.method), [
        'GET',
        'PATCH',
        'GET',
      ]);
      expect(server.faceSearchEnabled, isFalse);
    },
  );
}

Map<String, dynamic> _requestData(RequestOptions request) {
  final data = request.data;
  return Map<String, dynamic>.from(
    data is String ? jsonDecode(data) as Map : data as Map,
  );
}

ResponseBody _json(Map<String, dynamic> data, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _GalleryAccessServer implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  bool faceSearchEnabled = false;
  bool canManage = true;
  bool persistChanges = true;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    requests.add(options);
    if (options.method == 'GET' && options.path == '/gallery-access/info') {
      return _json({'faceSearchEnabled': faceSearchEnabled});
    }
    if (options.method == 'PATCH' &&
        options.path == '/gallery-access/settings') {
      if (!canManage) {
        return _json({'message': 'You cannot manage this event'}, status: 403);
      }
      if (persistChanges) {
        faceSearchEnabled = _requestData(options)['faceSearchEnabled'] == true;
      }
      return _json({'success': true});
    }
    throw StateError('Unexpected request: ${options.method} ${options.path}');
  }

  @override
  void close({bool force = false}) {}
}
