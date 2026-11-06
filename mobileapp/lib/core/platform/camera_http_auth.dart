import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// Challenge-response headers only. The caller bounds retries and restricts
/// every request to the configured camera; this class never makes requests.
class CameraHttpAuth {
  CameraHttpAuth(
    this.username,
    this.password, {
    String Function()? nonceFactory,
  }) : _nonceFactory = nonceFactory ?? _randomNonce;
  final String username;
  final String password;
  final String Function() _nonceFactory;
  String? _scheme;
  Map<String, String> _challenge = {};
  int _count = 0;

  static String _randomNonce() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  bool acceptChallenge(String value) {
    if (value.contains('\r') || value.contains('\n')) return false;
    final scheme = value.split(' ').first.toLowerCase();
    if (scheme == 'basic') {
      _scheme = scheme;
      return true;
    }
    if (scheme != 'digest') return false;
    final fields = <String, String>{
      for (final match in RegExp(
        r'(\w+)=(?:"((?:\\.|[^"\\])*)"|([^,\s]+))',
      ).allMatches(value))
        match.group(1)!.toLowerCase(): (match.group(2) ?? match.group(3)!)
            .replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!),
    };
    final algorithm = (fields['algorithm'] ?? 'MD5').toUpperCase();
    final qops = fields['qop']?.split(',').map((s) => s.trim().toLowerCase());
    if (fields['realm'] == null ||
        fields['nonce']?.isNotEmpty != true ||
        !const [
          'MD5',
          'MD5-SESS',
          'SHA-256',
          'SHA-256-SESS',
        ].contains(algorithm) ||
        (qops != null && !qops.contains('auth')) ||
        fields['userhash'] == 'true') {
      return false;
    }
    if (_challenge['nonce'] != fields['nonce']) _count = 0;
    _challenge = fields;
    _scheme = scheme;
    return true;
  }

  String? header(String method, Uri uri) {
    if (_scheme == null) return null;
    if (_scheme == 'basic') {
      return 'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    }
    if (username.contains('\r') || username.contains('\n')) return null;
    final realm = _challenge['realm']!;
    final nonce = _challenge['nonce']!;
    final algorithm = (_challenge['algorithm'] ?? 'MD5').toUpperCase();
    final digest = algorithm.startsWith('SHA-256') ? sha256 : md5;
    String hash(String value) => digest.convert(utf8.encode(value)).toString();
    String quote(String value) =>
        '"${value.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
    final cnonce = _nonceFactory();
    final nc = (++_count).toRadixString(16).padLeft(8, '0');
    final requestUri = uri.path + (uri.hasQuery ? '?${uri.query}' : '');
    var ha1 = hash('$username:$realm:$password');
    if (algorithm.endsWith('-SESS')) ha1 = hash('$ha1:$nonce:$cnonce');
    final ha2 = hash('$method:$requestUri');
    final withQop = _challenge.containsKey('qop');
    final response = withQop
        ? hash('$ha1:$nonce:$nc:$cnonce:auth:$ha2')
        : hash('$ha1:$nonce:$ha2');
    return 'Digest ${['username=${quote(username)}', 'realm=${quote(realm)}', 'nonce=${quote(nonce)}', 'uri=${quote(requestUri)}', 'algorithm=$algorithm', 'response=${quote(response)}', if (withQop) 'qop=auth', if (withQop) 'nc=$nc', if (withQop || algorithm.endsWith('-SESS')) 'cnonce=${quote(cnonce)}', if (_challenge['opaque'] != null) 'opaque=${quote(_challenge['opaque']!)}'].join(', ')}';
  }
}
