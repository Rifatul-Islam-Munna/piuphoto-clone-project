import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/pages/upload/camera_transfer_page.dart';
import 'package:mobileapp/pages/upload/manual_camera_staging.dart';

void main() {
  testWidgets(
    'three-dot menu changes approval mode and only selected files are sent',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.binding.setSurfaceSize(null);
      });

      // Only the UI selection logic is tested here; file persistence is
      // independently covered by manual_camera_staging_test.dart.
      final first = File('missing_first.jpg');
      final second = File('missing_second.jpg');

      final manual = ValueNotifier<bool>(false);
      final session = ValueNotifier<CameraTransferSessionStatus>(
        const CameraTransferSessionStatus(
          connectionLabel: 'USB camera',
          message: 'Camera connected',
          isActive: true,
        ),
      );
      final photos = ValueNotifier<List<ManualCameraPhoto>>([]);
      final transfers = ValueNotifier<List<TransferLedgerItem>>([]);
      final queue = ValueNotifier<List<PendingUploadItem>>([]);
      final uploaded = <String>[];
      final discarded = <String>[];
      var shares = 0;
      addTearDown(() {
        manual.dispose();
        session.dispose();
        photos.dispose();
        transfers.dispose();
        queue.dispose();
      });

      ManualCameraPhoto photo(String id, File file) => ManualCameraPhoto(
        id: id,
        eventId: 'event',
        eventTitle: 'Live shoot',
        filename: '$id.jpg',
        path: file.path,
        fingerprint: 'usb|$id',
        source: 'usb',
        createdAt: 100,
        isEnhanced: false,
        status: 'pending',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CameraTransferPage(
            eventId: 'event',
            eventTitle: 'Live shoot',
            session: session,
            transfers: transfers,
            queue: queue,
            manualCaptureMode: manual,
            manualInbox: photos,
            onChangeManualMode: (value) async => manual.value = value,
            onShareGallery: () => shares++,
            onUploadManual: (ids) async {
              uploaded.addAll(ids);
              photos.value = photos.value
                  .where((p) => !ids.contains(p.id))
                  .toList();
            },
            onDiscardManual: (ids) async {
              discarded.addAll(ids);
              photos.value = photos.value
                  .where((p) => !ids.contains(p.id))
                  .toList();
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byTooltip('Share album QR code'), findsOneWidget);
      await tester.tap(find.byTooltip('Share album QR code'));
      expect(shares, 1);

      await tester.tap(find.byTooltip('More camera transfer actions'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Upload settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Shoot & Upload'), findsOneWidget);
      expect(find.text('Select & Upload'), findsOneWidget);
      await tester.tap(find.text('Select & Upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(manual.value, isTrue);
      expect(find.textContaining('Nothing to review yet'), findsOneWidget);

      photos.value = [photo('first', first), photo('second', second)];
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('2 pending'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('review-first')));
      await tester.tap(find.byKey(const ValueKey('review-first')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Upload selected (1)'));
      await tester.tap(find.text('Upload selected (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(uploaded, ['first']);
      expect(discarded, isEmpty);
      expect(find.text('1 pending'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const ValueKey('review-second')));
      await tester.tap(find.byKey(const ValueKey('review-second')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('Remove'));
      await tester.tap(find.text('Remove'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Remove local copies?'), findsOneWidget);
      await tester.tap(find.text('Remove').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(discarded, ['second']);
    },
  );
}
