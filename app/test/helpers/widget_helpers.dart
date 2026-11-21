import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import '../support/settle_storage.dart';

/// Gemeinsame Hilfen für Widget-Tests. Ein Name je Bedeutung: Varianten mit
/// anderem Verhalten haben eigene Namen, keine Schalter.

/// Finder für das Widget mit `Key(k)`.
Finder key(String k) => find.byKey(Key(k));

/// Scrollt das Widget mit `Key(k)` sichtbar, tippt es an und wartet mit
/// `pumpAndSettle`.
Future<void> tapKey(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

/// Wie [tapKey] für einen beliebigen Finder, wartet aber zusätzlich vor dem
/// Tippen (Scroll-Animation abwarten).
Future<void> tapFinderAfterSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

/// Lässt Quelle und Kacheln zur Ruhe kommen: wartet, bis [requests] sechs
/// Frames (je 300 ms Testzeit) lang unverändert bleibt; ohne Echtzeit-Pausen
/// ([settleStorage]).
Future<void> settleUntilRequestsStable(
  WidgetTester tester,
  int Function() requests,
) async {
  var last = -1;
  var stable = 0;
  await settleStorage(
    tester,
    until: () => stable >= 6,
    onFrame: () {
      stable = requests() == last ? stable + 1 : 0;
      last = requests();
    },
    what: 'Kachelanfragen sechs Frames lang unverändert',
    frame: const Duration(milliseconds: 300),
  );
}

/// Lässt Lesen, Aufnahme und Speichern zur Ruhe kommen: feste zwölf Frames
/// zu je 100 ms Testzeit, ohne Bedingung und ohne Echtzeit-Pausen
/// ([observeFrames]).
Future<void> settleFixedFrames(WidgetTester tester) =>
    observeFrames(tester, 12, frame: const Duration(milliseconds: 100));

/// MaterialApp mit App-Theme (hell oder dunkel), Sprache und den
/// Lokalisierungen der App, so wie die Widget-Tests sie brauchen. Varianten
/// mit anderem Verhalten (zweites Theme, andere Delegates, Navigator, Router)
/// bleiben im jeweiligen Test.
Widget localizedApp({
  required Widget home,
  Locale locale = const Locale('de'),
  Brightness brightness = Brightness.light,
}) => MaterialApp(
  theme: brightness == Brightness.light ? RamuriTheme.light : RamuriTheme.dark,
  locale: locale,
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);
