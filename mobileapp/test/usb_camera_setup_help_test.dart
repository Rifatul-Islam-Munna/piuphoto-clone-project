import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/pages/upload/usb_camera_setup_help.dart';

void main() {
  testWidgets('setup remains usable on a narrow phone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const UsbCameraSetupHelpDialog(),
              ),
              child: const Text('Setup'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Setup'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('USB remote control / tethered shooting'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Remote Shooting, PC Remote, or PC(Tether)'),
      findsOneWidget,
    );
    expect(find.text('No automatic storage-mode fallback'), findsOneWidget);
    for (final brand in [
      'Panasonic / LUMIX',
      'Olympus / OM SYSTEM',
      'Pentax / Ricoh',
      'Canon EOS',
      'Nikon',
      'Sony Alpha 7 IV (ILCE-7M4)',
      'Sony Alpha 7R IV (ILCE-7RM4)',
    ]) {
      final tile = find.text(brand);
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.textContaining('Photo Import/Remote Control'), findsWidgets);
    expect(
      find.textContaining('Remote Shooting (NOT Mass Storage)'),
      findsOneWidget,
    );
    expect(find.textContaining('Dest.+Camera'), findsOneWidget);
    expect(find.textContaining('Desktop tethering'), findsNothing);
    expect(find.textContaining('a desktop tethering app'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(UsbCameraSetupHelpDialog), findsNothing);
  });

  testWidgets(
    'receiving an old photo does not claim shutter or cloud verification',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: UsbCameraReceiveStatus(photoReceived: false)),
        ),
      );
      expect(find.text('Ready for a test photo'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: UsbCameraReceiveStatus(photoReceived: true)),
        ),
      );
      expect(find.text('Photo received on phone'), findsOneWidget);
      expect(
        find.textContaining('take a new photo with the camera shutter'),
        findsOneWidget,
      );
      expect(find.textContaining('cloud upload progress'), findsOneWidget);
      expect(find.textContaining('Shutter verified'), findsNothing);
      expect(find.textContaining('Uploaded to cloud'), findsNothing);
    },
  );
}
