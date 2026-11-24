import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/pages/event_gallery/album_retouch_controls.dart';
import 'package:mobileapp/core/upload/transfer_ledger_storage.dart';
import 'package:mobileapp/widgets/ai_retouch_badge.dart';

void main() {
  test('scene defaults and portrait limits mirror the backend', () {
    final values = retouchValues('low_light', {
      'photo': {'noise': 0},
      'male': {'blemish': 50},
      'child': {'blemish': 80},
    });
    expect(values['photo']!['shadows'], 95);
    expect(values['photo']!['noise'], 0);
    expect(values['male']!['blemish'], 40);
    expect(values['female']!['blemish'], 20);
    expect(values['child']!['blemish'], 15);
  });

  testWidgets(
    'portrait and photo sliders are independently adjustable and resettable',
    (tester) async {
      var values = retouchValues('sports');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (context, setState) => AlbumRetouchControls(
                  preset: 'sports',
                  values: values,
                  enabled: true,
                  onChanged: (next) => setState(() => values = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('retouch-preset-details')));
      await tester.pumpAndSettle();
      final blemish = find.byKey(const ValueKey('retouch-female-blemish'));
      tester.widget<Slider>(blemish).onChanged!(35);
      await tester.pumpAndSettle();
      expect(values['female']!['blemish'], 35);
      expect(values['male']!['blemish'], 20);
      await tester.tap(find.text('Child'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('retouch-child-blemish')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('retouch-child-forehead')),
        findsNothing,
      );
      await tester.tap(find.text('Photo correction'));
      await tester.pumpAndSettle();
      final blur = find.byKey(const ValueKey('retouch-photo-deblur'));
      expect(tester.widget<Slider>(blur).value, 90);
      tester.widget<Slider>(blur).onChanged!(0);
      await tester.pumpAndSettle();
      expect(values['photo']!['deblur'], 0);
      final reset = find.text('Reset preset details');
      await tester.ensureVisible(reset);
      await tester.pumpAndSettle();
      await tester.tap(reset);
      await tester.pumpAndSettle();
      expect(values['photo']!['deblur'], 90);
      expect(values['female']!['blemish'], 20);
    },
  );

  test(
    'upload status is persisted separately from actual enhanced-image identity',
    () {
      const original = TransferLedgerItem(
        id: '1',
        eventId: 'event',
        eventTitle: 'Event',
        filename: 'photo.jpg',
        source: 'camera',
        status: TransferLedgerStatus.published,
        createdAt: 1,
        updatedAt: 2,
        eventImageId: 'source-id',
        enhancementStatus: 'processing',
        progress: 100,
      );
      final restored = TransferLedgerItem.fromJson(original.toJson());
      expect(restored.aiLabel, 'AI processing');
      expect(restored.aiPending, isTrue);
      final complete = restored.copyWith(enhancementStatus: 'completed');
      expect(complete.isUploaded, isTrue);
      expect(complete.isEnhanced, isFalse);
      expect(complete.aiLabel, 'AI copy ready');
      expect(complete.copyWith(isEnhanced: true).aiLabel, 'AI enhanced');
    },
  );

  testWidgets(
    'AI badge has sparkle icon only for actual enhanced or AI status',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AiRetouchBadge(label: 'Original'),
                AiRetouchBadge(label: 'AI enhanced'),
              ],
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.auto_awesome_rounded), findsOneWidget);
      expect(find.text('Original'), findsOneWidget);
      expect(find.text('AI enhanced'), findsOneWidget);
    },
  );
}
