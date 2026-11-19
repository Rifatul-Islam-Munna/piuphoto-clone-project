import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';

void main() {
  const eventId = '507f1f77bcf86cd799439011';

  test('encodes a browser-openable guest URL for the website HashRouter', () {
    final encoded = GuestQrPayload.encode(eventId);
    final decoded = GuestQrPayload.decode(encoded);

    expect(encoded, 'https://airpix.app/#/event/$eventId?v=1&face=1');
    final webUri = Uri.parse(encoded);
    final route = Uri.parse(webUri.fragment);
    expect(webUri.scheme, 'https');
    expect(webUri.query, isEmpty);
    expect(route.path, '/event/$eventId');
    expect(route.queryParameters['face'], '1');
    expect(decoded?.eventId, eventId);
    expect(decoded?.faceEnrollment, isTrue);
  });

  test('keeps existing custom-scheme QR codes scannable in AirPix', () {
    final decoded = GuestQrPayload.decode(
      'airpix://guest/event/$eventId?v=1&face=1',
    );

    expect(decoded?.eventId, eventId);
    expect(decoded?.faceEnrollment, isTrue);
  });

  test('preserves the configured website path and replaces stale routing', () {
    final encoded = GuestQrPayload.encode(
      ' $eventId ',
      publicAppUrl: ' https://photos.example/portal/?old=1#/planner/dashboard ',
    );

    expect(encoded, 'https://photos.example/portal/#/event/$eventId?v=1&face=1');
    expect(GuestQrPayload.decode(encoded)?.faceEnrollment, isTrue);
  });

  test('supports local websites with a port and a gallery-only QR', () {
    final encoded = GuestQrPayload.encode(
      eventId,
      publicAppUrl: 'http://localhost:5173',
      faceEnrollment: false,
    );

    expect(encoded, 'http://localhost:5173/#/event/$eventId?v=1&face=0');
    expect(GuestQrPayload.decode(encoded)?.faceEnrollment, isFalse);
  });

  test('uses production website when public URL config is blank', () {
    expect(
      GuestQrPayload.encode(eventId, publicAppUrl: ' '),
      GuestQrPayload.encode(eventId),
    );
  });

  test('reads face enrollment from the web route query', () {
    for (final value in ['1', 'true', 'yes']) {
      final decoded = GuestQrPayload.decode(
        'https://photos.example/#/event/$eventId?face=$value',
      );
      expect(decoded?.faceEnrollment, isTrue);
    }
  });

  test('reads the hash route event id before unrelated hex in the domain', () {
    final decoded = GuestQrPayload.decode(
      'https://000000000000000000000001.example/#/event/$eventId?face=1',
    );

    expect(decoded?.eventId, eventId);
    expect(decoded?.faceEnrollment, isTrue);
  });

  test('rejects website config that a browser cannot open', () {
    for (final url in [
      'airpix://guest',
      'airpix.app',
      'https:',
      'https://user:password@photos.example',
    ]) {
      expect(
        () => GuestQrPayload.encode(eventId, publicAppUrl: url),
        throwsArgumentError,
      );
    }
  });

  test('keeps legacy mobile QR codes working', () {
    final decoded = GuestQrPayload.decode('mobile:$eventId\nface:1');

    expect(decoded?.eventId, eventId);
    expect(decoded?.faceEnrollment, isTrue);
  });

  test('accepts a web event link and rejects unrelated QR codes', () {
    final decoded = GuestQrPayload.decode(
      'https://photos.example/#/event/$eventId?face=1',
    );

    expect(decoded?.eventId, eventId);
    expect(decoded?.faceEnrollment, isTrue);
    expect(GuestQrPayload.decode('https://example.com/menu'), isNull);
  });

  test('rejects invalid event ids when encoding', () {
    expect(() => GuestQrPayload.encode('not-an-event-id'), throwsArgumentError);
  });
}
