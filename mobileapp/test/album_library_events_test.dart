import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/storage/user_storage.dart';
import 'package:mobileapp/core/theme/app_theme.dart';
import 'package:mobileapp/models/user_model.dart';
import 'package:mobileapp/pages/event_gallery/album_library_page.dart';
import 'package:mobileapp/pages/event_gallery/album_settings_page.dart';
import 'package:mobileapp/pages/events/events_page.dart';
import 'package:mobileapp/pages/upload/upload_page.dart';
import 'package:mobileapp/utilities/app_toast.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _AlbumLibraryAdapter backend;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(preferences);

    UserStorage.currentUser.value = const UserModel(
      role: 'photographer',
      mongoId: 'owner-1',
    );
    dotenv.loadFromString(envString: 'API_URL=https://api.example.test');
    DioHelper.init();
    DioHelper.dio.interceptors.clear();
    backend = _AlbumLibraryAdapter();
    DioHelper.dio.httpClientAdapter = backend;
  });

  tearDown(() async {
    UserStorage.currentUser.value = null;
    DioHelper.dio.close(force: true);
    await getIt.reset();
  });

  testWidgets('existing events appear as albums without Album documents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppToast.messengerKey,
        home: const AlbumLibraryPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Albums'), findsOneWidget);
    expect(find.text('Wedding shoot'), findsOneWidget);
    expect(find.text('7 photos'), findsOneWidget);
    expect(find.text('1 albums'), findsOneWidget);
    expect(backend.albumListRequests, 0);

    await tester.tap(find.text('Wedding shoot'));
    await tester.pumpAndSettle();
    final shareButton = tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip('Share album'),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect((shareButton.icon as Icon).icon, Icons.share_rounded);
    expect(shareButton.style?.backgroundColor?.resolve({}), AppColors.cream);

    expect(backend.eventImageQueries, hasLength(1));
    expect(
      backend.eventImageQueries.single['eventId'],
      '507f1f77bcf86cd799439011',
    );
    expect(backend.eventImageQueries.single.containsKey('albumId'), isFalse);

    // Sharing remains available for an empty event and uses the event's
    // public QR link. Its Settings shortcut opens the dedicated settings flow.
    await tester.tap(find.byTooltip('Share album'));
    await tester.pumpAndSettle();
    expect(find.text('Facebook'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('WeChat'), findsOneWidget);
    expect(find.text('Telegram'), findsOneWidget);
    expect(find.text('Messenger'), findsOneWidget);
    expect(find.text('LINE'), findsNWidgets(2));
    expect(find.text('More'), findsNWidgets(2));
    expect(find.text('Settings'), findsNWidgets(2));
    expect(find.text('QR code'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Basic info'), findsOneWidget);
    expect(find.text('Album & Photo Privacy'), findsOneWidget);
    expect(find.text('Banner'), findsOneWidget);
    expect(find.text('Photo Watermark'), findsOneWidget);
    expect(find.text('Workflow Management'), findsOneWidget);
    expect(find.text('Upload settings'), findsOneWidget);
    expect(find.text('Store settings'), findsOneWidget);
    expect(find.text('Splash Screen poster'), findsNothing);
    expect(find.text('Access URL'), findsNothing);
    expect(find.text('Brand card'), findsNothing);
    expect(find.text('Advanced Branding'), findsNothing);
    expect(find.text('AI Photo Search'), findsNothing);
    expect(find.text('Guest notifications & delivery'), findsNothing);
    expect(find.text('Photo display & gallery options'), findsNothing);
    await tester.tap(find.text('Photo Watermark'));
    await tester.pumpAndSettle();
    expect(find.text('Opacity 70%'), findsOneWidget);
    expect(find.text('Size 24%'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic info').last);
    await tester.pumpAndSettle();
    expect(find.text('Basic info'), findsOneWidget);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(backend.eventUpdateRequests, 1);
  });

  testWidgets(
    'Store settings opens inside Settings and saves existing store options',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: AppToast.messengerKey,
          home: AlbumSettingsPage(
            albumId: null,
            eventId: '507f1f77bcf86cd799439011',
            eventTitle: 'Wedding shoot',
            albumTitle: 'Wedding shoot',
            albumDescription: 'Saturday wedding',
            onOpenWorkflow: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Store settings'));
      await tester.tap(find.text('Store settings'));
      await tester.pumpAndSettle();

      expect(find.text('Enable store for this event'), findsOneWidget);
      expect(find.text('Price per photo'), findsOneWidget);
      expect(find.text('Whole event price'), findsOneWidget);
      expect(find.text('Bundle price'), findsOneWidget);
      expect(find.text('Use my Stripe account'), findsOneWidget);
      expect(find.text('Who can view this gallery?'), findsNothing);
      expect(backend.storeSettingsReads, 1);

      await tester.tap(find.text('Enable store for this event'));
      final price = find.widgetWithText(TextField, 'Price per photo');
      await tester.ensureVisible(price);
      await tester.enterText(price, '12.50');
      await tester.ensureVisible(find.text('Save store settings'));
      await tester.tap(find.text('Save store settings'));
      await tester.pumpAndSettle();

      expect(backend.storeSettingsWrites, 1);
      expect(backend.savedStoreSettings['eventId'], '507f1f77bcf86cd799439011');
      expect(backend.savedStoreSettings['enabled'], true);
      expect(backend.savedStoreSettings['singlePhotoPrice'], 12.5);
    },
  );

  testWidgets('Album upload method shows only wired and wireless until More', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppToast.messengerKey,
        home: const AlbumLibraryPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Wedding shoot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload'));
    await tester.pumpAndSettle();

    // The upload controller is mounted directly in the modal sheet, not
    // pushed as a second full-screen page.
    final uploadController = find.byType(UploadPage);
    expect(uploadController, findsOneWidget);
    expect(tester.widget<UploadPage>(uploadController).asBottomSheet, isTrue);
    expect(find.text('Upload method'), findsOneWidget);
    expect(find.text('Wired Camera Connection'), findsOneWidget);
    expect(find.text('Wireless Camera Connection'), findsOneWidget);
    expect(find.text('Phone Gallery'), findsNothing);
    expect(find.text('Card Reader / Files'), findsNothing);

    await tester.tap(find.text('More upload methods'));
    await tester.pumpAndSettle();
    expect(find.text('Phone Gallery'), findsOneWidget);
    expect(find.text('Card Reader / Files'), findsOneWidget);
    expect(find.text('Choose Camera Photos'), findsOneWidget);
    expect(find.text('Watch Phone Gallery'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Close upload sheet'));
    await tester.tap(find.byTooltip('Close upload sheet'));
    await tester.pumpAndSettle();
    expect(find.byType(UploadPage), findsNothing);
    expect(find.text('Wedding shoot'), findsWidgets);
  });

  testWidgets(
    'Album settings exposes invitations and persists AI enhancement',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: AppToast.messengerKey,
          home: AlbumSettingsPage(
            albumId: null,
            eventId: '507f1f77bcf86cd799439011',
            eventTitle: 'Wedding shoot',
            albumTitle: 'Wedding shoot',
            albumDescription: 'Saturday wedding',
            onOpenWorkflow: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Invite photographers'));
      await tester.tap(find.text('Invite photographers'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Find photographers and invite them to collaborate on this album.',
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // Change the saved event setting directly from Album Settings:
      // no second page, local-only switch or duplicate flags.
      await tester.ensureVisible(
        find.byKey(const Key('event-auto-enhance-switch')),
      );
      expect(find.text('AI image enhancement'), findsOneWidget);
      expect(backend.autoEnhanceImages, false);
      await tester.tap(find.byKey(const Key('event-auto-enhance-switch')));
      await tester.pumpAndSettle();
      expect(backend.autoEnhanceImages, true);
      expect(backend.enhancementUpdates, 1);
      expect(backend.lastEnhancementEventId, '507f1f77bcf86cd799439011');
      await tester.tap(find.byKey(const Key('event-auto-enhance-switch')));
      await tester.pumpAndSettle();
      expect(backend.autoEnhanceImages, false);
      expect(backend.enhancementUpdates, 2);
    },
  );

  testWidgets('Privacy screen no longer duplicates the store form', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: AppToast.messengerKey,
        home: const EventGalleryPrivacyPage(
          eventId: '507f1f77bcf86cd799439011',
          eventTitle: 'Wedding shoot',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Who can view this gallery?'), findsOneWidget);
    expect(find.text('Enable store for this event'), findsNothing);
    expect(find.text('Save store settings'), findsNothing);
    expect(backend.storeSettingsReads, 0);
  });
}

class _AlbumLibraryAdapter implements HttpClientAdapter {
  int albumListRequests = 0;
  int eventUpdateRequests = 0;
  int storeSettingsReads = 0;
  int storeSettingsWrites = 0;
  int enhancementUpdates = 0;
  bool autoEnhanceImages = false;
  String? lastEnhancementEventId;
  Map<String, dynamic> savedStoreSettings = {};
  final eventImageQueries = <Map<String, dynamic>>[];

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
            '_id': '507f1f77bcf86cd799439011',
            'title': 'Wedding shoot',
            'description': 'Saturday wedding',
            'userId': {'_id': 'owner-1'},
            'photosCount': 7,
          },
        ],
      });
    }

    if (path == '/event-members/mine' && options.method == 'GET') {
      return _json({'data': []});
    }

    if (path == '/gallery-access/settings' && options.method == 'GET') {
      return _json({
        'data': {
          'branding': {
            'watermarkOpacity': 0.7,
            'watermarkScale': 24,
            'watermarkPosition': 'bottom_right',
          },
        },
      });
    }

    if (path == '/event/get-one' && options.method == 'GET') {
      return _json({
        'data': {
          '_id': '507f1f77bcf86cd799439011',
          'title': 'Wedding shoot',
          'autoEnhanceImages': autoEnhanceImages,
        },
      });
    }

    if (path == '/user/get-all' && options.method == 'GET') {
      return _json({'data': []});
    }

    if (path == '/store/settings' && options.method == 'GET') {
      storeSettingsReads++;
      return _json({
        'data': {
          'enabled': savedStoreSettings['enabled'] ?? false,
          'currency': savedStoreSettings['currency'] ?? 'USD',
          'singlePhotoPrice': savedStoreSettings['singlePhotoPrice'] ?? 5,
          'wholeEventPrice': 0,
          'bundlePrice': 0,
          'bundleMinPhotos': 10,
          'watermarkedPreview': true,
          'useCustomStripe': false,
        },
      });
    }

    if (path == '/store/settings' && options.method == 'PATCH') {
      storeSettingsWrites++;
      savedStoreSettings = Map<String, dynamic>.from(options.data as Map);
      return _json({'data': savedStoreSettings});
    }

    if (path == '/event/update' && options.method == 'PATCH') {
      eventUpdateRequests++;
      if (options.data is Map &&
          (options.data as Map).containsKey('autoEnhanceImages')) {
        enhancementUpdates++;
        autoEnhanceImages = (options.data as Map)['autoEnhanceImages'] == true;
        lastEnhancementEventId = options.queryParameters['id']?.toString();
      }
      return _json({'message': 'updated'});
    }

    if (path == '/eventImage/get-all' && options.method == 'GET') {
      eventImageQueries.add(Map<String, dynamic>.from(options.queryParameters));
      return _json({'data': [], 'totalPages': 0});
    }

    if (path == '/album/get-all' && options.method == 'GET') {
      albumListRequests++;
      return _json({'data': []});
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
