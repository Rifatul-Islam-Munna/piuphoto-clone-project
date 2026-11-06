import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:mobileapp/core/platform/camera_http_auth.dart';

class CanonCcapiContent {
  const CanonCcapiContent({required this.url, required this.name});

  final String url;
  final String name;
}

class CanonCcapiCamera {
  CanonCcapiCamera._({
    required this.origin,
    required this.version,
    required Dio dio,
  }) : _dio = dio;

  static const _versions = ['ver140', 'ver130', 'ver120', 'ver110', 'ver100'];

  final Uri origin;
  final String version;
  final Dio _dio;
  final CancelToken _cancelToken = CancelToken();
  final Map<String, CanonCcapiContent> _pending = {};
  final Set<String> _acknowledged = {};
  Future<List<CanonCcapiContent>>? _pollInFlight;
  bool _closed = false;

  bool get isClosed => _closed;

  String get sourceUrl => origin.toString();

  Uri get _eventUri => origin.replace(
    path: '/ccapi/$version/event/polling',
    queryParameters: const {'continue': 'off'},
  );
  static Future<CanonCcapiCamera?> discover(
    Iterable<Uri> candidateOrigins, {
    Duration timeout = const Duration(milliseconds: 1200),
    String? username,
    String? password,
    bool exactEndpoint = false,
    CancelToken? cancellation,
  }) async {
    final origins = <Uri>[];
    final seen = <String>{};

    void addOrigin(Uri uri) {
      if (uri.host.isEmpty) return;
      final scheme = uri.scheme == 'https' ? 'https' : 'http';
      final ports = <int>{
        if (uri.hasPort) uri.port,
        if (!exactEndpoint) 8080,
        if (!exactEndpoint || !uri.hasPort) scheme == 'https' ? 443 : 80,
      };
      for (final port in ports) {
        final origin = Uri(
          scheme: scheme,
          host: uri.host,
          port: port,
          path: '/',
        );
        if (seen.add(origin.toString())) origins.add(origin);
      }
    }

    for (final uri in candidateOrigins) {
      addOrigin(uri);
    }

    for (final origin in origins) {
      if (cancellation?.isCancelled == true) return null;
      final dio = Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: const Duration(seconds: 2),
          sendTimeout: timeout,
          validateStatus: (status) => status != null && status < 500,
          followRedirects: false,
        ),
      );
      // Only documented read endpoints on this exact camera are reachable.
      // No guessed snapshot/capture/live-view URL and no redirect is permitted.
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.method != 'GET' || !_allowsRead(origin, request.uri)) {
              handler.reject(
                DioException(
                  requestOptions: request,
                  error: 'Wireless camera control commands are blocked.',
                ),
              );
              return;
            }
            handler.next(request);
          },
        ),
      );
      if (username?.isNotEmpty == true) {
        final auth = CameraHttpAuth(username!, password ?? '');
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              final header = auth.header(request.method, request.uri);
              if (header != null) request.headers['Authorization'] = header;
              handler.next(request);
            },
            onResponse: (response, handler) async {
              if (response.statusCode != 401 ||
                  response.requestOptions.extra['cameraAuthRetried'] == true) {
                handler.next(response);
                return;
              }
              final challenges =
                  response.headers['www-authenticate'] ?? const <String>[];
              if (!challenges.any(auth.acceptChallenge)) {
                handler.next(response);
                return;
              }
              try {
                final retry = response.requestOptions.copyWith(
                  extra: {
                    ...response.requestOptions.extra,
                    'cameraAuthRetried': true,
                  },
                );
                handler.resolve(await dio.fetch(retry));
              } on DioException catch (error) {
                handler.reject(error);
              } catch (error) {
                handler.reject(
                  DioException(
                    requestOptions: response.requestOptions,
                    error: error,
                  ),
                );
              }
            },
          ),
        );
      }

      for (final version in _versions) {
        if (cancellation?.isCancelled == true) {
          dio.close(force: true);
          return null;
        }
        final camera = CanonCcapiCamera._(
          origin: origin,
          version: version,
          dio: dio,
        );
        try {
          final response = await dio.getUri(
            camera._eventUri,
            cancelToken: cancellation ?? camera._cancelToken,
          );
          if (exactEndpoint &&
              (response.statusCode == 401 || response.statusCode == 403)) {
            dio.close(force: true);
            return null;
          }
          if (response.statusCode == null ||
              response.statusCode! < 200 ||
              response.statusCode! >= 300) {
            continue;
          }
          dynamic data = response.data;
          if (data is String) {
            try {
              data = jsonDecode(data);
            } catch (_) {
              continue;
            }
          }
          if (data is Map || data is List) {
            // This discovery request consumes the camera event queue too.
            // Keep any shot it announced for the first live poll.
            camera._rememberContents(data);
            return camera;
          }
        } catch (_) {}
      }
      dio.close(force: true);
    }
    return null;
  }

  static bool _allowsRead(Uri origin, Uri uri) {
    if (uri.scheme != origin.scheme ||
        uri.host.toLowerCase() != origin.host.toLowerCase() ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty) {
      return false;
    }
    final path = uri.normalizePath().path;
    if (path != uri.path ||
        uri.pathSegments.any((s) => s == '.' || s == '..')) {
      return false;
    }
    return RegExp(r'^/ccapi/ver[0-9]+/event/polling$').hasMatch(path) ||
        RegExp(r'^/ccapi/ver[0-9]+/contents/').hasMatch(path);
  }

  /// Added-content events are destructive reads on the camera. Retain them
  /// until the caller confirms that the photo was saved to its local queue.
  Future<List<CanonCcapiContent>> pollAddedContents() {
    if (_closed) {
      return Future.error(StateError('The camera connection is closed'));
    }
    final existing = _pollInFlight;
    if (existing != null) return existing;
    late final Future<List<CanonCcapiContent>> operation;
    operation = _poll().whenComplete(() {
      if (identical(_pollInFlight, operation)) _pollInFlight = null;
    });
    _pollInFlight = operation;
    return operation;
  }

  Future<List<CanonCcapiContent>> _poll() async {
    try {
      final response = await _dio.getUri(_eventUri, cancelToken: _cancelToken);
      if (_closed) throw StateError('The camera connection is closed');
      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300) {
        throw StateError('Camera event polling is temporarily unavailable');
      }
      dynamic data = response.data;
      if (data is String) data = jsonDecode(data);
      if (data is! Map && data is! List) {
        throw const FormatException('Invalid camera event response');
      }
      _rememberContents(data);
    } catch (_) {
      if (_closed || _pending.isEmpty) rethrow;
      // Already-received announcements remain actionable during a transient
      // polling failure. A failed download is also left pending for retry.
    }
    return List<CanonCcapiContent>.unmodifiable(_pending.values);
  }

  void _rememberContents(dynamic data) {
    final candidates = <String>[];
    _collectAddedContent(data, candidates, insideAddedContents: false);
    for (final raw in candidates) {
      final Uri resolved;
      try {
        final uri = Uri.tryParse(raw);
        resolved = uri != null && uri.hasScheme ? uri : origin.resolve(raw);
      } on FormatException {
        continue;
      }
      // Credentials belong to this camera. Never follow an event URL to a
      // different server (or forward its Authorization header there).
      if (resolved.scheme != origin.scheme ||
          resolved.host.toLowerCase() != origin.host.toLowerCase() ||
          resolved.port != origin.port ||
          resolved.userInfo.isNotEmpty) {
        continue;
      }
      if (!_allowsRead(origin, resolved) ||
          !resolved.path.contains('/contents/') ||
          !_looksLikeCameraImage(resolved.path)) {
        continue;
      }
      final url = resolved.toString();
      if (_acknowledged.contains(url) || _pending.containsKey(url)) continue;
      final name = resolved.pathSegments.isEmpty
          ? 'canon-${DateTime.now().millisecondsSinceEpoch}.jpg'
          : resolved.pathSegments.last;
      _pending[url] = CanonCcapiContent(url: url, name: name);
    }
  }

  void acknowledgeContents(Iterable<String> urls) {
    for (final url in urls) {
      if (_pending.remove(url) != null) _acknowledged.add(url);
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancelToken.cancel('Camera receiving stopped');
    _dio.close(force: true);
    try {
      await _pollInFlight;
    } catch (_) {}
  }

  Future<CanonCcapiContent?> pollAddedContent() async {
    final contents = await pollAddedContents();
    return contents.isEmpty ? null : contents.last;
  }

  Future<Uint8List?> download(CanonCcapiContent content) async {
    if (_closed) throw StateError('The camera connection is closed');
    final uri = Uri.tryParse(content.url);
    if (uri == null ||
        !_allowsRead(origin, uri) ||
        !uri.path.contains('/contents/') ||
        uri.scheme != origin.scheme ||
        uri.host.toLowerCase() != origin.host.toLowerCase() ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final response = await _dio.get<List<int>>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
        followRedirects: false,
      ),
      cancelToken: _cancelToken,
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      return null;
    }
    final bytes = response.data ?? const <int>[];
    final expectedLength = int.tryParse(
      response.headers.value('content-length') ?? '',
    );
    final encoding = response.headers.value('content-encoding');
    if (expectedLength != null &&
        expectedLength >= 0 &&
        (encoding == null || encoding == 'identity') &&
        bytes.length != expectedLength) {
      return null;
    }
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
  }

  static void _collectAddedContent(
    dynamic value,
    List<String> results, {
    required bool insideAddedContents,
  }) {
    if (value is Map) {
      value.forEach((key, child) {
        final keyText = key.toString().toLowerCase();
        final isAdded =
            insideAddedContents ||
            keyText == 'addedcontents' ||
            keyText == 'addedcontent';
        _collectAddedContent(child, results, insideAddedContents: isAdded);
      });
      return;
    }
    if (value is Iterable) {
      for (final child in value) {
        _collectAddedContent(
          child,
          results,
          insideAddedContents: insideAddedContents,
        );
      }
      return;
    }
    if (insideAddedContents && value is String && value.isNotEmpty) {
      results.add(value);
    }
  }

  static bool _looksLikeCameraImage(String path) {
    final lower = path.toLowerCase();
    return const [
      '.jpg',
      '.jpeg',
      '.png',
      '.heic',
      '.heif',
      '.tif',
      '.tiff',
      '.dng',
      '.cr2',
      '.cr3',
      '.arw',
      '.nef',
      '.raf',
      '.rw2',
      '.orf',
      '.pef',
    ].any(lower.endsWith);
  }
}
