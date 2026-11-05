import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late File cameraDownload;
  late File queuedCopy;
  final event = EventSummary(id: 'event-1', title: 'Live shoot');
  const fingerprint = 'event-1|camera-1|photo-1';

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await UploadQueueStorage.init();
    TransferLedgerStorage.items.value = const [];
    directory = await Directory.systemTemp.createTemp(
      'live-capture-queue-test-',
    );
    cameraDownload = File('${directory.path}/camera-download.jpg');
    queuedCopy = File('${directory.path}/queued-copy.jpg');
    await cameraDownload.writeAsBytes([1, 2, 3], flush: true);
    await UploadQueueStorage.add(
      PendingUploadItem(
        id: 'queued-photo',
        eventId: event.id,
        eventTitle: event.title,
        localPath: queuedCopy.path,
        filename: 'photo.jpg',
        source: 'usb',
        isEnhanced: false,
        createdAt: 1,
        fingerprint: fingerprint,
      ),
    );
  });

  tearDown(() async {
    TransferLedgerStorage.items.value = const [];
    await getIt.reset();
    await directory.delete(recursive: true);
  });

  Future<bool> importAgain() => UploadQueueService.importFileLocalFirst(
    event: event,
    path: cameraDownload.path,
    filename: 'photo.jpg',
    isEnhanced: false,
    source: 'usb',
    fingerprint: fingerprint,
    tryUploadNow: false,
  );

  test(
    'missing queued duplicate rejects acceptance and retains camera download',
    () async {
      await expectLater(
        importAgain(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('missing or empty'),
          ),
        ),
      );

      expect(await cameraDownload.readAsBytes(), [1, 2, 3]);
      expect(UploadQueueStorage.items.value, hasLength(1));
    },
  );

  test('empty queued duplicate also rejects acceptance', () async {
    await queuedCopy.writeAsBytes([], flush: true);

    await expectLater(
      importAgain(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('missing or empty'),
        ),
      ),
    );

    expect(await cameraDownload.readAsBytes(), [1, 2, 3]);
    expect(UploadQueueStorage.items.value, hasLength(1));
  });

  test(
    'valid queued duplicate resolves without adding another upload',
    () async {
      await queuedCopy.writeAsBytes([1, 2, 3], flush: true);

      // false describes cloud-upload state; successful completion is the local
      // acceptance signal that allows the native camera capture to be ACKed.
      expect(await importAgain(), isFalse);
      expect(UploadQueueStorage.items.value, hasLength(1));
      expect(await queuedCopy.readAsBytes(), [1, 2, 3]);
    },
  );

  test(
    'overlapping duplicate saves share failure and a later retry can recover',
    () async {
      Future<Object?> captureError(Future<bool> operation) async {
        try {
          await operation;
          return null;
        } catch (error) {
          return error;
        }
      }

      final errors = await Future.wait([
        captureError(importAgain()),
        captureError(importAgain()),
      ]);
      expect(errors.first, isA<Exception>());
      expect(identical(errors.first, errors.last), isTrue);

      // The failed operation must be evicted from the in-flight map; otherwise
      // this repaired, durable copy would keep returning the previous failure.
      await queuedCopy.writeAsBytes([1, 2, 3], flush: true);
      expect(await importAgain(), isFalse);
      expect(UploadQueueStorage.items.value, hasLength(1));
    },
  );

  test(
    'a blob uploaded before event registration is not a completed transfer',
    () async {
      await TransferLedgerStorage.upsert(
        TransferLedgerItem(
          id: 'queued-photo',
          eventId: event.id,
          eventTitle: event.title,
          filename: 'photo.jpg',
          source: 'usb',
          status: TransferLedgerStatus.processing,
          createdAt: 1,
          updatedAt: 2,
          localPath: queuedCopy.path,
          imageUrl: 'https://example.invalid/photo.jpg',
          progress: 75,
        ),
      );

      await expectLater(
        importAgain(),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('missing or empty'),
          ),
        ),
      );

      // Processing at 100 means the event-image API accepted the photo and
      // server-side processing remains. Local cleanup is safe at this point.
      await TransferLedgerStorage.updateStatus(
        'queued-photo',
        TransferLedgerStatus.processing,
        progress: 100,
      );
      expect(await importAgain(), isFalse);
    },
  );

  test(
    'already uploaded duplicate can be accepted after local cleanup',
    () async {
      await TransferLedgerStorage.upsert(
        TransferLedgerItem(
          id: 'queued-photo',
          eventId: event.id,
          eventTitle: event.title,
          filename: 'photo.jpg',
          source: 'usb',
          status: TransferLedgerStatus.published,
          createdAt: 1,
          updatedAt: 2,
          localPath: queuedCopy.path,
          imageUrl: 'https://example.invalid/photo.jpg',
          progress: 100,
        ),
      );
      expect(await queuedCopy.exists(), isFalse);

      expect(await importAgain(), isFalse);
      expect(UploadQueueStorage.items.value, hasLength(1));
      expect(await cameraDownload.readAsBytes(), [1, 2, 3]);
    },
  );
}
