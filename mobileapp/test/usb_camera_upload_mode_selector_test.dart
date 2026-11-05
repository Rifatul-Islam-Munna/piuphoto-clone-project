import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/pages/upload/usb_camera_upload_mode_selector.dart';

void main() {
  testWidgets(
    'both upload scopes are explicit and the user can change the next session',
    (tester) async {
      final selected = ValueNotifier(LiveCameraUploadMode.newShotsOnly);
      addTearDown(selected.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<LiveCameraUploadMode>(
              valueListenable: selected,
              builder: (context, value, _) => UsbCameraUploadModeSelector(
                value: value,
                onChanged: (mode) => selected.value = mode,
              ),
            ),
          ),
        ),
      );

      expect(find.text('New shots only'), findsOneWidget);
      expect(find.text('Existing photos + new shots'), findsOneWidget);
      expect(
        find.text('Default — upload photos taken after the session is ready.'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('usb-upload-existing-and-new')),
      );
      await tester.pump();
      expect(selected.value, LiveCameraUploadMode.existingAndNew);

      await tester.tap(find.byKey(const ValueKey('usb-upload-new-shots-only')));
      await tester.pump();
      expect(selected.value, LiveCameraUploadMode.newShotsOnly);
    },
  );

  testWidgets('an active session keeps the scope fixed until it stops', (
    tester,
  ) async {
    final requested = <LiveCameraUploadMode>[];
    await _show(
      tester,
      value: LiveCameraUploadMode.existingAndNew,
      sessionLocked: true,
      onChanged: requested.add,
    );

    expect(
      find.text('Stop the current USB session to change this setting.'),
      findsOneWidget,
    );
    expect(
      tester
          .widgetList<OutlinedButton>(find.byType(OutlinedButton))
          .every((button) => button.onPressed == null),
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('usb-upload-new-shots-only')));
    await tester.pump();
    expect(requested, isEmpty);

    await _show(
      tester,
      value: LiveCameraUploadMode.existingAndNew,
      onChanged: requested.add,
    );
    await tester.tap(find.byKey(const ValueKey('usb-upload-new-shots-only')));
    expect(requested, [LiveCameraUploadMode.newShotsOnly]);
  });

  testWidgets('a pending preference write prevents conflicting choices', (
    tester,
  ) async {
    final requested = <LiveCameraUploadMode>[];
    await _show(
      tester,
      value: LiveCameraUploadMode.existingAndNew,
      isSaving: true,
      onChanged: requested.add,
    );

    expect(find.text('Saving photo selection…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('usb-upload-new-shots-only')));
    await tester.pump();
    expect(requested, isEmpty);
  });

  testWidgets('both modes remain readable on a narrow phone with large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await _show(
      tester,
      value: LiveCameraUploadMode.newShotsOnly,
      textScale: 2,
      onChanged: (_) {},
    );

    expect(find.text('New shots only'), findsOneWidget);
    expect(find.text('Existing photos + new shots'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(
  WidgetTester tester, {
  required LiveCameraUploadMode value,
  required ValueChanged<LiveCameraUploadMode> onChanged,
  bool sessionLocked = false,
  bool isSaving = false,
  double textScale = 1,
}) => tester.pumpWidget(
  MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: UsbCameraUploadModeSelector(
            value: value,
            onChanged: onChanged,
            sessionLocked: sessionLocked,
            isSaving: isSaving,
          ),
        ),
      ),
    ),
  ),
);
