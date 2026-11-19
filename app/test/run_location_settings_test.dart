import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// FR-0195: Standort aus → „Lauf vorbereiten“ öffnet die Standort-Einstellungen
/// des Systems und prüft nach der Rückkehr in den Vordergrund erneut.
Future<void> openStart(
  Device d,
  WidgetTester tester, {
  String locale = 'de',
}) async {
  await d.start(tester, Locale(locale));
  await d.skipSetup(tester);
  await tester.tap(key('home_start_run'));
  await tester.pumpAndSettle();
}

Future<void> leaveAndReturn(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Standort aus: Knopf öffnet die Einstellungen, Erklärung bleibt',
    (tester) async {
      final d = Device()..locationAccess.gps = false;
      await openStart(d, tester);
      expect(key('run_block_gpsOff'), findsOneWidget);
      expect(find.textContaining('Schnelleinstellungen'), findsOneWidget);
      expect(find.text('Standort-Einstellungen öffnen'), findsOneWidget);
      // Kein Rechtedialog und keine App-Einstellungen bei ausgeschaltetem GPS.
      expect(key('run_block_ask'), findsNothing);
      expect(key('run_block_settings'), findsNothing);
      expect(key('run_block_recheck'), findsOneWidget);
      expect(d.locationAccess.openSettingsCount, 0);

      await tester.tap(key('run_block_location_settings'));
      await tester.pumpAndSettle();
      expect(d.locationAccess.openSettingsCount, 1);
      expect(d.permissions.openSettingsCount, 0);
      expect(d.locationAccess.requestCount, 0);

      // Standort im System eingeschaltet, zurück in die App: Sperre weg.
      d.locationAccess.gps = true;
      await leaveAndReturn(tester);
      expect(key('run_block_gpsOff'), findsNothing);
      expect(key('run_block_location_settings'), findsNothing);
      expect(key('start_gps_blocked'), findsNothing);
      // Gestartet wird erst mit dem Tippen (FR-0195).
      expect(key('run_pause'), findsNothing);
      expect(await d.session.runs.list(), isEmpty);
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      expect(key('run_pause'), findsOneWidget);
    },
  );

  testWidgets('Rückkehr mit weiter ausgeschaltetem Standort: Sperre bleibt', (
    tester,
  ) async {
    final d = Device()..locationAccess.gps = false;
    await openStart(d, tester);
    await tester.tap(key('run_block_location_settings'));
    await tester.pumpAndSettle();
    await leaveAndReturn(tester);
    expect(key('run_block_gpsOff'), findsOneWidget);
    expect(key('run_block_location_settings'), findsOneWidget);
    expect(await d.session.runs.list(), isEmpty);
  });

  testWidgets('Einstellungen nicht zu öffnen: kein Absturz, Sperre bleibt', (
    tester,
  ) async {
    final d = Device()
      ..locationAccess.gps = false
      ..locationAccess.settingsOpen = false;
    await openStart(d, tester);
    await tester.tap(key('run_block_location_settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(key('run_block_gpsOff'), findsOneWidget);
    // Erneut prüfen geht weiterhin von Hand.
    d.locationAccess.gps = true;
    await tester.tap(key('run_block_recheck'));
    await tester.pumpAndSettle();
    expect(key('run_block_gpsOff'), findsNothing);
    expect(key('run_start_ready'), findsOneWidget);
  });

  testWidgets('Nur bei ausgeschaltetem Standort, nicht bei fehlendem Recht', (
    tester,
  ) async {
    final d = Device()..locationAccess.current = LocationAccess.denied;
    await openStart(d, tester);
    expect(key('run_block_permissionDenied'), findsOneWidget);
    expect(key('run_block_location_settings'), findsNothing);
  });

  testWidgets('Nur ungefährer Standort: kein Knopf zu den Einstellungen', (
    tester,
  ) async {
    final d = Device()..locationAccess.current = LocationAccess.approximateOnly;
    await openStart(d, tester);
    expect(key('run_block_approximateOnly'), findsOneWidget);
    expect(key('run_block_location_settings'), findsNothing);
    // Hauptknopf bleibt die Rechteabfrage.
    expect(tester.widget(key('run_block_ask')), isA<FilledButton>());
    expect(tester.widget(key('run_block_recheck')), isA<TextButton>());
  });

  testWidgets('Stand nicht prüfbar: kein Knopf, Erneut prüfen bleibt Haupt', (
    tester,
  ) async {
    final d = Device()..locationAccess.fail = true;
    await openStart(d, tester);
    expect(key('run_block_unknown'), findsOneWidget);
    expect(key('run_block_location_settings'), findsNothing);
    expect(key('run_block_ask'), findsNothing);
    expect(tester.widget(key('run_block_recheck')), isA<FilledButton>());
  });

  testWidgets('Englisch: Open location settings', (tester) async {
    final d = Device()..locationAccess.gps = false;
    await openStart(d, tester, locale: 'en');
    expect(find.text('Open location settings'), findsOneWidget);
  });
}
