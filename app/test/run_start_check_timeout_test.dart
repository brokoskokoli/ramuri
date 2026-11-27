// Startprüfung mit Frist (FR-0195, FR-0210, PAR-249): Bleibt eine Antwort
// aus, endet „Prüfe …“ nach der Frist mit dem unbekannten Grund und
// „Erneut prüfen“; ohne Prüfung startet nichts.
import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'settings_gate_storage.dart';

Finder key(String k) => find.byKey(Key(k));

Future<void> _openStartPage(WidgetTester tester) async {
  await tester.tap(key('home_start_run'));
  await tester.pump();
  await tester.pump();
}

/// Wartet die Frist ab: knapp davor noch „Prüfe …“, danach der Grund.
Future<void> _expectUnknownAfterTimeout(WidgetTester tester) async {
  await tester.pump(startCheckTimeout - const Duration(milliseconds: 100));
  expect(key('run_checking'), findsOneWidget, reason: 'vor der Frist');
  expect(key('run_block_unknown'), findsNothing);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
  expect(key('run_checking'), findsNothing, reason: 'nach der Frist');
  expect(key('run_block_unknown'), findsOneWidget);
  expect(key('run_block_recheck'), findsOneWidget);
  expect(key('start_gps_blocked'), findsOneWidget);
}

void main() {
  testWidgets(
    'Stand antwortet nie: nach der Frist unbekannt, Erneut prüfen, kein Start',
    (tester) async {
      final d = Device();
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      d.locationAccess.accessNeverAnswers = true;
      await _openStartPage(tester);
      await _expectUnknownAfterTimeout(tester);
      await tester.tap(key('run_start_ready'));
      await tester.pump();
      expect(key('run_pause'), findsNothing, reason: 'kein Start ohne Prüfung');
      expect(await d.session.runs.list(), isEmpty);
      // Die nächste Prüfung bekommt ihre Antwort: Seite bereit, kein Autostart.
      d.locationAccess.accessNeverAnswers = false;
      await tester.tap(key('run_block_recheck'));
      await tester.pumpAndSettle();
      expect(key('run_block_unknown'), findsNothing);
      expect(key('run_checking'), findsNothing);
      expect(key('start_gps_searching'), findsOneWidget);
      expect(key('run_pause'), findsNothing);
    },
  );

  testWidgets('GPS-Schalter antwortet nie: nach der Frist unbekannt', (
    tester,
  ) async {
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    d.locationAccess.gpsNeverAnswers = true;
    await _openStartPage(tester);
    await _expectUnknownAfterTimeout(tester);
    expect(await d.session.runs.list(), isEmpty);
    d.locationAccess.gpsNeverAnswers = false;
    await tester.tap(key('run_block_recheck'));
    await tester.pumpAndSettle();
    expect(key('start_gps_searching'), findsOneWidget);
  });

  testWidgets('Gemerkte Laufart antwortet nie: nach der Frist unbekannt', (
    tester,
  ) async {
    final d = Device();
    final gate = SettingsGateStorage(d.storage);
    d.storageOverride = gate;
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    final hold = Completer<void>();
    gate.hold = hold;
    await _openStartPage(tester);
    await _expectUnknownAfterTimeout(tester);
    expect(d.locationAccess.requestCount, 0);
    expect(await d.session.runs.list(), isEmpty);
    // Der Speicher antwortet wieder: die nächste Prüfung kommt durch.
    gate.hold = null;
    hold.complete();
    await tester.tap(key('run_block_recheck'));
    await tester.pumpAndSettle();
    expect(key('start_gps_searching'), findsOneWidget);
  });
}
