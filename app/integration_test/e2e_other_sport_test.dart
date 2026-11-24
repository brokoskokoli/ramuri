// E2E: andere Sportart mit Puls (FR-0221). Ohne verbundenen Pulssensor ist
// der Start gesperrt und der Nachtrag oeffnet mit "Sonstiges"; mit dem
// Test-Gurt Seilspringen ohne Standortrecht, Live-Ansicht ohne Pace und
// Strecke, Pause und Fortsetzen, Beenden, RPE, Zusammenfassung mit TRIMP und
// Hinweis Wade/Achillessehne, Verlauf ohne Strecke, Detail ohne Karte.
// Synthetischer Puls aus der Debug-Quelle, Ausgabe nur Zaehler und Schluessel.
// Laeuft in der Sammlung (all_test.dart).
//
// Mit --dart-define=SPORT_PLAN=true laeuft statt dessen der Ersatz einer
// lockeren Einheit (FR-0222, PAR-233): Profil und Ziel ueber die Oberflaeche
// (ein Lauftag heute, hoechstens 3 min je Einheit, also heute eine lockere
// Einheit von 3 min), "Einheit starten", "Andere Sportart", Seilspringen. Zuerst
// mit hohem Puls: keine Zuordnung, Grund "zu intensiv", Einheit bleibt offen.
// Dann mit Puls im lockeren Bereich ueber zwei Drittel der geplanten Dauer:
// Hinweis "Ersetzt den Ausdauerreiz ...", Einheit im Plan erledigt. Eigene
// Stufe sport-plan (tool/ci_e2e.sh), weil sie einen frischen Speicher ohne Ziel
// braucht.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/features/summary/subjective_section.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'support/e2e_plan_form.dart';
import 'support/e2e_support.dart';

/// Stufe sport-plan: nur der Ersatz der lockeren Einheit (frischer Speicher).
const _sportPlan = bool.fromEnvironment('SPORT_PLAN');

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
  if (_sportPlan) {
    testWidgets(
      'Andere Sportart ersetzt die lockere Einheit des Tages',
      reportingFailures(_planUnit),
      timeout: const Timeout(Duration(minutes: 15)),
    );
    return;
  }
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

Future<void> _planUnit(WidgetTester t) async {
  step('SPORT_PLAN start');
  final w = buildWorld();
  await startApp(t, w);
  await setupIfShown(t);
  final s = await session(t, w);
  expect(
    await t.runAsync(() => (s as GoalStorage).goals.goal()),
    isNull,
    reason: 'Test erwartet frischen Speicher ohne Ziel',
  );

  step('SPORT_PLAN profil');
  // HFmax 190, Ruhepuls 60: Grenze "locker" nach PAR-111 bei 151 bpm.
  await enterProfile(t, s);

  step('SPORT_PLAN tageswechsel_abwarten');
  // Die Einheiten duerfen Mitternacht nicht ueberqueren (Einheit von heute).
  await waitPastLateEvening(t);

  step('SPORT_PLAN ziel_anlegen');
  // Ein Lauftag (heute) und hoechstens 3 min je Einheit ergeben heute eine
  // lockere Einheit von 3 min; zwei Drittel davon sind 2 min Bewegungszeit.
  await tapKey(t, 'home_plan');
  await waitFor(t, () => has('plan_empty'), 'Plan leer');
  await tapKey(t, 'plan_create_goal');
  await waitFor(t, () => has('plan_form'), 'Zielformular');
  await setRunDays(t, {weekdayFromToday(0)});
  await enterField(t, 'plan_form_max_session', '3');
  await revealInPlanForm(t, 'plan_form_weekly');
  if (has('plan_form_weekly')) await enterField(t, 'plan_form_weekly', '');
  final l10n = AppLocalizations.of(t.element(find.byType(Scaffold).last));
  await tapUntil(
    t,
    find.descendant(
      of: find.byKey(const Key('plan_form_can30')),
      matching: find.text(l10n.planFormYes),
    ),
    () => can30State() == ContinuousRun30.yes,
    'plan_form_can30 Ja',
    reveal: () => revealInPlanForm(t, 'plan_form_can30'),
  );
  await revealInPlanForm(t, 'plan_form_date_pick');
  await pickTargetDate(t);
  await checkAndSaveGoal(t, 'SPORT_PLAN');
  final plans = (s as PlanStorage).plans;
  expect((await t.runAsync(plans.history))!, hasLength(1), reason: 'Plan');
  await waitFor(t, () => has('plan_goal_card'), 'Zielkarte');
  await tapKey(t, 'home_today');
  final today = DateTime.now();
  final day = DateTime.utc(today.year, today.month, today.day);
  final unit = (await t.runAsync(() => plans.unitOn(day)))!;
  expect(unit.kind, PlanUnitKind.easy, reason: 'heute lockere Einheit');
  log('SPORT_PLAN unit_minutes=${unit.minutes}');

  step('SPORT_PLAN gurt_verbinden');
  await _sensors(t, () async {
    if (has('sensor_connect_$_belt')) {
      await tapKey(t, 'sensor_connect_$_belt');
    }
    await waitFor(t, () => has('sensor_bpm_$_belt'), 'Test-Gurt verbunden');
  });

  step('SPORT_PLAN zu_intensiv');
  // Grundpuls 175 liegt ueber der Grenze aus PAR-111.
  w.sensor.setBase(_belt, 175);
  await _planSport(t, const Duration(seconds: 60));
  await waitFor(
    t,
    () => has('other_sport_not_assigned_tooIntensive'),
    'Grund zu intensiv',
  );
  expect(has('other_sport_replaced'), isFalse, reason: 'nicht abgehakt');
  _expectDialogText(
    t,
    'other_sport_not_assigned_tooIntensive',
    (l) => l.otherSportBlockTooIntensive,
    'Grund zu intensiv sichtbar',
  );
  await tapDialog(t, 'other_sport_dialog_ok');
  await waitFor(t, () => has('home_start_unit'), 'Einheit bleibt offen');
  expect(has('home_today_done'), isFalse, reason: 'Einheit offen');
  expect(
    (await t.runAsync(() => plans.unitOn(day)))!.runId,
    isNull,
    reason: 'keine Zuordnung',
  );

  step('SPORT_PLAN locker');
  // Grundpuls 120 (+-3) liegt unter der Grenze; 150 s Bewegungszeit sind mehr
  // als zwei Drittel der geplanten Dauer.
  w.sensor.setBase(_belt, 120);
  await _planSport(t, const Duration(seconds: 150));
  await waitFor(t, () => has('other_sport_replaced'), 'Hinweis Ersatz');
  // Wortlaut aus den Texten der App (Sprache des Geraets).
  _expectDialogText(
    t,
    'other_sport_replaced',
    (l) => l.otherSportReplacedHint,
    'Hinweis Ausdauerreiz',
  );
  await tapDialog(t, 'other_sport_dialog_ok');

  step('SPORT_PLAN erledigt');
  await waitFor(t, () => has('home_today_done'), 'Einheit als erledigt');
  final runs = [...(await t.runAsync(() => s.runs.list()))!]
    ..sort((a, b) => b.id.compareTo(a.id));
  expect(runs.first.mode, RunMode.sport, reason: 'andere Sportart');
  expect(
    (await t.runAsync(() => plans.unitOn(day)))!.runId,
    runs.first.id,
    reason: 'Sporteinheit der Einheit zugeordnet',
  );
  log('SPORT_PLAN ende');
}

/// Ueber "Einheit starten" Seilspringen fuer [moving] aufzeichnen, beenden,
/// RPE angeben und die Abschlussansicht schliessen.
Future<void> _planSport(WidgetTester t, Duration moving) async {
  await waitFor(t, () => has('home_start_unit'), 'heutige Einheit');
  await tapKey(t, 'home_start_unit');
  await waitFor(t, () => has('treadmill_mode_sport'), 'Start-Seite');
  await tapKey(t, 'treadmill_mode_sport');
  await waitFor(t, () => has('other_sport_card'), 'Sportwahl');
  await tapKey(t, 'other_sport_rope');
  await waitFor(t, () => _goEnabled(t) == true, 'Start frei mit Gurt');
  await tapKey(t, 'run_start_ready');
  await waitFor(t, () => has('run_time'), 'Live-Ansicht');
  await waitFor(t, () => has('run_hr'), 'Puls in der Live-Ansicht');
  await pumpFor(t, moving);
  await finishRun(t);
  await waitFor(t, () => has('subjective_rpe_3'), 'RPE gefragt');
  await tapKey(t, 'subjective_rpe_3');
  await waitFor(t, () => has('sum_other_sport'), 'Zusammenfassung');
  await tapKey(t, 'run_done_close');
}

/// Der Dialog [key] zeigt den Text [text] in der Sprache der App.
void _expectDialogText(
  WidgetTester t,
  String key,
  String Function(AppLocalizations) text,
  String reason,
) {
  final dialog = find.byKey(Key(key));
  final l = AppLocalizations.of(t.element(dialog));
  expect(
    find.descendant(of: dialog, matching: find.text(text(l))),
    findsOneWidget,
    reason: reason,
  );
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
