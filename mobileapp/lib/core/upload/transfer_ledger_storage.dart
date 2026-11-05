import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TransferLedgerStatus {
  detected,
  stored,
  queued,
  uploading,
  processing,
  published,
  delivered,
  failed,
  cancelled,
}

class TransferLedgerItem {
  const TransferLedgerItem({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.filename,
    required this.source,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.localPath,
    this.albumId,
    this.cameraId,
    this.progress = 0,
    this.bytesSent = 0,
    this.bytesTotal = 0,
    this.bytesPerSecond = 0,
    this.fileSize = 0,
    this.registrationStarted = false,
    this.waitingForConnection = false,
    this.error,
    this.imageUrl,
  });
  final String id;
  final String eventId;
  final String eventTitle;
  final String filename;
  final String source;
  final TransferLedgerStatus status;
  final int createdAt;
  final int updatedAt;
  final String? localPath;
  final String? albumId;
  final String? cameraId;
  final int progress;
  final int bytesSent;
  final int bytesTotal;
  final double bytesPerSecond;

  /// Original file bytes, without multipart request overhead.
  final int fileSize;

  /// The event-image request may already have committed on the server.
  final bool registrationStarted;

  /// Cloud networking failed before a usable server response arrived. This
  /// does not assert that Wi-Fi is absent; the connected camera may have its
  /// own network while the cloud service is temporarily unreachable.
  final bool waitingForConnection;
  final String? error;
  final String? imageUrl;

  bool get isUploaded =>
      status == TransferLedgerStatus.published ||
      status == TransferLedgerStatus.delivered ||
      (status == TransferLedgerStatus.processing && progress >= 100);

  bool get isPending =>
      !isUploaded &&
      status != TransferLedgerStatus.failed &&
      status != TransferLedgerStatus.cancelled;

  TransferLedgerItem copyWith({
    TransferLedgerStatus? status,
    int? progress,
    int? bytesSent,
    int? bytesTotal,
    double? bytesPerSecond,
    int? fileSize,
    bool? registrationStarted,
    bool? waitingForConnection,
    int? updatedAt,
    String? localPath,
    String? error,
    String? imageUrl,
    bool clearError = false,
  }) {
    return TransferLedgerItem(
      id: id,
      eventId: eventId,
      eventTitle: eventTitle,
      filename: filename,
      source: source,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      localPath: localPath ?? this.localPath,
      albumId: albumId,
      cameraId: cameraId,
      progress: progress ?? this.progress,
      bytesSent: bytesSent ?? this.bytesSent,
      bytesTotal: bytesTotal ?? this.bytesTotal,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      fileSize: fileSize ?? this.fileSize,
      registrationStarted: registrationStarted ?? this.registrationStarted,
      waitingForConnection: waitingForConnection ?? this.waitingForConnection,
      error: clearError ? null : (error ?? this.error),
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'eventId': eventId,
    'eventTitle': eventTitle,
    'filename': filename,
    'source': source,
    'status': status.name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'localPath': localPath,
    'albumId': albumId,
    'cameraId': cameraId,
    'progress': progress,
    'bytesSent': bytesSent,
    'bytesTotal': bytesTotal,
    'bytesPerSecond': bytesPerSecond,
    'fileSize': fileSize,
    'registrationStarted': registrationStarted,
    'waitingForConnection': waitingForConnection,
    'error': error,
    'imageUrl': imageUrl,
  };
  factory TransferLedgerItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status']?.toString() ?? 'queued';
    final status = TransferLedgerStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => TransferLedgerStatus.queued,
    );
    return TransferLedgerItem(
      id: json['id']?.toString() ?? '',
      eventId: json['eventId']?.toString() ?? '',
      eventTitle: json['eventTitle']?.toString() ?? 'Event',
      filename: json['filename']?.toString() ?? 'image.jpg',
      source: json['source']?.toString() ?? 'camera',
      status: status,
      createdAt: int.tryParse(json['createdAt']?.toString() ?? '') ?? 0,
      updatedAt: int.tryParse(json['updatedAt']?.toString() ?? '') ?? 0,
      localPath: json['localPath']?.toString(),
      albumId: json['albumId']?.toString(),
      cameraId: json['cameraId']?.toString(),
      progress: int.tryParse(json['progress']?.toString() ?? '') ?? 0,
      bytesSent: int.tryParse(json['bytesSent']?.toString() ?? '') ?? 0,
      bytesTotal: int.tryParse(json['bytesTotal']?.toString() ?? '') ?? 0,
      bytesPerSecond:
          double.tryParse(json['bytesPerSecond']?.toString() ?? '') ?? 0,
      fileSize: int.tryParse(json['fileSize']?.toString() ?? '') ?? 0,
      registrationStarted:
          json['registrationStarted'] == true ||
          // Older versions stored this stage as processing at 75 percent.
          ((int.tryParse(json['progress']?.toString() ?? '') ?? 0) >= 75 &&
              json['imageUrl']?.toString().isNotEmpty == true),
      waitingForConnection: json['waitingForConnection'] == true,
      error: json['error']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
    );
  }
}

class TransferLedgerStorage {
  TransferLedgerStorage._();

  static const _key = 'photo_transfer_ledger_v1';
  static const _maxItems = 2000;
  static final ValueNotifier<List<TransferLedgerItem>> items =
      ValueNotifier<List<TransferLedgerItem>>(const []);
  static Future<void> _writeChain = Future<void>.value();
  static SharedPreferences get _prefs => getIt<SharedPreferences>();

  static Future<void> init() async {
    await _writeChain;
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      items.value = const [];
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      items.value = decoded
          .whereType<Map>()
          .map(
            (item) =>
                TransferLedgerItem.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((item) => item.id.isNotEmpty && item.eventId.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      items.value = const [];
    }
  }

  static TransferLedgerItem? find(String id) {
    for (final item in items.value) {
      if (item.id == id) return item;
    }
    return null;
  }

  static List<TransferLedgerItem> _replace(
    List<TransferLedgerItem> current,
    TransferLedgerItem item,
  ) {
    final next = List<TransferLedgerItem>.from(current);
    final index = next.indexWhere((current) => current.id == item.id);
    if (index == -1) {
      next.insert(0, item);
    } else {
      if (_wouldRegress(next[index], item.status, item.progress)) return next;
      final existing = next[index];
      next[index] = item.copyWith(
        fileSize: item.fileSize > 0 ? item.fileSize : existing.fileSize,
        registrationStarted:
            item.registrationStarted || existing.registrationStarted,
        localPath: item.localPath ?? existing.localPath,
        imageUrl: item.imageUrl ?? existing.imageUrl,
      );
    }
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (next.length > _maxItems) {
      var historyCount = 0;
      next.removeWhere((entry) {
        // Pending and failed transfers still need their local preview and
        // registration boundary. A long shoot must not turn an uncertain
        // server commit into a cancellable new upload by pruning that state.
        if (!entry.isUploaded &&
            entry.status != TransferLedgerStatus.cancelled) {
          return false;
        }
        historyCount++;
        return historyCount > _maxItems;
      });
    }
    return next;
  }

  static bool _wouldRegress(
    TransferLedgerItem existing,
    TransferLedgerStatus status,
    int progress,
  ) {
    if (existing.status == TransferLedgerStatus.cancelled) {
      return status != TransferLedgerStatus.cancelled;
    }
    return existing.isUploaded &&
        status != TransferLedgerStatus.published &&
        status != TransferLedgerStatus.delivered &&
        !(status == TransferLedgerStatus.processing && progress >= 100);
  }

  static Future<void> upsert(TransferLedgerItem item) {
    return _mutate((current) => _replace(current, item));
  }

  static Future<void> updateStatus(
    String id,
    TransferLedgerStatus status, {
    int? progress,
    int? bytesSent,
    int? bytesTotal,
    double? bytesPerSecond,
    int? fileSize,
    bool? registrationStarted,
    bool waitingForConnection = false,
    String? error,
    String? imageUrl,
    String? localPath,
  }) {
    return _mutate((current) {
      final index = current.indexWhere((item) => item.id == id);
      if (index == -1) return current;
      final existing = current[index];
      return _replace(
        current,
        existing.copyWith(
          status: status,
          progress: progress,
          bytesSent: bytesSent,
          bytesTotal: bytesTotal,
          bytesPerSecond: bytesPerSecond,
          fileSize: fileSize,
          registrationStarted: registrationStarted,
          waitingForConnection: waitingForConnection,
          error: error,
          imageUrl: imageUrl,
          localPath: localPath,
          clearError: error == null,
        ),
      );
    });
  }

  static Future<void> clearEvent(String eventId) {
    return _mutate(
      (current) => current.where((item) => item.eventId != eventId).toList(),
    );
  }

  static Future<void> _mutate(
    List<TransferLedgerItem> Function(List<TransferLedgerItem>) mutate,
  ) {
    final operation = _writeChain.then((_) => _save(mutate(items.value)));
    _writeChain = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return operation;
  }

  static Future<void> _save(List<TransferLedgerItem> next) async {
    final saved = await _prefs.setString(
      _key,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
    if (!saved) throw StateError('Unable to save the photo transfer status');
    items.value = List.unmodifiable(next);
  }
}
