// E2E: Laufband-Lauf (FR-0196): Bandmodus waehlen, Start-Werte eingeben,
// laufen, Geschwindigkeit ueber den Knopf aendern, pausieren, beenden. Geprueft
// wird der gespeicherte Zustand: ein neuer, beendeter Lauf im Bandmodus mit den
// eingegebenen Bandwerten und ohne GPS-Positionen. Kein GPS noetig. Synthetische
// Werte, Ausgabe nur Zaehler. Laeuft in der Sammlung (all_test.dart).
//
// Mit --dart-define=TREADMILL_PLAN=true laeuft statt dessen die gefuehrte
// Einheit aus dem Plan auf dem Laufband (FR-0033, FR-0196): Profil und Ziel
// ueber die Oberflaeche (Geh-Lauf-Plan mit Einheit heute, wie
// e2e_m2_flow_test.dart), "Einheit starten", Bandmodus, Bandwerte, Wechsel des
// Abschnitts in Echtzeit (ca. 5 min), Beenden, Zusammenfassung "Aus dem Plan",
// Einheit im Plan erledigt. Eigene Stufe treadmill-plan (tool/ci_e2e.sh), weil
// sie einen frischen Speicher ohne Ziel braucht und wegen der Dauer.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'support/e2e_plan_form.dart';
import 'support/e2e_support.dart';

/// Stufe treadmill-plan: nur die gefuehrte Einheit (frischer Speicher).
const _guided = bool.fromEnvironment('TREADMILL_PLAN');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (_guided) {
    testWidgets(
      'Laufband: gefuehrte Einheit aus dem Plan',
      reportingFailures(_guidedUnit),
      timeout: const Timeout(Duration(minutes: 15)),
    );
    return;
  }
  testWidgets('Laufband-Lauf starten, Werte eingeben, speichern', (t) async {
    step('TREADMILL start');
    final w = buildWorld();
    await startApp(t, w);
    await setupIfShown(t);
    final s = await session(t, w);
    final before = (await t.runAsync(() => s.runs.list()))!.length;

    step('TREADMILL bandwahl');
    await tapKey(t, 'home_start_run');
    await waitFor(t, () => has('treadmill_mode_belt'), 'Bandwahl');
    await tapKey(t, 'treadmill_mode_belt');
    await waitFor(t, () => has('treadmill_start_speed'), 'Geschwindigkeit');
    // Ohne Geschwindigkeit ist Los gesperrt.
    expect(t.widget<RamuriStartButton>(_goFinder).onPressed, isNull);
    await t.enterText(find.byKey(const Key('treadmill_start_speed')), '10.5');
    await t.enterText(find.byKey(const Key('treadmill_start_incline')), '1.5');
    FocusManager.instance.primaryFocus?.unfocus();
    await pumpFor(t, const Duration(milliseconds: 300));
    step('TREADMILL lauf_start');
    await tapKey(t, 'run_start_ready');
    await waitFor(
      t,
      () => has('run_time') || has('treadmill_denied'),
      'Laufseite oder Rechtehinweis',
    );
    expect(has('treadmill_denied'), isFalse, reason: 'Bewegungsrecht fehlt');
    expect(has('treadmill_speed'), isTrue);
    // Anzeige je nach Sprache mit Komma oder Punkt; der Wert gilt im Speicher.
    await waitFor(t, () => _shows('10', '5'), 'Startgeschwindigkeit angezeigt');

    await pumpFor(t, const Duration(seconds: 3));
    step('TREADMILL geschwindigkeit_aendern');
    await tapKey(t, 'treadmill_speed_up');
    await waitFor(t, () => _shows('10', '6'), 'Geschwindigkeit nach Knopf');
    await pumpFor(t, const Duration(seconds: 3));
    step('TREADMILL lauf_beenden');
    await tapKey(t, 'run_pause');
    await waitFor(t, () => has('run_finish'), 'Pause (Beenden sichtbar)');
    await tapKey(t, 'run_finish');
    await tapDialog(t, 'run_finish_confirm');
    await waitFor(t, () => has('run_done_status'), 'Laufende angezeigt');

    step('TREADMILL gespeichert_pruefen');
    final runs = (await t.runAsync(() => s.runs.list()))!;
    final done = await _newestFinished(t, s);
    expect(runs.length, before + 1, reason: 'genau ein neuer Lauf');
    expect(done.mode, RunMode.treadmill);
    final raw = (await t.runAsync(() => s.rawData.read(done.id)))!;
    log(
      'TREADMILL belt=${raw.beltSettings.length} pos=${raw.positions.length}',
    );
    expect(raw.positions, isEmpty, reason: 'Bandlauf ohne GPS-Positionen');
    final speeds = [
      for (final b in raw.beltSettings) b.value.speedMetersPerSecond,
    ];
    expect(
      speeds.length,
      greaterThanOrEqualTo(2),
      reason: 'Start und Aenderung',
    );
    expect(speeds.first, closeTo(10.5 / 3.6, 1e-6), reason: 'Startwert');
    expect(speeds.last, closeTo(10.6 / 3.6, 1e-6), reason: 'nach Knopf');
    expect(raw.beltSettings.first.value.inclinePercent, 1.5);
  }, timeout: const Timeout(Duration(minutes: 5)));
}

Future<void> _guidedUnit(WidgetTester t) async {
  step('TREADMILL_PLAN start');
  final w = buildWorld();
  await startApp(t, w);
  await setupIfShown(t);
  final s = await session(t, w);
  expect(
    await t.runAsync(() => (s as GoalStorage).goals.goal()),
    isNull,
    reason: 'Test erwartet frischen Speicher ohne Ziel',
  );
  final runsBefore = (await t.runAsync(() => s.runs.list()))!.length;

  step('TREADMILL_PLAN profil');
  await enterProfile(t, s);

  step('TREADMILL_PLAN tageswechsel_abwarten');
  // Der Lauftag wird gleich festgelegt; der Lauf darf Mitternacht nicht
  // ueberqueren (home_today_done prueft gegen "heute").
  await waitPastLateEvening(t);

  step('TREADMILL_PLAN ziel_anlegen');
  // Heute ist Lauftag; kein Wochenstand und "keine 30 min am Stueck" ergeben
  // einen Geh-Lauf-Plan mit kurzen Abschnitten.
  await tapKey(t, 'home_plan');
  await waitFor(t, () => has('plan_empty'), 'Plan leer');
  await tapKey(t, 'plan_create_goal');
  await waitFor(t, () => has('plan_form'), 'Zielformular');
  await setRunDays(t, {
    weekdayFromToday(0),
    weekdayFromToday(2),
    weekdayFromToday(4),
  });
  await enterField(t, 'plan_form_max_session', '45');
  await revealInPlanForm(t, 'plan_form_weekly');
  if (has('plan_form_weekly')) await enterField(t, 'plan_form_weekly', '');
  final l10n = AppLocalizations.of(t.element(find.byType(Scaffold).last));
  await tapUntil(
    t,
    find.descendant(
      of: find.byKey(const Key('plan_form_can30')),
      matching: find.text(l10n.planFormNo),
    ),
    () => can30State() == ContinuousRun30.no,
    'plan_form_can30 Nein',
    reveal: () => revealInPlanForm(t, 'plan_form_can30'),
  );
  await revealInPlanForm(t, 'plan_form_can30');
  expect(can30State(), ContinuousRun30.no, reason: 'plan_form_can30 Nein');
  await revealInPlanForm(t, 'plan_form_date_pick');
  await pickTargetDate(t);
  await checkAndSaveGoal(t, 'TREADMILL_PLAN');
  final plans = (s as PlanStorage).plans;
  expect((await t.runAsync(plans.history))!, hasLength(1), reason: 'Plan');
  await waitFor(t, () => has('plan_goal_card'), 'Zielkarte');
  await tapKey(t, 'home_today');

  step('TREADMILL_PLAN einheit_starten');
  final firstSegmentSeconds = await firstSegmentSecondsToday(
    t,
    plans,
    'TREADMILL_PLAN',
  );
  await waitFor(t, () => has('home_start_unit'), 'heutige Einheit');
  await tapKey(t, 'home_start_unit');
  await waitFor(t, () => has('run_start_ready'), 'Start-Seite bereit');
  expect(has('guided_card'), isTrue, reason: 'gefuehrte Einheit angeboten');

  step('TREADMILL_PLAN bandwahl');
  await tapKey(t, 'treadmill_mode_belt');
  await waitFor(t, () => has('treadmill_start_speed'), 'Geschwindigkeit');
  expect(
    has('guided_card'),
    isTrue,
    reason: 'Einheit bleibt nach der Bandwahl gewaehlt',
  );
  // Ohne Geschwindigkeit ist Los gesperrt.
  expect(t.widget<RamuriStartButton>(_goFinder).onPressed, isNull);
  await enterField(t, 'treadmill_start_speed', '7.5');
  await enterField(t, 'treadmill_start_incline', '1');
  expect(
    t.widget<RamuriStartButton>(_goFinder).onPressed,
    isNotNull,
    reason: 'Los mit Bandwerten frei',
  );

  step('TREADMILL_PLAN lauf_start');
  await tapKey(t, 'run_start_ready');
  await waitFor(
    t,
    () => has('guided_section') || has('treadmill_denied'),
    'Fuehrungsseite oder Rechtehinweis',
  );
  expect(has('treadmill_denied'), isFalse, reason: 'Bewegungsrecht fehlt');
  expect(has('guided_section'), isTrue, reason: 'Fuehrungsseite');

  step('TREADMILL_PLAN abschnittswechsel');
  // Wechsel in Echtzeit, erkannt am Text unter dem Schluessel des Abschnitts.
  final first = txt('guided_section');
  expect(first, isNot('<fehlt>'), reason: 'Abschnitt angezeigt');
  final dl = DateTime.now().add(Duration(seconds: firstSegmentSeconds + 120));
  while (txt('guided_section') == first) {
    if (DateTime.now().isAfter(dl)) {
      fail('kein Abschnittswechsel in ${firstSegmentSeconds + 120} s');
    }
    await pumpFor(t, const Duration(seconds: 1));
  }
  expect(has('guided_section'), isTrue, reason: 'naechster Abschnitt');
  expect(txt('guided_section'), isNot(first), reason: 'Abschnitt gewechselt');
  log('TREADMILL_PLAN section_changed');

  step('TREADMILL_PLAN beenden');
  await tapVisible(t, 'run_pause');
  await tapVisible(t, 'run_finish');
  await waitFor(t, () => has('run_finish_confirm'), 'Beenden-Dialog');
  await tapDialog(t, 'run_finish_confirm');
  await waitFor(t, () => has('run_done_status'), 'Laufende angezeigt');

  step('TREADMILL_PLAN zusammenfassung');
  await waitFor(
    t,
    () => has('sum_from_plan') || has('map_consent_dialog'),
    'Aus dem Plan oder Karten-Frage',
  );
  // Fragt die Zusammenfassung nach der Karte, nur wegklicken.
  if (has('map_consent_dialog')) {
    await tapDialog(t, 'map_consent_not_now');
    await waitFor(t, () => !has('map_consent_dialog'), 'Karten-Frage zu');
  }
  await waitFor(t, () => has('sum_from_plan'), 'Aus dem Plan');
  expect(has('sum_from_plan_unit'), isTrue, reason: 'Einheit genannt');

  step('TREADMILL_PLAN gespeichert_pruefen');
  final done = await _newestFinished(t, s);
  final runs = (await t.runAsync(() => s.runs.list()))!;
  expect(runs.length, runsBefore + 1, reason: 'genau ein neuer Lauf');
  expect(done.mode, RunMode.treadmill, reason: 'Bandlauf');
  final raw = (await t.runAsync(() => s.rawData.read(done.id)))!;
  log(
    'TREADMILL_PLAN belt=${raw.beltSettings.length} pos=${raw.positions.length}',
  );
  expect(raw.positions, isEmpty, reason: 'Bandlauf ohne GPS-Positionen');
  expect(raw.beltSettings, isNotEmpty, reason: 'Bandwerte gespeichert');
  expect(
    raw.beltSettings.first.value.speedMetersPerSecond,
    closeTo(7.5 / 3.6, 1e-6),
    reason: 'Startgeschwindigkeit',
  );
  expect(raw.beltSettings.first.value.inclinePercent, 1, reason: 'Steigung');

  step('TREADMILL_PLAN erledigt');
  await tapKey(t, 'run_done_close');
  await waitFor(t, () => has('home_plan'), 'Heute');
  await waitFor(t, () => has('home_today_done'), 'Einheit als erledigt');
  // Einheit im Plan erledigt: zurueck auf "Heute" ordnet die App den Lauf der
  // gestarteten Einheit zu (plan_started_unit.dart), danach traegt sie ihn.
  final d0 = DateTime.now();
  final today = DateTime.utc(d0.year, d0.month, d0.day);
  PlanUnit? unit = await t.runAsync<PlanUnit?>(() => plans.unitOn(today));
  final uend = DateTime.now().add(const Duration(seconds: 20));
  while (unit?.runId != done.id && DateTime.now().isBefore(uend)) {
    await pumpFor(t, const Duration(milliseconds: 500));
    unit = await t.runAsync<PlanUnit?>(() => plans.unitOn(today));
  }
  expect(unit, isNotNull, reason: 'Einheit heute');
  expect(unit!.runId, done.id, reason: 'Lauf der Einheit zugeordnet');
}

bool _shows(String whole, String tenth) =>
    RegExp('^$whole[.,]$tenth').hasMatch(txt('treadmill_speed'));

final _goFinder = find.byKey(const Key('run_start_ready'));

/// Neuester Lauf, wartet (echte Zeit), bis er als beendet gespeichert ist.
Future<StoredRun> _newestFinished(WidgetTester t, StorageSession s) async {
  final end = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    final runs = [...(await t.runAsync(() => s.runs.list()))!]
      ..sort((a, b) => b.id.compareTo(a.id));
    if (runs.isNotEmpty && runs.first.state == RunState.finished) {
      return runs.first;
    }
    if (DateTime.now().isAfter(end)) fail('Lauf nicht als beendet gespeichert');
    await pumpFor(t, const Duration(milliseconds: 500));
  }
}
