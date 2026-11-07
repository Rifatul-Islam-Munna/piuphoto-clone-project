import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/adaptive_usb_camera_transport.dart';
import 'package:mobileapp/core/platform/live_camera_capture.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/ptp_tether_camera.dart';

class _ReaderFake implements LiveCameraTransport {
  _ReaderFake({
    this.startFailure,
    this.stopFailure,
    this.emitDisconnectAtStart = false,
  });

  PlatformException? startFailure;
  PlatformException? stopFailure;
  final bool emitDisconnectAtStart;
  final events = StreamController<LiveCameraEvent>.broadcast();
  final photos = <ConnectedCameraImage>[];
  int starts = 0;
  int stops = 0;
  int reads = 0;
  int acknowledgements = 0;
  int downloads = 0;

  @override
  Stream<LiveCameraEvent> eventsForSession(String sessionId) => events.stream;

  @override
  Future<LiveCameraSession> start(String sessionId) async {
    starts++;
    if (emitDisconnectAtStart) {
      events.add(
        LiveCameraEvent(
          sessionId: sessionId,
          type: 'disconnected',
          code: 'PTP_INVALID_RESPONSE',
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    if (startFailure != null) throw startFailure!;
    return LiveCameraSession(
      id: sessionId,
      cameraId: 'usb-1',
      name: 'Test camera',
      physicalShutter: 'unknown',
      message: 'Camera catalog ready',
      baselineCount: 2,
    );
  }

  @override
  Future<void> stop(String sessionId) async {
    stops++;
    if (stopFailure != null) throw stopFailure!;
  }

  @override
  Future<List<ConnectedCameraImage>> pending(String sessionId) async {
    reads++;
    return List.of(photos);
  }

  @override
  Future<OtgPickedFile> download(String sessionId, String imageId) async {
    downloads++;
    return OtgPickedFile(
      path: '/staging/NEW.JPG',
      name: 'NEW.JPG',
      id: imageId,
    );
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> ids) async {
    acknowledgements += ids.length;
  }
}

PlatformException _badGetDeviceInfo() => PlatformException(
  code: 'PTP_INVALID_RESPONSE',
  message: 'Could not parse reply',
  details: const <String, String>{
    'operation': '0x1001',
    'decoderReason': 'response-buffer-size',
    'responseBytes': '0',
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('iOS uses live vendor tether by default; catalog requires opt-in', () {
    expect(
      preferredUsbCameraTransport(
        platform: TargetPlatform.iOS,
        uploadMode: LiveCameraUploadMode.newShotsOnly,
      ),
      isA<PtpTetherCameraTransport>(),
    );
    expect(
      preferredUsbCameraTransport(
        platform: TargetPlatform.iOS,
        uploadMode: LiveCameraUploadMode.newShotsOnly,
        usePhotoCatalog: false,
      ),
      isA<PtpTetherCameraTransport>(),
    );
    expect(
      preferredUsbCameraTransport(
        platform: TargetPlatform.android,
        uploadMode: LiveCameraUploadMode.newShotsOnly,
      ),
      isNot(isA<AdaptiveUsbCameraTransport>()),
    );
  });

  test(
    'a failed GetDeviceInfo recovers through the SAME mode photo catalog',
    () async {
      // Native may emit disconnected before start() returns its PTP failure.
      // It must not cancel the fallback before catalog recovery starts.
      final primary = _ReaderFake(
        startFailure: _badGetDeviceInfo(),
        emitDisconnectAtStart: true,
      );
      final catalog = _ReaderFake();
      catalog.photos.add(
        const ConnectedCameraImage(id: 'usb-1|1', name: 'NEW.JPG', size: 1024),
      );
      var now = DateTime(2026, 11, 7);
      final adaptive = AdaptiveUsbCameraTransport(
        tether: primary,
        catalog: catalog,
        now: () => now,
      );
      final delivered = <String>[];
      final events = adaptive
          .eventsForSession('one')
          .listen((event) => delivered.add(event.type));
      final session = await adaptive.start('one');
      expect(session.usesPhotoCatalog, isTrue);
      expect(session.message, contains('without changing its USB mode'));
      expect(primary.starts, 1);
      expect(delivered, isEmpty); // Startup disconnect was not forwarded.
      expect(primary.stops, 1); // Released BEFORE catalog takes ownership.
      expect(catalog.starts, 1);

      catalog.events.add(
        const LiveCameraEvent(sessionId: 'one', type: 'photosAvailable'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(delivered, ['photosAvailable']);
      expect((await adaptive.pending('one')).single.name, 'NEW.JPG');
      expect(await adaptive.pending('one'), isEmpty);
      expect(catalog.reads, 1);
      now = now.add(const Duration(seconds: 3));
      expect((await adaptive.pending('one')).single.id, 'usb-1|1');
      expect(catalog.reads, 2);
      final image = await adaptive.download('one', 'usb-1|1');
      expect(image.name, 'NEW.JPG');
      await events.cancel();
      await adaptive.stop('one');
      expect(catalog.stops, 1);
      await adaptive.acknowledge('one', ['usb-1|1']);
      expect(catalog.acknowledgements, 1); // Safe post-stop ACK.
      await primary.events.close();
      await catalog.events.close();
    },
  );

  test(
    'malformed reply after initial PTP handshake never changes readers',
    () async {
      final primary = _ReaderFake(
        startFailure: PlatformException(
          code: 'PTP_INVALID_RESPONSE',
          details: const {'operation': '0x1008'},
        ),
      );
      final catalog = _ReaderFake();
      final adaptive = AdaptiveUsbCameraTransport(
        tether: primary,
        catalog: catalog,
      );
      await expectLater(
        adaptive.start('one'),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'PTP_INVALID_RESPONSE',
          ),
        ),
      );
      expect(catalog.starts, 0);
      await primary.events.close();
      await catalog.events.close();
    },
  );

  test('native close failure prevents claiming the camera again', () async {
    final primary = _ReaderFake(
      startFailure: _badGetDeviceInfo(),
      stopFailure: PlatformException(code: 'PTP_CLOSE_FAILED'),
    );
    final catalog = _ReaderFake();
    final adaptive = AdaptiveUsbCameraTransport(
      tether: primary,
      catalog: catalog,
    );
    await expectLater(
      adaptive.start('one'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'PTP_CLOSE_FAILED',
        ),
      ),
    );
    expect(primary.stops, 1);
    expect(catalog.starts, 0);
    await primary.events.close();
    await catalog.events.close();
  });

  test(
    'PTP success keeps the vendor path and never opens a photo catalog',
    () async {
      final primary = _ReaderFake();
      final catalog = _ReaderFake();
      final adaptive = AdaptiveUsbCameraTransport(
        tether: primary,
        catalog: catalog,
      );
      final session = await adaptive.start('one');
      expect(session.usesPhotoCatalog, isFalse);
      await adaptive.pending('one');
      expect(primary.reads, 1);
      expect(catalog.starts, 0);
      await adaptive.stop('one');
      await primary.events.close();
      await catalog.events.close();
    },
  );
}
