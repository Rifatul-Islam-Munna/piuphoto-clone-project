import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/core/upload/upload_queue_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _ControlledPreferences preferences;

  setUp(() async {
    await getIt.reset();
    preferences = _ControlledPreferences();
    getIt.registerSingleton<SharedPreferences>(preferences);
    await UploadQueueStorage.init();
  });

  tearDown(() async {
    preferences.autoComplete = true;
    for (final write in preferences.writes) {
      if (!write.result.isCompleted) write.result.complete(true);
    }
    await UploadQueueStorage.init();
    await getIt.reset();
  });

  test(
    'a captured photo is visible only after its queue write succeeds',
    () async {
      preferences.autoComplete = false;
      var accepted = false;
      final save = UploadQueueStorage.add(_item('shot-1')).then((_) {
        accepted = true;
      });

      await _settle();
      expect(preferences.writes, hasLength(1));
      expect(UploadQueueStorage.items.value, isEmpty);
      expect(accepted, isFalse);

      preferences.writes.single.result.complete(true);
      await save;

      expect(accepted, isTrue);
      expect(_queueIds(), ['shot-1']);
      expect(preferences.persistedIds, ['shot-1']);
    },
  );

  for (final removeFirst in [false, true]) {
    test('concurrent burst and upload completion preserve new shots '
        '(remove first: $removeFirst)', () async {
      await UploadQueueStorage.add(_item('uploaded'));
      preferences.writes.clear();
      preferences.autoComplete = false;

      final operations = removeFirst
          ? [
              UploadQueueStorage.remove('uploaded'),
              UploadQueueStorage.add(_item('shot-1')),
              UploadQueueStorage.add(_item('shot-2')),
            ]
          : [
              UploadQueueStorage.add(_item('shot-1')),
              UploadQueueStorage.remove('uploaded'),
              UploadQueueStorage.add(_item('shot-2')),
            ];
      final expectedSnapshots = removeFirst
          ? <List<String>>[
              [],
              ['shot-1'],
              ['shot-1', 'shot-2'],
            ]
          : <List<String>>[
              ['uploaded', 'shot-1'],
              ['shot-1'],
              ['shot-1', 'shot-2'],
            ];

      for (var index = 0; index < expectedSnapshots.length; index++) {
        await _settle();
        // A later mutation must wait for the preceding persistence result.
        expect(preferences.writes, hasLength(index + 1));
        expect(preferences.writes[index].ids, expectedSnapshots[index]);
        preferences.writes[index].result.complete(true);
        await operations[index];
      }

      await Future.wait(operations);
      expect(_queueIds(), ['shot-1', 'shot-2']);
      expect(preferences.persistedIds, ['shot-1', 'shot-2']);
      await UploadQueueStorage.init();
      expect(_queueIds(), ['shot-1', 'shot-2']);
    });
  }

  test(
    'a false write result rejects capture acceptance and preserves the queue',
    () async {
      await UploadQueueStorage.add(_item('existing'));
      preferences.writes.clear();
      preferences.autoComplete = false;

      final failedSave = UploadQueueStorage.add(_item('not-saved'));
      final failure = expectLater(failedSave, throwsStateError);
      final nextSave = UploadQueueStorage.add(_item('next-shot'));

      await _settle();
      preferences.writes[0].result.complete(false);
      await failure;
      await _settle();

      expect(_queueIds(), ['existing']);
      expect(preferences.persistedIds, ['existing']);
      expect(preferences.writes, hasLength(2));
      expect(preferences.writes[1].ids, ['existing', 'next-shot']);

      preferences.writes[1].result.complete(true);
      await nextSave;
      expect(_queueIds(), ['existing', 'next-shot']);
      expect(preferences.persistedIds, ['existing', 'next-shot']);
    },
  );

  test(
    'a thrown persistence error does not poison subsequent mutations',
    () async {
      preferences.autoComplete = false;
      final failedSave = UploadQueueStorage.add(_item('not-saved'));
      final failure = expectLater(failedSave, throwsA(isA<Exception>()));
      final nextSave = UploadQueueStorage.add(_item('next-shot'));

      await _settle();
      preferences.writes[0].result.completeError(Exception('Disk unavailable'));
      await failure;
      await _settle();

      expect(_queueIds(), isEmpty);
      expect(preferences.writes, hasLength(2));
      expect(preferences.writes[1].ids, ['next-shot']);

      preferences.writes[1].result.complete(true);
      await nextSave;
      expect(_queueIds(), ['next-shot']);
      expect(preferences.persistedIds, ['next-shot']);
    },
  );

  test(
    'retry metadata update does not overwrite a concurrently added shot',
    () async {
      final retry = _item('retry');
      await UploadQueueStorage.add(retry);
      preferences.writes.clear();
      preferences.autoComplete = false;

      final add = UploadQueueStorage.add(_item('new-shot'));
      final update = UploadQueueStorage.update(retry.copyWith(attempts: 1));
      await _settle();
      preferences.writes[0].result.complete(true);
      await add;
      await _settle();

      expect(preferences.writes, hasLength(2));
      expect(preferences.writes[1].ids, ['retry', 'new-shot']);
      preferences.writes[1].result.complete(true);
      await update;

      expect(_queueIds(), ['retry', 'new-shot']);
      expect(UploadQueueStorage.items.value.first.attempts, 1);
      expect(preferences.persistedIds, ['retry', 'new-shot']);
    },
  );

  test('fingerprint lookup respects the event and camera source', () async {
    await UploadQueueStorage.add(
      PendingUploadItem.fromJson({
        ..._item('other-event').toJson(),
        'eventId': 'event-2',
        'fingerprint': 'same-camera-photo',
      }),
    );
    await UploadQueueStorage.add(
      PendingUploadItem.fromJson({
        ..._item('other-source').toJson(),
        'source': 'wifi',
        'fingerprint': 'same-camera-photo',
      }),
    );
    await UploadQueueStorage.add(
      PendingUploadItem.fromJson({
        ..._item('matching').toJson(),
        'fingerprint': 'same-camera-photo',
      }),
    );

    expect(
      UploadQueueStorage.findByFingerprint(
        'same-camera-photo',
        eventId: 'event-1',
        source: 'usb',
      )?.id,
      'matching',
    );
    expect(
      UploadQueueStorage.findByFingerprint(
        'same-camera-photo',
        eventId: 'event-3',
        source: 'usb',
      ),
      isNull,
    );
  });

  test('cancellation survives restart before pending-row removal', () async {
    final photo = _item('cancelled-shot');
    await UploadQueueStorage.add(photo);
    await UploadQueueStorage.markCancelled(photo.id);

    // Simulate termination between the durable decision and queue cleanup.
    await UploadQueueStorage.init();
    expect(UploadQueueStorage.isCancelled(photo.id), isTrue);
    expect(_queueIds(), isEmpty);

    await UploadQueueStorage.add(photo);
    await UploadQueueStorage.update(photo.copyWith(attempts: 1));
    expect(_queueIds(), isEmpty);
    expect(preferences.persistedIds, isEmpty);
  });

  test(
    'failed cancellation persistence leaves the durable queue intact',
    () async {
      await UploadQueueStorage.add(_item('keep-shot'));
      preferences.writes.clear();
      preferences.autoComplete = false;
      final cancellation = UploadQueueStorage.markCancelled('keep-shot');
      final failure = expectLater(cancellation, throwsStateError);

      await _settle();
      expect(UploadQueueStorage.isCancelled('keep-shot'), isFalse);
      preferences.writes.single.result.complete(false);
      await failure;
      expect(UploadQueueStorage.isCancelled('keep-shot'), isFalse);
      expect(_queueIds(), ['keep-shot']);
      expect(preferences.persistedIds, ['keep-shot']);

      preferences.autoComplete = true;
      await UploadQueueStorage.markCancelled('keep-shot');
      await UploadQueueStorage.remove('keep-shot');
      expect(UploadQueueStorage.isCancelled('keep-shot'), isTrue);
      expect(_queueIds(), isEmpty);
    },
  );

  test(
    'camera review deadline is persisted independently of retry time',
    () async {
      await UploadQueueStorage.add(
        _item('review-shot').copyWith(uploadAfter: 5000, nextRetryAt: 9000),
      );
      await UploadQueueStorage.init();
      final restored = UploadQueueStorage.items.value.single;
      expect(restored.uploadAfter, 5000);
      expect(restored.nextRetryAt, 9000);
      expect(restored.copyWith(attempts: 1).uploadAfter, 5000);
    },
  );
}

PendingUploadItem _item(String id) => PendingUploadItem(
  id: id,
  eventId: 'event-1',
  eventTitle: 'Live shoot',
  localPath: '/queue/$id.jpg',
  filename: '$id.jpg',
  source: 'usb',
  isEnhanced: false,
  createdAt: 1,
  fingerprint: 'event-1|camera-1|$id',
);

List<String> _queueIds() =>
    UploadQueueStorage.items.value.map((item) => item.id).toList();

Future<void> _settle() => Future<void>.delayed(Duration.zero);

class _PendingWrite {
  _PendingWrite(this.key, this.value);

  final String key;
  final String value;
  final Completer<bool> result = Completer<bool>();

  List<String> get ids => _decodeIds(value);
}

// Control the actual persistence boundary without a platform channel or an
// extra mocking package. This also lets tests emulate a full/failed disk.
class _ControlledPreferences implements SharedPreferences {
  final Map<String, String> _stored = {};
  final List<_PendingWrite> writes = [];
  bool autoComplete = true;

  List<String> get persistedIds =>
      _decodeIds(_stored['pending_upload_queue'] ?? '[]');

  @override
  String? getString(String key) => _stored[key];

  @override
  Future<bool> setString(String key, String value) async {
    final write = _PendingWrite(key, value);
    writes.add(write);
    if (autoComplete) write.result.complete(true);
    final saved = await write.result.future;
    if (saved) _stored[key] = value;
    return saved;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected preferences call: ${invocation.memberName}',
  );
}

List<String> _decodeIds(String value) => (jsonDecode(value) as List)
    .map((item) => (item as Map)['id'] as String)
    .toList();
