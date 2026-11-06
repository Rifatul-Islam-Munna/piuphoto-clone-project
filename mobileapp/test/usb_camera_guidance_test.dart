import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/usb_camera_guidance.dart';

void main() {
  test('passive USB blocks shutter, deletion and UI-lock actions', () {
    final advice = UsbCameraGuidance.forStatus('PTP_SHOOTING_COMMAND_BLOCKED');
    expect(advice.title, contains('blocked for safety'));
    expect(advice.details, contains('delete'));
    expect(advice.nextSteps, contains('physical shutter'));
  });

  test('USB permission errors identify whether phone settings are needed', () {
    final ios = UsbCameraGuidance.forStatus('CAMERA_ACCESS_DENIED');
    expect(ios.settingsRequired, isTrue);
    expect(ios.title, contains('permission'));
    expect(ios.nextSteps, contains('Settings'));

    final android = UsbCameraGuidance.forStatus('USB_PERMISSION_REQUIRED');
    expect(android.settingsRequired, isFalse);
    expect(android.nextSteps, contains('Allow'));
  });

  test('camera discovery is separate from an active live session', () {
    final detected = UsbCameraGuidance.forStatus('camera-detected');
    final live = UsbCameraGuidance.forStatus('live-ready');
    expect(detected.title, 'Wired camera detected');
    expect(detected.details, contains('has not opened'));
    expect(detected.nextSteps, contains('Start Live shooting'));
    expect(live.title, contains('session is active'));
    expect(live.nextSteps, contains('test photo'));
    expect(live.nextSteps, contains('camera shutter'));
  });

  test('unsupported existing-photo scope preserves the shooting workflow', () {
    final guidance = UsbCameraGuidance.forStatus(
      'TETHER_EXISTING_PHOTOS_UNAVAILABLE',
    );
    expect(guidance.title, contains('New shots only'));
    expect(guidance.details, contains('without opening file-import mode'));
    expect(guidance.nextSteps, contains('stop Live shooting'));
    expect(guidance.nextSteps, contains('manual upload'));
  });

  test('undecided iOS authorization offers retry without claiming denial', () {
    for (final status in [
      'authorization-pending',
      'CAMERA_AUTHORIZATION_PENDING',
    ]) {
      final guidance = UsbCameraGuidance.forStatus(status);
      expect(guidance.settingsRequired, isFalse);
      expect(guidance.details, contains('has not yet granted or denied'));
      expect(guidance.nextSteps, contains('retry'));
    }
  });

  test('iOS restrictions are not presented as an app permission toggle', () {
    for (final status in [
      'permission-restricted',
      'CAMERA_ACCESS_RESTRICTED',
    ]) {
      final guidance = UsbCameraGuidance.forStatus(status);
      expect(guidance.settingsRequired, isFalse);
      expect(guidance.title, contains('restricted'));
      expect(guidance.nextSteps, contains('device-management'));
    }
  });

  test('an unavailable authorization state does not claim user denial', () {
    for (final status in [
      'authorization-unavailable',
      'CAMERA_AUTHORIZATION_UNAVAILABLE',
    ]) {
      final guidance = UsbCameraGuidance.forStatus(status);
      expect(guidance.settingsRequired, isFalse);
      expect(guidance.title, contains('could not be checked'));
      expect(guidance.nextSteps, contains('support report'));
    }
  });

  test('no camera never claims the cable is definitely disconnected', () {
    final result = UsbCameraGuidance.forStatus('no-camera');
    expect(result.title, contains('No compatible USB camera'));
    expect(result.details, contains('does not prove'));
    expect(result.nextSteps, contains('PTP'));
  });

  test(
    'unconfirmed camera release requires unplugging without claiming success',
    () {
      for (final code in [
        'PTP_CLOSE_FAILED',
        'PTP_CLOSE_TIMEOUT',
        'PTP_CLOSE_PENDING',
      ]) {
        final guidance = UsbCameraGuidance.forStatus(code);
        expect(guidance.title, 'Disconnect USB to release the camera');
        expect(guidance.details, contains('has not confirmed'));
        expect(guidance.nextSteps, contains('Unplug the USB cable'));
        expect(guidance.nextSteps, contains('continue uploading'));
      }
    },
  );

  test('Sony A7 IV Mass Storage error gives the correct camera menu', () {
    final guidance = UsbCameraGuidance.forStatus('SONY_MASS_STORAGE_MODE');
    expect(guidance.title, contains('Mass Storage'));
    expect(guidance.nextSteps, contains('Remote Shooting'));
    expect(guidance.nextSteps, contains('Dest.+Camera'));
    expect(guidance.nextSteps, contains('New shots only'));
  });

  test(
    'Sony iOS PTP failure keeps the actual reason and does not promise a connection',
    () {
      final guidance = UsbCameraGuidance.forStatus(
        'SONY_CAMERA_SESSION_FAILED',
        message: 'ILCE-7M4: USB session could not open (ImageCaptureCore -99)',
      );
      expect(guidance.title, contains('control is unavailable'));
      expect(guidance.details, contains('ImageCaptureCore -99'));
      expect(guidance.nextSteps, contains('iOS'));
      expect(guidance.nextSteps, contains('Remote Shooting'));
      expect(guidance.nextSteps, contains('Dest.+Camera'));
      expect(guidance.nextSteps, contains('wireless/FTP'));
    },
  );

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
