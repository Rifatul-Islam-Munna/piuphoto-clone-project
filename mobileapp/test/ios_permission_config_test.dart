import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every enabled iOS resource has a nonempty purpose string', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    for (final key in [
      'NSCameraUsageDescription',
      'NSPhotoLibraryUsageDescription',
      'NSPhotoLibraryAddUsageDescription',
      'NSLocalNetworkUsageDescription',
    ]) {
      final pattern = RegExp('<key>$key</key>\\s*<string>([^<]+)</string>');
      final values = pattern.allMatches(plist).toList();
      expect(values, hasLength(1), reason: key);
      expect(
        values.single.group(1)!.trim().length,
        greaterThan(25),
        reason: key,
      );
    }
  });

  test('CocoaPods enables only the permission handlers used by the app', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    for (final flag in ['CAMERA', 'PHOTOS', 'PHOTOS_ADD_ONLY']) {
      expect(podfile, contains('PERMISSION_$flag=1'));
    }
    for (final flag in [
      'MICROPHONE',
      'LOCATION',
      'BLUETOOTH',
      'CONTACTS',
      'APP_TRACKING_TRANSPARENCY',
    ]) {
      expect(podfile, contains('PERMISSION_$flag=0'));
    }
    expect(
      File('ios/Flutter/Debug.xcconfig').readAsStringSync(),
      contains('Pods-Runner.debug.xcconfig'),
    );
    expect(
      File('ios/Flutter/Release.xcconfig').readAsStringSync(),
      contains('Pods-Runner.release.xcconfig'),
    );
  });
}
