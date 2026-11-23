import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/pages/upload/upload_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('compact upload selector keeps all four actions on one row', (
    tester,
  ) async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    UserStorage.currentUser.value = const UserModel(role: 'event_planner');
    ActiveEventStorage.activeEvent.value = const EventSummary(
      id: 'event-one',
      title: 'Solo Workspace',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      UserStorage.currentUser.value = null;
      ActiveEventStorage.activeEvent.value = null;
      await tester.binding.setSurfaceSize(null);
      await getIt.reset();
    });

    for (final width in [320.0, 390.0]) {
      await tester.binding.setSurfaceSize(Size(width, 900));
      await tester.pumpWidget(const MaterialApp(home: UploadPage()));
      await tester.pumpAndSettle();

      // The album name appears in the top bar and in the compact picker.
      // Assert alignment against the picker itself, not both text instances.
      final name = find.widgetWithText(OutlinedButton, 'Solo Workspace');
      final create = find.byTooltip('Create event & activate');
      final gallery = find.byTooltip('Gallery QR');
      final face = find.byTooltip('Face QR');
      expect(name, findsOneWidget);
      expect(create, findsOneWidget);
      expect(gallery, findsOneWidget);
      expect(face, findsOneWidget);
      final nameY = tester.getCenter(name).dy;
      for (final control in [create, gallery, face]) {
        expect((tester.getCenter(control).dy - nameY).abs(), lessThan(25));
      }
      final selectorCard = find
          .ancestor(of: gallery, matching: find.byType(Card))
          .first;
      expect(tester.getSize(selectorCard).height, lessThan(70));
      expect(tester.takeException(), isNull);
      // Dispose between iterations: never keep a live Upload screen
      // simultaneously mounted while its selection state is replaced.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}
