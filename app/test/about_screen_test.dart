import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/settings/about_screen.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show started;

Future<DeveloperModeStore> _store() async {
  final session = await FakeStorage().open(Uint8List(32));
  return SettingsDeveloperModeStore(
    session.settings,
    FakeClock(DateTime.utc(2026, 11, 14)),
  );
}

Future<void> _pump(
  WidgetTester tester,
  DeveloperModeStore store, {
  String locale = 'de',
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: Locale(locale),
      theme: RamuriTheme.light,
      darkTheme: RamuriTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: AboutScreen(
        developerMode: store,
        appVersion: () async => '0.1.0 (12)',
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVersion(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    await tester.tap(key('about_version'));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Name, Version, Lizenzen; ohne Modus kein Abschnitt Entwickler', (
    tester,
  ) async {
    await _pump(tester, await _store());
    expect(find.text('Über'), findsOneWidget);
    expect(find.text('Version 0.1.0 (12)'), findsOneWidget);
    expect(key('about_licenses'), findsOneWidget);
    expect(key('about_dev_section'), findsNothing);
    expect(key('about_dev_badge'), findsNothing);
    expect(key('about_toast'), findsNothing);
  });

  testWidgets('9 Tipps schalten nicht ein, Zähler erst ab dem 7. Tipp', (
    tester,
  ) async {
    final store = await _store();
    await _pump(tester, store);
    await _tapVersion(tester, 6);
    expect(key('about_toast'), findsNothing);
    await _tapVersion(tester, 1);
    expect(find.text('Noch 3 Tipps bis zum Entwicklermodus'), findsOneWidget);
    await _tapVersion(tester, 1);
    expect(find.text('Noch 2 Tipps bis zum Entwicklermodus'), findsOneWidget);
    await _tapVersion(tester, 1);
    expect(find.text('Noch 1 Tipp bis zum Entwicklermodus'), findsOneWidget);
    expect(await store.read(), isFalse);
    expect(key('about_dev_section'), findsNothing);
    expect(key('about_dev_badge'), findsNothing);
  });

  testWidgets('10 Tipps schalten ein; Abschnitt, Hinweis, gespeichert', (
    tester,
  ) async {
    final store = await _store();
    await _pump(tester, store);
    await _tapVersion(tester, 10);
    expect(await store.read(), isTrue);
    expect(find.text('Entwicklermodus an'), findsNWidgets(2)); // Hinweis, Toast
    expect(key('about_dev_badge'), findsOneWidget);
    expect(find.text('Entwickler'), findsOneWidget);
    expect(key('about_dev_switch'), findsOneWidget);
  });

  testWidgets('Schalter schaltet aus, Zähler beginnt neu', (tester) async {
    final store = await _store();
    await store.set(true);
    await _pump(tester, store);
    expect(key('about_dev_section'), findsOneWidget);
    expect(key('about_toast'), findsNothing);
    await tester.tap(key('about_dev_switch'));
    await tester.pumpAndSettle();
    expect(await store.read(), isFalse);
    expect(key('about_dev_section'), findsNothing);
    expect(key('about_dev_badge'), findsNothing);
    // 9 Tipps danach schalten wieder nicht ein.
    await _tapVersion(tester, 9);
    expect(await store.read(), isFalse);
  });

  testWidgets('Englisch, dunkel: Texte und Abschnitt', (tester) async {
    final store = await _store();
    await store.set(true);
    await _pump(tester, store, locale: 'en', dark: true);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Version 0.1.0 (12)'), findsOneWidget);
    expect(find.text('Developer mode on'), findsOneWidget);
    expect(find.text('Developer'), findsOneWidget);
    expect(find.text('Licenses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Version unbekannt, wenn das System keine liefert', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        theme: RamuriTheme.light,
        home: AboutScreen(
          developerMode: await _store(),
          appVersion: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version unbekannt'), findsOneWidget);
  });

  testWidgets('Übersicht: Über zeigt den Modus aus der Sitzung (Verdrahtung)', (
    tester,
  ) async {
    final d = await started(tester);
    await SettingsDeveloperModeStore(d.session.settings, d.clock).set(true);
    await openOverview(tester);
    await tester.tap(key('overview_about'));
    await tester.pumpAndSettle();
    expect(key('about_dev_badge'), findsOneWidget);
  });
}
