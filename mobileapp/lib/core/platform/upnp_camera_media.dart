import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class UpnpCameraImage {
  const UpnpCameraImage({
    required this.url,
    required this.name,
    required this.id,
  });

  final String url;
  final String name;
  final String id;

  String get fingerprint => '$id|$url|$name';
}

class UpnpCameraMedia {
  UpnpCameraMedia._({
    required this.location,
    required this.controlUrl,
    required this.serviceType,
    required Dio dio,
  }) : _dio = dio;

  final Uri location;
  final Uri controlUrl;
  final String serviceType;
  final Dio _dio;

  String get sourceUrl => location.toString();

  static Future<UpnpCameraMedia?> discover(
    Iterable<Uri> locations, {
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final seen = <String>{};
    for (final location in locations) {
      if (!location.hasScheme || location.host.isEmpty) continue;
      if (!seen.add(location.toString())) continue;

      final dio = Dio(
        BaseOptions(
          connectTimeout: timeout,
          receiveTimeout: const Duration(seconds: 2),
          sendTimeout: timeout,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      try {
        final response = await dio.get<String>(
          location.toString(),
          options: Options(responseType: ResponseType.plain),
        );
        final body = response.data ?? '';
        if (body.isEmpty) continue;
        final services = RegExp(
          r'<service>(.*?)</service>',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(body);
        for (final match in services) {
          final block = match.group(1) ?? '';
          final type = _tag(block, 'serviceType');
          if (type == null || !type.contains('ContentDirectory')) continue;
          final control = _tag(block, 'controlURL');
          if (control == null || control.isEmpty) continue;
          return UpnpCameraMedia._(
            location: location,
            controlUrl: location.resolve(control),
            serviceType: type,
            dio: dio,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  Future<List<UpnpCameraImage>> recentImages({int limit = 20}) async {
    final images = <UpnpCameraImage>[];
    final pending = <String>['0'];
    final visited = <String>{};

    while (pending.isNotEmpty && visited.length < 24 && images.length < limit) {
      final objectId = pending.removeAt(0);
      if (!visited.add(objectId)) continue;
      final result = await _browse(objectId);
      if (result == null) continue;
      final decoded = _decodeEntities(result);

      for (final container in RegExp(
        r'<container\b[^>]*\bid="([^"]+)"[^>]*>',
        caseSensitive: false,
      ).allMatches(decoded)) {
        final id = container.group(1);
        if (id != null && id.isNotEmpty && !visited.contains(id)) {
          pending.add(id);
        }
      }

      final itemMatches = RegExp(
        r'<item\b([^>]*)>(.*?)</item>',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(decoded);
      for (final item in itemMatches) {
        final attrs = item.group(1) ?? '';
        final block = item.group(2) ?? '';
        final id =
            RegExp(
              r'\bid="([^"]+)"',
              caseSensitive: false,
            ).firstMatch(attrs)?.group(1) ??
            block.hashCode.toString();
        final title = _tag(block, 'dc:title') ?? _tag(block, 'title');
        final resources = RegExp(
          r'<res\b([^>]*)>(.*?)</res>',
          caseSensitive: false,
          dotAll: true,
        ).allMatches(block);
        for (final resource in resources) {
          final attrs = resource.group(1) ?? '';
          final rawUrl = (resource.group(2) ?? '').trim();
          if (rawUrl.isEmpty) continue;
          final protocol = attrs.toLowerCase();
          final resolved = location.resolve(_decodeEntities(rawUrl));
          if (!protocol.contains('image/') && !_looksLikeImage(resolved.path)) {
            continue;
          }
          final name = title?.trim().isNotEmpty == true
              ? title!.trim()
              : (resolved.pathSegments.isEmpty
                    ? 'camera-image.jpg'
                    : resolved.pathSegments.last);
          images.add(
            UpnpCameraImage(url: resolved.toString(), name: name, id: id),
          );
          break;
        }
        if (images.length >= limit) break;
      }
    }

    return images.reversed.toList(growable: false);
  }

  Future<Uint8List?> download(UpnpCameraImage image) async {
    final response = await _dio.get<List<int>>(
      image.url,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final bytes = response.data ?? const <int>[];
    return bytes.isEmpty ? null : Uint8List.fromList(bytes);
  }

  Future<String?> _browse(String objectId) async {
    final body =
        '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
 s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
 <s:Body>
  <u:Browse xmlns:u="$serviceType">
   <ObjectID>${_escapeXml(objectId)}</ObjectID>
   <BrowseFlag>BrowseDirectChildren</BrowseFlag>
   <Filter>*</Filter>
   <StartingIndex>0</StartingIndex>
   <RequestedCount>256</RequestedCount>
   <SortCriteria></SortCriteria>
  </u:Browse>
 </s:Body>
</s:Envelope>''';

    final response = await _dio.post<String>(
      controlUrl.toString(),
      data: body,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'Content-Type': 'text/xml; charset="utf-8"',
          'SOAPAction': '"$serviceType#Browse"',
        },
      ),
    );
    final responseBody = response.data ?? '';
    return _tag(responseBody, 'Result');
  }

  static String? _tag(String xml, String tag) {
    final escaped = RegExp.escape(tag);
    return RegExp(
      '<(?:[A-Za-z0-9_-]+:)?$escaped(?:\\s[^>]*)?>(.*?)</(?:[A-Za-z0-9_-]+:)?$escaped>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(xml)?.group(1)?.trim();
  }

  static String _decodeEntities(String value) {
    return value
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  static String _escapeXml(String value) {
    return const HtmlEscape(HtmlEscapeMode.element).convert(value);
  }

  static bool _looksLikeImage(String path) {
    final lower = path.toLowerCase();
    return const [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.heic',
      '.heif',
      '.tif',
      '.tiff',
    ].any(lower.endsWith);
  }
}
