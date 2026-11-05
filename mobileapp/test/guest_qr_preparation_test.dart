import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/core/guest/guest_qr_preparation.dart';

void main() {
  testWidgets(
    'successful preparation keeps the transfer page and permits the final QR',
    (tester) async {
      final harness = _PreparationHarness();
      await harness.open(tester);
      await harness.start(tester);

      // Production calls from UploadPage while its transfer route is above it.
      expect(harness.callerRoute.isCurrent, isFalse);
      expect(harness.prepareCalls, 1);
      expect(_loader, findsOneWidget);

      harness.preparation.complete(true);
      await tester.pumpAndSettle();

      expect(await harness.result, isTrue);
      expect(_loader, findsNothing);
      expect(find.text('Transfer session'), findsOneWidget);
      expect(harness.transferRoute.isCurrent, isTrue);
    },
  );

  testWidgets(
    'system Back cancels the QR without later popping the transfer page',
    (tester) async {
      final harness = _PreparationHarness();
      await harness.open(tester);
      await harness.start(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(_loader, findsNothing);
      expect(find.text('Transfer session'), findsOneWidget);

      harness.preparation.complete(true);
      await tester.pumpAndSettle();

      expect(await harness.result, isFalse);
      expect(find.text('Transfer session'), findsOneWidget);
      expect(harness.transferRoute.isCurrent, isTrue);
    },
  );

  testWidgets(
    'a different page stays open and the hidden loading route is removed',
    (tester) async {
      final harness = _PreparationHarness();
      await harness.open(tester);
      await harness.start(tester);
      final anotherRoute = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Another page')),
      );
      unawaited(harness.navigator.push<void>(anotherRoute));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      harness.preparation.complete(true);
      await tester.pumpAndSettle();

      expect(await harness.result, isFalse);
      expect(find.text('Another page'), findsOneWidget);
      expect(anotherRoute.isCurrent, isTrue);
      expect(_loaderIncludingOffstage, findsNothing);

      harness.navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Transfer session'), findsOneWidget);
      expect(harness.transferRoute.isCurrent, isTrue);
    },
  );

  testWidgets('disposing the caller removes only its loading dialog', (
    tester,
  ) async {
    final harness = _PreparationHarness();
    await harness.open(tester);
    await harness.start(tester);

    // The transfer route and root navigator survive the originating page.
    harness.navigator.removeRoute(harness.callerRoute);
    await tester.pump();
    expect(harness.callerContext.mounted, isFalse);
    expect(_loader, findsOneWidget);

    harness.preparation.complete(true);
    await tester.pumpAndSettle();

    expect(await harness.result, isFalse);
    expect(_loader, findsNothing);
    expect(find.text('Transfer session'), findsOneWidget);
    expect(harness.transferRoute.isCurrent, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing the navigator while preparation is pending is safe', (
    tester,
  ) async {
    final harness = _PreparationHarness();
    await harness.open(tester);
    await harness.start(tester);
    await tester.pumpWidget(const SizedBox.shrink());

    harness.preparation.complete(true);
    await tester.pump();

    expect(await harness.result, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed preparation dismisses the loader without permitting QR', (
    tester,
  ) async {
    final harness = _PreparationHarness();
    await harness.open(tester);
    await harness.start(tester);

    harness.preparation.complete(false);
    await tester.pumpAndSettle();

    expect(await harness.result, isFalse);
    expect(_loader, findsNothing);
    expect(harness.transferRoute.isCurrent, isTrue);
  });

  testWidgets('preparation errors clean up only the loader and propagate', (
    tester,
  ) async {
    final harness = _PreparationHarness();
    await harness.open(tester);
    await harness.start(tester);
    final failure = StateError('Preparation failed');
    final reported = expectLater(harness.result, throwsA(same(failure)));

    harness.preparation.completeError(failure);
    await tester.pumpAndSettle();
    await reported;

    expect(_loader, findsNothing);
    expect(find.text('Transfer session'), findsOneWidget);
    expect(harness.transferRoute.isCurrent, isTrue);
  });
}

Finder get _loader => find.byKey(const ValueKey('guest-qr-preparation-dialog'));

Finder get _loaderIncludingOffstage => find.byKey(
  const ValueKey('guest-qr-preparation-dialog'),
  skipOffstage: false,
);

class _PreparationHarness {
  final navigatorKey = GlobalKey<NavigatorState>();
  final preparation = Completer<bool>();
  late BuildContext callerContext;
  late ModalRoute<void> callerRoute;
  late MaterialPageRoute<void> transferRoute;
  late Future<bool> result;
  int prepareCalls = 0;

  NavigatorState get navigator => navigatorKey.currentState!;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) {
            callerContext = context;
            callerRoute = ModalRoute.of<void>(context)!;
            return const Scaffold(body: Text('Workspace'));
          },
        ),
      ),
    );
    transferRoute = MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Transfer session')),
        body: Center(
          child: FilledButton(
            onPressed: () {
              result = runGuestQrPreparation(
                context: callerContext,
                prepare: () {
                  prepareCalls++;
                  return preparation.future;
                },
              );
            },
            child: const Text('Share guest QR'),
          ),
        ),
      ),
    );
    unawaited(navigator.push<void>(transferRoute));
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    await tester.tap(find.text('Share guest QR'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_loader, findsOneWidget);
  }
}
