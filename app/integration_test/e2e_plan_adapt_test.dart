// E2E: Plananpassung an Erholung (FR-0157, FR-0158, FR-0216, PAR-173) in der
// echten App mit echtem Speicher. Ziel und Plan, Morgenmessungen (Kamera, mit
// Schlafangabe am Messtag) und Entwicklermodus werden direkt in den Speicher
// geschrieben; die feste Uhr steht um 09:00 Ortszeit am Tag der ersten harten
// Einheit des Plans, der Wert dieses Tages liegt im Band "Erholung empfohlen".
// Szenarien in Reihenfolge, jedes baut auf dem Stand des vorigen auf:
//  1 "fix" (Vorgabe): Plan bleibt, unter der Karte "Erholung" steht die
//    Empfehlung mit "Locker laufen"; Abbrechen im Dialog laesst den Plan
//  2 Wechsel auf "adaptiv" im Plan: die harte Einheit von heute wird locker
//    (Fassung feedback, Grund readiness), "Heute" zeigt "Plan angepasst" statt
//    der Empfehlung
//  3 zurueck auf "fix": die Einheit kehrt zurueck (Grund adaptationFixed),
//    die Empfehlung steht wieder da
// Ausgabe: Zeilen "E2E_<zeit> ...", synthetische Werte. Marker "SHOT <name>".
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:running_app/system_clock.dart';

import 'support/e2e_support.dart';

/// Uhr mit festem "jetzt", Versatz der Systemzeitzone (Emulator).
class _FixedClock implements Clock {
  _FixedClock(this.at);
  final DateTime at;
  final _sw = Stopwatch()..start();
  @override
  DateTime now() => at;
  @override
  Duration monotonic() => _sw.elapsed;
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

/// Kamera-Morgenmessung am Tag [day] relativ zu [d] (0 = Messtag): Ruhepuls
/// und RMSSD im Normalbereich, am Messtag auffaellig und mit kurzer Nacht.
MorningMeasurement _morning(DateTime d, int day) => MorningMeasurement(
  measuredAt: _at(d, day, 7),
  utcOffset: DateTime(d.year, d.month, d.day + day, 7).timeZoneOffset,
  posture: RestingPosture.lying,
  deviceManufacturer: 'E2E',
  deviceModel: 'AVD',
  method: 'ppg',
  methodVersion: 1,
  quality: PpgQuality.good,
  restingHrBpm: day == 0 ? 66.0 : 56.0 + (day.abs() % 4),
  rmssdMs: day == 0 ? 30.0 : 44.0 + (day.abs() % 5) * 2,
  timingNoiseMs: 10,
  cameraIntervalsMs: const [],
  beforeValidation: false,
  outsideWindow: false,
  sleepBand: day == 0 ? SleepBand.under5 : null,
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

Future<PlanUnit?> _unit(WidgetTester t, StorageSession s, DateTime d) =>
    t.runAsync<PlanUnit?>(() => (s as PlanStorage).plans.unitOn(_planDay(d)));

Future<List<PlanVersionRecord>> _history(WidgetTester t, StorageSession s) =>
    t.runAsync(() => (s as PlanStorage).plans.history()).then((h) => h!);

Future<PlanAdaptationMode?> _mode(WidgetTester t, StorageSession s) =>
    t.runAsync(() => SettingsPlanAdaptationStore(s.settings).read());

/// "Heute" mit Karte "Erholung" (Import und Erholung geladen).
Future<void> _onHome(WidgetTester t) async {
  await waitFor(t, () => has('home_overview'), 'Heute');
  await waitFor(t, () => has('readiness_card'), 'Karte Erholung');
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Plananpassung an Erholung: fix mit Empfehlung, adaptiv lockert, zurueck',
    reportingFailures((t) async {
      step('PLANADAPT S0 start');
      final w = buildWorld();
      await startApp(t, w);
      await setupIfShown(t);
      final s = await session(t, w);
      // App vor dem Schreiben beenden: sonst reagiert die laufende App (echte
      // Uhr) auf das neue Ziel und rechnet den Plan neu, waehrend geseedet
      // wird, und die harte Einheit am Messtag kann wegfallen.
      await t.pumpWidget(const SizedBox());
      await pumpFor(t, const Duration(seconds: 1));
      final today = _today(w.deps.clock);
      final d = (await t.runAsync(() => _seedPlan(s, today)))!;
      final clock = _FixedClock(_at(d, 0, 9));
      log(
        'S0 heute=${_planDay(today).toIso8601String().substring(0, 10)} '
        'harter_tag=${_planDay(d).toIso8601String().substring(0, 10)}',
      );
      await t.runAsync(() async {
        // Pruefung der Woche gilt als erledigt: sonst rechnet das Oeffnen des
        // Plans die Woche neu, bevor der Schalter getestet ist.
        await s.settings.set(
          planLastCheckDayKey,
          isoDay(_planDay(d)),
          at: clock.now(),
        );
        for (var day = -27; day <= 0; day++) {
          await (s as MorningStorage).morning.add(_morning(d, day));
        }
        await SettingsDeveloperModeStore(s.settings, clock).set(true);
      });
      expect(
        await _mode(t, s),
        PlanAdaptationMode.fixed,
        reason: 'S0 Vorgabe fix',
      );
      final hard = (await _unit(t, s, d))!;
      expect(hard.isHard, isTrue, reason: 'S0 harte Einheit am Messtag');
      final versions0 = (await _history(t, s)).length;

      step('PLANADAPT S1 fix_empfehlung');
      final w1 = buildWorld(clock: clock);
      await startApp(t, w1);
      await _onHome(t);
      await waitFor(
        t,
        () => has('plan_adapt_recommendation'),
        'Empfehlung bei fix',
      );
      log('S1 text=${txt('plan_adapt_recommendation_text')}');
      expect(
        has('plan_change_card'),
        isFalse,
        reason: 'S1 keine Karte Plan angepasst',
      );
      expect(
        (await _unit(t, s, d))!.kind,
        hard.kind,
        reason: 'S1 Einheit unveraendert',
      );
      expect(
        (await _history(t, s)).length,
        versions0,
        reason: 'S1 keine neue Fassung',
      );
      await shot(t, 's1_fix');
      await tapKey(t, 'plan_adapt_easy_run');
      await waitFor(t, () => has('home_easy_dialog'), 'Dialog locker laufen');
      await tapDialog(t, 'home_easy_cancel');
      // Abbrechen aendert nichts; Wirkung: plan_adapt_easy_run wieder
      // bedienbar (solange der Dialog offen ist, liegt er davor).
      await waitFor(
        t,
        () => hittable(t, find.byKey(const Key('plan_adapt_easy_run'))),
        'plan_adapt_easy_run bedienbar nach home_easy_cancel',
      );
      expect(find.byType(ErrorWidget), findsNothing);
      expect(
        (await _unit(t, s, d))!.kind,
        hard.kind,
        reason: 'S1 Abbrechen laesst den Plan',
      );
      expect(
        has('plan_adapt_recommendation'),
        isTrue,
        reason: 'S1 Empfehlung bleibt nach Abbrechen',
      );

      step('PLANADAPT S2 adaptiv');
      await _switchTo(t, 'plan_adapt_adaptive');
      final end2 = DateTime.now().add(const Duration(seconds: 40));
      PlanUnit? eased;
      while (true) {
        eased = await _unit(t, s, d);
        if (eased != null && !eased.isHard) break;
        if (DateTime.now().isAfter(end2)) {
          fail('nach 40 s nicht erreicht: Einheit locker nach adaptiv');
        }
        await pumpFor(t, const Duration(milliseconds: 200));
      }
      final h2 = await _history(t, s);
      log('S2 art=${eased.kind.name} minuten=${eased.minutes}');
      expect(
        await _mode(t, s),
        PlanAdaptationMode.adaptive,
        reason: 'S2 Modus adaptiv',
      );
      expect(h2.length, versions0 + 1, reason: 'S2 genau eine Fassung');
      expect(
        h2.last.trigger,
        PlanTrigger.feedback,
        reason: 'S2 Ausloeser feedback',
      );
      expect(h2.last.reason, planReasonReadiness, reason: 'S2 Grund readiness');
      expect(eased.minutes, hard.minutes, reason: 'S2 gleiche Minuten');
      await shot(t, 's2_plan');
      await tapKey(t, 'home_today');
      await _onHome(t);
      await waitFor(t, () => has('plan_change_card'), 'Karte Plan angepasst');
      expect(
        has('plan_adapt_recommendation'),
        isFalse,
        reason: 'S2 keine Empfehlung bei adaptiv',
      );
      await shot(t, 's2_heute');

      step('PLANADAPT S3 zurueck_fix');
      await _switchTo(t, 'plan_adapt_fixed');
      final end3 = DateTime.now().add(const Duration(seconds: 40));
      while (true) {
        final u = await _unit(t, s, d);
        if (u != null && u.isHard) break;
        if (DateTime.now().isAfter(end3)) {
          fail('nach 40 s nicht erreicht: Einheit zurueck nach fix');
        }
        await pumpFor(t, const Duration(milliseconds: 200));
      }
      final h3 = await _history(t, s);
      expect(
        (await _unit(t, s, d))!.kind,
        hard.kind,
        reason: 'S3 urspruengliche Art',
      );
      expect(h3.length, versions0 + 2, reason: 'S3 eine weitere Fassung');
      expect(
        h3.last.reason,
        planReasonAdaptationFixed,
        reason: 'S3 Grund adaptationFixed',
      );
      await tapKey(t, 'home_today');
      await _onHome(t);
      await waitFor(
        t,
        () => has('plan_adapt_recommendation'),
        'Empfehlung wieder bei fix',
      );
      await shot(t, 's3_heute');
      log('S3 ok');
    }),
  );
}
