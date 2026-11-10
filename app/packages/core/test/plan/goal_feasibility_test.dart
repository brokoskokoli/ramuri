import 'package:core/core.dart';
import 'package:test/test.dart';

final d0 = DateTime.utc(2026, 11, 11); // Mittwoch
final anchor = DateTime.utc(2026, 11, 9);

TrainingGoal goal({
  GoalType type = GoalType.distance,
  GoalDistance distance = GoalDistance.tenKilometers,
  Set<int> days = const {2, 4, 6},
  int maxMin = 120,
  int capMin = 240,
  ContinuousRun30 c30 = ContinuousRun30.yes,
  double? stated,
  DateTime? date,
  double target = 3000,
}) => TrainingGoal(
  type: type,
  distance: type == GoalType.open ? null : distance,
  targetSeconds: type == GoalType.time ? target : null,
  targetDate: date,
  runDays: days,
  maxSessionSeconds: maxMin * 60.0,
  weeklyCapSeconds: capMin * 60.0,
  createdAt: d0,
  hardSessionEnabled: false,
  currentWeeklySeconds: stated,
  canRun30: c30,
);

PlanInputs inputs({int start = 90, int walk = 0}) => PlanInputs(
  anchor: anchor,
  startWeeklyMinutes: start,
  today: d0,
  walkRunWeeks: walk,
);

GoalAssessment? assess(
  TrainingGoal g, {
  PlanInputs? i,
  TimeGoalBasis basis = const TimeGoalBasis(),
}) => assessGoal(goal: g, inputs: i ?? inputs(), today: d0, basis: basis);

DateTime inWeeks(int w) => d0.add(Duration(days: 7 * w));

void main() {
  group('Streckenziel (PAR-206)', () {
    // 10 km ohne Tempo: 65 min längster Lauf, 3 Lauftage: Spitze 163 min.
    test('Spitze rechtzeitig: passt', () {
      final a = assess(goal(date: inWeeks(60)))!;
      expect(a.feasibility, GoalFeasibility.fits);
      expect(a.reason, FeasibilityReason.peakReached);
      expect(a.fitsFrom, isNull);
      expect(a.regulatorTooLow, isFalse);
    });

    test('zu knapp: knapp mit Datum, an dem es passt', () {
      final a = assess(goal(date: inWeeks(10)))!;
      expect(a.feasibility, GoalFeasibility.tight);
      expect(a.reason, FeasibilityReason.peakTooLate);
      final from = a.fitsFrom!;
      expect(from.isAfter(inWeeks(10)), isTrue);
      // das Datum passt wirklich, die Woche davor nicht
      expect(assess(goal(date: from))!.feasibility, GoalFeasibility.fits);
      expect(
        assess(goal(date: from.subtract(const Duration(days: 7))))!.feasibility,
        GoalFeasibility.tight,
      );
      // gleicher Wochentag wie das Ziel
      expect(from.weekday, inWeeks(10).weekday);
    });

    test('ein späteres Datum ist nie schlechter', () {
      var seenFit = false;
      for (var w = 1; w <= 90; w++) {
        final f = assess(goal(date: inWeeks(w)))!.feasibility;
        if (f == GoalFeasibility.fits) seenFit = true;
        if (seenFit) expect(f, GoalFeasibility.fits, reason: 'Woche $w');
      }
      expect(seenFit, isTrue);
    });

    test('Halbmarathon braucht länger als 5 km', () {
      final a5 = assess(
        goal(distance: GoalDistance.fiveKilometers, date: inWeeks(12)),
      )!;
      final a21 = assess(
        goal(distance: GoalDistance.halfMarathon, date: inWeeks(12)),
      )!;
      expect(a5.feasibility, GoalFeasibility.fits);
      expect(a21.feasibility, GoalFeasibility.tight);
    });

    test('Regler unter der Zielspitze: ausgewiesen, kein Datum', () {
      final a = assess(goal(date: inWeeks(60), capMin: 120))!;
      expect(a.feasibility, GoalFeasibility.tight);
      expect(a.reason, FeasibilityReason.peakAboveRegulator);
      expect(a.regulatorTooLow, isTrue);
      expect(a.fitsFrom, isNull);
    });

    test('Regler genau auf der Zielspitze: kein Fehlalarm', () {
      final a = assess(goal(date: inWeeks(60), capMin: 163))!;
      expect(a.regulatorTooLow, isFalse);
      expect(a.feasibility, GoalFeasibility.fits);
      expect(
        assess(goal(date: inWeeks(60), capMin: 162))!.regulatorTooLow,
        isTrue,
      );
    });

    test('Stand schon auf der Spitze: passt auch kurz vor dem Termin', () {
      final a = assess(goal(date: inWeeks(1)), i: inputs(start: 170))!;
      expect(a.feasibility, GoalFeasibility.fits);
      // Termin in der laufenden Woche: kein Aufbau mehr, nur Reduktion
      final sameWeek = d0.add(const Duration(days: 2));
      expect(
        assess(goal(date: sameWeek), i: inputs(start: 170))!.feasibility,
        GoalFeasibility.fits,
      );
      expect(
        assess(goal(date: sameWeek), i: inputs(start: 160))!.feasibility,
        GoalFeasibility.tight,
      );
    });

    test('maximale Zeit je Einheit unter dem längsten Lauf: Hinweis', () {
      expect(
        assess(goal(date: inWeeks(60), maxMin: 60))!.sessionLimitsLongestRun,
        isTrue,
      );
      expect(
        assess(goal(date: inWeeks(60), maxMin: 65))!.sessionLimitsLongestRun,
        isFalse,
      );
    });

    test('Ziel ohne Datum und offenes Ziel: keine Einschätzung', () {
      expect(assess(goal()), isNull);
      expect(assess(goal(type: GoalType.open)), isNull);
    });
  });

  group('Zeitziel (PAR-206)', () {
    // Zielzeit 3000 s; Verbesserung = (cur - 3000)/cur in Prozent.
    // Bei 10 Wochen: 0,25 % je Woche = 2,5 % gesamt.
    TimeGoalBasis basis(double cur, [int runs = 3]) =>
        TimeGoalBasis(currentSeconds: cur, runsInWindow: runs);
    GoalAssessment run(double cur, {int weeks = 10, int runs = 3}) => assess(
      goal(type: GoalType.time, date: inWeeks(weeks)),
      basis: basis(cur, runs),
    )!;

    test('Grenzen 0,25 und 0,5 sind einschließlich', () {
      // cur = 3000/(1-0.025) => 2,5 % gesamt => 0,25 %/Woche
      final fits = run(3000 / 0.975);
      expect(fits.requiredPercentPerWeek, closeTo(0.25, 1e-9));
      expect(fits.feasibility, GoalFeasibility.fits);
      final tight = run(3000 / 0.95); // 5 % => 0,5 %/Woche
      expect(tight.feasibility, GoalFeasibility.tight);
      expect(tight.reason, FeasibilityReason.improvementMedium);
      expect(run(3000 / 0.9499).feasibility, GoalFeasibility.later);
      expect(run(3000 / 0.9749).feasibility, GoalFeasibility.tight);
    });

    test('ab etwa Datum bei knapp und eher später', () {
      final a = run(3000 / 0.95);
      // 5 % bei 0,25 %/Woche = 20 Wochen
      expect(a.fitsFrom, inWeeks(20));
      final b = run(3000 / 0.9, weeks: 5);
      expect(b.feasibility, GoalFeasibility.later);
      expect(b.fitsFrom, inWeeks(40));
      expect(run(3000 / 0.975).fitsFrom, isNull);
    });

    test('ein späteres Datum ist nie schlechter', () {
      var best = -1;
      for (var w = 1; w <= 80; w++) {
        final f = run(3200, weeks: w).feasibility.index;
        // fits(0) < tight(1) < later(2) im Enum? Rangfolge ausdrücklich:
        final rank = {
          GoalFeasibility.fits: 0,
          GoalFeasibility.tight: 1,
          GoalFeasibility.later: 2,
        }[GoalFeasibility.values[f]]!;
        if (best >= 0) expect(rank <= best, isTrue, reason: 'Woche $w');
        best = rank;
      }
    });

    test('schon schneller als das Ziel: passt', () {
      final a = run(2900);
      expect(a.feasibility, GoalFeasibility.fits);
      expect(a.requiredPercentPerWeek, 0);
    });

    test('Datum heute oder vorbei bei nötiger Verbesserung: eher später', () {
      final a = assess(
        goal(type: GoalType.time, date: d0),
        basis: basis(3300),
      )!;
      expect(a.feasibility, GoalFeasibility.later);
      expect(a.requiredPercentPerWeek, isNull);
      expect(a.fitsFrom, isNotNull);
    });

    test('keine Referenz oder zu wenig Läufe: noch nicht genug Daten', () {
      final none = assess(goal(type: GoalType.time, date: inWeeks(10)))!;
      expect(none.feasibility, GoalFeasibility.notEnoughData);
      expect(none.reason, FeasibilityReason.noReference);
      final few = run(3300, runs: 2);
      expect(few.feasibility, GoalFeasibility.notEnoughData);
      expect(few.reason, FeasibilityReason.tooFewRuns);
      expect(
        run(3300, runs: 3).feasibility,
        isNot(GoalFeasibility.notEnoughData),
      );
    });

    test('Zielspitze über Regler wird auch beim Zeitziel ausgewiesen', () {
      final a = assess(
        goal(type: GoalType.time, date: inWeeks(10), capMin: 100),
        basis: basis(3000 / 0.975),
      )!;
      expect(a.regulatorTooLow, isTrue);
      expect(a.feasibility, GoalFeasibility.fits);
    });
  });

  group('Anschluss an predictGoal', () {
    test('knapp und eher später begrenzen die Zielprognose', () {
      const good = DistancePrediction(
        distance: PredictionDistance.tenKilometers,
        seconds: 3000,
        level: PredictionLevel.good,
        reason: PredictionReason.none,
        limits: [],
      );
      final tight = assess(goal(date: inWeeks(10)))!;
      expect(
        predictGoal(general: good, feasibility: tight.feasibility).level,
        PredictionLevel.provisional,
      );
      final fits = assess(goal(date: inWeeks(60)))!;
      expect(
        predictGoal(general: good, feasibility: fits.feasibility).level,
        PredictionLevel.good,
      );
    });
  });

  group('Testhinweis nach Planlage (PAR-117)', () {
    test('3 Lauftage und 30 min am Stück', () {
      expect(
        planAllowsFiveKilometerTest(
          goal: goal(date: inWeeks(20)),
          inputs: inputs(),
          today: d0,
        ),
        isTrue,
      );
    });
    test('2 Lauftage: nein, 3: ja', () {
      bool a(Set<int> days) => planAllowsFiveKilometerTest(
        goal: goal(days: days, date: inWeeks(20)),
        inputs: inputs(),
        today: d0,
      );
      expect(a({2, 4}), isFalse);
      expect(a({2, 4, 6}), isTrue);
      expect(a({1, 2, 4, 6}), isTrue);
    });
    test(
      '30 min am Stück: nein, unbekannt ohne Stand, Stand, nach Geh-Lauf',
      () {
        bool a(
          ContinuousRun30 c, {
          double? stated,
          int walk = 0,
          DateTime? today,
        }) => planAllowsFiveKilometerTest(
          goal: goal(c30: c, stated: stated, date: inWeeks(40)),
          inputs: inputs(walk: walk),
          today: today ?? d0,
        );
        expect(a(ContinuousRun30.no), isFalse);
        expect(a(ContinuousRun30.unknown), isFalse);
        // 3 Tage: längster Lauf 40 % der Wochenzeit; 75 min => 30 min
        expect(a(ContinuousRun30.unknown, stated: 75 * 60), isTrue);
        expect(a(ContinuousRun30.unknown, stated: 74 * 60), isFalse);
        // Geh-Lauf-Abfolge 4 Wochen ab Anker 9.11.: erst ab Woche 4 ja
        expect(a(ContinuousRun30.no, walk: 4, today: inWeeks(3)), isFalse);
        expect(a(ContinuousRun30.no, walk: 4, today: inWeeks(4)), isTrue);
      },
    );
    test('Hinweis: Planlage entscheidet, ohne Plan die WP20-Ersatzregel', () {
      final p = predictPerformance(
        now: d0,
        references: const [],
        runs: const [],
      );
      expect(
        p.of(PredictionDistance.fiveKilometers).level,
        PredictionLevel.notDeterminable,
      );
      // Plan sagt ja, keine Läufe: Hinweis
      expect(
        showFiveKilometerTestHint(
          prediction: p,
          now: d0,
          runs: const [],
          planAllowsTest: true,
        ),
        isTrue,
      );
      // Plan sagt nein, auch mit vielen Läufen: kein Hinweis
      final many = [
        for (var i = 0; i < 14; i++)
          PredictionRun(
            id: 'r$i',
            date: d0.subtract(Duration(days: i)),
            distanceMeters: 5000,
            movingSeconds: 1900,
          ),
      ];
      expect(
        showFiveKilometerTestHint(
          prediction: p,
          now: d0,
          runs: many,
          planAllowsTest: false,
        ),
        isFalse,
      );
      // ohne Plan: Ersatzregel
      expect(
        showFiveKilometerTestHint(prediction: p, now: d0, runs: many),
        isTrue,
      );
      expect(
        showFiveKilometerTestHint(prediction: p, now: d0, runs: const []),
        isFalse,
      );
    });
  });
}
