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
    this.attempts = 0,
    this.lastError,
    this.lastAttemptAt,
    this.nextRetryAt,
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
  final int attempts;
  final String? lastError;
  final int? lastAttemptAt;
  final int? nextRetryAt;

  PendingUploadItem copyWith({
    String? localPath,
    int? attempts,
    String? lastError,
    int? lastAttemptAt,
    int? nextRetryAt,
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
      attempts: attempts ?? this.attempts,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
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
      'attempts': attempts,
      'lastError': lastError,
      'lastAttemptAt': lastAttemptAt,
      'nextRetryAt': nextRetryAt,
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
      attempts: int.tryParse(json['attempts']?.toString() ?? '') ?? 0,
      lastError: json['lastError']?.toString(),
      lastAttemptAt: int.tryParse(json['lastAttemptAt']?.toString() ?? ''),
      nextRetryAt: int.tryParse(json['nextRetryAt']?.toString() ?? ''),
    );
  }
}

class UploadQueueStorage {
  UploadQueueStorage._();

  static const _key = 'pending_upload_queue';
  static final ValueNotifier<List<PendingUploadItem>> items =
      ValueNotifier<List<PendingUploadItem>>(const []);

  static SharedPreferences get _prefs => getIt<SharedPreferences>();

  static Future<void> init() async {
    items.value = _read();
  }

  static List<PendingUploadItem> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];

    return decoded
        .whereType<Map>()
        .map((item) => PendingUploadItem.fromJson(Map<String, dynamic>.from(item)))
        .where((item) =>
            item.id.isNotEmpty &&
            item.eventId.isNotEmpty &&
            item.localPath.isNotEmpty)
        .toList(growable: false);
  }

  static Future<void> add(PendingUploadItem item) async {
    final next = List<PendingUploadItem>.from(items.value)..add(item);
    await _save(next);
  }

  static PendingUploadItem? findByFingerprint(String fingerprint) {
    for (final item in items.value) {
      if (item.fingerprint == fingerprint) return item;
    }
    return null;
  }

  static Future<void> update(PendingUploadItem item) async {
    final next = items.value
        .map((current) => current.id == item.id ? item : current)
        .toList(growable: false);
    await _save(next);
  }

  static Future<void> remove(String id) async {
    final next = items.value.where((item) => item.id != id).toList(growable: false);
    await _save(next);
  }

  static Future<void> _save(List<PendingUploadItem> next) async {
    items.value = next;
    await _prefs.setString(
      _key,
      jsonEncode(next.map((item) => item.toJson()).toList()),
    );
  }
}
