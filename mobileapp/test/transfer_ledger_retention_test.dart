import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await getIt.reset();
  });

  test(
    'history cap preserves pending shots and ambiguous registration state',
    () async {
      final pending = _item('waiting-photo', TransferLedgerStatus.queued, 1);
      final ambiguous = _item('uncertain-photo', TransferLedgerStatus.failed, 2)
          .copyWith(
            registrationStarted: true,
            imageUrl: 'https://images.invalid/uncertain.jpg',
            progress: 75,
            fileSize: 8000,
          );
      // Make both active records older than more than 2,000 completed photos.
      // Seeding the persisted store keeps the test focused on the prune boundary.
      final history = List.generate(
        2000,
        (index) =>
            _item('history-$index', TransferLedgerStatus.published, index + 3),
      );
      await getIt.reset();
      SharedPreferences.setMockInitialValues({
        'photo_transfer_ledger_v1': jsonEncode(
          [
            pending,
            ambiguous,
            ...history,
          ].map((item) => item.toJson()).toList(),
        ),
      });
      getIt.registerSingleton<SharedPreferences>(
        await SharedPreferences.getInstance(),
      );
      await TransferLedgerStorage.init();

      await TransferLedgerStorage.upsert(
        _item('latest-photo', TransferLedgerStatus.published, 5000),
      );
      await TransferLedgerStorage.init();

      expect(TransferLedgerStorage.items.value, hasLength(2002));
      expect(TransferLedgerStorage.find('history-0'), isNull);
      expect(TransferLedgerStorage.find(pending.id), isNotNull);
      final restored = TransferLedgerStorage.find(ambiguous.id)!;
      expect(restored.registrationStarted, isTrue);
      expect(restored.imageUrl, ambiguous.imageUrl);
      expect(restored.fileSize, 8000);
      expect(UploadQueueService.canCancel(restored), isFalse);
    },
  );
}

TransferLedgerItem _item(String id, TransferLedgerStatus status, int at) =>
    TransferLedgerItem(
      id: id,
      eventId: 'event-1',
      eventTitle: 'Long camera session',
      filename: '$id.jpg',
      source: 'otg-ptp',
      status: status,
      createdAt: at,
      updatedAt: at,
      localPath: '/camera/$id.jpg',
    );
