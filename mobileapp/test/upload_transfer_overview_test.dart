import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/pages/upload/upload_transfer_overview.dart';

TransferLedgerItem photo(String id, TransferLedgerStatus status) {
  return TransferLedgerItem(
    id: id,
    eventId: 'event',
    eventTitle: 'Live event',
    filename: '$id.jpg',
    source: 'camera-usb',
    status: status,
    createdAt: 1000,
    updatedAt: 1000,
  );
}

void main() {
  testWidgets(
    'Upload page overview shows real upload counts and live thumbnails',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      final transfers = ValueNotifier<List<TransferLedgerItem>>([
        photo('queued', TransferLedgerStatus.queued),
        photo('uploading', TransferLedgerStatus.uploading),
        photo('uploaded', TransferLedgerStatus.published),
        photo('failed', TransferLedgerStatus.failed),
        photo(
          'elsewhere',
          TransferLedgerStatus.published,
        ).copyWith(progress: 100),
      ]);
      // Keep another event out of the counters even if it has the same photo name.
      transfers.value = [
        for (final item in transfers.value)
          if (item.id == 'elsewhere')
            TransferLedgerItem(
              id: item.id,
              eventId: 'different',
              eventTitle: 'Other event',
              filename: item.filename,
              source: item.source,
              status: item.status,
              createdAt: item.createdAt,
              updatedAt: item.updatedAt,
            )
          else
            item,
      ];

      var opened = 0;
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        transfers.dispose();
        await tester.binding.setSurfaceSize(null);
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: UploadTransferOverview(
                eventId: 'event',
                transfers: transfers,
                onViewAll: () => opened++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('4 received'), findsOneWidget);
      expect(find.text('1 uploaded'), findsOneWidget);
      expect(find.text('1 uploading'), findsOneWidget);
      expect(find.text('1 not uploaded'), findsOneWidget);
      expect(find.text('1 failed'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('overview-photo-uploaded')),
        findsOneWidget,
      );

      transfers.value = [
        photo('queued', TransferLedgerStatus.published),
        photo('uploading', TransferLedgerStatus.published),
        photo('uploaded', TransferLedgerStatus.published),
        photo('failed', TransferLedgerStatus.failed),
      ];
      await tester.pump();
      expect(find.text('3 uploaded'), findsOneWidget);
      expect(find.text('0 uploading'), findsOneWidget);

      await tester.tap(find.text('View grid'));
      await tester.pump();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
