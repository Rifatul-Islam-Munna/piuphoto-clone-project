import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/guest/guest_qr_payload.dart';

void main() {
  const eventId = '507f1f77bcf86cd799439011';

  test('encodes and decodes the versioned AirPix guest QR', () {
    final encoded = GuestQrPayload.encode(eventId);
    final decoded = GuestQrPayload.decode(encoded);

    expect(encoded, contains('airpix://guest/event/$eventId'));
    expect(decoded?.eventId, eventId);
    expect(decoded?.faceEnrollment, isTrue);
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
