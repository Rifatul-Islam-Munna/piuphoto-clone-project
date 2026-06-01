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
    String? lastError,
  }) async {
    await _queueBytes(
      bytes: bytes,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      lastError: lastError,
    );
  }

  static Future<void> processQueue() async {
    if (isProcessing.value || UploadQueueStorage.items.value.isEmpty) return;

    isProcessing.value = true;
    try {
      final snapshot = List<PendingUploadItem>.from(UploadQueueStorage.items.value);
      for (final item in snapshot) {
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
          await UploadQueueStorage.update(
            item.copyWith(
              attempts: item.attempts + 1,
              lastError: _errorText(error),
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

  static Future<void> _queueFile({
    required String sourcePath,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? lastError,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Local import file missing before queue');
    }

    final itemId = DateTime.now().microsecondsSinceEpoch.toString();
    final target = await _queueTargetPath(itemId, filename);
    await sourceFile.copy(target);

    await UploadQueueStorage.add(
      PendingUploadItem(
        id: itemId,
        eventId: event.id,
        eventTitle: event.title,
        localPath: target,
        filename: filename,
        source: source,
        isEnhanced: isEnhanced,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        albumId: albumId,
        lastError: lastError,
      ),
    );
  }

  static Future<void> _queueBytes({
    required Uint8List bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? lastError,
  }) async {
    final itemId = DateTime.now().microsecondsSinceEpoch.toString();
    final target = await _queueTargetPath(itemId, filename);
    final file = File(target);
    await file.writeAsBytes(bytes, flush: true);

    await UploadQueueStorage.add(
      PendingUploadItem(
        id: itemId,
        eventId: event.id,
        eventTitle: event.title,
        localPath: target,
        filename: filename,
        source: source,
        isEnhanced: isEnhanced,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        albumId: albumId,
        lastError: lastError,
      ),
    );
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
}
