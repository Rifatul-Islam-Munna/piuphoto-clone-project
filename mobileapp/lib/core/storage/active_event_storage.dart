import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/models/event_invitation_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActiveEventStorage {
  ActiveEventStorage._();

  static const _activeEventKey = 'active_event';
  static final ValueNotifier<EventSummary?> activeEvent =
      ValueNotifier<EventSummary?>(null);

  static SharedPreferences get _prefs => getIt<SharedPreferences>();

  static Future<void> init() async {
    activeEvent.value = getActiveEvent();
  }

  static EventSummary? getActiveEvent() {
    final raw = _prefs.getString(_activeEventKey);
    if (raw == null) return null;

    return EventSummary.fromJson(
      Map<String, dynamic>.from(jsonDecode(raw) as Map),
    );
  }

  static Future<void> saveActiveEvent(EventSummary event) async {
    await _prefs.setString(_activeEventKey, jsonEncode(event.toJson()));
    activeEvent.value = event;
  }

  static Future<void> clear() async {
    await _prefs.remove(_activeEventKey);
    activeEvent.value = null;
  }
}
