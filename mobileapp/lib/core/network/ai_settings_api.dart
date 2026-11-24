import 'package:flutter/foundation.dart';
import 'package:mobileapp/core/network/dio_helper.dart';

/// Event GET returns a plain object; some API versions wrap it in data.
/// Keep all AI controls on the same response contract and refresh them when
/// another screen saves settings for the same event.
class AiSettingsApi {
  static final changes = ValueNotifier<String?>(null);

  static Map<String, dynamic> eventFromResponse(Object? response) {
    if (response is! Map) throw const FormatException('Invalid event response');
    final raw = response['data'] is Map ? response['data'] as Map : response;
    if (raw['_id'] == null && raw['id'] == null) {
      throw const FormatException('Missing event');
    }
    return Map<String, dynamic>.from(raw);
  }

  static Future<Map<String, dynamic>> readEvent(String eventId) async {
    final response = await DioHelper.get(
      '/event/get-one',
      queryParameters: {'id': eventId},
    );
    return eventFromResponse(response.data);
  }

  static Future<Map<String, dynamic>> readAlbum(
    String eventId,
    String albumId,
  ) async {
    final response = await DioHelper.get(
      '/album/get-all',
      queryParameters: {'eventId': eventId},
    );
    final raw = response.data;
    final rows = raw is Map ? raw['data'] : raw;
    if (rows is! List) throw const FormatException('Invalid album response');
    for (final row in rows.whereType<Map>()) {
      if ((row['_id'] ?? row['id']).toString() == albumId)
        return Map<String, dynamic>.from(row);
    }
    throw StateError('Album not found');
  }

  static Future<({Map<String, dynamic> event, Map<String, dynamic> scope})>
  read(String eventId, String? albumId) async {
    if (albumId == null) {
      final event = await readEvent(eventId);
      return (event: event, scope: event);
    }
    final results = await Future.wait([
      readEvent(eventId),
      readAlbum(eventId, albumId),
    ]);
    return (event: results[0], scope: results[1]);
  }

  static bool enabled(Map<String, dynamic> event, Map<String, dynamic> scope) =>
      (scope['autoEnhanceImages'] ?? event['autoEnhanceImages']) == true;

  static final _pendingSaves = <String, Future<void>>{};

  // Upload registration must observe a switch change that is already saving.
  // On failure, the UI reports the error and the server's previous value wins.
  static Future<void> waitForSave(String eventId) async {
    while (true) {
      final pending = _pendingSaves[eventId];
      if (pending == null) return;
      try {
        await pending;
      } catch (_) {}
      if (identical(_pendingSaves[eventId], pending)) return;
    }
  }

  static Future<void> save(
    String eventId,
    String? albumId,
    Map<String, dynamic> settings,
  ) {
    final previous = _pendingSaves[eventId];
    final pending = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (_) {}
      }
      await DioHelper.patch(
        albumId == null ? '/event/update' : '/album/update',
        queryParameters: {'id': albumId ?? eventId},
        data: settings,
      );
      changes.value = null;
      changes.value = eventId;
    }();
    _pendingSaves[eventId] = pending;
    return pending.whenComplete(() {
      if (identical(_pendingSaves[eventId], pending))
        _pendingSaves.remove(eventId);
    });
  }
}
