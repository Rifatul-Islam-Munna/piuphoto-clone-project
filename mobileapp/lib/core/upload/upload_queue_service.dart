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

enum UploadCancellationResult {
  cancelled,
  alreadyCompleted,
  finishing,
  notFound,
}

class _ActiveUpload {
  final cancelToken = CancelToken();
  bool registering = false;
}

class _UploadCancelled implements Exception {
  const _UploadCancelled();
}

class UploadQueueService {
  UploadQueueService._();

  static const _maxRetryDelayMinutes = 30;
  static final ValueNotifier<bool> isProcessing = ValueNotifier<bool>(false);
  static final Map<String, Future<void>> _remoteSyncChains = {};
  static final Map<String, Future<PendingUploadItem>> _fileImportsInFlight = {};
  static final Map<String, _ActiveUpload> _activeUploads = {};
  static final Set<String> _cancelRequested = {};
  static final Map<String, Future<UploadCancellationResult>> _cancellations =
      {};
  static Timer? _timer;
  static Timer? _nextPassTimer;
  static bool _schedulingStopped = false;

  static void start() {
    _schedulingStopped = false;
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _requestAutomaticUpload(),
    );
    unawaited(
      _backfillPendingLedger().catchError((Object error) {
        debugPrint('Camera upload history will be checked again: $error');
      }),
    );
    unawaited(_syncRecentLedger());
    _requestAutomaticUpload();
  }

  static void _requestAutomaticUpload() {
    if (_schedulingStopped) return;
    unawaited(
      processQueue().catchError((Object error) {
        // The photo is already durable. A temporary persistence failure must
        // not escape an unawaited timer/camera callback or stop camera capture.
        debugPrint('Automatic cloud upload will retry: $error');
      }),
    );
  }

  static bool _isCancelled(String id) =>
      _cancelRequested.contains(id) ||
      UploadQueueStorage.isCancelled(id) ||
      TransferLedgerStorage.find(id)?.status == TransferLedgerStatus.cancelled;

  static bool _isCompleted(String id) =>
      UploadQueueStorage.isCompleted(id) ||
      _hasCompletedUpload(TransferLedgerStorage.find(id));

  static bool canCancel(TransferLedgerItem item) =>
      !item.isUploaded &&
      !_isCompleted(item.id) &&
      item.status != TransferLedgerStatus.cancelled &&
      !item.registrationStarted &&
      _activeUploads[item.id]?.registering != true &&
      !_cancellations.containsKey(item.id);

  static Future<UploadCancellationResult> cancelUpload(String transferId) {
    final previous = _cancellations[transferId];
    if (previous != null) return previous;
    final ledger = TransferLedgerStorage.find(transferId);
    if (_isCompleted(transferId)) {
      return Future.value(UploadCancellationResult.alreadyCompleted);
    }
    if (ledger?.registrationStarted == true ||
        _activeUploads[transferId]?.registering == true) {
      // An event-image request can commit even if its response is lost. Do not
      // label that photo cancelled or silently delete it from the event.
      return Future.value(UploadCancellationResult.finishing);
    }
    final queued = UploadQueueStorage.items.value.any(
      (item) => item.id == transferId,
    );
    if (ledger == null && !queued && !_isCancelled(transferId)) {
      return Future.value(UploadCancellationResult.notFound);
    }

    // Stop networking synchronously, before waiting for persistence. Every
    // queue snapshot and importer also observes this in-memory decision.
    _cancelRequested.add(transferId);
    _activeUploads[transferId]?.cancelToken.cancel('Cancelled by photographer');
    late final Future<UploadCancellationResult> operation;
    operation = _persistCancellation(transferId).whenComplete(() {
      if (identical(_cancellations[transferId], operation)) {
        _cancellations.remove(transferId);
      }
    });
    _cancellations[transferId] = operation;
    return operation;
  }

  static Future<UploadCancellationResult> _persistCancellation(
    String id,
  ) async {
    // The tombstone must reach disk before the pending row is removed. It
    // survives app restarts, camera resends and display-ledger pruning.
    await UploadQueueStorage.markCancelled(id);
    _cancelRequested.remove(id);
    await _setStatus(
      id,
      TransferLedgerStatus.cancelled,
      bytesPerSecond: 0,
      error: 'Upload cancelled',
    );
    await UploadQueueStorage.remove(id);
    _scheduleNextPass();
    return UploadCancellationResult.cancelled;
  }

  static void _throwIfCancelled(String id) {
    if (_isCancelled(id)) throw const _UploadCancelled();
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
    // Preserve successful receipts from earlier app versions before new shots
    // can age those rows out of the bounded transfer-history display.
    await UploadQueueStorage.markCompleted(
      TransferLedgerStorage.items.value
          .where((item) => item.isUploaded)
          .map((item) => item.id),
    );
    for (final pending in UploadQueueStorage.items.value) {
      if (UploadQueueStorage.isCompleted(pending.id)) continue;
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
        fileSize: await _fileSize(pending.localPath),
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
    int fileSize = 0,
  }) async {
    if (_isCancelled(transferId) && status != TransferLedgerStatus.cancelled) {
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final previous = TransferLedgerStorage.find(transferId);
    await TransferLedgerStorage.upsert(
      TransferLedgerItem(
        id: transferId,
        eventId: event.id,
        eventTitle: event.title,
        filename: filename,
        source: source,
        status: status,
        createdAt: previous?.createdAt ?? now,
        updatedAt: now,
        localPath: localPath,
        albumId: albumId,
        cameraId: cameraId,
        progress: progress,
        fileSize: fileSize > 0 ? fileSize : (previous?.fileSize ?? 0),
        bytesTotal: fileSize > 0 ? fileSize : (previous?.bytesTotal ?? 0),
        registrationStarted: previous?.registrationStarted ?? false,
        imageUrl: previous?.imageUrl,
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
    bool? registrationStarted,
    bool waitingForConnection = false,
    String? error,
    String? imageUrl,
    String? localPath,
    String? eventImageId,
  }) async {
    if (_isCancelled(transferId) && status != TransferLedgerStatus.cancelled) {
      return;
    }
    await TransferLedgerStorage.updateStatus(
      transferId,
      status,
      progress: progress,
      bytesSent: bytesSent,
      bytesTotal: bytesTotal,
      bytesPerSecond: bytesPerSecond,
      registrationStarted: registrationStarted,
      waitingForConnection: waitingForConnection,
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
      fileSize: await _fileSize(path),
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
      if (_isCancelled(transferId)) return false;
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
      fileSize: bytes.length,
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
      if (_isCancelled(transferId)) return false;
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

  /// Accepts a complete camera photo and immediately starts cloud delivery.
  /// Completion means the retry copy is durable, so the camera can acknowledge
  /// this object and send its next shot without waiting for the cloud response.
  /// Only the transfer ledger's isUploaded flag confirms cloud registration.
  static Future<PendingUploadItem> receiveCameraFile({
    required EventSummary event,
    required String path,
    required String filename,
    required bool isEnhanced,
    required String source,
    required String fingerprint,
    String? albumId,
    String? cameraId,
  }) => _receiveCamera(
    _queueFile(
      sourcePath: path,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      fingerprint: fingerprint,
      albumId: albumId,
      cameraId: cameraId,
    ),
  );

  /// The byte-based wireless equivalent of receiveCameraFile. Automatic camera
  /// uploads deliberately have no review delay or separate Upload button.
  static Future<PendingUploadItem> receiveCameraBytes({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required bool isEnhanced,
    required String source,
    required String fingerprint,
    String? albumId,
    String? cameraId,
  }) => _receiveCamera(
    _queueBytes(
      bytes: bytes,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      fingerprint: fingerprint,
      albumId: albumId,
      cameraId: cameraId,
    ),
  );

  static Future<PendingUploadItem> _receiveCamera(
    Future<PendingUploadItem> acceptance,
  ) async {
    final photo = await acceptance;
    _requestAutomaticUpload();
    return photo;
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
    Duration uploadDelay = Duration.zero,
  }) async {
    final queued = await _queueBytes(
      bytes: bytes,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      cameraId: cameraId,
      lastError: 'Waiting to upload',
      fingerprint: fingerprint,
      uploadDelay: uploadDelay,
    );
    if (tryUploadNow) {
      await processQueue();
      return _isCompleted(queued.id);
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
    Duration uploadDelay = Duration.zero,
  }) async {
    final queued = await _queueFile(
      sourcePath: path,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      cameraId: cameraId,
      lastError: 'Waiting to upload',
      fingerprint: fingerprint,
      uploadDelay: uploadDelay,
    );
    if (tryUploadNow) {
      await processQueue();
      return _isCompleted(queued.id);
    }
    return false;
  }

  static Future<void> retryNow(String transferId) async {
    if (_isCancelled(transferId)) return;
    PendingUploadItem? queued;
    for (final item in UploadQueueStorage.items.value) {
      if (item.id == transferId) {
        queued = item;
        break;
      }
    }
    if (queued == null) return;
    await UploadQueueStorage.update(
      queued.copyWith(nextRetryAt: 0, uploadAfter: 0, clearLastError: true),
    );
    await _setStatus(transferId, TransferLedgerStatus.queued, progress: 0);
    await processQueue();
  }

  static bool _stillQueued(String id) =>
      !_isCancelled(id) &&
      UploadQueueStorage.items.value.any((item) => item.id == id);

  static int _readyAt(PendingUploadItem item) {
    final retryAt = item.nextRetryAt ?? 0;
    final uploadAfter = item.uploadAfter ?? 0;
    return retryAt > uploadAfter ? retryAt : uploadAfter;
  }

  static void _scheduleNextPass() {
    _nextPassTimer?.cancel();
    _nextPassTimer = null;
    if (_schedulingStopped || isProcessing.value) return;
    int? readyAt;
    for (final item in UploadQueueStorage.items.value) {
      if (_isCancelled(item.id)) continue;
      final itemReadyAt = _readyAt(item);
      if (readyAt == null || itemReadyAt < readyAt) readyAt = itemReadyAt;
    }
    if (readyAt == null) return;
    final delay = readyAt - DateTime.now().millisecondsSinceEpoch;
    _nextPassTimer = Timer(
      Duration(milliseconds: delay > 0 ? delay : 0),
      _requestAutomaticUpload,
    );
  }

  /// Stop automatic scheduling, for example while signing out. An upload that
  /// has already started remains governed by its explicit cancellation action.
  static void stop() {
    _schedulingStopped = true;
    _timer?.cancel();
    _timer = null;
    _nextPassTimer?.cancel();
    _nextPassTimer = null;
  }

  static Future<void> processQueue() async {
    if (isProcessing.value || UploadQueueStorage.items.value.isEmpty) return;
    _nextPassTimer?.cancel();
    _nextPassTimer = null;
    isProcessing.value = true;
    var shouldSchedule = true;
    try {
      final snapshot = List<PendingUploadItem>.from(
        UploadQueueStorage.items.value,
      );
      for (final item in snapshot) {
        // A user can cancel a later photo while an earlier upload is awaiting
        // the network. A stale snapshot must never restart the cancelled one.
        if (!_stillQueued(item.id)) continue;

        final file = File(item.localPath);
        final existing = TransferLedgerStorage.find(item.id);
        if (_isCompleted(item.id)) {
          // A crash or a failed history write can leave a queue row after the
          // confirmed receipt. Finish local cleanup without another upload or
          // registration, even when its old retry deadline has not passed.
          await UploadQueueStorage.markCompleted([item.id]);
          if (existing != null && !existing.isUploaded) {
            await _setStatus(
              item.id,
              TransferLedgerStatus.processing,
              progress: 100,
              bytesPerSecond: 0,
            );
          }
          try {
            await file.delete();
          } catch (_) {}
          await UploadQueueStorage.remove(item.id);
          continue;
        }
        if (_readyAt(item) > DateTime.now().millisecondsSinceEpoch) continue;
        final canFinishRegistration =
            existing?.registrationStarted == true &&
            existing?.imageUrl?.isNotEmpty == true;
        if (!canFinishRegistration && !await file.exists()) {
          if (!_stillQueued(item.id)) continue;
          await _setStatus(
            item.id,
            TransferLedgerStatus.failed,
            error: 'Local queued file is missing',
          );
          await UploadQueueStorage.remove(item.id);
          continue;
        }
        if (!_stillQueued(item.id)) continue;

        final event = EventSummary(id: item.eventId, title: item.eventTitle);
        try {
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
          if (_isCancelled(item.id)) continue;
          if (UploadQueueStorage.isCompleted(item.id)) {
            // Cloud registration succeeded. A local status/cleanup failure
            // must not downgrade it to failed or start another blob upload.
            rethrow;
          }
          final now = DateTime.now().millisecondsSinceEpoch;
          final nextDelayMinutes = _retryDelayMinutes(
            item.attempts + 1,
          ).clamp(1, _maxRetryDelayMinutes);
          final errorText = _errorText(error);
          await _setStatus(
            item.id,
            TransferLedgerStatus.failed,
            bytesPerSecond: 0,
            error: errorText,
            waitingForConnection: _isConnectionFailure(error),
          );
          if (!_stillQueued(item.id)) continue;
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
    } catch (_) {
      // A local persistence failure should not create a zero-delay retry loop.
      // The regular service timer or an explicit retry can try again.
      shouldSchedule = false;
      rethrow;
    } finally {
      isProcessing.value = false;
      if (shouldSchedule) _scheduleNextPass();
    }
  }

  static void Function(int, int) _uploadProgressReporter(String transferId) {
    final active = _activeUploads[transferId];
    final startedAt = DateTime.now().millisecondsSinceEpoch;
    var lastReportedAt = startedAt;
    var lastProgress = 15;

    return (sent, total) {
      if (total <= 0 ||
          active == null ||
          !identical(_activeUploads[transferId], active) ||
          _isCancelled(transferId) ||
          active.registering) {
        return;
      }
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
        ).catchError((Object error) {
          // The next progress or terminal update can retry local status.
        }),
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
  }) => _runUpload(
    filename: filename,
    event: event,
    isEnhanced: isEnhanced,
    transferId: transferId,
    albumId: albumId,
    buildForm: () async => FormData.fromMap({
      'file': await MultipartFile.fromFile(path, filename: filename),
    }),
  );

  static Future<void> _uploadSingleBytes({
    required Uint8List bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String transferId,
    String? albumId,
  }) => _runUpload(
    filename: filename,
    event: event,
    isEnhanced: isEnhanced,
    transferId: transferId,
    albumId: albumId,
    buildForm: () async => FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    }),
  );

  static Future<void> _runUpload({
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String transferId,
    required Future<FormData> Function() buildForm,
    String? albumId,
  }) async {
    _throwIfCancelled(transferId);
    if (_isCompleted(transferId)) {
      await UploadQueueStorage.markCompleted([transferId]);
      return;
    }
    final active = _ActiveUpload();
    if (_activeUploads.containsKey(transferId)) {
      throw StateError('This photo is already uploading');
    }
    _activeUploads[transferId] = active;
    try {
      final previous = TransferLedgerStorage.find(transferId);
      var imageUrl = previous?.registrationStarted == true
          ? previous?.imageUrl ?? ''
          : '';
      if (imageUrl.isEmpty) {
        await _setStatus(
          transferId,
          TransferLedgerStatus.uploading,
          progress: 15,
        );
        _throwIfCancelled(transferId);
        final formData = await buildForm();
        _throwIfCancelled(transferId);
        final response = await DioHelper.post(
          '/image/upload',
          data: formData,
          cancelToken: active.cancelToken,
          onSendProgress: _uploadProgressReporter(transferId),
        );
        _throwIfCancelled(transferId);
        imageUrl = response.data['url']?.toString() ?? '';
        if (imageUrl.isEmpty) throw Exception('Image upload returned no URL');
      }

      _throwIfCancelled(transferId);
      // No cancellation is accepted after this point. Persist that boundary
      // before sending the request because a lost response does not imply the
      // server rolled back its event image. Retrying uses the same URL and the
      // idempotent clientTransferId instead of uploading another blob.
      active.registering = true;
      await _setStatus(
        transferId,
        TransferLedgerStatus.processing,
        progress: 75,
        bytesPerSecond: 0,
        imageUrl: imageUrl,
        registrationStarted: true,
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
      if (createdData is! Map ||
          createdData['_id'] is! String ||
          (createdData['_id'] as String).trim().isEmpty) {
        // A 2xx response without a real event-photo ID does not confirm that
        // the photo was registered. Keep its URL, idempotency key and retry
        // copy; otherwise a malformed response could delete the only buffer.
        throw StateError(
          'Cloud upload confirmation is incomplete. AirPix will retry.',
        );
      }
      final eventImageId = (createdData['_id'] as String).trim();
      final isPublished = createdData['isPublished'] == true;
      // The display history is bounded, but this acceptance receipt is not
      // tied to its retention. If this write fails, keep the URL/registration
      // boundary and retry copy so a retry uses the same cloud object.
      await UploadQueueStorage.markCompleted([transferId]);
      await _setStatus(
        transferId,
        isPublished
            ? TransferLedgerStatus.published
            : TransferLedgerStatus.processing,
        progress: 100,
        imageUrl: imageUrl,
        eventImageId: eventImageId,
      );
    } finally {
      if (identical(_activeUploads[transferId], active)) {
        _activeUploads.remove(transferId);
      }
    }
  }

  static bool _hasCompletedUpload(TransferLedgerItem? item) =>
      item?.isUploaded == true;

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
    Duration uploadDelay = Duration.zero,
  }) => _queueImport(
    sourcePath: sourcePath,
    filename: filename,
    event: event,
    isEnhanced: isEnhanced,
    source: source,
    albumId: albumId,
    cameraId: cameraId,
    lastError: lastError,
    fingerprint: fingerprint,
    transferId: transferId,
    uploadDelay: uploadDelay,
  );

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
    Duration uploadDelay = Duration.zero,
  }) => _queueImport(
    bytes: bytes,
    filename: filename,
    event: event,
    isEnhanced: isEnhanced,
    source: source,
    albumId: albumId,
    cameraId: cameraId,
    lastError: lastError,
    fingerprint: fingerprint,
    transferId: transferId,
    uploadDelay: uploadDelay,
  );

  static Future<PendingUploadItem> _queueImport({
    String? sourcePath,
    Uint8List? bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? cameraId,
    String? lastError,
    String? fingerprint,
    String? transferId,
    required Duration uploadDelay,
  }) {
    Future<PendingUploadItem> save() => _queueImportOnce(
      sourcePath: sourcePath,
      bytes: bytes,
      filename: filename,
      event: event,
      isEnhanced: isEnhanced,
      source: source,
      albumId: albumId,
      cameraId: cameraId,
      lastError: lastError,
      fingerprint: fingerprint,
      transferId: transferId,
      uploadDelay: uploadDelay,
    );

    if (fingerprint == null) return save();
    final key = jsonEncode([event.id, source, fingerprint]);
    final existing = _fileImportsInFlight[key];
    if (existing != null) return existing;

    // USB reconnects and wireless resends can overlap the same photo. Share
    // the durable save so no receiver overwrites an actively uploading file.
    late final Future<PendingUploadItem> operation;
    operation = save().whenComplete(() {
      if (identical(_fileImportsInFlight[key], operation)) {
        _fileImportsInFlight.remove(key);
      }
    });
    _fileImportsInFlight[key] = operation;
    return operation;
  }

  static Future<PendingUploadItem> _queueImportOnce({
    String? sourcePath,
    Uint8List? bytes,
    required String filename,
    required EventSummary event,
    required bool isEnhanced,
    required String source,
    String? albumId,
    String? cameraId,
    String? lastError,
    String? fingerprint,
    String? transferId,
    required Duration uploadDelay,
  }) async {
    if (fingerprint != null) {
      final existing = UploadQueueStorage.findByFingerprint(
        fingerprint,
        eventId: event.id,
        source: source,
      );
      if (existing != null) {
        if (_isCancelled(existing.id) || _isCompleted(existing.id)) {
          if (_isCompleted(existing.id)) {
            await UploadQueueStorage.markCompleted([existing.id]);
          }
          return existing;
        }
        final queuedFile = File(existing.localPath);
        if (!await queuedFile.exists() || await queuedFile.length() == 0) {
          throw Exception(
            'Existing queued photo is missing or empty. Please retry the import.',
          );
        }
        return existing;
      }
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
    final previous = TransferLedgerStorage.find(itemId);
    PendingUploadItem acceptedWithoutRequeue(String localPath) =>
        PendingUploadItem(
          id: itemId,
          eventId: event.id,
          eventTitle: event.title,
          localPath: previous?.localPath ?? localPath,
          filename: filename,
          source: source,
          isEnhanced: isEnhanced,
          createdAt:
              previous?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
          fingerprint: fingerprint,
          albumId: albumId,
          cameraId: cameraId,
        );
    if (_isCancelled(itemId) || _isCompleted(itemId)) {
      if (_isCompleted(itemId)) {
        await UploadQueueStorage.markCompleted([itemId]);
      }
      // A confirmed receipt or an intentional cancellation already accepts
      // this object. Acknowledge the resend without sending it to cloud again.
      return acceptedWithoutRequeue(sourcePath ?? '');
    }

    final target = await _queueTargetPath(itemId, filename);
    if (_isCancelled(itemId)) return acceptedWithoutRequeue(target);
    int fileSize;
    if (sourcePath != null) {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        throw Exception('Local import file missing before queue');
      }
      fileSize = await sourceFile.length();
      if (fileSize == 0) {
        throw Exception('Local import file is empty before queue');
      }
      if (sourceFile.path != target) await sourceFile.copy(target);
    } else {
      if (bytes == null || bytes.isEmpty) {
        throw Exception('Local import file is empty before queue');
      }
      fileSize = bytes.length;
      await File(target).writeAsBytes(bytes, flush: true);
    }
    if (_isCancelled(itemId)) return acceptedWithoutRequeue(target);

    final now = DateTime.now().millisecondsSinceEpoch;
    final item = PendingUploadItem(
      id: itemId,
      eventId: event.id,
      eventTitle: event.title,
      localPath: target,
      filename: filename,
      source: source,
      isEnhanced: isEnhanced,
      createdAt: now,
      fingerprint: fingerprint,
      albumId: albumId,
      cameraId: cameraId,
      lastError: lastError,
      uploadAfter: uploadDelay.inMilliseconds > 0
          ? now + uploadDelay.inMilliseconds
          : null,
    );
    // Publish metadata before the pending row. A background upload must never
    // be overwritten by a late "queued" status from its original import.
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
      progress: previous?.registrationStarted == true ? 75 : 0,
      fileSize: fileSize,
    );
    if (!_isCancelled(itemId)) await UploadQueueStorage.add(item);
    return item;
  }

  static Future<int> _fileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
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

  static bool _isConnectionFailure(Object error) {
    if (error is SocketException) return true;
    if (error is! DioException || error.response != null) return false;
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => true,
      _ => error.error is SocketException,
    };
  }

  static int _retryDelayMinutes(int attempts) {
    if (attempts <= 1) return 1;
    if (attempts == 2) return 2;
    if (attempts == 3) return 5;
    if (attempts == 4) return 10;
    return 30;
  }
}
