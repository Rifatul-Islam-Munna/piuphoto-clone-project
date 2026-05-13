import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobileapp/core/di/locator.dart';
import 'package:mobileapp/models/user_model.dart';

class UserStorage {
  UserStorage._();

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _userKey = 'current_user';
  static const _seenOnboardingKey = 'seen_onboarding';
  static final ValueNotifier<UserModel?> currentUser = ValueNotifier<UserModel?>(
    null,
  );

  static SharedPreferences get _prefs => getIt<SharedPreferences>();
  static FlutterSecureStorage get _secure => getIt<FlutterSecureStorage>();

  static Future<void> init() async {
    currentUser.value = getUser();
  }

  static Future<void> saveUser(UserModel user, {String? accessToken, String? refreshToken}) async {
    await _prefs.setString(_userKey, jsonEncode(user.toJson()));
    if (accessToken != null) {
      await saveAccessToken(accessToken);
    }
    if (refreshToken != null) {
      await saveRefreshToken(refreshToken);
    }
    currentUser.value = user;
  }

  static Future<void> saveAccessToken(String token) =>
      _secure.write(key: _accessTokenKey, value: token);

  static Future<void> saveRefreshToken(String token) =>
      _secure.write(key: _refreshTokenKey, value: token);

  static Future<String?> getAccessToken() => _secure.read(key: _accessTokenKey);

  static Future<String?> getRefreshToken() => _secure.read(key: _refreshTokenKey);

  static Future<void> saveSeenOnboarding() =>
      Future.wait([
        _secure.write(key: _seenOnboardingKey, value: 'true'),
        _prefs.setBool(_seenOnboardingKey, true),
      ]);

  static Future<bool> hasSeenOnboarding() async {
    final value = await _secure.read(key: _seenOnboardingKey);
    if (value == 'true') {
      return true;
    }

    return _prefs.getBool(_seenOnboardingKey) ?? false;
  }

  static UserModel? getUser() {
    final raw = _prefs.getString(_userKey);
    if (raw == null) return null;
    return UserModel.fromJson(jsonDecode(raw));
  }

  static Future<UserModel?> refreshUserFromStorage() async {
    final user = getUser();
    currentUser.value = user;
    return user;
  }

  static Future<void> clear() async {
    await _secure.delete(key: _accessTokenKey);
    await _secure.delete(key: _refreshTokenKey);
    await _prefs.remove(_userKey);
    currentUser.value = null;
  }
}
