import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/pages/upload/event_live_preview_page.dart';

void main() {
  test('preview records retain the publication state and timestamp', () {
    final photo = LiveEventPhoto.fromJson({
      '_id': 'one',
      'imageUrl': 'https://photos.example.test/one.jpg',
      'createdAt': '2026-11-19T15:30:00Z',
      'isPublished': false,
      'mediaType': 'photo',
    });
    expect(photo.id, 'one');
    expect(photo.isPublished, isFalse);
    expect(photo.createdAt.year, 2026);
  });

  testWidgets('Photo Live groups photos, loads older items and refreshes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    });

    var fresh = false;
    final pages = <int>[];
    final day1 = DateTime(2026, 11, 19, 15);
    final day2 = DateTime(2026, 11, 19, 13);
    Future<LiveEventPhotoPage> loader(int page) async {
      pages.add(page);
      if (page == 1) {
        return LiveEventPhotoPage(
          photos: [
            LiveEventPhoto(
              id: 'shot-1',
              imageUrl: '',
              createdAt: day1,
              mediaType: 'video',
            ),
            if (fresh)
              LiveEventPhoto(
                id: 'shot-3',
                imageUrl: '',
                createdAt: day1,
                mediaType: 'video',
              ),
          ],
          total: fresh ? 3 : 2,
          hasMore: !fresh,
        );
      }
      return LiveEventPhotoPage(
        photos: [
          LiveEventPhoto(
            id: 'shot-2',
            imageUrl: '',
            createdAt: day2,
            mediaType: 'video',
            isPublished: false,
          ),
        ],
        total: 2,
        hasMore: false,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: EventLivePreviewPage(
          eventId: 'event',
          eventTitle: 'Nikos',
          loadPhotos: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Photo Live'), findsWidgets);
    expect(find.text('Nikos'), findsOneWidget);
    expect(find.text('1 loaded · 2 event uploads'), findsOneWidget);
    expect(find.byKey(const ValueKey('live-photo-shot-1')), findsOneWidget);

    await tester.ensureVisible(find.text('Load older photos'));
    await tester.tap(find.text('Load older photos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-photo-shot-2')), findsOneWidget);
    expect(find.text('Not published'), findsOneWidget);

    fresh = true;
    await tester.tap(find.byTooltip('Refresh live photos'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('live-photo-shot-3')), findsOneWidget);
    expect(find.text('3 loaded · 3 event uploads'), findsOneWidget);
    expect(pages, containsAllInOrder([1, 2, 1]));
  });
}
