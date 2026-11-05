import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/live_camera_capture.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';

class _Camera implements LiveCameraTransport {
  LiveCameraUploadMode uploadMode = LiveCameraUploadMode.newShotsOnly;
  final signals = StreamController<LiveCameraEvent>.broadcast(sync: true);
  final photos = <ConnectedCameraImage>[];
  final downloaded = <String>[];
  final acknowledgements = <String>[];
  final stopped = <String>[];
  String? id;
  int pendingCalls = 0;
  int failedDownloads = 0;
  int failedAcks = 0;
  int failedStops = 0;
  Completer<void>? opening;
  Completer<void>? closing;
  Completer<void>? downloadGate;

  @override
  Stream<LiveCameraEvent> eventsForSession(String sessionId) => signals.stream;

  @override
  Future<LiveCameraSession> start(String sessionId) async {
    id = sessionId;
    await opening?.future;
    return LiveCameraSession(
      id: sessionId,
      cameraId: 'camera-serial',
      name: 'Test camera',
      physicalShutter: 'unknown',
      message: 'Take a test shot.',
      baselineCount: 1200,
      uploadMode: uploadMode,
    );
  }

  @override
  Future<void> stop(String sessionId) async {
    stopped.add(sessionId);
    await closing?.future;
    if (failedStops > 0) {
      failedStops--;
      throw PlatformException(
        code: 'PTP_CLOSE_FAILED',
        message: 'The camera session remains open.',
      );
    }
  }

  @override
  Future<List<ConnectedCameraImage>> pending(String sessionId) async {
    pendingCalls++;
    return List.of(photos);
  }

  @override
  Future<OtgPickedFile> download(String sessionId, String imageId) async {
    downloaded.add(imageId);
    if (failedDownloads > 0) {
      failedDownloads--;
      throw PlatformException(code: 'CAMERA_FILE_NOT_READY');
    }
    await downloadGate?.future;
    return OtgPickedFile(
      id: imageId,
      path: '/staging/$imageId.jpg',
      name: '$imageId.jpg',
    );
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> imageIds) async {
    if (failedAcks > 0) {
      failedAcks--;
      throw PlatformException(code: 'ACK_BUSY');
    }
    acknowledgements.addAll(imageIds);
    photos.removeWhere((image) => imageIds.contains(image.id));
  }

  void add(String imageId) => photos.add(
    ConnectedCameraImage(id: imageId, name: '$imageId.jpg', size: 42),
  );
  void signal({String? sessionId, String type = 'photosAvailable'}) =>
      signals.add(LiveCameraEvent(sessionId: sessionId ?? id!, type: type));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Camera camera;
  late LiveCameraCapture capture;
  late List<LiveCameraUpdate> updates;
  late bool stagedUsable;

  setUp(() {
    camera = _Camera();
    updates = [];
    stagedUsable = true;
    capture = LiveCameraCapture(
      transport: camera,
      onUpdate: updates.add,
      pollInterval: const Duration(days: 1),
      retryDelay: Duration.zero,
      isStagedFileUsable: (_) async => stagedUsable,
    );
  });

  tearDown(() async {
    await capture.stop();
    await camera.signals.close();
  });

  test(
    'waits for local persistence before acknowledging a new photo',
    () async {
      final saveStarted = Completer<void>();
      final saved = Completer<void>();
      await capture.start(
        save: (file, session) async {
          saveStarted.complete();
          await saved.future;
        },
      );
      await capture.poll();
      camera.add('new-shot');
      final work = capture.poll();
      await saveStarted.future;
      expect(camera.acknowledgements, isEmpty);
      saved.complete();
      await work;
      expect(camera.acknowledgements, ['new-shot']);
    },
  );

  test(
    'does not enumerate old catalog through the legacy import API',
    () async {
      final saved = <String>[];
      final session = await capture.start(
        save: (file, _) async => saved.add(file.id!),
      );
      await capture.poll();
      expect(session.baselineCount, 1200);
      expect(saved, isEmpty);
      camera.add('fresh');
      await capture.poll();
      expect(saved, ['fresh']);
    },
  );

  test(
    'existing and new mode rechecks priority after every complete photo',
    () async {
      camera.uploadMode = LiveCameraUploadMode.existingAndNew;
      camera.add('old-first');
      camera.add('old-second');
      final saved = <String>[];
      final receivedAll = Completer<void>();
      final modes = <LiveCameraUploadMode>[];

      final session = await capture.start(
        save: (file, session) async {
          saved.add(file.id!);
          modes.add(session.uploadMode);
          if (file.id == 'old-first') {
            // A new photo appears while the first old file is being saved.
            // The transport puts it before the remaining card backlog.
            camera.photos.insert(
              0,
              const ConnectedCameraImage(
                id: 'new-shot',
                name: 'new-shot.jpg',
                size: 42,
              ),
            );
          }
          if (saved.length == 3) receivedAll.complete();
        },
      );
      await receivedAll.future.timeout(const Duration(seconds: 2));
      await capture.poll();

      expect(session.uploadMode, LiveCameraUploadMode.existingAndNew);
      expect(saved, ['old-first', 'new-shot', 'old-second']);
      expect(camera.acknowledgements, saved);
      expect(modes, everyElement(LiveCameraUploadMode.existingAndNew));
      expect(
        updates.where((update) => update.message.contains('new photo(s)')),
        isEmpty,
      );
    },
  );

  test('session metadata keeps upload scope explicit and defaults safely', () {
    final base = <Object?, Object?>{'sessionId': 'test'};
    expect(
      LiveCameraSession.fromMap(base).uploadMode,
      LiveCameraUploadMode.newShotsOnly,
    );
    expect(
      LiveCameraSession.fromMap({
        ...base,
        'uploadMode': 'existingAndNew',
      }).uploadMode,
      LiveCameraUploadMode.existingAndNew,
    );
    expect(
      LiveCameraSession.fromMap({
        ...base,
        'uploadMode': 'unexpected-value',
      }).uploadMode,
      LiveCameraUploadMode.newShotsOnly,
    );
  });

  test(
    'burst over 500 photos is delivered once despite duplicate hints',
    () async {
      final saved = <String>[];
      await capture.start(save: (file, _) async => saved.add(file.id!));
      await capture.poll();
      for (var i = 0; i < 620; i++) {
        camera.add('shot-$i');
      }
      camera.add('shot-10');
      camera.signal();
      camera.signal();
      await capture.poll();
      await capture.poll();
      expect(saved.length, 620);
      expect(saved.toSet().length, 620);
      expect(camera.acknowledgements.length, 620);
    },
  );

  test(
    'busy camera leaves the photo pending and retries the download',
    () async {
      final saved = <String>[];
      await capture.start(save: (file, _) async => saved.add(file.id!));
      await capture.poll();
      camera.add('busy-shot');
      camera.failedDownloads = 1;
      await capture.poll();
      expect(camera.acknowledgements, isEmpty);
      expect(saved, isEmpty);
      await capture.poll();
      expect(saved, ['busy-shot']);
      expect(camera.downloaded, ['busy-shot', 'busy-shot']);
    },
  );

  test(
    'local storage failure never acknowledges; retry reuses staging file',
    () async {
      var attempts = 0;
      await capture.start(
        save: (file, _) async {
          attempts++;
          if (attempts == 1) throw StateError('disk full');
        },
      );
      await capture.poll();
      camera.add('pending-storage');
      await capture.poll();
      expect(camera.acknowledgements, isEmpty);
      await capture.poll();
      expect(attempts, 2);
      expect(camera.downloaded, ['pending-storage']);
      expect(camera.acknowledgements, ['pending-storage']);
    },
  );

  test('ack failure retries ack without importing or saving twice', () async {
    final saved = <String>[];
    await capture.start(save: (file, _) async => saved.add(file.id!));
    await capture.poll();
    camera.add('ack-retry');
    camera.failedAcks = 1;
    await capture.poll();
    expect(saved, ['ack-retry']);
    expect(camera.acknowledgements, isEmpty);
    await capture.poll();
    expect(camera.acknowledgements, ['ack-retry']);
    expect(saved, ['ack-retry']);
    expect(camera.downloaded, ['ack-retry']);
  });

  test('a missing staging file is downloaded again on retry', () async {
    var attempts = 0;
    await capture.start(
      save: (file, _) async {
        attempts++;
        if (attempts == 1) throw StateError('staging file disappeared');
      },
    );
    await capture.poll();
    camera.add('missing-staging');
    await capture.poll();
    stagedUsable = false;
    await capture.poll();
    expect(camera.downloaded, ['missing-staging', 'missing-staging']);
    expect(camera.acknowledgements, ['missing-staging']);
  });

  test(
    'simultaneous starts do not leak or replace the pending session',
    () async {
      camera.opening = Completer<void>();
      final first = capture.start(save: (_, _) async {});
      await expectLater(
        capture.start(save: (_, _) async {}),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'LIVE_CAMERA_BUSY',
          ),
        ),
      );
      camera.opening!.complete();
      final session = await first;
      expect(session.id, camera.id);
      expect(capture.isActive, isTrue);
    },
  );

  test('one failed shot does not block the rest of a burst', () async {
    final saved = <String>[];
    await capture.start(save: (file, _) async => saved.add(file.id!));
    await capture.poll();
    camera.add('not-ready');
    camera.add('ready');
    camera.failedDownloads = 1;
    await capture.poll();
    expect(saved, ['ready']);
    expect(camera.photos.single.id, 'not-ready');
    await capture.poll();
    expect(saved, ['ready', 'not-ready']);
  });

  test(
    'late permission or startup response cannot reactivate a stopped run',
    () async {
      camera.opening = Completer<void>();
      final start = capture.start(save: (_, _) async {});
      final error = expectLater(
        start,
        throwsA(
          isA<PlatformException>().having(
            (value) => value.code,
            'code',
            'LIVE_CAMERA_CANCELLED',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final token = camera.id;
      await capture.stop();
      camera.opening!.complete();
      await error;
      expect(capture.isActive, isFalse);
      expect(camera.stopped, everyElement(token));
      expect(camera.downloaded, isEmpty);
    },
  );

  test('events from a different session cannot import or disconnect', () async {
    await capture.start(save: (_, _) async {});
    await capture.poll();
    final scans = camera.pendingCalls;
    camera.signal(sessionId: 'old-session');
    camera.signal(sessionId: 'old-session', type: 'disconnected');
    await Future<void>.delayed(Duration.zero);
    expect(camera.pendingCalls, scans);
    expect(capture.isActive, isTrue);
  });

  test(
    'Stop waits for native release confirmation before reporting stopped',
    () async {
      await capture.start(save: (_, _) async {});
      await capture.poll();
      camera.closing = Completer<void>();
      final close = capture.stop();
      await Future<void>.delayed(Duration.zero);

      expect(capture.isActive, isFalse);
      expect(
        updates.where((update) => update.phase == LiveCameraPhase.stopped),
        isEmpty,
      );

      camera.closing!.complete();
      await close;
      expect(updates.last.phase, LiveCameraPhase.stopped);
    },
  );

  test(
    'failed release stops reception and explains disconnect without false success',
    () async {
      final saved = <String>[];
      await capture.start(save: (file, _) async => saved.add(file.id!));
      await capture.poll();
      camera.add('received');
      await capture.poll();
      camera.failedStops = 1;

      await expectLater(
        capture.stop(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'PTP_CLOSE_FAILED',
          ),
        ),
      );
      expect(capture.isActive, isFalse);
      expect(updates.last.phase, LiveCameraPhase.error);
      expect(updates.last.message, contains('Disconnect the USB cable'));
      expect(updates.last.savedPhotos, 1);
      expect(
        updates.where((update) => update.phase == LiveCameraPhase.stopped),
        isEmpty,
      );

      camera.add('after-stop');
      await capture.poll();
      expect(saved, ['received']);
    },
  );

  test('a disconnect preserves close-failure recovery guidance', () async {
    await capture.start(save: (_, _) async {});
    await capture.poll();
    camera.failedStops = 1;
    camera.signal(type: 'disconnected');
    await Future<void>.delayed(Duration.zero);

    expect(capture.isActive, isFalse);
    expect(updates.last.phase, LiveCameraPhase.disconnected);
    expect(updates.last.code, 'PTP_CLOSE_FAILED');
    expect(updates.last.message, contains('Disconnect the USB cable'));
  });

  test(
    'disconnect ends session and stops processing subsequent photos',
    () async {
      final saved = <String>[];
      await capture.start(save: (file, _) async => saved.add(file.id!));
      await capture.poll();
      camera.signal(type: 'disconnected');
      await Future<void>.delayed(Duration.zero);
      camera.add('after-detach');
      await capture.poll();
      expect(capture.isActive, isFalse);
      expect(saved, isEmpty);
      expect(updates.last.phase, LiveCameraPhase.disconnected);
    },
  );

  test(
    'Stop preserves an already downloaded shot without starting the next',
    () async {
      final saving = Completer<void>();
      final finishSave = Completer<void>();
      final saved = <String>[];
      await capture.start(
        save: (file, _) async {
          saving.complete();
          await finishSave.future;
          saved.add(file.id!);
        },
      );
      await capture.poll();
      camera.add('in-flight');
      camera.add('next');
      final work = capture.poll();
      await saving.future;
      await capture.stop();
      finishSave.complete();
      await work;
      expect(saved, ['in-flight']);
      expect(camera.downloaded, ['in-flight']);
      expect(camera.acknowledgements, ['in-flight']);
    },
  );

  group('native method channel contract', () {
    const channel = MethodChannel('airpix/otg_picker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test(
      'passes the same cancellation token through start, download, ack, stop',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          expect(call.arguments['sessionId'], 'request-1');
          return switch (call.method) {
            'startLiveCameraSession' => {
              'sessionId': 'request-1',
              'cameraId': 'serial',
              'name': 'Camera',
              'physicalShutter': 'supported',
              'baselineCount': 2000,
            },
            'pendingLiveCameraImages' => [
              {'id': 'new-id', 'name': 'IMG.JPG', 'size': '1234'},
            ],
            'downloadLiveCameraImage' => {
              'id': 'new-id',
              'name': 'IMG.JPG',
              'path': '/cache/IMG.JPG',
            },
            _ => true,
          };
        });
        final native = NativeLiveCameraTransport();
        final session = await native.start('request-1');
        expect(session.physicalShutter, 'supported');
        final pending = await native.pending(session.id);
        expect(pending.single.size, 1234);
        final file = await native.download(session.id, pending.single.id);
        expect(file.id, 'new-id');
        await native.acknowledge(session.id, [file.id!]);
        await native.stop(session.id);
        expect(calls.map((call) => call.method), [
          'startLiveCameraSession',
          'pendingLiveCameraImages',
          'downloadLiveCameraImage',
          'acknowledgeLiveCameraImages',
          'stopLiveCameraSession',
        ]);
        expect(calls[2].arguments['id'], 'new-id');
        expect(calls[3].arguments['ids'], ['new-id']);
      },
    );

    test('rejects wrong photo identity or missing download path', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {
          'id': 'other-shot',
          'name': 'image.jpg',
          'path': '/cache/image.jpg',
        },
      );
      await expectLater(
        NativeLiveCameraTransport().download('request', 'expected'),
        throwsA(isA<PlatformException>()),
      );
    });

    test('unknown shutter capability remains unverified', () {
      final session = LiveCameraSession.fromMap({
        'sessionId': 's',
        'physicalShutter': false,
      });
      expect(session.physicalShutter, 'unknown');
    });
  });
}
