import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

/// Letzter Stil, den die Region unter [finder] liefert (wie ihn Flutter
/// für die Systemleiste an der Stelle wählt).
SystemUiOverlayStyle _styleAt(WidgetTester tester, Finder finder) {
  final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
    find
        .ancestor(
          of: finder,
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        )
        .first,
  );
  return region.value;
}

void main() {
  testWidgets('Ladeansichten im hellen System: Nacht-Grund, kein Hellblitz', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final d = Device();
    await d.start(tester, const Locale('de'), welcome: true, settle: false);
    var seen = 0;
    for (var i = 0; i < 20; i++) {
      for (final e in find.byType(CircularProgressIndicator).evaluate()) {
        seen++;
        expect(Theme.of(e).brightness, Brightness.dark);
        expect(
          Theme.of(e).scaffoldBackgroundColor,
          RamuriColors.night.background,
        );
      }
      await tester.pump();
    }
    expect(seen, greaterThan(0));
    await tester.pumpAndSettle();
    expect(key('welcome_screen'), findsOneWidget);
  });

  testWidgets('Statusleiste: Dunkel-Fläche hell, Heute folgt dem Theme', (
    tester,
  ) async {
    for (final (mode, icons) in [
      (Brightness.light, Brightness.dark),
      (Brightness.dark, Brightness.light),
    ]) {
      tester.platformDispatcher.platformBrightnessTestValue = mode;
      final d = Device();
      await d.start(tester, const Locale('de'), welcome: true);
      // Willkommen: immer helle Symbole.
      expect(
        _styleAt(tester, key('welcome_screen')).statusBarIconBrightness,
        Brightness.light,
      );
      await d.stop(tester);
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      // Heute (keine App-Leiste): Symbole nach Helligkeit des Themes.
      expect(key('home_screen'), findsOneWidget);
      expect(
        _styleAt(tester, key('home_screen')).statusBarIconBrightness,
        icons,
      );
      await d.stop(tester);
    }
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  });
}
