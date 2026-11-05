import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';
import 'package:mobileapp/core/network/dio_helper.dart';
import 'package:mobileapp/core/platform/live_camera_capture.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/ptp_tether_camera.dart';
import 'package:mobileapp/core/platform/ptp_tether_link.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/core/upload/upload_queue_service.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// These tests join the real protocol parser, live receiver, durable queue and
/// cloud worker. Only the native camera I/O and remote HTTP server are faked.
/// Long fallback intervals make a successful shot depend on its native event,
/// rather than an explicit test poll or a conveniently timed reconciliation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  final event = EventSummary(
    id: '654321001122334455667788',
    title: 'Physical shutter event',
  );
  const albumId = '654321001122334455667799';
  late Directory directory;
  late _NativeNikon native;
  late _CloudServer cloud;
  final captures = <LiveCameraCapture>[];
  final accepted = <PendingUploadItem>[];
  final updates = <LiveCameraUpdate>[];

  setUp(() async {
    UploadQueueService.stop();
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    await UploadQueueStorage.init();
    await TransferLedgerStorage.init();
    directory = await Directory.systemTemp.createTemp('usb-shutter-cloud-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => directory.path);
    dotenv.loadFromString(envString: 'API_URL=https://cloud.invalid');
    DioHelper.init();
    DioHelper.dio.interceptors.clear();
    native = _NativeNikon(directory);
    cloud = _CloudServer();
    DioHelper.dio.httpClientAdapter = cloud;
    captures.clear();
    accepted.clear();
    updates.clear();
    UploadQueueService.start();
  });

  tearDown(() async {
    UploadQueueService.stop();
    for (final capture in captures) {
      await capture.stop(notify: false);
    }
    cloud.releaseFirstUpload();
    await _until(() => !UploadQueueService.isProcessing.value);
    await native.dispose();
    await Future<void>.delayed(Duration.zero);
    await TransferLedgerStorage.init();
    await UploadQueueStorage.init();
    DioHelper.dio.close(force: true);
    await cloud.waitForBodies();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await getIt.reset();
    await directory.delete(recursive: true);
  });

  Future<LiveCameraCapture> start({
    LiveCameraUploadMode uploadMode = LiveCameraUploadMode.newShotsOnly,
  }) async {
    final transport = PtpTetherCameraTransport(
      link: native,
      uploadMode: uploadMode,
      eventPollInterval: const Duration(days: 1),
      cardScanInterval: const Duration(days: 1),
    );
    final capture = LiveCameraCapture(
      transport: transport,
      uploadMode: uploadMode,
      onUpdate: updates.add,
      pollInterval: const Duration(days: 1),
    );
    captures.add(capture);
    await capture.start(
      save: (file, session) async {
        // Same receiver boundary as UploadPage: the destination belongs to the
        // session, and cloud acceptance does not wait for network completion.
        final item = await UploadQueueService.receiveCameraFile(
          event: event,
          path: file.path,
          filename: file.name,
          isEnhanced: true,
          albumId: albumId,
          source: 'otg-ptp',
          cameraId: session.name,
          fingerprint: '${event.id}|otg-ptp|${session.cameraId}|${file.id}',
        );
        accepted.add(item);
        await File(file.path).delete();
      },
    );
    return capture;
  }

  test(
    'native shutter events upload every new photo while cloud is blocked and old card photos stay skipped',
    () async {
      await native.putOnCard(1, 'OLD.JPG');
      cloud.holdFirstUpload = true;
      final capture = await start();
      // Settle the initial empty drain; no poll is called after any shutter.
      await capture.poll();
      expect(accepted, isEmpty);
      expect(native.downloadedNames, isEmpty);
      expect(cloud.uploads, isEmpty);

      await native.shutter(2, 'SHOT_0002.JPG');
      await _until(() => native.acknowledgedNames.length == 1);
      await _until(() => cloud.uploads.length == 1);
      expect(cloud.firstUploadReleased, isFalse);
      expect(cloud.registrations, isEmpty);

      final first = accepted.single;
      final receiving = TransferLedgerStorage.find(first.id)!;
      expect(receiving.filename, 'SHOT_0002.JPG');
      expect(receiving.fileSize, _jpeg.length);
      expect(receiving.isUploaded, isFalse);
      expect(receiving.localPath, first.localPath);
      expect(await File(first.localPath).readAsBytes(), _jpeg);
      expect(UploadQueueService.canCancel(receiving), isTrue);

      // A second physical shutter and duplicate interrupt hints arrive while
      // the first upload response is unavailable. Camera ACK must still proceed.
      await native.shutter(3, 'SHOT_0003.JPG');
      native.signalAdded(2);
      native.signalAdded(3);
      native.signalAdded(3);
      await _until(() => native.acknowledgedNames.length == 2);
      expect(native.downloadedNames, ['SHOT_0002.JPG', 'SHOT_0003.JPG']);
      expect(accepted, hasLength(2));
      expect(UploadQueueStorage.items.value, hasLength(2));
      expect(cloud.uploads, hasLength(1));
      expect(cloud.registrations, isEmpty);

      cloud.releaseFirstUpload();
      await _until(
        () =>
            cloud.registrations.length == 2 &&
            UploadQueueStorage.items.value.isEmpty &&
            !UploadQueueService.isProcessing.value,
      );

      expect(cloud.uploads.map(_uploadFilename), [
        'SHOT_0002.JPG',
        'SHOT_0003.JPG',
      ]);
      final registrations = cloud.registrations.map(_requestData).toList();
      expect(
        registrations.map((row) => row['clientTransferId']).toSet(),
        accepted.map((item) => item.id).toSet(),
      );
      final guestQr = GuestQrPayload.decode(GuestQrPayload.encode(event.id))!;
      expect(guestQr.faceEnrollment, isTrue);
      for (final registration in registrations) {
        expect(registration['eventId'], guestQr.eventId);
        expect(registration['albumId'], albumId);
        expect(registration['isEnhanced'], isTrue);
        expect(registration['mediaType'], 'photo');
      }
      for (final item in accepted) {
        expect(TransferLedgerStorage.find(item.id)!.isUploaded, isTrue);
        expect(UploadQueueStorage.isCompleted(item.id), isTrue);
        expect(await File(item.localPath).exists(), isFalse);
      }
      for (final handle in [1, 2, 3]) {
        expect(await native.cardFile(handle).readAsBytes(), _jpeg);
      }
      expect(native.bodyModes, everyElement(0));
      expect(
        updates.where((update) => update.phase == LiveCameraPhase.error),
        isEmpty,
      );
    },
  );

  test(
    'combined mode prioritizes a new shutter over old backlog and reconnect does not publish the same objects twice',
    () async {
      await native.putOnCard(1, 'OLD_0001.JPG');
      await native.putOnCard(2, 'OLD_0002.JPG');
      native.onDownload = (handle) async {
        if (handle == 1 && !native.hasPhoto(3)) {
          // The new event arrives while one whole old file is transferring.
          await native.shutter(3, 'NEW_0003.JPG');
        }
      };
      final firstCapture = await start(
        uploadMode: LiveCameraUploadMode.existingAndNew,
      );
      await _until(
        () =>
            native.acknowledgedNames.length == 3 &&
            cloud.registrations.length == 3 &&
            UploadQueueStorage.items.value.isEmpty &&
            !UploadQueueService.isProcessing.value,
      );

      expect(native.downloadedNames, [
        'OLD_0001.JPG',
        'NEW_0003.JPG',
        'OLD_0002.JPG',
      ]);
      expect(cloud.uploads.map(_uploadFilename), [
        'OLD_0001.JPG',
        'NEW_0003.JPG',
        'OLD_0002.JPG',
      ]);
      final firstTransferIds = accepted.map((item) => item.id).toSet();
      expect(firstTransferIds, hasLength(3));
      await firstCapture.stop(notify: false);

      // Simulate UI-history retention and app-state reload while preserving
      // confirmed receipts. Reading the same card must not reupload its photos.
      await TransferLedgerStorage.clearEvent(event.id);
      await UploadQueueStorage.init();
      await TransferLedgerStorage.init();
      await start(uploadMode: LiveCameraUploadMode.existingAndNew);
      await _until(() => native.acknowledgedNames.length == 6);
      expect(accepted.skip(3).map((item) => item.id).toSet(), firstTransferIds);
      expect(cloud.uploads, hasLength(3));
      expect(cloud.registrations, hasLength(3));
      expect(UploadQueueStorage.items.value, isEmpty);
      for (final handle in [1, 2, 3]) {
        expect(await native.cardFile(handle).readAsBytes(), _jpeg);
      }
    },
  );

  test(
    'cancelling an in-flight camera upload leaves the next shutter receiving and uploading normally',
    () async {
      cloud.holdFirstUpload = true;
      final capture = await start();
      await capture.poll();
      await native.shutter(1, 'CANCEL_ME.JPG');
      await _until(
        () => native.acknowledgedNames.length == 1 && cloud.uploads.length == 1,
      );
      final cancelled = accepted.single;
      expect(
        await UploadQueueService.cancelUpload(cancelled.id),
        UploadCancellationResult.cancelled,
      );

      await native.shutter(2, 'KEEP_SHOOTING.JPG');
      native.signalAdded(1);
      await _until(
        () =>
            native.acknowledgedNames.length == 2 &&
            cloud.registrations.length == 1 &&
            UploadQueueStorage.items.value.isEmpty &&
            !UploadQueueService.isProcessing.value,
      );

      expect(capture.isActive, isTrue);
      expect(cloud.uploads, hasLength(2));
      expect(
        _requestData(cloud.registrations.single)['clientTransferId'],
        accepted.last.id,
      );
      expect(
        TransferLedgerStorage.find(cancelled.id)!.status,
        TransferLedgerStatus.cancelled,
      );
      expect(TransferLedgerStorage.find(accepted.last.id)!.isUploaded, isTrue);
      expect(await File(cancelled.localPath).exists(), isTrue);
      expect(await native.cardFile(1).readAsBytes(), _jpeg);
      expect(await native.cardFile(2).readAsBytes(), _jpeg);
      expect(native.downloadedNames, ['CANCEL_ME.JPG', 'KEEP_SHOOTING.JPG']);
    },
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'The automatic USB-to-cloud pipeline did not reach the expected state',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

String _uploadFilename(RequestOptions request) =>
    (request.data as FormData).files.single.value.filename!;

Map<String, dynamic> _requestData(RequestOptions request) {
  final data = request.data;
  return Map<String, dynamic>.from(
    data is String ? jsonDecode(data) as Map : data as Map,
  );
}

ResponseBody _json(Map<String, dynamic> value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

class _CloudServer implements HttpClientAdapter {
  final uploads = <RequestOptions>[];
  final registrations = <RequestOptions>[];
  final _bodies = <Future<void>>[];
  final _firstUpload = Completer<ResponseBody>();
  bool holdFirstUpload = false;

  bool get firstUploadReleased => _firstUpload.isCompleted;

  void releaseFirstUpload() {
    if (!_firstUpload.isCompleted) {
      _firstUpload.complete(_json({'url': 'https://photos.invalid/first.jpg'}));
    }
  }

  Future<void> waitForBodies() async {
    await Future.wait(_bodies);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (requestStream != null) {
      final body = requestStream.drain<void>();
      _bodies.add(body);
      await body;
    }
    Future<ResponseBody> response;
    switch (options.path) {
      case '/image/upload':
        uploads.add(options);
        response = holdFirstUpload && uploads.length == 1
            ? _firstUpload.future
            : Future.value(
                _json({'url': 'https://photos.invalid/${uploads.length}.jpg'}),
              );
      case '/eventImage':
        registrations.add(options);
        response = Future.value(
          _json({
            'data': {
              '_id': 'photo-${registrations.length}',
              'isPublished': true,
            },
          }),
        );
      default:
        // Transfer-status synchronization is independent of image registration.
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

/// A camera-side boundary fixture: emits binary standard PTP events and datasets
/// and writes real complete staging files. Unexpected opcodes fail the test,
/// including any attempt to take a remote shot, lock the body, or delete a card.
class _NativeNikon implements PtpTetherLink {
  _NativeNikon(this.directory);

  final Directory directory;
  final _events = StreamController<Map<Object?, Object?>>.broadcast(sync: true);
  final _card = <int, File>{};
  final _names = <int, String>{};
  final _transferNames = <String, String>{};
  final downloadedNames = <String>[];
  final acknowledgedNames = <String>[];
  final bodyModes = <int>[];
  Future<void> Function(int handle)? onDownload;
  String? _sessionId;

  static const operations = [
    0x1001,
    0x1004,
    0x1007,
    0x1008,
    0x1009,
    0x101b,
    0x90c2,
    0x941c,
  ];

  bool hasPhoto(int handle) => _card.containsKey(handle);
  File cardFile(int handle) => _card[handle]!;

  Future<void> putOnCard(int handle, String name) async {
    final card = Directory('${directory.path}/camera-card');
    await card.create(recursive: true);
    final file = File('${card.path}/$handle-$name');
    await file.writeAsBytes(_jpeg, flush: true);
    _card[handle] = file;
    _names[handle] = name;
  }

  Future<void> shutter(int handle, String name) async {
    await putOnCard(handle, name);
    signalAdded(handle);
  }

  void signalAdded(int handle) {
    _events.add({
      'sessionId': _sessionId,
      'type': 'ptpEvent',
      'data': Uint8List.fromList([
        ..._u32(16),
        ..._u16(4),
        ..._u16(0x4002),
        ..._u32(0),
        ..._u32(handle),
      ]),
    });
  }

  Future<void> dispose() => _events.close();

  @override
  Stream<Map<Object?, Object?>> events(String sessionId) => _events.stream;

  @override
  Future<PtpTetherConnection> open(String sessionId) async {
    expect(_sessionId, isNull);
    _sessionId = sessionId;
    return PtpTetherConnection(
      sessionId: sessionId,
      cameraId: 'nikon-test-serial-001',
      name: 'Nikon Z6',
      vendorId: 0x04b0,
    );
  }

  @override
  Future<PtpTetherResponse> command(
    String sessionId,
    int opcode, {
    List<int> params = const [],
    Uint8List? outData,
  }) async {
    expect(sessionId, _sessionId);
    expect(outData, isNull);
    expect(operations, contains(opcode));
    switch (opcode) {
      case 0x1001:
        return _ok([
          ..._u16(100),
          ..._u32(10),
          ..._u16(100),
          0,
          ..._u16(0),
          ..._array16(operations),
          ..._array16([0x4002]),
          ..._array16([]),
          ..._array16([0x3801]),
          ..._array16([0x3801]),
          ..._string('Nikon'),
          ..._string('Nikon Z6'),
          ..._string('1.0'),
          ..._string('TEST-001'),
        ]);
      case 0x90c2:
        bodyModes.add(params.single);
        expect(params.single, 0);
        return _ok([]);
      case 0x941c:
        return _ok([0, 0, 0, 0]);
      case 0x1004:
        return _ok(_array32([1]));
      case 0x1007:
        expect(params, [1, 0, 0]);
        return _ok(_array32(_card.keys.toList()));
      case 0x1008:
        final handle = params.single;
        final file = _card[handle];
        if (file == null) return PtpTetherResponse(responseCode: 0x2009);
        return _ok([
          ..._u32(1),
          ..._u16(0x3801),
          ..._u16(0),
          ..._u32(await file.length()),
          ...List<int>.filled(26, 0),
          ..._u32(0),
          ...List<int>.filled(6, 0),
          ..._u32(0),
          ..._string(_names[handle]!),
          ..._string('20261106T1200${handle.toString().padLeft(2, '0')}'),
          0,
          0,
        ]);
      default:
        throw StateError(
          'Photo bytes must use the native file-transfer method',
        );
    }
  }

  @override
  Future<OtgPickedFile> download(
    String sessionId, {
    required String transferId,
    required int handle,
    required String name,
    required int expectedSize,
    int? partialOpcode,
  }) async {
    expect(sessionId, _sessionId);
    expect(name, _names[handle]);
    expect(expectedSize, await cardFile(handle).length());
    expect(partialOpcode, 0x101b);
    final staging = Directory('${directory.path}/native-staging');
    await staging.create(recursive: true);
    downloadedNames.add(name);
    _transferNames[transferId] = name;
    final file = await cardFile(
      handle,
    ).copy('${staging.path}/${downloadedNames.length}-$name');
    await onDownload?.call(handle);
    return OtgPickedFile(path: file.path, name: name, id: transferId);
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> ids) async {
    for (final id in ids) {
      acknowledgedNames.add(_transferNames[id]!);
    }
  }

  @override
  Future<void> close(String sessionId) async {
    if (_sessionId == sessionId) _sessionId = null;
  }

  PtpTetherResponse _ok(List<int> data) =>
      PtpTetherResponse(responseCode: 0x2001, data: Uint8List.fromList(data));
}

List<int> _u16(int value) => [value & 255, (value >> 8) & 255];
List<int> _u32(int value) => [
  for (var byte = 0; byte < 4; byte++) (value >> (8 * byte)) & 255,
];
List<int> _array16(List<int> values) => [
  ..._u32(values.length),
  for (final value in values) ..._u16(value),
];
List<int> _array32(List<int> values) => [
  ..._u32(values.length),
  for (final value in values) ..._u32(value),
];
List<int> _string(String value) => [
  value.length + 1,
  for (final unit in value.codeUnits) ..._u16(unit),
  0,
  0,
];

// A generated one-pixel JPEG keeps the transfer byte-exact without needing a
// physical camera or a network-hosted fixture. Its format is a real decodable JPG.
final Uint8List _jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwChRRRXsHln/9k=',
);
