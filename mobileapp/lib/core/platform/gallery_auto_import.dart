import 'package:flutter/services.dart';

class GalleryImportImage {
  const GalleryImportImage({
    required this.id,
    required this.path,
    required this.name,
  });

  final String id;
  final String path;
  final String name;

  factory GalleryImportImage.fromMap(Map<Object?, Object?> map) {
    return GalleryImportImage(
      id: map['id']?.toString() ?? '',
      path: map['path']?.toString() ?? '',
      name: map['name']?.toString() ?? 'gallery-image.jpg',
    );
  }
}

class GalleryAutoImport {
  const GalleryAutoImport._();

  static const _channel = MethodChannel('piuphoto/gallery_import');

  static Future<List<GalleryImportImage>> recentImages({
    required int sinceMs,
    required List<String> excludeIds,
  }) async {
    final result = await _channel.invokeListMethod<Object?>(
      'recentImages',
      {
        'sinceMs': sinceMs,
        'excludeIds': excludeIds,
      },
    );

    return (result ?? [])
        .whereType<Map<Object?, Object?>>()
        .map(GalleryImportImage.fromMap)
        .where((image) => image.id.isNotEmpty && image.path.isNotEmpty)
        .toList();
  }

  static Future<bool> deleteImage(String id) async {
    return await _channel.invokeMethod<bool>('deleteImage', {'id': id}) ??
        false;
  }
}
