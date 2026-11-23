import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/active_event_storage.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/home/home_page.dart';
import 'package:mobileapp/pages/events/events_page.dart';
import 'package:mobileapp/pages/invitations/invitations_page.dart';
import 'package:mobileapp/pages/onboarding/onboarding_page.dart';
import 'package:mobileapp/pages/plans/plans_page.dart';
import 'package:mobileapp/pages/profile/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    ActiveEventStorage.activeEvent.value = null;
    ActiveEventStorage.selectionLocked.value = false;
    dotenv.loadFromString(envString: 'API_URL=https://api.example.test');
    DioHelper.init();
    DioHelper.dio.interceptors.clear();
    DioHelper.dio.httpClientAdapter = _CompactPagesAdapter();
  });

  tearDown(() async {
    UserStorage.currentUser.value = null;
    ActiveEventStorage.activeEvent.value = null;
    ActiveEventStorage.selectionLocked.value = false;
    DioHelper.dio.close(force: true);
    await getIt.reset();
  });

  Future<void> showOnPhone(WidgetTester tester, Widget home) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: home),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact photographer profile keeps edit controls on narrow phones',
    (tester) async {
      UserStorage.currentUser.value = const UserModel(
        id: 'photographer-1',
        role: 'photographer',
        name: 'Photographer with a long full name',
        email: 'photographer.long.email@example.com',
        creditsValue: 15,
      );
      await showOnPhone(tester, const ProfilePage());
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Contact details'), findsOneWidget);
      expect(find.text('Workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsOneWidget);
      expect(find.byTooltip('Change profile photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('photographer Studio uses the compact album layout', (
    tester,
  ) async {
    UserStorage.currentUser.value = const UserModel(
      id: 'photographer-studio',
      role: 'photographer',
      name: 'Studio photographer',
    );
    ActiveEventStorage.activeEvent.value = const EventSummary(
      id: 'event-1',
      title: 'Wedding on Saturday',
    );
    await showOnPhone(tester, const HomePage());
    expect(find.text('Studio'), findsOneWidget);
    expect(find.text('Photographer studio'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner Overview uses the compact album layout', (tester) async {
    UserStorage.currentUser.value = const UserModel(
      id: 'planner-home',
      role: 'event_planner',
      name: 'Studio planner',
      creditsValue: 10,
    );
    ActiveEventStorage.activeEvent.value = const EventSummary(
      id: 'event-1',
      title: 'Wedding on Saturday',
    );
    await showOnPhone(tester, const HomePage());
    expect(find.text('Overview'), findsOneWidget);
    expect(find.text('Event planner workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner profile uses the same compact layout', (tester) async {
    UserStorage.currentUser.value = const UserModel(
      id: 'planner-1',
      role: 'event_planner',
      name: 'Event Planner',
      email: 'planner@example.com',
      creditsValue: 5,
    );
    await showOnPhone(tester, const ProfilePage());
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invites has a compact join card and useful empty state', (
    tester,
  ) async {
    UserStorage.currentUser.value = const UserModel(role: 'photographer');
    await showOnPhone(tester, const InvitationsPage());
    expect(find.text('Join an event'), findsOneWidget);
    expect(find.text('Your invitations'), findsOneWidget);
    expect(find.text('No invitations yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner events remain usable with album-like rows', (
    tester,
  ) async {
    UserStorage.currentUser.value = const UserModel(
      role: 'event_planner',
      name: 'Planner',
    );
    await showOnPhone(tester, const EventsPage());
    expect(find.text('Your events'), findsOneWidget);
    expect(find.text('Wedding on Saturday'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('activate-event-event-1')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner plans retain billing controls on narrow phones', (
    tester,
  ) async {
    UserStorage.currentUser.value = const UserModel(role: 'event_planner');
    await showOnPhone(tester, const PlansPage());
    expect(find.text('Plans & billing'), findsOneWidget);
    expect(find.text('Monthly'), findsOneWidget);
    expect(find.text('Yearly'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('onboarding fits the compact design on narrow phones', (
    tester,
  ) async {
    await showOnPhone(tester, const OnboardingPage());
    expect(find.text('Enter Airpix'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _CompactPagesAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    final path = options.uri.path;
    if (path == '/event/my-events') {
      return _json({
        'data': [
          {
            '_id': 'event-1',
            'title': 'Wedding on Saturday',
            'isPublished': true,
            'isActive': true,
            'photosCount': 12,
          },
        ],
      });
    }
    if (path == '/event-members/mine' ||
        path == '/event/my-photographer-invitations' ||
        path == '/subscription-plan/get-all' ||
        path == '/addon/get-all') {
      return _json({'data': []});
    }
    return _json({'data': []});
  }

  ResponseBody _json(Map<String, dynamic> data) => ResponseBody.fromString(
    jsonEncode(data),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

  @override
  void close({bool force = false}) {}
}
