import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:mobileapp/core/platform/live_camera_types.dart';
import 'package:mobileapp/core/platform/otg_file_picker.dart';
import 'package:path_provider/path_provider.dart';

class DebugPcCameraTransport implements LiveCameraTransport {
  DebugPcCameraTransport({
    Uri? baseUri,
    this.eventTimeout = const Duration(seconds: 20),
  }) : baseUri = baseUri ?? Uri.parse('http://127.0.0.1:8765');

  final Uri baseUri;
  final Duration eventTimeout;
  final HttpClient _client = HttpClient();
  final Map<String, _PcRun> _runs = {};

  Uri _uri(String path, [Map<String, String>? query]) =>
      baseUri.replace(path: path, queryParameters: query);

  @override
  Stream<LiveCameraEvent> eventsForSession(String sessionId) {
    final run = _runs.putIfAbsent(sessionId, () => _PcRun(sessionId));
    return run.controller.stream;
  }

  @override
  Future<LiveCameraSession> start(String sessionId) async {
    final run = _runs.putIfAbsent(sessionId, () => _PcRun(sessionId));
    final health = await _getJson(_uri('/health'));
    if (health['ok'] != true) {
      throw PlatformException(
        code: 'PC_CAMERA_BRIDGE_UNAVAILABLE',
        message:
            'PC camera simulator did not answer. Start the bridge and run adb reverse tcp:8765 tcp:8765.',
      );
    }
    run.active = true;
    unawaited(_eventLoop(run));
    return LiveCameraSession(
      id: sessionId,
      cameraId: 'pc-camera-simulator',
      name: 'PC Camera Simulator',
      physicalShutter: 'supported',
      message:
          'PC test bridge ready. Open http://localhost:8765 on the PC, choose a JPG, and click Simulate shutter.',
      baselineCount: 0,
      uploadMode: LiveCameraUploadMode.newShotsOnly,
    );
  }

  Future<void> _eventLoop(_PcRun run) async {
    while (run.active) {
      try {
        final data = await _getJson(
          _uri('/events', {
            'after': '${run.sequence}',
            'timeout': '${eventTimeout.inSeconds}',
          }),
        );
        if (!run.active) return;
        final sequence = int.tryParse('${data['seq']}') ?? run.sequence;
        if (sequence > run.sequence) {
          run.sequence = sequence;
          run.controller.add(
            LiveCameraEvent(
              sessionId: run.sessionId,
              type: 'photosAvailable',
              message: 'PC simulator shutter event received.',
            ),
          );
        }
      } catch (error) {
        if (!run.active) return;
        run.controller.add(
          LiveCameraEvent(
            sessionId: run.sessionId,
            type: 'error',
            code: 'PC_CAMERA_BRIDGE_INTERRUPTED',
            message: 'PC test bridge interrupted: $error',
          ),
        );
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  @override
  Future<List<ConnectedCameraImage>> pending(String sessionId) async {
    _requireActive(sessionId);
    final data = await _getJson(_uri('/pending'));
    final raw = data['photos'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              ConnectedCameraImage.fromMap(Map<Object?, Object?>.from(item)),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<OtgPickedFile> download(String sessionId, String imageId) async {
    _requireActive(sessionId);
    final request = await _client.getUrl(
      _uri('/photo/${Uri.encodeComponent(imageId)}'),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      throw PlatformException(
        code: 'PC_CAMERA_DOWNLOAD_FAILED',
        message: 'PC simulator photo download failed (${response.statusCode}).',
      );
    }
    final name = Uri.decodeComponent(
      response.headers.value('x-photo-name') ?? 'pc-test.jpg',
    );
    final bytes = await response.fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );
    if (bytes.isEmpty) {
      throw PlatformException(
        code: 'PC_CAMERA_DOWNLOAD_FAILED',
        message: 'PC simulator returned an empty photo.',
      );
    }
    final temp = await getTemporaryDirectory();
    final safeName = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      '${temp.path}${Platform.pathSeparator}pc-$imageId-$safeName',
    );
    await file.writeAsBytes(bytes, flush: true);
    return OtgPickedFile(path: file.path, name: name, id: imageId);
  }

  @override
  Future<void> acknowledge(String sessionId, List<String> imageIds) async {
    if (imageIds.isEmpty) return;
    await _postJson(_uri('/ack'), {'ids': imageIds});
  }

  @override
  Future<void> stop(String sessionId) async {
    final run = _runs.remove(sessionId);
    if (run == null) return;
    run.active = false;
    if (!run.controller.isClosed) {
      await run.controller.close();
    }
  }

  void _requireActive(String sessionId) {
    if (_runs[sessionId]?.active != true) {
      throw PlatformException(code: 'LIVE_CAMERA_SESSION_NOT_FOUND');
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $body', uri: uri);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, Object?> payload,
  ) async {
    final request = await _client.postUrl(uri);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(payload));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $body', uri: uri);
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      throw const FormatException('Expected a JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }
}

class _PcRun {
  _PcRun(this.sessionId);

  final String sessionId;
  final StreamController<LiveCameraEvent> controller =
      StreamController<LiveCameraEvent>.broadcast();
  bool active = false;
  int sequence = 0;
}
