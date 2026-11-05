import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The settings to enter in a camera's FTP transfer profile.
///
/// This receiver uses ordinary FTP, not FTPS. Use a trusted, private local
/// network, passive mode, and no encryption in the camera's FTP settings.
/// Neither credentials nor photographs are encrypted on that local connection.
class CameraFtpConnection {
  const CameraFtpConnection({
    required this.sessionId,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  final String sessionId;
  final String host;
  final int port;
  final String username;
  final String password;
}

/// A completely received file. [localPath] exists only during
/// [CameraFtpReceiver.onFile].
///
/// The receiver deletes this staging copy after the callback completes, so the
/// callback must await a durable copy into the app's upload queue. Do not wait
/// for an Internet upload in that callback. Throw if local persistence fails;
/// the receiver then returns a retryable FTP failure instead of acknowledging
/// the camera's transfer. The camera's memory card is never modified.
class CameraFtpFile {
  const CameraFtpFile({
    required this.sessionId,
    required this.transferId,
    required this.localPath,
    required this.name,
    required this.remotePath,
    required this.size,
    required this.sha256,
    required this.receivedAt,
  });

  final String sessionId;
  final String transferId;
  final String localPath;
  final String name;
  final String remotePath;
  final int size;
  final String sha256;
  final DateTime receivedAt;

  /// Stable across reconnects, but distinct for reused filenames/new contents.
  String get fingerprint => '$remotePath|$size|$sha256';
}

/// An upload-only, authenticated FTP receiver for cameras with FTP auto-send.
///
/// Start this while the transfer page is in the foreground. Choose a local
/// Wi-Fi/Ethernet IPv4 address, enter the returned profile in the camera, and
/// enable its automatic transfer after each shot. The camera controls shooting;
/// this class sends no shutter, live-view, or camera-lock commands. Supported
/// shooting functions still depend on the camera's firmware and FTP support.
///
/// Only a selected private interface is bound. A passive data connection must
/// originate from the control connection's peer. The remote directory tree is
/// virtual: commands cannot read, delete, or rename files on the phone. Files
/// stream to unique staging paths with backpressure. Incomplete, failed,
/// cancelled and empty transfers are never passed to [onFile]. A graceful FTP
/// data EOF is the protocol's end-of-file signal; when a camera supplies ALLO,
/// its declared length is checked as well.
///
/// [onFile] callbacks are serialized across clients, and identical retransmits
/// are acknowledged without importing again within one receiver session.
/// Credentials default to cryptographically random per-session values. A saved
/// profile can pass both credential overrides and a fixed port to [start].
class CameraFtpReceiver {
  CameraFtpReceiver({
    required this.stagingDirectory,
    required this.onFile,
    this.onError,
    this.onClientAuthenticated,
    this.onClientDisconnected,
    this.commandTimeout = const Duration(minutes: 15),
    this.dataTimeout = const Duration(seconds: 30),
    this.maxFileBytes = 1024 * 1024 * 1024,
    this.maxConnections = 4,
  }) {
    if (commandTimeout <= Duration.zero || dataTimeout <= Duration.zero) {
      throw ArgumentError('FTP timeouts must be positive.');
    }
    if (maxFileBytes <= 0 || maxConnections <= 0) {
      throw ArgumentError('FTP limits must be positive.');
    }
  }

  final Directory stagingDirectory;
  final Future<void> Function(CameraFtpFile file) onFile;
  final void Function(Object error)? onError;
  final void Function()? onClientAuthenticated;
  final void Function()? onClientDisconnected;
  final Duration commandTimeout;
  final Duration dataTimeout;
  final int maxFileBytes;
  final int maxConnections;

  /// Still-image names accepted from a camera. Format/content validation still
  /// belongs to the durable photo-import callback. Connection probe files,
  /// sidecars, executables and videos are not published as photographs.
  static const supportedImageExtensions = <String>{
    'jpg',
    'jpeg',
    'jpe',
    'jfif',
    'heic',
    'heif',
    'hif',
    'png',
    'tif',
    'tiff',
    'dng',
    'crw',
    'cr2',
    'cr3',
    'nef',
    'nrw',
    'arw',
    'sr2',
    'srf',
    'orf',
    'rw2',
    'raf',
    'pef',
    'rwl',
    '3fr',
    'fff',
    'iiq',
    'x3f',
    'erf',
    'mef',
    'mos',
    'mrw',
    'raw',
  };

  _FtpRun? _run;
  Future<void>? _stopping;
  Completer<void>? _startCompletion;
  bool _starting = false;
  int _generation = 0;

  bool get isRunning => _run != null && !_run!.closed;
  CameraFtpConnection? get connection => _run?.connection;
  int get authenticatedClientCount => _run?.authenticatedClientCount ?? 0;

  /// Local camera-network candidates, with Wi-Fi before Ethernet.
  ///
  /// Cellular, VPN, loopback and common virtual/container interfaces are
  /// excluded. A caller should let the user choose when several remain.
  static Future<List<InternetAddress>> availableAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: true,
    );
    final excluded = RegExp(
      r'^(lo\b|pdp_ip|rmnet|v4-rmnet|ccmni|wwan|utun|tun|tap|ppp|ipsec|wg\d|'
      r'awdl|llw|dummy|veth|docker|virbr|vmnet|vethernet|tailscale|zt)',
      caseSensitive: false,
    );
    interfaces.removeWhere((item) => excluded.hasMatch(item.name));
    int rank(String name) {
      final lower = name.toLowerCase();
      if (lower == 'en0' ||
          lower.contains('wi-fi') ||
          lower.startsWith('wlan') ||
          lower.startsWith('wifi') ||
          lower.startsWith('ap') ||
          lower.startsWith('swlan')) {
        return 0;
      }
      if (lower.startsWith('en') || lower.startsWith('eth')) {
        return 1;
      }
      return 2;
    }

    interfaces.sort((a, b) => rank(a.name).compareTo(rank(b.name)));
    final seen = <String>{};
    return [
      for (final network in interfaces)
        for (final address in network.addresses)
          if (_isPrivateV4(address) &&
              !address.isLoopback &&
              seen.add(address.address))
            address,
    ];
  }

  Future<CameraFtpConnection> start({
    InternetAddress? address,
    int port = 0,
    String? username,
    String? password,
  }) async {
    if (_starting || isRunning) {
      throw StateError('The camera FTP receiver is already running.');
    }
    if (port < 0 || port > 65535) {
      throw ArgumentError.value(port, 'port', 'Invalid TCP port.');
    }
    if ((username == null) != (password == null)) {
      throw ArgumentError('Supply both FTP username and password.');
    }
    if (username != null) {
      _validateCredential(username, 'username');
      _validateCredential(password!, 'password');
    }

    // Capture before the first async suspension. A concurrent stop waits for
    // this start's cleanup; startup must await only the *previous* stop.
    final previousStop = _stopping;
    _starting = true;
    final startCompletion = Completer<void>();
    _startCompletion = startCompletion;
    final generation = ++_generation;
    Directory? directory;
    ServerSocket? listener;
    try {
      await previousStop;
      final selected = address ?? (await availableAddresses()).firstOrNull;
      if (selected == null) {
        throw const SocketException(
          'Connect the phone and camera to the same private Wi-Fi network.',
        );
      }
      if (!_isPrivateV4(selected)) {
        throw ArgumentError.value(
          selected.address,
          'address',
          'Select one private IPv4 interface, not a public or wildcard address.',
        );
      }
      await stagingDirectory.create(recursive: true);
      final sessionId = _randomHex(12);
      directory = await stagingDirectory.createTemp('airpix-ftp-$sessionId-');
      if (generation != _generation) {
        throw StateError('Camera FTP start was cancelled.');
      }
      listener = await ServerSocket.bind(
        selected,
        port,
        backlog: maxConnections,
      );
      if (generation != _generation) {
        throw StateError('Camera FTP start was cancelled.');
      }
      final connection = CameraFtpConnection(
        sessionId: sessionId,
        host: selected.address,
        port: listener.port,
        username: username ?? 'ap_${_randomHex(3)}',
        password: password ?? _randomHex(12),
      );
      final run = _FtpRun(this, connection, selected, directory, listener);
      _run = run;
      run.listen();
      return connection;
    } catch (_) {
      await listener?.close();
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
      rethrow;
    } finally {
      _starting = false;
      _startCompletion = null;
      startCompletion.complete();
    }
  }

  /// Closes sockets immediately, removes partials, and waits for an already
  /// running durable-copy callback before deleting its staging file.
  Future<void> stop() async {
    _generation++;
    final run = _run;
    _run = null;
    final starting = _startCompletion?.future;
    final previous = _stopping;
    final stopping = () async {
      await previous;
      await run?.close();
      await starting;
    }();
    _stopping = stopping;
    await stopping;
  }

  void _report(Object error) {
    try {
      onError?.call(error);
    } catch (_) {
      // A UI error callback must not break socket/file cleanup.
    }
  }
}

class _FtpRun {
  _FtpRun(
    this.owner,
    this.connection,
    this.address,
    this.directory,
    this.listener,
  );

  final CameraFtpReceiver owner;
  final CameraFtpConnection connection;
  final InternetAddress address;
  final Directory directory;
  final ServerSocket listener;
  final Set<_FtpClient> clients = {};
  final Set<String> directories = {'/'};
  final Set<String> acceptedFingerprints = {};
  final Map<String, CameraFtpFile> acceptedFiles = {};
  Future<void> _delivery = Future<void>.value();
  Future<void>? _closing;
  bool closed = false;
  int sequence = 0;

  int get authenticatedClientCount =>
      clients.where((client) => client.authenticated && !client.closed).length;

  void listen() {
    listener.listen(
      (socket) {
        if (closed ||
            clients.length >= owner.maxConnections ||
            !_isPrivateV4(socket.remoteAddress)) {
          socket.destroy();
          return;
        }
        final client = _FtpClient(this, socket);
        clients.add(client);
        client.listen();
      },
      onError: (Object error) {
        if (!closed) {
          owner._report(error);
          unawaited(close());
        }
      },
    );
  }

  Future<void> deliver(CameraFtpFile file) {
    final result = Completer<void>();
    _delivery = _delivery.then((_) async {
      try {
        if (closed) {
          throw const _TransferStopped();
        }
        if (!acceptedFingerprints.contains(file.fingerprint)) {
          await owner.onFile(file);
          acceptedFingerprints.add(file.fingerprint);
        }
        acceptedFiles[file.remotePath] = file;
        result.complete();
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    closed = true;
    final pendingClients = [for (final client in clients) client.close()];
    await listener.close();
    await Future.wait(pendingClients);
    await _delivery;
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class _FtpClient {
  _FtpClient(this.run, this.socket);

  final _FtpRun run;
  final Socket socket;
  final List<int> _buffer = [];
  StreamSubscription<List<int>>? _subscription;
  Future<void> _commands = Future<void>.value();
  Future<void>? _closing;
  Timer? _idleTimer;
  _FtpPassive? _passive;
  Socket? _dataSocket;
  bool closed = false;
  bool authenticated = false;
  bool _usernameMatches = false;
  bool _activeTransfer = false;
  bool _abortRequested = false;
  bool _epsvOnly = false;
  int _failedLogins = 0;
  int _queuedCommands = 0;
  int? _expectedSize;
  String _cwd = '/';

  void listen() {
    socket.setOption(SocketOption.tcpNoDelay, true);
    // Socket write failures also complete IOSink.done; observe both directions.
    unawaited(socket.done.then<void>((_) {}, onError: (Object error) {}));
    _subscription = socket.listen(
      _read,
      onDone: () => unawaited(close()),
      onError: (Object error) => unawaited(close()),
    );
    _reply(220, 'AirPix camera transfer ready.');
    _resetIdle();
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(run.owner.commandTimeout, () {
      if (_activeTransfer) {
        _resetIdle();
      } else {
        _reply(421, 'Camera connection timed out. Reconnect to continue.');
        unawaited(close());
      }
    });
  }

  void _read(List<int> bytes) {
    if (closed) {
      return;
    }
    _resetIdle();
    _buffer.addAll(bytes);
    while (true) {
      final end = _buffer.indexOf(10);
      if (end < 0) {
        break;
      }
      if (end > 4096 || _queuedCommands >= 32) {
        _reply(421, 'Too many or oversized commands.');
        unawaited(close());
        return;
      }
      final lineBytes = _buffer.sublist(0, end);
      _buffer.removeRange(0, end + 1);
      if (lineBytes.isNotEmpty && lineBytes.last == 13) {
        lineBytes.removeLast();
      }
      final line = utf8.decode(lineBytes, allowMalformed: true);
      final verb = line.split(' ').first.toUpperCase();
      if (verb == 'ABOR' || verb == 'QUIT') {
        // Interrupt a blocked STOR without waiting behind it in the command
        // queue. Its cleanup/reply still completes before the ABOR/QUIT reply.
        _abortRequested = true;
        _dataSocket?.destroy();
        unawaited(_passive?.close());
      }
      _queuedCommands++;
      _commands = _commands.then((_) async {
        try {
          if (!closed) {
            await _command(line);
          }
        } catch (error) {
          if (!closed) {
            run.owner._report(error);
            _reply(451, 'Temporary transfer error. Retry the image.');
          }
        } finally {
          _queuedCommands--;
        }
      });
    }
    if (_buffer.length > 4096) {
      _reply(421, 'Command too long.');
      unawaited(close());
    }
  }

  Future<void> _command(String line) async {
    final separator = line.indexOf(' ');
    final verb = (separator < 0 ? line : line.substring(0, separator))
        .toUpperCase();
    final argument = separator < 0 ? '' : line.substring(separator + 1).trim();
    if (line.contains('\x00') || line.contains('\r')) {
      _reply(500, 'Invalid command.');
      return;
    }
    switch (verb) {
      case 'USER':
        _setAuthenticated(false);
        _usernameMatches = _sameCredential(argument, run.connection.username);
        _reply(331, 'Password required.');
        return;
      case 'PASS':
        final accepted =
            _sameCredential(argument, run.connection.password) &&
            _usernameMatches;
        _setAuthenticated(accepted);
        if (accepted) {
          _failedLogins = 0;
          _reply(230, 'Camera signed in.');
        } else {
          _failedLogins++;
          _reply(530, 'Sign-in failed. Check the displayed FTP profile.');
          if (_failedLogins >= 5) {
            unawaited(close());
          }
        }
        return;
      case 'FEAT':
        _write(
          '211-Features\r\n UTF8\r\n EPSV\r\n SIZE\r\n MDTM\r\n211 End\r\n',
        );
        return;
      case 'SYST':
        _reply(215, 'UNIX Type: L8');
        return;
      case 'AUTH':
        _reply(
          502,
          'Use passive FTP without TLS on a trusted private network.',
        );
        return;
      case 'NOOP':
        _reply(200, 'OK');
        return;
      case 'QUIT':
        _reply(221, 'Goodbye.');
        await socket.flush();
        unawaited(close());
        return;
    }
    if (!authenticated) {
      _reply(530, 'Sign in with USER and PASS first.');
      return;
    }
    switch (verb) {
      case 'TYPE':
        if (['I', 'A', 'L 8'].contains(argument.toUpperCase())) {
          _reply(200, 'Transfer type accepted.');
        } else {
          _reply(504, 'Unsupported transfer type.');
        }
        break;
      case 'OPTS':
        _reply(
          argument.toUpperCase() == 'UTF8 ON' ? 200 : 501,
          argument.toUpperCase() == 'UTF8 ON'
              ? 'UTF8 enabled.'
              : 'Use UTF8 ON.',
        );
        break;
      case 'CLNT':
        _reply(200, 'OK');
        break;
      case 'MODE':
      case 'STRU':
        final accepted = argument.toUpperCase() == (verb == 'MODE' ? 'S' : 'F');
        _reply(accepted ? 200 : 504, accepted ? 'OK' : 'Unsupported mode.');
        break;
      case 'PWD':
      case 'XPWD':
        _reply(257, '"${_cwd.replaceAll('"', '""')}"');
        break;
      case 'CWD':
      case 'XCWD':
        final path = _virtualPath(argument, _cwd, allowParent: true);
        if (path != null && run.directories.contains(path)) {
          _cwd = path;
          _reply(250, 'Directory changed.');
        } else {
          _reply(550, 'Directory does not exist.');
        }
        break;
      case 'CDUP':
        _cwd = _parentPath(_cwd);
        _reply(250, 'Directory changed.');
        break;
      case 'MKD':
      case 'XMKD':
        final path = _virtualPath(argument, _cwd);
        if (path == null || run.directories.length >= 1024) {
          _reply(550, 'Invalid directory.');
        } else {
          var current = path;
          while (current != '/') {
            run.directories.add(current);
            current = _parentPath(current);
          }
          _reply(257, '"${path.replaceAll('"', '""')}" created.');
        }
        break;
      case 'PASV':
        if (_epsvOnly) {
          _reply(522, 'Use EPSV.');
        } else {
          await _openPassive(extended: false);
        }
        break;
      case 'EPSV':
        if (argument.toUpperCase() == 'ALL') {
          _epsvOnly = true;
          await _passive?.close();
          _passive = null;
          _reply(200, 'EPSV only.');
        } else if (argument.isEmpty || argument == '1') {
          await _openPassive(extended: true);
        } else {
          _reply(522, 'IPv4 only; use EPSV or EPSV 1.');
        }
        break;
      case 'ALLO':
        final size = int.tryParse(argument.split(' ').first);
        if (size == null || size <= 0 || size > run.owner.maxFileBytes) {
          _expectedSize = null;
          _reply(552, 'Invalid file size or file exceeds the receiver limit.');
        } else {
          _expectedSize = size;
          _reply(200, 'File size accepted.');
        }
        break;
      case 'STOR':
        await _store(argument);
        break;
      case 'LIST':
      case 'NLST':
        await _list(argument, namesOnly: verb == 'NLST');
        break;
      case 'SIZE':
      case 'MDTM':
        final path = _virtualPath(argument, _cwd);
        final file = run.acceptedFiles[path];
        if (file == null) {
          _reply(550, 'File not found in this transfer session.');
        } else {
          _reply(
            213,
            verb == 'SIZE' ? '${file.size}' : _ftpTime(file.receivedAt),
          );
        }
        break;
      case 'ABOR':
        await _passive?.close();
        _passive = null;
        _expectedSize = null;
        _reply(226, 'Transfer aborted.');
        break;
      case 'STAT':
        _reply(211, 'Camera FTP receiver ready.');
        break;
      default:
        // No RETR, DELETE, rename, append, active-mode, or arbitrary SITE
        // commands. Remote names are never host filesystem paths.
        _reply(502, 'Unsupported command. Use passive upload mode.');
    }
  }

  void _setAuthenticated(bool value) {
    if (authenticated == value) {
      return;
    }
    authenticated = value;
    try {
      if (value) {
        run.owner.onClientAuthenticated?.call();
      } else {
        run.owner.onClientDisconnected?.call();
      }
    } catch (error) {
      run.owner._report(error);
    }
  }

  Future<void> _openPassive({required bool extended}) async {
    await _passive?.close();
    final passive = await _FtpPassive.open(
      address: run.address,
      peer: socket.remoteAddress.address,
      timeout: run.owner.dataTimeout,
    );
    if (closed || run.closed) {
      await passive.close();
      return;
    }
    _passive = passive;
    if (extended) {
      _reply(229, 'Entering Extended Passive Mode (|||${passive.port}|)');
    } else {
      final host = run.address.address.replaceAll('.', ',');
      _reply(
        227,
        'Entering Passive Mode ($host,${passive.port ~/ 256},${passive.port % 256})',
      );
    }
  }

  Future<Socket?> _beginTransfer() async {
    final passive = _passive;
    if (passive == null) {
      _reply(425, 'Use PASV or EPSV before transferring.');
      return null;
    }
    _activeTransfer = true;
    _abortRequested = false;
    _reply(150, 'Opening data connection.');
    try {
      final data = await passive.take();
      if (closed || run.closed || _abortRequested) {
        data?.destroy();
        throw const _TransferStopped();
      }
      if (data == null) {
        throw TimeoutException('Camera data connection timed out.');
      }
      _dataSocket = data;
      unawaited(data.done.then<void>((_) {}, onError: (Object error) {}));
      return data;
    } finally {
      _passive = null;
      await passive.close();
    }
  }

  Future<void> _store(String argument) async {
    final path = _virtualPath(argument, _cwd);
    final expectedSize = _expectedSize;
    _expectedSize = null;
    if (path == null ||
        path == '/' ||
        run.directories.contains(path) ||
        !run.directories.contains(_parentPath(path))) {
      _reply(550, 'Invalid filename or destination directory.');
      return;
    }
    final originalName = path.split('/').last;
    final dot = originalName.lastIndexOf('.');
    if (dot <= 0 ||
        !CameraFtpReceiver.supportedImageExtensions.contains(
          originalName.substring(dot + 1).toLowerCase(),
        )) {
      _reply(550, 'Only supported still-image files can be transferred.');
      return;
    }
    File? temporary;
    File? completed;
    RandomAccessFile? output;
    try {
      final data = await _beginTransfer();
      if (data == null) {
        return;
      }
      final transferId = '${run.connection.sessionId}-${++run.sequence}';
      final name = _safeBasename(originalName);
      temporary = File('${run.directory.path}/$transferId.part');
      output = await temporary.open(mode: FileMode.write);
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var size = 0;
      try {
        await for (final chunk in data.timeout(run.owner.dataTimeout)) {
          if (closed || run.closed || _abortRequested) {
            throw const _TransferStopped();
          }
          size += chunk.length;
          if (size > run.owner.maxFileBytes ||
              (expectedSize != null && size > expectedSize)) {
            throw const _FileSizeFailure();
          }
          await output.writeFrom(chunk);
          hash.add(chunk);
        }
      } finally {
        hash.close();
      }
      if (closed || run.closed || _abortRequested) {
        throw const _TransferStopped();
      }
      if (size == 0 || (expectedSize != null && size != expectedSize)) {
        throw const _FileSizeFailure();
      }
      await output.flush();
      await output.close();
      output = null;
      completed = await temporary.rename(
        '${run.directory.path}/${transferId}__$name',
      );
      temporary = null;
      final file = CameraFtpFile(
        sessionId: run.connection.sessionId,
        transferId: transferId,
        localPath: completed.path,
        name: name,
        remotePath: path,
        size: size,
        sha256: digest.value!.toString(),
        receivedAt: DateTime.now().toUtc(),
      );
      await run.deliver(file);
      _reply(226, 'Photo received and saved by AirPix.');
    } on _FileSizeFailure {
      _reply(
        552,
        'Incomplete, empty, or oversized file. Retry the whole image.',
      );
    } on _TransferStopped {
      _reply(426, 'Transfer interrupted. Retry the whole image.');
    } on TimeoutException {
      _reply(426, 'Data connection timed out. Retry the whole image.');
    } on SocketException {
      _reply(426, 'Data connection interrupted. Retry the whole image.');
    } catch (error) {
      if (!closed && !run.closed) {
        run.owner._report(error);
      }
      _reply(451, 'Could not save the image. Retry the whole image.');
    } finally {
      _dataSocket?.destroy();
      _dataSocket = null;
      if (output != null) {
        try {
          await output.close();
        } catch (error) {
          run.owner._report(error);
        }
      }
      if (temporary != null) {
        await _deleteIfPresent(temporary, run.owner._report);
      }
      if (completed != null) {
        await _deleteIfPresent(completed, run.owner._report);
      }
      _activeTransfer = false;
      _resetIdle();
    }
  }

  Future<void> _list(String argument, {required bool namesOnly}) async {
    final path = argument.isEmpty || argument.startsWith('-')
        ? _cwd
        : _virtualPath(argument, _cwd, allowParent: true);
    if (path == null || !run.directories.contains(path)) {
      _reply(550, 'Directory does not exist.');
      return;
    }
    try {
      final data = await _beginTransfer();
      if (data == null) {
        return;
      }
      final lines = <String>[];
      for (final directory in run.directories) {
        if (directory == '/' || _parentPath(directory) != path) {
          continue;
        }
        final name = directory.split('/').last;
        lines.add(
          namesOnly ? name : 'drwx------ 1 camera camera 0 Jan 01 00:00 $name',
        );
      }
      for (final file in run.acceptedFiles.values) {
        if (_parentPath(file.remotePath) != path) {
          continue;
        }
        final name = file.remotePath.split('/').last;
        lines.add(
          namesOnly
              ? name
              : '-rw------- 1 camera camera ${file.size} Jan 01 00:00 $name',
        );
      }
      if (lines.isNotEmpty) {
        data.add(utf8.encode('${lines.join('\r\n')}\r\n'));
      }
      await data.flush().timeout(run.owner.dataTimeout);
      await data.close().timeout(run.owner.dataTimeout);
      _reply(226, 'Directory transfer complete.');
    } catch (_) {
      _reply(426, 'Directory transfer interrupted.');
    } finally {
      _dataSocket?.destroy();
      _dataSocket = null;
      _activeTransfer = false;
      _resetIdle();
    }
  }

  void _reply(int code, String message) => _write('$code $message\r\n');

  void _write(String message) {
    if (closed) {
      return;
    }
    try {
      socket.add(utf8.encode(message));
    } catch (_) {
      unawaited(close());
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    closed = true;
    _idleTimer?.cancel();
    _setAuthenticated(false);
    _dataSocket?.destroy();
    socket.destroy();
    await _passive?.close();
    await _subscription?.cancel();
    await _commands;
    _idleTimer?.cancel();
    run.clients.remove(this);
  }
}

class _FtpPassive {
  _FtpPassive(this.listener, this.peer, Duration timeout) {
    _timer = Timer(timeout, () => unawaited(close()));
    listener.listen((socket) {
      if (_closed ||
          _accepted != null ||
          socket.remoteAddress.address != peer) {
        socket.destroy();
        return;
      }
      _accepted = socket;
      _ready.complete(socket);
      unawaited(listener.close());
    }, onError: (Object error) => unawaited(close()));
  }

  final ServerSocket listener;
  final String peer;
  final Completer<Socket?> _ready = Completer<Socket?>();
  Socket? _accepted;
  Timer? _timer;
  bool _taken = false;
  bool _closed = false;

  int get port => listener.port;

  static Future<_FtpPassive> open({
    required InternetAddress address,
    required String peer,
    required Duration timeout,
  }) async {
    final listener = await ServerSocket.bind(address, 0, backlog: 2);
    return _FtpPassive(listener, peer, timeout);
  }

  Future<Socket?> take() async {
    final socket = await _ready.future;
    if (_closed) {
      return null;
    }
    _taken = true;
    _timer?.cancel();
    return socket;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _timer?.cancel();
    if (!_ready.isCompleted) {
      _ready.complete(null);
    }
    if (!_taken) {
      _accepted?.destroy();
    }
    await listener.close();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

class _TransferStopped implements Exception {
  const _TransferStopped();
}

class _FileSizeFailure implements Exception {
  const _FileSizeFailure();
}

bool _isPrivateV4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) {
    return false;
  }
  final bytes = address.rawAddress;
  return bytes[0] == 10 ||
      bytes[0] == 127 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168) ||
      (bytes[0] == 169 && bytes[1] == 254);
}

String _randomHex(int bytes) {
  final random = Random.secure();
  return List.generate(
    bytes,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

void _validateCredential(String value, String name) {
  if (value.isEmpty ||
      value.length > 64 ||
      value.codeUnits.any((byte) => byte < 33 || byte > 126)) {
    throw ArgumentError.value(
      '<redacted>',
      name,
      'Use 1–64 printable ASCII characters without spaces.',
    );
  }
}

bool _sameCredential(String a, String b) {
  var difference = a.length ^ b.length;
  for (var i = 0; i < max(a.length, b.length); i++) {
    difference |=
        (i < a.length ? a.codeUnitAt(i) : 0) ^
        (i < b.length ? b.codeUnitAt(i) : 0);
  }
  return difference == 0;
}

String? _virtualPath(String input, String cwd, {bool allowParent = false}) {
  if (input.isEmpty ||
      input.length > 1024 ||
      input.codeUnits.any((byte) => byte < 32 || byte == 127)) {
    return null;
  }
  final normalized = input.replaceAll('\\', '/');
  final parts = normalized.startsWith('/')
      ? <String>[]
      : cwd.split('/').where((part) => part.isNotEmpty).toList();
  for (final part in normalized.split('/')) {
    if (part.isEmpty || part == '.') {
      continue;
    }
    if (part == '..') {
      if (!allowParent) {
        return null;
      }
      if (parts.isNotEmpty) {
        parts.removeLast();
      }
      continue;
    }
    if (part.contains(':') || part.length > 255) {
      return null;
    }
    parts.add(part);
    if (parts.length > 16) {
      return null;
    }
  }
  return '/${parts.join('/')}';
}

String _parentPath(String path) {
  final end = path.lastIndexOf('/');
  return end <= 0 ? '/' : path.substring(0, end);
}

String _safeBasename(String original) {
  var name = original
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]'), '_')
      .replaceAll(RegExp(r'[. ]+$'), '');
  if (name.isEmpty) {
    name = 'camera-photo';
  }
  final stem = name.split('.').first.toUpperCase();
  if (RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$').hasMatch(stem)) {
    name = '_$name';
  }
  if (utf8.encode(name).length > 180) {
    final dot = name.lastIndexOf('.');
    final extension = dot > 0 && name.length - dot <= 16
        ? name.substring(dot)
        : '';
    final stem = (extension.isEmpty ? name : name.substring(0, dot)).runes
        .toList();
    while (stem.isNotEmpty &&
        utf8.encode('${String.fromCharCodes(stem)}$extension').length > 180) {
      stem.removeLast();
    }
    name = '${String.fromCharCodes(stem)}$extension';
  }
  return name;
}

String _ftpTime(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}${two(utc.month)}${two(utc.day)}'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}';
}

Future<void> _deleteIfPresent(File file, void Function(Object) onError) async {
  try {
    if (await file.exists()) {
      await file.delete();
    }
  } catch (error) {
    onError(error);
  }
}
