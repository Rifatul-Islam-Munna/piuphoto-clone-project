import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/pages/upload/camera_transfer_page.dart';

void main() {
  testWidgets(
    'phone selected photos use the same monitor, counts and upload controls',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });

      final photos = ValueNotifier<List<PickedTransferPhoto>>([
        const PickedTransferPhoto(path: 'missing-1.jpg', filename: 'first.jpg'),
        const PickedTransferPhoto(
          path: 'missing-2.jpg',
          filename: 'second.jpg',
        ),
      ]);
      final uploading = ValueNotifier<bool>(false);
      final manualMode = ValueNotifier<bool>(false);
      final session = ValueNotifier<CameraTransferSessionStatus>(
        const CameraTransferSessionStatus(
          connectionLabel: 'Not connected',
          message: 'No camera connected',
          isActive: false,
        ),
      );
      final transfers = ValueNotifier<List<TransferLedgerItem>>([]);
      final queue = ValueNotifier<List<PendingUploadItem>>([]);
      var uploadCalls = 0;
      var cameraOptions = 0;
      var addCalls = 0;
      var removed = '';
      addTearDown(() {
        photos.dispose();
        uploading.dispose();
        manualMode.dispose();
        session.dispose();
        transfers.dispose();
        queue.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          home: CameraTransferPage(
            eventId: 'event',
            eventTitle: 'Wedding album',
            selectedSource: 'phone',
            session: session,
            transfers: transfers,
            queue: queue,
            pickedPhotos: photos,
            pickedUploading: uploading,
            onUploadPickedPhotos: () async {
              uploadCalls++;
              photos.value = const [];
            },
            onClearPickedPhotos: () => photos.value = const [],
            onRemovePickedPhoto: (path) {
              removed = path;
              photos.value = photos.value
                  .where((photo) => photo.path != path)
                  .toList();
            },
            onAddPickedPhotos: () => addCalls++,
            onCameraOptions: () => cameraOptions++,
            manualCaptureMode: manualMode,
            onChangeManualMode: (value) async => manualMode.value = value,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Wedding album'), findsOneWidget);
      expect(find.text('Photos ready to upload'), findsOneWidget);
      expect(find.text('Selected photos (2)'), findsOneWidget);
      expect(find.text('All 2'), findsOneWidget);
      expect(find.text('Not uploaded 2'), findsOneWidget);

      await tester.ensureVisible(find.text('Upload selected (2)'));
      await tester.tap(find.text('Upload selected (2)'));
      await tester.pumpAndSettle();
      expect(uploadCalls, 1);
      expect(find.text('Selected photos (2)'), findsNothing);

      photos.value = const [
        PickedTransferPhoto(path: 'missing-1.jpg', filename: 'first.jpg'),
      ];
      await tester.pumpAndSettle();
      expect(find.text('Selected photos (1)'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Remove first.jpg'));
      await tester.tap(find.byTooltip('Remove first.jpg'));
      await tester.pumpAndSettle();
      expect(removed, 'missing-1.jpg');

      await tester.tap(find.byTooltip('More camera transfer actions'));
      await tester.pumpAndSettle();
      expect(find.text('Upload settings'), findsOneWidget);
      expect(find.text('Camera options'), findsOneWidget);
      await tester.tap(find.text('Camera options'));
      await tester.pumpAndSettle();
      expect(cameraOptions, 1);

      await tester.tap(find.byTooltip('More camera transfer actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose more photos'));
      await tester.pumpAndSettle();
      expect(addCalls, 1);

      await tester.tap(find.byTooltip('More camera transfer actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload settings'));
      await tester.pumpAndSettle();
      expect(find.text('Shoot & Upload'), findsOneWidget);
      expect(find.text('Select & Upload'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
