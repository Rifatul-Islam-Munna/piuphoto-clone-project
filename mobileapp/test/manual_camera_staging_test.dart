import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:mobileapp/pages/upload/manual_camera_staging.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory temporary;
  const event = EventSummary(id: 'test-event-001', title: 'Shoot');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ManualCameraStaging.resetInMemoryForTest();
    temporary = await Directory.systemTemp.createTemp('manual-camera-inbox-');
    ManualCameraStaging.testRootDirectory = temporary;
  });

  tearDown(() async {
    ManualCameraStaging.resetInMemoryForTest();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  test(
    'USB capture is staged locally and not passed to cloud upload queue',
    () async {
      final source = File(
        '${temporary.path}${Platform.pathSeparator}photo.CR2',
      );
      await source.writeAsBytes([1, 2, 3, 4, 5], flush: true);

      final saved = await ManualCameraStaging.stageFile(
        event: event,
        path: source.path,
        filename: 'photo.CR2',
        fingerprint: 'usb|shot-1',
        source: 'usb',
        isEnhanced: false,
      );

      expect(ManualCameraStaging.pendingFor(event.id), hasLength(1));
      expect(saved.path, isNot(source.path));
      expect(await File(saved.path).readAsBytes(), [1, 2, 3, 4, 5]);
      expect(await source.exists(), isTrue);

      // A camera retransmission must not add a duplicate selection item.
      final duplicate = await ManualCameraStaging.stageFile(
        event: event,
        path: source.path,
        filename: 'photo.CR2',
        fingerprint: 'usb|shot-1',
        source: 'usb',
        isEnhanced: false,
      );
      expect(duplicate.id, saved.id);
      expect(ManualCameraStaging.pendingFor(event.id), hasLength(1));

      // The manifest survives a page/app restart.
      ManualCameraStaging.resetInMemoryForTest();
      ManualCameraStaging.testRootDirectory = temporary;
      await ManualCameraStaging.load();
      expect(ManualCameraStaging.pendingFor(event.id), hasLength(1));

      // After queue acceptance only the private review copy is removed.
      await ManualCameraStaging.markSubmitted(saved.id);
      expect(ManualCameraStaging.pendingFor(event.id), isEmpty);
      expect(await File(saved.path).exists(), isFalse);
      expect(await source.exists(), isTrue);
      expect(ManualCameraStaging.items.value.single.status, 'submitted');
    },
  );

  test(
    'unselected wireless camera photo is removed only from local review',
    () async {
      final saved = await ManualCameraStaging.stageBytes(
        event: event,
        bytes: Uint8List.fromList([11, 12, 13]),
        filename: 'shoot_002.jpg',
        fingerprint: 'wireless|shot-2',
        source: 'wireless-ftp',
        isEnhanced: true,
      );

      expect(await File(saved.path).exists(), isTrue);
      expect(
        ManualCameraStaging.pendingFor(event.id).single.filename,
        'shoot_002.jpg',
      );
      await ManualCameraStaging.discard(saved.id);
      expect(ManualCameraStaging.pendingFor(event.id), isEmpty);
      expect(await File(saved.path).exists(), isFalse);
      expect(ManualCameraStaging.items.value.single.status, 'discarded');
    },
  );

  test(
    'photos from different events do not cross into another review queue',
    () async {
      await ManualCameraStaging.stageBytes(
        event: event,
        bytes: Uint8List.fromList([1]),
        filename: 'a.jpg',
        fingerprint: 'shot-1',
        source: 'wireless',
        isEnhanced: false,
      );
      const other = EventSummary(id: 'another-event', title: 'Other');
      await ManualCameraStaging.stageBytes(
        event: other,
        bytes: Uint8List.fromList([2]),
        filename: 'b.jpg',
        fingerprint: 'shot-1',
        source: 'wireless',
        isEnhanced: false,
      );
      expect(ManualCameraStaging.pendingFor(event.id), hasLength(1));
      expect(ManualCameraStaging.pendingFor(other.id), hasLength(1));
      expect(
        ManualCameraStaging.items.value[0].id,
        isNot(ManualCameraStaging.items.value[1].id),
      );
    },
  );
}
