import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/pages/upload/camera_upload_sheet_view.dart';

void main() {
  testWidgets(
    'camera choices start native callbacks from the sheet, not a page',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });

      final started = <String>[];
      var closed = false;
      var transferOpened = 0;
      var settingsOpened = 0;
      final sheet = CameraUploadSheetView(
        eventTitle: 'Wedding album',
        albums: const [],
        selectedAlbumId: null,
        selectedFileCount: 0,
        receiving: false,
        isBusy: false,
        isUploading: false,
        queueCount: 0,
        pendingReviewCount: 0,
        onStart: (method) async => started.add(method),
        onClose: () => closed = true,
        onStop: () async {},
        onOpenTransfers: () => transferOpened++,
        onUploadSettings: () => settingsOpened++,
        onUsbOptions: () {},
        onWirelessOptions: () {},
        onShare: () {},
        onGuestQr: () {},
        onFaceQr: () {},
        onPreview: () {},
        onClearSelected: () {},
        onUploadSelected: () {},
        onChangeAlbum: (_) {},
        onRetryQueue: () {},
        onFreeSpace: () {},
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Center(child: sheet)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Upload method'), findsOneWidget);
      expect(find.text('Wired Camera Connection'), findsOneWidget);
      expect(find.text('Wireless Camera Connection'), findsOneWidget);
      expect(find.text('Phone Gallery'), findsNothing);
      expect(find.text('Card Reader / Files'), findsNothing);
      expect(find.text('Select from phone gallery'), findsNothing);

      await tester.ensureVisible(find.text('Start Upload'));
      await tester.tap(find.text('Start Upload'));
      await tester.pumpAndSettle();
      expect(started, ['usb']);

      await tester.ensureVisible(find.text('Wireless Camera Connection'));
      await tester.tap(find.text('Wireless Camera Connection'));
      await tester.ensureVisible(find.text('Start Upload'));
      await tester.tap(find.text('Start Upload'));
      await tester.pumpAndSettle();
      expect(started, ['usb', 'wireless']);

      await tester.tap(find.text('More upload methods'));
      await tester.pumpAndSettle();
      expect(find.text('Phone Gallery'), findsOneWidget);
      expect(find.text('Card Reader / Files'), findsOneWidget);
      await tester.ensureVisible(find.text('Phone Gallery'));
      await tester.tap(find.text('Phone Gallery'));
      await tester.ensureVisible(find.text('Start Upload'));
      await tester.tap(find.text('Start Upload'));
      await tester.pumpAndSettle();
      expect(started, ['usb', 'wireless', 'phone']);

      await tester.ensureVisible(find.text('Upload settings'));
      await tester.tap(find.text('Upload settings'));
      expect(settingsOpened, 1);
      await tester.ensureVisible(find.byTooltip('Close upload sheet'));
      await tester.tap(find.byTooltip('Close upload sheet'));
      expect(closed, true);
      expect(transferOpened, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('active camera replaces Start with direct live transfer action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });
    var monitorOpened = 0;
    var stopped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CameraUploadSheetView(
            eventTitle: 'Wedding album',
            albums: const [],
            selectedAlbumId: null,
            selectedFileCount: 0,
            receiving: true,
            isBusy: false,
            isUploading: false,
            queueCount: 2,
            pendingReviewCount: 3,
            statusMessage: 'Receiving USB photos',
            onStart: (_) async => fail('Must not restart an active session'),
            onClose: () {},
            onStop: () async => stopped++,
            onOpenTransfers: () => monitorOpened++,
            onUploadSettings: () {},
            onUsbOptions: () {},
            onWirelessOptions: () {},
            onShare: () {},
            onGuestQr: () {},
            onFaceQr: () {},
            onPreview: () {},
            onClearSelected: () {},
            onUploadSelected: () {},
            onChangeAlbum: (_) {},
            onRetryQueue: () {},
            onFreeSpace: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Start Upload'), findsNothing);
    expect(find.text('View live transfers'), findsOneWidget);
    // Counts and photo review live on the transfer monitor, not on this sheet.
    expect(find.text('3 photos awaiting selection'), findsNothing);
    await tester.ensureVisible(find.text('View live transfers'));
    await tester.tap(find.text('View live transfers'));
    expect(monitorOpened, 1);
    await tester.ensureVisible(find.text('Stop receiving'));
    await tester.tap(find.text('Stop receiving'));
    expect(stopped, 1);
    expect(tester.takeException(), isNull);
  });
}
