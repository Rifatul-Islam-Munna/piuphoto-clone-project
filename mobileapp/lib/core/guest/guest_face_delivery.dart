import 'package:mobileapp/core/network/dio_helper.dart';

/// Reuses enabled guest delivery without requiring permission to edit settings.
/// Enabling delivery still uses the existing permission and consent rules.
Future<void> ensureGuestFaceDeliveryEnabled(String eventId) async {
  if (await _guestFaceDeliveryEnabled(eventId)) return;

  await DioHelper.patch(
    '/gallery-access/settings',
    data: {
      'eventId': eventId,
      'faceSearchEnabled': true,
      'faceConsentRequired': true,
    },
  );
  if (!await _guestFaceDeliveryEnabled(eventId)) {
    throw StateError('Face delivery was not enabled');
  }
}

Future<bool> _guestFaceDeliveryEnabled(String eventId) async {
  final response = await DioHelper.get(
    '/gallery-access/info',
    queryParameters: {'eventId': eventId},
  );
  final info = response.data;
  return info is Map && info['faceSearchEnabled'] == true;
}
