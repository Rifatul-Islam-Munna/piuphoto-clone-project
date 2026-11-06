import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/camera_http_auth.dart';

void main() {
  // RFC 7616 section 3.9.1, published interoperability vectors.
  for (final entry in {
    'MD5': '8ca523f5e9506fed4657c9700eebdbec',
    'SHA-256':
        '753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1',
  }.entries) {
    test('RFC 7616 ${entry.key} challenge response', () {
      final auth = CameraHttpAuth(
        'Mufasa',
        'Circle of Life',
        nonceFactory: () => 'f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ',
      );
      expect(
        auth.acceptChallenge(
          'Digest realm="http-auth@example.org", '
          'qop="auth, auth-int", algorithm=${entry.key}, '
          'nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", '
          'opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS"',
        ),
        isTrue,
      );
      final header = auth.header(
        'GET',
        Uri.parse('http://www.example.org/dir/index.html'),
      );
      expect(header, contains('response="${entry.value}"'));
      expect(header, contains('nc=00000001'));
      expect(header, contains('uri="/dir/index.html"'));
      expect(
        auth.header('GET', Uri.parse('http://www.example.org/dir/index.html')),
        contains('nc=00000002'),
      );
    });
  }

  test('unsupported or malformed challenges are rejected', () {
    final auth = CameraHttpAuth('user', 'password');
    for (final value in [
      'Bearer token',
      'Digest realm="Camera"',
      'Digest realm="Camera", nonce="x", algorithm=unknown',
      'Digest realm="Camera", nonce="x", qop="auth-int"',
      'Digest realm="Camera", nonce="x", userhash=true',
      'Digest realm="Camera"\r\nHeader: value',
    ]) {
      expect(auth.acceptChallenge(value), isFalse);
    }
    expect(auth.header('GET', Uri.parse('http://camera/')), isNull);
  });
}
