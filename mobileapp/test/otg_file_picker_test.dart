import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('airpix/otg_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('iOS and Android USB diagnostics use the same native method', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'cameraConnectionDiagnostics');
      return {
        'status': 'session-failed',
        'message': 'PTP session could not open',
        'totalImages': 0,
        'cameras': [
          {
            'name': 'Test DSLR',
            'sessionOpen': false,
            'catalogReady': false,
            'catalogProgress': 0,
            'imageCount': 0,
            'sessionError': 'Camera busy',
          },
        ],
      };
    });
    final report = await OtgFilePicker.cameraConnectionDiagnostics();
    expect(report.status, 'session-failed');
    expect(report.cameras.single.sessionError, 'Camera busy');
    expect(report.toSupportReport(), contains('Camera busy'));
  });

  test('native USB permission errors are preserved for the UI', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'USB_PERMISSION_DENIED',
        message: 'Device access was denied',
      );
    });
    await expectLater(
      OtgFilePicker.connectedCameraImages(),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'USB_PERMISSION_DENIED',
        ),
      ),
    );
  });

  test('camera image ids and paths survive the native bridge', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'connectedCameraImages') {
        return [
          {'id': 'usb1|42', 'name': 'IMG_0001.JPG', 'size': '123456'},
        ];
      }
      expect(call.method, 'importConnectedCameraImages');
      expect(call.arguments, {
        'ids': ['usb1|42'],
      });
      return [
        {'id': 'usb1|42', 'name': 'IMG_0001.JPG', 'path': '/tmp/photo.jpg'},
      ];
    });
    final photos = await OtgFilePicker.connectedCameraImages();
    expect(photos.single.id, 'usb1|42');
    final files = await OtgFilePicker.importConnectedCameraImages([
      photos.single.id,
    ]);
    expect(files.single.id, photos.single.id);
    expect(files.single.path, '/tmp/photo.jpg');
  });
}
