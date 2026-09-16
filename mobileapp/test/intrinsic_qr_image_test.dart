import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/widgets/intrinsic_qr_image.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  const testPayload = 'airpix://guest/event/507f1f77bcf86cd799439011?v=1&face=1';

  // Regression test: an AlertDialog measures its content with IntrinsicWidth
  // before layout. QrImageView wraps its painter in a LayoutBuilder, which
  // throws "LayoutBuilder does not support returning intrinsic dimensions"
  // in that situation. IntrinsicQrImage must be safe here.
  Future<void> showQrDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('shell')),
        ),
      ),
    );

    final dialogContext = tester.element(find.text('shell'));
    unawaited(
      showDialog<void>(
        context: dialogContext,
        useRootNavigator: true,
        builder: (_) => AlertDialog(
        title: const Text('Guest face-delivery QR'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ColoredBox(
              color: Colors.white,
              child: IntrinsicQrImage(data: testPayload, size: 230),
            ),
            const SizedBox(height: 12),
            const Text('Scan in AirPix'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () {},
            child: const Text('Done'),
          ),
        ],
      ),
      ),
    );
    await tester.pumpAndSettle();
  }

  RenderCustomPaint qrPaintFinder(WidgetTester tester) {
    return tester.renderObject<RenderCustomPaint>(
      find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is QrPainter,
      ),
    );
  }

  testWidgets('QR renders inside an AlertDialog without intrinsic errors',
      (tester) async {
    await showQrDialog(tester);

    expect(tester.takeException(), isNull);

    // The painted QR modules must be visible (not a collapsed 0x0 box).
    final paintBounds = qrPaintFinder(tester).paintBounds;
    expect(paintBounds.width, greaterThan(100));
    expect(paintBounds.height, greaterThan(100));
  });

  testWidgets('falls back to a placeholder when the data cannot be encoded',
      (tester) async {
    // Far exceeds the maximum QR capacity, so validation must fail.
    final oversizedData = 'A' * 4000;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IntrinsicWidth(
            child: IntrinsicQrImage(data: oversizedData, size: 230),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.qr_code), findsOneWidget);
  });

  testWidgets('uses a valid QR error-correction level', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: IntrinsicQrImage(
            data: testPayload,
            size: 230,
            errorCorrectionLevel: QrErrorCorrectLevel.Q,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final customPaint = qrPaintFinder(tester);
    expect(customPaint.paintBounds.longestSide, closeTo(230 - 20, 0.5));
  });
}
