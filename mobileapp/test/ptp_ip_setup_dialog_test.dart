import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/pages/upload/ptp_ip_setup_dialog.dart';

void main() {
  test(
    'camera address accepts hosts and explicit ports but rejects malformed endpoints',
    () {
      expect(PtpIpCameraAddress.parse('192.168.1.1')?.port, 15740);
      expect(
        PtpIpCameraAddress.parse(' camera.local:15741 ')?.host,
        'camera.local',
      );
      expect(PtpIpCameraAddress.parse('[fe80::1]:15740')?.host, 'fe80::1');
      for (final address in [
        '',
        'http://192.168.1.1',
        'camera:0',
        'camera:65536',
        'camera:abc',
        'user@camera',
        'camera/path',
        'camera?query=1',
        'camera#fragment',
      ]) {
        expect(PtpIpCameraAddress.parse(address), isNull, reason: address);
      }
    },
  );

  testWidgets('wireless camera setup validates address before connecting', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PtpIpSetupDialog())),
    );
    await tester.tap(find.text('Connect & start'));
    await tester.pump();
    expect(
      find.text('Enter a camera IP or host, optionally followed by :port.'),
      findsOneWidget,
    );
  });
}
