import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
    TransferLedgerStorage.items.value = const [];
  });

  tearDown(() async {
    TransferLedgerStorage.items.value = const [];
    await getIt.reset();
  });

  test('transfer ledger serializes upload state', () {
    final item = TransferLedgerItem(
      id: 'capture-1',
      eventId: 'event-1',
      eventTitle: 'Wedding',
      filename: 'IMG_0001.JPG',
      source: 'otg-ptp',
      cameraId: 'Canon EOS R6',
      status: TransferLedgerStatus.delivered,
      createdAt: 10,
      updatedAt: 20,
      progress: 100,
      bytesSent: 10 * 1024 * 1024,
      bytesTotal: 10 * 1024 * 1024,
      bytesPerSecond: 2.5 * 1024 * 1024,
    );
    final restored = TransferLedgerItem.fromJson(item.toJson());
    expect(restored.id, item.id);
    expect(restored.cameraId, 'Canon EOS R6');
    expect(restored.status, TransferLedgerStatus.delivered);
    expect(restored.isUploaded, isTrue);
    expect(restored.isPending, isFalse);
    expect(restored.progress, 100);
    expect(restored.bytesTotal, 10 * 1024 * 1024);
    expect(restored.bytesPerSecond, greaterThan(2 * 1024 * 1024));
  });

  test('transfer ledger persists successful history', () async {
    final item = TransferLedgerItem(
      id: 'capture-2',
      eventId: 'event-2',
      eventTitle: 'Sports Day',
      filename: 'DSC_2001.JPG',
      source: 'wireless-ptp',
      status: TransferLedgerStatus.delivered,
      createdAt: 100,
      updatedAt: 200,
      progress: 100,
    );

    await TransferLedgerStorage.upsert(item);
    expect(TransferLedgerStorage.find('capture-2')?.isUploaded, isTrue);

    TransferLedgerStorage.items.value = const [];
    await TransferLedgerStorage.init();

    expect(TransferLedgerStorage.find('capture-2')?.filename, 'DSC_2001.JPG');
    expect(
      TransferLedgerStorage.find('capture-2')?.status,
      TransferLedgerStatus.delivered,
    );
  });
}
