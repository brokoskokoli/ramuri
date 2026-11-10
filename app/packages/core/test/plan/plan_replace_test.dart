import 'package:core/core.dart';
import 'package:test/test.dart';

/// Montag, 9.11.2026.
final DateTime _mon = DateTime.utc(2026, 11, 9);
DateTime _d(int n) => _mon.add(Duration(days: n));

PlanUnit _u(
  int id,
  int day, {
  PlanUnitKind kind = PlanUnitKind.easy,
  int minutes = 30,
  int? runId,
  bool pinned = false,
}) => PlanUnit(
  id: id,
  day: _d(day),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: day ~/ 7,
  minutes: minutes,
  runId: runId,
  pinned: pinned,
  segments: const [],
);

TrainingGoal _goal({int maxSessionMinutes = 120}) => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime(2027, 6, 1),
  runDays: const {1, 3, 5, 6},
  maxSessionSeconds: maxSessionMinutes * 60,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  canRun30: ContinuousRun30.yes,
);

PlanInputs _inputs() => PlanInputs(
  anchor: _mon,
  startWeeklyMinutes: 150,
  today: _mon,
  easyPaceSecondsPerKm: 345.5,
  easyRunCount: 4,
);

PlanReplaceCheck _replace(
  List<PlanUnit> units,
  PlanUnit unit,
  PlanUnitKind kind, {
  int today = 0,
  int maxSessionMinutes = 120,
  List<int> completedIntensive = const [],
}) => checkPlanReplace(
  units: units,
  unit: unit,
  kind: kind,
  goal: _goal(maxSessionMinutes: maxSessionMinutes),
  inputs: _inputs(),
  today: _d(today),
  completedIntensiveDays: [for (final d in completedIntensive) _d(d)],
);

PlanRestDayCheck _rest(
  List<PlanUnit> units,
  int day, {
  int today = 0,
  Set<int> runDays = const {},
}) => checkPlanRestDay(
  units: units,
  day: _d(day),
  today: _d(today),
  weeklyCapSeconds: 240 * 60,
  runDays: runDays,
);

void main() {
  // Woche: Di locker, Do Intervalle, Sa lang.
  final easy = _u(1, 1, minutes: 40);
  final hard = _u(2, 3, kind: PlanUnitKind.intervals, minutes: 45);
  final long = _u(3, 5, kind: PlanUnitKind.long, minutes: 70);
  final week = [easy, hard, long];

  group('checkPlanReplace', () {
    test('Sperren wie der Speicher, dazu gleiche Art', () {
      expect(
        _replace(week, _u(1, 1, runId: 7), PlanUnitKind.tempo).blocked,
        PlanReplaceBlock.unitHasRun,
      );
      expect(
        _replace(week, easy, PlanUnitKind.tempo, today: 2).blocked,
        PlanReplaceBlock.unitPast,
      );
      for (final k in [PlanUnitKind.rest, PlanUnitKind.walkRun]) {
        expect(
          _replace(week, _u(9, 2, kind: k), PlanUnitKind.easy).blocked,
          PlanReplaceBlock.unitNotReplaceable,
          reason: k.name,
        );
      }
      expect(
        _replace(week, easy, PlanUnitKind.walkRun).blocked,
        PlanReplaceBlock.kindNotAllowed,
      );
      final same = _replace(week, easy, PlanUnitKind.easy);
      expect(same.blocked, PlanReplaceBlock.sameKind);
      expect(same.unit, isNull);
    });

    test('harte Form passt nicht in die maximale Zeit je Einheit: gesperrt '
        '(PAR-198), lockere Art passt', () {
      final tooLong = _replace(
        week,
        easy,
        PlanUnitKind.intervals,
        maxSessionMinutes: 15,
      );
      expect(tooLong.blocked, PlanReplaceBlock.exceedsMaxSession);
      expect(tooLong.unit, isNull);
      expect(tooLong.allowed, isFalse);
      // Gleiche Einheit mit genug Zeit: erlaubt (die Sperre kommt nur von
      // der maximalen Zeit).
      expect(_replace(week, easy, PlanUnitKind.intervals).allowed, isTrue);
      expect(
        _replace(week, hard, PlanUnitKind.long, maxSessionMinutes: 15).allowed,
        isTrue,
      );
    });

    test('Ersatz: gleiche Einheit und Tag, pinned, fixed = kind, Dauer aus '
        'den Abschnitten, Zielintensität', () {
      final c = _replace(week, easy, PlanUnitKind.tempo);
      expect(c.allowed, isTrue);
      final u = c.unit!;
      expect(u.id, easy.id);
      expect(u.day, easy.day);
      expect(u.kind, PlanUnitKind.tempo);
      expect(u.pinned, isTrue);
      expect(u.fixed, PlanUnitFixed.kind);
      expect(u.weekIndex, easy.weekIndex);
      expect(u.segments, isNotEmpty);
      expect(u.segments.fold<int>(0, (a, s) => a + s.minutes), u.minutes);
      expect(u.segments.any((s) => s.kind == PlanSegmentKind.tempo), isTrue);
    });

    test('Hinweise: Abstand (PAR-059/060, auch absolvierte Läufe) und zweite '
        'harte Einheit derselben Woche (PAR-198), keine Sperre', () {
      // Tempo am Di: Do (Intervalle) liegt 2 Tage weiter -> kein Konflikt;
      // ein absolvierter intensiver Lauf am Mo schon.
      final c = _replace(
        [...week, _u(4, 10, kind: PlanUnitKind.tempo)],
        easy,
        PlanUnitKind.tempo,
        completedIntensive: [0],
      );
      expect(c.allowed, isTrue);
      expect(c.spacingDays, [_d(0)]);
      // Nur die harte Einheit derselben Woche, nicht die der Folgewoche.
      expect(c.otherHardDays, [_d(3)]);
      expect(c.hasSecondHard, isTrue);

      // Locker am Fr neben Do (Intervalle) und Sa (lang): als Tempo zwei
      // Abstandskonflikte.
      final fri = _u(5, 4);
      final c2 = _replace([...week, fri], fri, PlanUnitKind.tempo);
      expect(c2.spacingDays, [_d(3), _d(5)]);

      // Lockere Art: keine Hinweise.
      final c3 = _replace(week, hard, PlanUnitKind.easy);
      expect(c3.spacingDays, isEmpty);
      expect(c3.otherHardDays, isEmpty);
    });
  });

  group('checkPlanRestDay', () {
    test('Sperren: vergangen, Einheit mit Lauf, schon Ruhetag', () {
      expect(_rest(week, 1, today: 2).blocked, PlanRestDayBlock.dayPast);
      expect(
        _rest([_u(1, 1, runId: 3)], 1).blocked,
        PlanRestDayBlock.unitHasRun,
      );
      expect(
        _rest([_u(1, 1, kind: PlanUnitKind.rest, minutes: 0)], 1).blocked,
        PlanRestDayBlock.alreadyRest,
      );
    });

    test('freier Tag: keine Einheit, nichts entfällt', () {
      final c = _rest(week, 2);
      expect(c.allowed, isTrue);
      expect(c.unit, isNull);
      expect(c.alternatives, isEmpty);
      expect(c.unitDropsWithoutMove, isFalse);
    });

    test('Alternativtage ohne Abstandskonflikt (PAR-059/060), freie Tage '
        'derselben Woche, dem Ruhetag nächster zuerst', () {
      // Ruhetag am Do (Intervalle): Fr und So lägen neben Sa (lang),
      // Di ist belegt. Bleiben Mi (1 Tag weg) und Mo (3 Tage weg).
      final c = _rest(week, 3);
      expect(c.unit?.id, hard.id);
      expect(c.alternatives, [_d(2), _d(0)]);
      expect(c.unitDropsWithoutMove, isFalse);
    });

    test('Lauftage des Ziels zuerst', () {
      // Lauftag Mo (weekday 1) vor dem näheren Mi.
      final c = _rest(week, 3, runDays: {DateTime.monday});
      expect(c.alternatives, [_d(0), _d(2)]);
    });

    test('kein passender Tag: die Einheit entfällt ohne Zieltag', () {
      // Heute So: alle anderen Tage der Woche liegen davor.
      final sun = _u(6, 6);
      final c = _rest([...week, sun], 6, today: 6);
      expect(c.allowed, isTrue);
      expect(c.unit?.id, sun.id);
      expect(c.alternatives, isEmpty);
      expect(c.unitDropsWithoutMove, isTrue);
    });
  });

  group('planRestDayUnit', () {
    test('Ruhetag: rest, 0 min, pinned, fixed = day, Woche und Phase aus '
        'dem Plan', () {
      final goal = _goal();
      final weeks = planCourseSetup(goal, _inputs()).course(today: _mon).weeks;
      final u = planRestDayUnit(
        day: _d(9),
        goal: goal,
        inputs: _inputs(),
        today: _mon,
      );
      expect(u.day, _d(9));
      expect(u.kind, PlanUnitKind.rest);
      expect(u.minutes, 0);
      expect(u.segments, isEmpty);
      expect(u.pinned, isTrue);
      expect(u.fixed, PlanUnitFixed.day);
      expect(u.isRestDay, isTrue);
      final w = weeks.firstWhere((w) => w.start == _d(7));
      expect(u.weekIndex, w.index);
      expect(u.phase, w.phase);
    });

    test('nach dem Verlauf: Woche ab dem Anker, Phase der letzten Woche', () {
      final goal = _goal();
      final weeks = planCourseSetup(goal, _inputs()).course(today: _mon).weeks;
      final after = weeks.last.start.add(const Duration(days: 21));
      final u = planRestDayUnit(
        day: after,
        goal: goal,
        inputs: _inputs(),
        today: _mon,
      );
      expect(u.weekIndex, after.difference(_mon).inDays ~/ 7);
      expect(u.phase, weeks.last.phase);
    });
  });
}
