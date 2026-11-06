import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Ownership checks for automatic cleanup. Never infer ownership from a file
/// name alone, and reject links that resolve outside the private directories.
class CameraPrivateFiles {
  CameraPrivateFiles._();

  static Future<bool> isStagingPath(String path) async {
    final caches = await getTemporaryDirectory();
    final bases = [caches, if (Platform.isIOS) Directory.systemTemp];
    for (final base in bases) {
      for (final name in [
        'airpix_ptp_tether',
        'airpix_ptp_fallback',
        'camera_import',
        'camera_ftp',
        'ptp-tether',
      ]) {
        if (await _inside(path, Directory('${base.path}/$name'))) return true;
      }
      // Legacy Android camera downloads are flat cache files.
      final file = File(path).absolute;
      if (Platform.isAndroid &&
          RegExp(r'^camera_[0-9]+_').hasMatch(file.uri.pathSegments.last) &&
          file.parent.absolute.uri == base.absolute.uri &&
          await _inside(path, base)) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> isQueuePath(String path) async {
    final documents = await getApplicationDocumentsDirectory();
    return _inside(path, Directory('${documents.path}/upload_queue'));
  }

  static bool _descendant(String path, String root) {
    var candidate = File(path).absolute.uri.normalizePath().path;
    var parent = Directory(root).absolute.uri.normalizePath().path;
    if (!parent.endsWith('/')) parent += '/';
    if (Platform.isWindows) {
      candidate = candidate.toLowerCase();
      parent = parent.toLowerCase();
    }
    return candidate.startsWith(parent) && candidate.length > parent.length;
  }

  static Future<bool> _inside(String path, Directory root) async {
    if (path.isEmpty) return false;
    if (await FileSystemEntity.type(root.path, followLinks: false) ==
        FileSystemEntityType.link) {
      return false;
    }
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.link) return false;
    if (type == FileSystemEntityType.notFound) {
      return _descendant(path, root.path);
    }
    try {
      // iOS can spell the same sandbox path with /var or /private/var.
      // Compare canonical existing paths so those aliases remain valid.
      final resolved = await File(path).resolveSymbolicLinks();
      final resolvedRoot = await root.resolveSymbolicLinks();
      return _descendant(resolved, resolvedRoot);
    } on FileSystemException {
      return false;
    }
  }
}
