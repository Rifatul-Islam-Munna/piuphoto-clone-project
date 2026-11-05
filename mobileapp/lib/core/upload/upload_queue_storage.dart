import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingUploadItem {
  const PendingUploadItem({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.localPath,
    required this.filename,
    required this.source,
    required this.isEnhanced,
    required this.createdAt,
    this.fingerprint,
    this.albumId,
    this.cameraId,
    this.attempts = 0,
    this.lastError,
    this.lastAttemptAt,
    this.nextRetryAt,
    this.uploadAfter,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String localPath;
  final String filename;
  final String source;
  final bool isEnhanced;
  final int createdAt;
  final String? fingerprint;
  final String? albumId;
  final String? cameraId;
  final int attempts;
  final String? lastError;
  final int? lastAttemptAt;
  final int? nextRetryAt;

  /// Initial review window for a newly received camera photo.
  final int? uploadAfter;

  PendingUploadItem copyWith({
    String? localPath,
    int? attempts,
    String? lastError,
    int? lastAttemptAt,
    int? nextRetryAt,
    int? uploadAfter,
    bool clearLastError = false,
  }) {
    return PendingUploadItem(
      id: id,
      eventId: eventId,
      eventTitle: eventTitle,
      localPath: localPath ?? this.localPath,
      filename: filename,
      source: source,
      isEnhanced: isEnhanced,
      createdAt: createdAt,
      fingerprint: fingerprint,
      albumId: albumId,
      cameraId: cameraId,
      attempts: attempts ?? this.attempts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      uploadAfter: uploadAfter ?? this.uploadAfter,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'eventId': eventId,
      'eventTitle': eventTitle,
      'localPath': localPath,
      'filename': filename,
      'source': source,
      'isEnhanced': isEnhanced,
      'createdAt': createdAt,
      'fingerprint': fingerprint,
      'albumId': albumId,
      'cameraId': cameraId,
      'attempts': attempts,
      'lastError': lastError,
      'lastAttemptAt': lastAttemptAt,
      'nextRetryAt': nextRetryAt,
      'uploadAfter': uploadAfter,
    };
  }

  factory PendingUploadItem.fromJson(Map<String, dynamic> json) {
    return PendingUploadItem(
      id: json['id']?.toString() ?? '',
      eventId: json['eventId']?.toString() ?? '',
      eventTitle: json['eventTitle']?.toString() ?? 'Event',
      localPath: json['localPath']?.toString() ?? '',
      filename: json['filename']?.toString() ?? 'image.jpg',
      source: json['source']?.toString() ?? 'import',
      isEnhanced: json['isEnhanced'] == true,
      createdAt: int.tryParse(json['createdAt']?.toString() ?? '') ?? 0,
      fingerprint: json['fingerprint']?.toString(),
      albumId: json['albumId']?.toString(),
      cameraId: json['cameraId']?.toString(),
      attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
      lastError: json['lastError']?.toString(),
      lastAttemptAt: int.tryParse(json['lastAttemptAt']?.toString() ?? ''),
      nextRetryAt: int.tryParse(json['nextRetryAt']?.toString() ?? ''),
      uploadAfter: int.tryParse(json['uploadAfter']?.toString() ?? ''),
    );
  }
}

class UploadQueueStorage {
  UploadQueueStorage._();

  static const _key = 'pending_upload_queue';
  // Keep the user's decision independently of the bounded display ledger.
  // A camera can resend an object after reconnecting or retrying FTP.
  static const _cancelledKey = 'cancelled_upload_ids_v1';
  // Successful camera receipts must also outlive the bounded display ledger.
  // Store only transfer IDs, whose event/source/fingerprint scope is already
  // fixed by the receiver, so re-reading a large card cannot upload it again.
  static const _completedKey = 'completed_upload_ids_v1';
  static Set<String> _cancelledIds = {};
  static Set<String> _completedIds = {};
  static final ValueNotifier<List<PendingUploadItem>> items =
      ValueNotifier<List<PendingUploadItem>>(const []);
  static Future<void> _writeChain = Future<void>.value();

  static SharedPreferences get _prefs => getIt<SharedPreferences>();

  static Future<void> init() async {
    await _writeChain;
    final rawCancelled = _prefs.getString(_cancelledKey);
    _cancelledIds = rawCancelled == null
        ? {}
        : (jsonDecode(rawCancelled) as List).whereType<String>().toSet();
    final rawCompleted = _prefs.getString(_completedKey);
    _completedIds = rawCompleted == null
        ? {}
        : (jsonDecode(rawCompleted) as List).whereType<String>().toSet();
    items.value = _read();
  }

  static bool isCancelled(String id) => _cancelledIds.contains(id);

  static bool isCompleted(String id) => _completedIds.contains(id);

  /// Call only after a valid cloud registration response, or to migrate an
  /// already-confirmed ledger entry. Persist before deleting the retry copy.
  static Future<void> markCompleted(Iterable<String> ids) {
    final requested = ids.where((id) => id.isNotEmpty).toSet();
    final operation = _writeChain.then((_) async {
      final additions = requested.difference(_completedIds);
      if (additions.isEmpty) return;
      final next = {..._completedIds, ...additions};
      final saved = await _prefs.setString(
        _completedKey,
        jsonEncode(next.toList()),
      );
      if (!saved) throw StateError('Unable to save the cloud upload receipt');
      _completedIds = next;
    });
    _keepWriteChainAlive(operation);
    return operation;
  }

  static Future<void> markCancelled(String id) {
    final operation = _writeChain.then((_) async {
      if (_cancelledIds.contains(id)) return;
      final next = {..._cancelledIds, id};
      final saved = await _prefs.setString(
        _cancelledKey,
        jsonEncode(next.toList()),
      );
      if (!saved) throw StateError('Unable to save the upload cancellation');
      _cancelledIds = next;
    });
    _keepWriteChainAlive(operation);
    return operation;
  }

  static List<PendingUploadItem> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map(
          (item) => PendingUploadItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .where(
          (item) =>
              item.id.isNotEmpty &&
              item.eventId.isNotEmpty &&
              item.localPath.isNotEmpty &&
              !isCancelled(item.id),
        )
        .toList(growable: false);
  }

  static Future<void> add(PendingUploadItem item) {
    return _mutate((current) {
      if (isCancelled(item.id) || isCompleted(item.id)) return current;
      return [...current.where((queued) => queued.id != item.id), item];
    });
  }

  static PendingUploadItem? findByFingerprint(
    String fingerprint, {
    String? eventId,
    String? source,
  }) {
    for (final item in items.value) {
      if (item.fingerprint == fingerprint &&
          (eventId == null || item.eventId == eventId) &&
          (source == null || item.source == source)) {
        return item;
      }
    }
    return null;
  }

  static Future<void> update(PendingUploadItem item) {
    return _mutate(
      (current) => current
          .where((queued) => !isCancelled(queued.id))
          .map((queued) => queued.id == item.id ? item : queued)
          .toList(growable: false),
    );
  }

  static Future<void> remove(String id) {
    return _mutate(
      (current) =>
          current.where((item) => item.id != id).toList(growable: false),
    );
  }

  static Future<void> _mutate(
    List<PendingUploadItem> Function(List<PendingUploadItem>) mutate,
  ) {
    // Compute each change after the previous write settles, so a new shot and
    // an upload completion cannot persist competing snapshots of the queue.
    final operation = _writeChain.then((_) => _save(mutate(items.value)));
    _keepWriteChainAlive(operation);
    return operation;
  }

  static void _keepWriteChainAlive(Future<void> operation) {
    // Keep the caller's failure while allowing subsequent writes to proceed.
    _writeChain = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
  }

  static Future<void> _save(List<PendingUploadItem> next) async {
    final saved = await _prefs.setString(
      _key,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw StateError('Unable to save the upload queue');
    }
    // Native capture may be acknowledged once this future succeeds. Publish
    // only committed rows, never a row whose persistence is still pending.
    items.value = List<PendingUploadItem>.unmodifiable(next);
  }
}
