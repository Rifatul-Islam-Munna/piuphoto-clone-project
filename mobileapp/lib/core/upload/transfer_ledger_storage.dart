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
  final String? error;
  final String? imageUrl;

  bool get isUploaded => const {
    TransferLedgerStatus.processing,
    TransferLedgerStatus.published,
    TransferLedgerStatus.delivered,
  }.contains(status);

  bool get isPending => !isUploaded && status != TransferLedgerStatus.failed;

  TransferLedgerItem copyWith({
    TransferLedgerStatus? status,
    int? progress,
    int? bytesSent,
    int? bytesTotal,
    double? bytesPerSecond,
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
  static SharedPreferences get _prefs => getIt<SharedPreferences>();

  static Future<void> init() async {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return;
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

  static Future<void> upsert(TransferLedgerItem item) async {
    final next = List<TransferLedgerItem>.from(items.value);
    final index = next.indexWhere((current) => current.id == item.id);
    if (index == -1) {
      next.insert(0, item);
    } else {
      next[index] = item;
    }
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (next.length > _maxItems) {
      next.removeRange(_maxItems, next.length);
    }
    await _save(next);
  }

  static Future<void> updateStatus(
    String id,
    TransferLedgerStatus status, {
    int? progress,
    int? bytesSent,
    int? bytesTotal,
    double? bytesPerSecond,
    String? error,
    String? imageUrl,
    String? localPath,
  }) async {
    final existing = find(id);
    if (existing == null) return;
    await upsert(
      existing.copyWith(
        status: status,
        progress: progress,
        bytesSent: bytesSent,
        bytesTotal: bytesTotal,
        bytesPerSecond: bytesPerSecond,
        error: error,
        imageUrl: imageUrl,
        localPath: localPath,
        clearError: error == null,
      ),
    );
  }

  static Future<void> clearEvent(String eventId) async {
    await _save(items.value.where((item) => item.eventId != eventId).toList());
  }

  static Future<void> _save(List<TransferLedgerItem> next) async {
    items.value = List.unmodifiable(next);
    await _prefs.setString(
      _key,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }
}
