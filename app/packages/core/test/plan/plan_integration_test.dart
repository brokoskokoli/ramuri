import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _today = DateTime.utc(2026, 11, 11); // Mittwoch

TrainingGoal _goal({
  Set<int> days = const {2, 4, 6},
  int maxMin = 120,
  ContinuousRun30 c30 = ContinuousRun30.yes,
  double? stated,
  GoalDistance distance = GoalDistance.fiveKilometers,
  DateTime? date,
}) => TrainingGoal(
  type: GoalType.distance,
  distance: distance,
  targetDate: date ?? DateTime.utc(2027, 5, 31),
  runDays: days,
  maxSessionSeconds: maxMin * 60.0,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  currentWeeklySeconds: stated,
  canRun30: c30,
);

String _sig(PlanUnit u) =>
    '${u.day.toIso8601String()}|${u.kind.name}|${u.minutes}|'
    '${[for (final s in u.segments) '${s.kind.name}:${s.seconds ?? s.minutes}:'
          '${s.intensity?.rpeMin}-${s.intensity?.rpeMax}:'
          '${s.intensity?.paceFastSecondsPerKm}:${s.intensity?.basisCode}'].join(',')}';

IntensityInputs _reference() => IntensityInputs(
  referenceSeconds: 1500,
  referenceMeters: 5000,
  referenceAgeDays: 5,
);

void main() {
  group('Zielintensität im Plan (FR-0153, ADR-0010 Punkt 2, 11)', () {
    test('neue Einheiten tragen die Intensität, eingefrorene bleiben', () {
      final goal = _goal();
      final frozen = PlanUnit(
        day: DateTime.utc(2026, 11, 10),
        kind: PlanUnitKind.easy,
        phase: PlanPhase.build,
        weekIndex: 0,
        minutes: 30,
        segments: const [PlanSegment(kind: PlanSegmentKind.easy, minutes: 30)],
      );
      final inputs = PlanInputs(
        anchor: DateTime.utc(2026, 11, 9),
        startWeeklyMinutes: 90,
        today: _today,
        intensity: _reference(),
      );
      final plan = generatePlan(goal, inputs, [frozen], _today);
      expect(plan.frozenUnits.single.segments.single.intensity, isNull);
      final hard = plan.units.firstWhere((u) => u.isHard);
      final interval = hard.segments.firstWhere(
        (s) =>
            s.kind == PlanSegmentKind.interval ||
            s.kind == PlanSegmentKind.tempo,
      );
      expect(interval.intensity?.basisCode, 'reference');
      expect(interval.intensity?.paceFastSecondsPerKm, isNotNull);
      for (final u in plan.units) {
        for (final s in u.segments) {
          expect(s.intensity?.rpeMin, isNotNull, reason: _sig(u));
        }
      }
    });

    test('ohne Grundlagen nur RPE', () {
      final plan = generatePlan(
        _goal(),
        PlanInputs(
          anchor: DateTime.utc(2026, 11, 9),
          startWeeklyMinutes: 90,
          today: _today,
        ),
        const [],
        _today,
      );
      for (final u in plan.units) {
        for (final s in u.segments) {
          expect(s.intensity?.basisCode, 'effort');
          expect(s.intensity?.paceFastSecondsPerKm, isNull);
        }
      }
    });

    test('JSON-Rundreise der Eingaben, gleicher Plan', () {
      final goal = _goal(c30: ContinuousRun30.no);
      final base = PlanInputs.forNewGoal(goal, _today);
      final inputs = base.copyWith(
        intensity: IntensityInputs(
          referenceSeconds: 1500,
          referenceMeters: 5000,
          referenceAgeDays: 5,
          longestPauseSinceReferenceDays: 3,
          vo2max: 45,
          vo2maxGrade: Vo2maxGrade.good,
          heartRate: const HeartRateBasis(
            maxBpm: 190,
            restingBpm: 55,
            maxIsEstimated: true,
          ),
        ),
      );
      final text = jsonEncode(inputs.toJson());
      final back = PlanInputs.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      expect(jsonEncode(back.toJson()), text);
      expect(back.walkRunStart, const WalkRunPosition(0));
      expect(back.walkRunFrom, _today);
      final a = generatePlan(goal, inputs, const [], _today);
      final b = generatePlan(goal, back, const [], _today);
      expect(
        [for (final u in a.units) _sig(u)],
        [for (final u in b.units) _sig(u)],
      );
    });

    test('fromJson lehnt Ungültiges in intensity und walkRunStart ab', () {
      final ok = PlanInputs.forNewGoal(
        _goal(c30: ContinuousRun30.no),
        _today,
      ).toJson();
      expect(
        () => PlanInputs.fromJson({
          ...ok,
          'walkRunStart': {'week': -1},
        }),
        throwsFormatException,
      );
      expect(
        () => PlanInputs.fromJson({...ok, 'intensity': 'x'}),
        throwsFormatException,
      );
      expect(
        () => PlanInputs.fromJson({
          ...ok,
          'intensity': {
            ...IntensityInputs().toJson(),
            'zoneBounds': [1, 2],
          },
        }),
        throwsFormatException,
      );
    });
  });

  group('Einstieg: Geh-Lauf-Abfolge (PAR-192, PAR-065, PAR-141)', () {
    List<PlanUnit> walkUnits(GeneratedPlan p) => [
      for (final u in p.units)
        if (u.kind == PlanUnitKind.walkRun) u,
    ];

    test('ja: keine Abfolge, Start mit 30 min je Lauftag', () {
      final i = PlanInputs.forNewGoal(_goal(), _today);
      expect(i.walkRunStart, isNull);
      expect(i.walkRunWeeks, 0);
      expect(i.startWeeklyMinutes, 90);
    });

    test(
      'nein, 3 Tage: 9 Programmwochen ab dem ersten Lauftag, dann 3 x 30',
      () {
        final goal = _goal(c30: ContinuousRun30.no);
        final i = PlanInputs.forNewGoal(goal, _today);
        expect(i.walkRunStart, const WalkRunPosition(0));
        expect(i.startWeeklyMinutes, 90);
        // Mittwoch angelegt: Donnerstag und Samstag der Ankerwoche gehören
        // dazu, der Dienstag davor nicht -> 27 Einheiten in 10 Kalenderwochen.
        expect(i.walkRunWeeks, 10);
        final plan = generatePlan(goal, i, const [], _today);
        final walk = walkUnits(plan);
        expect(walk, hasLength(27));
        expect(walk.first.day, DateTime.utc(2026, 11, 12));
        expect(walk.first.weekIndex, 0);
        // Programmwoche 1: 8 Läufe zu 1 min.
        expect(
          walk.first.segments.where((s) => s.kind == PlanSegmentKind.run),
          hasLength(8),
        );
        // Letzte Einheit: Programmwoche 9, 30 min Dauerlauf mit Gehen davor/danach.
        final last = walk.last;
        expect(
          last.segments
              .where((s) => s.kind == PlanSegmentKind.run)
              .single
              .minutes,
          30,
        );
        expect(last.minutes, 40);
        // Danach Wochenzeit 90 (PAR-192), keine Abfolge mehr.
        final after = plan.units.where((u) => u.day.isAfter(last.day)).toList();
        expect(after.every((u) => u.kind != PlanUnitKind.walkRun), isTrue);
        final firstRunWeek = plan.weeks.firstWhere((w) => w.minutes != null);
        expect(firstRunWeek.index, 10);
        expect(firstRunWeek.minutes, 90);
        expect(
          after
              .where((u) => u.weekIndex == 10)
              .fold<int>(0, (a, u) => a + u.minutes),
          90,
        );
        // PAR-193 bis PAR-195 nicht in der Abfolge: keine Wochenzeit.
        expect(
          plan.weeks.where((w) => w.index < 10).every((w) => w.minutes == null),
          isTrue,
        );
        expect(plan.walkRunStaysAtWeek, isNull);
      },
    );

    test('Abfolge hat Zielintensität (RPE)', () {
      final goal = _goal(c30: ContinuousRun30.no);
      final plan = generatePlan(
        goal,
        PlanInputs.forNewGoal(goal, _today),
        const [],
        _today,
      );
      final u = plan.units.first;
      expect(u.kind, PlanUnitKind.walkRun);
      expect(u.segments.every((s) => s.intensity?.rpeMax != null), isTrue);
    });

    test(
      'Stand genannt, aber unter 30 min am Stück: Abfolge, dann 30 je Tag',
      () {
        final goal = _goal(c30: ContinuousRun30.unknown, stated: 60 * 60);
        final i = PlanInputs.forNewGoal(goal, _today);
        expect(i.walkRunStart, isNotNull);
        expect(i.startWeeklyMinutes, 90);
      },
    );

    test('weniger Tage: längere Kalenderfolge (PAR-141)', () {
      final two = PlanInputs.forNewGoal(
        _goal(days: {2, 6}, c30: ContinuousRun30.no),
        _today,
      );
      expect(two.walkRunWeeks, 14); // 27 Einheiten / 2 = 13,5
      final one = PlanInputs.forNewGoal(
        _goal(days: {3}, c30: ContinuousRun30.no),
        _today,
      );
      expect(one.walkRunWeeks, 27);
    });

    test(
      'zu kurze Zeit: bei der letzten passenden Woche bleiben (PAR-141)',
      () {
        final goal = _goal(c30: ContinuousRun30.no, maxMin: 30);
        final i = PlanInputs.forNewGoal(goal, _today);
        final plan = generatePlan(goal, i, const [], _today);
        // Programmwoche 6 hat einen Lauf von 25 min; mit Gehen 3+3 sind das
        // 31 min: Die Abfolge bleibt bei Programmwoche 5 (Index 4).
        expect(plan.walkRunStaysAtWeek, 4);
        expect(plan.walkRunNoWeekFits, isFalse);
        expect(plan.units.every((u) => u.kind == PlanUnitKind.walkRun), isTrue);
        expect(plan.units.every((u) => u.minutes <= 30), isTrue);
        // Die Wiederholung bleibt bis zum Planende dieselbe Woche.
        final lastWeek = plan.units.where(
          (u) => u.weekIndex == plan.units.last.weekIndex,
        );
        final earlier = plan.units.where(
          (u) => u.weekIndex == plan.units.last.weekIndex - 1,
        );
        expect(
          [for (final u in lastWeek) u.minutes],
          [for (final u in earlier) u.minutes],
        );
      },
    );

    test('passt schon die erste Einheit nicht: bleibt dort, gemeldet', () {
      final goal = _goal(c30: ContinuousRun30.no, maxMin: 10);
      final plan = generatePlan(
        goal,
        PlanInputs.forNewGoal(goal, _today),
        const [],
        _today,
      );
      expect(plan.walkRunStaysAtWeek, 0);
      expect(plan.walkRunNoWeekFits, isTrue);
      expect(plan.units, isNotEmpty);
    });
  });

  group('Machbarkeit und Plan teilen die Rechnung (PAR-206)', () {
    test('assessGoal rechnet die Länge der Abfolge wie generatePlan', () {
      // Eingaben mit 3 Tagen und 120 min: Abfolge 10 Wochen. Das Ziel hat
      // später nur 30 min je Einheit: die Abfolge bleibt stehen, die
      // Zielspitze wird nie erreicht. Mit dem gespeicherten Wert 10 wäre sie
      // erreicht.
      final fine = _goal(c30: ContinuousRun30.no);
      final inputs = PlanInputs.forNewGoal(fine, _today);
      final stuck = _goal(c30: ContinuousRun30.no, maxMin: 30);
      final a = assessGoal(goal: stuck, inputs: inputs, today: _today);
      final b = assessGoal(goal: fine, inputs: inputs, today: _today);
      expect(b.reason, FeasibilityReason.peakReached);
      expect(a.reason, isNot(FeasibilityReason.peakReached));
      // Der Plan zeigt dasselbe: nie eine Laufwoche.
      final plan = generatePlan(stuck, inputs, const [], _today);
      expect(plan.weeks.every((w) => w.minutes == null), isTrue);
    });

    test('Zielspitze und Regler kommen aus einem Helfer', () {
      final goal = _goal(distance: GoalDistance.halfMarathon);
      final inputs = PlanInputs(
        anchor: DateTime.utc(2026, 11, 9),
        startWeeklyMinutes: 90,
        today: _today,
      );
      final setup = planCourseSetup(goal, inputs);
      final a = assessGoal(goal: goal, inputs: inputs, today: _today);
      expect(a.regulatorTooLow, setup.regulatorTooLow);
      expect(a.sessionLimitsLongestRun, setup.sessionLimitsLongestRun);
      final plan = generatePlan(goal, inputs, const [], _today);
      expect(plan.weeks.length, setup.course(today: _today).weeks.length);
    });
  });
}
