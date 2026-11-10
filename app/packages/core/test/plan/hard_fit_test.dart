import 'package:core/core.dart';
import 'package:test/test.dart';

final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch

TrainingGoal _goal({
  GoalType type = GoalType.time,
  bool hard = true,
  int cap = 240,
  int maxMin = 120,
  Set<int> days = const {2, 4, 6},
  GoalDistance distance = GoalDistance.fiveKilometers,
}) => TrainingGoal(
  type: type,
  distance: distance,
  targetSeconds: type == GoalType.time ? 1800 : null,
  targetDate: DateTime.utc(2027, 6, 1),
  runDays: days,
  maxSessionSeconds: maxMin * 60.0,
  weeklyCapSeconds: cap * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: hard,
  canRun30: ContinuousRun30.yes,
);

PlanInputs _inputs() => PlanInputs(
  anchor: DateTime.utc(2026, 11, 9),
  startWeeklyMinutes: 60,
  today: _d0,
);

int _maxWeek(GeneratedPlan p) =>
    p.weeks.map((w) => w.minutes ?? 0).reduce((a, b) => a > b ? a : b);

void main() {
  group('Zeitziel mit harter Einheit (T1)', () {
    test('Schalter an: Plan steigt über die Zielspitze bis zur Passform, '
        'harte Einheit erscheint, nie über dem Regler', () {
      final g = _goal();
      final s = planCourseSetup(g, _inputs());
      expect(s.targetPeakMinutes, 88);
      expect(s.hardFit, HardFitStatus.raised);
      expect(s.hardFitMinutes, 120);
      expect(s.peakMinutes, 120);
      final p = generatePlan(g, _inputs(), const [], _d0);
      expect(_maxWeek(p), 120);
      expect(_maxWeek(p), lessThanOrEqualTo(s.capMinutes));
      expect(p.units.where((u) => u.isHard), isNotEmpty);
      for (final u in p.units.where((u) => u.isHard)) {
        // Die harte Einheit liegt in einer Woche der Spitze (>= Passform).
        final w = p.weeks.firstWhere((w) => w.index == u.weekIndex);
        expect(w.minutes, greaterThanOrEqualTo(120));
      }
      expect(p.hardFit, HardFitStatus.raised);
    });

    test('Schalter aus: der Plan hält bei der Zielspitze', () {
      final g = _goal(hard: false);
      final s = planCourseSetup(g, _inputs());
      expect(s.hardFit, HardFitStatus.notApplicable);
      expect(s.peakMinutes, 88);
      final p = generatePlan(g, _inputs(), const [], _d0);
      expect(_maxWeek(p), 88);
      expect(p.units.where((u) => u.isHard), isEmpty);
    });

    test('Regler unter der Passform: Zielspitze, keine harte Einheit, Grund '
        'gemeldet, nie über dem Regler', () {
      final g = _goal(cap: 100);
      final s = planCourseSetup(g, _inputs());
      expect(s.hardFit, HardFitStatus.regulatorBelowFit);
      expect(s.hardFitMinutes, 120);
      expect(s.peakMinutes, 88);
      final p = generatePlan(g, _inputs(), const [], _d0);
      expect(p.hardFit, HardFitStatus.regulatorBelowFit);
      expect(_maxWeek(p), 88);
      expect(p.units.where((u) => u.isHard), isEmpty);
      expect(p.hardOmissions.values, contains(HardOmission.weekTooShort));
    });

    test('Passt nie (zwei Lauftage, maximale Zeit zu kurz): Zielspitze, '
        'Grund gemeldet', () {
      for (final g in [
        _goal(days: const {2, 5}),
        _goal(maxMin: 25),
      ]) {
        final s = planCourseSetup(g, _inputs());
        expect(s.hardFit, HardFitStatus.neverFits);
        expect(s.hardFitMinutes, isNull);
        expect(s.peakMinutes, s.targetPeakMinutes);
        final p = generatePlan(g, _inputs(), const [], _d0);
        expect(p.hardFit, HardFitStatus.neverFits);
        expect(p.units.where((u) => u.isHard), isEmpty);
      }
    });

    test('NB4: Passform am tatsächlichen Niveau, nicht nur an der kleinsten '
        'Wochenzeit (Halbmarathon, max. 40 min)', () {
      // Ab 180 min gilt die lange Form (48 min), sie scheitert an 40 min; die
      // kleinste Passform (112) liegt unter der Spitze (250), das Niveau
      // 250 trägt die harte Einheit aber nicht.
      for (final cap in [400, 200]) {
        final g = _goal(
          distance: GoalDistance.halfMarathon,
          cap: cap,
          maxMin: 40,
        );
        final s = planCourseSetup(g, _inputs());
        expect(s.targetPeakMinutes, 250);
        // Nicht "nie": in einem Teil der Spitzenwochen erscheint sie (Soll 1).
        expect(s.hardFit, HardFitStatus.partialAtPeak);
        expect(s.hardFitMinutes, isNotNull);
        final p = generatePlan(g, _inputs(), const [], _d0);
        final a = assessGoal(
          goal: g,
          inputs: _inputs(),
          today: _d0,
          basis: const TimeGoalBasis(currentSeconds: 9000, runsInWindow: 5),
        );
        expect(p.hardFit, s.hardFit);
        expect(a.hardFit, s.hardFit);
        // Der Status stimmt mit dem Plan überein: auf dem Niveau der Spitze
        // fehlt die harte Einheit in mindestens einer Woche.
        final level = s.course(today: _d0).levelMinutes;
        final peakWeeks = p.weeks.where((w) => (w.minutes ?? 0) >= level);
        bool hasHard(PlanWeek w) =>
            p.units.any((u) => u.weekIndex == w.index && u.isHard);
        expect(peakWeeks.any((w) => !hasHard(w)), isTrue);
        // Die Form wechselt nur nach einer geplanten harten Einheit; ob in den
        // Spitzenwochen eine erscheint, hängt davon ab (Regler 400: ja).
        if (cap == 400) expect(peakWeeks.any(hasHard), isTrue);
      }
      // Ohne die zu kurze maximale Zeit passt sie am Niveau.
      final ok = planCourseSetup(
        _goal(distance: GoalDistance.halfMarathon, cap: 400, maxMin: 120),
        _inputs(),
      );
      expect(ok.hardFit, HardFitStatus.atPeak);
    });

    test('Streckenziel bleibt unverändert', () {
      final s = planCourseSetup(_goal(type: GoalType.distance), _inputs());
      expect(s.hardFit, HardFitStatus.notApplicable);
      expect(s.peakMinutes, s.targetPeakMinutes);
      expect(s.peakMinutes, 88);
    });

    test('Machbarkeit und Plan rechnen mit demselben Wert', () {
      for (final g in [
        _goal(),
        _goal(cap: 100),
        _goal(days: const {2, 5}),
      ]) {
        final s = planCourseSetup(g, _inputs());
        final a = assessGoal(
          goal: g,
          inputs: _inputs(),
          today: _d0,
          basis: const TimeGoalBasis(currentSeconds: 2000, runsInWindow: 5),
        );
        final p = generatePlan(g, _inputs(), const [], _d0);
        expect(a.hardFit, s.hardFit);
        expect(p.hardFit, s.hardFit);
        expect(
          s.course(today: _d0).levelMinutes,
          s.peakMinutes!.clamp(_inputs().startWeeklyMinutes, s.capMinutes),
        );
        expect(_maxWeek(p), s.course(today: _d0).levelMinutes);
      }
    });

    test('hardFitWeeklyMinutes ist minimal: eine Minute weniger lässt eine '
        'Form weg', () {
      const p = PlanParameters();
      for (final days in [
        {1, 3, 5},
        {2, 4, 6},
        {1, 2, 4, 6},
        {1, 2, 3, 5, 6},
      ]) {
        for (final maxS in [60, 90, 120, 180]) {
          final t = hardFitWeeklyMinutes(
            runDays: days,
            maxSessionMinutes: maxS,
            upTo: 400,
            parameters: p,
          );
          if (t == null) continue;
          bool all(int m) {
            for (var o = 0; o < 3; o++) {
              final w = planWeekUnits(
                week: PlanWeek(
                  index: 0,
                  start: DateTime.utc(2001, 1, 1),
                  minutes: m,
                  phase: PlanPhase.build,
                  kind: WeekKind.holding,
                ),
                runDays: days,
                maxSessionMinutes: maxS,
                hardEnabled: true,
                continuous30: true,
                hardOrdinal: o,
                parameters: p,
              );
              if (w.hardOmission != null) return false;
            }
            return true;
          }

          expect(all(t), isTrue, reason: '$days $maxS');
          expect(all(t - 1), isFalse, reason: '$days $maxS');
        }
      }
      expect(
        hardFitWeeklyMinutes(
          runDays: {2, 4},
          maxSessionMinutes: 120,
          upTo: 1000,
        ),
        isNull,
      );
    });
  });
}
