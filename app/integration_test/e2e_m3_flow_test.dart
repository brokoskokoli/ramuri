// E2E: Abschlussfluss M3 am Stueck in der echten App mit echtem Speicher und
// fester Uhr (07:30 Ortszeit am Tag der ersten harten Einheit des Plans):
//  0 Ziel und Plan (harte Einheit heute) und eine Kamera-Reihe der Vortage
//    (gleiches Geraet wie die Messung: unauffaellige Referenz, die zwei Tage
//    vor heute auffaellig) stehen im Speicher; App beim Schreiben beendet
//  1 Health Connect (Debug-Quelle): Einwilligung fuer HRV, Ruhepuls und Schlaf,
//    "Jetzt abrufen": nur diese Arten gespeichert, Einheit bleibt hart
//  2 Entwicklermodus ueber zehn Tipps auf die Version
//  3 Modus "adaptiv" im Plan: ohne heutige Messung keine Aenderung
//  4 Test-Gurt mit RR verbinden, Morgenmessung mit Fake-Kamera ueber die Karte
//    auf "Heute": Messung und Gurt-Paar gespeichert; HRV und Ruhepuls aus der
//    Kamera, Schlaf aus Health Connect; die harte Einheit wird locker (Fassung
//    feedback, Grund readiness), "Heute" zeigt die Karte "Erholung" und
//    "Plan angepasst" mit dem Grund Erholung (FR-0157, PAR-173, PAR-204)
//  5 Modus "fix": die Einheit kehrt zurueck und bleibt hart, unter der Karte
//    steht die Empfehlung "Locker laufen" (FR-0158, FR-0216)
//  6 Widerruf "Schlaf" mit Loeschfrage, Loeschen: keine Schlafwerte mehr im
//    Speicher und in der Erholung, Schlaf fehlt auf der Detailseite (SEC-0007)
// Nur synthetische Werte. Ausgabe: Zeilen "E2E_<zeit> ..."; oeffentlich nur
// Schrittmarken (step). Marker "SHOT <name>".
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/debug/debug_test_health_connect.dart';
import 'package:running_app/debug/debug_test_ppg_camera.dart';
import 'package:running_app/debug/debug_test_sensor.dart';
import 'package:running_app/features/measure/device_info.dart';
import 'package:running_app/features/readiness/readiness_service.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/system_clock.dart';
import 'package:running_app/ui/ui.dart';

import 'support/e2e_support.dart';

/// Feste Wanduhr (Versatz der Systemzeitzone, Emulator); die monotone Zeit
/// laeuft in Echtzeit und kann vorgestellt werden ([jump]), damit die feste
/// Ruhephase der Morgenmessung gleich endet.
class _FlowClock implements Clock {
  _FlowClock(this.at);
  final DateTime at;
  final _sw = Stopwatch()..start();
  Duration _bonus = Duration.zero;
  void jump(Duration d) => _bonus += d;
  @override
  DateTime now() => at;
  @override
  Duration monotonic() => _sw.elapsed + _bonus;
  @override
  Duration utcOffsetAt(DateTime t) => const SystemClock().utcOffsetAt(t);
}

DateTime _today(Clock c) {
  final n = c.now();
  final l = n.toUtc().add(c.utcOffsetAt(n));
  return DateTime(l.year, l.month, l.day);
}

/// Lokale Zeit am Tag [d] plus [days] Tage, in UTC.
DateTime _at(DateTime d, int days, int h, [int min = 0]) =>
    DateTime(d.year, d.month, d.day + days, h, min).toUtc();

/// Ortstag [d] als Plantag (UTC-Mitternacht).
DateTime _planDay(DateTime d) => DateTime.utc(d.year, d.month, d.day);

TrainingGoal _goal(DateTime created) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(created.year + 1, created.month, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: created,
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

/// Ziel und Plan ab [today] (Ortstag); Ergebnis: Tag der ersten harten
/// Einheit ab heute (Ortstag).
Future<DateTime> _seedPlan(StorageSession s, DateTime today) async {
  final day = _planDay(today);
  final goal = _goal(day);
  await (s as GoalStorage).goals.save(goal, today: day);
  final plans = (s as PlanStorage).plans;
  await recalculatePlan(
    plans: plans,
    settings: s.settings,
    trigger: PlanTrigger.create,
    today: day,
    now: DateTime.now().toUtc(),
    inputs: PlanInputs.forNewGoal(goal, day).copyWith(startWeeklyMinutes: 180),
    warning: (s as WarningStorage).warning,
  );
  for (var n = 0; n < 28; n++) {
    final u = await plans.unitOn(day.add(Duration(days: n)));
    if (u != null && u.isHard && recoveryEasable(u)) {
      return DateTime(today.year, today.month, today.day + n);
    }
  }
  fail('keine harte Einheit in vier Wochen');
}

/// Kamera-Morgenmessung am Tag [day] (< 0) vor dem Messtag [d], Geraet wie
/// die Messung im Test ([dev]). Referenz (Tag -28 bis -3): Ruhepuls um 50,
/// RMSSD um 80; Tag -2 und -1: Ruhepuls 70, RMSSD 30. Mit der heutigen
/// Messung der Fake-Kamera (Puls um 70, RMSSD um 35) liegen HRV und Ruhepuls
/// im Fenster weit von der Referenz, der Wert faellt unter 50.
MorningMeasurement _morning(DateTime d, int day, DeviceInfo dev) {
  final recent = day >= -2;
  return MorningMeasurement(
    measuredAt: _at(d, day, 7),
    utcOffset: DateTime(d.year, d.month, d.day + day, 7).timeZoneOffset,
    posture: RestingPosture.lying,
    deviceManufacturer: dev.manufacturer,
    deviceModel: dev.model,
    method: ppgMethod,
    methodVersion: ppgMethodVersion,
    quality: PpgQuality.good,
    restingHrBpm: recent ? 70.0 : 49.0 + (day.abs() % 4),
    rmssdMs: recent ? 30.0 : 76.0 + (day.abs() % 5) * 2,
    timingNoiseMs: 10,
    cameraIntervalsMs: const [],
    beforeValidation: false,
    outsideWindow: false,
  );
}

Future<PlanUnit?> _unit(WidgetTester t, StorageSession s, DateTime d) =>
    t.runAsync<PlanUnit?>(() => (s as PlanStorage).plans.unitOn(_planDay(d)));

Future<List<PlanVersionRecord>> _history(WidgetTester t, StorageSession s) =>
    t.runAsync(() => (s as PlanStorage).plans.history()).then((h) => h!);

Future<PlanAdaptationMode?> _mode(WidgetTester t, StorageSession s) =>
    t.runAsync(() => SettingsPlanAdaptationStore(s.settings).read());

Future<Map<HealthDataKind, int>> _counts(
  WidgetTester t,
  StorageSession s,
) async => (await t.runAsync(() async {
  final h = (s as HealthStorage).health;
  return {for (final k in HealthDataKind.values) k: await h.count(k)};
}))!;

String _fmt(Map<HealthDataKind, int> c) =>
    c.entries.map((e) => '${e.key.key}=${e.value}').join(' ');

/// Erholung so, wie die App sie rechnet (ohne Belastung; fuer die Quellen der
/// Faktoren und die Tatsachen genuegt das).
Future<ReadinessResult> _readiness(
  WidgetTester t,
  StorageSession s,
  Clock clock,
) async =>
    (await t.runAsync(() => ReadinessService(session: s, clock: clock).load()))!
        .result;

ReadinessFactorSource? _sourceOf(ReadinessResult r, ReadinessFactorId id) {
  for (final f in r.factors) {
    if (f.id == id) return f.source;
  }
  return null;
}

/// Wartet (echte Zeit) auf [cond] ueber die Einheit von [d] im Speicher.
Future<PlanUnit> _waitUnit(
  WidgetTester t,
  StorageSession s,
  DateTime d,
  bool Function(PlanUnit u) cond,
  String what,
) async {
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (true) {
    final u = await _unit(t, s, d);
    if (u != null && cond(u)) return u;
    if (DateTime.now().isAfter(end)) fail('nach 40 s nicht erreicht: $what');
    await pumpFor(t, const Duration(milliseconds: 200));
  }
}

/// "Heute"; mit [card] (erweiterte Stufe, Entwicklermodus an) auch die Karte
/// "Erholung". Ohne Entwicklermodus gilt die Basisstufe: keine Karte.
Future<void> _onHome(WidgetTester t, {bool card = true}) async {
  await waitFor(t, () => has('home_overview'), 'Heute');
  if (card) {
    await waitFor(t, () => has('readiness_card'), 'Karte Erholung');
  } else {
    expect(has('readiness_card'), isFalse, reason: 'Basisstufe ohne Karte');
  }
}

/// Heute -> Uebersicht -> Einstellungen -> Health Connect.
Future<void> _openHealth(WidgetTester t) async {
  await tapKey(t, 'home_overview');
  await tapKey(t, 'home_settings');
  await waitFor(
    t,
    () => !has('home_settings'),
    'Einstellungen offen (home_settings verdeckt)',
  );
  await t.scrollUntilVisible(
    find.byKey(const Key('settings_health')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tapKey(t, 'settings_health');
  await waitFor(t, () => has('health_main'), 'Health-Connect-Seite');
}

/// Von der Health-Connect-Seite zurueck auf "Heute".
Future<void> _healthToHome(WidgetTester t, {bool card = true}) async {
  for (var i = 0; i < 3 && !has('home_today'); i++) {
    await back(t);
  }
  await tapKey(t, 'home_today');
  await _onHome(t, card: card);
}

bool _on(String kind) {
  final f = find.byKey(Key('health_switch_$kind'));
  return (f.evaluate().first.widget as SwitchListTile).value;
}

/// Plan-Tab, Schalter in den gebauten Bereich holen und [key] tippen.
Future<void> _switchTo(WidgetTester t, String key) async {
  await tapKey(t, 'home_plan');
  await waitFor(t, () => has('plan_list'), 'Plan offen');
  await t.scrollUntilVisible(
    find.byKey(Key(key)),
    300,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('plan_list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tapKey(t, key);
}

/// Ergebnis der Morgenmessung steht fest (Fertig bedienbar).
bool _resultSettled() {
  if (has('morning_again') || has('morning_save_retry')) return true;
  final f = find.byKey(const Key('morning_done'));
  if (f.evaluate().isEmpty) return false;
  final w = f.evaluate().first.widget;
  return w is RamuriPrimaryButton && w.onPressed != null;
}

/// Wartet (echte Zeit) bis [cond] (Speicher, Fake) gilt, sonst Fehler [what].
Future<void> _waitAsync(
  WidgetTester t,
  Future<bool> Function() cond,
  String what,
) async {
  final end = DateTime.now().add(const Duration(seconds: 40));
  while (!(await t.runAsync(cond) ?? false)) {
    if (DateTime.now().isAfter(end)) fail('nach 40 s nicht erreicht: $what');
    await pumpFor(t, const Duration(milliseconds: 200));
  }
}

const _kinds = {
  HealthDataKind.hrvRmssd,
  HealthDataKind.restingHeartRate,
  HealthDataKind.sleep,
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'M3: Health Connect, Morgenmessung, Erholung, adaptiv/fix, Widerruf',
    reportingFailures((t) async {
      step('M3 S0 start');
      final w0 = buildWorld();
      await startApp(t, w0);
      await setupIfShown(t);
      final s = await session(t, w0);
      // App vor dem Schreiben beenden: sonst rechnet die laufende App (echte
      // Uhr) den Plan neu, waehrend geseedet wird.
      await t.pumpWidget(const SizedBox());
      await pumpFor(t, const Duration(seconds: 1));
      final today = _today(w0.deps.clock);
      final d = (await t.runAsync(() => _seedPlan(s, today)))!;
      final clock = _FlowClock(_at(d, 0, 7, 30));
      final dev = (await t.runAsync(readDeviceInfo))!;
      await t.runAsync(() async {
        // Wochenpruefung gilt als erledigt: sonst rechnet das Oeffnen des
        // Plans die Woche neu, bevor die Erholung wirkt.
        await s.settings.set(
          planLastCheckDayKey,
          isoDay(_planDay(d)),
          at: clock.now(),
        );
        for (var day = -28; day <= -1; day++) {
          await (s as MorningStorage).morning.add(_morning(d, day, dev));
        }
      });
      final hard = (await _unit(t, s, d))!;
      expect(hard.isHard, isTrue, reason: 'S0 harte Einheit heute');
      expect(
        await _mode(t, s),
        PlanAdaptationMode.fixed,
        reason: 'S0 Vorgabe fix',
      );
      final versions0 = (await _history(t, s)).length;
      log('S0 harter_tag=${isoDay(_planDay(d))} fassungen=$versions0');

      final hc = DebugTestHealthConnect(now: clock.now);
      final cam = DebugTestPpgCamera(speed: 30);
      final sensor = DebugTestSensor(const SystemClock());
      final w = World(
        AppDependencies.create(
          heartRateSensor: sensor,
          ppgCamera: cam,
          healthConnect: hc,
          clock: clock,
        ),
        sensor,
      );
      await startApp(t, w);
      await _onHome(t, card: false);

      step('M3 S1 health_connect');
      final before = await _counts(t, s);
      expect(
        before.values.every((v) => v == 0),
        isTrue,
        reason: 'S1 vorher keine Gesundheitsdaten',
      );
      await _openHealth(t);
      await tapKey(t, 'health_switch_hrv_rmssd');
      await tapKey(t, 'health_switch_resting_heart_rate');
      await tapKey(t, 'health_switch_sleep');
      await waitFor(
        t,
        () => _on('hrv_rmssd') && _on('resting_heart_rate') && _on('sleep'),
        'Schalter HRV, Ruhepuls und Schlaf an',
      );
      await tapKey(t, 'health_continue');
      await _waitAsync(
        t,
        () async => (await hc.grantedKinds()).isNotEmpty,
        'Rechte angefragt',
      );
      final granted = (await t.runAsync(hc.grantedKinds))!;
      expect(granted, _kinds, reason: 'S1 Rechte genau HRV, Ruhepuls, Schlaf');
      await tapKey(t, 'health_fetch');
      await waitFor(
        t,
        () => find.byType(SnackBar).evaluate().isNotEmpty,
        'Rueckmeldung nach Abruf',
      );
      final imported = await _counts(t, s);
      log('S1 nachher ${_fmt(imported)}');
      for (final k in HealthDataKind.values) {
        if (_kinds.contains(k)) {
          expect(imported[k], greaterThan(0), reason: 'S1 ${k.key} importiert');
        } else {
          expect(imported[k], 0, reason: 'S1 ${k.key} nicht eingewilligt');
        }
      }
      await shot(t, 's1_health');
      await _healthToHome(t, card: false);
      expect(
        (await _unit(t, s, d))!.isHard,
        isTrue,
        reason: 'S1 Import allein aendert den Plan nicht (fix)',
      );

      step('M3 S2 entwicklermodus');
      await tapKey(t, 'home_overview');
      await tapKey(t, 'overview_about');
      await waitFor(t, () => has('about_version'), 'Ueber');
      for (var i = 0; i < 10; i++) {
        await t.tap(find.byKey(const Key('about_version')));
        await pumpFor(t, const Duration(milliseconds: 120));
      }
      await waitFor(t, () => has('about_dev_badge'), 'Entwicklermodus an');
      expect(
        await t.runAsync(
          () => SettingsDeveloperModeStore(s.settings, clock).read(),
        ),
        isTrue,
        reason: 'S2 Entwicklermodus gespeichert',
      );
      await back(t);
      await back(t);
      await _onHome(t);
      await waitFor(t, () => has('morning_card'), 'Karte Morgenmessung');

      step('M3 S3 adaptiv');
      await _switchTo(t, 'plan_adapt_adaptive');
      await _waitAsync(
        t,
        () async =>
            await SettingsPlanAdaptationStore(s.settings).read() ==
            PlanAdaptationMode.adaptive,
        'Modus adaptiv gespeichert',
      );
      expect(
        (await _unit(t, s, d))!.isHard,
        isTrue,
        reason: 'S3 ohne heutige Messung bleibt die Einheit hart',
      );
      final versions3 = (await _history(t, s)).length;
      await tapKey(t, 'home_today');
      await _onHome(t);

      step('M3 S4 morgenmessung');
      await connect(t, ['fake-gurt-1'], 'fake-gurt-1');
      sensor.sendRr = true;
      await _onHome(t);
      final pairs0 = (await t.runAsync(
        () => countMorningPairs((s as MorningStorage).morning),
      ))!;
      await tapKey(t, 'morning_card_start');
      await waitFor(t, () => has('morning_start'), 'Einstieg Morgenmessung');
      await tapKey(t, 'morning_start');
      await waitFor(t, () => has('measure_rest_clock'), 'Ruhephase');
      clock.jump(const Duration(minutes: 30));
      await waitFor(
        t,
        _resultSettled,
        'Ergebnis der Morgenmessung',
        timeout: const Duration(seconds: 60),
      );
      expect(has('morning_again'), isFalse, reason: 'S4 Messung gueltig');
      expect(
        has('morning_note_not_counted'),
        isFalse,
        reason: 'S4 erste Messung des Tages zaehlt',
      );
      await shot(t, 's4_ergebnis');
      final pairs = (await t.runAsync(
        () => countMorningPairs((s as MorningStorage).morning),
      ))!;
      log('S4 paare mit=${pairs.withBelt} ohne=${pairs.without}');
      expect(
        pairs.withBelt,
        pairs0.withBelt + 1,
        reason: 'S4 Gurt-RR zur Messung gespeichert',
      );
      await tapKey(t, 'morning_done');
      await _onHome(t);

      step('M3 S4 locker');
      final eased = await _waitUnit(
        t,
        s,
        d,
        (u) => !u.isHard,
        'Einheit locker nach der Morgenmessung (adaptiv)',
      );
      final h4 = await _history(t, s);
      log('S4 art=${eased.kind.name} fassungen=${h4.length}');
      expect(h4.length, versions3 + 1, reason: 'S4 genau eine Fassung');
      expect(
        h4.last.trigger,
        PlanTrigger.feedback,
        reason: 'S4 Ausloeser feedback',
      );
      expect(h4.last.reason, planReasonReadiness, reason: 'S4 Grund readiness');
      final r4 = await _readiness(t, s, clock);
      log(
        'S4 zustand=${r4.state.name} band=${r4.band?.name} '
        'quellen=${r4.factors.map((f) => '${f.id.name}:${f.source.name}').join(',')}',
      );
      expect(r4.state, ReadinessState.number, reason: 'S4 Erholung als Zahl');
      expect(
        _sourceOf(r4, ReadinessFactorId.hrv),
        ReadinessFactorSource.camera,
        reason: 'S4 HRV aus der Kamera',
      );
      expect(
        _sourceOf(r4, ReadinessFactorId.restingHeartRate),
        ReadinessFactorSource.camera,
        reason: 'S4 Ruhepuls aus der Kamera',
      );
      expect(
        _sourceOf(r4, ReadinessFactorId.sleep),
        ReadinessFactorSource.healthConnect,
        reason: 'S4 Schlaf aus Health Connect',
      );
      await waitFor(t, () => has('plan_change_card'), 'Karte Plan angepasst');
      final l = AppLocalizations.of(
        t.element(find.byKey(const Key('plan_change_card'))),
      );
      expect(
        txt('plan_change_reason'),
        l.planAdaptReasonReadiness,
        reason: 'S4 Grund Erholung auf der Karte',
      );
      expect(
        has('readiness_value'),
        isTrue,
        reason: 'S4 Karte Erholung mit Wert',
      );
      expect(
        has('plan_adapt_recommendation'),
        isFalse,
        reason: 'S4 keine Empfehlung bei adaptiv',
      );
      await shot(t, 's4_heute');

      step('M3 S5 fix');
      await _switchTo(t, 'plan_adapt_fixed');
      final back5 = await _waitUnit(
        t,
        s,
        d,
        (u) => u.isHard,
        'Einheit zurueck nach fix',
      );
      expect(back5.kind, hard.kind, reason: 'S5 urspruengliche Art');
      expect(back5.minutes, hard.minutes, reason: 'S5 urspruengliche Dauer');
      final h5 = await _history(t, s);
      expect(
        h5.last.reason,
        planReasonAdaptationFixed,
        reason: 'S5 Grund adaptationFixed',
      );
      expect(
        await _mode(t, s),
        PlanAdaptationMode.fixed,
        reason: 'S5 Modus fix',
      );
      await tapKey(t, 'home_today');
      await _onHome(t);
      await waitFor(
        t,
        () => has('plan_adapt_recommendation'),
        'Empfehlung bei fix',
      );
      expect(
        txt('plan_adapt_recommendation_text'),
        l.planAdaptRecommendEasy,
        reason: 'S5 Empfehlung locker laufen',
      );
      expect(
        has('plan_adapt_easy_run'),
        isTrue,
        reason: 'S5 Knopf locker laufen',
      );
      expect(
        (await _unit(t, s, d))!.isHard,
        isTrue,
        reason: 'S5 Plan bleibt bei fix unveraendert',
      );
      expect(
        (await _history(t, s)).length,
        h5.length,
        reason: 'S5 keine weitere Fassung bei fix',
      );
      await shot(t, 's5_heute');

      step('M3 S6 widerruf');
      await _openHealth(t);
      await tapKey(t, 'health_switch_sleep');
      await waitFor(t, () => has('health_delete_dialog'), 'Loeschfrage');
      await shot(t, 's6_loeschfrage');
      await tapDialog(t, 'health_delete_confirm');
      await waitFor(t, () => !has('health_delete_dialog'), 'Dialog zu');
      await waitFor(t, () => !_on('sleep'), 'Schalter Schlaf aus');
      await _waitAsync(
        t,
        () async =>
            await (s as HealthStorage).health.count(HealthDataKind.sleep) == 0,
        'Schlaf geloescht',
      );
      final after = await _counts(t, s);
      log('S6 nachher ${_fmt(after)}');
      expect(after[HealthDataKind.sleep], 0, reason: 'S6 Schlaf geloescht');
      expect(
        after[HealthDataKind.hrvRmssd],
        imported[HealthDataKind.hrvRmssd],
        reason: 'S6 HRV bleibt',
      );
      expect(
        after[HealthDataKind.restingHeartRate],
        imported[HealthDataKind.restingHeartRate],
        reason: 'S6 Ruhepuls bleibt',
      );
      expect(_on('hrv_rmssd'), isTrue, reason: 'S6 HRV weiter eingewilligt');
      final r6 = await _readiness(t, s, clock);
      expect(
        _sourceOf(r6, ReadinessFactorId.sleep),
        isNull,
        reason: 'S6 kein Schlaf als Faktor',
      );
      expect(
        r6.facts.where((f) => f.kind == ReadinessFactKind.sleepDuration),
        isEmpty,
        reason: 'S6 kein Schlaf als Tatsache',
      );
      expect(
        r6.missing,
        contains(ReadinessFactorId.sleep),
        reason: 'S6 Schlaf fehlt in der Erholung',
      );
      await _healthToHome(t);
      await tapKey(t, 'readiness_where_from');
      await waitFor(t, () => has('readiness_detail'), 'Detailseite Erholung');
      await waitFor(
        t,
        () => has('readiness_detail_missing'),
        'Abschnitt fehlende Faktoren',
      );
      expect(
        has('readiness_detail_factor_sleep'),
        isFalse,
        reason: 'S6 Detail ohne Schlaf als Faktor',
      );
      expect(
        has('readiness_detail_missing_sleep'),
        isTrue,
        reason: 'S6 Detail nennt Schlaf als fehlend',
      );
      await shot(t, 's6_detail');
      log('S6 ok');
    }),
  );
}
