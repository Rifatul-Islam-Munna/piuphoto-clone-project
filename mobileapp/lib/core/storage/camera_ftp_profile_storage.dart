import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class CameraFtpProfile {
  const CameraFtpProfile({required this.username, required this.password});

  final String username;
  final String password;
  static const port = 2121;
}

/// Keep the phone's FTP profile stable so the camera can remember it. These
/// credentials stay in device secure storage and never enter the upload ledger.
class CameraFtpProfileStorage {
  static const _storage = FlutterSecureStorage();
  static const _passwordKey = 'airpix_camera_ftp_password_v1';
  static Future<CameraFtpProfile>? _loading;

  static Future<CameraFtpProfile> load() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  static Future<CameraFtpProfile> _load() async {
    var password = await _storage.read(key: _passwordKey);
    if (password == null || password.isEmpty) {
      const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
      final random = Random.secure();
      password = List.generate(
        16,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      await _storage.write(key: _passwordKey, value: password);
    }
    return CameraFtpProfile(username: 'airpix', password: password);
  }
}
