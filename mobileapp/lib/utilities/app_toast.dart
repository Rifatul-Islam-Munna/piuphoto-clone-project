import 'package:flutter/material.dart';

class AppToast {
  AppToast._();

  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static void success(String message) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  static void error(String message) {
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }
}

