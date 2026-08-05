import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terrax/ui/splash.dart';
import 'package:terrax/ui/theme.dart';

void main() {
  Widget app() => MaterialApp(
        theme: terraxTheme(),
        home: const SplashGate(child: Scaffold(body: Text('home'))),
      );

  /// The splash draws nothing until the brand PNGs decode. That is real
  /// async IO, which fake-async pumps never run — runAsync lets it finish.
  Future<void> pumpUntilArtReady(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      if (tester.any(find.byType(TerraxAppTitle))) return;
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    fail('splash art never became ready');
  }

  testWidgets('holds the centred logo, then flies and removes itself',
      (tester) async {
    await tester.pumpWidget(app());
    await pumpUntilArtReady(tester);

    final held = tester.getCenter(find.byType(TerraxAppTitle));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(held.dx, closeTo(screen.width / 2, 1));
    expect(held.dy, closeTo(screen.height / 2, 1));

    // Mid-flight it has left centre, moving up and left.
    await tester.pump(const Duration(milliseconds: 800)); // hold elapses
    await tester.pump(const Duration(milliseconds: 450));
    final flying = tester.getCenter(find.byType(TerraxAppTitle));
    expect(flying.dx, lessThan(held.dx));
    expect(flying.dy, lessThan(held.dy));

    // Once done the overlay is removed entirely and the app is visible.
    await tester.pumpAndSettle();
    expect(find.byType(TerraxAppTitle), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('lands on the app-bar title position', (tester) async {
    await tester.pumpWidget(app());
    await pumpUntilArtReady(tester);
    await tester.pump(const Duration(milliseconds: 800));
    // End of flight, before the overlay is disposed.
    await tester.pump(const Duration(milliseconds: 899));
    final topLeft = tester.getTopLeft(find.byType(TerraxAppTitle));
    // AppBar titleSpacing = 16; title centred in the toolbar (~20px row).
    expect(topLeft.dx, closeTo(16, 2));
    expect(topLeft.dy, closeTo((kToolbarHeight - 20) / 2, 2));
  });
}
