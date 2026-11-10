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
}) => PlanUnit(
  id: id,
  day: _d(day),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: day ~/ 7,
  minutes: minutes,
  runId: runId,
  segments: const [],
);

PlanMoveCheck _check(
  List<PlanUnit> units,
  PlanUnit unit,
  int day, {
  int today = 0,
  double capMinutes = 240,
  List<int> completedIntensive = const [],
  Set<int> runDays = const {},
}) => checkPlanMove(
  units: units,
  unit: unit,
  newDay: _d(day),
  today: _d(today),
  weeklyCapSeconds: capMinutes * 60,
  completedIntensiveDays: [for (final d in completedIntensive) _d(d)],
  runDays: runDays,
);

void main() {
  // Woche: Di locker, Do Intervalle, Sa lang.
  final easy = _u(1, 1);
  final hard = _u(2, 3, kind: PlanUnitKind.intervals, minutes: 45);
  final long = _u(3, 5, kind: PlanUnitKind.long, minutes: 70);
  final week = [easy, hard, long];

  test('PAR-060: intensive Einheit ohne vollen Tag Abstand ist ein Konflikt '
      'mit Alternativtagen, nicht gesperrt', () {
    final c = _check(week, hard, 4); // Fr neben Sa (lang)
    expect(c.allowed, isTrue);
    expect(c.hasSpacingConflict, isTrue);
    expect(c.spacingDays, [_d(5)]);
    // Frei: Mo(0), Mi(2), So(6). Mi liegt 3 Tage vor Sa, Mo 5 Tage, So
    // daneben. Dem Fr nächster zuerst: Mi (2 Tage), Mo (4 Tage).
    expect(c.alternatives, [_d(2), _d(0)]);
    expect(c.overRegulator, isFalse);
  });

  test('genau ein voller Tag dazwischen ist kein Konflikt (PAR-059)', () {
    final c = _check(week, hard, 2); // Mi, Sa liegt 3 Tage weiter
    expect(c.hasSpacingConflict, isFalse);
    expect(c.alternatives, isEmpty);
    final c2 = _check(
      [easy, long, _u(4, 7, kind: PlanUnitKind.tempo)],
      long,
      9,
    );
    // Lang auf Mi der Folgewoche (Tag 9), Tempo am Mo (Tag 7): 2 Tage.
    expect(c2.hasSpacingConflict, isFalse);
  });

  test('lockere Einheit hat keinen Abstandskonflikt', () {
    final c = _check(week, easy, 4);
    expect(c.hasSpacingConflict, isFalse);
  });

  test('Regler überschritten: Hinweis, nicht gesperrt, Alternative in der '
      'bisherigen Woche', () {
    final next = [_u(5, 8, minutes: 50), _u(6, 10, minutes: 50)];
    final c = _check([...week, ...next], long, 12, capMinutes: 160);
    expect(c.allowed, isTrue);
    expect(c.weekMinutes, 170);
    expect(c.weekCapMinutes, 160);
    expect(c.overRegulator, isTrue);
    // Folgewoche bleibt über dem Regler; in der bisherigen Woche passt Mo, So
    // (beide ohne intensiven Nachbarn); Mi/Fr liegen neben den Intervallen.
    expect(c.alternatives, [_d(6), _d(0)]);
  });

  test('eingefroren, Tag vor heute, gleicher und belegter Tag: gesperrt', () {
    final done = _u(7, 2, runId: 9);
    expect(_check(week, done, 4).blocked, PlanMoveBlock.unitHasRun);
    expect(_check(week, easy, 4, today: 2).blocked, PlanMoveBlock.unitPast);
    expect(_check(week, hard, 0, today: 1).blocked, PlanMoveBlock.dayPast);
    expect(_check(week, hard, 3).blocked, PlanMoveBlock.sameDay);
    expect(_check(week, hard, 5).blocked, PlanMoveBlock.dayTaken);
    expect(_check(week, hard, 6).blocked, isNull);
  });

  test('Alternativen nicht vor heute und nicht auf belegten Tagen', () {
    final c = _check(week, hard, 4, today: 1);
    expect(c.alternatives, [_d(2)]);
  });

  test(
    'hart -> locker (easyForHard) in eine andere Woche: wird kind, '
    'Hinweis im Dialog; in der eigenen Woche bleibt es (Festlegung WP22)',
    () {
      final efh = PlanUnit(
        id: 1,
        day: _d(1),
        kind: PlanUnitKind.easy,
        phase: PlanPhase.build,
        weekIndex: 0,
        minutes: 30,
        segments: const [],
        pinned: true,
        fixed: PlanUnitFixed.easyForHard,
      );
      final units = [efh, hard, long];
      expect(planMovedFixed(efh, _d(2)), PlanUnitFixed.easyForHard);
      expect(planMovedFixed(efh, _d(6)), PlanUnitFixed.easyForHard); // So
      expect(planMovedFixed(efh, _d(7)), PlanUnitFixed.kind); // Mo danach
      expect(planMovedFixed(efh, _d(-1)), PlanUnitFixed.kind); // So davor
      expect(_check(units, efh, 2).endsHardReplacement, isFalse);
      final other = _check(units, efh, 8);
      expect(other.allowed, isTrue);
      expect(other.endsHardReplacement, isTrue);
      // Andere Festlegungen bleiben, auch über die Woche.
      final kindUnit = efh.copyWith(fixed: PlanUnitFixed.kind);
      expect(planMovedFixed(kindUnit, _d(8)), PlanUnitFixed.kind);
      expect(_check([kindUnit], kindUnit, 8).endsHardReplacement, isFalse);
      expect(_check(week, easy, 8).endsHardReplacement, isFalse);
    },
  );

  group('Nachbesserung E', () {
    test('Wochengrenzen beim Regler: Sonntag der Vorwoche und Montag der '
        'Folgewoche zählen nicht zur Woche', () {
      final prevSunday = _u(10, -1, minutes: 120);
      final nextMonday = _u(11, 7, minutes: 120);
      final units = [prevSunday, ...week, nextMonday];
      // Lockere Einheit auf den Sonntag: Woche 30 + 45 + 70 = 145 min.
      final toSunday = _check(units, easy, 6, capMinutes: 200);
      expect(toSunday.weekMinutes, 145);
      expect(toSunday.overRegulator, isFalse);
      // Auf den Montag: ebenso 145 min, der Sonntag davor zählt nicht.
      final toMonday = _check(units, easy, 0, capMinutes: 200);
      expect(toMonday.weekMinutes, 145);
      expect(toMonday.overRegulator, isFalse);
    });

    test('Abstand über die Wochengrenze: Sonntag der Vorwoche und Montag der '
        'Folgewoche (PAR-059)', () {
      final prevSunday = _u(10, -1, kind: PlanUnitKind.tempo, minutes: 40);
      final nextMonday = _u(11, 7, kind: PlanUnitKind.tempo, minutes: 40);
      final units = [prevSunday, ...week, nextMonday];
      expect(_check(units, hard, 0, today: -1).spacingDays, [_d(-1)]);
      expect(_check(units, hard, 6, today: -1).spacingDays, [_d(5), _d(7)]);
    });

    test('absolvierter intensiver Lauf ohne Einheit zählt für den Abstand '
        '(PAR-058)', () {
      // Intervalle auf Mi: ohne Lauf kein Konflikt (Sa liegt 3 Tage weiter).
      expect(_check(week, hard, 2).hasSpacingConflict, isFalse);
      final c = _check(week, hard, 2, completedIntensive: [1]);
      expect(c.spacingDays, [_d(1)]);
      // Auch die Alternativen meiden den Tag daneben: Mo (0) liegt neben Di.
      expect(c.alternatives, isNot(contains(_d(0))));
      // Lockere Einheiten bleiben ohne Konflikt.
      expect(
        _check(week, easy, 2, completedIntensive: [1]).hasSpacingConflict,
        isFalse,
      );
    });

    test('Lauftage des Ziels zuerst, danach dem gewünschten Tag nächster', () {
      // Wie der erste Fall: ohne Lauftage Mi (2) vor Mo (0).
      final c = _check(week, hard, 4, runDays: {DateTime.monday});
      expect(c.alternatives, [_d(0), _d(2)]);
    });
  });
}
