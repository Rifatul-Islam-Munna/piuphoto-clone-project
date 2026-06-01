import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';

class UploadQueueService {
  UploadQueueService._();

  static const _maxRetryDelayMinutes = 30;
  static final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  static Timer? _timer;

  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => processQueue(),
    );
    unawaited(processQueue());
  }

  static Future<bool> uploadNowOrQueueFile({
    required EventSummary event,
    required String path,
    required String filename,
    required bool isEnhanced,
    required String source,
    String? albumId,
  }) async {
    try {
      await _uploadSingle(
        path: path,
        filename: filename,
        event: event,
        isEnhanced: isEnhanced,
        albumId: albumId,
      );
      return true;
    } catch (error) {
      await _queueFile(
        sourcePath: path,
        filename: filename,
        event: event,
        isEnhanced: isEnhanced,
        source: source,
        albumId: albumId,
        lastError: _errorText(error),
      );
      return false;
    }
  }

  static Future<bool> uploadNowOrQueueBytes({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required bool isEnhanced,
    required String source,
    String? albumId,
  }) async {
    try {
      await _uploadSingleBytes(
        bytes: bytes,
        filename: filename,
        event: event,
        isEnhanced: isEnhanced,
        albumId: albumId,
      );
      return true;
    } catch (error) {
      await _queueBytes(
        bytes: bytes,
        filename: filename,
        event: event,
        isEnhanced: isEnhanced,
        source: source,
        albumId: albumId,
        lastError: _errorText(error),
      );
      return false;
    }
  }

  static Future<void> queueFileOnly({
    required EventSummary event,
    required String path,
    required String filename,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? lastError,
  }) async {
    await _queueFile(
      sourcePath: path,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      lastError: lastError,
    );
  }

  static Future<void> queueBytesOnly({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? fingerprint,
    String? lastError,
  }) async {
    await _queueBytes(
      bytes: bytes,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      fingerprint: fingerprint,
      lastError: lastError,
    );
  }

  static Future<bool> importBytesLocalFirst({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? fingerprint,
    bool tryUploadNow = false,
  }) async {
    final queued = await _queueBytes(
      bytes: bytes,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      lastError: tryUploadNow ? 'Waiting to upload' : 'Waiting for internet connection',
      fingerprint: fingerprint,
    );

    if (tryUploadNow) {
      await processQueue();
      return !UploadQueueStorage.items.value.any((item) => item.id == queued.id);
    }

    return false;
  }

  static Future<bool> importFileLocalFirst({
    required EventSummary event,
    required String path,
    required String filename,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? fingerprint,
    bool tryUploadNow = false,
  }) async {
    final queued = await _queueFile(
      sourcePath: path,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      lastError: tryUploadNow ? 'Waiting to upload' : 'Waiting for internet connection',
      fingerprint: fingerprint,
    );

    if (tryUploadNow) {
      await processQueue();
      return !UploadQueueStorage.items.value.any((item) => item.id == queued.id);
    }

    return false;
  }

  static Future<void> processQueue() async {
    if (isProcessing.value || UploadQueueStorage.items.value.isEmpty) return;

    isProcessing.value = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final snapshot = List<PendingUploadItem>.from(UploadQueueStorage.items.value);
      for (final item in snapshot) {
        if (item.nextRetryAt != null && item.nextRetryAt! > nowMs) {
          continue;
        }

        final file = File(item.localPath);
        if (!await file.exists()) {
          await UploadQueueStorage.remove(item.id);
          continue;
        }

        final event = EventSummary(
          id: item.eventId,
          title: item.eventTitle,
        );

        try {
          await _uploadSingle(
            path: item.localPath,
            filename: item.filename,
            event: event,
            isEnhanced: item.isEnhanced,
            albumId: item.albumId,
          );
          try {
            await file.delete();
          } catch (_) {}
          await UploadQueueStorage.remove(item.id);
        } catch (error) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final nextDelayMinutes =
              _retryDelayMinutes(item.attempts + 1).clamp(1, _maxRetryDelayMinutes);
          await UploadQueueStorage.update(
            item.copyWith(
              attempts: item.attempts + 1,
              lastError: _errorText(error),
              lastAttemptAt: now,
              nextRetryAt: now + Duration(minutes: nextDelayMinutes).inMilliseconds,
            ),
          );
        }
      }
    } finally {
      isProcessing.value = false;
    }
  }

  static Future<void> _uploadSingle({
    required String path,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    String? albumId,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    final response = await DioHelper.post('/image/upload', data: formData);
    final imageUrl = response.data['url']?.toString() ?? '';
    if (imageUrl.isEmpty) {
      throw Exception('Image upload returned no URL');
    }

    await DioHelper.post(
      '/eventImage',
      data: {
        'eventId': event.id,
        'imageUrl': imageUrl,
        'isEnhanced': isEnhanced,
        if (albumId != null) 'albumId': albumId,
      },
    );
  }

  static Future<void> _uploadSingleBytes({
    required Uint8List bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    String? albumId,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await DioHelper.post('/image/upload', data: formData);
    final imageUrl = response.data['url']?.toString() ?? '';
    if (imageUrl.isEmpty) {
      throw Exception('Image upload returned no URL');
    }

    await DioHelper.post(
      '/eventImage',
      data: {
        'eventId': event.id,
        'imageUrl': imageUrl,
        'isEnhanced': isEnhanced,
        if (albumId != null) 'albumId': albumId,
      },
    );
  }

  static Future<PendingUploadItem> _queueFile({
    required String sourcePath,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? lastError,
    String? fingerprint,
  }) async {
    if (fingerprint != null) {
      final existing = UploadQueueStorage.findByFingerprint(fingerprint);
      if (existing != null) return existing;
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Local import file missing before queue');
    }

    final itemId = DateTime.now().microsecondsSinceEpoch.toString();
    final target = await _queueTargetPath(itemId, filename);
    await sourceFile.copy(target);

    final item = PendingUploadItem(
      id: itemId,
      eventId: event.id,
      eventTitle: event.title,
      localPath: target,
      filename: filename,
      source: source,
      isEnhanced: isEnhanced,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      fingerprint: fingerprint,
      albumId: albumId,
      lastError: lastError,
    );
    await UploadQueueStorage.add(item);
    return item;
  }

  static Future<PendingUploadItem> _queueBytes({
    required Uint8List bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? lastError,
    String? fingerprint,
  }) async {
    if (fingerprint != null) {
      final existing = UploadQueueStorage.findByFingerprint(fingerprint);
      if (existing != null) return existing;
    }

    final itemId = DateTime.now().microsecondsSinceEpoch.toString();
    final target = await _queueTargetPath(itemId, filename);
    final file = File(target);
    await file.writeAsBytes(bytes, flush: true);

    final item = PendingUploadItem(
      id: itemId,
      eventId: event.id,
      eventTitle: event.title,
      localPath: target,
      filename: filename,
      source: source,
      isEnhanced: isEnhanced,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      fingerprint: fingerprint,
      albumId: albumId,
      lastError: lastError,
    );
    await UploadQueueStorage.add(item);
    return item;
  }

  static Future<String> _queueTargetPath(String itemId, String filename) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}upload_queue');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${dir.path}${Platform.pathSeparator}${itemId}_$safeName';
  }

  static String _errorText(Object error) {
    if (error is DioException) {
      final message = error.response?.data?['message']?.toString();
      if (message != null && message.isNotEmpty) return message;
      return error.message ?? 'Network error';
    }
    return error.toString();
  }

  static int _retryDelayMinutes(int attempts) {
    if (attempts <= 1) return 1;
    if (attempts == 2) return 2;
    if (attempts == 3) return 5;
    if (attempts == 4) return 10;
    return 30;
  }
}
