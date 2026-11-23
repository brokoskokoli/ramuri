import 'package:adapters/map_testing.dart';
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

/// Wartet, bis die Kachelarbeit fertig ist: keine Anfrage an [net] offen
/// (`active == 0`) und seit dem vorigen Frame keine neue Anfrage dazu – in
/// zwei aufeinanderfolgenden Frames (über [settleReal], mit Obergrenze und
/// Meldung).
///
/// Warum zwei Frames: Nach einer Antwort ist kurz keine Anfrage offen, aber
/// die Dekodierung (Stil, TileJSON, Kacheln, in Isolates und mit echter Zeit)
/// kann noch Folgeanfragen auslösen. Erst wenn die Bedingung über zwei Frames
/// hält – also über die volle Echtzeitscheibe des zweiten Frames, in der
/// keine Folgeanfrage kam –, gilt die Arbeit als fertig, und der Helfer
/// endet, statt wie früher sechs Frames Stillstand abzuwarten.
///
/// Der erste Frame vergleicht mit der Anfragezahl beim Aufruf. Gibt die Zahl
/// der Frames zurück; nach [maxFrames] Frames schlägt der Test fehl, die
/// Meldung nennt „keine Kachelanfrage offen“.
Future<int> settleUntilMapIdle(
  WidgetTester tester,
  FakeInner net, {
  int maxFrames = 250,
}) {
  var last = net.requests.length;
  var idleFrames = 0;
  return settleReal(
    tester,
    until: () => idleFrames >= 2,
    onFrame: () {
      final n = net.requests.length;
      idleFrames = net.active == 0 && n == last ? idleFrames + 1 : 0;
      last = n;
    },
    what: 'keine Kachelanfrage offen',
    frame: const Duration(milliseconds: 300),
    realSlice: const Duration(milliseconds: 40),
    maxFrames: maxFrames,
  );
}

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
