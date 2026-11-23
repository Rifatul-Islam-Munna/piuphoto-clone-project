import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/router/app_router.dart';
import 'package:mobileapp/models/user_model.dart';

void main() {
  test(
    'photographer navigation prioritizes Albums and keeps all destinations',
    () {
      const photographer = UserModel(role: 'photographer');
      final items = buildShellItems(photographer);
      expect(items.map((item) => item.label).toList(), [
        'Albums',
        'Studio',
        'Invites',
        'Profile',
      ]);
      expect((items.first.icon as Icon).icon, Icons.photo_library_outlined);
      expect((items[1].icon as Icon).icon, Icons.camera_roll_outlined);
    },
  );

  test('non-photographer navigation stays in its original order', () {
    final items = buildShellItems(const UserModel(role: 'user'));
    expect(items.map((item) => item.label).toList(), [
      'Overview',
      'Events',
      'Plans',
      'Profile',
    ]);
  });
}
