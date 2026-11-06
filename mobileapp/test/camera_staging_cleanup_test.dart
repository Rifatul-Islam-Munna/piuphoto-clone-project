import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/upload/camera_staging_cleanup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory root;
  late Directory staging;
  late SharedPreferences prefs;
  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    getIt.registerSingleton<SharedPreferences>(prefs);
    root = await Directory.systemTemp.createTemp('camera-cleanup-');
    staging = await Directory('${root.path}/airpix_ptp_tether').create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (_) async => root.path);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await root.delete(recursive: true);
    await getIt.reset();
  });

  test(
    'releases only staging copy and leaves queue and camera original',
    () async {
      final stage = File('${staging.path}/stage.jpg');
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
      final blockedPath = '${staging.path}/stage.jpg';
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

  test(
    'FTP staging cleanup preserves the durable queue copy and originals',
    () async {
      final session = await Directory(
        '${root.path}/camera_ftp/airpix-ftp-session',
      ).create(recursive: true);
      final received = await File(
        '${session.path}/shot.jpg',
      ).writeAsBytes([1, 2, 3]);
      final queue = await Directory('${root.path}/upload_queue').create();
      final durable = await received.copy('${queue.path}/shot.jpg');
      await CameraStagingCleanup.release(received.path);
      expect(await received.exists(), isFalse);
      expect(await durable.readAsBytes(), [1, 2, 3]);
      expect(prefs.getStringList('camera_staging_cleanup_v1'), isEmpty);
    },
  );

  test('unrelated and traversal paths are rejected without deletion', () async {
    final original = File('${root.path}/original.jpg');
    await original.writeAsBytes([7, 8, 9]);
    for (final path in [original.path, '${staging.path}/../original.jpg']) {
      await expectLater(
        CameraStagingCleanup.release(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await original.readAsBytes(), [7, 8, 9]);
    }
  });

  test(
    'untrusted persisted cleanup entries are discarded without deleting originals',
    () async {
      final original = File('${root.path}/original.jpg');
      await original.writeAsBytes([9]);
      await prefs.setStringList('camera_staging_cleanup_v1', [original.path]);
      await CameraStagingCleanup.retryPending();
      expect(await original.readAsBytes(), [9]);
      expect(prefs.getStringList('camera_staging_cleanup_v1'), isEmpty);
    },
  );

  test('links cannot redirect staging cleanup to an original', () async {
    final original = File('${root.path}/original.jpg');
    await original.writeAsBytes([9]);
    final link = Link('${staging.path}/linked.jpg');
    try {
      await link.create(original.path);
    } on FileSystemException {
      markTestSkipped('This host does not permit creating symbolic links.');
      return;
    }
    await expectLater(
      CameraStagingCleanup.release(link.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await original.readAsBytes(), [9]);
    await link.delete();
  });

  test('overlapping cleanup requests do not lose pending paths', () async {
    final a = Directory('${staging.path}/a');
    final b = Directory('${staging.path}/b');
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
