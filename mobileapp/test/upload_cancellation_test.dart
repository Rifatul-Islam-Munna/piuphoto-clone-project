import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final event = EventSummary(id: 'event-1', title: 'Camera session');
  late Directory directory;
  late File original;
  late _UploadAdapter adapter;

  setUp(() async {
    UploadQueueService.stop();
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await UploadQueueStorage.init();
    await TransferLedgerStorage.init();
    directory = await Directory.systemTemp.createTemp('camera-cancel-test-');
    original = File('${directory.path}/camera-original.jpg');
    await original.writeAsBytes([1, 2, 3, 4], flush: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => directory.path);
    dotenv.loadFromString(envString: 'API_URL=https://upload.invalid');
    DioHelper.init();
    DioHelper.dio.interceptors.clear();
    adapter = _UploadAdapter();
    DioHelper.dio.httpClientAdapter = adapter;
  });

  tearDown(() async {
    UploadQueueService.stop();
    // Transfer-status synchronization is independent of image networking.
    await Future<void>.delayed(Duration.zero);
    await TransferLedgerStorage.init();
    await UploadQueueStorage.init();
    DioHelper.dio.close(force: true);
    await adapter.waitForRequestBodies();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await getIt.reset();
    await directory.delete(recursive: true);
  });

  Future<PendingUploadItem> receive(
    String photo, {
    Duration delay = Duration.zero,
  }) async {
    await UploadQueueService.importFileLocalFirst(
      event: event,
      path: original.path,
      filename: '$photo.jpg',
      isEnhanced: false,
      source: 'otg-ptp',
      fingerprint: photo,
      uploadDelay: delay,
    );
    return UploadQueueStorage.findByFingerprint(photo)!;
  }

  for (final source in ['otg-ptp', 'wireless-ftp']) {
    test(
      '$source starts cloud upload immediately without holding camera acceptance for the server',
      () async {
        final uploadStarted = Completer<RequestOptions>();
        final uploadResponse = Completer<ResponseBody>();
        final registrationStarted = Completer<RequestOptions>();
        final registrationResponse = Completer<ResponseBody>();
        adapter.onUpload = (request) {
          uploadStarted.complete(request);
          return uploadResponse.future;
        };
        adapter.onEventImage = (request) {
          registrationStarted.complete(request);
          return registrationResponse.future;
        };
        UploadQueueService.start();
        try {
          // Completion must allow the camera to send its next photo even
          // though neither cloud response has been released by this server.
          final accepted = await UploadQueueService.receiveCameraFile(
            event: event,
            path: original.path,
            filename: 'instant-shot.jpg',
            isEnhanced: true,
            albumId: 'album-at-shutter-time',
            source: source,
            fingerprint: 'instant-$source',
          );
          expect(accepted.uploadAfter, isNull);
          expect(accepted.albumId, 'album-at-shutter-time');
          await uploadStarted.future.timeout(const Duration(seconds: 5));
          expect(uploadResponse.isCompleted, isFalse);
          expect(TransferLedgerStorage.find(accepted.id)!.isUploaded, isFalse);
          expect(
            UploadQueueService.canCancel(
              TransferLedgerStorage.find(accepted.id)!,
            ),
            isTrue,
          );

          uploadResponse.complete(
            _json({'url': 'https://images.invalid/instant.jpg'}),
          );
          final registration = await registrationStarted.future.timeout(
            const Duration(seconds: 5),
          );
          final details = _requestData(registration);
          expect(details['eventId'], event.id);
          expect(details['albumId'], 'album-at-shutter-time');
          expect(details['isEnhanced'], isTrue);
          expect(details['clientTransferId'], accepted.id);
          expect(details['imageUrl'], 'https://images.invalid/instant.jpg');
          final confirming = TransferLedgerStorage.find(accepted.id)!;
          expect(confirming.isUploaded, isFalse);
          expect(confirming.registrationStarted, isTrue);
          expect(UploadQueueService.canCancel(confirming), isFalse);
          expect(await File(accepted.localPath).exists(), isTrue);

          registrationResponse.complete(
            _json({
              'data': {'_id': 'confirmed-$source', 'isPublished': true},
            }),
          );
          await _waitForUploadState(
            () =>
                UploadQueueStorage.items.value.isEmpty &&
                !UploadQueueService.isProcessing.value,
          );
          expect(TransferLedgerStorage.find(accepted.id)!.isUploaded, isTrue);
          expect(await File(accepted.localPath).exists(), isFalse);
          expect(await original.readAsBytes(), [1, 2, 3, 4]);
          expect(adapter.imageUploads, hasLength(1));
          expect(adapter.eventImages, hasLength(1));
        } finally {
          if (!uploadResponse.isCompleted) {
            uploadResponse.complete(
              _json({'url': 'https://images.invalid/cleanup.jpg'}),
            );
          }
          if (!registrationResponse.isCompleted) {
            registrationResponse.complete(
              _json({
                'data': {'_id': 'cleanup', 'isPublished': true},
              }),
            );
          }
          await _waitForUploadState(
            () => !UploadQueueService.isProcessing.value,
          );
        }
      },
    );
  }

  test(
    'wireless photo bytes automatically reach cloud without a manual queue action',
    () async {
      UploadQueueService.start();
      final accepted = await UploadQueueService.receiveCameraBytes(
        event: event,
        bytes: Uint8List.fromList([5, 6, 7, 8]),
        filename: 'wireless-shot.jpg',
        isEnhanced: false,
        source: 'wireless-ptpip-sharedNetwork',
        fingerprint: 'wireless-shot',
      );
      expect(accepted.uploadAfter, isNull);
      await _waitForUploadState(
        () =>
            UploadQueueStorage.items.value.isEmpty &&
            !UploadQueueService.isProcessing.value,
      );
      expect(adapter.imageUploads, hasLength(1));
      expect(adapter.eventImages, hasLength(1));
      expect(TransferLedgerStorage.find(accepted.id)!.isUploaded, isTrue);
      expect(await File(accepted.localPath).exists(), isFalse);
    },
  );

  test(
    'shots arriving during an upload start automatically on the next pass',
    () async {
      final firstStarted = Completer<void>();
      final firstResponse = Completer<ResponseBody>();
      adapter.onUpload = (_) {
        if (!firstStarted.isCompleted) {
          firstStarted.complete();
          return firstResponse.future;
        }
        return Future.value(_json({'url': 'https://images.invalid/burst.jpg'}));
      };
      UploadQueueService.start();
      Future<PendingUploadItem> shot(int number) =>
          UploadQueueService.receiveCameraFile(
            event: event,
            path: original.path,
            filename: 'burst-$number.jpg',
            isEnhanced: false,
            source: 'otg-ptp',
            fingerprint: 'burst-$number',
          );
      try {
        final first = await shot(1);
        await firstStarted.future.timeout(const Duration(seconds: 5));
        final later = await Future.wait([shot(2), shot(3)]);
        expect(adapter.imageUploads, hasLength(1));
        expect(UploadQueueStorage.items.value, hasLength(3));
        firstResponse.complete(
          _json({'url': 'https://images.invalid/first.jpg'}),
        );
        await _waitForUploadState(
          () =>
              UploadQueueStorage.items.value.isEmpty &&
              !UploadQueueService.isProcessing.value,
        );
        expect(adapter.imageUploads, hasLength(3));
        expect(adapter.eventImages, hasLength(3));
        expect(
          adapter.eventImages
              .map((request) => _requestData(request)['clientTransferId'])
              .toSet(),
          {first.id, ...later.map((photo) => photo.id)},
        );
        for (final photo in [first, ...later]) {
          expect(TransferLedgerStorage.find(photo.id)!.isUploaded, isTrue);
        }
      } finally {
        if (!firstResponse.isCompleted) {
          firstResponse.complete(
            _json({'url': 'https://images.invalid/cleanup.jpg'}),
          );
        }
        await _waitForUploadState(() => !UploadQueueService.isProcessing.value);
      }
    },
  );

  test(
    'cloud connection failures persist and resume automatically at their retry deadline',
    () async {
      var reachable = false;
      adapter.onUpload = (request) async {
        if (!reachable) {
          throw DioException(
            requestOptions: request,
            type: DioExceptionType.connectionError,
            message: 'Cloud temporarily unreachable',
          );
        }
        return _json({'url': 'https://images.invalid/recovered.jpg'});
      };
      UploadQueueService.start();
      final accepted = await UploadQueueService.receiveCameraFile(
        event: event,
        path: original.path,
        filename: 'offline-shot.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'offline-shot',
      );
      await _waitForUploadState(
        () =>
            TransferLedgerStorage.find(accepted.id)?.status ==
                TransferLedgerStatus.failed &&
            !UploadQueueService.isProcessing.value,
      );
      final failed = TransferLedgerStorage.find(accepted.id)!;
      expect(failed.waitingForConnection, isTrue);
      expect(failed.isUploaded, isFalse);
      expect(adapter.eventImages, isEmpty);
      expect(await File(accepted.localPath).exists(), isTrue);

      // A retired request cannot replace Waiting for connection with Uploading.
      adapter.imageUploads.single.onSendProgress?.call(100, 100);
      await Future<void>.delayed(Duration.zero);
      await TransferLedgerStorage.init();
      expect(
        TransferLedgerStorage.find(accepted.id)!.status,
        TransferLedgerStatus.failed,
      );
      expect(
        TransferLedgerStorage.find(accepted.id)!.waitingForConnection,
        isTrue,
      );

      // Restart with a persisted, near-term deadline. No page callback, manual
      // processQueue call or Upload button is involved in the retry.
      UploadQueueService.stop();
      reachable = true;
      final retry = UploadQueueStorage.items.value.single;
      await UploadQueueStorage.update(
        retry.copyWith(
          nextRetryAt: DateTime.now().millisecondsSinceEpoch + 100,
        ),
      );
      UploadQueueService.start();
      await _waitForUploadState(
        () =>
            UploadQueueStorage.items.value.isEmpty &&
            !UploadQueueService.isProcessing.value,
      );
      final uploaded = TransferLedgerStorage.find(accepted.id)!;
      expect(uploaded.isUploaded, isTrue);
      expect(uploaded.waitingForConnection, isFalse);
      expect(adapter.imageUploads, hasLength(2));
      expect(adapter.eventImages, hasLength(1));
      expect(await File(accepted.localPath).exists(), isFalse);
    },
  );

  test(
    'a rejected cloud request is not misreported as a missing connection',
    () async {
      adapter.onUpload = (request) async => throw DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: request,
          statusCode: 400,
          data: {'message': 'Unsupported image format'},
        ),
      );
      UploadQueueService.start();
      final accepted = await UploadQueueService.receiveCameraFile(
        event: event,
        path: original.path,
        filename: 'rejected-shot.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'rejected-shot',
      );
      await _waitForUploadState(
        () =>
            TransferLedgerStorage.find(accepted.id)?.status ==
                TransferLedgerStatus.failed &&
            !UploadQueueService.isProcessing.value,
      );
      final failed = TransferLedgerStorage.find(accepted.id)!;
      expect(failed.waitingForConnection, isFalse);
      expect(failed.error, 'Unsupported image format');
      expect(failed.isUploaded, isFalse);
      expect(await File(accepted.localPath).exists(), isTrue);
    },
  );

  test(
    'a late camera receipt cannot restart automatic networking after the service stopped',
    () async {
      final accepted = await UploadQueueService.receiveCameraFile(
        event: event,
        path: original.path,
        filename: 'paused-service-shot.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'paused-service-shot',
      );
      await Future<void>.delayed(Duration.zero);
      expect(adapter.imageUploads, isEmpty);
      expect(TransferLedgerStorage.find(accepted.id)!.isUploaded, isFalse);

      UploadQueueService.start();
      await _waitForUploadState(
        () =>
            UploadQueueStorage.items.value.isEmpty &&
            !UploadQueueService.isProcessing.value,
      );
      expect(adapter.imageUploads, hasLength(1));
      expect(TransferLedgerStorage.find(accepted.id)!.isUploaded, isTrue);
    },
  );

  test(
    'malformed successful registration responses retain the buffer and retry the same cloud object',
    () async {
      final responses = <Map<String, dynamic>>[
        {},
        {'data': null},
        {
          'data': {'_id': ''},
        },
        {
          'data': {'_id': '  '},
        },
        {
          'data': {'_id': 42},
        },
        {
          'data': {'_id': <String, dynamic>{}},
        },
      ];
      for (var index = 0; index < responses.length; index++) {
        var confirmations = 0;
        adapter.onEventImage = (_) async {
          confirmations++;
          return confirmations == 1
              ? _json(responses[index])
              : _json({
                  'data': {'_id': 'confirmed-$index', 'isPublished': true},
                });
        };
        final uploadsBefore = adapter.imageUploads.length;
        final queued = await receive('incomplete-confirmation-$index');
        await UploadQueueService.processQueue();
        final pending = TransferLedgerStorage.find(queued.id)!;
        expect(pending.isUploaded, isFalse);
        expect(pending.registrationStarted, isTrue);
        expect(pending.imageUrl, isNotEmpty);
        expect(pending.status, TransferLedgerStatus.failed);
        expect(UploadQueueStorage.isCompleted(queued.id), isFalse);
        expect(await File(queued.localPath).exists(), isTrue);
        expect(UploadQueueService.canCancel(pending), isFalse);

        await UploadQueueService.retryNow(queued.id);
        final attempts = adapter.eventImages
            .where(
              (request) =>
                  _requestData(request)['clientTransferId'] == queued.id,
            )
            .map(_requestData)
            .toList();
        expect(attempts, hasLength(2));
        expect(attempts[1]['imageUrl'], attempts[0]['imageUrl']);
        expect(adapter.imageUploads.length, uploadsBefore + 1);
        expect(TransferLedgerStorage.find(queued.id)!.isUploaded, isTrue);
        expect(UploadQueueStorage.isCompleted(queued.id), isTrue);
        expect(UploadQueueStorage.items.value, isEmpty);
        expect(await File(queued.localPath).exists(), isFalse);
      }
    },
  );

  test(
    'review delay exposes preview and exact size before any cloud upload',
    () async {
      final before = DateTime.now().millisecondsSinceEpoch;
      final queued = await receive(
        'new-shot',
        delay: const Duration(seconds: 5),
      );
      final ledger = TransferLedgerStorage.find(queued.id)!;
      expect(ledger.fileSize, 4);
      expect(ledger.bytesTotal, 4);
      expect(await File(ledger.localPath!).readAsBytes(), [1, 2, 3, 4]);
      expect(queued.uploadAfter, greaterThanOrEqualTo(before + 5000));

      await UploadQueueService.processQueue();
      expect(adapter.imageUploads, isEmpty);
      expect(UploadQueueService.canCancel(ledger), isTrue);
      expect(
        await UploadQueueService.cancelUpload(queued.id),
        UploadCancellationResult.cancelled,
      );
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(
        TransferLedgerStorage.find(queued.id)!.status,
        TransferLedgerStatus.cancelled,
      );
      expect(await original.readAsBytes(), [1, 2, 3, 4]);
      // The saved preview remains available; the camera/source is never deleted.
      expect(await File(ledger.localPath!).exists(), isTrue);
    },
  );

  test(
    'cancelled camera resend stays cancelled after restart and ledger pruning',
    () async {
      final queued = await receive('repeated-shot');
      await UploadQueueService.cancelUpload(queued.id);
      await TransferLedgerStorage.clearEvent(event.id);
      await UploadQueueStorage.init();
      await TransferLedgerStorage.init();
      expect(TransferLedgerStorage.find(queued.id), isNull);
      expect(UploadQueueStorage.isCancelled(queued.id), isTrue);

      await UploadQueueService.importFileLocalFirst(
        event: event,
        path: original.path,
        filename: 'repeated-shot.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'repeated-shot',
        tryUploadNow: true,
      );
      // The byte-based wireless path must honor the same persisted decision too.
      await UploadQueueService.importBytesLocalFirst(
        event: event,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        filename: 'repeated-shot.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'repeated-shot',
        tryUploadNow: true,
      );
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(adapter.imageUploads, isEmpty);
    },
  );

  test(
    'confirmed camera receipt survives history pruning and restart without another cloud upload',
    () async {
      final queued = await receive('confirmed-old-photo');
      await UploadQueueService.processQueue();
      expect(UploadQueueStorage.isCompleted(queued.id), isTrue);
      expect(await File(queued.localPath).exists(), isFalse);

      await TransferLedgerStorage.clearEvent(event.id);
      await UploadQueueStorage.init();
      await TransferLedgerStorage.init();
      expect(TransferLedgerStorage.find(queued.id), isNull);
      expect(UploadQueueStorage.isCompleted(queued.id), isTrue);

      final accepted = await UploadQueueService.receiveCameraFile(
        event: event,
        path: original.path,
        filename: 'confirmed-old-photo.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'confirmed-old-photo',
      );
      final alreadyUploaded = await UploadQueueService.importBytesLocalFirst(
        event: event,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        filename: 'confirmed-old-photo.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'confirmed-old-photo',
        tryUploadNow: true,
      );
      expect(accepted.id, queued.id);
      expect(alreadyUploaded, isTrue);
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(adapter.imageUploads, hasLength(1));
      expect(adapter.eventImages, hasLength(1));
      expect(
        await UploadQueueService.cancelUpload(queued.id),
        UploadCancellationResult.alreadyCompleted,
      );
      expect(await original.readAsBytes(), [1, 2, 3, 4]);
    },
  );

  test(
    'completed receipts remain scoped to their original event and camera source',
    () async {
      final first = await receive('same-camera-object');
      await UploadQueueService.processQueue();
      await TransferLedgerStorage.clearEvent(event.id);
      await UploadQueueStorage.init();
      await TransferLedgerStorage.init();

      final otherEvent = await UploadQueueService.receiveCameraFile(
        event: EventSummary(id: 'other-event', title: 'Another event'),
        path: original.path,
        filename: 'same-camera-object.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'same-camera-object',
      );
      final otherSource = await UploadQueueService.receiveCameraBytes(
        event: event,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        filename: 'same-camera-object.jpg',
        isEnhanced: false,
        source: 'wireless-ftp',
        fingerprint: 'same-camera-object',
      );
      expect({first.id, otherEvent.id, otherSource.id}, hasLength(3));
      expect(UploadQueueStorage.items.value, hasLength(2));
      await UploadQueueService.processQueue();
      expect(adapter.imageUploads, hasLength(3));
      expect(adapter.eventImages, hasLength(3));
      expect(UploadQueueStorage.items.value, isEmpty);
    },
  );

  test(
    'failed receipt persistence preserves the buffer and retries registration with the same cloud object',
    () async {
      final preferences = _ReceiptFailurePreferences(
        getIt<SharedPreferences>(),
      );
      await getIt.unregister<SharedPreferences>();
      getIt.registerSingleton<SharedPreferences>(preferences);
      final queued = await receive('receipt-write-failure');
      await UploadQueueService.processQueue();
      final pending = TransferLedgerStorage.find(queued.id)!;
      expect(UploadQueueStorage.isCompleted(queued.id), isFalse);
      expect(pending.isUploaded, isFalse);
      expect(pending.registrationStarted, isTrue);
      expect(pending.imageUrl, isNotEmpty);
      expect(await File(queued.localPath).exists(), isTrue);
      expect(UploadQueueService.canCancel(pending), isFalse);
      expect(adapter.imageUploads, hasLength(1));
      expect(adapter.eventImages, hasLength(1));

      preferences.failReceipt = false;
      await UploadQueueService.retryNow(queued.id);
      expect(UploadQueueStorage.isCompleted(queued.id), isTrue);
      expect(TransferLedgerStorage.find(queued.id)!.isUploaded, isTrue);
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(await File(queued.localPath).exists(), isFalse);
      expect(adapter.imageUploads, hasLength(1));
      expect(adapter.eventImages, hasLength(2));
      expect(
        _requestData(adapter.eventImages.last)['imageUrl'],
        _requestData(adapter.eventImages.first)['imageUrl'],
      );
      await UploadQueueStorage.init();
      expect(UploadQueueStorage.isCompleted(queued.id), isTrue);
    },
  );

  test(
    'restart after receipt persistence finishes local cleanup without another network request',
    () async {
      final queued = await receive('confirmed-before-crash');
      await TransferLedgerStorage.updateStatus(
        queued.id,
        TransferLedgerStatus.processing,
        progress: 75,
        registrationStarted: true,
        imageUrl: 'https://images.invalid/confirmed-before-crash.jpg',
      );
      // Simulate a successful cloud confirmation followed by process exit
      // before its final display status, file deletion and queue-row removal.
      await UploadQueueStorage.markCompleted([queued.id]);
      await UploadQueueStorage.init();
      await TransferLedgerStorage.init();
      expect(UploadQueueStorage.items.value, hasLength(1));
      expect(await File(queued.localPath).exists(), isTrue);
      expect(
        UploadQueueService.canCancel(TransferLedgerStorage.find(queued.id)!),
        isFalse,
      );

      await UploadQueueService.processQueue();
      expect(TransferLedgerStorage.find(queued.id)!.isUploaded, isTrue);
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(await File(queued.localPath).exists(), isFalse);
      expect(adapter.imageUploads, isEmpty);
      expect(adapter.eventImages, isEmpty);
    },
  );

  test(
    'successful history from earlier builds gains durable receipts before it is cleared',
    () async {
      final queued = await receive('legacy-confirmed-photo');
      await TransferLedgerStorage.updateStatus(
        queued.id,
        TransferLedgerStatus.published,
        progress: 100,
        registrationStarted: true,
        imageUrl: 'https://images.invalid/legacy.jpg',
      );
      await UploadQueueStorage.remove(queued.id);
      expect(UploadQueueStorage.isCompleted(queued.id), isFalse);

      UploadQueueService.start();
      // Storage init waits for the history migration's queued write.
      await UploadQueueStorage.init();
      UploadQueueService.stop();
      expect(UploadQueueStorage.isCompleted(queued.id), isTrue);
      await TransferLedgerStorage.clearEvent(event.id);
      await UploadQueueStorage.init();
      await TransferLedgerStorage.init();
      await UploadQueueService.receiveCameraFile(
        event: event,
        path: original.path,
        filename: 'legacy-confirmed-photo.jpg',
        isEnhanced: false,
        source: 'otg-ptp',
        fingerprint: 'legacy-confirmed-photo',
      );
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(adapter.imageUploads, isEmpty);
      expect(adapter.eventImages, isEmpty);
    },
  );

  test(
    'X cancels active networking and late progress cannot requeue the photo',
    () async {
      final started = Completer<RequestOptions>();
      final response = Completer<ResponseBody>();
      adapter.onUpload = (options) {
        started.complete(options);
        return response.future;
      };
      final queued = await receive('active-shot');
      final processing = UploadQueueService.processQueue();
      final request = await started.future;
      expect(request.cancelToken, isNotNull);

      expect(
        await UploadQueueService.cancelUpload(queued.id),
        UploadCancellationResult.cancelled,
      );
      expect(request.cancelToken!.isCancelled, isTrue);
      await processing;
      // A slow transport can still emit a final callback after cancellation.
      request.onSendProgress?.call(100, 100);
      response.complete(_json({'url': 'https://images.invalid/late.jpg'}));
      await Future<void>.delayed(Duration.zero);
      await UploadQueueService.retryNow(queued.id);

      expect(adapter.eventImages, isEmpty);
      expect(adapter.imageUploads, hasLength(1));
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(
        TransferLedgerStorage.find(queued.id)!.status,
        TransferLedgerStatus.cancelled,
      );
      expect(await original.exists(), isTrue);
    },
  );

  test(
    'cancelling a later photo invalidates the current queue snapshot',
    () async {
      final started = Completer<void>();
      final response = Completer<ResponseBody>();
      adapter.onUpload = (_) {
        if (!started.isCompleted) started.complete();
        return response.future;
      };
      final first = await receive('first-shot');
      final second = await receive('second-shot');
      final processing = UploadQueueService.processQueue();
      await started.future;
      await UploadQueueService.cancelUpload(second.id);
      response.complete(_json({'url': 'https://images.invalid/first.jpg'}));
      await processing;

      expect(adapter.imageUploads, hasLength(1));
      expect(adapter.eventImages, hasLength(1));
      expect(TransferLedgerStorage.find(first.id)!.isUploaded, isTrue);
      expect(
        TransferLedgerStorage.find(second.id)!.status,
        TransferLedgerStatus.cancelled,
      );
      expect(UploadQueueStorage.items.value, isEmpty);
    },
  );

  test(
    'registration boundary never reports an already-committing photo cancelled',
    () async {
      final started = Completer<void>();
      final response = Completer<ResponseBody>();
      adapter.onEventImage = (_) {
        started.complete();
        return response.future;
      };
      final queued = await receive('committing-shot');
      final processing = UploadQueueService.processQueue();
      await started.future;

      final ledger = TransferLedgerStorage.find(queued.id)!;
      expect(ledger.registrationStarted, isTrue);
      expect(ledger.isUploaded, isFalse);
      expect(UploadQueueService.canCancel(ledger), isFalse);
      expect(
        await UploadQueueService.cancelUpload(queued.id),
        UploadCancellationResult.finishing,
      );
      response.complete(
        _json({
          'data': {'_id': 'photo-id', 'isPublished': true},
        }),
      );
      await processing;
      expect(
        await UploadQueueService.cancelUpload(queued.id),
        UploadCancellationResult.alreadyCompleted,
      );
      expect(UploadQueueStorage.isCancelled(queued.id), isFalse);
    },
  );

  test(
    'lost registration response retries its URL and id without another upload',
    () async {
      var registrations = 0;
      adapter.onEventImage = (options) async {
        registrations++;
        if (registrations == 1) {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            message: 'Response lost after request reached server',
          );
        }
        return _json({
          'data': {'_id': 'same-photo', 'isPublished': true},
        });
      };
      final queued = await receive('uncertain-shot');
      await UploadQueueService.processQueue();
      final uncertain = TransferLedgerStorage.find(queued.id)!;
      expect(uncertain.status, TransferLedgerStatus.failed);
      expect(uncertain.registrationStarted, isTrue);
      expect(UploadQueueService.canCancel(uncertain), isFalse);
      expect(
        await UploadQueueService.cancelUpload(queued.id),
        UploadCancellationResult.finishing,
      );

      // Even if a local preview has been lost, the already-uploaded blob can be
      // registered idempotently without requiring a second upload from camera.
      await File(queued.localPath).delete();
      await UploadQueueService.retryNow(queued.id);
      expect(adapter.imageUploads, hasLength(1));
      expect(adapter.eventImages, hasLength(2));
      final first = _requestData(adapter.eventImages.first);
      final retry = _requestData(adapter.eventImages.last);
      expect(retry['clientTransferId'], first['clientTransferId']);
      expect(retry['imageUrl'], first['imageUrl']);
      expect(TransferLedgerStorage.find(queued.id)!.isUploaded, isTrue);
      expect(UploadQueueStorage.items.value, isEmpty);
    },
  );

  test(
    'terminal ledger status survives stale progress and server metadata',
    () async {
      final queued = await receive('status-race-shot');
      final originalLedger = TransferLedgerStorage.find(queued.id)!;
      await UploadQueueService.cancelUpload(queued.id);
      await TransferLedgerStorage.updateStatus(
        queued.id,
        TransferLedgerStatus.uploading,
        progress: 70,
      );
      await TransferLedgerStorage.upsert(
        originalLedger.copyWith(status: TransferLedgerStatus.queued),
      );
      await TransferLedgerStorage.init();
      expect(
        TransferLedgerStorage.find(queued.id)!.status,
        TransferLedgerStatus.cancelled,
      );
      expect(TransferLedgerStorage.find(queued.id)!.fileSize, 4);
    },
  );
}

Future<void> _waitForUploadState(bool Function() ready) async {
  final completed = Completer<void>();
  final signals = [
    UploadQueueStorage.items,
    TransferLedgerStorage.items,
    UploadQueueService.isProcessing,
  ];
  void check() {
    if (!completed.isCompleted && ready()) completed.complete();
  }

  for (final signal in signals) {
    signal.addListener(check);
  }
  try {
    check();
    await completed.future.timeout(const Duration(seconds: 10));
  } finally {
    for (final signal in signals) {
      signal.removeListener(check);
    }
  }
}

Map<String, dynamic> _requestData(RequestOptions options) {
  final data = options.data;
  return data is String
      ? Map<String, dynamic>.from(jsonDecode(data) as Map)
      : Map<String, dynamic>.from(data as Map);
}

ResponseBody _json(Map<String, dynamic> data) => ResponseBody.fromString(
  jsonEncode(data),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _ReceiptFailurePreferences implements SharedPreferences {
  _ReceiptFailurePreferences(this.delegate);

  final SharedPreferences delegate;
  bool failReceipt = true;

  @override
  String? getString(String key) => delegate.getString(key);

  @override
  List<String>? getStringList(String key) => delegate.getStringList(key);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      delegate.setStringList(key, value);

  @override
  Future<bool> setString(String key, String value) async {
    if (failReceipt && key == 'completed_upload_ids_v1') return false;
    return delegate.setString(key, value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected preferences call: ${invocation.memberName}',
  );
}

class _UploadAdapter implements HttpClientAdapter {
  final List<RequestOptions> imageUploads = [];
  final List<RequestOptions> eventImages = [];
  final List<Future<void>> _requestBodies = [];
  Future<ResponseBody> Function(RequestOptions)? onUpload;
  Future<ResponseBody> Function(RequestOptions)? onEventImage;

  Future<void> waitForRequestBodies() async {
    await Future.wait(_requestBodies);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      // Dio finalizes multipart data with an asynchronous file producer. A
      // fake server must consume that body before returning or holding its
      // response, just as a real server receiving the upload would. Otherwise
      // cancellation can finish while the ignored file reader is still open.
      final body = requestStream.drain<void>();
      _requestBodies.add(body);
      await body;
    }
    Future<ResponseBody> response;
    if (options.path == '/image/upload') {
      imageUploads.add(options);
      response =
          onUpload?.call(options) ??
          Future.value(_json({'url': 'https://images.invalid/photo.jpg'}));
    } else if (options.path == '/eventImage') {
      eventImages.add(options);
      response =
          onEventImage?.call(options) ??
          Future.value(
            _json({
              'data': {'_id': 'photo', 'isPublished': true},
            }),
          );
    } else {
      response = Future.value(_json({}));
    }
    return Future.any([
      response,
      if (cancelFuture != null)
        cancelFuture.then<ResponseBody>(
          (_) => throw DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
          ),
        ),
    ]);
  }

  @override
  void close({bool force = false}) {}
}
