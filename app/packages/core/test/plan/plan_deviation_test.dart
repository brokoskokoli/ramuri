import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Synthetische Daten: Ziel, Plan und Läufe sind ausgedacht.
final _d0 = DateTime.utc(2026, 11, 16); // Montag
DateTime _day(int n) => _d0.add(Duration(days: n));
DateTime _now(int n) => DateTime.utc(2026, 11, 16, 20).add(Duration(days: n));

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

PlanUnit _unit(
  PlanUnitKind kind,
  int minutes, {
  int day = 0,
  bool pinned = false,
  int? runId,
}) => PlanUnit(
  day: _day(day),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: 0,
  minutes: minutes,
  segments: [PlanSegment(kind: PlanSegmentKind.easy, minutes: minutes)],
  pinned: pinned,
  runId: runId,
);

PlanRunFacts _facts({
  int runId = 1,
  int day = 0,
  int? minutes,
  int? rpe,
  double? highHr,
}) => PlanRunFacts(
  runId: runId,
  day: _day(day),
  movingSeconds: minutes == null ? null : minutes * 60,
  rpe: rpe,
  highHrMinutes: highHr,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String().substring(0, 10)}|${u.kind.name}|'
    '${u.minutes}|${u.pinned}|${u.runId}';

class _Env {
  _Env(this.session) : plans = (session as PlanStorage).plans;
  final StorageSession session;
  final PlanRepository plans;
  final runs = <PlanRunFacts>[];

  /// Plan ab Montag [_d0] mit [startMinutes] Wochenzeit; Schalter [mode].
  static Future<_Env> open({
    required PlanAdaptationMode mode,
    int startMinutes = 150,
  }) async {
    final e = _Env(
      await FakeStorage().open(Uint8List.fromList(List.generate(32, (i) => i))),
    );
    await (e.session as GoalStorage).goals.save(_goal(), today: _day(0));
    await recalculatePlan(
      plans: e.plans,
      settings: e.session.settings,
      trigger: PlanTrigger.create,
      today: _day(0),
      now: _now(0),
      inputs: PlanInputs.forNewGoal(
        _goal(),
        _day(0),
      ).copyWith(startWeeklyMinutes: startMinutes),
    );
    await SettingsPlanAdaptationStore(e.session.settings)
        .set(mode, at: _now(0));
    return e;
  }

  Future<PlanRecalculation> recalc(
    int n, {
    PlanTrigger trigger = PlanTrigger.run,
  }) => recalculatePlan(
    plans: plans,
    settings: session.settings,
    trigger: trigger,
    today: _day(n),
    now: _now(n),
    markChecked: false,
    runs: runs,
  );

  /// Lauf am Tag [n], der Einheit des Tags zugeordnet; dann Neuberechnung
  /// mit Auslöser `run` an dem Tag.
  Future<PlanRecalculation> run(
    int n, {
    int? minutes,
    int? rpe,
    double? highHr,
  }) async {
    final unit = (await plans.unitOn(_day(n)))!;
    final id = (await session.runs.create(startedAt: _day(n))).id;
    await plans.assignRun(unit.id!, id);
    runs.add(
      _facts(runId: id, day: n, minutes: minutes, rpe: rpe, highHr: highHr),
    );
    return recalc(n);
  }

  Future<List<PlanUnit>> week(int from) =>
      plans.unitsBetween(_day(from), _day(from + 6));

  Future<List<String>> sigs(int from) async => [
    for (final u in await week(from)) _sig(u),
  ];

  Future<PlanVersionRecord> last() async => (await plans.history()).last;
}

int _sum(Iterable<PlanUnit> units) => units.fold(0, (a, u) => a + u.minutes);

void main() {
  group('Erkennung (PAR-235)', () {
    test('30 min geplant: 59 min gelaufen nicht, 60 min deutlich mehr', () {
      final u = _unit(PlanUnitKind.easy, 30);
      expect(detectPlanDeviation(u, _facts(minutes: 59)).muchMore, isFalse);
      expect(detectPlanDeviation(u, _facts(minutes: 60)).muchMore, isTrue);
    });

    test('locker (Obergrenze 4): RPE 6 nicht, RPE 7 deutlich mehr', () {
      final u = _unit(PlanUnitKind.easy, 30);
      expect(planUnitRpeUpper(PlanUnitKind.easy), 4);
      expect(
        detectPlanDeviation(u, _facts(minutes: 30, rpe: 6)).muchMore,
        isFalse,
      );
      expect(
        detectPlanDeviation(u, _facts(minutes: 30, rpe: 7)).muchMore,
        isTrue,
      );
    });

    test('Intervalle (Obergrenze 8): RPE 10 löst nicht aus, nur die Zeit', () {
      final u = _unit(PlanUnitKind.intervals, 40);
      expect(planUnitRpeUpper(PlanUnitKind.intervals), 8);
      expect(
        detectPlanDeviation(u, _facts(minutes: 40, rpe: 10)).muchMore,
        isFalse,
      );
      expect(
        detectPlanDeviation(u, _facts(minutes: 80, rpe: 10)).muchMore,
        isTrue,
      );
    });

    test('ohne RPE nur über die Zeit; ohne Zeit und RPE nie', () {
      final u = _unit(PlanUnitKind.easy, 30);
      expect(detectPlanDeviation(u, _facts(minutes: 59)).muchMore, isFalse);
      expect(detectPlanDeviation(u, _facts(minutes: 61)).muchMore, isTrue);
      expect(detectPlanDeviation(u, _facts()).muchMore, isFalse);
    });

    test('Obergrenzen je Art nach PAR-105, progressiv nach dem Endblock', () {
      expect(planUnitRpeUpper(PlanUnitKind.long), 4);
      expect(planUnitRpeUpper(PlanUnitKind.tempo), 7);
      expect(planUnitRpeUpper(PlanUnitKind.progressive), 7);
      expect(planUnitRpeUpper(PlanUnitKind.walkRun), 4);
      expect(planUnitRpeUpper(PlanUnitKind.rest), isNull);
      final p = _unit(PlanUnitKind.progressive, 40);
      expect(detectPlanDeviation(p, _facts(rpe: 9)).muchMore, isFalse);
      expect(detectPlanDeviation(p, _facts(rpe: 10)).muchMore, isTrue);
    });

    test('intensiv statt locker: locker, lang oder Geh-Lauf und nach PAR-058 '
        'intensiv (RPE 7 oder 10 min über 80 % HFmax)', () {
      for (final k in [
        PlanUnitKind.easy,
        PlanUnitKind.long,
        PlanUnitKind.walkRun,
      ]) {
        final u = _unit(k, 30);
        expect(
          detectPlanDeviation(u, _facts(rpe: 7)).intensiveInsteadOfEasy,
          isTrue,
        );
        expect(
          detectPlanDeviation(u, _facts(highHr: 10)).intensiveInsteadOfEasy,
          isTrue,
        );
        expect(
          detectPlanDeviation(
            u,
            _facts(rpe: 6, highHr: 9.9),
          ).intensiveInsteadOfEasy,
          isFalse,
        );
      }
      for (final k in [
        PlanUnitKind.intervals,
        PlanUnitKind.tempo,
        PlanUnitKind.progressive,
      ]) {
        expect(
          detectPlanDeviation(
            _unit(k, 30),
            _facts(rpe: 9),
          ).intensiveInsteadOfEasy,
          isFalse,
        );
      }
    });
  });

  group('Adaptiv: deutlich mehr kürzt den Rest der Woche (PAR-235, '
      'FR-0157)', () {
    test('Woche 150 min, Einheit 30 min mit 65 min gelaufen: Rest um 35 min '
        'gekürzt, lockere zuerst, Woche höchstens Wochenzeit', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final before = await e.week(0);
      expect(before.map((u) => '${u.day.weekday}${u.kind.name}${u.minutes}'), [
        '2easy30',
        '3easy30',
        '5easy30',
        '7long60',
      ]);
      final r = await e.run(1, minutes: 65);
      expect(r.wasWritten, isTrue);
      expect(r.version!.trigger, PlanTrigger.run);
      final after = await e.week(0);
      final rest = after.where((u) => u.runId == null).toList();
      // Freitag (späteste lockere) entfällt, Mittwoch verliert 5 min, der lange
      // Lauf bleibt.
      expect(rest.map((u) => '${u.day.weekday}${u.kind.name}${u.minutes}'), [
        '3easy25',
        '7long60',
      ]);
      expect(_sum(rest), 120 - 35);
      expect(65 + _sum(rest), lessThanOrEqualTo(150));
      // Die erledigte Einheit behält ihre Vorgabe (PAR-203).
      expect(after.first.minutes, 30);
      expect(after.first.runId, isNotNull);
      expect(r.generated!.droppedDaysByWeek[0], [_day(4)]);
      final notes = planRunNotesFromSummary((await e.last()).summary);
      expect(notes, hasLength(1));
      expect(notes.single.day, _day(2));
      expect(notes.single.change, PlanRunChange.shortened);
      expect(notes.single.runDay, _day(1));
      // Folgewoche unverändert.
      expect(_sum(await e.week(7)), _sum(await _planned(7)));
      // Idempotent: erneutes Neuberechnen ändert nichts weiter.
      final first = await e.sigs(0);
      expect((await e.recalc(1)).wasWritten, isFalse);
      expect(
        (await e.recalc(1, trigger: PlanTrigger.manual)).wasWritten,
        isFalse,
      );
      expect((await e.recalc(2)).wasWritten, isFalse);
      expect(await e.sigs(0), first);
    });

    test('45 min gelaufen (unter 2 ×): keine Änderung', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final before = await e.sigs(2);
      final r = await e.run(1, minutes: 45);
      expect(await e.sigs(2), before);
      expect(r.generated!.runNotes, isEmpty);
      expect(planRunNotesFromSummary(r.version?.summary ?? const {}), isEmpty);
    });

    test('RPE 7 bei gleicher Zeit: deutlich mehr, aber weniger oder gleiche '
        'Zeit erhöht nichts', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
      final before = await e.sigs(2);
      await e.run(1, minutes: 25, rpe: 7);
      expect(await e.sigs(2), before);
    });
  });

  group('Adaptiv: intensiv statt locker ersetzt die harte Einheit '
      '(PAR-235, PAR-058)', () {
    // Woche ab Tag 14: Di locker, Mi progressiv, Fr locker, So lang.
    Future<_Env> open() async {
      final e = await _Env.open(
        mode: PlanAdaptationMode.adaptive,
        startMinutes: 180,
      );
      await e.recalc(14, trigger: PlanTrigger.manual);
      final w = await e.week(14);
      expect(w.map((u) => '${u.day.weekday}${u.kind.name}'), [
        '2easy',
        '3progressive',
        '5easy',
        '7long',
      ]);
      return e;
    }

    for (final (label, rpe, highHr) in [
      ('RPE 7', 7, null),
      ('Puls: 12 min über 80 % HFmax', null, 12.0),
    ]) {
      test('locker geplant, intensiv gelaufen ($label): die harte Einheit '
          'am Mittwoch wird locker mit Begründung', () async {
        final e = await open();
        final wed = (await e.plans.unitOn(_day(16)))!;
        await e.run(15, minutes: 36, rpe: rpe, highHr: highHr);
        final now = (await e.plans.unitOn(_day(16)))!;
        expect(now.kind, PlanUnitKind.easy);
        expect(now.minutes, wed.minutes);
        final notes = planRunNotesFromSummary((await e.last()).summary);
        final n = planRunNoteFor(now, notes)!;
        expect(n.change, PlanRunChange.eased);
        expect(n.runDay, _day(15));
      });
    }

    test(
      'ohne weitere intensive Einheit in der Woche: keine Änderung',
      () async {
        final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
        final before = await e.sigs(2);
        final r = await e.run(1, minutes: 30, rpe: 7);
        expect(await e.sigs(2), before);
        expect(r.generated!.runNotes, isEmpty);
      },
    );

    test('Idempotenz: zweimal Neuberechnen ergibt dieselbe Fassung', () async {
      final e = await open();
      await e.run(15, minutes: 80, rpe: 7);
      final first = await e.sigs(14);
      final count = (await e.plans.history()).length;
      final again = await e.recalc(15);
      expect(again.wasWritten, isFalse);
      final manual = await e.recalc(15, trigger: PlanTrigger.manual);
      expect(manual.wasWritten, isFalse);
      expect(await e.sigs(14), first);
      expect((await e.plans.history()).length, count);
      // Am nächsten Tag ebenso.
      await e.recalc(16);
      expect(await e.sigs(14), first);
    });
  });

  group('Fix (FR-0216)', () {
    test('2,5 × geplante Dauer gelaufen: keine Planänderung', () async {
      final e = await _Env.open(mode: PlanAdaptationMode.fixed);
      final before = await e.sigs(2);
      final r = await e.run(1, minutes: 75);
      expect(await e.sigs(2), before);
      expect(r.generated!.runNotes, isEmpty);
    });

    test('intensiv gelaufen am Dienstag, harte Einheit am Mittwoch, locker am '
        'Freitag: Tausch, Art und Dauer bleiben; idempotent', () async {
      final e = await _Env.open(
        mode: PlanAdaptationMode.fixed,
        startMinutes: 180,
      );
      await e.recalc(14, trigger: PlanTrigger.manual);
      final wed = (await e.plans.unitOn(_day(16)))!;
      final fri = (await e.plans.unitOn(_day(18)))!;
      expect(wed.kind, PlanUnitKind.progressive);
      expect(fri.kind, PlanUnitKind.easy);
      await e.run(15, minutes: 36, rpe: 7);
      final wedNow = (await e.plans.unitOn(_day(16)))!;
      final friNow = (await e.plans.unitOn(_day(18)))!;
      expect(friNow.kind, PlanUnitKind.progressive);
      expect(friNow.minutes, wed.minutes);
      expect(wedNow.kind, PlanUnitKind.easy);
      expect(wedNow.minutes, fri.minutes);
      final notes = planRunNotesFromSummary((await e.last()).summary);
      expect(planRunNoteFor(friNow, notes)?.change, PlanRunChange.swapped);
      expect(planRunNoteFor(friNow, notes)?.otherDay, _day(16));
      expect(planRunNoteFor(wedNow, notes)?.otherDay, _day(18));
      expect(planRunNoteFor(friNow, notes)?.runDay, _day(15));
      final first = await e.sigs(14);
      expect((await e.recalc(15)).wasWritten, isFalse);
      expect(
        (await e.recalc(15, trigger: PlanTrigger.manual)).wasWritten,
        isFalse,
      );
      expect(await e.sigs(14), first);
      // Ohne den intensiven Lauf bleibt der Plan, wie er war.
      expect(
        planRunSpacingConflicts(
          await e.week(14),
          planIntensiveRunDays(e.runs, _day(15)),
          _day(15),
        ),
        isEmpty,
      );
    });

    test('locker gelaufener Dienstag: kein Tausch', () async {
      final e = await _Env.open(
        mode: PlanAdaptationMode.fixed,
        startMinutes: 180,
      );
      await e.recalc(14, trigger: PlanTrigger.manual);
      final before = await e.sigs(16);
      await e.run(15, minutes: 36, rpe: 4);
      expect(await e.sigs(16), before);
    });

    test('harte Einheit am Mittwoch `pinned`: kein Tausch, Konflikthinweis '
        '(PAR-060)', () {
      final units = [
        _unit(PlanUnitKind.intervals, 40, day: 2, pinned: true),
        _unit(PlanUnitKind.easy, 30, day: 4),
        _unit(PlanUnitKind.long, 60, day: 6),
      ];
      final runDays = {_day(1)};
      final s = applyRunSpacingSwap(
        units: units,
        intensiveRunDays: runDays,
        today: _day(1),
      );
      expect(s.units, units);
      expect(s.notes, isEmpty);
      final c = planRunSpacingConflicts(s.units, runDays, _day(1));
      expect(c, hasLength(1));
      expect(c.single.kind, PinnedConflictKind.spacing);
      expect(c.single.day, _day(2));
      expect(c.single.otherDay, _day(1));
    });

    test('lockere Einheit `pinned` oder zu nah an einer anderen intensiven: '
        'kein Tausch, Hinweis', () {
      final runDays = {_day(1)};
      for (final units in [
        [
          _unit(PlanUnitKind.intervals, 40, day: 2),
          _unit(PlanUnitKind.easy, 30, day: 4, pinned: true),
        ],
        [
          _unit(PlanUnitKind.intervals, 40, day: 2),
          _unit(PlanUnitKind.easy, 30, day: 5),
          _unit(PlanUnitKind.long, 60, day: 6),
        ],
      ]) {
        final s = applyRunSpacingSwap(
          units: units,
          intensiveRunDays: runDays,
          today: _day(1),
        );
        expect(s.notes, isEmpty);
        expect(planRunSpacingConflicts(s.units, runDays, _day(1)), isNotEmpty);
      }
    });

    test('Abstandsgrenze: ein voller Tag dazwischen reicht (kein Tausch)', () {
      final units = [
        _unit(PlanUnitKind.intervals, 40, day: 3),
        _unit(PlanUnitKind.easy, 30, day: 5),
      ];
      final s = applyRunSpacingSwap(
        units: units,
        intensiveRunDays: {_day(1)},
        today: _day(1),
      );
      expect(s.notes, isEmpty);
      expect(planRunSpacingConflicts(units, {_day(1)}, _day(1)), isEmpty);
    });

    test('intensiver Lauf am Sonntag der Vorwoche zählt für den Montag', () {
      final runs = [_facts(day: -1, rpe: 8), _facts(runId: 2, day: -3, rpe: 8)];
      expect(planIntensiveRunDays(runs, _day(0)), {_day(-1)});
    });
  });

  group('Begründungen im summary', () {
    test('Hin- und Rückweg; unlesbare Einträge entfallen', () {
      final n = PlanRunNote(
        day: _day(4),
        kind: PlanUnitKind.intervals,
        change: PlanRunChange.swapped,
        runDay: _day(1),
        otherDay: _day(2),
      );
      final back = planRunNotesFromSummary({
        planRunNotesKey: [
          n.toJson(),
          'x',
          <String, Object?>{'day': 1},
        ],
      });
      expect(back, hasLength(1));
      expect(back.single.toJson(), n.toJson());
    });
  });
}

/// Die Einheiten der Woche ab Tag [from] eines frischen Plans ohne Läufe.
Future<List<PlanUnit>> _planned(int from) async {
  final e = await _Env.open(mode: PlanAdaptationMode.adaptive);
  return e.week(from);
}
