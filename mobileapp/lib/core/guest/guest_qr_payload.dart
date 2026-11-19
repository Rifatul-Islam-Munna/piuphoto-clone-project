class GuestQrData {
  const GuestQrData({required this.eventId, required this.faceEnrollment});

  final String eventId;
  final bool faceEnrollment;
}

class GuestQrPayload {
  GuestQrPayload._();

  static final RegExp _objectId = RegExp(r'^[a-fA-F0-9]{24}$');
  static final RegExp _eventPath = RegExp(
    r'(?:^|/)events?/([a-fA-F0-9]{24})(?:/|$)',
    caseSensitive: false,
  );
  static final RegExp _legacyMobile = RegExp(
    r'mobile\s*:\s*([a-fA-F0-9]{24})',
    caseSensitive: false,
  );
  static String encode(
    String eventId, {
    bool faceEnrollment = true,
    String? publicAppUrl,
  }) {
    final normalizedId = eventId.trim();
    if (!_objectId.hasMatch(normalizedId)) {
      throw ArgumentError.value(eventId, 'eventId', 'Invalid event id');
    }

    final configuredUrl = publicAppUrl?.trim() ?? '';
    final appUri = Uri.tryParse(
      configuredUrl.isEmpty ? 'https://airpix.app' : configuredUrl,
    );
    if (appUri == null ||
        (appUri.scheme != 'https' && appUri.scheme != 'http') ||
        appUri.host.isEmpty ||
        appUri.userInfo.isNotEmpty) {
      throw ArgumentError.value(
        publicAppUrl,
        'publicAppUrl',
        'Expected an HTTP(S) website URL',
      );
    }

    // The website uses HashRouter: route query parameters belong inside the
    // fragment. HTTPS also works in phone cameras without AirPix installed.
    final route = Uri(
      pathSegments: ['', 'event', normalizedId],
      queryParameters: {'v': '1', 'face': faceEnrollment ? '1' : '0'},
    );
    return Uri(
      scheme: appUri.scheme,
      host: appUri.host,
      port: appUri.hasPort ? appUri.port : null,
      path: appUri.path.endsWith('/') ? appUri.path : '${appUri.path}/',
      fragment: route.toString(),
    ).toString();
  }

  static GuestQrData? decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final uri = Uri.tryParse(text);
    final eventId = _eventIdFromUri(uri) ?? _eventIdFromText(text);
    if (eventId == null) return null;

    final faceValue =
        _faceValueFromUri(uri) ??
        _faceValueFromUri(uri == null ? null : Uri.tryParse(uri.fragment));
    final faceEnrollment =
        _truthy(faceValue) ||
        RegExp(
          r'(?:face|faceEnrollment)\s*[:=]\s*(?:1|true)',
          caseSensitive: false,
        ).hasMatch(text);

    return GuestQrData(eventId: eventId, faceEnrollment: faceEnrollment);
  }

  static String? _faceValueFromUri(Uri? uri) =>
      uri?.queryParameters['face'] ?? uri?.queryParameters['faceEnrollment'];

  static String? _eventIdFromUri(Uri? uri) {
    if (uri == null) return null;
    final queryId = uri.queryParameters['eventId'];
    if (queryId != null && _objectId.hasMatch(queryId)) return queryId;

    final pathMatch = _eventPath.firstMatch(uri.path);
    if (pathMatch != null) return pathMatch.group(1);
    final fragmentPath = Uri.tryParse(uri.fragment)?.path ?? '';
    final fragmentMatch = _eventPath.firstMatch(fragmentPath);
    if (fragmentMatch != null) return fragmentMatch.group(1);
    return null;
  }

  static String? _eventIdFromText(String text) {
    final legacy = _legacyMobile.firstMatch(text);
    if (legacy != null) return legacy.group(1);

    final pathMatch = _eventPath.firstMatch(text);
    if (pathMatch != null) return pathMatch.group(1);

    final fallback = RegExp(r'[a-fA-F0-9]{24}').firstMatch(text);
    return fallback?.group(0);
  }

  static bool _truthy(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == '1' || normalized == 'true' || normalized == 'yes';
  }
}
