import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/usb_camera_diagnostics.dart';
import 'package:mobileapp/core/platform/usb_camera_guidance.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('airpix/otg_picker');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('reports attached USB device separately from a compatible camera', () {
    final diagnostic = UsbCameraDiagnostics.fromMap({
      'status': 'unsupported-device',
      'message': 'A USB accessory was detected',
      'totalImages': 0,
      'usbEnumerationAvailable': true,
      'usbHostSupported': true,
      'connectionNote': 'No PTP camera detected',
      'usbDevices': [
        {
          'id': '7',
          'name': 'Card reader',
          'category': 'USB mass storage / SD reader',
          'vendorId': 4660,
          'productId': 22136,
          'usbClass': 0,
          'interfaceClasses': [8],
          'hasPermission': false,
          'cameraCandidate': false,
        },
      ],
      'cameras': [],
    });
    expect(diagnostic.usbDevices.single.cameraCandidate, isFalse);
    expect(diagnostic.usbDevices.single.usbIdentifier, contains('1234'));
    expect(diagnostic.usbDevices.single.usbIdentifier, contains('5678'));
    expect(diagnostic.cameras, isEmpty);
    expect(diagnostic.canImport, isFalse);
    expect(diagnostic.toSupportReport(), contains('Card reader'));
  });

  test('iOS report does not pretend to enumerate arbitrary OTG adapters', () {
    final diagnostic = UsbCameraDiagnostics.fromMap({
      'status': 'no-camera',
      'message': 'No camera found',
      'totalImages': 0,
      'connectionNote': 'iOS only exposes image capture cameras',
      'cameras': [],
    });
    expect(diagnostic.usbEnumerationAvailable, isFalse);
    expect(diagnostic.usbHostSupported, isNull);
    expect(diagnostic.usbDevices, isEmpty);
    expect(diagnostic.toSupportReport(), contains('iOS only exposes'));
  });

  test('reports transport, USB vendor/product ids and wired confidence', () {
    final diagnostic = UsbCameraDiagnostics.fromMap({
      'status': 'ready',
      'message': 'Connected',
      'totalImages': 2,
      'cameras': [
        {
          'name': 'DSLR',
          'sessionOpen': true,
          'catalogReady': true,
          'catalogProgress': 100,
          'imageCount': 2,
          'transportType': 'ICTransportTypeUSB',
          'usbVendorId': 1196,
          'usbProductId': 123,
          'wiredConfirmed': true,
        },
      ],
    });
    expect(diagnostic.canImport, isTrue);
    expect(diagnostic.cameras.single.wiredConfirmed, isTrue);
    expect(diagnostic.toSupportReport(), contains('ICTransportTypeUSB'));
    expect(diagnostic.toSupportReport(), contains('Camera USB VID'));
  });

  test('USB host unsupported has clear guidance', () {
    final guidance = UsbCameraGuidance.forStatus('host-unsupported');
    expect(guidance.title, contains('OTG'));
    expect(guidance.nextSteps, contains('USB host/OTG'));
  });

  test(
    'manually choosing an unknown USB device uses the correct channel',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'useUsbDeviceAsCamera');
        expect(call.arguments, {'deviceId': '23'});
        return true;
      });
      await OtgFilePicker.useUsbDeviceAsCamera('23');
    },
  );

  test('manual USB candidate failure is not silently ignored', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'USB_CAMERA_DISCONNECTED',
        message: 'USB unplugged',
      );
    });
    await expectLater(
      OtgFilePicker.useUsbDeviceAsCamera('23'),
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'USB_CAMERA_DISCONNECTED',
        ),
      ),
    );
  });
}
