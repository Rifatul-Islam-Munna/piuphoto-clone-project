import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:path_provider/path_provider.dart';

class UploadQueueService {
  UploadQueueService._();

  static const _maxRetryDelayMinutes = 30;
  static final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  static final Map<String, Future<void>> _remoteSyncChains = {};
  static Timer? _timer;

  static void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => processQueue());
    unawaited(_backfillPendingLedger());
    unawaited(_syncRecentLedger());
    unawaited(processQueue());
  }

  static String _newTransferId() =>
      DateTime.now().microsecondsSinceEpoch.toString();

  static String _stableTransferId({
    required EventSummary event,
    required String source,
    required String fingerprint,
  }) {
    const offsetBasis = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xFFFFFFFFFFFFFFFF;
    var hash = offsetBasis;
    for (final byte in utf8.encode('${event.id}|$source|$fingerprint')) {
      hash ^= byte;
      hash = (hash * prime) & mask;
    }
    return 'camera-${hash.toRadixString(16).padLeft(16, '0')}';
  }

  static Future<void> _backfillPendingLedger() async {
    for (final pending in UploadQueueStorage.items.value) {
      if (TransferLedgerStorage.find(pending.id) != null) continue;
      final event = EventSummary(
        id: pending.eventId,
        title: pending.eventTitle,
      );
      await _createLedger(
        transferId: pending.id,
        event: event,
        filename: pending.filename,
        source: pending.source,
        status: TransferLedgerStatus.queued,
        localPath: pending.localPath,
        albumId: pending.albumId,
        cameraId: pending.cameraId,
        error: pending.lastError,
      );
      final ledger = TransferLedgerStorage.find(pending.id);
      if (ledger != null) unawaited(_syncRemote(ledger));
    }
  }

  static Future<void> _syncRecentLedger() async {
    final recent = TransferLedgerStorage.items.value.take(250).toList();
    for (final item in recent) {
      await _syncRemote(item);
    }
  }

  static Future<void> _createLedger({
    required String transferId,
    required EventSummary event,
    required String filename,
    required String source,
    required TransferLedgerStatus status,
    String? localPath,
    String? albumId,
    String? cameraId,
    String? error,
    int progress = 0,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await TransferLedgerStorage.upsert(
      TransferLedgerItem(
        id: transferId,
        eventId: event.id,
        eventTitle: event.title,
        filename: filename,
        source: source,
        status: status,
        createdAt: TransferLedgerStorage.find(transferId)?.createdAt ?? now,
        updatedAt: now,
        localPath: localPath,
        albumId: albumId,
        cameraId: cameraId,
        progress: progress,
        error: error,
      ),
    );
    final ledger = TransferLedgerStorage.find(transferId);
    if (ledger != null) unawaited(_syncRemote(ledger));
  }

  static Future<void> _syncRemote(
    TransferLedgerItem item, {
    String? eventImageId,
  }) async {
    final previous = _remoteSyncChains[item.id] ?? Future<void>.value();
    late final Future<void> next;
    next = previous
        .then((_) async {
          try {
            await DioHelper.post(
              '/transfer-status',
              data: {
                'eventId': item.eventId,
                'clientTransferId': item.id,
                'filename': item.filename,
                'source': item.source,
                'albumId': ?item.albumId,
                'cameraId': ?item.cameraId,
                'mediaType': _mediaType(item.filename),
                'status': item.status.name,
                'progress': item.progress,
                'bytesSent': item.bytesSent,
                'bytesTotal': item.bytesTotal,
                'bytesPerSecond': item.bytesPerSecond,
                if (item.error != null) 'error': item.error,
                if (item.imageUrl != null) 'imageUrl': item.imageUrl,
                'eventImageId': ?eventImageId,
              },
            );
          } catch (_) {
            // Tracking must never break camera/import delivery.
          }
        })
        .whenComplete(() {
          if (identical(_remoteSyncChains[item.id], next)) {
            _remoteSyncChains.remove(item.id);
          }
        });
    _remoteSyncChains[item.id] = next;
    await next;
  }

  static String _mediaType(String filename) {
    final lower = filename.toLowerCase();
    return const ['.mp4', '.mov', '.m4v', '.avi'].any(lower.endsWith)
        ? 'video'
        : 'photo';
  }

  static Future<void> _setStatus(
    String transferId,
    TransferLedgerStatus status, {
    int? progress,
    int? bytesSent,
    int? bytesTotal,
    double? bytesPerSecond,
    String? error,
    String? imageUrl,
    String? localPath,
    String? eventImageId,
  }) async {
    await TransferLedgerStorage.updateStatus(
      transferId,
      status,
      progress: progress,
      bytesSent: bytesSent,
      bytesTotal: bytesTotal,
      bytesPerSecond: bytesPerSecond,
      error: error,
      imageUrl: imageUrl,
      localPath: localPath,
    );
    final item = TransferLedgerStorage.find(transferId);
    if (item != null) {
      unawaited(_syncRemote(item, eventImageId: eventImageId));
    }
  }

  static Future<bool> uploadNowOrQueueFile({
    required EventSummary event,
    required String path,
    required String filename,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? cameraId,
  }) async {
    final transferId = _newTransferId();
    await _createLedger(
      transferId: transferId,
      event: event,
      filename: filename,
      source: source,
      status: TransferLedgerStatus.detected,
      localPath: path,
      albumId: albumId,
      cameraId: cameraId,
    );
    try {
      await _uploadSingle(
        path: path,
        filename: filename,
        event: event,
        isEnhanced: isEnhanced,
        albumId: albumId,
        transferId: transferId,
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
        cameraId: cameraId,
        lastError: _errorText(error),
        transferId: transferId,
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
    String? cameraId,
  }) async {
    final transferId = _newTransferId();
    await _createLedger(
      transferId: transferId,
      event: event,
      filename: filename,
      source: source,
      status: TransferLedgerStatus.detected,
      albumId: albumId,
      cameraId: cameraId,
    );
    try {
      await _uploadSingleBytes(
        bytes: bytes,
        filename: filename,
        event: event,
        isEnhanced: isEnhanced,
        albumId: albumId,
        transferId: transferId,
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
        cameraId: cameraId,
        lastError: _errorText(error),
        transferId: transferId,
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
    String? cameraId,
    String? lastError,
  }) async {
    await _queueFile(
      sourcePath: path,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      cameraId: cameraId,
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
    String? cameraId,
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
      cameraId: cameraId,
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
    String? cameraId,
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
      cameraId: cameraId,
      lastError: tryUploadNow
          ? 'Waiting to upload'
          : 'Waiting for internet connection',
      fingerprint: fingerprint,
    );
    if (tryUploadNow) {
      await processQueue();
      return !UploadQueueStorage.items.value.any(
        (item) => item.id == queued.id,
      );
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
    String? cameraId,
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
      cameraId: cameraId,
      lastError: tryUploadNow
          ? 'Waiting to upload'
          : 'Waiting for internet connection',
      fingerprint: fingerprint,
    );
    if (tryUploadNow) {
      await processQueue();
      return !UploadQueueStorage.items.value.any(
        (item) => item.id == queued.id,
      );
    }
    return false;
  }

  static Future<void> retryNow(String transferId) async {
    PendingUploadItem? queued;
    for (final item in UploadQueueStorage.items.value) {
      if (item.id == transferId) {
        queued = item;
        break;
      }
    }
    if (queued == null) return;
    await UploadQueueStorage.update(
      queued.copyWith(nextRetryAt: 0, clearLastError: true),
    );
    await _setStatus(transferId, TransferLedgerStatus.queued, progress: 0);
    await processQueue();
  }

  static Future<void> processQueue() async {
    if (isProcessing.value || UploadQueueStorage.items.value.isEmpty) return;
    isProcessing.value = true;
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final snapshot = List<PendingUploadItem>.from(
        UploadQueueStorage.items.value,
      );
      for (final item in snapshot) {
        if (item.nextRetryAt != null && item.nextRetryAt! > nowMs) continue;

        final file = File(item.localPath);
        if (!await file.exists()) {
          await _setStatus(
            item.id,
            TransferLedgerStatus.failed,
            error: 'Local queued file is missing',
          );
          await UploadQueueStorage.remove(item.id);
          continue;
        }

        final event = EventSummary(id: item.eventId, title: item.eventTitle);
        try {
          await _setStatus(
            item.id,
            TransferLedgerStatus.uploading,
            progress: 10,
          );
          await _uploadSingle(
            path: item.localPath,
            filename: item.filename,
            event: event,
            isEnhanced: item.isEnhanced,
            albumId: item.albumId,
            transferId: item.id,
          );
          try {
            await file.delete();
          } catch (_) {}
          await UploadQueueStorage.remove(item.id);
        } catch (error) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final nextDelayMinutes = _retryDelayMinutes(
            item.attempts + 1,
          ).clamp(1, _maxRetryDelayMinutes);
          final errorText = _errorText(error);
          await _setStatus(
            item.id,
            TransferLedgerStatus.failed,
            error: errorText,
          );
          await UploadQueueStorage.update(
            item.copyWith(
              attempts: item.attempts + 1,
              lastError: errorText,
              lastAttemptAt: now,
              nextRetryAt:
                  now + Duration(minutes: nextDelayMinutes).inMilliseconds,
            ),
          );
        }
      }
    } finally {
      isProcessing.value = false;
    }
  }

  static void Function(int, int) _uploadProgressReporter(String transferId) {
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    var lastReportedAt = startedAt;
    var lastProgress = 15;

    return (sent, total) {
      if (total <= 0) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final mappedProgress = (15 + ((sent / total) * 55).round()).clamp(15, 70);
      final shouldReport =
          sent >= total ||
          mappedProgress - lastProgress >= 3 ||
          now - lastReportedAt >= 500;
      if (!shouldReport) return;

      lastProgress = mappedProgress;
      lastReportedAt = now;
      final elapsedMs = (now - startedAt).clamp(1, 1 << 31);
      final bytesPerSecond = sent * 1000 / elapsedMs;
      unawaited(
        _setStatus(
          transferId,
          TransferLedgerStatus.uploading,
          progress: mappedProgress,
          bytesSent: sent,
          bytesTotal: total,
          bytesPerSecond: bytesPerSecond,
        ),
      );
    };
  }

  static Future<void> _uploadSingle({
    required String path,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String transferId,
    String? albumId,
  }) async {
    await _setStatus(transferId, TransferLedgerStatus.uploading, progress: 15);
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    });
    final response = await DioHelper.post(
      '/image/upload',
      data: formData,
      onSendProgress: _uploadProgressReporter(transferId),
    );
    final imageUrl = response.data['url']?.toString() ?? '';
    if (imageUrl.isEmpty) throw Exception('Image upload returned no URL');

    await _setStatus(
      transferId,
      TransferLedgerStatus.processing,
      progress: 75,
      imageUrl: imageUrl,
    );
    final eventResponse = await DioHelper.post(
      '/eventImage',
      data: {
        'eventId': event.id,
        'clientTransferId': transferId,
        'imageUrl': imageUrl,
        'isEnhanced': isEnhanced,
        'mediaType': _mediaType(filename),
        'albumId': ?albumId,
      },
    );
    final eventResponseData = eventResponse.data;
    final createdData = eventResponseData is Map
        ? eventResponseData['data']
        : null;
    final eventImageId = createdData is Map
        ? createdData['_id']?.toString()
        : null;
    final isPublished = createdData is Map
        ? createdData['isPublished'] != false
        : true;
    await _setStatus(
      transferId,
      isPublished
          ? TransferLedgerStatus.published
          : TransferLedgerStatus.processing,
      progress: 100,
      imageUrl: imageUrl,
      eventImageId: eventImageId,
    );
  }

  static Future<void> _uploadSingleBytes({
    required Uint8List bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String transferId,
    String? albumId,
  }) async {
    await _setStatus(transferId, TransferLedgerStatus.uploading, progress: 15);
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await DioHelper.post(
      '/image/upload',
      data: formData,
      onSendProgress: _uploadProgressReporter(transferId),
    );
    final imageUrl = response.data['url']?.toString() ?? '';
    if (imageUrl.isEmpty) throw Exception('Image upload returned no URL');

    await _setStatus(
      transferId,
      TransferLedgerStatus.processing,
      progress: 75,
      imageUrl: imageUrl,
    );
    final eventResponse = await DioHelper.post(
      '/eventImage',
      data: {
        'eventId': event.id,
        'clientTransferId': transferId,
        'imageUrl': imageUrl,
        'isEnhanced': isEnhanced,
        'mediaType': _mediaType(filename),
        'albumId': ?albumId,
      },
    );
    final eventResponseData = eventResponse.data;
    final createdData = eventResponseData is Map
        ? eventResponseData['data']
        : null;
    final eventImageId = createdData is Map
        ? createdData['_id']?.toString()
        : null;
    final isPublished = createdData is Map
        ? createdData['isPublished'] != false
        : true;
    await _setStatus(
      transferId,
      isPublished
          ? TransferLedgerStatus.published
          : TransferLedgerStatus.processing,
      progress: 100,
      imageUrl: imageUrl,
      eventImageId: eventImageId,
    );
  }

  static Future<PendingUploadItem> _queueFile({
    required String sourcePath,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? cameraId,
    String? lastError,
    String? fingerprint,
    String? transferId,
  }) async {
    if (fingerprint != null) {
      final existing = UploadQueueStorage.findByFingerprint(fingerprint);
      if (existing != null) return existing;
    }

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('Local import file missing before queue');
    }

    final itemId =
        transferId ??
        (fingerprint == null
            ? _newTransferId()
            : _stableTransferId(
                event: event,
                source: source,
                fingerprint: fingerprint,
              ));
    final target = await _queueTargetPath(itemId, filename);
    final completed = TransferLedgerStorage.find(itemId);
    if (completed?.isUploaded == true) {
      return PendingUploadItem(
        id: itemId,
        eventId: event.id,
        eventTitle: event.title,
        localPath: completed?.localPath ?? target,
        filename: filename,
        source: source,
        isEnhanced: isEnhanced,
        createdAt:
            completed?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        fingerprint: fingerprint,
        albumId: albumId,
        cameraId: cameraId,
      );
    }
    if (sourceFile.path != target) await sourceFile.copy(target);

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
      cameraId: cameraId,
      lastError: lastError,
    );
    final alreadyQueued = UploadQueueStorage.items.value.any(
      (current) => current.id == item.id,
    );
    if (alreadyQueued) {
      await UploadQueueStorage.update(item);
    } else {
      await UploadQueueStorage.add(item);
    }
    await _createLedger(
      transferId: itemId,
      event: event,
      filename: filename,
      source: source,
      status: TransferLedgerStatus.queued,
      localPath: target,
      albumId: albumId,
      cameraId: cameraId,
      error: lastError,
      progress: 0,
    );
    final ledger = TransferLedgerStorage.find(itemId);
    if (ledger != null) unawaited(_syncRemote(ledger));
    return item;
  }

  static Future<PendingUploadItem> _queueBytes({
    required Uint8List bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? cameraId,
    String? lastError,
    String? fingerprint,
    String? transferId,
  }) async {
    if (fingerprint != null) {
      final existing = UploadQueueStorage.findByFingerprint(fingerprint);
      if (existing != null) return existing;
    }

    final itemId =
        transferId ??
        (fingerprint == null
            ? _newTransferId()
            : _stableTransferId(
                event: event,
                source: source,
                fingerprint: fingerprint,
              ));
    final target = await _queueTargetPath(itemId, filename);
    final completed = TransferLedgerStorage.find(itemId);
    if (completed?.isUploaded == true) {
      return PendingUploadItem(
        id: itemId,
        eventId: event.id,
        eventTitle: event.title,
        localPath: completed?.localPath ?? target,
        filename: filename,
        source: source,
        isEnhanced: isEnhanced,
        createdAt:
            completed?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
        fingerprint: fingerprint,
        albumId: albumId,
        cameraId: cameraId,
      );
    }
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
      cameraId: cameraId,
      lastError: lastError,
    );
    final alreadyQueued = UploadQueueStorage.items.value.any(
      (current) => current.id == item.id,
    );
    if (alreadyQueued) {
      await UploadQueueStorage.update(item);
    } else {
      await UploadQueueStorage.add(item);
    }
    await _createLedger(
      transferId: itemId,
      event: event,
      filename: filename,
      source: source,
      status: TransferLedgerStatus.queued,
      localPath: target,
      albumId: albumId,
      cameraId: cameraId,
      error: lastError,
      progress: 0,
    );
    final ledger = TransferLedgerStorage.find(itemId);
    if (ledger != null) unawaited(_syncRemote(ledger));
    return item;
  }

  static Future<String> _queueTargetPath(String itemId, String filename) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}${Platform.pathSeparator}upload_queue');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safeName = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '${dir.path}${Platform.pathSeparator}${itemId}_$safeName';
  }

  static String _errorText(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      final message = data is Map ? data['message']?.toString() : null;
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
