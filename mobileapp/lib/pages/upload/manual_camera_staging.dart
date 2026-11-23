import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Locally retained camera photos waiting for photographer approval.
///
/// This is deliberately separate from UploadQueueService: the upload queue
/// automatically sends every queued file, so adding unapproved photos there
/// would upload them without permission. Only approved photos reach that queue.
@immutable
class ManualCameraPhoto {
  const ManualCameraPhoto({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.filename,
    required this.path,
    required this.fingerprint,
    required this.source,
    required this.createdAt,
    required this.isEnhanced,
    required this.status,
    this.albumId,
    this.cameraId,
  });

  final String id;
  final String eventId;
  final String eventTitle;
  final String filename;
  final String path;
  final String fingerprint;
  final String source;
  final int createdAt;
  final bool isEnhanced;
  final String status;
  final String? albumId;
  final String? cameraId;

  bool get isPending => status == 'pending';

  ManualCameraPhoto withStatus(String next) => ManualCameraPhoto(
    id: id,
    eventId: eventId,
    eventTitle: eventTitle,
    filename: filename,
    path: path,
    fingerprint: fingerprint,
    source: source,
    createdAt: createdAt,
    isEnhanced: isEnhanced,
    status: next,
    albumId: albumId,
    cameraId: cameraId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'eventId': eventId,
    'eventTitle': eventTitle,
    'filename': filename,
    'path': path,
    'fingerprint': fingerprint,
    'source': source,
    'createdAt': createdAt,
    'isEnhanced': isEnhanced,
    'status': status,
    if (albumId != null) 'albumId': albumId,
    if (cameraId != null) 'cameraId': cameraId,
  };

  factory ManualCameraPhoto.fromJson(Map<String, dynamic> json) =>
      ManualCameraPhoto(
        id: json['id']?.toString() ?? '',
        eventId: json['eventId']?.toString() ?? '',
        eventTitle: json['eventTitle']?.toString() ?? '',
        filename: json['filename']?.toString() ?? '',
        path: json['path']?.toString() ?? '',
        fingerprint: json['fingerprint']?.toString() ?? '',
        source: json['source']?.toString() ?? 'camera',
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        isEnhanced: json['isEnhanced'] == true,
        status: json['status']?.toString() ?? 'pending',
        albumId: json['albumId']?.toString(),
        cameraId: json['cameraId']?.toString(),
      );
}

class ManualCameraStaging {
  ManualCameraStaging._();

  static const _key = 'manual_camera_review_v1';
  static final ValueNotifier<List<ManualCameraPhoto>> items =
      ValueNotifier<List<ManualCameraPhoto>>(const []);

  static Future<void>? _loading;
  static Future<void> _pendingWrite = Future<void>.value();
  @visibleForTesting
  static Directory? testRootDirectory;

  static Future<void> load() => _loading ??= _load();

  static Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final photos = <ManualCameraPhoto>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final photo = ManualCameraPhoto.fromJson(
          Map<String, dynamic>.from(entry),
        );
        if (photo.id.isEmpty || photo.eventId.isEmpty) continue;
        if (photo.isPending && !await File(photo.path).exists()) continue;
        photos.add(photo);
      }
      items.value = photos;
    } catch (_) {
      // An invalid index must not cause unrelated camera transfers to fail.
    }
  }

  static Future<T> _exclusive<T>(Future<T> Function() action) async {
    final previous = _pendingWrite;
    final release = Completer<void>();
    _pendingWrite = release.future;
    await previous;
    try {
      await load();
      return await action();
    } finally {
      release.complete();
    }
  }

  static Future<void> _persist(List<ManualCameraPhoto> photos) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(photos.map((p) => p.toJson()).toList());
    if (!await prefs.setString(_key, encoded)) {
      throw FileSystemException('Could not save manual photo review index');
    }
    items.value = List.unmodifiable(photos);
  }

  static String _idFor(EventSummary event, String fingerprint) =>
      sha256.convert(utf8.encode('${event.id}|$fingerprint')).toString();

  static Future<File> _fileFor(String id, String filename) async {
    final root = testRootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}manual_camera_review',
    );
    if (!await directory.exists()) await directory.create(recursive: true);
    // Files are named only by a hash, never by a camera-supplied path.
    final extensionMatch = RegExp(
      r'\.([a-zA-Z0-9]{1,6})$',
    ).firstMatch(filename);
    final extension = extensionMatch?.group(1)?.toLowerCase() ?? 'jpg';
    return File('${directory.path}${Platform.pathSeparator}$id.$extension');
  }

  static Future<ManualCameraPhoto> stageFile({
    required EventSummary event,
    required String path,
    required String filename,
    required String fingerprint,
    required String source,
    required bool isEnhanced,
    String? albumId,
    String? cameraId,
  }) => _exclusive(() async {
    final id = _idFor(event, fingerprint);
    for (final photo in items.value) {
      if (photo.id == id) return photo;
    }
    final destination = await _fileFor(id, filename);
    await File(path).copy(destination.path);
    final photo = ManualCameraPhoto(
      id: id,
      eventId: event.id,
      eventTitle: event.title,
      filename: filename,
      path: destination.path,
      fingerprint: fingerprint,
      source: source,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isEnhanced: isEnhanced,
      albumId: albumId,
      cameraId: cameraId,
      status: 'pending',
    );
    await _persist([...items.value, photo]);
    return photo;
  });

  static Future<ManualCameraPhoto> stageBytes({
    required EventSummary event,
    required Uint8List bytes,
    required String filename,
    required String fingerprint,
    required String source,
    required bool isEnhanced,
    String? albumId,
    String? cameraId,
  }) => _exclusive(() async {
    final id = _idFor(event, fingerprint);
    for (final photo in items.value) {
      if (photo.id == id) return photo;
    }
    final destination = await _fileFor(id, filename);
    await destination.writeAsBytes(bytes, flush: true);
    final photo = ManualCameraPhoto(
      id: id,
      eventId: event.id,
      eventTitle: event.title,
      filename: filename,
      path: destination.path,
      fingerprint: fingerprint,
      source: source,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isEnhanced: isEnhanced,
      albumId: albumId,
      cameraId: cameraId,
      status: 'pending',
    );
    await _persist([...items.value, photo]);
    return photo;
  });

  static List<ManualCameraPhoto> pendingFor(String eventId) =>
      items.value.where((p) => p.eventId == eventId && p.isPending).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Call only *after* the existing upload queue has accepted its own durable
  /// copy. Never remove the camera's source file here.
  static Future<void> markSubmitted(String id) => _mark(id, 'submitted');

  /// This removes only an app-owned local review copy, never camera media.
  static Future<void> discard(String id) => _mark(id, 'discarded');

  static Future<void> _mark(String id, String status) => _exclusive(() async {
    final photos = [...items.value];
    final index = photos.indexWhere((photo) => photo.id == id);
    if (index < 0 || !photos[index].isPending) return;
    final photo = photos[index];
    photos[index] = photo.withStatus(status);
    await _persist(photos);
    try {
      await File(photo.path).delete();
    } on FileSystemException {
      // The index is already updated; a delayed cleanup does not resurrect
      // or accidentally approve an unwanted photo.
    }
  });

  @visibleForTesting
  static void resetInMemoryForTest() {
    _loading = null;
    _pendingWrite = Future<void>.value();
    testRootDirectory = null;
    items.value = const [];
  }
}
