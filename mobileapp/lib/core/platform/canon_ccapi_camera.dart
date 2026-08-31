import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

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
  }) async {
    final origins = <Uri>[];
    final seen = <String>{};

    void addOrigin(Uri uri) {
      if (uri.host.isEmpty) return;
      final scheme = uri.scheme == 'https' ? 'https' : 'http';
      final ports = <int>{
        if (uri.hasPort) uri.port,
        8080,
        scheme == 'https' ? 443 : 80,
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
      final dio = Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: const Duration(seconds: 2),
          sendTimeout: timeout,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (username?.isNotEmpty == true) {
        final credentials = base64Encode(
          utf8.encode('$username:${password ?? ''}'),
        );
        dio.options.headers['Authorization'] = 'Basic $credentials';
      }

      for (final version in _versions) {
        final camera = CanonCcapiCamera._(
          origin: origin,
          version: version,
          dio: dio,
        );
        try {
          final response = await dio.getUri(camera._eventUri);
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
            return camera;
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<List<CanonCcapiContent>> pollAddedContents() async {
    final response = await _dio.getUri(_eventUri);
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      return const [];
    }

    dynamic data = response.data;
    if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {
        return const [];
      }
    }

    final candidates = <String>[];
    _collectAddedContent(data, candidates, insideAddedContents: false);
    if (candidates.isEmpty) return const [];

    final contents = <CanonCcapiContent>[];
    final seen = <String>{};
    for (final raw in candidates) {
      final uri = Uri.tryParse(raw);
      final resolved = uri != null && uri.hasScheme ? uri : origin.resolve(raw);
      if (!_looksLikeCameraImage(resolved.path)) continue;
      final url = resolved.toString();
      if (!seen.add(url)) continue;
      final name = resolved.pathSegments.isEmpty
          ? 'canon-${DateTime.now().millisecondsSinceEpoch}.jpg'
          : resolved.pathSegments.last;
      contents.add(CanonCcapiContent(url: url, name: name));
    }
    return contents;
  }

  Future<CanonCcapiContent?> pollAddedContent() async {
    final contents = await pollAddedContents();
    return contents.isEmpty ? null : contents.last;
  }

  Future<Uint8List?> download(CanonCcapiContent content) async {
    final uri = Uri.tryParse(content.url);
    if (uri == null) return null;
    final response = await _dio.get<List<int>>(
      uri.toString(),
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    if (response.statusCode == null ||
        response.statusCode! < 200 ||
        response.statusCode! >= 300) {
      return null;
    }
    final bytes = response.data ?? const <int>[];
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
