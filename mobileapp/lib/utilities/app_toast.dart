import 'package:flutter/material.dart';
import 'package:mobileapp/core/theme/app_theme.dart';

class AppToast {
  AppToast._();

  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void success(String message) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.success),
    );
  }

  static void error(String message) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: AppColors.destructive),
    );
  }
}
