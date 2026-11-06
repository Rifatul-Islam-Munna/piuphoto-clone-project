import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/pages/upload/canon_wireless_setup_dialog.dart';

void main() {
  test('camera address preserves only explicit origin and port', () {
    expect(
      parseCanonWirelessAddress('192.168.1.10:8080').toString(),
      'http://192.168.1.10:8080/',
    );
    expect(
      parseCanonWirelessAddress('https://camera.local:8443/ccapi').toString(),
      'https://camera.local:8443/',
    );
    for (final input in [
      '',
      'ftp://camera',
      'http://user:password@camera',
      'http://camera/capture',
      'http://camera/live',
      'http://camera/?command=capture',
      'http://camera/#capture',
      'http://camera:0',
      'http://camera:65536',
    ]) {
      expect(
        () => parseCanonWirelessAddress(input),
        throwsFormatException,
        reason: input,
      );
    }
  });

  testWidgets('setup is scrollable at narrow width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    CanonWirelessSettings? result;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<CanonWirelessSettings>(
                  context: context,
                  builder: (_) => const CanonWirelessSetupDialog(
                    initialAddress: 'http://192.168.1.10:8080',
                    cameraHotspot: true,
                  ),
                );
              },
              child: const Text('Setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Local Network access'), findsOneWidget);
    expect(find.textContaining('does not start live view'), findsOneWidget);
    final password = find.byType(TextFormField).last;
    await tester.ensureVisible(password);
    await tester.pumpAndSettle();
    await tester.enterText(password, 'temporary-password');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result?.origin.port, 8080);
    expect(result?.password, 'temporary-password');
    expect(find.byType(CanonWirelessSetupDialog), findsNothing);
  });
}
