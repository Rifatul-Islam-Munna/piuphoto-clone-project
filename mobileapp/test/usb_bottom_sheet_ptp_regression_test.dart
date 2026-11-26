import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/upload/camera_transfer_page.dart';
import 'package:mobileapp/pages/upload/upload_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<int> _u16(int n) => [n & 255, (n >> 8) & 255];
List<int> _u32(int n) => [for (var i = 0; i < 4; i++) (n >> (8 * i)) & 255];
List<int> _array16(List<int> a) => [
  ..._u32(a.length),
  for (final n in a) ..._u16(n),
];
List<int> _array32(List<int> a) => [
  ..._u32(a.length),
  for (final n in a) ..._u32(n),
];
List<int> _string(String s) => [
  s.length + 1,
  for (final n in s.codeUnits) ..._u16(n),
  0,
  0,
];
Uint8List _deviceInfo() => Uint8List.fromList([
  ..._u16(100),
  ..._u32(0),
  ..._u16(100),
  0,
  ..._u16(0),
  ..._array16([0x1001, 0x1004, 0x1007, 0x1008, 0x1009]),
  ..._array16([0x4002]),
  ..._array16([]),
  ..._array16([0x3801]),
  ..._array16([0x3801]),
  ..._string('Test'),
  ..._string('Test camera'),
  ..._string('1.0'),
  ..._string('TEST'),
]);

// Stream cancellation can complete in the real async zone of the test
// binding. Give that queue time to drain as well as advancing fake frames.
Future<void> _settleNativeClose(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    });
    await tester.pump(const Duration(milliseconds: 400));
  }
  await tester.pumpAndSettle();
}

void main() {
  const methods = MethodChannel('airpix/otg_picker');
  const events = MethodChannel('airpix/otg_live');

  for (final failure in <String?>[
    null,
    'CAMERA_STORAGE_ONLY',
    'LIVE_CAMERA_CANCELLED',
  ]) {
    testWidgets('album sheet PTP startup: ${failure ?? 'success'}', (
      tester,
    ) async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      getIt.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      );
      ActiveEventStorage.activeEvent.value = const EventSummary(
        id: 'event',
        title: 'Camera test',
      );
      await tester.binding.setSurfaceSize(const Size(390, 900));
      final messenger = tester.binding.defaultBinaryMessenger;
      final calls = <MethodCall>[];
      final open = Completer<Map<String, dynamic>>();
      messenger.setMockMethodCallHandler(events, (_) async => null);
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'openPtpTetherSession':
            return open.future;
          case 'sendPtpTetherCommand':
            final opcode = (call.arguments as Map)['opcode'];
            return {
              'responseCode': 0x2001,
              'parameters': <int>[],
              'data': switch (opcode) {
                0x1001 => _deviceInfo(),
                0x1004 => Uint8List.fromList(_array32([1])),
                0x1007 => Uint8List.fromList(_array32([])),
                _ => throw StateError('Unexpected PTP opcode: $opcode'),
              },
            };
          case 'closePtpTetherSession':
            return null;
          default:
            fail('Live shooting must not invoke ${call.method}');
        }
      });
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        messenger.setMockMethodCallHandler(methods, null);
        messenger.setMockMethodCallHandler(events, null);
        ActiveEventStorage.activeEvent.value = null;
        await tester.binding.setSurfaceSize(null);
        await getIt.reset();
      });
      // Exercise the real sheet from an album's nested navigator.
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showCameraUploadBottomSheet(context),
                    child: const Text('Open album upload'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open album upload'));
      await tester.pumpAndSettle();
      expect(calls, isEmpty, reason: 'Opening the sheet must be passive.');
      await tester.ensureVisible(find.text('Start Upload'));
      await tester.tap(find.text('Start Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls.map((c) => c.method), ['openPtpTetherSession']);
      expect(find.byType(CameraTransferPage), findsNothing);
      expect(find.text('View live transfers'), findsNothing);
      expect(find.byKey(const Key('camera-receiver-status')), findsOneWidget);
      final sessionId = (calls.single.arguments as Map)['sessionId'] as String;
      if (failure != null) {
        open.completeError(PlatformException(code: failure));
        await _settleNativeClose(tester);
        expect(find.byType(CameraTransferPage), findsNothing);
        if (failure == 'CAMERA_STORAGE_ONLY') {
          expect(
            find.text('Connection code: CAMERA_STORAGE_ONLY'),
            findsOneWidget,
          );
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
          expect(find.textContaining('CAMERA_STORAGE_ONLY'), findsOneWidget);
        } else {
          expect(
            find.textContaining('Live shooting cancelled'),
            findsOneWidget,
          );
        }
        expect(find.text('Start Upload'), findsOneWidget);
        expect(
          calls.where((c) => c.method == 'openPtpTetherSession'),
          hasLength(1),
        );
        expect(
          calls.where((c) => c.method == 'closePtpTetherSession'),
          isNotEmpty,
        );
      } else {
        open.complete({
          'sessionId': sessionId,
          'cameraId': 'test-usb',
          'name': 'Test camera',
          'physicalShutter': 'supported',
        });
        await tester.pumpAndSettle();
        expect(find.byType(CameraTransferPage), findsOneWidget);
        expect(
          calls.where((c) => c.method == 'closePtpTetherSession'),
          isEmpty,
        );
        // The live monitor must not permit a second USB storage owner.
        final monitor = tester.widget<CameraTransferPage>(
          find.byType(CameraTransferPage),
        );
        monitor.onCameraOptions!();
        await tester.pumpAndSettle();
        for (final title in [
          'Select stored camera photos',
          'Browse Files / SD card',
        ]) {
          final tile = tester.widget<ListTile>(
            find.widgetWithText(ListTile, title),
          );
          expect(tile.onTap, isNull);
        }
        Navigator.of(tester.element(find.text('Browse Files / SD card'))).pop();
        await tester.pumpAndSettle();
        // Returning from the monitor must not dispose the original receiver.
        Navigator.of(tester.element(find.byType(CameraTransferPage))).pop();
        await tester.pumpAndSettle();
        expect(find.text('View live transfers'), findsOneWidget);
        expect(
          calls.where((c) => c.method == 'closePtpTetherSession'),
          isEmpty,
        );
        await tester.ensureVisible(find.text('Stop receiving'));
        await tester.tap(find.text('Stop receiving'));
        await _settleNativeClose(tester);
        expect(find.text('Start Upload'), findsOneWidget);
        expect(
          calls.where((c) => c.method == 'openPtpTetherSession'),
          hasLength(1),
        );
        final closes = calls.where((c) => c.method == 'closePtpTetherSession');
        expect(closes, isNotEmpty);
        expect(
          closes.every((c) => (c.arguments as Map)['sessionId'] == sessionId),
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}
