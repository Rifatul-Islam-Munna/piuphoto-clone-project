import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
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
    this.previewUrl,
    this.eventImageId,
    this.enhancementStatus,
    this.isEnhanced = false,
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
  final String? previewUrl;
  final String? eventImageId;
  final String? enhancementStatus;
  final bool isEnhanced;
  bool get aiPending =>
      enhancementStatus == 'pending' || enhancementStatus == 'processing';
  String? get aiLabel => isEnhanced
      ? 'AI enhanced'
      : switch (enhancementStatus) {
          'pending' || 'processing' => 'AI processing',
          'completed' => 'AI copy ready',
          'failed' => 'AI failed',
          'skipped' => 'AI skipped',
          _ => null,
        };
  String? get displayUrl =>
      previewUrl?.isNotEmpty == true ? previewUrl : imageUrl;

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
    String? previewUrl,
    String? eventImageId,
    String? enhancementStatus,
    bool? isEnhanced,
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
      previewUrl: previewUrl ?? this.previewUrl,
      eventImageId: eventImageId ?? this.eventImageId,
      enhancementStatus: enhancementStatus ?? this.enhancementStatus,
      isEnhanced: isEnhanced ?? this.isEnhanced,
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
    'previewUrl': previewUrl,
    'eventImageId': eventImageId,
    'enhancementStatus': enhancementStatus,
    'isEnhanced': isEnhanced,
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
      previewUrl: json['previewUrl']?.toString(),
      eventImageId: json['eventImageId']?.toString(),
      enhancementStatus: json['enhancementStatus']?.toString(),
      isEnhanced: json['isEnhanced'] == true,
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
        previewUrl: item.previewUrl ?? existing.previewUrl,
        eventImageId: item.eventImageId ?? existing.eventImageId,
        enhancementStatus: item.enhancementStatus ?? existing.enhancementStatus,
        isEnhanced: item.isEnhanced || existing.isEnhanced,
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

  /// Save a confirmed manual upload batch with a single persistence write.
  static Future<void> upsertAll(Iterable<TransferLedgerItem> updates) {
    return _mutate((current) {
      var next = current;
      for (final item in updates) {
        next = _replace(next, item);
      }
      return next;
    });
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
    String? previewUrl,
    String? eventImageId,
    String? enhancementStatus,
    bool? isEnhanced,
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
          previewUrl: previewUrl,
          eventImageId: eventImageId,
          enhancementStatus: enhancementStatus,
          isEnhanced: isEnhanced,
          localPath: localPath,
          clearError: error == null,
        ),
      );
    });
  }

  static final _aiRequests = <String>{};

  /// Poll only known, in-flight enhancements belonging to this event.
  /// A status change never changes upload completion, publication or ordering.
  static Future<void> refreshAiStatuses(String eventId) async {
    if (!_aiRequests.add(eventId)) return;
    try {
      final pending = items.value
          .where(
            (item) =>
                item.eventId == eventId &&
                item.isUploaded &&
                item.aiPending &&
                item.eventImageId?.isNotEmpty == true,
          )
          .toList();
      final ids = pending
          .map((item) => item.eventImageId!)
          .toSet()
          .take(100)
          .toList();
      if (ids.isEmpty) return;
      final response = await DioHelper.get(
        '/eventImage/enhancement-status',
        queryParameters: {'eventId': eventId, 'ids': ids.join(',')},
      );
      final data = response.data is Map ? response.data['data'] : null;
      if (data is! List) return;
      final statuses = <String, Map>{
        for (final row in data.whereType<Map>())
          if (row['id'] != null) row['id'].toString(): row,
      };
      // Missing rows may have been deleted or access revoked. Stop polling
      // them without claiming that enhancement succeeded.
      final queried = ids.toSet();
      await _mutate((current) {
        var changed = false;
        final next = current.map((item) {
          final id = item.eventImageId;
          if (item.eventId != eventId ||
              !item.aiPending ||
              !queried.contains(id))
            return item;
          final row = statuses[id];
          final status = row?['enhancementStatus']?.toString() ?? 'none';
          final enhanced = row?['isEnhanced'] == true || item.isEnhanced;
          if (status == item.enhancementStatus && enhanced == item.isEnhanced)
            return item;
          changed = true;
          return item.copyWith(
            enhancementStatus: status,
            isEnhanced: enhanced,
            updatedAt: item.updatedAt,
          );
        }).toList();
        return changed ? next : current;
      });
    } catch (_) {
      // Upload completion is independent from status refresh/network failures.
    } finally {
      _aiRequests.remove(eventId);
    }
  }

  static Future<void> clearEvent(String eventId) {
    return _mutate(
      (current) => current.where((item) => item.eventId != eventId).toList(),
    );
  }

  static Future<void> _mutate(
    List<TransferLedgerItem> Function(List<TransferLedgerItem>) mutate,
  ) {
    final operation = _writeChain.then((_) async {
      final current = items.value;
      final next = mutate(current);
      if (!identical(current, next)) await _save(next);
    });
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
