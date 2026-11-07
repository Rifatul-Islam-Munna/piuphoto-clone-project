import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/pages/upload/usb_camera_reader_selector.dart';

void main() {
  testWidgets('reader choice wraps, starts off and needs an explicit tap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: UsbCameraReaderSelector(
                value: false,
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      ),
    );
    expect(selected, isNull);
    expect(tester.takeException(), isNull);
    expect(find.textContaining('may lock shutter'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    expect(selected, isTrue);
  });

  testWidgets('active session disables reader changes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UsbCameraReaderSelector(value: true, onChanged: null),
        ),
      ),
    );
    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isTrue);
    expect(tile.onChanged, isNull);
  });
}
