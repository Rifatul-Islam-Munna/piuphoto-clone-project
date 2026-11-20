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
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/pages/events/events_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _EventsAdapter backend;
  late SharedPreferences preferences;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(preferences);

    ActiveEventStorage.activeEvent.value = null;
    ActiveEventStorage.selectionLocked.value = false;
    UserStorage.currentUser.value = const UserModel(role: 'photographer');

    dotenv.loadFromString(envString: 'API_URL=https://api.example.test');
    DioHelper.init();
    DioHelper.dio.interceptors.clear();
    backend = _EventsAdapter();
    DioHelper.dio.httpClientAdapter = backend;
  });

  tearDown(() async {
    ActiveEventStorage.activeEvent.value = null;
    ActiveEventStorage.selectionLocked.value = false;
    UserStorage.currentUser.value = null;
    DioHelper.dio.close(force: true);
    await getIt.reset();
  });

  Future<void> showEvents(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppToast.messengerKey,
        home: const EventsPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tiny Activate button selects an event without opening details', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    await showEvents(tester);

    expect(
      find.byKey(const ValueKey('activate-event-event-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('activate-event-event-b')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('activate-event-event-a')));
    await tester.pumpAndSettle();

    expect(ActiveEventStorage.activeEvent.value?.id, 'event-a');
    expect(
      jsonDecode(preferences.getString('active_event')!)['_id'],
      'event-a',
    );
    // Clicking the quick action didn't navigate into the detailed event view.
    expect(find.text('Shoots'), findsOneWidget);
    expect(backend.patchedIds, isEmpty);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('activate-event-event-a')),
    );
    expect(button.onPressed, isNull);
    expect(find.text('Active'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive backend event is reactivated before selecting it', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    await showEvents(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('activate-event-event-b')),
    );
    await tester.tap(find.byKey(const ValueKey('activate-event-event-b')));
    await tester.pumpAndSettle();

    expect(backend.patchedIds, ['event-b']);
    expect(ActiveEventStorage.activeEvent.value?.id, 'event-b');
    expect(backend.isEventBActive, isTrue);
    expect(find.text('Shoots'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active camera transfer prevents switching on the card', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    await showEvents(tester);
    await tester.tap(find.byKey(const ValueKey('activate-event-event-a')));
    await tester.pumpAndSettle();
    ActiveEventStorage.selectionLocked.value = true;
    await tester.pump();

    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('activate-event-event-b')),
    );
    expect(button.onPressed, isNull);
    expect(ActiveEventStorage.activeEvent.value?.id, 'event-a');
    expect(backend.patchedIds, isEmpty);

    ActiveEventStorage.selectionLocked.value = false;
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('activate-event-event-b')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'preview button opens the selected event inside the app without activating it',
    (tester) async {
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });
      await showEvents(tester);

      // Event A stays active while we preview event B.
      await tester.tap(find.byKey(const ValueKey('activate-event-event-a')));
      await tester.pumpAndSettle();
      expect(ActiveEventStorage.activeEvent.value?.id, 'event-a');

      await tester.ensureVisible(find.text('Second shoot'));
      await tester.tap(find.text('Second shoot'));
      await tester.pumpAndSettle();

      final previewButton = find.byKey(const ValueKey('preview-event-event-b'));
      expect(previewButton, findsOneWidget);
      await tester.ensureVisible(previewButton);
      await tester.tap(previewButton);
      await tester.pumpAndSettle();

      expect(find.text('Photo Live'), findsWidgets);
      expect(find.text('Second shoot'), findsWidgets);
      expect(ActiveEventStorage.activeEvent.value?.id, 'event-a');
      expect(backend.patchedIds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('backend reactivation failure leaves current selection alone', (
    tester,
  ) async {
    backend.failReactivation = true;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    await showEvents(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('activate-event-event-b')),
    );
    await tester.tap(find.byKey(const ValueKey('activate-event-event-b')));
    await tester.pumpAndSettle();
    expect(ActiveEventStorage.activeEvent.value, isNull);
    expect(preferences.getString('active_event'), isNull);
    expect(tester.takeException(), isNull);
  });
}

class _EventsAdapter implements HttpClientAdapter {
  final patchedIds = <String>[];
  bool isEventBActive = false;
  bool failReactivation = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) await requestStream.drain<void>();
    final path = options.uri.path;

    if (path == '/event/my-events' && options.method == 'GET') {
      return _json({
        'data': [
          {
            '_id': 'event-a',
            'title': 'Solo Workspace',
            'isPublished': true,
            'isActive': true,
            'photosCount': 8,
          },
          {
            '_id': 'event-b',
            'title': 'Second shoot',
            'isPublished': true,
            'isActive': isEventBActive,
            'photosCount': 2,
          },
        ],
      });
    }

    if (path == '/event/toggle-active' && options.method == 'PATCH') {
      patchedIds.add(options.uri.queryParameters['id'] ?? '');
      if (failReactivation) return _json({'message': 'Access denied'}, 403);
      isEventBActive = true;
      return _json({
        'data': {'isActive': true},
      });
    }
    return _json({'message': 'Not found'}, 404);
  }

  ResponseBody _json(Map<String, dynamic> data, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(data),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
