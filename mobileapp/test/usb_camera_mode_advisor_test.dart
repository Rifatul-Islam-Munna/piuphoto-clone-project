import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/usb_camera_diagnostics.dart';
import 'package:mobileapp/core/platform/usb_camera_mode_advisor.dart';

UsbShootingModeAdvice advise({
  String name = 'Connected camera',
  String transport = 'USB',
  int vendor = 0,
  bool active = false,
}) => UsbShootingModeAdvice.fromDiagnostics(
  UsbCameraDiagnostics.fromMap({
    'status': active ? 'live-ready' : 'camera-detected',
    'message': 'USB camera found',
    'totalImages': 0,
    'cameras': [
      {
        'name': name,
        'transportType': transport,
        'usbVendorId': vendor,
        'liveSessionActive': active,
        'sessionOpen': active,
      },
    ],
  }),
);

void main() {
  test('Alpha 7R IV failure shows its PC Remote Function menu', () {
    for (final name in ['ILCE-7RM4', 'Sony Alpha 7R IV']) {
      final advice = advise(
        name: name,
        vendor: 0x054c,
        transport: 'Mass Storage',
      );
      expect(advice.nextSteps, contains('PC Remote Function'));
      expect(advice.nextSteps, contains('PC Remote Cnct Method = USB'));
      expect(advice.nextSteps, contains('PC+Camera'));
      expect(advice.nextSteps, isNot(contains('Dest.+Camera')));
      expect(advice.nextSteps, contains('will not change it'));
    }
  });

  test('native USB failure immediately displays camera-specific mode help', () {
    final failure = PlatformException(
      code: 'CAMERA_SESSION_FAILED',
      message: 'Native camera session cannot open',
      details: <String, Object>{
        'camera': 'ILCE-7M4',
        'vendorId': 0x054c,
        'transport': 'USB Mass Storage',
      },
    );
    final advice = UsbShootingModeAdvice.fromFailure(failure);
    expect(advice, isNotNull);
    expect(advice!.wrongMode, isTrue);
    expect(advice.nextSteps, contains('Sony'));
    expect(advice.nextSteps, contains('Dest.+Camera'));
  });

  test('missing native identity does not guess a camera brand', () {
    final failure = PlatformException(
      code: 'PTP_TRANSPORT_FAILED',
      message: 'No camera information returned',
    );
    expect(UsbShootingModeAdvice.fromFailure(failure), isNull);
  });

  test(
    'Canon MTP session failure must not be mistaken for storage-only mode',
    () {
      final failure = PlatformException(
        code: 'CAMERA_SESSION_FAILED',
        details: <String, Object>{
          'camera': 'Canon EOS R6 Mark II',
          'vendorId': 0x04a9,
          'transport': 'USB/MTP',
        },
      );
      final advice = UsbShootingModeAdvice.fromFailure(failure);
      expect(advice, isNotNull);
      expect(advice!.wrongMode, isFalse);
      expect(advice.nextSteps, contains('Photo Import/Remote Control'));
    },
  );

  test('Sony Mass Storage is rejected with the right setup', () {
    final advice = advise(
      name: 'ILCE-7M4',
      transport: 'USB Mass Storage',
      vendor: 0x054c,
    );
    expect(advice.wrongMode, isTrue);
    expect(advice.title, contains('Wrong USB mode'));
    expect(advice.nextSteps, contains('PC Remote'));
    expect(advice.nextSteps, contains('Dest.+Camera'));
    expect(advice.nextSteps, contains('Disconnect USB'));
  });

  for (final camera in [
    ('Canon EOS R6 Mark II', 0x04a9, 'USB/MTP', 'Photo Import/Remote Control'),
    ('Nikon Z6', 0x04b0, 'MTP', 'Nikon'),
    ('FUJIFILM X-T5', 0x04cb, 'USB/PTP', 'USB TETHER SHOOTING'),
    ('LUMIX S5', 0x04da, 'USB/PTP', 'PC(Tether)'),
    ('OM SYSTEM OM-1', 0x33a2, 'PTP', 'camera'),
    ('PENTAX K-1', 0x25fb, 'PTP', 'Pentax/Ricoh'),
  ]) {
    test(
      'brand-specific guidance for ${camera.$1} without false mode success',
      () {
        final advice = advise(
          name: camera.$1,
          vendor: camera.$2,
          transport: camera.$3,
        );
        expect(advice.wrongMode, isFalse);
        expect(advice.state, UsbShootingModeState.unverified);
        expect(advice.nextSteps, contains(camera.$4));
        expect(advice.nextSteps, contains('physical shutter'));
      },
    );
  }

  test('generic file-transfer label is not proof of wrong USB mode', () {
    for (final transport in [
      'File Transfer',
      'USB file-transfer',
      'MTP File Transfer',
    ]) {
      final advice = advise(
        name: 'Canon EOS',
        vendor: 0x04a9,
        transport: transport,
      );
      expect(advice.wrongMode, isFalse);
      expect(advice.status, contains('unverified'));
    }
  });

  test('Canon MTP label is not sufficient to reject its tether mode', () {
    final advice = advise(
      name: 'Canon EOS R8',
      vendor: 0x04a9,
      transport: 'USB MTP',
      active: true,
    );
    expect(advice.wrongMode, isFalse);
    expect(advice.state, UsbShootingModeState.activeUnverified);
    expect(advice.status, contains('test shot'));
  });

  test('Sony MTP label prompts PC Remote without guessing a USB mode', () {
    final advice = advise(name: 'Sony Alpha', vendor: 0x054c, transport: 'MTP');
    expect(advice.wrongMode, isFalse);
    expect(advice.nextSteps, contains('PC Remote'));
    expect(advice.status, contains('unverified'));
  });

  test('card-reader and USB streaming are never live shooting', () {
    for (final transport in ['Card Reader', 'USB Streaming', 'exFAT']) {
      expect(advise(name: 'Camera', transport: transport).wrongMode, isTrue);
    }
  });

  test('Android class-8 storage adapter is rejected before a PTP attempt', () {
    final report = UsbCameraDiagnostics.fromMap({
      'status': 'no-camera',
      'totalImages': 0,
      'cameras': [],
      'usbDevices': [
        {
          'id': 'usb1',
          'name': 'Memory card adapter',
          'category': 'Connected accessory',
          'vendorId': 0,
          'productId': 1,
          'usbClass': 8,
          'interfaceClasses': [8],
        },
      ],
    });
    expect(UsbShootingModeAdvice.fromDiagnostics(report).wrongMode, isTrue);
  });

  test(
    'a composite device with a PTP interface is not rejected by class 8',
    () {
      final report = UsbCameraDiagnostics.fromMap({
        'status': 'camera-detected',
        'totalImages': 0,
        'cameras': [],
        'usbDevices': [
          {
            'id': 'usb2',
            'name': 'Nikon camera',
            'category': 'USB/MTP',
            'vendorId': 0x04b0,
            'productId': 2,
            'usbClass': 8,
            'interfaceClasses': [6, 8],
          },
        ],
      });
      final advice = UsbShootingModeAdvice.fromDiagnostics(report);
      expect(advice.wrongMode, isFalse);
      expect(advice.status, contains('unverified'));
    },
  );

  test('iOS cannot claim a wrong camera setting when none is visible', () {
    final advice = UsbShootingModeAdvice.fromDiagnostics(
      UsbCameraDiagnostics.fromMap({
        'status': 'no-camera',
        'cameras': [],
        'totalImages': 0,
      }),
    );
    expect(advice.state, UsbShootingModeState.noCamera);
    expect(advice.wrongMode, isFalse);
    expect(advice.nextSteps, contains('iOS'));
  });
}
