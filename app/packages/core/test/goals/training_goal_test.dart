import 'package:core/core.dart';
import 'package:test/test.dart';

final today = DateTime(2026, 11, 10, 15);

TrainingGoal goal({
  GoalType type = GoalType.time,
  GoalDistance? distance = GoalDistance.tenKilometers,
  double? targetSeconds = 3300,
  DateTime? targetDate,
  Set<int> runDays = const {2, 4, 6},
  double maxSession = 5400,
  double weeklyCap = 14400,
}) => TrainingGoal(
  type: type,
  distance: distance,
  targetSeconds: targetSeconds,
  targetDate: targetDate,
  runDays: runDays,
  maxSessionSeconds: maxSession,
  weeklyCapSeconds: weeklyCap,
  createdAt: today,
);

TrainingGoal open({
  Set<int> runDays = const {1, 4},
  double maxSession = 3600,
  double weeklyCap = 10800,
  GoalDistance? distance,
  double? targetSeconds,
  DateTime? targetDate,
}) => goal(
  type: GoalType.open,
  distance: distance,
  targetSeconds: targetSeconds,
  targetDate: targetDate,
  runDays: runDays,
  maxSession: maxSession,
  weeklyCap: weeklyCap,
);

void main() {
  group('gültige Ziele (FR-0135, FR-0137)', () {
    test('Zeitziel mit Datum, Streckenziel ohne Zeit, offenes Ziel', () {
      expect(goal(targetDate: DateTime(2027, 3, 1)).validate(today), isNull);
      expect(
        goal(type: GoalType.distance, targetSeconds: null).validate(today),
        isNull,
      );
      expect(open().validate(today), isNull);
    });

    test('alle drei Strecken bis Halbmarathon', () {
      for (final d in GoalDistance.values) {
        expect(goal(distance: d).validate(today), isNull, reason: '$d');
      }
      expect(GoalDistance.fiveKilometers.meters, 5000);
      expect(GoalDistance.tenKilometers.meters, 10000);
      expect(GoalDistance.halfMarathon.meters, 21097.5);
    });

    test('Datum heute ist gültig, ohne Datum ebenso', () {
      expect(goal(targetDate: DateTime(2026, 11, 10)).validate(today), isNull);
      expect(
        goal(targetDate: DateTime(2026, 11, 10, 0, 1))
            .validate(DateTime(2026, 11, 10, 23)),
        isNull,
      );
    });

    test('Lauftage 1 bis 7 (PAR-197)', () {
      expect(goal(runDays: const {3}).validate(today), isNull);
      expect(
        goal(runDays: const {1, 2, 3, 4, 5, 6, 7}).validate(today),
        isNull,
      );
    });
  });

  group('Negativfälle', () {
    final cases = <String, (TrainingGoal, GoalProblem)>{
      'Streckenziel ohne Strecke': (
        goal(type: GoalType.distance, distance: null, targetSeconds: null),
        GoalProblem.distanceMissing,
      ),
      'Zeitziel ohne Strecke': (
        goal(distance: null),
        GoalProblem.distanceMissing,
      ),
      'offenes Ziel mit Strecke': (
        open(distance: GoalDistance.fiveKilometers),
        GoalProblem.distanceNotAllowed,
      ),
      'Zeitziel ohne Zeit': (
        goal(targetSeconds: null),
        GoalProblem.targetTimeMissing,
      ),
      'Zeit 0': (goal(targetSeconds: 0), GoalProblem.targetTimeInvalid),
      'Zeit negativ': (goal(targetSeconds: -5), GoalProblem.targetTimeInvalid),
      'Zeit NaN': (
        goal(targetSeconds: double.nan),
        GoalProblem.targetTimeInvalid,
      ),
      'Zeit unendlich': (
        goal(targetSeconds: double.infinity),
        GoalProblem.targetTimeInvalid,
      ),
      'Streckenziel mit Zeit': (
        goal(type: GoalType.distance),
        GoalProblem.targetTimeNotAllowed,
      ),
      'offenes Ziel mit Zeit': (
        open(targetSeconds: 1500),
        GoalProblem.targetTimeNotAllowed,
      ),
      'offenes Ziel mit Datum': (
        open(targetDate: DateTime(2027)),
        GoalProblem.targetDateNotAllowed,
      ),
      'Datum gestern': (
        goal(targetDate: DateTime(2026, 11, 9, 23, 59)),
        GoalProblem.targetDateInPast,
      ),
      'keine Lauftage': (goal(runDays: const {}), GoalProblem.runDaysEmpty),
      'Tag 0': (goal(runDays: const {0, 2}), GoalProblem.runDayInvalid),
      'Tag 8': (goal(runDays: const {8}), GoalProblem.runDayInvalid),
      'max. Zeit 0': (goal(maxSession: 0), GoalProblem.maxSessionInvalid),
      'max. Zeit NaN': (
        goal(maxSession: double.nan),
        GoalProblem.maxSessionInvalid,
      ),
      'max. Zeit unendlich': (
        goal(maxSession: double.infinity),
        GoalProblem.maxSessionInvalid,
      ),
      'Regler 0': (goal(weeklyCap: 0), GoalProblem.weeklyCapInvalid),
      'Regler negativ': (goal(weeklyCap: -1), GoalProblem.weeklyCapInvalid),
      'Regler NaN': (goal(weeklyCap: double.nan), GoalProblem.weeklyCapInvalid),
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(e.value.$1.validate(today), e.value.$2));
    }

    test('Parameter: Obergrenze der Lauftage kommt aus GoalParameters', () {
      const p = GoalParameters(maxRunDays: 5);
      expect(goal(runDays: const {1, 2, 3, 4, 5}).validate(today, p), isNull);
      expect(
        goal(runDays: const {1, 2, 3, 4, 5, 6}).validate(today, p),
        GoalProblem.runDayInvalid,
      );
    });
  });

  test('reine Funktion: gleiche Eingabe, gleiches Ergebnis, kein Ablauf', () {
    final g = goal(targetDate: DateTime(2026, 12, 1));
    expect(g.validate(today), g.validate(today));
    // Dasselbe Ziel ist später ungültig, wenn "heute" übergeben später liegt.
    expect(g.validate(DateTime(2026, 12, 2)), GoalProblem.targetDateInPast);
  });
}
