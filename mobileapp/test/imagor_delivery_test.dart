import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/utils/image_loader.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';

void main() {
  test('recognizes signed and extensionless cached AVIF URLs', () {
    expect(
      ImageLoader.isAvifUrl(
        'https://img.example/signed/fit-in/720x720/filters:format(avif)/piuphoto/a.jpg',
      ),
      isTrue,
    );
    expect(
      ImageLoader.isAvifUrl('https://cache.example/aa/bb/hash?format=avif'),
      isTrue,
    );
    expect(ImageLoader.isAvifUrl('https://cache.example/test.AVIF'), isTrue);
    expect(ImageLoader.isAvifUrl('https://cache.example/a.jpg'), isFalse);
  });
  test('display variants never overwrite the original download URL', () {
    final image = EventImageModel.fromJson({
      '_id': 'photo',
      'imageUrl': 'https://originals.example/file.jpg',
      'previewUrl': 'https://cache.example/preview?format=avif',
      'viewUrl': 'https://cache.example/view?format=avif',
    });
    expect(image.displayUrl, contains('preview'));
    expect(image.fullViewUrl, contains('view'));
    expect(image.imageUrl, endsWith('file.jpg'));
    final legacy = EventImageModel.fromJson({
      '_id': 'old',
      'imageUrl': 'https://originals.example/old.jpg',
    });
    expect(legacy.displayUrl, legacy.imageUrl);
    expect(legacy.fullViewUrl, legacy.imageUrl);
  });
  test('transfer ledger keeps preview independently of retry source', () {
    final item = TransferLedgerItem.fromJson({
      'id': '1',
      'imageUrl': 'https://originals.example/a.jpg',
      'previewUrl': 'https://cache.example/a?format=avif',
    });
    expect(item.displayUrl, item.previewUrl);
    expect(item.imageUrl, endsWith('a.jpg'));
    final restored = TransferLedgerItem.fromJson(item.toJson());
    expect(restored.displayUrl, item.displayUrl);
    expect(restored.imageUrl, item.imageUrl);
  });
}
