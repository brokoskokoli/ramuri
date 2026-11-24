import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/plan/plan_controller.dart';
import 'package:running_app/features/plan/plan_data_reader.dart';

import 'helpers/local_clock.dart';

// Andere Sportart ersetzt eine lockere Einheit (FR-0222, PAR-233) in der App:
// Prüfung bei der Zuordnung, Wochenzeit und RPE-Regel (PAR-201), Abstand
// (PAR-059), lockeres Tempo und Stand unverändert, Löschen (ADR-0010).
// Synthetische Daten: Ziel, Plan, Puls und Läufe sind ausgedacht.

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i + 3));

final _d0 = DateTime.utc(2026, 11, 16); // Montag
DateTime _day(int n) => _d0.add(Duration(days: n));

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

// Lauftage Dienstag, Mittwoch, Freitag, Sonntag.
TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {2, 3, 5, 7},
  maxSessionSeconds: 7200,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

class _Env {
  _Env(this.session, this.clock) {
    reader = PlanDataReader(
      session: session,
      clock: clock,
      loadRuns: () async => [...figures],
    );
    controller = PlanController(session: session, clock: clock, reader: reader);
  }

  final StorageSession session;
  final LocalFakeClock clock;
  final figures = <RunFigures>[];
  late final PlanDataReader reader;
  late final PlanController controller;
  PlanRepository get plans => (session as PlanStorage).plans;

  /// Plan ab Montag [_d0] mit 180 min Wochenzeit, Rechnung der Woche ab
  /// Tag 14 (Di locker, Mi progressiv, Fr locker, So lang); Schalter [mode],
  /// Uhr am Dienstag (Tag 15) abends, Wochenprüfung erledigt.
  static Future<_Env> open(PlanAdaptationMode mode) async {
    final session = await FakeStorage().open(_key);
    final e = _Env(session, LocalFakeClock(DateTime(2026, 12, 1, 20)));
    await (session as GoalStorage).goals.save(_goal(), today: _day(0));
    // Grenze „locker“ nach PAR-111: 151 Schläge.
    await session.profile.save(
      const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
    );
    await recalculatePlan(
      plans: e.plans,
      settings: session.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: DateTime.utc(2026, 11, 16, 20),
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: 180),
    );
    await SettingsPlanAdaptationStore(session.settings)
        .set(mode, at: DateTime.utc(2026, 11, 16, 20));
    await recalculatePlan(
      plans: e.plans,
      settings: session.settings,
      trigger: PlanTrigger.manual,
      today: _day(14),
      now: DateTime.utc(2026, 11, 30, 20),
      markChecked: false,
    );
    await session.settings.set(
      planLastCheckDayKey,
      _iso(_day(14)),
      at: DateTime.utc(2026, 11, 30, 20),
    );
    final w = await e.week();
    expect(w.map((u) => '${u.day.weekday}${u.kind.name}'), [
      '2easy',
      '3progressive',
      '5easy',
      '7long',
    ]);
    return e;
  }

  /// Beendete andere Sportart (Seilspringen) am Tag [day] um 7 Uhr mit
  /// [minutes] Bewegungszeit, Durchschnittspuls [avg], [rpe] und [highHr].
  Future<int> sport(
    int day, {
    required int minutes,
    double avg = 130,
    int? rpe = 5,
    double? highHr,
  }) async {
    final d = _day(day);
    final start = DateTime(d.year, d.month, d.day, 7);
    final r = await session.runs.create(
      startedAt: start,
      mode: RunMode.sport,
      sport: OtherSport.rope,
    );
    final end = start.add(Duration(minutes: minutes));
    await session.runs.setState(
      r.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: end.timeZoneOffset,
    );
    if (rpe != null) {
      await session.subjective.save(r.id, RunSubjective(rpe: rpe));
    }
    if (highHr != null) await _highHr(r.id, highHr, end);
    figures.add(
      RunFigures(
        runId: r.id,
        endedAt: end.toUtc(),
        day: _iso(d),
        isRunning: false,
        movingTime: Duration(minutes: minutes),
        totalTime: Duration(minutes: minutes),
        heartRateAverageBpm: avg,
      ),
    );
    return r.id;
  }

  /// Beendeter Lauf am Tag [day] mit [minutes] Bewegungszeit und [rpe].
  Future<int> run(int day, {required int minutes, int? rpe}) async {
    final d = _day(day);
    final start = DateTime(d.year, d.month, d.day, 7);
    final r = await session.runs.create(startedAt: start);
    final end = start.add(Duration(minutes: minutes));
    await session.runs.setState(
      r.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: end.timeZoneOffset,
    );
    if (rpe != null) {
      await session.subjective.save(r.id, RunSubjective(rpe: rpe));
    }
    figures.add(
      RunFigures(
        runId: r.id,
        endedAt: end.toUtc(),
        day: _iso(d),
        movingTime: Duration(minutes: minutes),
        distanceMeters: minutes * 60 / 0.36,
        paceTime: Duration(minutes: minutes),
      ),
    );
    return r.id;
  }

  Future<void> _highHr(int runId, double minutes, DateTime end) =>
      session.values.createOriginals(ValueOwner.run(runId), [
        ComputedValue(
          key: highHeartRateTimeValueKey,
          value: minutes,
          unit: minutesUnit,
          computedAt: end.toUtc(),
          measurementCount: 600,
          sources: const ['strap'],
          method: HighHeartRateTime.methodId,
          methodVersion: 1,
          parameterVersion: 1,
          quality: ValueQuality.good,
        ),
      ]);

  Future<PlanUnit> unit(int day) async => (await plans.unitOn(_day(day)))!;

  Future<PlanActionResult> assign(int day, int runId) async =>
      controller.assignRun((await unit(day)).id!, runId);

  Future<List<PlanUnit>> week() => plans.unitsBetween(_day(14), _day(20));
}

void main() {
  // Uhr: Dienstag, Tag 15, abends. Woche Tag 14 (Mo) bis Tag 20 (So):
  // Di locker, Mi progressiv, Fr locker, So lang.
  group('Zuordnung nach PAR-233', () {
    test('locker und lang genug: abgehakt und eingefroren', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final tue = await e.unit(15);
      final id = await e.sport(15, minutes: (tue.minutes * 3 / 4).ceil());
      expect(await e.controller.sportReplacementBlock(tue, id), isNull);
      expect(await e.assign(15, id), PlanActionResult.done);
      final after = await e.unit(15);
      expect(after.runId, id);
      expect(after.kind, PlanUnitKind.easy);
      expect(after.minutes, tue.minutes);
      expect((await e.plans.history()).last.trigger, PlanTrigger.run);
    });

    test(
      'unter zwei Dritteln der Dauer: nicht abgehakt, Grund zu kurz',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final tue = await e.unit(15);
        final id = await e.sport(15, minutes: (tue.minutes * 2 / 3).ceil() - 1);
        expect(
          await e.controller.sportReplacementBlock(tue, id),
          SportReplacementBlock.tooShort,
        );
        expect(await e.assign(15, id), PlanActionResult.rejected);
        expect((await e.unit(15)).runId, isNull);
      },
    );

    test('10 min ab 80 % HFmax: nicht abgehakt, Grund zu intensiv; zählt '
        'für den Abstand zu harten Einheiten', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final tue = await e.unit(15);
      final id = await e.sport(15, minutes: tue.minutes, highHr: 10);
      expect(
        await e.controller.sportReplacementBlock(tue, id),
        SportReplacementBlock.tooIntensive,
      );
      expect(await e.assign(15, id), PlanActionResult.rejected);
      expect((await e.unit(15)).runId, isNull);
      final facts = await e.reader.runFacts(_day(15));
      expect(facts.map((f) => f.runId), contains(id));
      expect(planIntensiveRunDays(facts, _day(15)), {_day(15)});
      // Kalender und Verschieben (PAR-060) sehen sie als intensiv.
      final cal = await e.controller.runsBetween(_day(15), _day(15));
      expect(cal.single.intensive, isTrue);
    });

    test(
      'Durchschnittspuls über der Grenze aus PAR-111: zu intensiv',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final tue = await e.unit(15);
        final id = await e.sport(15, minutes: tue.minutes, avg: 160);
        expect(
          await e.controller.sportReplacementBlock(tue, id),
          SportReplacementBlock.tooIntensive,
        );
        expect(await e.assign(15, id), PlanActionResult.rejected);
      },
    );

    test('progressiv und lang lassen sich nicht ersetzen', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      for (final day in [16, 20]) {
        final u = await e.unit(day);
        final id = await e.sport(day, minutes: u.minutes);
        expect(
          await e.controller.sportReplacementBlock(u, id),
          SportReplacementBlock.noEasyUnit,
          reason: u.kind.name,
        );
        expect(
          await e.controller.assignRun(u.id!, id),
          PlanActionResult.rejected,
        );
        expect((await e.unit(day)).runId, isNull);
      }
    });

    test('zweite Sporteinheit derselben Woche: schon ersetzt; in der '
        'Folgewoche wieder möglich', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final tue = await e.unit(15);
      final first = await e.sport(15, minutes: tue.minutes);
      expect(await e.assign(15, first), PlanActionResult.done);
      final fri = await e.unit(18);
      final second = await e.sport(18, minutes: fri.minutes);
      expect(
        await e.controller.sportReplacementBlock(fri, second),
        SportReplacementBlock.alreadyReplaced,
      );
      expect(
        await e.controller.assignRun(fri.id!, second),
        PlanActionResult.rejected,
      );
      final nextTue = await e.unit(22);
      expect(nextTue.kind, PlanUnitKind.easy);
      final third = await e.sport(22, minutes: nextTue.minutes);
      expect(await e.controller.sportReplacementBlock(nextTue, third), isNull);
    });

    test(
      'ein Lauf wird wie bisher ohne Prüfung zugeordnet (PAR-231)',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final id = await e.run(15, minutes: 5);
        expect(await e.assign(15, id), PlanActionResult.done);
        expect((await e.unit(15)).runId, id);
      },
    );
  });

  group('Wochenprüfung (PAR-201)', () {
    test(
      'ersetzte Einheit zählt mit ihrer Bewegungszeit, ohne Zuordnung 0',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final tue = await e.unit(15);
        final minutes = tue.minutes;
        final id = await e.sport(15, minutes: minutes);
        await e.run(18, minutes: 40);
        await e.run(20, minutes: 40);
        final free = await e.reader.weekEvidence(_day(21));
        expect(free.doneMinutes, closeTo(80, 1e-9));
        expect(await e.assign(15, id), PlanActionResult.done);
        final replaced = await e.reader.weekEvidence(_day(21));
        expect(replaced.doneMinutes, closeTo(80 + minutes, 1e-9));
      },
    );

    test('RPE der ersetzten Einheit zählt für die RPE-Regel', () async {
      final e = await _Env.open(PlanAdaptationMode.adaptive);
      final tue = await e.unit(15);
      final id = await e.sport(15, minutes: tue.minutes, rpe: 6);
      final fri = await e.run(18, minutes: 40, rpe: 6);
      expect(await e.assign(18, fri), PlanActionResult.done);
      expect((await e.reader.weekEvidence(_day(21))).recentEasyRpe, [6]);
      expect(await e.assign(15, id), PlanActionResult.done);
      final ev = await e.reader.weekEvidence(_day(21));
      expect(ev.recentEasyRpe, [6, 6]);
      // Zwei von drei lockeren Einheiten mit RPE ≥ 6: −10 % (PAR-201).
      const p = PlanParameters();
      expect(
        ev.recentEasyRpe.where((r) => r != null && r >= p.fatigueRpe).length,
        greaterThanOrEqualTo(p.fatigueRuns),
      );
    });

    test(
      'lockeres Tempo und Stand bleiben mit und ohne ersetzte Einheit',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        await e.run(14, minutes: 40);
        final tue = await e.unit(15);
        final id = await e.sport(15, minutes: tue.minutes);
        final before = await e.reader.read(goal: _goal(), today: _day(15));
        expect(await e.assign(15, id), PlanActionResult.done);
        final after = await e.reader.read(goal: _goal(), today: _day(15));
        expect(after.inputs.toJson(), before.inputs.toJson());
        expect(
          after.goal.currentWeeklySeconds,
          before.goal.currentWeeklySeconds,
        );
        expect(after.goal.currentWeeklySeconds, 40 * 60.0);
      },
    );

    test(
      'Löschen der Sporteinheit: Einheit wieder offen, Woche ohne sie',
      () async {
        final e = await _Env.open(PlanAdaptationMode.adaptive);
        final tue = await e.unit(15);
        final id = await e.sport(15, minutes: tue.minutes);
        expect(await e.assign(15, id), PlanActionResult.done);
        await e.session.deleteRun(id);
        e.figures.removeWhere((f) => f.runId == id);
        expect((await e.unit(15)).runId, isNull);
        expect((await e.reader.weekEvidence(_day(21))).doneMinutes, 0);
      },
    );
  });
}
