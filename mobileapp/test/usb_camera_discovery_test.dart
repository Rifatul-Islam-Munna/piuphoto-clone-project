import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/usb_camera_diagnostics.dart';

Map<String, Object> cameraSnapshot({
  bool sessionOpen = false,
  bool catalogReady = false,
  bool liveSessionActive = false,
  int imageCount = 0,
}) => {
  'name': 'Test camera',
  'sessionOpen': sessionOpen,
  'catalogReady': catalogReady,
  'catalogProgress': catalogReady ? 100 : 0,
  'imageCount': imageCount,
  'liveSessionActive': liveSessionActive,
};

void main() {
  test(
    'discovery reports a camera without claiming an empty photo catalog',
    () {
      final report = UsbCameraDiagnostics.fromMap({
        'status': 'camera-detected',
        'discoveryOnly': true,
        'contentsAuthorization': 'authorized',
        'controlAuthorization': 'not-determined',
        'totalImages': 0,
        'cameras': [cameraSnapshot()],
      });

      expect(report.cameras.single.name, 'Test camera');
      expect(report.discoveryOnly, isTrue);
      expect(report.canImport, isFalse);
      expect(
        report.toSupportReport(),
        contains('Readable images: Not inspected'),
      );
      expect(report.toSupportReport(), isNot(contains('Readable images: 0')));
      expect(
        report.toSupportReport(),
        contains('Control authorization: not-determined'),
      );
    },
  );

  test('cached counts cannot turn a discovery check into import readiness', () {
    final report = UsbCameraDiagnostics.fromMap({
      'status': 'ready',
      'discoveryOnly': true,
      'totalImages': 17,
      'cameras': [cameraSnapshot(catalogReady: true, imageCount: 17)],
    });

    expect(report.canImport, isFalse);
    expect(report.toSupportReport(), contains('Image count: Not inspected'));
    expect(report.toSupportReport(), isNot(contains('Readable images: 17')));
  });

  test('an active live session can be ready before it contains any photos', () {
    final report = UsbCameraDiagnostics.fromMap({
      'status': 'live-ready',
      'discoveryOnly': false,
      'totalImages': 0,
      'cameras': [
        cameraSnapshot(
          sessionOpen: true,
          catalogReady: true,
          liveSessionActive: true,
        ),
      ],
    });

    expect(report.status, 'live-ready');
    expect(report.cameras.single.liveSessionActive, isTrue);
    expect(report.canImport, isFalse);
    expect(report.toSupportReport(), contains('Live session active: true'));
  });

  test(
    'live ownership prevents manual import even with a readable catalog',
    () {
      final report = UsbCameraDiagnostics.fromMap({
        'status': 'ready',
        'discoveryOnly': false,
        'totalImages': 3,
        'cameras': [
          cameraSnapshot(
            sessionOpen: true,
            catalogReady: true,
            liveSessionActive: true,
            imageCount: 3,
          ),
        ],
      });

      expect(report.canImport, isFalse);
    },
  );

  test('an existing manual import session retains catalog readiness', () {
    final report = UsbCameraDiagnostics.fromMap({
      'status': 'ready',
      'discoveryOnly': false,
      'contentsAuthorization': 'authorized',
      'totalImages': 3,
      'cameras': [
        cameraSnapshot(sessionOpen: true, catalogReady: true, imageCount: 3),
      ],
    });

    expect(report.canImport, isTrue);
    expect(report.toSupportReport(), contains('Readable images: 3'));
  });

  test(
    'support reports preserve pending, restricted and denied permission',
    () {
      for (final state in {
        'authorization-pending': 'not-determined',
        'permission-restricted': 'restricted',
        'permission-denied': 'denied',
        'authorization-unavailable': 'unknown',
      }.entries) {
        final report = UsbCameraDiagnostics.fromMap({
          'status': state.key,
          'contentsAuthorization': state.value,
          'controlAuthorization': 'not-determined',
          'discoveryOnly': true,
          'cameras': [],
        });

        expect(report.status, state.key);
        expect(report.contentsAuthorization, state.value);
        expect(report.canImport, isFalse);
        expect(report.toSupportReport(), contains('Status: ${state.key}'));
        expect(
          report.toSupportReport(),
          contains('Contents authorization: ${state.value}'),
        );
      }
    },
  );
}
