import 'package:flutter/services.dart';

class DeviceSettings {
  const DeviceSettings._();

  static const _channel = MethodChannel('piuphoto/device_settings');

  static Future<void> openWifiSettings() async {
    await _channel.invokeMethod<void>('openWifiSettings');
  }
}
