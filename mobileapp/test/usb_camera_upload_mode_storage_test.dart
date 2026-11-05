import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/storage/usb_camera_upload_mode_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
  });

  tearDown(() async {
    await getIt.reset();
  });

  test(
    'missing and invalid preferences never widen uploads to old photos',
    () async {
      expect(
        UsbCameraUploadModeStorage.read(),
        LiveCameraUploadMode.newShotsOnly,
      );

      final preferences = getIt<SharedPreferences>();
      await preferences.setString(
        'usb_camera_upload_mode_v1',
        'unknown-future-mode',
      );
      expect(
        UsbCameraUploadModeStorage.read(),
        LiveCameraUploadMode.newShotsOnly,
      );

      await preferences.setInt('usb_camera_upload_mode_v1', 1);
      expect(
        UsbCameraUploadModeStorage.read(),
        LiveCameraUploadMode.newShotsOnly,
      );
    },
  );

  test(
    'restores the selected mode from preferences for the next session',
    () async {
      await UsbCameraUploadModeStorage.save(
        LiveCameraUploadMode.existingAndNew,
      );
      expect(
        UsbCameraUploadModeStorage.read(),
        LiveCameraUploadMode.existingAndNew,
      );

      await UsbCameraUploadModeStorage.save(LiveCameraUploadMode.newShotsOnly);
      expect(
        UsbCameraUploadModeStorage.read(),
        LiveCameraUploadMode.newShotsOnly,
      );
    },
  );

  test(
    'a rejected preference write is surfaced instead of reporting success',
    () async {
      await getIt.unregister<SharedPreferences>();
      getIt.registerSingleton<SharedPreferences>(_RejectingPreferences());

      await expectLater(
        UsbCameraUploadModeStorage.save(LiveCameraUploadMode.existingAndNew),
        throwsStateError,
      );
      expect(
        UsbCameraUploadModeStorage.read(),
        LiveCameraUploadMode.newShotsOnly,
      );
    },
  );
}

class _RejectingPreferences implements SharedPreferences {
  String value = LiveCameraUploadMode.newShotsOnly.name;

  @override
  Object? get(String key) => value;

  @override
  Future<bool> setString(String key, String next) async {
    value = next;
    return false;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected preferences call: ${invocation.memberName}',
  );
}
