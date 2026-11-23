import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/models/event_image_model.dart';
import 'package:mobileapp/pages/event_gallery/album_media_tile.dart';

void main() {
  const photo = EventImageModel(
    id: 'photo-1',
    imageUrl: 'https://cdn.example.com/long-uuid-xyz.jpg',
  );

  Future<void> mountTile(
    WidgetTester tester, {
    required VoidCallback onSelect,
    required VoidCallback onView,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              height: 150,
              child: AlbumMediaTile(
                image: photo,
                label: 'Photo 1',
                selected: false,
                onSelect: onSelect,
                onOpen: onView,
                preview: const ColoredBox(color: Colors.green),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('expand icon views without selecting', (tester) async {
    var selected = 0;
    var viewed = 0;
    await mountTile(tester, onSelect: () => selected++, onView: () => viewed++);
    expect(find.text('Photo 1'), findsOneWidget);
    expect(find.textContaining('long-uuid'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('view-photo-photo-1')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(viewed, 1);
    expect(selected, 0);
  });

  testWidgets('double tapping opens viewer while single tapping selects', (
    tester,
  ) async {
    var selected = 0;
    var viewed = 0;
    await mountTile(tester, onSelect: () => selected++, onView: () => viewed++);
    final tile = find.byKey(const ValueKey('album-media-photo-1'));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 400));
    expect(viewed, 1);
    expect(selected, 0);

    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 400));
    expect(selected, 1);
  });
}
