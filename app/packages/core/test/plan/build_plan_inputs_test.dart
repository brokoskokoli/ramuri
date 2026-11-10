import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

final _today = DateTime.utc(2026, 11, 11); // Mittwoch

const _hr = HeartRateBasis(maxBpm: 190, restingBpm: 55);
// Grenze: min(55 + 0,70 * 135 = 149,5; 0,8 * 190 = 152) = 149,5.

TrainingGoal _goal({
  ContinuousRun30 c30 = ContinuousRun30.yes,
  double? stated,
}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 5, 31),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 120 * 60.0,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  currentWeeklySeconds: stated,
  canRun30: c30,
);

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Lauf [ago] Tage vor heute: 5 km in [paceSec] s/km, Puls [avgHr].
RunFigures _run(
  int id,
  int ago,
  double paceSec, {
  double? avgHr = 140,
  int minutes = 30,
}) {
  final d = _today.subtract(Duration(days: ago));
  return RunFigures(
    runId: id,
    endedAt: d.add(const Duration(hours: 8)),
    day: _day(d),
    distanceMeters: 5000,
    movingTime: Duration(minutes: minutes),
    totalTime: Duration(minutes: minutes),
    paceTime: Duration(seconds: (paceSec * 5).round()),
    heartRateAverageBpm: avgHr,
  );
}

BuiltPlanInputs _build(
  List<RunFigures> runs, {
  TrainingGoal? goal,
  ReferencePerformance? reference,
  DateTime? today,
}) => buildPlanInputs(
  goal: goal ?? _goal(),
  today: today ?? _today,
  runs: runs,
  reference: reference,
  heartRate: _hr,
);

ReferencePerformance _ref(DateTime date) => ReferencePerformance(
  kind: ReferenceKind.values.first,
  distanceMeters: 5000,
  seconds: 1500,
  date: date,
  createdAt: date,
);

void main() {
  group('Lockeres Tempo (PAR-205)', () {
    test('Median aus 3 lockeren Läufen', () {
      final b = _build([_run(1, 3, 360), _run(2, 10, 330), _run(3, 20, 400)]);
      expect(b.inputs.easyPaceSecondsPerKm, 360);
      expect(b.inputs.easyRunCount, 3);
    });

    test('gerade Zahl: Mittel der beiden mittleren', () {
      final b = _build([
        _run(1, 3, 300),
        _run(2, 10, 340),
        _run(3, 20, 360),
        _run(4, 25, 500),
      ]);
      expect(b.inputs.easyPaceSecondsPerKm, 350);
    });

    test('weniger als 3 lockere Läufe: kein Tempo, Zahl bleibt', () {
      final b = _build([_run(1, 3, 360), _run(2, 10, 330)]);
      expect(b.inputs.easyPaceSecondsPerKm, isNull);
      expect(b.inputs.easyRunCount, 2);
      expect(
        targetLongestRunMinutes(
          distance: GoalDistance.tenKilometers,
          easyPaceSecondsPerKm: b.inputs.easyPaceSecondsPerKm,
          easyRunCount: b.inputs.easyRunCount,
        ),
        65,
      );
    });

    test('nicht lockere Läufe (Puls über Grenze) zählen nicht', () {
      final b = _build([
        _run(1, 3, 360),
        _run(2, 10, 330),
        _run(3, 20, 300, avgHr: 150), // 150 >= 149,5
        _run(4, 21, 300, avgHr: null), // ohne Puls nicht bestimmbar
      ]);
      expect(b.inputs.easyRunCount, 2);
      expect(b.inputs.easyPaceSecondsPerKm, isNull);
      final c = _build([
        _run(1, 3, 360),
        _run(2, 10, 330),
        _run(3, 20, 300, avgHr: 149),
      ]);
      expect(c.inputs.easyRunCount, 3);
    });

    test('80 % HFmax gilt, wenn niedriger als Reservegrenze (PAR-111)', () {
      const high = HeartRateBasis(maxBpm: 190, restingBpm: 80);
      // Reservegrenze 80 + 0,7 * 110 = 157, 80 % HFmax = 152 -> 152.
      List<RunFigures> runs(double hr) => [
        _run(1, 3, 360, avgHr: hr),
        _run(2, 10, 360, avgHr: hr),
        _run(3, 20, 360, avgHr: hr),
      ];
      expect(
        buildPlanInputs(
          goal: _goal(),
          today: _today,
          runs: runs(151),
          heartRate: high,
        ).inputs.easyRunCount,
        3,
      );
      expect(
        buildPlanInputs(
          goal: _goal(),
          today: _today,
          runs: runs(153),
          heartRate: high,
        ).inputs.easyRunCount,
        0,
      );
    });

    test('ohne HFmax oder Ruhepuls kein lockerer Lauf', () {
      final runs = [_run(1, 3, 360), _run(2, 4, 360), _run(3, 5, 360)];
      for (final h in [
        null,
        const HeartRateBasis(maxBpm: 190),
        const HeartRateBasis(restingBpm: 55),
      ]) {
        expect(
          buildPlanInputs(
            goal: _goal(),
            today: _today,
            runs: runs,
            heartRate: h,
          ).inputs.easyRunCount,
          0,
        );
      }
    });

    test('locker auch ohne Puls: Zuordnung zu lockerer/langer Einheit', () {
      final runs = [_run(1, 3, 360), _run(2, 4, 360), _run(3, 5, 360)];
      final b = buildPlanInputs(
        goal: _goal(),
        today: _today,
        runs: runs,
        easyPlannedRunIds: const {1, 2, 3},
      );
      expect(b.inputs.easyRunCount, 3);
      expect(b.inputs.easyPaceSecondsPerKm, 360);
    });

    test('locker auch ohne Puls: RPE höchstens 4 (PAR-108/110)', () {
      final runs = [
        _run(1, 3, 360, avgHr: null),
        _run(2, 4, 360, avgHr: null),
        _run(3, 5, 360, avgHr: null),
        _run(4, 6, 300, avgHr: null),
      ];
      final b = buildPlanInputs(
        goal: _goal(),
        today: _today,
        runs: runs,
        rpeByRunId: const {1: 4, 2: 1, 3: 3, 4: 5},
      );
      expect(b.inputs.easyRunCount, 3, reason: 'RPE 5 zählt nicht');
      expect(b.inputs.easyPaceSecondsPerKm, 360);
    });

    test('einer harten/Geh-Lauf-Einheit zugeordnet: nie locker, auch bei '
        'RPE 3 oder niedrigem Puls (NB3 Muss 2)', () {
      final runs = [
        _run(1, 3, 300, avgHr: 130),
        _run(2, 4, 300, avgHr: 130),
        _run(3, 5, 300, avgHr: 130),
        _run(4, 6, 360, avgHr: 130), // ohne Zuordnung: Puls Zone 1-2
      ];
      final b = buildPlanInputs(
        goal: _goal(),
        today: _today,
        runs: runs,
        heartRate: _hr,
        otherPlannedRunIds: const {1, 2, 3},
        rpeByRunId: const {1: 3, 2: 3, 3: 3},
      );
      expect(b.inputs.easyRunCount, 1);
      // Gegenprobe: ohne Zuordnung zählen alle vier.
      final c = buildPlanInputs(
        goal: _goal(),
        today: _today,
        runs: runs,
        heartRate: _hr,
        rpeByRunId: const {1: 3, 2: 3, 3: 3},
      );
      expect(c.inputs.easyRunCount, 4);
    });

    test('hoher Puls, RPE 6, keine Zuordnung: nicht locker', () {
      // Puls 170 (über der Grenze), ohne Zuordnung, RPE 6: nicht locker.
      final runs = [
        _run(1, 3, 360, avgHr: 170),
        _run(2, 4, 360, avgHr: 170),
        _run(3, 5, 360, avgHr: 170),
      ];
      final b = buildPlanInputs(
        goal: _goal(),
        today: _today,
        runs: runs,
        heartRate: _hr,
        rpeByRunId: const {1: 6, 2: 6, 3: 6},
      );
      expect(b.inputs.easyRunCount, 0);
    });

    test('Fenstergrenze: 6 Wochen = 42 Tage inklusive heute', () {
      // Tag 41 zählt, Tag 42 nicht.
      final inside = _build([
        _run(1, 41, 360),
        _run(2, 3, 360),
        _run(3, 4, 360),
      ]);
      expect(inside.inputs.easyRunCount, 3);
      final outside = _build([
        _run(1, 42, 360),
        _run(2, 3, 360),
        _run(3, 4, 360),
      ]);
      expect(outside.inputs.easyRunCount, 2);
      expect(outside.inputs.easyPaceSecondsPerKm, isNull);
    });

    test('Läufe nach heute zählen nicht', () {
      final b = _build([_run(1, -1, 360), _run(2, 3, 360), _run(3, 4, 360)]);
      expect(b.inputs.easyRunCount, 2);
    });

    test('das Tempo wirkt auf die Zielspitze (PAR-205)', () {
      final b = _build([_run(1, 3, 360), _run(2, 10, 360), _run(3, 20, 360)]);
      expect(
        targetLongestRunMinutes(
          distance: GoalDistance.tenKilometers,
          easyPaceSecondsPerKm: b.inputs.easyPaceSecondsPerKm,
          easyRunCount: b.inputs.easyRunCount,
        ),
        60,
      );
    });
  });

  group('Läufe ersetzen den Stand (PAR-192)', () {
    test('Mittel der Laufwochen ersetzt die Angabe und das Nein', () {
      // Wochen ab Mo 9.11.: 60 min, 2.11.: 80 min, 26.10.: 100 min -> Mittel 80.
      final goal = _goal(c30: ContinuousRun30.no, stated: 30 * 60);
      final b = _build([
        _run(1, 1, 360, minutes: 60), // Di 10.11.
        _run(2, 3, 360, minutes: 80), // So 8.11.
        _run(3, 10, 360, minutes: 100), // So 1.11.
      ], goal: goal);
      expect(b.goal.currentWeeklySeconds, 80 * 60);
      expect(b.inputs.startWeeklyMinutes, 80);
      expect(b.inputs.walkRunStart, isNull);
      expect(goal.currentWeeklySeconds, 30 * 60); // Original unverändert
    });

    test('ohne Läufe im Fenster gilt die Angabe', () {
      final goal = _goal(c30: ContinuousRun30.no, stated: 100 * 60);
      final b = _build([_run(1, 50, 360)], goal: goal);
      expect(b.goal.currentWeeklySeconds, 100 * 60);
      expect(b.inputs.startWeeklyMinutes, 100);
      final c = _build(const [], goal: _goal(c30: ContinuousRun30.no));
      expect(c.inputs.walkRunStart, const WalkRunPosition(0));
    });

    test('der Plan rechnet mit dem Stand aus Läufen', () {
      final goal = _goal(c30: ContinuousRun30.no);
      final b = _build([
        _run(1, 1, 360, minutes: 90),
        _run(2, 3, 360, minutes: 90),
      ], goal: goal);
      final plan = generatePlan(b.goal, b.inputs, const [], _today);
      final noRuns = _build(const [], goal: goal);
      final plan0 = generatePlan(noRuns.goal, noRuns.inputs, const [], _today);
      expect(plan.units.first.kind, isNot(PlanUnitKind.walkRun));
      expect(plan0.units.first.kind, PlanUnitKind.walkRun);
    });
  });

  group('Referenz mit Datum (ADR-0010 Punkt 2)', () {
    test('Datum statt Alter, JSON-Rundreise', () {
      final b = _build(const [], reference: _ref(DateTime.utc(2026, 11, 1)));
      final json = b.inputs.toJson();
      final intensity = json['intensity']! as Map<String, Object?>;
      expect(intensity['referenceDate'], '2026-11-01');
      expect(intensity.containsKey('referenceAgeDays'), isFalse);
      final text = jsonEncode(json);
      final back = PlanInputs.fromJson(
        jsonDecode(text) as Map<String, Object?>,
      );
      expect(jsonEncode(back.toJson()), text);
      expect(back.intensity!.referenceDate, DateTime.utc(2026, 11, 1));
    });

    test('ungültiges Datum wird abgelehnt', () {
      final j = IntensityInputs(referenceDate: DateTime.utc(2026, 1, 2))
          .toJson();
      for (final bad in ['2026-02-30', 'x', 5]) {
        expect(
          () => IntensityInputs.fromJson({...j, 'referenceDate': bad}),
          throwsFormatException,
        );
      }
    });

    test('Alter wächst mit heute', () {
      final b = _build(const [], reference: _ref(DateTime.utc(2026, 11, 1)));
      expect(b.inputs.intensity!.withAgeAt(_today).referenceAgeDays, 10);
      expect(
        b.inputs.intensity!
            .withAgeAt(DateTime.utc(2026, 12, 11))
            .referenceAgeDays,
        40,
      );
    });

    test('Neuberechnung später altert die Referenz (Bandbreite, Verfall)', () {
      final goal = _goal();
      final b = _build(
        const [],
        goal: goal,
        reference: _ref(DateTime.utc(2026, 11, 1)),
      );
      String paces(DateTime today) {
        final i = b.inputs.intensity!.withAgeAt(today);
        final t = segmentTarget(
          unitKind: PlanUnitKind.tempo,
          segment: PlanSegmentKind.tempo,
          inputs: i,
        )!.intensity;
        return '${t.paceFastSecondsPerKm}-${t.paceSlowSecondsPerKm}-'
            '${t.basisCode}';
      }

      final young = paces(_today); // 10 Tage: Bandbreite 3 %
      final mid = paces(DateTime.utc(2026, 12, 11)); // 40 Tage: 6 %
      final gone = paces(DateTime.utc(2027, 6, 1)); // > 26 Wochen
      expect(young, contains('reference'));
      expect(mid, contains('reference'));
      expect(young, isNot(mid));
      expect(gone, isNot(contains('reference')));
    });

    test('generatePlan rechnet das Alter aus heute', () {
      final goal = _goal();
      final b = _build(
        const [],
        goal: goal,
        reference: _ref(DateTime.utc(2026, 11, 1)),
      );
      String hardPace(DateTime today) {
        final plan = generatePlan(goal, b.inputs, const [], today);
        final u = plan.units.firstWhere(
          (u) =>
              u.kind == PlanUnitKind.intervals || u.kind == PlanUnitKind.tempo,
        );
        final s = u.segments.firstWhere(
          (s) =>
              s.kind == PlanSegmentKind.interval ||
              s.kind == PlanSegmentKind.tempo,
        );
        return '${s.intensity!.paceFastSecondsPerKm}-'
            '${s.intensity!.paceSlowSecondsPerKm}';
      }

      // Alter 10 Tage (3 %) gegen 40 Tage (6 %): gleiches schnelles Ende,
      // breiteres langsames.
      final a = hardPace(_today).split('-');
      final c = hardPace(DateTime.utc(2026, 12, 11)).split('-');
      expect(a[0], c[0]);
      expect(double.parse(c[1]), greaterThan(double.parse(a[1])));
    });

    test('Pause seit der Referenz (PAR-101)', () {
      final b = _build(
        [_run(1, 5, 360), _run(2, 30, 360)],
        reference: _ref(DateTime.utc(2026, 9, 1)), // 71 Tage her
      );
      // Lücken: 1.9.->12.10. (41 Tage), 12.10.->6.11. (25), 6.11.->11.11. (5)
      expect(b.inputs.intensity!.longestPauseSinceReferenceDays, 41);
    });

    test('Profil und VO₂max gehen in die Eingaben', () {
      final b = buildPlanInputs(
        goal: _goal(),
        today: _today,
        heartRate: const HeartRateBasis(
          maxBpm: 185,
          restingBpm: 50,
          maxIsEstimated: true,
        ),
        vo2max: 48,
        vo2maxGrade: Vo2maxGrade.good,
      );
      final i = b.inputs.intensity!;
      expect(i.heartRate!.maxIsEstimated, isTrue);
      expect(i.vo2max, 48);
      expect(i.vo2maxGrade, Vo2maxGrade.good);
      expect(i.referenceDate, isNull);
      expect(
        buildPlanInputs(goal: _goal(), today: _today).inputs.intensity,
        isNull,
      );
    });
  });

  group('WP22: Zuordnung, Auffrischen, VO2max-Güte', () {
    PlanUnit unit(PlanUnitKind k, int? runId) => PlanUnit(
      day: _today,
      kind: k,
      phase: PlanPhase.build,
      weekIndex: 0,
      minutes: 30,
      segments: const [],
      runId: runId,
    );

    test('plannedRunIds: locker und lang = locker, alles andere = andere', () {
      final r = plannedRunIds([
        unit(PlanUnitKind.easy, 1),
        unit(PlanUnitKind.long, 2),
        unit(PlanUnitKind.intervals, 3),
        unit(PlanUnitKind.tempo, 4),
        unit(PlanUnitKind.progressive, 5),
        unit(PlanUnitKind.walkRun, 6),
        unit(PlanUnitKind.easy, null),
      ]);
      expect(r.easy, {1, 2});
      expect(r.other, {3, 4, 5, 6});
    });

    test('refreshMeasuredInputs: Zählung bleibt, Gemessenes ist neu', () {
      final stored = PlanInputs(
        anchor: DateTime.utc(2026, 10, 5),
        startWeeklyMinutes: 77,
        today: DateTime.utc(2026, 10, 7),
        walkRunWeeks: 3,
        walkRunStart: const WalkRunPosition(1, 2),
        walkRunFrom: DateTime.utc(2026, 10, 7),
        lastWeekMinutes: 50,
        achievedShare: 0.5,
        easyPaceSecondsPerKm: 400,
        easyRunCount: 5,
      );
      final measured = PlanInputs(
        anchor: DateTime.utc(2026, 11, 9),
        startWeeklyMinutes: 90,
        today: _today,
        easyRunCount: 2,
        intensity: IntensityInputs(vo2max: 44),
      );
      final r = refreshMeasuredInputs(stored, measured);
      expect(r.anchor, stored.anchor);
      expect(r.startWeeklyMinutes, 77);
      expect(r.walkRunWeeks, 3);
      expect(r.walkRunStart, const WalkRunPosition(1, 2));
      expect(r.walkRunFrom, stored.walkRunFrom);
      expect(r.lastWeekMinutes, 50);
      expect(r.achievedShare, 0.5);
      expect(r.today, _today);
      expect(r.easyPaceSecondsPerKm, isNull, reason: 'Tempo neu bestimmt');
      expect(r.easyRunCount, 2);
      expect(r.intensity?.vo2max, 44);
    });

    ComputedValue v(ValueQuality q, {double? value = 45}) => ComputedValue(
      key: 'k',
      value: value,
      unit: 'ml/kg/min',
      computedAt: _today,
      measurementCount: 3,
      sources: const ['test'],
      method: 'm',
      methodVersion: 1,
      parameterVersion: 1,
      quality: q,
    );

    test('vo2maxGradeFor nach PAR-081', () {
      Vo2maxGrade? g(
        ValueQuality lt,
        ValueQuality run, {
        int ago = 10,
        double? value = 45,
      }) => vo2maxGradeFor(
        longTerm: v(lt, value: value),
        lastRun: v(run),
        lastRunDay: _today.subtract(Duration(days: ago)),
        today: _today,
      );
      expect(g(ValueQuality.good, ValueQuality.sufficient), Vo2maxGrade.good);
      expect(
        g(ValueQuality.sufficient, ValueQuality.good),
        Vo2maxGrade.sufficient,
      );
      expect(g(ValueQuality.provisional, ValueQuality.good), isNull);
      expect(g(ValueQuality.good, ValueQuality.provisional), isNull);
      expect(g(ValueQuality.good, ValueQuality.undeterminable), isNull);
      expect(g(ValueQuality.good, ValueQuality.good, value: null), isNull);
      expect(
        g(ValueQuality.good, ValueQuality.good, ago: 42),
        Vo2maxGrade.good,
      );
      expect(g(ValueQuality.good, ValueQuality.good, ago: 43), isNull);
      expect(
        vo2maxGradeFor(
          longTerm: v(ValueQuality.good),
          lastRun: null,
          lastRunDay: null,
          today: _today,
        ),
        isNull,
      );
    });
  });
}
