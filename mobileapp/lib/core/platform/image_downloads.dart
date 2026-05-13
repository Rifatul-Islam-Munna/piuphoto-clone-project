import 'dart:typed_data';

import 'package:flutter/services.dart';

class ImageDownloads {
  const ImageDownloads._();

  static const _channel = MethodChannel('piuphoto/image_downloads');

  static Future<bool> saveImage({
    required Uint8List bytes,
    required String filename,
  }) async {
    return await _channel.invokeMethod<bool>(
          'saveImage',
          {
            'bytes': bytes,
            'filename': filename,
          },
        ) ??
        false;
  }
}
