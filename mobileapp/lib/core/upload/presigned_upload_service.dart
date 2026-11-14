import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mobileapp/core/network/dio_helper.dart';

class PresignedUploadService {
  PresignedUploadService._();

  // No app auth interceptor or cookies on requests to storage.
  static final Dio _storage = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(minutes: 15),
      receiveTimeout: const Duration(seconds: 60),
      responseType: ResponseType.plain,
    ),
  );

  @visibleForTesting
  static Dio get storageDio => _storage;

  static Future<String> uploadFile({
    required String path,
    required String filename,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final file = File(path);
    return _upload(
      filename: filename,
      size: await file.length(),
      openStream: file.openRead,
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
  }

  static Future<String> uploadBytes({
    required Uint8List bytes,
    required String filename,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) => _upload(
    filename: filename,
    size: bytes.length,
    openStream: () => Stream.value(bytes),
    cancelToken: cancelToken,
    onSendProgress: onSendProgress,
  );

  static Future<String> _upload({
    required String filename,
    required int size,
    required Stream<List<int>> Function() openStream,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
  }) async {
    final response = await DioHelper.post(
      '/image/presign',
      data: {
        'fileName': filename,
        'contentType': 'application/octet-stream',
        'size': size,
      },
      cancelToken: cancelToken,
    );
    final data = response.data;
    if (data is! Map ||
        data['uploadUrl'] is! String ||
        data['url'] is! String ||
        (data['uploadUrl'] as String).isEmpty ||
        (data['url'] as String).isEmpty ||
        data['headers'] is! Map) {
      throw StateError('Could not prepare direct image upload');
    }
    if (cancelToken?.isCancelled == true) throw cancelToken!.cancelError!;
    await _storage.put<void>(
      data['uploadUrl'] as String,
      data: openStream(),
      options: Options(
        headers: {
          ...Map<String, dynamic>.from(data['headers'] as Map),
          Headers.contentLengthHeader: size,
        },
        responseType: ResponseType.plain,
      ),
      cancelToken: cancelToken,
      onSendProgress: onSendProgress,
    );
    return data['url'] as String;
  }

  static Future<List<String>> uploadFiles(
    List<({String path, String filename})> files,
  ) async {
    final urls = List<String>.filled(files.length, '');
    var next = 0;
    Future<void> worker() async {
      while (next < files.length) {
        final index = next++;
        urls[index] = await uploadFile(
          path: files[index].path,
          filename: files[index].filename,
        );
      }
    }

    // Bound concurrent disk readers and network transfers; preserve input order.
    await Future.wait([
      for (var i = 0; i < 3 && i < files.length; i++) worker(),
    ]);
    return urls;
  }
}
