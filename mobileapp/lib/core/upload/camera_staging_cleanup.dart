import 'dart:io';

import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/upload/camera_private_files.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only private camera staging copies whose durable upload queue save succeeded
/// may enter this journal. Never pass camera-card or phone-gallery originals.
class CameraStagingCleanup {
  CameraStagingCleanup._();

  static const _key = 'camera_staging_cleanup_v1';
  static Future<void> _tail = Future<void>.value();

  static Future<void> _serial(Future<void> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  static Future<void> _save(SharedPreferences prefs, Set<String> paths) async {
    if (!await prefs.setStringList(_key, paths.toList())) {
      throw StateError('Unable to save temporary camera file cleanup');
    }
  }

  /// Caller has already persisted a separate queue copy or a cloud receipt.
  static Future<void> release(String path) => _serial(() async {
    if (path.isEmpty) return;
    if (!await CameraPrivateFiles.isStagingPath(path)) {
      throw FileSystemException(
        'Refusing cleanup outside private camera staging',
        path,
      );
    }
    final prefs = getIt<SharedPreferences>();
    final paths = (prefs.getStringList(_key) ?? const <String>[]).toSet();
    if (paths.add(path)) await _save(prefs, paths);
    if (await _remove(path)) {
      paths.remove(path);
      await _save(prefs, paths);
    }
  });

  static Future<void> retryPending() => _serial(() async {
    final prefs = getIt<SharedPreferences>();
    final paths = (prefs.getStringList(_key) ?? const <String>[]).toSet();
    if (paths.isEmpty) return;
    final remaining = <String>{};
    for (final path in paths) {
      if (!await _remove(path)) remaining.add(path);
    }
    if (remaining.length != paths.length) await _save(prefs, remaining);
  });

  static Future<bool> _remove(String path) async {
    try {
      // Revalidate persisted paths after restart; discard an unsafe journal
      // entry without touching its file.
      if (!await CameraPrivateFiles.isStagingPath(path)) return true;
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) return true;
      // Never recurse: a wrong path must not delete a directory of photographs.
      if (type != FileSystemEntityType.file) return false;
      await File(path).delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}
