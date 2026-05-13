import 'package:flutter/services.dart';

class OtgPickedFile {
  const OtgPickedFile({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

class OtgFilePicker {
  OtgFilePicker._();

  static const _channel = MethodChannel('piuphoto/otg_picker');

  static Future<OtgPickedFile?> pickImage() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('pickImage');
    if (result == null) return null;

    final path = result['path']?.toString();
    final name = result['name']?.toString();
    if (path == null || name == null) return null;

    return OtgPickedFile(path: path, name: name);
  }
}
