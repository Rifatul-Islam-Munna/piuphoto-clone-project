import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/usb_camera_diagnostics.dart';

void main() {
  test('converts native iOS camera state to typed diagnostics', () {
    final diagnostic = UsbCameraDiagnostics.fromMap({
      'status': 'ready',
      'message': 'Camera connected',
      'totalImages': 14,
      'cameras': [
        {
          'name': 'PTP Camera',
          'sessionOpen': true,
          'catalogReady': true,
          'catalogProgress': 100,
          'imageCount': 14,
        },
      ],
    });
    expect(diagnostic.canImport, isTrue);
    expect(diagnostic.cameras.single.sessionOpen, isTrue);
    expect(diagnostic.toSupportReport(), contains('PTP Camera'));
    expect(diagnostic.toSupportReport(), contains('14'));
  });

  test('handles no camera and permission denied without crashing', () {
    for (final status in [
      'no-camera',
      'permission-denied',
      'catalog-loading',
    ]) {
      final diagnostic = UsbCameraDiagnostics.fromMap({
        'status': status,
        'message': 'Please check connection',
        'cameras': [],
        'totalImages': 0,
      });
      expect(diagnostic.canImport, isFalse);
      expect(diagnostic.cameras, isEmpty);
    }
  });
}
