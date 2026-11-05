import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:mobileapp/core/platform/ptp_tether_camera.dart';
import 'package:mobileapp/core/platform/ptp_tether_link.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('physical camera tether workflows', () {
    test(
      'Canon enables EOS events, confirms card recording and imports only new shots',
      () async {
        final link = _CameraLink(_Brand.canon)..canonDestination = 4;
        link.addCard(1, const _Photo('OLD.JPG', 4));
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('canon');
          await link.dispose();
        });

        final session = await camera.start('canon');
        expect(session.baselineCount, 1);
        expect(session.uploadMode, LiveCameraUploadMode.newShotsOnly);
        expect(session.physicalShutter, 'unknown');
        expect(link.canonDestination, 1);
        expect(
          link.calls.where((call) => call.opcode == 0x9114).single.params,
          [1],
        );
        expect(
          link.calls.where((call) => call.opcode == 0x9115).single.params,
          [1],
        );
        expect(link.calls.where((call) => call.opcode == 0x9110).single.data, [
          12,
          0,
          0,
          0,
          0x1c,
          0xd1,
          0,
          0,
          1,
          0,
          0,
          0,
        ]);
        expect(await camera.pending('canon'), isEmpty);
        expect(link.metadataHandles, isEmpty);

        link.addCard(2, const _Photo('NEW.JPG', 6));
        final shot = (await camera.pending('canon')).single;
        expect(shot.name, 'NEW.JPG');
        final staged = await camera.download('canon', shot.id);
        expect(staged.id, shot.id);
        expect(link.downloads.single.partialOpcode, 0x101b);
        expect(link.acknowledgements, isEmpty);
        await camera.acknowledge('canon', [shot.id]);
        expect(await camera.pending('canon'), isEmpty);
        expect(link.acknowledgements.single.$2, [shot.id]);
        expect(link.calls.where((call) => call.opcode == 0x9117), isEmpty);
        await camera.stop('canon');
        expect(
          link.calls
              .where((call) => call.opcode == 0x9114)
              .map((call) => call.params),
          [
            [1],
            [0],
            [1],
          ],
        );
        expect(link.calls.where((call) => call.opcode == 0x9115).last.params, [
          0,
        ]);
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'Canon refuses host-only recording without an advertised card choice',
      () async {
        final link = _CameraLink(_Brand.canon)
          ..canonDestination = 4
          ..canonChoices = [4];
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('bad-card'),
          _error('TETHER_CARD_RECORDING_REQUIRED'),
        );
        expect(link.calls.where((call) => call.opcode == 0x9110), isEmpty);
        expect(link.downloads, isEmpty);
        expect(link.closed, contains('bad-card'));
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'a successful Canon write response needs matching property readback',
      () async {
        final link = _CameraLink(_Brand.canon)
          ..canonDestination = 4
          ..acceptPropertyWrites = false;
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('unconfirmed'),
          _error('TETHER_MODE_NOT_CONFIRMED'),
        );
        expect(link.canonDestination, 4);
        expect(link.downloads, isEmpty);
        expect(link.calls.where((call) => call.opcode == 0x1007), isEmpty);
        expect(link.closed, contains('unconfirmed'));
      },
    );

    test(
      'Canon host transfer completion follows the caller durable-save ACK',
      () async {
        final link = _CameraLink(_Brand.canon);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('host');
          await link.dispose();
        });
        await camera.start('host');
        link.objects[70] = const _Photo('HOST.JPG', 8);
        link.canonObjectEvents.add(_canonTransfer(70));
        final shot = (await camera.pending('host')).single;
        await camera.download('host', shot.id);
        expect(link.calls.where((call) => call.opcode == 0x9117), isEmpty);
        expect((await camera.pending('host')).single.id, shot.id);
        await camera.acknowledge('host', [shot.id]);
        expect(
          link.calls.where((call) => call.opcode == 0x9117).single.params,
          [70],
        );
        expect(
          link.timeline.indexOf('download:70'),
          lessThan(link.timeline.indexOf('command:9117')),
        );
        expect(
          link.timeline.indexOf('command:9117'),
          lessThan(link.timeline.indexOf('ack:host')),
        );
      },
    );

    test(
      'verified Canon C186 metadata covers RAM handles that reject ObjectInfo',
      () async {
        for (final response in [0x2009, 0x2005]) {
          final link = _CameraLink(_Brand.canon)
            ..metadataRejections[70] = response;
          final camera = _transport(link);
          addTearDown(() async {
            await camera.stop('host-metadata');
            await link.dispose();
          });
          await camera.start('host-metadata');
          link.canonObjectEvents.add(_canonTransfer(70));
          final shot = (await camera.pending('host-metadata')).single;
          expect(shot.name, 'HOST.JPG');
          expect(shot.size, 8);
          expect(link.metadataHandles, [70]);
          await camera.download('host-metadata', shot.id);
          // An event-backed RAM object must not repeat the unsupported metadata
          // command before the verified-length native download.
          expect(link.metadataHandles, [70]);
          expect(link.downloads.single.expectedSize, 8);
          expect(link.downloads.single.partialOpcode, 0x101b);
          expect(link.calls.where((call) => call.opcode == 0x9117), isEmpty);
          await camera.acknowledge('host-metadata', [shot.id]);
          expect(
            link.calls.where((call) => call.opcode == 0x9117).single.params,
            [70],
          );
          await camera.stop('host-metadata');
          await link.dispose();
        }
      },
    );

    test(
      'Canon event metadata cannot bypass access denial or guess a 64-bit object size',
      () async {
        for (final scenario in [(0x200f, 0xc186), (0x2009, 0xc1a9)]) {
          final link = _CameraLink(_Brand.canon)
            ..metadataRejections[70] = scenario.$1;
          final camera = _transport(link);
          addTearDown(() async {
            await camera.stop('host-denied');
            await link.dispose();
          });
          await camera.start('host-denied');
          final event = _canonTransfer(70);
          ByteData.sublistView(event).setUint32(4, scenario.$2, Endian.little);
          link.canonObjectEvents.add(event);
          await expectLater(
            camera.pending('host-denied'),
            _error('PTP_COMMAND_REJECTED'),
          );
          expect(link.downloads, isEmpty);
          expect(link.calls.where((call) => call.opcode == 0x9117), isEmpty);
          await camera.stop('host-denied');
          await link.dispose();
        }
      },
    );

    test(
      'Nikon selects body mode zero and reconciles a complete multi-card burst',
      () async {
        final link = _CameraLink(_Brand.nikon);
        link.addCard(1, const _Photo('OLD.JPG', 4));
        link.storages[2] = [];
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('nikon');
          await link.dispose();
        });
        await camera.start('nikon');
        expect(
          link.calls.where((call) => call.opcode == 0x90c2).single.params,
          [0],
        );
        for (var handle = 10; handle < 85; handle++) {
          link.addCard(
            handle,
            _Photo('BURST$handle.JPG', 8),
            storage: handle.isEven ? 1 : 2,
          );
        }
        final shots = await camera.pending('nikon');
        expect(shots, hasLength(75));
        expect(link.metadataHandles.contains(1), isFalse);
        expect(
          (await camera.pending('nikon')).map((shot) => shot.id).toSet(),
          shots.map((shot) => shot.id).toSet(),
        );
        await camera.download('nikon', shots.first.id);
        await camera.acknowledge('nikon', [shots.first.id]);
        expect(await camera.pending('nikon'), hasLength(74));
        expect(link.calls.where((call) => call.opcode == 0x9117), isEmpty);
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'Nikon vendor events produce new card shots without Canon completion commands',
      () async {
        final link = _CameraLink(_Brand.nikon);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('nikon-events');
          await link.dispose();
        });
        await camera.start('nikon-events');
        link.addCard(9, const _Photo('NIKON.NEF', 12));
        link.nikonEvents.add((0x4002, [9]));
        final shot = (await camera.pending('nikon-events')).single;
        await camera.download('nikon-events', shot.id);
        await camera.acknowledge('nikon-events', [shot.id]);
        expect(link.calls.any((call) => call.opcode == 0x941c), isTrue);
        expect(link.calls.any((call) => call.opcode == 0x9117), isFalse);
      },
    );

    test(
      'Nikon RAM-only capture stops the card workflow without using a Canon ACK',
      () async {
        final link = _CameraLink(_Brand.nikon);
        final camera = _transport(link);
        final errorCodes = <String?>[];
        final subscription = camera.eventsForSession('nikon-ram').listen((
          event,
        ) {
          if (event.type == 'disconnected') errorCodes.add(event.code);
        });
        addTearDown(() async {
          await camera.stop('nikon-ram');
          await subscription.cancel();
          await link.dispose();
        });
        await camera.start('nikon-ram');
        link.nikonEvents.add((0xc101, [0xffff0001]));
        await expectLater(
          camera.pending('nikon-ram'),
          _error('USB_CAMERA_DISCONNECTED'),
        );
        await Future<void>.value();
        expect(errorCodes, contains('TETHER_MODE_CHANGED'));
        expect(link.metadataHandles, isEmpty);
        expect(link.downloads, isEmpty);
        expect(link.calls.any((call) => call.opcode == 0x9117), isFalse);
      },
    );

    test(
      'Sony handshake uses Camera priority and PC plus camera recording',
      () async {
        final link = _CameraLink(_Brand.sony)
          ..sonyPriority = 1
          ..sonyDestination = 1;
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('sony');
          await link.dispose();
        });
        await camera.start('sony');
        expect(
          link.calls
              .where((call) => call.opcode == 0x9201)
              .map((call) => call.params),
          [
            [1, 0, 0],
            [2, 0, 0],
            [3, 0, 0],
          ],
        );
        expect(
          link.calls.where((call) => call.opcode == 0x9202).single.params,
          [0x12c, 1],
        );
        final writes = link.calls
            .where((call) => call.opcode == 0x9205)
            .toList();
        expect(writes.map((call) => call.params), [
          [0xd222],
          [0xd25a],
        ]);
        expect(writes[0].data, [17, 0]);
        expect(writes[1].data, [0]);
        expect(link.sonyDestination, 17);
        expect(link.sonyPriority, 0);
        await camera.stop('sony');
        expect(link.calls.where((call) => call.opcode == 0x9205), hasLength(2));
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'Sony transient buffer state never downloads and fixed handle gets distinct delivery IDs',
      () async {
        final link = _CameraLink(_Brand.sony);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('sony-queue');
          await link.dispose();
        });
        await camera.start('sony-queue');
        link.sonyMemoryOverride = 1;
        expect(await camera.pending('sony-queue'), isEmpty);
        expect(link.metadataHandles, isEmpty);
        expect(link.downloads, isEmpty);
        link.sonyMemoryOverride = null;
        link.sonyMemory.addAll([
          const _Photo('SAME.JPG', 8),
          const _Photo('SAME.JPG', 8),
        ]);
        final first = (await camera.pending('sony-queue')).single;
        final staged = await camera.download('sony-queue', first.id);
        expect(link.sonyMemory, hasLength(1));
        expect(link.downloads.single.handle, 0xffffc001);
        expect(link.downloads.single.partialOpcode, isNull);
        expect(
          (await camera.download('sony-queue', first.id)).path,
          staged.path,
        );
        expect(link.downloads, hasLength(1));
        expect((await camera.pending('sony-queue')).single.id, first.id);
        await camera.acknowledge('sony-queue', [first.id]);
        final second = (await camera.pending('sony-queue')).single;
        expect(second.id, isNot(first.id));
        expect(second.name, first.name);
        await camera.download('sony-queue', second.id);
        expect(link.downloads, hasLength(2));
        await camera.acknowledge('sony-queue', [second.id]);
        expect(await camera.pending('sony-queue'), isEmpty);
        expect(link.calls.where((call) => call.opcode == 0x9117), isEmpty);
      },
    );

    test(
      'Sony retries empty warm-up capability replies before arming',
      () async {
        final link = _CameraLink(_Brand.sony);
        link.sonyExtensionReplies.addAll([
          Uint8List(0),
          Uint8List.fromList([
            ..._u16(0x12c),
            ..._array16([]),
            ..._array16([]),
          ]),
        ]);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('sony-warm-up');
          await link.dispose();
        });
        await camera.start('sony-warm-up');
        expect(link.calls.where((call) => call.opcode == 0x9202), hasLength(3));
        expect(link.calls.where((call) => call.opcode == 0x9201).last.params, [
          3,
          0,
          0,
        ]);
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'Sony empty capability retries are bounded and never imply ready',
      () async {
        final link = _CameraLink(_Brand.sony);
        link.sonyExtensionReplies.addAll(
          List.generate(20, (_) => Uint8List(0)),
        );
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('sony-empty'),
          _error('TETHER_MODE_NOT_CONFIRMED'),
        );
        expect(
          link.calls.where((call) => call.opcode == 0x9202),
          hasLength(20),
        );
        expect(link.calls.where((call) => call.opcode == 0x9205), isEmpty);
        expect(link.closed, contains('sony-empty'));
      },
    );

    test(
      'Sony malformed nonempty capabilities fail instead of retrying as empty',
      () async {
        final link = _CameraLink(_Brand.sony);
        link.sonyExtensionReplies.add(Uint8List.fromList([1]));
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('sony-malformed'),
          throwsA(isA<FormatException>()),
        );
        expect(link.calls.where((call) => call.opcode == 0x9202), hasLength(1));
        expect(link.calls.where((call) => call.opcode == 0x9205), isEmpty);
        expect(link.closed, contains('sony-malformed'));
      },
    );

    test(
      'Sony old RAM photos are never silently read, discarded or uploaded',
      () async {
        final link = _CameraLink(_Brand.sony)
          ..sonyPriority = 1
          ..sonyDestination = 1;
        link.sonyMemory.add(const _Photo('PREVIOUS.JPG', 8));
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('old-sony'),
          _error('TETHER_PREVIOUS_PHOTOS_PENDING'),
        );
        expect(link.sonyMemory, hasLength(1));
        expect(link.metadataHandles, isEmpty);
        expect(link.downloads, isEmpty);
        expect(link.calls.where((call) => call.opcode == 0x9205), isEmpty);
      },
    );

    test(
      'Sony in-progress pre-session capture cannot become a clean baseline',
      () async {
        final link = _CameraLink(_Brand.sony)..sonyMemoryOverride = 1;
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(camera.start('sony-busy'), _error('CAMERA_BUSY'));
        expect(link.metadataHandles, isEmpty);
        expect(link.downloads, isEmpty);
        expect(link.calls.where((call) => call.opcode == 0x9205), isEmpty);
      },
    );

    test(
      'Sony never guesses a destination that is absent from the advertised choices',
      () async {
        final link = _CameraLink(_Brand.sony)
          ..sonyDestination = 1
          ..sonyDestinationChoices = [1, 16];
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('sony-choice'),
          _error('TETHER_CAMERA_SETTING_REQUIRED'),
        );
        expect(link.calls.where((call) => call.opcode == 0x9205), isEmpty);
        expect(link.downloads, isEmpty);
      },
    );

    test(
      'Sony readback failure never publishes a ready shooting session',
      () async {
        final link = _CameraLink(_Brand.sony)
          ..sonyDestination = 1
          ..acceptPropertyWrites = false;
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('sony-readback'),
          _error('TETHER_MODE_NOT_CONFIRMED'),
        );
        expect(link.closed, contains('sony-readback'));
        expect(link.downloads, isEmpty);
      },
    );

    test(
      'a missing consumed Sony staging file cannot consume the next image',
      () async {
        final link = _CameraLink(_Brand.sony);
        var stagedExists = true;
        final camera = _transport(
          link,
          stagedExists: (_) async => stagedExists,
        );
        addTearDown(() async {
          await camera.stop('sony-missing');
          await link.dispose();
        });
        await camera.start('sony-missing');
        link.sonyMemory.addAll([
          const _Photo('ONE.JPG', 8),
          const _Photo('TWO.JPG', 8),
        ]);
        final first = (await camera.pending('sony-missing')).single;
        await camera.download('sony-missing', first.id);
        stagedExists = false;
        await expectLater(
          camera.download('sony-missing', first.id),
          _error('PTP_STAGED_FILE_MISSING'),
        );
        expect(link.downloads, hasLength(1));
        expect(link.sonyMemory.single.name, 'TWO.JPG');
      },
    );

    test(
      'card file growth refreshes transfer length without changing its delivery ID',
      () async {
        final link = _CameraLink(_Brand.nikon);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('growth');
          await link.dispose();
        });
        await camera.start('growth');
        link.addCard(5, const _Photo('GROW.JPG', 4));
        final first = (await camera.pending('growth')).single;
        link.objects[5] = const _Photo('GROW.JPG', 16);
        final file = await camera.download('growth', first.id);
        expect(file.id, first.id);
        expect(link.downloads.single.expectedSize, 16);
        final refreshed = (await camera.pending('growth')).single;
        expect(refreshed.id, first.id);
        expect(refreshed.size, 16);
      },
    );

    test(
      'zero-length files remain retryable until camera metadata is complete',
      () async {
        final link = _CameraLink(_Brand.nikon);
        var now = DateTime.utc(2026, 11, 6);
        final camera = _transport(link, now: () => now);
        addTearDown(() async {
          await camera.stop('writing');
          await link.dispose();
        });
        await camera.start('writing');
        link.addCard(5, const _Photo('WRITING.JPG', 0));
        expect(await camera.pending('writing'), isEmpty);
        link.objects[5] = const _Photo('WRITING.JPG', 8);
        now = now.add(const Duration(milliseconds: 500));
        expect((await camera.pending('writing')).single.name, 'WRITING.JPG');
      },
    );

    test(
      'temporary filenames retry without blocking other complete photos',
      () async {
        final link = _CameraLink(_Brand.nikon);
        var now = DateTime.utc(2026, 11, 6);
        final camera = _transport(link, now: () => now);
        addTearDown(() async {
          await camera.stop('temporary');
          await link.dispose();
        });
        await camera.start('temporary');
        link.addCard(5, const _Photo('WRITING.TMP', 4));
        link.addCard(6, const _Photo('READY.JPG', 8));
        expect((await camera.pending('temporary')).single.name, 'READY.JPG');
        link.objects[5] = const _Photo('FINISHED.JPG', 12);
        now = now.add(const Duration(milliseconds: 500));
        expect(
          (await camera.pending('temporary')).map((shot) => shot.name).toSet(),
          {'FINISHED.JPG', 'READY.JPG'},
        );
      },
    );

    for (final response in [0x2009, 0x2019]) {
      test(
        'one pending metadata response $response cannot stall the next burst shot',
        () async {
          final link = _CameraLink(_Brand.nikon);
          var now = DateTime.utc(2026, 11, 6);
          final camera = _transport(link, now: () => now);
          addTearDown(() async {
            await camera.stop('metadata-$response');
            await link.dispose();
          });
          await camera.start('metadata-$response');
          link.addCard(5, const _Photo('FIRST.JPG', 8));
          link.addCard(6, const _Photo('READY.JPG', 8));
          link.metadataRejections[5] = response;
          expect(
            (await camera.pending('metadata-$response')).single.name,
            'READY.JPG',
          );
          expect(
            link.metadataHandles.where((handle) => handle == 5),
            hasLength(1),
          );
          // No busy-loop or repeated multi-attempt command while this entry waits.
          await camera.pending('metadata-$response');
          expect(
            link.metadataHandles.where((handle) => handle == 5),
            hasLength(1),
          );
          link.metadataRejections.remove(5);
          now = now.add(const Duration(milliseconds: 500));
          expect(
            (await camera.pending(
              'metadata-$response',
            )).map((shot) => shot.name).toSet(),
            {'FIRST.JPG', 'READY.JPG'},
          );
        },
      );
    }

    test(
      'a stale missing-object event is retired after the next complete card scan',
      () async {
        final link = _CameraLink(_Brand.nikon);
        var now = DateTime.utc(2026, 11, 6);
        final camera = _transport(link, now: () => now);
        addTearDown(() async {
          await camera.stop('stale-object');
          await link.dispose();
        });
        await camera.start('stale-object');
        link.addCard(5, const _Photo('REMOVED.JPG', 8));
        link.metadataRejections[5] = 0x2009;
        expect(await camera.pending('stale-object'), isEmpty);
        link.storages[1]!.remove(5);
        link.objects.remove(5);
        link.addCard(6, const _Photo('NEXT.JPG', 8));
        expect((await camera.pending('stale-object')).single.name, 'NEXT.JPG');
        now = now.add(const Duration(seconds: 20));
        await camera.pending('stale-object');
        expect(
          link.metadataHandles.where((handle) => handle == 5),
          hasLength(1),
        );
      },
    );

    test('a new completion event bypasses incomplete-photo backoff', () async {
      final link = _CameraLink(_Brand.nikon);
      final camera = _transport(link, now: () => DateTime.utc(2026, 11, 6));
      addTearDown(() async {
        await camera.stop('completion-event');
        await link.dispose();
      });
      await camera.start('completion-event');
      link.addCard(5, const _Photo('WRITING.TMP', 0));
      expect(await camera.pending('completion-event'), isEmpty);
      await camera.pending('completion-event');
      expect(link.metadataHandles, [5]);
      link.objects[5] = const _Photo('READY.JPG', 8);
      link.nikonEvents.add((0x4002, [5]));
      expect(
        (await camera.pending('completion-event')).single.name,
        'READY.JPG',
      );
      expect(link.metadataHandles, [5, 5]);
    });

    test(
      'metadata isolation never swallows native transport or framing errors',
      () async {
        for (final code in [
          'PTP_TIMEOUT',
          'PTP_INVALID_RESPONSE',
          'PTP_TRANSPORT_FAILED',
        ]) {
          final link = _CameraLink(_Brand.nikon);
          final camera = _transport(link);
          try {
            await camera.start('fatal-$code');
            link.addCard(5, const _Photo('FIRST.JPG', 8));
            link.addCard(6, const _Photo('SECOND.JPG', 8));
            link.metadataFailures[5] = PlatformException(code: code);
            await expectLater(camera.pending('fatal-$code'), _error(code));
            expect(link.metadataHandles, [5]);
            expect(link.downloads, isEmpty);
          } finally {
            await camera.stop('fatal-$code');
            await link.dispose();
          }
        }
      },
    );

    test(
      'a card swap cannot reinterpret the new card as newly captured photos',
      () async {
        final link = _CameraLink(_Brand.nikon);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('swap');
          await link.dispose();
        });
        await camera.start('swap');
        link.storages.clear();
        link.addCard(1, const _Photo('OTHER_CARD_OLD.JPG', 8), storage: 2);
        await expectLater(
          camera.pending('swap'),
          _error('CAMERA_STORAGE_CHANGED'),
        );
        expect(link.metadataHandles, isEmpty);
        expect(link.downloads, isEmpty);
      },
    );

    test(
      'a newly inserted empty card is a valid baseline, absence of a card is not',
      () async {
        final link = _CameraLink(_Brand.nikon);
        final camera = _transport(link);
        addTearDown(link.dispose);
        expect((await camera.start('empty')).baselineCount, 0);
        await camera.stop('empty');
        link.storages.clear();
        await expectLater(
          camera.start('missing'),
          _error('TETHER_CARD_RECORDING_REQUIRED'),
        );
      },
    );

    test(
      'unknown cameras and unsupported EOS M never receive guessed mode commands',
      () async {
        for (final link in [
          _CameraLink(_Brand.unknown),
          _CameraLink(_Brand.canon)..model = 'Canon EOS M50',
        ]) {
          final camera = _transport(link);
          await expectLater(
            camera.start('unsupported'),
            _error('TETHER_CAMERA_UNSUPPORTED'),
          );
          expect(link.calls.map((call) => call.opcode).toSet(), {0x1001});
          expect(link.closed, contains('unsupported'));
          await link.dispose();
        }
      },
    );

    test(
      'a camera brand cannot authorize an unadvertised vendor mode command',
      () async {
        final link = _CameraLink(_Brand.canon)
          ..unavailableOperations.add(0x9114);
        final camera = _transport(link);
        addTearDown(link.dispose);
        await expectLater(
          camera.start('missing-operation'),
          _error('TETHER_MODE_UNSUPPORTED'),
        );
        expect(link.calls.map((call) => call.opcode).toSet(), {0x1001});
        expect(link.downloads, isEmpty);
      },
    );

    for (final (vendor, brand, mode) in [
      (0x04cb, 'Fujifilm', 'USB TETHER SHOOTING AUTO'),
      (0x04da, 'Panasonic / LUMIX', 'PC(Tether)'),
      (0x33a2, 'OM SYSTEM / Olympus', 'PC-control tether adapter'),
      (0x25fb, 'Pentax / Ricoh', 'PTP/MTP'),
    ]) {
      test(
        '$brand is identified automatically without claiming an unsupported adapter',
        () async {
          final link = _CameraLink(_Brand.unknown)
            ..vendorIdOverride = vendor
            ..model = 'Detected body';
          final camera = _transport(link);
          addTearDown(link.dispose);
          await expectLater(
            camera.start('identified-$vendor'),
            throwsA(
              isA<PlatformException>()
                  .having(
                    (error) => error.code,
                    'code',
                    'TETHER_CAMERA_UNSUPPORTED',
                  )
                  .having(
                    (error) => error.message,
                    'message',
                    allOf(
                      contains(brand),
                      contains(mode),
                      contains('does not yet provide'),
                    ),
                  ),
            ),
          );
          expect(link.calls.map((call) => call.opcode).toSet(), {0x1001});
          expect(link.closed, contains('identified-$vendor'));
        },
      );
    }

    for (final mode in LiveCameraUploadMode.values) {
      test(
        'native shutter support cannot bypass Fuji buffer handling in ${mode.name}',
        () async {
          final link = _CameraLink(_Brand.unknown)
            ..vendorIdOverride = 0x04cb
            ..physicalShutter = 'supported'
            ..model = 'X-T5';
          final camera = _transport(link, uploadMode: mode);
          addTearDown(link.dispose);
          await expectLater(
            camera.start('fuji-native'),
            _error('TETHER_CAMERA_UNSUPPORTED'),
          );
          expect(link.calls.map((call) => call.opcode), [0x1001]);
          expect(link.downloads, isEmpty);
          expect(link.closed, contains('fuji-native'));
          _expectNoCaptureOrLock(link);
        },
      );
    }

    test(
      'non-Fuji native shutter support retains the standard card adapter',
      () async {
        final link = _CameraLink(_Brand.unknown)..physicalShutter = 'supported';
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('native-card');
          await link.dispose();
        });
        await camera.start('native-card');
        link.addCard(5, const _Photo('NEW.JPG', 8));
        final image = (await camera.pending('native-card')).single;
        await camera.download('native-card', image.id);
        expect(link.downloads.single.partialOpcode, 0x101b);
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'Stop during delayed native open prevents all later camera commands',
      () async {
        final link = _CameraLink(_Brand.nikon)..openGate = Completer<void>();
        final camera = _transport(link);
        addTearDown(link.dispose);
        final starting = camera.start('late');
        final failed = expectLater(starting, _error('LIVE_CAMERA_CANCELLED'));
        await link.openStarted.future;
        await camera.stop('late');
        link.openGate!.complete();
        await failed;
        expect(link.calls, isEmpty);
        expect(link.closed, contains('late'));
        link.openGate = null;
        await camera.start('next');
        expect(link.calls.every((call) => call.session == 'next'), isTrue);
        await camera.stop('next');
      },
    );

    test(
      'an old-session local-save ACK cannot send a completion command into the next camera session',
      () async {
        final link = _CameraLink(_Brand.canon);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('next');
          await link.dispose();
        });
        await camera.start('old');
        link.objects[70] = const _Photo('HOST.JPG', 8);
        link.canonObjectEvents.add(_canonTransfer(70));
        final shot = (await camera.pending('old')).single;
        await camera.download('old', shot.id);
        await camera.stop('old');
        await camera.start('next');
        final commandsBeforeAck = link.calls.length;
        await camera.acknowledge('old', [shot.id]);
        expect(link.calls, hasLength(commandsBeforeAck));
        expect(link.acknowledgements.last.$1, 'old');
        expect(link.acknowledgements.last.$2, [shot.id]);
        expect(await camera.pending('next'), isEmpty);
      },
    );

    test(
      'detach prevents new commands but permits exact-token release of a staged photo',
      () async {
        final link = _CameraLink(_Brand.canon);
        final camera = _transport(link);
        addTearDown(() async {
          await camera.stop('detached');
          await link.dispose();
        });
        await camera.start('detached');
        link.addCard(1, const _Photo('NEW.JPG', 8));
        final shot = (await camera.pending('detached')).single;
        await camera.download('detached', shot.id);
        link.eventsController.add({
          'sessionId': 'detached',
          'type': 'disconnected',
        });
        final commandsBeforeAck = link.calls.length;
        await camera.acknowledge('detached', [shot.id]);
        expect(link.calls, hasLength(commandsBeforeAck));
        expect(link.acknowledgements.last.$2, [shot.id]);
        await expectLater(
          camera.pending('detached'),
          _error('USB_CAMERA_DISCONNECTED'),
        );
      },
    );
  });

  group('USB upload modes', () {
    for (final brand in [_Brand.canon, _Brand.nikon]) {
      test(
        '${brand.name} receives existing photos and every later shot in the same shooting session',
        () async {
          final link = _CameraLink(brand);
          link.addCard(1, const _Photo('OLD.JPG', 4));
          link.addCard(2, const _Photo('OLDER.NEF', 8));
          final camera = _transport(
            link,
            uploadMode: LiveCameraUploadMode.existingAndNew,
          );
          addTearDown(() async {
            await camera.stop('all-${brand.name}');
            await link.dispose();
          });
          final id = 'all-${brand.name}';
          final session = await camera.start(id);
          expect(session.uploadMode, LiveCameraUploadMode.existingAndNew);
          expect(session.baselineCount, 2);
          expect(session.message, contains('Existing photos'));
          // Startup enumerates handles without reading every old photo's info.
          expect(link.metadataHandles, isEmpty);
          expect((await camera.pending(id)).map((photo) => photo.name), [
            'OLD.JPG',
            'OLDER.NEF',
          ]);

          link.addCard(3, const _Photo('NEW.JPG', 12));
          final pending = await camera.pending(id);
          expect(pending.map((photo) => photo.name), [
            'NEW.JPG',
            'OLD.JPG',
            'OLDER.NEF',
          ]);
          for (final photo in pending) {
            await camera.download(id, photo.id);
            await camera.acknowledge(id, [photo.id]);
          }
          expect(await camera.pending(id), isEmpty);
          expect(link.downloads.map((photo) => photo.handle), [3, 1, 2]);
          expect(link.acknowledgements, hasLength(3));
          _expectNoCaptureOrLock(link);
        },
      );
    }

    test(
      'large initial cards use bounded batches and give new shots priority',
      () async {
        final link = _CameraLink(_Brand.nikon);
        for (var handle = 1; handle <= 4096; handle++) {
          link.addCard(handle, _Photo('OLD$handle.JPG', 8));
        }
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        addTearDown(() async {
          await camera.stop('large-card');
          await link.dispose();
        });
        final session = await camera.start('large-card');
        expect(session.baselineCount, 4096);
        expect(link.metadataHandles, isEmpty);
        expect(await camera.pending('large-card'), hasLength(8));
        expect(link.metadataHandles, hasLength(8));
        for (var check = 0; check < 6; check++) {
          await camera.pending('large-card');
        }
        // Slow downloads cannot make the timer index all 4,096 photos at once.
        expect(link.metadataHandles, hasLength(32));

        link.addCard(5000, const _Photo('SHUTTER.JPG', 16));
        link.nikonEvents.add((0x4002, [5000]));
        final pending = await camera.pending('large-card');
        expect(pending, hasLength(33));
        expect(pending.first.name, 'SHUTTER.JPG');
        expect(link.metadataHandles.last, 5000);
        await camera.download('large-card', pending.first.id);
        await camera.acknowledge('large-card', [pending.first.id]);
        expect((await camera.pending('large-card')).first.name, 'OLD1.JPG');
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'a pending new download cannot starve the remaining old-photo backlog',
      () async {
        final link = _CameraLink(_Brand.nikon);
        for (var handle = 1; handle <= 12; handle++) {
          link.addCard(handle, _Photo('OLD$handle.JPG', 4));
        }
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        addTearDown(() async {
          await camera.stop('backlog-fairness');
          await link.dispose();
        });
        await camera.start('backlog-fairness');
        final firstBatch = await camera.pending('backlog-fairness');
        expect(firstBatch, hasLength(8));
        link.addCard(20, const _Photo('RETRY_NEW.JPG', 8));
        expect(
          (await camera.pending('backlog-fairness')).first.name,
          'RETRY_NEW.JPG',
        );
        // Leave the new photo pending, as the controller does after a failed
        // download, and finish the old photos already available to it.
        for (final old in firstBatch) {
          await camera.download('backlog-fairness', old.id);
          await camera.acknowledge('backlog-fairness', [old.id]);
        }
        final next = await camera.pending('backlog-fairness');
        expect(next.map((photo) => photo.name), [
          'RETRY_NEW.JPG',
          'OLD9.JPG',
          'OLD10.JPG',
          'OLD11.JPG',
          'OLD12.JPG',
        ]);
      },
    );

    test(
      'a busy existing photo does not block later old files or a new shot',
      () async {
        final link = _CameraLink(_Brand.nikon);
        link.addCard(1, const _Photo('BUSY.JPG', 4));
        link.addCard(2, const _Photo('READY.JPG', 8));
        link.metadataRejections[1] = 0x2019;
        var now = DateTime.utc(2026, 11, 6);
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
          now: () => now,
        );
        addTearDown(() async {
          await camera.stop('old-busy');
          await link.dispose();
        });
        await camera.start('old-busy');
        expect((await camera.pending('old-busy')).single.name, 'READY.JPG');
        await camera.pending('old-busy');
        expect(
          link.metadataHandles.where((handle) => handle == 1),
          hasLength(1),
        );

        link.addCard(3, const _Photo('NEW.JPG', 12));
        final newer = (await camera.pending('old-busy')).first;
        expect(newer.name, 'NEW.JPG');
        await camera.download('old-busy', newer.id);
        await camera.acknowledge('old-busy', [newer.id]);
        link.metadataRejections.remove(1);
        now = now.add(const Duration(milliseconds: 500));
        expect(
          (await camera.pending('old-busy')).map((photo) => photo.name).toSet(),
          {'BUSY.JPG', 'READY.JPG'},
        );
      },
    );

    test(
      'productive non-photo batches continue promptly, retry-only batches do not spin',
      () async {
        final link = _CameraLink(_Brand.nikon);
        for (var handle = 1; handle <= 9; handle++) {
          link.addCard(handle, _Photo('FOLDER$handle', 0, format: 0x3001));
        }
        link.addCard(10, const _Photo('WAITING.JPG', 0));
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
          now: () => DateTime.utc(2026, 11, 6),
        );
        final events = <LiveCameraEvent>[];
        final subscription = camera
            .eventsForSession('non-photos')
            .listen(events.add);
        addTearDown(() async {
          await camera.stop('non-photos');
          await subscription.cancel();
          await link.dispose();
        });
        await camera.start('non-photos');
        expect(await camera.pending('non-photos'), isEmpty);
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((event) => event.type == 'photosAvailable'),
          hasLength(1),
        );
        expect(link.metadataHandles, hasLength(8));
        events.clear();
        expect(await camera.pending('non-photos'), isEmpty);
        expect(await camera.pending('non-photos'), isEmpty);
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((event) => event.type == 'photosAvailable'),
          isEmpty,
        );
        expect(
          link.metadataHandles.where((handle) => handle == 10),
          hasLength(1),
        );
      },
    );

    test(
      'an oversized old photo is reported once without blocking later old or new files',
      () async {
        final link = _CameraLink(_Brand.nikon);
        link.addCard(1, const _Photo('OVERSIZED.TIF', 512 * 1024 * 1024 + 1));
        link.addCard(2, const _Photo('VALID.JPG', 8));
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        final events = <LiveCameraEvent>[];
        final subscription = camera
            .eventsForSession('oversized-old')
            .listen(events.add);
        addTearDown(() async {
          await camera.stop('oversized-old');
          await subscription.cancel();
          await link.dispose();
        });
        await camera.start('oversized-old');
        final valid = (await camera.pending('oversized-old')).single;
        expect(valid.name, 'VALID.JPG');
        await camera.download('oversized-old', valid.id);
        await camera.acknowledge('oversized-old', [valid.id]);
        expect(await camera.pending('oversized-old'), isEmpty);
        await Future<void>.delayed(Duration.zero);
        final failures = events.where(
          (event) => event.code == 'TETHER_FILE_TOO_LARGE',
        );
        expect(failures, hasLength(1));
        expect(failures.single.message, contains('OVERSIZED.TIF'));
        expect(failures.single.message, contains('512 MB'));
        expect(
          link.metadataHandles.where((handle) => handle == 1),
          hasLength(1),
        );
        expect(link.downloads.map((photo) => photo.handle), [2]);
        expect(link.objects.containsKey(1), isTrue);

        link.addCard(3, const _Photo('NEW.JPG', 12));
        expect((await camera.pending('oversized-old')).single.name, 'NEW.JPG');
        _expectNoCaptureOrLock(link);
      },
    );

    test(
      'known sidecar files are ignored while unfinished old photos remain retryable',
      () async {
        final link = _CameraLink(_Brand.nikon);
        link.addCard(1, const _Photo('DSC_0001.XMP', 4));
        link.addCard(2, const _Photo('DSC_0001.THM', 4));
        link.addCard(3, const _Photo('WRITING.TMP', 4));
        link.addCard(4, const _Photo('PHOTO.JPG', 8));
        var now = DateTime.utc(2026, 11, 6);
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
          now: () => now,
        );
        addTearDown(() async {
          await camera.stop('sidecars');
          await link.dispose();
        });
        await camera.start('sidecars');
        expect((await camera.pending('sidecars')).single.name, 'PHOTO.JPG');
        await camera.pending('sidecars');
        expect(link.metadataHandles.where((handle) => handle <= 2), [1, 2]);
        link.objects[3] = const _Photo('FINISHED.JPG', 12);
        now = now.add(const Duration(milliseconds: 500));
        expect(
          (await camera.pending('sidecars')).map((photo) => photo.name).toSet(),
          {'PHOTO.JPG', 'FINISHED.JPG'},
        );
        expect(link.metadataHandles.where((handle) => handle <= 2), [1, 2]);
      },
    );

    test(
      'acknowledging a batch requests the next existing photos immediately',
      () async {
        final link = _CameraLink(_Brand.canon);
        for (var handle = 1; handle <= 10; handle++) {
          link.addCard(handle, _Photo('OLD$handle.JPG', 4));
        }
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        final events = <LiveCameraEvent>[];
        final subscription = camera
            .eventsForSession('backlog-ack')
            .listen(events.add);
        addTearDown(() async {
          await camera.stop('backlog-ack');
          await subscription.cancel();
          await link.dispose();
        });
        await camera.start('backlog-ack');
        final first = (await camera.pending('backlog-ack')).first;
        await camera.download('backlog-ack', first.id);
        await Future<void>.delayed(Duration.zero);
        events.clear();
        await camera.acknowledge('backlog-ack', [first.id]);
        await Future<void>.delayed(Duration.zero);
        expect(
          events.where((event) => event.type == 'photosAvailable'),
          hasLength(1),
        );
        expect(await camera.pending('backlog-ack'), hasLength(9));
        expect(link.downloads, hasLength(1));
        expect(link.calls.where((call) => call.opcode == 0x9117), isEmpty);
      },
    );

    test(
      'reconnecting preserves existing photo IDs and distinguishes a replacement capture',
      () async {
        final link = _CameraLink(_Brand.nikon);
        link.addCard(7, const _Photo('DSC_0001.JPG', 8));
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        addTearDown(() async {
          await camera.stop('replacement');
          await link.dispose();
        });
        await camera.start('first');
        final first = (await camera.pending('first')).single;
        await camera.download('first', first.id);
        await camera.acknowledge('first', [first.id]);
        await camera.stop('first');
        await camera.start('reconnect');
        expect((await camera.pending('reconnect')).single.id, first.id);
        await camera.stop('reconnect');

        link.objects[7] = const _Photo(
          'DSC_0001.JPG',
          8,
          captured: '20261106T120000',
        );
        await camera.start('replacement');
        expect(
          (await camera.pending('replacement')).single.id,
          isNot(first.id),
        );
      },
    );

    test(
      'a removed backlog handle can become a later live shot when reused',
      () async {
        final link = _CameraLink(_Brand.nikon);
        for (var handle = 1; handle <= 12; handle++) {
          link.addCard(handle, _Photo('OLD$handle.JPG', 4));
        }
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        addTearDown(() async {
          await camera.stop('reused');
          await link.dispose();
        });
        await camera.start('reused');
        await camera.pending('reused');
        link.storages[1]!.remove(12);
        link.objects.remove(12);
        expect(await camera.pending('reused'), hasLength(11));
        link.addCard(12, const _Photo('REUSED.JPG', 12));
        final pending = await camera.pending('reused');
        expect(pending.first.name, 'REUSED.JPG');
        expect(pending, hasLength(12));
        expect(
          pending.map((photo) => photo.name),
          isNot(contains('OLD12.JPG')),
        );
      },
    );

    test('stop during backlog metadata prevents later camera work', () async {
      final link = _CameraLink(_Brand.nikon);
      for (var handle = 1; handle <= 12; handle++) {
        link.addCard(handle, _Photo('OLD$handle.JPG', 4));
      }
      final gate = Completer<void>();
      final started = Completer<void>();
      link.metadataGates[1] = gate;
      link.onMetadataRequest = (handle) {
        if (!started.isCompleted) started.complete();
      };
      final camera = _transport(
        link,
        uploadMode: LiveCameraUploadMode.existingAndNew,
      );
      addTearDown(link.dispose);
      await camera.start('stop-backlog');
      final pending = camera.pending('stop-backlog');
      final rejected = expectLater(pending, _error('LIVE_CAMERA_CANCELLED'));
      await started.future;
      await camera.stop('stop-backlog');
      gate.complete();
      await rejected;
      expect(link.metadataHandles, [1]);
      expect(link.downloads, isEmpty);
      expect(link.closed, contains('stop-backlog'));
      _expectNoCaptureOrLock(link);
    });

    test(
      'Sony existing-and-new fails before remote writes or consumptive reads',
      () async {
        final link = _CameraLink(_Brand.sony);
        link.addCard(1, const _Photo('OLD.JPG', 8));
        link.sonyMemory.add(const _Photo('PREVIOUS_RAM.JPG', 12));
        final camera = _transport(
          link,
          uploadMode: LiveCameraUploadMode.existingAndNew,
        );
        addTearDown(link.dispose);
        // Advertising generic card operations does not prove that Sony exposes
        // its card filesystem in this PC Remote shooting connection.
        expect(link.operations, containsAll([0x1004, 0x1007, 0x1008, 0x1009]));
        await expectLater(
          camera.start('sony-all'),
          _error('TETHER_EXISTING_PHOTOS_UNAVAILABLE'),
        );
        expect(link.calls.map((call) => call.opcode), [0x1001]);
        expect(link.sonyMemory.single.name, 'PREVIOUS_RAM.JPG');
        expect(link.downloads, isEmpty);
        expect(link.closed, contains('sony-all'));
        _expectNoCaptureOrLock(link);
      },
    );
  });

  group('native channel result validation', () {
    const channel = MethodChannel('airpix/otg_picker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('a missing response cannot become PTP success', () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => <String, Object?>{},
      );
      await expectLater(
        MethodChannelPtpTetherLink().command('s', 0x9114, params: [1]),
        _error('PTP_INVALID_RESPONSE'),
      );
    });

    test(
      'native download length mismatch is rejected with the exact transfer ID preserved',
      () async {
        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'downloadPtpTetherObject') {
            return {'path': '/staged/file.jpg', 'size': 7};
          }
          return null;
        });
        final link = MethodChannelPtpTetherLink();
        await expectLater(
          link.download(
            's',
            transferId: 'delivery-17',
            handle: 7,
            name: 'A.JPG',
            expectedSize: 8,
          ),
          _error('CAMERA_IMPORT_FAILED'),
        );
        expect((calls.single.arguments as Map)['transferId'], 'delivery-17');
        await link.acknowledge('s', ['delivery-17']);
        expect(calls.last.method, 'acknowledgePtpTetherFiles');
        expect(calls.last.arguments, {
          'sessionId': 's',
          'ids': ['delivery-17'],
        });
      },
    );
  });
}

PtpTetherCameraTransport _transport(
  _CameraLink link, {
  LiveCameraUploadMode uploadMode = LiveCameraUploadMode.newShotsOnly,
  Future<bool> Function(OtgPickedFile)? stagedExists,
  DateTime Function()? now,
}) => PtpTetherCameraTransport(
  link: link,
  uploadMode: uploadMode,
  eventPollInterval: const Duration(days: 1),
  cardScanInterval: Duration.zero,
  stopGracePeriod: const Duration(milliseconds: 5),
  delay: (_) async {},
  stagedFileExists: stagedExists ?? (_) async => true,
  now: now,
);

Matcher _error(String code) => throwsA(
  isA<PlatformException>().having((error) => error.code, 'code', code),
);

void _expectNoCaptureOrLock(_CameraLink link) {
  const forbidden = {
    0x100b, // DeleteObject.
    0x100e, // InitiateCapture.
    0x910f, // EOS RemoteRelease.
    0x911b, // EOS SetUILock.
    0x9128, // EOS RemoteReleaseOn.
    0x9151, // EOS InitiateViewfinder.
    0x9207, // Sony shutter/control buttons.
  };
  expect(link.calls.where((call) => forbidden.contains(call.opcode)), isEmpty);
  expect(
    link.calls.where((call) => call.opcode == 0x90c2 && call.params.first != 0),
    isEmpty,
  );
}

enum _Brand { canon, nikon, sony, unknown }

class _Photo {
  const _Photo(
    this.name,
    this.size, {
    this.captured = '20261105T120000',
    this.format = 0x3801,
  });
  final String name;
  final int size;
  final String captured;
  final int format;
}

class _Call {
  _Call(this.session, this.opcode, this.params, this.data);
  final String session;
  final int opcode;
  final List<int> params;
  final Uint8List? data;
}

class _Download {
  _Download(
    this.session,
    this.transferId,
    this.handle,
    this.expectedSize,
    this.partialOpcode,
  );
  final String session;
  final String transferId;
  final int handle;
  final int expectedSize;
  final int? partialOpcode;
}

/// Deliberately implements a camera's wire responses, not the adapter's methods.
/// Any guessed opcode or unadvertised write makes the test fail immediately.
class _CameraLink implements PtpTetherLink {
  _CameraLink(this.brand)
    : model = switch (brand) {
        _Brand.canon => 'Canon EOS R8',
        _Brand.nikon => 'Nikon Z6',
        _Brand.sony => 'ILCE-7M4',
        _Brand.unknown => 'Unprofiled Camera',
      };

  final _Brand brand;
  String model;
  int? vendorIdOverride;
  String physicalShutter = 'unknown';
  final eventsController = StreamController<Map<Object?, Object?>>.broadcast(
    sync: true,
  );
  final calls = <_Call>[];
  final downloads = <_Download>[];
  final acknowledgements = <(String, List<String>)>[];
  final closed = <String>[];
  final timeline = <String>[];
  final metadataHandles = <int>[];
  final metadataRejections = <int, int>{};
  final metadataFailures = <int, PlatformException>{};
  final metadataGates = <int, Completer<void>>{};
  void Function(int handle)? onMetadataRequest;
  final unavailableOperations = <int>{};
  final storages = <int, List<int>>{1: []};
  final objects = <int, _Photo>{};
  final canonObjectEvents = <Uint8List>[];
  final nikonEvents = <(int, List<int>)>[];
  final sonyMemory = Queue<_Photo>();
  final sonyExtensionReplies = Queue<Uint8List>();
  int canonDestination = 2;
  List<int> canonChoices = [1, 2, 4];
  int sonyPriority = 0;
  int sonyDestination = 17;
  int? sonyMemoryOverride;
  List<int> sonyDestinationChoices = [1, 16, 17];
  bool acceptPropertyWrites = true;
  Completer<void>? openGate;
  final openStarted = Completer<void>();

  Set<int> get operations => <int>{
    0x1001,
    0x1004,
    0x1007,
    0x1008,
    0x1009,
    0x101b,
    if (brand == _Brand.canon) ...{0x9110, 0x9114, 0x9115, 0x9116, 0x9117},
    if (brand == _Brand.nikon) ...{0x90c2, 0x90c7, 0x941c},
    if (brand == _Brand.sony) ...{0x9201, 0x9202, 0x9205, 0x9209},
  }.difference(unavailableOperations);

  void addCard(int handle, _Photo photo, {int storage = 1}) {
    storages.putIfAbsent(storage, () => []).add(handle);
    objects[handle] = photo;
  }

  Future<void> dispose() => eventsController.close();

  @override
  Stream<Map<Object?, Object?>> events(String sessionId) =>
      eventsController.stream;

  @override
  Future<PtpTetherConnection> open(String sessionId) async {
    if (!openStarted.isCompleted) openStarted.complete();
    await openGate?.future;
    return PtpTetherConnection(
      sessionId: sessionId,
      cameraId: 'camera-${brand.name}',
      name: model,
      vendorId:
          vendorIdOverride ??
          (switch (brand) {
            _Brand.canon => 0x04a9,
            _Brand.nikon => 0x04b0,
            _Brand.sony => 0x054c,
            _Brand.unknown => 0,
          }),
      physicalShutter: physicalShutter,
    );
  }

  PtpTetherResponse _ok([List<int> data = const []]) =>
      PtpTetherResponse(responseCode: 0x2001, data: Uint8List.fromList(data));

  @override
  Future<PtpTetherResponse> command(
    String sessionId,
    int opcode, {
    List<int> params = const [],
    Uint8List? outData,
  }) async {
    calls.add(_Call(sessionId, opcode, List.of(params), outData));
    timeline.add('command:${opcode.toRadixString(16)}');
    if (!operations.contains(opcode)) {
      throw StateError(
        'Unadvertised camera command ${opcode.toRadixString(16)}',
      );
    }
    switch (opcode) {
      case 0x1001:
        return _ok(_deviceInfo());
      case 0x1004:
        return _ok(_array32(storages.keys.toList()));
      case 0x1007:
        expect(params.sublist(1), [0, 0]);
        return _ok(_array32(storages[params.first] ?? []));
      case 0x1008:
        metadataHandles.add(params.single);
        onMetadataRequest?.call(params.single);
        await metadataGates[params.single]?.future;
        final failure = metadataFailures[params.single];
        if (failure != null) throw failure;
        final rejected = metadataRejections[params.single];
        if (rejected != null) return PtpTetherResponse(responseCode: rejected);
        final photo = params.single == 0xffffc001
            ? sonyMemory.first
            : objects[params.single];
        if (photo == null) return PtpTetherResponse(responseCode: 0x2009);
        return _ok(_objectInfo(photo));
      case 0x9114:
      case 0x9115:
      case 0x9117:
      case 0x90c2:
      case 0x9201:
        return _ok();
      case 0x9116:
        final payload = <int>[
          ..._block(0xc189, [..._u32(0xd11c), ..._u32(canonDestination)]),
          ..._block(0xc18a, [
            ..._u32(0xd11c),
            ..._u32(3),
            ..._u32(canonChoices.length),
            for (final value in canonChoices) ..._u32(value),
          ]),
          for (final event in canonObjectEvents) ...event,
          ..._u32(8),
          ..._u32(0),
        ];
        canonObjectEvents.clear();
        return _ok(payload);
      case 0x9110:
        expect(outData, isNotNull);
        final data = ByteData.sublistView(outData!);
        expect(data.getUint32(0, Endian.little), 12);
        expect(data.getUint32(4, Endian.little), 0xd11c);
        final choice = data.getUint32(8, Endian.little);
        expect(canonChoices, contains(choice));
        if (acceptPropertyWrites) canonDestination = choice;
        return _ok();
      case 0x941c:
        final data = <int>[
          ..._u16(nikonEvents.length),
          0,
          0,
          for (final event in nikonEvents) ...[
            ..._u16(event.$1),
            ..._u16(event.$2.length),
            for (final parameter in event.$2) ..._u32(parameter),
          ],
        ];
        nikonEvents.clear();
        return _ok(data);
      case 0x90c7:
        final data = <int>[
          ..._u16(nikonEvents.length),
          for (final event in nikonEvents) ...[
            ..._u16(event.$1),
            ..._u32(event.$2.first),
          ],
        ];
        nikonEvents.clear();
        return _ok(data);
      case 0x9202:
        if (sonyExtensionReplies.isNotEmpty) {
          return _ok(sonyExtensionReplies.removeFirst());
        }
        return _ok([
          ..._u16(0x12c),
          ..._array16([0x9205, 0x9209]),
          ..._array16([0xd215, 0xd222, 0xd25a]),
        ]);
      case 0x9209:
        final memory =
            sonyMemoryOverride ??
            (sonyMemory.isEmpty ? 0 : 0x8000 + sonyMemory.length);
        return _ok([
          ..._u32(3),
          ..._u32(0),
          ..._sonyProperty(0xd25a, 2, sonyPriority, [0, 1]),
          ..._sonyProperty(0xd222, 4, sonyDestination, sonyDestinationChoices),
          ..._sonyProperty(0xd215, 4, memory, null, writable: false),
        ]);
      case 0x9205:
        if (params.single == 0xd222) {
          final value = ByteData.sublistView(
            outData!,
          ).getUint16(0, Endian.little);
          expect(sonyDestinationChoices, contains(value));
          if (acceptPropertyWrites) sonyDestination = value;
        } else if (params.single == 0xd25a) {
          expect(outData, [0]);
          if (acceptPropertyWrites) sonyPriority = 0;
        } else {
          fail('Unimplemented Sony property write');
        }
        return _ok();
      default:
        throw StateError(
          'Unexpected camera command ${opcode.toRadixString(16)}',
        );
    }
  }

  @override
  Future<OtgPickedFile> download(
    String sessionId, {
    required String transferId,
    required int handle,
    required String name,
    required int expectedSize,
    int? partialOpcode,
  }) async {
    downloads.add(
      _Download(sessionId, transferId, handle, expectedSize, partialOpcode),
    );
    timeline.add('download:$handle');
    if (brand == _Brand.sony) {
      expect(handle, 0xffffc001);
      expect(sonyMemoryOverride, isNull);
      expect(sonyMemory.first.name, name);
      sonyMemory.removeFirst();
    }
    return OtgPickedFile(
      path: '/native/$sessionId/${downloads.length}.jpg',
      name: name,
      id: transferId,
    );
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> ids) async {
    timeline.add('ack:$sessionId');
    acknowledgements.add((sessionId, List.of(ids)));
  }

  @override
  Future<void> close(String sessionId) async {
    closed.add(sessionId);
  }

  List<int> _deviceInfo() => [
    ..._u16(100),
    ..._u32(switch (brand) {
      _Brand.canon => 11,
      _Brand.nikon => 10,
      _Brand.sony => 17,
      _Brand.unknown => 0,
    }),
    ..._u16(100),
    0,
    ..._u16(0),
    ..._array16(operations.toList()),
    ..._array16([0x4002]),
    ..._array16([]),
    ..._array16([0x3801]),
    ..._array16([0x3801]),
    ..._string(switch (brand) {
      _Brand.canon => 'Canon',
      _Brand.nikon => 'Nikon',
      _Brand.sony => 'Sony',
      _Brand.unknown => 'Unprofiled',
    }),
    ..._string(model),
    ..._string('1.0'),
    ..._string('TEST-001'),
  ];
}

List<int> _u16(int value) => [value & 255, (value >> 8) & 255];
List<int> _u32(int value) => [
  for (var byte = 0; byte < 4; byte++) (value >> (8 * byte)) & 255,
];
List<int> _array16(List<int> values) => [
  ..._u32(values.length),
  for (final value in values) ..._u16(value),
];
List<int> _array32(List<int> values) => [
  ..._u32(values.length),
  for (final value in values) ..._u32(value),
];
List<int> _string(String value) => value.isEmpty
    ? [0]
    : [
        value.length + 1,
        for (final unit in value.codeUnits) ..._u16(unit),
        0,
        0,
      ];
List<int> _objectInfo(_Photo photo) => [
  ..._u32(1),
  ..._u16(photo.format),
  ..._u16(0),
  ..._u32(photo.size),
  ...List<int>.filled(26, 0),
  ..._u32(0),
  ...List<int>.filled(6, 0),
  ..._u32(0),
  ..._string(photo.name),
  ..._string(photo.captured),
  0,
  0,
];
List<int> _block(int code, List<int> payload) => [
  ..._u32(payload.length + 8),
  ..._u32(code),
  ...payload,
];
Uint8List _canonTransfer(int handle) => Uint8List.fromList(
  _block(0xc186, [
    ..._u32(handle),
    ..._u16(0x3801),
    ...List<int>.filled(6, 0),
    ..._u32(8),
    ..._u32(0),
    ...'HOST.JPG'.codeUnits,
    0,
  ]),
);
List<int> _sonyProperty(
  int code,
  int type,
  int current,
  List<int>? choices, {
  bool writable = true,
}) {
  List<int> value(int number) => type == 2 ? [number] : _u16(number);
  return [
    ..._u16(code),
    ..._u16(type),
    writable ? 1 : 0,
    writable ? 1 : 2,
    ...value(0),
    ...value(current),
    if (choices == null)
      0
    else ...[
      2,
      ..._u16(choices.length),
      for (final choice in choices) ...value(choice),
    ],
  ];
}
