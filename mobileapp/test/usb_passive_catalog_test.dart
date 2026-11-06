import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/live_camera_capture.dart';
import 'package:mobileapp/core/platform/mtp_catalog_camera.dart';
import 'package:mobileapp/core/platform/ptp_tether_camera.dart';

Matcher _error(String code) => throwsA(
  isA<PlatformException>().having((error) => error.code, 'code', code),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const methodChannel = MethodChannel('airpix/otg_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test(
    'live defaults use shooting transport and never fall back to file import',
    () {
      expect(
        preferredUsbCameraTransport(
          platform: TargetPlatform.iOS,
          uploadMode: LiveCameraUploadMode.newShotsOnly,
        ),
        isA<PtpTetherCameraTransport>(),
      );
      expect(
        preferredUsbCameraTransport(
          platform: TargetPlatform.android,
          uploadMode: LiveCameraUploadMode.newShotsOnly,
        ),
        isA<PtpTetherCameraTransport>(),
      );
      expect(
        preferredUsbCameraTransport(
          platform: TargetPlatform.windows,
          uploadMode: LiveCameraUploadMode.newShotsOnly,
        ),
        isA<PtpTetherCameraTransport>(),
      );
    },
  );

  test(
    'iOS calls ImageCaptureCore catalog APIs, no vendor PTP commands',
    () async {
      final methods = <String>[];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        methods.add(call.method);
        final args = call.arguments as Map?;
        switch (call.method) {
          case 'startLiveCameraSession':
            expect(args?['uploadMode'], 'existingAndNew');
            return <String, Object?>{
              'sessionId': args?['sessionId'],
              'cameraId': 'sony-camera',
              'name': 'Sony',
              'physicalShutter': 'unknown',
              'message': 'Camera photo catalog ready',
              'baselineCount': 2,
              'uploadMode': 'existingAndNew',
            };
          case 'pendingLiveCameraImages':
            return <Object?>[
              <String, Object?>{
                'id': 'sony-camera|4',
                'name': 'NEW.JPG',
                'size': '6',
              },
            ];
          case 'downloadLiveCameraImage':
            expect(args?['id'], 'sony-camera|4');
            return <String, Object?>{
              'id': 'sony-camera|4',
              'name': 'NEW.JPG',
              'path': '/staging/new.jpg',
            };
          case 'acknowledgeLiveCameraImages':
            expect(args?['ids'], ['sony-camera|4']);
            return null;
          case 'stopLiveCameraSession':
            return null;
          default:
            throw PlatformException(code: 'UNEXPECTED_NATIVE_PTP_COMMAND');
        }
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(methodChannel, null),
      );

      const native = NativeLiveCameraTransport(
        uploadMode: LiveCameraUploadMode.existingAndNew,
      );
      final session = await native.start('live-1');
      expect(session.uploadMode, LiveCameraUploadMode.existingAndNew);
      expect(session.baselineCount, 2);
      final images = await native.pending('live-1');
      expect(images.map((image) => image.name), ['NEW.JPG']);
      final downloaded = await native.download('live-1', images.single.id);
      expect(downloaded.name, 'NEW.JPG');
      await native.acknowledge('live-1', [images.single.id]);
      await native.stop('live-1');

      expect(methods, [
        'startLiveCameraSession',
        'pendingLiveCameraImages',
        'downloadLiveCameraImage',
        'acknowledgeLiveCameraImages',
        'stopLiveCameraSession',
      ]);
      expect(methods.contains('sendPtpTetherCommand'), isFalse);
      expect(methods.contains('openPtpTetherSession'), isFalse);
    },
  );

  group('Android read-only MTP catalog', () {
    late List<Map<String, Object?>> devices;
    late List<Map<String, Object?>> cameraPhotos;
    late Directory temp;
    late File stagedPhoto;
    late List<String> methods;

    setUp(() async {
      devices = <Map<String, Object?>>[
        <String, Object?>{
          'id': '17',
          'name': 'Nikon Z6',
          'hasPermission': true,
          'directSupported': true,
        },
      ];
      cameraPhotos = <Map<String, Object?>>[
        <String, Object?>{'id': '17|1', 'name': 'OLD.JPG', 'size': '6'},
      ];
      methods = <String>[];
      temp = await Directory.systemTemp.createTemp('airpix-passive-ptp-');
      stagedPhoto = File('${temp.path}${Platform.pathSeparator}NEW.JPG');
      await stagedPhoto.writeAsString('ABCDEF');
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        methods.add(call.method);
        switch (call.method) {
          case 'setTransferScreenAwake':
            final args = call.arguments as Map;
            expect(args['owner'], startsWith('usb-mtp:'));
            return null;
          case 'connectedCameraDevices':
            return devices;
          case 'connectedCameraImages':
            return cameraPhotos;
          case 'importConnectedCameraImages':
            final ids = (call.arguments as Map)['ids'] as List;
            return ids
                .map(
                  (id) => {
                    'id': id,
                    'path': stagedPhoto.path,
                    'name': 'NEW.JPG',
                  },
                )
                .toList();
          default:
            throw PlatformException(
              code: 'REMOTE_SHUTTER_OR_STORAGE_FALLBACK_FORBIDDEN',
              message: call.method,
            );
        }
      });
    });

    tearDown(() async {
      messenger.setMockMethodCallHandler(methodChannel, null);
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test(
      'skips baseline, polls new shot, downloads and acknowledges locally',
      () async {
        final camera = MtpCatalogCameraTransport();
        final session = await camera.start('s');
        expect(session.baselineCount, 1);
        expect(session.uploadMode, LiveCameraUploadMode.newShotsOnly);
        expect(await camera.pending('s'), isEmpty);

        cameraPhotos.add({'id': '17|2', 'name': 'NEW.JPG', 'size': '6'});
        final files = await camera.pending('s');
        expect(files.map((image) => image.id), ['17|2']);
        final file = await camera.download('s', '17|2');
        expect(file.path, stagedPhoto.path);
        expect(file.name, 'NEW.JPG');
        await camera.acknowledge('s', ['17|2']);
        expect(await camera.pending('s'), isEmpty);
        await camera.stop('s');
        expect(methods, contains('connectedCameraImages'));
        expect(methods, contains('importConnectedCameraImages'));
        expect(methods, isNot(contains('openPtpTetherSession')));
        expect(methods, isNot(contains('sendPtpTetherCommand')));
        expect(methods, isNot(contains('pickSource')));
      },
    );

    test(
      'automatic polling receives new photos without any shutter event',
      () async {
        final transport = MtpCatalogCameraTransport();
        final received = Completer<String>();
        final capture = LiveCameraCapture(
          transport: transport,
          pollInterval: const Duration(milliseconds: 35),
          onUpdate: (_) {},
        );
        addTearDown(() => capture.stop(notify: false));
        await capture.start(
          save: (file, _) async {
            if (!received.isCompleted) received.complete(file.name);
          },
        );
        cameraPhotos.add({'id': '17|2', 'name': 'NEW.JPG', 'size': '6'});
        final name = await received.future.timeout(const Duration(seconds: 3));
        expect(name, 'NEW.JPG');
        expect(methods, isNot(contains('sendPtpTetherCommand')));
        expect(methods, isNot(contains('openPtpTetherSession')));
      },
    );

    test(
      'delayed file-length metadata does not permanently hide a new photo',
      () async {
        final camera = MtpCatalogCameraTransport();
        await camera.start('s');
        cameraPhotos.add({'id': '17|5', 'name': 'WRITING.JPG', 'size': '0'});
        expect(await camera.pending('s'), isEmpty);
        cameraPhotos.last['size'] = '6';
        final files = await camera.pending('s');
        expect(files.map((image) => image.id), ['17|5']);
        await camera.stop('s');
      },
    );

    test(
      'partial image bytes never receive a successful download result',
      () async {
        final camera = MtpCatalogCameraTransport();
        await camera.start('s');
        cameraPhotos.add({'id': '17|6', 'name': 'WRITING.JPG', 'size': '9'});
        expect((await camera.pending('s')).single.id, '17|6');
        await expectLater(
          camera.download('s', '17|6'),
          _error('CAMERA_FILE_NOT_READY'),
        );
        expect(await stagedPhoto.exists(), isFalse);
        expect((await camera.pending('s')).single.id, '17|6');
        await camera.stop('s');
      },
    );

    test(
      'existing-and-new mode preserves old-photo backlog without USB mode change',
      () async {
        final camera = MtpCatalogCameraTransport(
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        final session = await camera.start('s');
        expect(session.uploadMode, LiveCameraUploadMode.existingAndNew);
        expect((await camera.pending('s')).single.name, 'OLD.JPG');
        await camera.stop('s');
        expect(methods, isNot(contains('sendPtpTetherCommand')));
      },
    );

    test(
      'camera-maker vendor USB interface works even without standard class 6',
      () async {
        devices[0]['directSupported'] = false;
        final transport = MtpCatalogCameraTransport();
        final session = await transport.start('vendor-ptp');
        expect(session.baselineCount, 1);
        cameraPhotos.add({'id': '17|2', 'name': 'NEW.JPG', 'size': '6'});
        expect((await transport.pending('vendor-ptp')).single.id, '17|2');
        await transport.stop('vendor-ptp');
        expect(methods, isNot(contains('sendPtpTetherCommand')));
      },
    );

    test(
      'storage-only USB devices are rejected, never opened as a folder',
      () async {
        devices[0]['name'] = 'USB Mass Storage Card Reader';
        final camera = MtpCatalogCameraTransport();
        await expectLater(camera.start('s'), _error('TETHER_MODE_UNSUPPORTED'));
        expect(methods, isNot(contains('pickSource')));
        expect(methods, isNot(contains('openPtpTetherSession')));
      },
    );
  });
}
