import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/upload/upload_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Nikon wireless setup is reachable without opening USB or connecting on cancel',
    (tester) async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      getIt.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      );
      ActiveEventStorage.activeEvent.value = const EventSummary(
        id: 'event',
        title: 'Camera test',
      );
      final calls = <MethodCall>[];
      const channel = MethodChannel('airpix/otg_picker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(() async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        ActiveEventStorage.activeEvent.value = null;
        await getIt.reset();
      });
      await tester.pumpWidget(const MaterialApp(home: UploadPage()));
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      expect(find.text('Select from phone gallery'), findsOneWidget);
      expect(find.text('Select from connected camera'), findsOneWidget);
      await tester.ensureVisible(find.text('More upload methods'));
      await tester.tap(find.text('More upload methods'));
      await tester.pumpAndSettle();
      expect(find.text('Upload method'), findsOneWidget);
      expect(find.text('Select & Upload'), findsNWidgets(2));
      expect(find.text('Card reader / Files'), findsOneWidget);
      expect(find.text('Shoot & Upload'), findsOneWidget);
      Navigator.of(tester.element(find.text('Upload method'))).pop();
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start wireless'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nikon Wi-Fi (PTP/IP)'));
      await tester.pumpAndSettle();
      expect(find.text('Nikon Wi-Fi camera'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Wireless setup cancelled.'), findsOneWidget);
      expect(calls, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
