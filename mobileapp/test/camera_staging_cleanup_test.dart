import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/upload/camera_staging_cleanup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SharedPreferences prefs;
  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
    root = await Directory.systemTemp.createTemp('camera-cleanup-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
    await getIt.reset();
  });

  test(
    'releases only staging copy and leaves queue and camera original',
    () async {
      final stage = File('${root.path}/stage.jpg');
      final queue = File('${root.path}/queued.jpg');
      final camera = File('${root.path}/camera-original.jpg');
      for (final file in [stage, queue, camera]) {
        await file.writeAsBytes([1, 2, 3]);
      }
      await CameraStagingCleanup.release(stage.path);
      expect(await stage.exists(), isFalse);
      expect(await queue.readAsBytes(), [1, 2, 3]);
      expect(await camera.readAsBytes(), [1, 2, 3]);
      expect(prefs.getStringList('camera_staging_cleanup_v1'), isEmpty);
    },
  );

  test(
    'failed deletion persists and retries after a service restart',
    () async {
      final blockedPath = '${root.path}/stage.jpg';
      await Directory(blockedPath).create();
      final unrelated = File('$blockedPath/original.jpg');
      await unrelated.writeAsBytes([9]);
      await CameraStagingCleanup.release(blockedPath);
      expect(await unrelated.readAsBytes(), [9]);
      expect(prefs.getStringList('camera_staging_cleanup_v1'), [blockedPath]);
      // Simulate restart by restoring only persisted preferences.
      final journal = prefs.getStringList('camera_staging_cleanup_v1')!;
      await Directory(blockedPath).delete(recursive: true);
      await File(blockedPath).writeAsBytes([1, 2, 3]);
      await getIt.reset();
      SharedPreferences.setMockInitialValues({
        'camera_staging_cleanup_v1': journal,
      });
      prefs = await SharedPreferences.getInstance();
      getIt.registerSingleton<SharedPreferences>(prefs);
      await CameraStagingCleanup.retryPending();
      expect(await File(blockedPath).exists(), isFalse);
      expect(prefs.getStringList('camera_staging_cleanup_v1'), isEmpty);
    },
  );

  test('overlapping cleanup requests do not lose pending paths', () async {
    final a = Directory('${root.path}/a');
    final b = Directory('${root.path}/b');
    await a.create();
    await b.create();
    await Future.wait([
      CameraStagingCleanup.release(a.path),
      CameraStagingCleanup.release(b.path),
    ]);
    expect(
      prefs.getStringList('camera_staging_cleanup_v1'),
      unorderedEquals([a.path, b.path]),
    );
  });
}
