import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/platform/camera_ftp_receiver.dart';

void main() {
  late Directory directory;
  late CameraFtpReceiver receiver;
  final clients = <_FtpClient>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('airpix-ftp-test-');
    clients.clear();
    receiver = CameraFtpReceiver(
      stagingDirectory: directory,
      onFile: (_) async {},
      dataTimeout: const Duration(seconds: 2),
    );
  });

  tearDown(() async {
    for (final client in clients) {
      await client.close();
    }
    await receiver.stop();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<_FtpClient> connect(CameraFtpConnection connection) async {
    final client = await _FtpClient.connect(connection);
    clients.add(client);
    return client;
  }

  Future<CameraFtpConnection> start() =>
      receiver.start(address: InternetAddress.loopbackIPv4);

  test(
    'requires credentials and reports authenticated camera connections',
    () async {
      var authenticated = 0;
      var disconnected = 0;
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (_) async {},
        onClientAuthenticated: () => authenticated++,
        onClientDisconnected: () => disconnected++,
      );
      final connection = await start();
      final client = await connect(connection);
      expect(receiver.authenticatedClientCount, 0);
      expect(await client.command('STOR IMG_0001.JPG'), startsWith('530 '));
      expect(await client.command('USER wrong'), startsWith('331 '));
      expect(await client.command('PASS wrong'), startsWith('530 '));
      await client.login(connection);
      expect(receiver.authenticatedClientCount, 1);
      expect(authenticated, 1);
      expect(await client.command('AUTH TLS'), startsWith('502 '));
      expect(await client.command('SYST'), startsWith('215 '));
      expect(await client.command('TYPE I'), startsWith('200 '));
      expect(await client.command('OPTS UTF8 ON'), startsWith('200 '));
      client.send('FEAT');
      expect(await client.read(), '211-Features');
      final features = <String>[];
      while (true) {
        final line = await client.read();
        if (line.startsWith('211 ')) {
          break;
        }
        features.add(line.trim());
      }
      expect(features, containsAll(['EPSV', 'UTF8', 'SIZE', 'MDTM']));
      expect(await client.command('QUIT'), startsWith('221 '));
      await _until(() => receiver.authenticatedClientCount == 0);
      expect(disconnected, 1);
    },
  );

  test('acknowledges only after streamed bytes are durably accepted', () async {
    final entered = Completer<CameraFtpFile>();
    final accepted = Completer<void>();
    final bytes = List<int>.generate(200000, (index) => index % 251);
    receiver = CameraFtpReceiver(
      stagingDirectory: directory,
      onFile: (file) async {
        expect(await File(file.localPath).readAsBytes(), bytes);
        entered.complete(file);
        await accepted.future;
      },
    );
    final connection = await start();
    final client = await connect(connection);
    await client.login(connection);
    final upload = client.upload('IMG_0001.JPG', bytes);
    var acknowledged = false;
    unawaited(upload.then((_) => acknowledged = true));
    final file = await entered.future;
    expect(file.size, bytes.length);
    expect(file.name, 'IMG_0001.JPG');
    expect(file.sha256, sha256.convert(bytes).toString());
    expect(file.localPath.endsWith('.part'), isFalse);
    expect(await File(file.localPath).exists(), isTrue);
    expect(acknowledged, isFalse);
    accepted.complete();
    expect(await upload, startsWith('226 '));
    expect(await client.command('SIZE IMG_0001.JPG'), '213 ${bytes.length}');
    expect(await client.command('MDTM IMG_0001.JPG'), matches(r'^213 \d{14}$'));
    await receiver.stop();
    expect(await directory.list().toList(), isEmpty);
  });

  test('EPSV permits a data connection opened after STOR', () async {
    final files = <CameraFtpFile>[];
    receiver = CameraFtpReceiver(
      stagingDirectory: directory,
      onFile: (file) async => files.add(file),
    );
    final connection = await start();
    final client = await connect(connection);
    await client.login(connection);
    expect(await client.command('EPSV ALL'), startsWith('200 '));
    expect(await client.command('PASV'), startsWith('522 '));
    final port = await client.passive(extended: true);
    client.send('STOR DSC_0042.JPG');
    expect(await client.read(), startsWith('150 '));
    final data = await Socket.connect(connection.host, port);
    data.add([1, 2, 3, 4]);
    await data.flush();
    await data.close();
    expect(await client.read(), startsWith('226 '));
    data.destroy();
    expect(files.single.name, 'DSC_0042.JPG');
  });

  test(
    'deduplicates retransmits across reconnects but preserves reused names',
    () async {
      final fingerprints = <String>[];
      final saved = <List<int>>[];
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (file) async {
          fingerprints.add(file.fingerprint);
          saved.add(await File(file.localPath).readAsBytes());
        },
      );
      final connection = await start();
      var client = await connect(connection);
      await client.login(connection);
      expect(
        await client.upload('DSC_0001.JPG', [1, 2, 3]),
        startsWith('226 '),
      );
      expect(
        await client.upload('DSC_0001.JPG', [1, 2, 3]),
        startsWith('226 '),
      );
      await client.close();
      client = await connect(connection);
      await client.login(connection);
      expect(
        await client.upload('DSC_0001.JPG', [1, 2, 3]),
        startsWith('226 '),
      );
      expect(
        await client.upload('DSC_0001.JPG', [4, 5, 6]),
        startsWith('226 '),
      );
      expect(saved, [
        [1, 2, 3],
        [4, 5, 6],
      ]);
      expect(fingerprints.toSet().length, 2);
    },
  );

  test(
    'failed local persistence is retryable and is never marked delivered',
    () async {
      var attempts = 0;
      final failures = <Object>[];
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onError: failures.add,
        onFile: (file) async {
          attempts++;
          if (attempts == 1) {
            throw StateError('Local queue unavailable');
          }
        },
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      expect(
        await client.upload('IMG_0002.JPG', [7, 8, 9]),
        startsWith('451 '),
      );
      expect(await client.command('SIZE IMG_0002.JPG'), startsWith('550 '));
      expect(
        await client.upload('IMG_0002.JPG', [7, 8, 9]),
        startsWith('226 '),
      );
      expect(attempts, 2);
      expect(failures, hasLength(1));
    },
  );

  test(
    'rejects zero length, declared truncation and size limit overruns',
    () async {
      var imports = 0;
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        maxFileBytes: 16,
        onFile: (_) async => imports++,
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      expect(await client.upload('EMPTY.JPG', []), startsWith('552 '));
      expect(await client.command('ALLO 10'), startsWith('200 '));
      expect(await client.upload('SHORT.JPG', [1, 2, 3]), startsWith('552 '));
      expect(await client.command('ALLO 17'), startsWith('552 '));
      expect(
        await client.upload('LARGE.JPG', List.filled(17, 1)),
        startsWith('552 '),
      );
      expect(imports, 0);
      expect(await client.upload('OK.JPG', [1, 2]), startsWith('226 '));
      expect(imports, 1);
    },
  );

  test(
    'data timeout removes the partial file and permits the next photo',
    () async {
      var imports = 0;
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        dataTimeout: const Duration(milliseconds: 150),
        onFile: (_) async => imports++,
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      final port = await client.passive();
      final data = await Socket.connect(connection.host, port);
      client.send('STOR INTERRUPTED.JPG');
      expect(await client.read(), startsWith('150 '));
      data.add([1, 2]);
      await data.flush();
      expect(await client.read(), startsWith('426 '));
      data.destroy();
      expect(imports, 0);
      expect(await client.upload('RETRY.JPG', [1, 2, 3]), startsWith('226 '));
      expect(imports, 1);
      await receiver.stop();
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'stop interrupts an active receive without publishing a partial',
    () async {
      var imports = 0;
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (_) async => imports++,
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      final port = await client.passive();
      final data = await Socket.connect(connection.host, port);
      client.send('STOR STOPPED.JPG');
      expect(await client.read(), startsWith('150 '));
      data.add(List.filled(4096, 3));
      await data.flush();
      await receiver.stop();
      data.destroy();
      expect(imports, 0);
      expect(receiver.isRunning, isFalse);
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test(
    'stop preserves a completed source until its durable callback finishes',
    () async {
      final entered = Completer<CameraFtpFile>();
      final copied = Completer<void>();
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (file) async {
          entered.complete(file);
          await copied.future;
          expect(await File(file.localPath).readAsBytes(), [3, 4, 5]);
        },
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      final upload = client.upload('COMPLETE.JPG', [3, 4, 5]);
      // Stopping legitimately closes control before the FTP success reply.
      unawaited(upload.then<void>((_) {}, onError: (Object error) {}));
      final file = await entered.future;
      final stopping = receiver.stop();
      var stopped = false;
      unawaited(stopping.then((_) => stopped = true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stopped, isFalse);
      expect(await File(file.localPath).exists(), isTrue);
      copied.complete();
      await stopping;
      expect(await directory.list().toList(), isEmpty);
    },
  );

  test('ABOR interrupts STOR and leaves the connection usable', () async {
    var imports = 0;
    receiver = CameraFtpReceiver(
      stagingDirectory: directory,
      onFile: (_) async => imports++,
    );
    final connection = await start();
    final client = await connect(connection);
    await client.login(connection);
    final port = await client.passive();
    final data = await Socket.connect(connection.host, port);
    client.send('STOR ABORTED.JPG');
    expect(await client.read(), startsWith('150 '));
    data.add([9, 9]);
    await data.flush();
    client.send('ABOR');
    expect(await client.read(), startsWith('426 '));
    expect(await client.read(), startsWith('226 '));
    data.destroy();
    expect(imports, 0);
    expect(await client.upload('NEXT.JPG', [1, 2, 3]), startsWith('226 '));
    expect(imports, 1);
  });

  test(
    'a passive data socket must have the control connection peer address',
    () async {
      final received = <List<int>>[];
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (file) async =>
            received.add(await File(file.localPath).readAsBytes()),
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      final port = await client.passive();
      final unrelated = await Socket.connect(
        connection.host,
        port,
        sourceAddress: InternetAddress('127.0.0.2'),
      );
      unrelated.destroy();
      final data = await Socket.connect(connection.host, port);
      client.send('STOR SAFE.JPG');
      expect(await client.read(), startsWith('150 '));
      data.add([4, 5, 6]);
      await data.flush();
      await data.close();
      expect(await client.read(), startsWith('226 '));
      data.destroy();
      expect(received, [
        [4, 5, 6],
      ]);
    },
  );

  test(
    'remote folders are virtual and filenames cannot escape staging',
    () async {
      final files = <CameraFtpFile>[];
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (file) async {
          expect(file.localPath.startsWith(directory.path), isTrue);
          files.add(file);
        },
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      expect(await client.command('MKD DCIM/100CANON'), startsWith('257 '));
      expect(await client.command('CWD DCIM/100CANON'), startsWith('250 '));
      expect(await client.command('PWD'), '257 "/DCIM/100CANON"');
      expect(
        await client.command('STOR ../../outside.jpg'),
        startsWith('550 '),
      );
      expect(await client.command('STOR C:\\outside.jpg'), startsWith('550 '));
      expect(
        await client.command('STOR camera-connection-probe.txt'),
        startsWith('550 '),
      );
      expect(await client.command('STOR clip.MP4'), startsWith('550 '));
      expect(await client.command('DELE anything.jpg'), startsWith('502 '));
      expect(await client.command('RETR anything.jpg'), startsWith('502 '));
      expect(await client.command('PORT 127,0,0,1,4,1'), startsWith('502 '));
      expect(
        await client.upload('IMG*001?.JPG', [3, 2, 1]),
        startsWith('226 '),
      );
      expect(files.single.name, 'IMG_001_.JPG');
      expect(files.single.remotePath, '/DCIM/100CANON/IMG*001?.JPG');
      expect(await client.command('SIZE /etc/passwd'), startsWith('550 '));
      expect(
        await File('${directory.parent.path}/outside.jpg').exists(),
        isFalse,
      );
    },
  );

  test(
    'UTF8 filenames fit filesystem byte limits and retain the extension',
    () async {
      final names = <String>[];
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (file) async => names.add(file.name),
      );
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      expect(
        await client.upload('${List.filled(200, 'é').join()}.JPG', [1, 2, 3]),
        startsWith('226 '),
      );
      expect(utf8.encode(names.single).length, lessThanOrEqualTo(180));
      expect(names.single.endsWith('.JPG'), isTrue);
    },
  );

  test(
    'concurrent camera uploads serialize durable callbacks without overwriting',
    () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      final names = <String>[];
      var inCallback = 0;
      var maximum = 0;
      receiver = CameraFtpReceiver(
        stagingDirectory: directory,
        onFile: (file) async {
          inCallback++;
          if (inCallback > maximum) {
            maximum = inCallback;
          }
          names.add(file.name);
          if (file.name == 'FIRST.JPG') {
            entered.complete();
            await release.future;
          }
          inCallback--;
        },
      );
      final connection = await start();
      final first = await connect(connection);
      final second = await connect(connection);
      await first.login(connection);
      await second.login(connection);
      final one = first.upload('FIRST.JPG', [1, 2, 3]);
      await entered.future;
      final two = second.upload('SECOND.JPG', [4, 5, 6]);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(names, ['FIRST.JPG']);
      release.complete();
      expect(await one, startsWith('226 '));
      expect(await two, startsWith('226 '));
      expect(names, ['FIRST.JPG', 'SECOND.JPG']);
      expect(maximum, 1);
    },
  );

  test(
    'stop during startup closes late listeners and allows a fresh session',
    () async {
      final opening = receiver.start(address: InternetAddress.loopbackIPv4);
      final openingResult = expectLater(opening, throwsA(isA<StateError>()));
      await receiver.stop();
      await openingResult;
      expect(receiver.isRunning, isFalse);
      expect(await directory.list().toList(), isEmpty);
      final connection = await start();
      final client = await connect(connection);
      await client.login(connection);
      expect(await client.upload('AFTER_RESTART.JPG', [1]), startsWith('226 '));
    },
  );

  test(
    'saved profile overrides are stable while session IDs are fresh',
    () async {
      final first = await receiver.start(
        address: InternetAddress.loopbackIPv4,
        username: 'saved-camera',
        password: 'saved-camera-password',
      );
      await receiver.stop();
      final second = await receiver.start(
        address: InternetAddress.loopbackIPv4,
        port: first.port,
        username: first.username,
        password: first.password,
      );
      expect(second.port, first.port);
      expect(second.username, first.username);
      expect(second.password, first.password);
      expect(second.sessionId, isNot(first.sessionId));
    },
  );

  test('rejects unsafe bind addresses and malformed credentials', () async {
    await expectLater(
      receiver.start(address: InternetAddress.anyIPv4),
      throwsArgumentError,
    );
    await expectLater(
      receiver.start(address: InternetAddress('8.8.8.8')),
      throwsArgumentError,
    );
    await expectLater(
      receiver.start(address: InternetAddress.loopbackIPv4, username: 'only'),
      throwsArgumentError,
    );
    await expectLater(
      receiver.start(
        address: InternetAddress.loopbackIPv4,
        username: 'bad\r\nUSER name',
        password: 'safe',
      ),
      throwsArgumentError,
    );
  });
}

class _FtpClient {
  _FtpClient(this.socket, this.host)
    : lines = StreamIterator(
        socket
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );

  final Socket socket;
  final String host;
  final StreamIterator<String> lines;
  bool closed = false;

  static Future<_FtpClient> connect(CameraFtpConnection connection) async {
    final socket = await Socket.connect(connection.host, connection.port);
    unawaited(socket.done.then<void>((_) {}, onError: (Object error) {}));
    final client = _FtpClient(socket, connection.host);
    expect(await client.read(), startsWith('220 '));
    return client;
  }

  void send(String command) => socket.add(utf8.encode('$command\r\n'));

  Future<String> read() async {
    if (!await lines.moveNext().timeout(const Duration(seconds: 5))) {
      throw const SocketException('FTP control connection closed');
    }
    return lines.current;
  }

  Future<String> command(String value) {
    send(value);
    return read();
  }

  Future<void> login(CameraFtpConnection connection) async {
    expect(await command('USER ${connection.username}'), startsWith('331 '));
    expect(await command('PASS ${connection.password}'), startsWith('230 '));
  }

  Future<int> passive({bool extended = false}) async {
    final response = await command(extended ? 'EPSV' : 'PASV');
    if (extended) {
      expect(response, startsWith('229 '));
      return int.parse(
        RegExp(r'\(\|\|\|(\d+)\|\)').firstMatch(response)!.group(1)!,
      );
    }
    expect(response, startsWith('227 '));
    final values = RegExp(
      r'\(([^)]+)\)',
    ).firstMatch(response)!.group(1)!.split(',').map(int.parse).toList();
    return values[4] * 256 + values[5];
  }

  Future<String> upload(String name, List<int> bytes) async {
    final port = await passive();
    final data = await Socket.connect(host, port);
    unawaited(data.done.then<void>((_) {}, onError: (Object error) {}));
    try {
      send('STOR $name');
      expect(await read(), startsWith('150 '));
      // Multiple chunks exercise streaming rather than a whole-file buffer.
      for (var offset = 0; offset < bytes.length; offset += 4096) {
        final end = offset + 4096 < bytes.length ? offset + 4096 : bytes.length;
        data.add(bytes.sublist(offset, end));
      }
      await data.flush();
      await data.close();
      return await read();
    } finally {
      data.destroy();
    }
  }

  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    socket.destroy();
    await lines.cancel();
  }
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition did not become true.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
