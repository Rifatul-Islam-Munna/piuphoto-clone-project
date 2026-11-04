import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/usb_camera_guidance.dart';

void main() {
  test('USB permission errors identify whether phone settings are needed', () {
    final ios = UsbCameraGuidance.forStatus('CAMERA_ACCESS_DENIED');
    expect(ios.settingsRequired, isTrue);
    expect(ios.title, contains('permission'));
    expect(ios.nextSteps, contains('Settings'));

    final android = UsbCameraGuidance.forStatus('USB_PERMISSION_REQUIRED');
    expect(android.settingsRequired, isFalse);
    expect(android.nextSteps, contains('Allow'));
  });

  test('no camera never claims the cable is definitely disconnected', () {
    final result = UsbCameraGuidance.forStatus('no-camera');
    expect(result.title, contains('No compatible USB camera'));
    expect(result.details, contains('does not prove'));
    expect(result.nextSteps, contains('PTP'));
  });

  test('separates the camera session from the file catalog', () {
    final session = UsbCameraGuidance.forStatus('session-failed');
    final catalog = UsbCameraGuidance.forStatus('catalog-loading');
    final empty = UsbCameraGuidance.forStatus('empty-media');
    expect(session.title, contains('connection failed'));
    expect(catalog.title, contains('loading photo list'));
    expect(empty.title, contains('no readable photos'));
  });

  test('keeps the native reason and relevant recovery steps', () {
    final guidance = UsbCameraGuidance.forStatus(
      'USB_CAMERA_IMPORT_FAILED',
      message: 'MTP import returned no data',
    );
    expect(guidance.details, 'MTP import returned no data');
    expect(guidance.nextSteps, contains('storage'));
  });

  test('detects an unsupported USB accessory and outdated native bridge', () {
    expect(
      UsbCameraGuidance.forStatus('unsupported-device').nextSteps,
      contains('Files'),
    );
    expect(
      UsbCameraGuidance.forStatus('missing_plugin').title,
      contains('unavailable'),
    );
  });
}
