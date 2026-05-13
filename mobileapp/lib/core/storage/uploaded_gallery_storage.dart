import 'dart:convert';

import 'package:mobileapp/core/di/locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UploadedGalleryImage {
  const UploadedGalleryImage({
    required this.id,
    required this.name,
    required this.uploadedAt,
  });

  final String id;
  final String name;
  final int uploadedAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'uploadedAt': uploadedAt,
    };
  }

  factory UploadedGalleryImage.fromJson(Map<String, dynamic> json) {
    return UploadedGalleryImage(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'image',
      uploadedAt: int.tryParse(json['uploadedAt']?.toString() ?? '') ?? 0,
    );
  }
}

class UploadedGalleryStorage {
  UploadedGalleryStorage._();

  static const _key = 'uploaded_gallery_images';

  static SharedPreferences get _prefs => getIt<SharedPreferences>();

  static List<UploadedGalleryImage> getImages() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];

    final data = jsonDecode(raw);
    if (data is! List) return [];

    return data
        .whereType<Map>()
        .map((item) => UploadedGalleryImage.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((image) => image.id.isNotEmpty)
        .toList();
  }

  static Future<void> add({
    required String id,
    required String name,
  }) async {
    final images = getImages();
    if (images.any((image) => image.id == id)) return;

    images.add(
      UploadedGalleryImage(
        id: id,
        name: name,
        uploadedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    await _save(images);
  }

  static Future<void> removeIds(Set<String> ids) async {
    final images = getImages()
        .where((image) => !ids.contains(image.id))
        .toList(growable: false);
    await _save(images);
  }

  static Future<void> _save(List<UploadedGalleryImage> images) async {
    await _prefs.setString(
      _key,
      jsonEncode(images.map((image) => image.toJson()).toList()),
    );
  }
}
