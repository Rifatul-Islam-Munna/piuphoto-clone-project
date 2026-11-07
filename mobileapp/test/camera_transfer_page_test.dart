import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/pages/upload/camera_transfer_page.dart';

void main() {
  testWidgets('shows the current session photo, preview and exact file size', (
    tester,
  ) async {
    final harness = _Harness([
      _photo('current', createdAt: 1000, fileSize: 2 * 1024 * 1024),
      _photo('previous', createdAt: 999),
      _photo('other-event', eventId: 'other', createdAt: 2000),
    ]);
    await _show(tester, harness);

    expect(find.text('current.JPG'), findsOneWidget);
    expect(find.text('previous.JPG'), findsNothing);
    expect(find.text('other-event.JPG'), findsNothing);
    expect(find.text('2.0 MB'), findsOneWidget);
    expect(find.text('1 received'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Preview of current.JPG',
      ),
      findsOneWidget,
    );
    expect(find.byTooltip('Cancel upload of current.JPG'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('X awaits real cancellation for the selected photo', (
    tester,
  ) async {
    final photo = _photo('shot');
    final harness = _Harness([photo]);
    final cancellation = Completer<UploadCancellationResult>();
    final requested = <String>[];
    await _show(
      tester,
      harness,
      cancelUpload: (id) {
        requested.add(id);
        return cancellation.future;
      },
    );

    await tester.tap(find.byKey(const ValueKey('cancel-shot')));
    await tester.pump();

    expect(requested, ['shot']);
    expect(find.text('Cancelling upload…'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-shot')), findsNothing);
    expect(harness.transfers.value.single.status, TransferLedgerStatus.queued);

    harness.transfers.value = [
      photo.copyWith(status: TransferLedgerStatus.cancelled),
    ];
    cancellation.complete(UploadCancellationResult.cancelled);
    await tester.pumpAndSettle();

    expect(find.text('Upload cancelled'), findsOneWidget);
    expect(find.text('Upload cancelled for shot.JPG.'), findsOneWidget);
    expect(find.text('1 cancelled'), findsOneWidget);
    expect(find.byKey(const ValueKey('cancel-shot')), findsNothing);
  });

  testWidgets('guest QR stays available while camera photos upload', (
    tester,
  ) async {
    final harness = _Harness([
      _photo(
        'shooting',
      ).copyWith(status: TransferLedgerStatus.uploading, progress: 40),
    ]);
    var qrRequests = 0;
    var stops = 0;
    await _show(
      tester,
      harness,
      onShareGuestQr: () => qrRequests++,
      onStop: () async => stops++,
    );

    expect(find.text('shooting.JPG'), findsOneWidget);
    expect(find.text('Uploading to cloud'), findsOneWidget);
    final menu = tester.widget<PopupMenuButton<String>>(
      find.byWidgetPredicate((widget) => widget is PopupMenuButton<String>),
    );
    menu.onSelected?.call('qr');
    await tester.pump();
    expect(qrRequests, 1);
    expect(stops, 0);
    expect(harness.session.value.isActive, isTrue);
    expect(
      harness.transfers.value.single.status,
      TransferLedgerStatus.uploading,
    );
    expect(find.byTooltip('Cancel upload of shooting.JPG'), findsOneWidget);
  });

  testWidgets(
    'reports an upload that passed its cancellation boundary honestly',
    (tester) async {
      final harness = _Harness([_photo('shot')]);
      await _show(
        tester,
        harness,
        cancelUpload: (_) async => UploadCancellationResult.finishing,
      );

      await tester.tap(find.byKey(const ValueKey('cancel-shot')));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'shot.JPG is finishing its upload and can no longer be cancelled.',
        ),
        findsOneWidget,
      );
      expect(find.text('Upload cancelled'), findsNothing);
      expect(
        harness.transfers.value.single.status,
        TransferLedgerStatus.queued,
      );
    },
  );

  testWidgets(
    'preserves a previously scheduled review deadline separately from cloud completion',
    (tester) async {
      final harness = _Harness([_photo('shot')]);
      harness.queue.value = [
        _queued(
          'shot',
          uploadAfter: DateTime.now().millisecondsSinceEpoch + 5000,
        ),
      ];
      await _show(tester, harness);

      expect(
        find.textContaining(RegExp(r'Uploads in [1-5] s')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('cancel-shot')), findsOneWidget);

      harness.queue.value = [
        _queued('shot', uploadAfter: DateTime.now().millisecondsSinceEpoch - 1),
      ];
      await tester.pump();
      expect(find.text('Waiting for cloud upload'), findsOneWidget);

      harness.transfers.value = [
        _photo(
          'shot',
        ).copyWith(status: TransferLedgerStatus.published, progress: 100),
      ];
      harness.queue.value = [];
      await tester.pumpAndSettle();
      expect(find.text('Uploaded to cloud'), findsOneWidget);
      expect(find.text('1 uploaded'), findsOneWidget);
      expect(find.byKey(const ValueKey('cancel-shot')), findsNothing);
    },
  );

  testWidgets(
    'immediate camera uploads show cloud progress without a review countdown',
    (tester) async {
      final photo = _photo('shot');
      final harness = _Harness([photo]);
      harness.queue.value = [_queued('shot', uploadAfter: 0)];
      await _show(tester, harness);
      expect(find.text('Waiting for cloud upload'), findsOneWidget);
      expect(find.textContaining('Uploads in'), findsNothing);

      harness.transfers.value = [
        photo.copyWith(
          status: TransferLedgerStatus.uploading,
          progress: 70,
          bytesSent: 100,
          bytesTotal: 100,
        ),
      ];
      await tester.pump();
      expect(find.text('Uploading to cloud'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.text('Uploaded to cloud'), findsNothing);
      expect(find.text('0 uploaded'), findsOneWidget);
      expect(find.byKey(const ValueKey('cancel-shot')), findsOneWidget);

      harness.transfers.value = [
        photo.copyWith(
          status: TransferLedgerStatus.processing,
          progress: 75,
          registrationStarted: true,
        ),
      ];
      await tester.pump();
      expect(find.text('Finishing cloud upload'), findsOneWidget);
      expect(find.text('Uploaded to cloud'), findsNothing);
      expect(find.byKey(const ValueKey('cancel-shot')), findsNothing);

      harness.transfers.value = [
        photo.copyWith(
          status: TransferLedgerStatus.published,
          progress: 100,
          registrationStarted: true,
        ),
      ];
      harness.queue.value = [];
      await tester.pumpAndSettle();
      expect(find.text('Uploaded to cloud'), findsOneWidget);
      expect(find.text('1 uploaded'), findsOneWidget);
    },
  );

  testWidgets(
    'connection retry is distinguished from a rejected cloud upload',
    (tester) async {
      final photo = _photo('shot').copyWith(
        status: TransferLedgerStatus.failed,
        waitingForConnection: true,
        error: 'Network connection unavailable',
      );
      final harness = _Harness([photo]);
      harness.queue.value = [
        _queued(
          'shot',
          uploadAfter: 0,
        ).copyWith(nextRetryAt: DateTime.now().millisecondsSinceEpoch + 60000),
      ];
      await _show(tester, harness);
      expect(find.text('Waiting for cloud connection'), findsOneWidget);
      expect(find.text('Uploaded to cloud'), findsNothing);
      expect(find.byKey(const ValueKey('cancel-shot')), findsOneWidget);

      harness.transfers.value = [
        photo.copyWith(
          waitingForConnection: false,
          error: 'Unsupported image format',
        ),
      ];
      await tester.pump();
      expect(find.text('Cloud upload paused'), findsOneWidget);
      expect(find.text('Waiting for cloud connection'), findsNothing);
      expect(find.text('Unsupported image format'), findsOneWidget);
    },
  );

  testWidgets(
    'uncertain cloud registration never offers cancellation or claims success',
    (tester) async {
      final harness = _Harness([
        _photo('shot').copyWith(
          status: TransferLedgerStatus.failed,
          registrationStarted: true,
          progress: 75,
          error: 'Cloud upload confirmation is incomplete.',
        ),
      ]);
      harness.queue.value = [
        _queued(
          'shot',
          uploadAfter: 0,
        ).copyWith(nextRetryAt: DateTime.now().millisecondsSinceEpoch + 60000),
      ];
      await _show(tester, harness);
      expect(find.text('Waiting for cloud confirmation'), findsOneWidget);
      expect(find.text('Uploaded to cloud'), findsNothing);
      expect(find.byKey(const ValueKey('cancel-shot')), findsNothing);
      expect(find.textContaining('You can still cancel'), findsNothing);
      expect(
        find.text(
          'Cloud confirmation is pending. AirPix will retry automatically.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('connection details stay compact behind the top menu', (
    tester,
  ) async {
    final harness = _Harness([]);
    var stopCalls = 0;
    await _show(
      tester,
      harness,
      connectionDetailsBuilder: (_) => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('FTP server: 192.168.1.10:2121'),
        ),
      ),
      onStop: () async {
        stopCalls++;
        harness.session.value = const CameraTransferSessionStatus(
          connectionLabel: 'Camera disconnected',
          message:
              'Receiving has stopped. Queued photos will continue uploading.',
          isActive: false,
        );
      },
    );

    expect(find.text('FTP server: 192.168.1.10:2121'), findsNothing);
    expect(find.text('Waiting for camera photos'), findsOneWidget);
    expect(find.text('Stop receiving'), findsOneWidget);

    await tester.tap(find.byTooltip('More camera transfer actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Connection details'));
    await tester.pumpAndSettle();
    expect(find.text('FTP server: 192.168.1.10:2121'), findsOneWidget);

    Navigator.of(
      tester.element(find.text('FTP server: 192.168.1.10:2121')),
    ).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop receiving'));
    await tester.pumpAndSettle();

    expect(stopCalls, 1);
    expect(find.text('Receiving stopped'), findsOneWidget);
    expect(find.text('Stop receiving'), findsNothing);
    expect(find.text('No photos received yet'), findsOneWidget);
  });

  testWidgets(
    'displays failed USB session guidance when no photos were received',
    (tester) async {
      final harness = _Harness([]);
      harness.session.value = const CameraTransferSessionStatus(
        connectionLabel: 'Sony Alpha 7 IV',
        message:
            'USB Mass Storage is for file transfer. Unplug USB, choose Remote '
            'Shooting and Dest.+Camera, then reconnect for New shots only.',
        isActive: false,
      );
      await _show(tester, harness);
      expect(find.text('Receiving stopped'), findsOneWidget);
      expect(find.text('No photos received yet'), findsOneWidget);
      expect(
        find.textContaining('USB Mass Storage is for file transfer'),
        findsOneWidget,
      );
      expect(find.textContaining('Dest.+Camera'), findsOneWidget);
    },
  );

  testWidgets(
    'all camera brands can open mode guidance from an empty live session',
    (tester) async {
      final harness = _Harness([]);
      var helpRequests = 0;
      await _show(tester, harness, onCameraSetupHelp: () => helpRequests++);
      expect(find.text('Connection prepared — test shutter'), findsOneWidget);
      await tester.tap(find.text('Camera screen black? Stop and fix USB mode'));
      await tester.pump();
      expect(helpRequests, 1);
      expect(harness.session.value.isActive, isTrue);
      expect(find.text('No photos received yet'), findsNothing);
    },
  );

  testWidgets('leaving the page keeps the parent camera session running', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final harness = _Harness([]);
    var stopCalls = 0;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => harness.page(
                    onStop: () async {
                      stopCalls++;
                    },
                  ),
                ),
              ),
              child: const Text('Open transfers'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open transfers'));
    await tester.pumpAndSettle();
    expect(find.text('Camera transfers'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Open transfers'), findsOneWidget);
    expect(stopCalls, 0);
    expect(harness.session.value.isActive, isTrue);
  });
}

Future<void> _show(
  WidgetTester tester,
  _Harness harness, {
  Future<UploadCancellationResult> Function(String)? cancelUpload,
  Future<void> Function()? onStop,
  VoidCallback? onShareGuestQr,
  VoidCallback? onCameraSetupHelp,
  WidgetBuilder? connectionDetailsBuilder,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
    await tester.binding.setSurfaceSize(null);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: harness.page(
        cancelUpload: cancelUpload,
        onStop: onStop,
        onShareGuestQr: onShareGuestQr,
        onCameraSetupHelp: onCameraSetupHelp,
        connectionDetailsBuilder: connectionDetailsBuilder,
      ),
    ),
  );
  await tester.pump();
}

class _Harness {
  _Harness(List<TransferLedgerItem> items)
    : transfers = ValueNotifier<List<TransferLedgerItem>>(items);

  final ValueNotifier<List<TransferLedgerItem>> transfers;
  final queue = ValueNotifier<List<PendingUploadItem>>([]);
  final session = ValueNotifier<CameraTransferSessionStatus>(
    const CameraTransferSessionStatus(
      connectionLabel: 'Camera connected',
      message: 'Waiting for the next photo.',
      isActive: true,
    ),
  );

  CameraTransferPage page({
    Future<UploadCancellationResult> Function(String)? cancelUpload,
    Future<void> Function()? onStop,
    VoidCallback? onShareGuestQr,
    VoidCallback? onCameraSetupHelp,
    WidgetBuilder? connectionDetailsBuilder,
  }) => CameraTransferPage(
    eventId: 'event',
    eventTitle: 'Live shoot',
    session: session,
    startedAt: DateTime.fromMillisecondsSinceEpoch(1000),
    transfers: transfers,
    queue: queue,
    cancelUpload:
        cancelUpload ?? (_) async => UploadCancellationResult.cancelled,
    canCancel: (item) =>
        !item.isUploaded &&
        item.status != TransferLedgerStatus.cancelled &&
        !item.registrationStarted,
    onStop: onStop,
    onShareGuestQr: onShareGuestQr,
    onCameraSetupHelp: onCameraSetupHelp,
    connectionDetailsBuilder: connectionDetailsBuilder,
  );

  void dispose() {
    session.dispose();
    transfers.dispose();
    queue.dispose();
  }
}

TransferLedgerItem _photo(
  String id, {
  String eventId = 'event',
  int createdAt = 1000,
  int fileSize = 1024,
}) => TransferLedgerItem(
  id: id,
  eventId: eventId,
  eventTitle: 'Live shoot',
  filename: '$id.JPG',
  source: 'camera-ftp',
  status: TransferLedgerStatus.queued,
  createdAt: createdAt,
  updatedAt: createdAt,
  fileSize: fileSize,
);

PendingUploadItem _queued(String id, {required int uploadAfter}) =>
    PendingUploadItem(
      id: id,
      eventId: 'event',
      eventTitle: 'Live shoot',
      localPath: '/queue/$id.JPG',
      filename: '$id.JPG',
      source: 'camera-ftp',
      isEnhanced: false,
      createdAt: 1000,
      uploadAfter: uploadAfter,
    );
