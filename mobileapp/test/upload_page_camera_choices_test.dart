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
      await tester.ensureVisible(find.text('Start wireless'));
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
