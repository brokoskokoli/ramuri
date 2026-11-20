import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Daten: Ziel, Plan und Readiness-Reihen sind ausgedacht.
//
// Simulation über 8 Wochen wie der Ablauf in der App (FR-0157, FR-0158,
// FR-0216, PAR-173): montags die Wochenprüfung ohne Erholungsdaten, danach
// täglich die Prüfung nach neuen Gesundheitsdaten bzw. der Morgenmessung
// (nur „adaptiv“, nur heute, nur eine offene harte Einheit an einem Tag mit
// niedrigem Wert). Dazu Moduswechsel, ein Warnsignal und eine Pause.
final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));
DateTime _now(int n) => DateTime.utc(2026, 11, 11, 8).add(Duration(days: n));

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.minutes}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.minutes}'].join(',')}|'
    '${u.pinned}|${u.fixed.name}|${u.runId}';

/// Härte einer Einheit: Ruhe < locker/lang < hart.
int _rank(PlanUnit u) => switch (u.kind) {
  PlanUnitKind.rest => 0,
  PlanUnitKind.intervals || PlanUnitKind.tempo || PlanUnitKind.progressive => 2,
  _ => 1,
};

const _warnFrom = 40, _warnUntil = 44; // Warnsignal Tag 40 bis 43
const _pauseDay = 47, _lastTraining = 38; // Pause von 9 Tagen (PAR-202)
const _fixedFrom = 14, _adaptiveAgain = 28;

class _Sim {
  _Sim(this.session, this.values) : plans = (session as PlanStorage).plans;
  final StorageSession session;
  final PlanRepository plans;
  final List<int?> values;
  SettingsStore get settings => session.settings;
  WarningStore get warning => (session as WarningStorage).warning;
  SettingsPlanAdaptationStore get mode => SettingsPlanAdaptationStore(settings);

  int eased = 0;
  int restored = 0;
  int fixedChecks = 0;

  static Future<_Sim> open(List<int?> values) async {
    final s = _Sim(
      await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i))),
      values,
    );
    await (s.session as GoalStorage).goals.save(_goal(), today: _day(0));
    await s.recalc(
      PlanTrigger.create,
      0,
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 180),
    );
    await s.mode.set(PlanAdaptationMode.adaptive, at: _now(0));
    return s;
  }

  Future<PlanRecalculation> recalc(
    PlanTrigger t,
    int n, {
    Iterable<PlanReadinessDay> readiness = const [],
    PlanInputs? inputs,
    String? reason,
  }) => recalculatePlan(
    plans: plans,
    settings: settings,
    trigger: t,
    today: _day(n),
    now: _now(n),
    readiness: readiness,
    inputs: inputs,
    reason: reason,
    warning: warning,
  );

  Future<Map<DateTime, PlanUnit>> units() async => {
    for (final u in await plans.unitsBetween(_day(-30), _day(400)))
      planDay(u.day): u,
  };

  PlanReadinessDay? valueOn(int n) {
    final v = values[n];
    return v == null
        ? null
        : PlanReadinessDay.number(
            day: _day(n),
            value: v,
            drivers: const [ReadinessFactorId.hrv, ReadinessFactorId.sleep],
          );
  }

  /// Wie die App nach Import oder Morgenmessung: nur „adaptiv“, nur eine
  /// offene harte Einheit heute, nur bei niedrigem heutigem Wert.
  Future<void> recheck(int n) async {
    if (await mode.read() != PlanAdaptationMode.adaptive) return;
    final unit = await plans.unitOn(_day(n));
    if (unit == null || !recoveryEasable(unit)) return;
    final day = valueOn(n);
    if (day == null || !day.eases) return;
    final before = await units();
    final r = await recalc(
      PlanTrigger.feedback,
      n,
      readiness: [day],
      reason: planReasonReadiness,
    );
    expect(r.wasWritten, isTrue, reason: 'Tag $n');
    final after = await units();
    _expectOnlyToday(before, after, n);
    final was = before[_day(n)]!, now = after[_day(n)]!;
    expect(now.kind, PlanUnitKind.easy, reason: 'Tag $n');
    expect(now.minutes, was.minutes, reason: 'Tag $n');
    expect(_rank(now), lessThan(_rank(was)), reason: 'Tag $n');
    // Grund sichtbar (FR-0170): größere Änderung mit Code „readiness“.
    final history = await plans.history();
    expect(history.last.reason, planReasonReadiness);
    expect(isLargerPlanChange(history.last), isTrue, reason: 'Tag $n');
    final notice = planChangeNotice(history);
    expect(notice?.planId, history.last.id);
    expect(notice?.explanation.code, planReasonReadiness);
    eased++;
  }

  /// Wechsel des Modus wie `PlanController.setAdaptation`.
  Future<void> switchTo(PlanAdaptationMode m, int n) async {
    await mode.set(m, at: _now(n));
    if (m == PlanAdaptationMode.adaptive) return recheck(n);
    final last = (await plans.history()).last;
    final easedToday = recoveryEasedFromSummary(last.summary)
        .any((e) => planDay(e.day) == _day(n));
    if (!easedToday) return;
    final before = await units();
    await recalc(PlanTrigger.feedback, n, reason: planReasonAdaptationFixed);
    final after = await units();
    _expectOnlyToday(before, after, n);
    // Die harte Einheit kehrt zurück, Dauer gleich.
    expect(recoveryEasable(after[_day(n)]!), isTrue, reason: 'Tag $n');
    expect(after[_day(n)]!.minutes, before[_day(n)]!.minutes);
    final history = await plans.history();
    expect(history.last.reason, planReasonAdaptationFixed);
    expect(planChangeNotice(history)?.explanation.code, isNotNull);
    restored++;
  }

  /// Bei „fix“ ändert ein niedriger Wert nichts am Plan.
  Future<void> fixedCheck(int n) async {
    final day = valueOn(n);
    if (day == null || !day.eases) return;
    final before = await units();
    await recalc(PlanTrigger.feedback, n, readiness: [day]);
    expect(
      (await units()).values.map(_sig).toList(),
      before.values.map(_sig).toList(),
      reason: 'Tag $n',
    );
    fixedChecks++;
  }

  void _expectOnlyToday(
    Map<DateTime, PlanUnit> before,
    Map<DateTime, PlanUnit> after,
    int n,
  ) {
    expect(after.keys.toSet(), before.keys.toSet(), reason: 'Tag $n');
    for (final d in before.keys) {
      if (d == _day(n)) continue;
      expect(_sig(after[d]!), _sig(before[d]!), reason: 'Tag $n, $d');
    }
  }
}

void main() {
  // Rund 40 % niedrige Werte (unter 50), dazu Tage ohne Zahl.
  List<int?> series(Random rnd) => [
    for (var n = 0; n <= 56; n++)
      rnd.nextInt(8) == 0
          ? null
          : rnd.nextInt(10) < 4
          ? rnd.nextInt(50)
          : 50 + rnd.nextInt(51),
  ];

  for (final seed in [1, 2, 3, 4, 5]) {
    test('8 Wochen mit Readiness-Reihe $seed, Moduswechseln, Warnsignal und '
        'Pause: nur heute gelockert, mit Grund, nie härter', () async {
      final values = series(Random(seed));
      final s = await _Sim.open(values);
      // Mit Lockerung am Tag des Wechsels auf „fix“: niedriger Wert am ersten
      // harten Tag ab Tag 14.
      var switchDay = _fixedFrom;
      for (var n = _fixedFrom; n < _fixedFrom + 7; n++) {
        final u = await s.plans.unitOn(_day(n));
        if (u != null && recoveryEasable(u)) {
          switchDay = n;
          values[n] = 20;
          break;
        }
      }
      int? lateEased;
      for (var n = 1; n <= 56; n++) {
        final before = await s.units();
        if (n == _warnFrom) {
          await s.warning.set(
            WarningSignal(reportedOn: _day(n), source: WarningSource.manual),
          );
          await s.recalc(PlanTrigger.feedback, n, reason: planReasonWarning);
        }
        if (n == _warnUntil) {
          await s.warning.lift();
          await s.recalc(
            PlanTrigger.feedback,
            n,
            reason: planReasonWarningLifted,
          );
        }
        if (_day(n).weekday == DateTime.monday) {
          await s.recalc(PlanTrigger.weekly, n);
        }
        if (n == _pauseDay) {
          final h = await s.plans.history();
          final restart = planPauseRestart(
            goal: _goal(),
            inputs: h.last.inputs.copyWith(today: _day(n)),
            today: _day(n),
            lastTrainingDay: _day(_lastTraining),
            baseWeekMinutes: 120,
            anchorFromAdjustment: planAnchorFromAdjustment(h),
          );
          expect(restart.inputs, isNotNull);
          await s.recalc(PlanTrigger.pause, n, inputs: restart.inputs);
        }
        if (n == _adaptiveAgain) {
          await s.switchTo(PlanAdaptationMode.adaptive, n);
        }
        final adaptive = await s.mode.read() == PlanAdaptationMode.adaptive;
        if (adaptive) {
          // Im zweiten Abschnitt „adaptiv“ sicher eine Lockerung: niedriger
          // Wert am ersten Tag mit offener harter Einheit.
          final u = await s.plans.unitOn(_day(n));
          if (n >= _adaptiveAgain &&
              lateEased == null &&
              u != null &&
              recoveryEasable(u)) {
            values[n] = 20;
            lateEased = n;
          }
          await s.recheck(n);
        } else {
          await s.fixedCheck(n);
        }
        if (n == switchDay) {
          expect(
            recoveryEasable((await s.plans.unitOn(_day(n)))!),
            isFalse,
            reason: 'Tag $n: vor dem Wechsel gelockert',
          );
          await s.switchTo(PlanAdaptationMode.fixed, n);
        }
        // Vergangene Tage bleiben, was sie waren.
        final after = await s.units();
        for (final d in before.keys) {
          if (!d.isBefore(_day(n))) continue;
          expect(_sig(after[d]!), _sig(before[d]!), reason: 'Tag $n, $d');
        }
      }
      final all = await s.units();
      // Unter dem Warnsignal nur Ruhetage.
      for (var n = _warnFrom; n < _warnUntil; n++) {
        final u = all[_day(n)];
        if (u != null) expect(u.kind, PlanUnitKind.rest, reason: 'Tag $n');
      }
      // Woche des Neustarts nach der Pause ohne harte Einheit (PAR-202).
      for (var n = _pauseDay; _day(n).weekday != DateTime.monday; n++) {
        final u = all[_day(n)];
        if (u != null) expect(u.isHard, isFalse, reason: 'Tag $n');
      }
      // Die Reihe prüft etwas: Lockerungen, Rückkehr und „fix“.
      expect(lateEased, isNotNull);
      expect(s.eased, greaterThanOrEqualTo(2));
      expect(s.restored, 1);
      expect(s.fixedChecks, greaterThan(0));
      // Jede Lockerung im Verlauf trägt den Grund „readiness“.
      final history = await s.plans.history();
      expect(
        history.where((v) => v.reason == planReasonReadiness).length,
        s.eased,
      );
    });
  }
}
