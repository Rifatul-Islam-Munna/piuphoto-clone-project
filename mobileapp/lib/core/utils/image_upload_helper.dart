import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobileapp/core/network/dio_helper.dart';

class PickedAppImage {
  const PickedAppImage({
    required this.path,
    required this.name,
  });

  final String path;
  final String name;
}

class ImageUploadHelper {
  ImageUploadHelper._();

  static final ImagePicker _picker = ImagePicker();

  static Future<PickedAppImage?> pickFromGallery() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (image == null) return null;

    return PickedAppImage(
      path: image.path,
      name: image.name,
    );
  }

  static Future<String> uploadFile({
    required String path,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: filename,
      ),
    });
    final response = await DioHelper.post('/image/upload', data: formData);
    return response.data['url']?.toString() ?? '';
  }
}
