import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/upload/presigned_upload_service.dart';

void main() {
  late _DirectUploadAdapter adapter;
  setUp(() {
    dotenv.loadFromString(envString: 'API_URL=https://api.invalid');
    DioHelper.init();
    DioHelper.dio.interceptors.clear();
    DioHelper.dio.options.headers['access_token'] = 'app-token';
    adapter = _DirectUploadAdapter();
    DioHelper.dio.httpClientAdapter = adapter;
    PresignedUploadService.storageDio.httpClientAdapter = adapter;
  });

  tearDown(() => DioHelper.dio.close(force: true));

  test('uploads raw bytes to R2 without leaking app credentials', () async {
    final progress = <int>[];
    final url = await PresignedUploadService.uploadBytes(
      bytes: Uint8List.fromList([1, 2, 3]),
      filename: 'photo.jpg',
      onSendProgress: (sent, total) => progress.add(sent),
    );
    expect(url, 'https://images.invalid/photo.jpg');
    expect(adapter.requests.map((r) => r.method), ['POST', 'PUT']);
    final payload = adapter.requests.first.data;
    final metadata = payload is String
        ? jsonDecode(payload) as Map
        : payload as Map;
    expect(metadata['fileName'], 'photo.jpg');
    expect(metadata['size'], 3);
    final put = adapter.requests.last;
    expect(put.uri.host, 'r2.invalid');
    expect(put.headers.containsKey('access_token'), isFalse);
    expect(put.headers[Headers.contentLengthHeader], 3);
    expect(put.contentType, 'image/jpeg');
    expect(adapter.uploadedBytes, [1, 2, 3]);
    expect(progress.last, 3);
  });

  test(
    'manual batch emits per-file progress and completion callbacks',
    () async {
      final directory = await Directory.systemTemp.createTemp('airpix-batch-');
      try {
        final first = File('${directory.path}/first.jpg');
        final second = File('${directory.path}/second.jpg');
        await first.writeAsBytes([1, 2, 3]);
        await second.writeAsBytes([4, 5, 6]);
        final started = <int>[];
        final stored = <int>[];
        final progress = <int>[];

        final urls = await PresignedUploadService.uploadFiles(
          [
            (path: first.path, filename: 'first.jpg'),
            (path: second.path, filename: 'second.jpg'),
          ],
          onStarted: started.add,
          onProgress: (index, sent, total) => progress.add(index),
          onStored: stored.add,
        );
        expect(urls, [
          'https://images.invalid/photo.jpg',
          'https://images.invalid/photo.jpg',
        ]);
        expect(started, containsAll([0, 1]));
        expect(stored, containsAll([0, 1]));
        expect(progress, isNotEmpty);
        expect(
          adapter.requests.where((item) => item.method == 'PUT').length,
          2,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('failed direct PUT never reports a successful upload URL', () async {
    adapter.putStatus = 403;
    await expectLater(
      PresignedUploadService.uploadBytes(
        bytes: Uint8List.fromList([1]),
        filename: 'photo.jpg',
      ),
      throwsA(isA<DioException>()),
    );
  });

  test('cancellation during signing prevents the direct PUT', () async {
    final token = CancelToken();
    adapter.afterSigning = () => token.cancel('cancelled');
    await expectLater(
      PresignedUploadService.uploadBytes(
        bytes: Uint8List.fromList([1]),
        filename: 'photo.jpg',
        cancelToken: token,
      ),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.cancel,
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });
}

class _DirectUploadAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  final uploadedBytes = <int>[];
  int putStatus = 200;
  void Function()? afterSigning;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (options.method == 'PUT') {
      if (requestStream != null) {
        await for (final bytes in requestStream) {
          uploadedBytes.addAll(bytes);
        }
      }
      return ResponseBody.fromString('', putStatus);
    }
    if (requestStream != null) await requestStream.drain<void>();
    afterSigning?.call();
    return ResponseBody.fromString(
      jsonEncode({
        'uploadUrl': 'https://r2.invalid/photo.jpg?signature=test',
        'url': 'https://images.invalid/photo.jpg',
        'method': 'PUT',
        'headers': {'Content-Type': 'image/jpeg'},
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
