// E2E: andere Sportart mit Puls (FR-0221). Ohne verbundenen Pulssensor ist
// der Start gesperrt und der Nachtrag oeffnet mit "Sonstiges"; mit dem
// Test-Gurt Seilspringen ohne Standortrecht, Live-Ansicht ohne Pace und
// Strecke, Pause und Fortsetzen, Beenden, RPE, Zusammenfassung mit TRIMP und
// Hinweis Wade/Achillessehne, Verlauf ohne Strecke, Detail ohne Karte.
// Synthetischer Puls aus der Debug-Quelle, Ausgabe nur Zaehler und Schluessel.
// Laeuft in der Sammlung (all_test.dart).
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/features/summary/subjective_section.dart';
import 'package:running_app/ui/ui.dart';

import 'support/e2e_support.dart';

const _belt = 'fake-gurt-1';

/// Laufwerte, die eine andere Sportart nie zeigt.
const _runValues = [
  'run_pace',
  'run_avg_pace',
  'run_distance',
  'run_ascent',
  'run_cadence',
  'run_lap',
  'run_laps',
  'live_chip_gps',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Andere Sportart: Sperre ohne Gurt, Seilspringen bis Detail', (
    t,
  ) async {
    step('SPORT start');
    final w = buildWorld();
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    final before = (await t.runAsync(() => s.runs.list()))!.length;

    step('SPORT ohne_sensor');
    await _openSport(t);
    expect(has('other_sport_chest_hint'), isTrue, reason: 'Brustgurt-Hinweis');
    // Der Test-Gurt ist aus frueheren Gruppen bekannt und verbindet sich beim
    // Start der App ggf. automatisch: trennen, bis die Sperre steht.
    final sensors = w.deps.sensors;
    await waitFor(t, () {
      if (sensors.connectedIds.contains(_belt)) sensors.disconnect(_belt);
      return !sensors.autoConnecting &&
          sensors.connectedIds.isEmpty &&
          _goEnabled(t) == false;
    }, 'Start ohne Gurt gesperrt');
    await t.scrollUntilVisible(
      find.byKey(const Key('other_sport_needs_sensor')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tapKey(t, 'other_sport_manual_entry');
    await waitFor(t, () => has('manual_kind_other'), 'Nachtrag offen');
    expect(
      t
          .widget<SubjectiveChoice>(find.byKey(const Key('manual_kind_other')))
          .selected,
      isTrue,
      reason: 'Nachtrag mit Sonstiges',
    );
    await back(t);
    await back(t);

    step('SPORT gurt_verbinden');
    await _sensors(t, () async {
      if (has('sensor_connect_$_belt')) {
        await tapKey(t, 'sensor_connect_$_belt');
      }
      await waitFor(t, () => has('sensor_bpm_$_belt'), 'Test-Gurt verbunden');
    });

    step('SPORT seilspringen');
    await _openSport(t);
    await tapKey(t, 'other_sport_rope');
    await waitFor(t, () => _goEnabled(t) == true, 'Start frei mit Gurt');
    expect(has('other_sport_needs_sensor'), isFalse);
    expect(has('other_sport_rope_hint'), isTrue, reason: 'Hinweis Wade');
    await tapKey(t, 'run_start_ready');
    await waitFor(
      t,
      () => has('run_time') || has('run_block_permissionDenied'),
      'Live-Ansicht oder Sperre',
    );
    expect(
      has('run_block_permissionDenied'),
      isFalse,
      reason: 'kein Standortrecht verlangt',
    );
    expect(has('live_other_sport'), isTrue, reason: 'Sportart in der Live');
    await waitFor(t, () => has('run_hr'), 'Puls in der Live-Ansicht');
    for (final k in _runValues) {
      expect(has(k), isFalse, reason: 'Live ohne $k');
    }

    step('SPORT pause_fortsetzen');
    await pumpFor(t, const Duration(seconds: 4));
    await tapKey(t, 'run_pause');
    await waitFor(t, () => has('run_resume'), 'Pause (run_resume)');
    await pumpFor(t, const Duration(seconds: 2));
    await tapKey(t, 'run_resume');
    await waitFor(t, () => has('run_pause'), 'Fortgesetzt');
    await pumpFor(t, const Duration(seconds: 4));

    step('SPORT beenden');
    await finishRun(t);
    await waitFor(t, () => has('subjective_rpe_5'), 'RPE gefragt');
    await tapKey(t, 'subjective_rpe_5');
    await waitFor(t, () => has('sum_trimp'), 'Zusammenfassung mit TRIMP');
    expect(has('sum_other_sport'), isTrue, reason: 'Sportart-Block');
    expect(has('sum_other_sport_rope_hint'), isTrue, reason: 'Hinweis Wade');
    expect(has('run_distance'), isFalse, reason: 'ohne Strecke');
    expect(has('run_avg_pace'), isFalse, reason: 'ohne Pace');

    step('SPORT gespeichert_pruefen');
    final runs = [...(await t.runAsync(() => s.runs.list()))!]
      ..sort((a, b) => b.id.compareTo(a.id));
    expect(runs.length, before + 1, reason: 'genau eine neue Einheit');
    final done = runs.first;
    expect(done.mode, RunMode.sport, reason: 'andere Sportart');
    final raw = (await t.runAsync(() => s.rawData.read(done.id)))!;
    log('SPORT hr=${raw.heartRates.length} pos=${raw.positions.length}');
    expect(raw.positions, isEmpty, reason: 'ohne Positionen');
    expect(raw.heartRates, isNotEmpty, reason: 'Puls gespeichert');

    step('SPORT verlauf');
    await tapKey(t, 'run_done_close');
    await waitFor(t, () => has('home_history'), 'Heute');
    await tapKey(t, 'home_history');
    await waitFor(t, () => has('history_title'), 'Verlauf');
    await waitFor(t, () => has('history_sport_${done.id}'), 'Eintrag');
    expect(has('history_distance_${done.id}'), isFalse, reason: 'ohne Strecke');
    expect(has('history_pace_${done.id}'), isFalse, reason: 'ohne Pace');

    step('SPORT detail');
    await tapKey(t, 'history_sport_${done.id}');
    await waitFor(t, () => has('detail_started'), 'Detail');
    expect(has('sum_other_sport'), isTrue, reason: 'Sportart im Detail');
    expect(has('detail_route_none'), isFalse, reason: 'ohne Karte');
    expect(has('route_paint'), isFalse, reason: 'ohne Karte');
    expect(has('detail_km_none'), isFalse, reason: 'ohne Splits');
    expect(has('run_distance'), isFalse, reason: 'ohne Strecke');
    log('SPORT ende');
    // Zurueck in den Verlauf (Reiter, kein weiteres Zurueck).
    await back(t);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Sensorverwaltung oeffnen, suchen, [act] ausfuehren, zurueck nach "Heute".
Future<void> _sensors(WidgetTester t, Future<void> Function() act) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'overview_sensors');
  await tapKey(t, 'sensors_scan');
  await waitFor(t, () => has('sensor_$_belt'), 'Test-Gurt gefunden');
  await act();
  await back(t);
  await back(t);
}

/// Start-Seite mit "Andere Sportart".
Future<void> _openSport(WidgetTester t) async {
  await tapKey(t, 'home_start_run');
  await waitFor(t, () => has('treadmill_mode_sport'), 'Start-Seite');
  await tapKey(t, 'treadmill_mode_sport');
  await waitFor(t, () => has('other_sport_card'), 'Sportwahl');
}

/// Ob "Start" frei ist; `null`, solange die Taste nicht im Baum steht.
bool? _goEnabled(WidgetTester t) {
  final b = maybeWidget<RamuriStartButton>(
    find.byKey(const Key('run_start_ready')),
  );
  return b == null ? null : b.onPressed != null;
}
