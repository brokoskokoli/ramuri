import 'dart:convert';

import 'package:core/core.dart';
import 'package:test/test.dart';

DateTime _d(int day) => DateTime.utc(2026, 11, day);

PlanUnit _unit(
  int day,
  PlanUnitKind kind,
  int minutes, {
  int week = 0,
  int? runId,
}) => PlanUnit(
  day: _d(day),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: week,
  minutes: minutes,
  runId: runId,
  segments: const [],
);

PlanVersionRecord _rec(
  int id,
  PlanTrigger trigger,
  Map<String, Object?> summary, {
  String? reason,
}) => PlanVersionRecord(
  id: id,
  goalId: 1,
  createdAt: _d(id),
  validFrom: _d(id),
  trigger: trigger,
  reason: reason ?? trigger.name,
  version: const PlanVersion(),
  inputsJson: '{}',
  summaryJson: jsonEncode(summary),
);

void main() {
  group('PAR-204 aus dem Vergleich der Fassungen', () {
    // Eine Woche, 100 min -> 90,9 / 90 / 110 min.
    List<PlanUnit> week(int minutes) => [_unit(10, PlanUnitKind.easy, minutes)];
    bool larger(int a, int b) => summarizeChange(week(a), week(b)).isLarger;

    test('9,9 % kleiner, 10 % und mehr größer, in beide Richtungen', () {
      expect(larger(1000, 901), isFalse); // 9,9 %
      expect(larger(1000, 900), isTrue); // 10 %
      expect(larger(1000, 1099), isFalse);
      expect(larger(1000, 1100), isTrue);
    });

    test('Wechsel hart/locker/Ruhetag und Entfallen, Verlängern nicht', () {
      bool l(PlanUnit a, PlanUnit? b) => summarizeChange([a], [?b]).isLarger;
      final easy = _unit(10, PlanUnitKind.easy, 50);
      expect(l(easy, _unit(10, PlanUnitKind.rest, 0)), isTrue);
      expect(l(easy, null), isTrue);
      expect(l(easy, _unit(10, PlanUnitKind.easy, 49)), isFalse);
    });

    test('die erste Fassung ist keine Änderung, Kleineres nur im Verlauf', () {
      expect(
        isLargerPlanChange(_rec(1, PlanTrigger.create, {'larger': true})),
        isFalse,
      );
      expect(
        isLargerPlanChange(_rec(2, PlanTrigger.weekly, {'larger': false})),
        isFalse,
      );
      expect(
        isLargerPlanChange(_rec(2, PlanTrigger.weekly, {'larger': true})),
        isTrue,
      );
      expect(isLargerPlanChange(_rec(2, PlanTrigger.weekly, {})), isFalse);
    });
  });

  group('Karte „Plan angepasst“: bis gesehen', () {
    final h = [
      _rec(1, PlanTrigger.create, {'larger': true}),
      _rec(2, PlanTrigger.feedback, {'larger': true}, reason: 'warning'),
      _rec(3, PlanTrigger.weekly, {'larger': false}),
    ];

    test('jüngste größere Änderung mit Grund-Code aus der Fassung', () {
      final n = planChangeNotice(h);
      expect(n?.planId, 2);
      expect(n?.explanation.code, 'warning');
      expect(n?.explanation.kind, ExplanationKind.planChange);
    });

    test(
      'gesehen ist die Plan-ID: gleiche und ältere weg, neuere wieder da',
      () {
        expect(planChangeNotice(h, seenPlanId: 2), isNull);
        expect(planChangeNotice(h, seenPlanId: 3), isNull);
        expect(planChangeNotice(h, seenPlanId: 1)?.planId, 2);
        final h2 = [
          ...h,
          _rec(4, PlanTrigger.pause, {'larger': true}),
        ];
        expect(planChangeNotice(h2, seenPlanId: 2)?.planId, 4);
      },
    );

    test('ohne größere Änderung keine Karte', () {
      expect(planChangeNotice([h[0], h[2]]), isNull);
      expect(planChangeNotice(const []), isNull);
    });
  });

  group('Vorschlag „Woche wiederholen“ (PAR-140)', () {
    // Programmwochen 0 und 1 mit je 3 Einheiten: Tage 2/4/6 und 9/11/13.
    List<PlanUnit> units({List<int?> runIds = const [null, null, null]}) => [
      for (var i = 0; i < 3; i++)
        _unit(2 + 2 * i, PlanUnitKind.walkRun, 30, runId: runIds[i]),
      for (var i = 0; i < 3; i++) _unit(9 + 2 * i, PlanUnitKind.walkRun, 30),
    ];
    WalkRunWeekProposal? find(
      List<PlanUnit> u, {
      int today = 8,
      Map<int, int> rpe = const {},
    }) => walkRunWeekProposal(
      units: u,
      start: const WalkRunPosition(0),
      rpeByRunId: rpe,
      today: _d(today),
    );

    test('Woche vorbei mit weniger als 2 absolvierten: wiederholen', () {
      final p = find(units(runIds: [1, null, null]));
      expect(p?.programWeek, 0);
      expect(p?.suggestion.scope, WalkRunRepeatScope.week);
      expect(p?.doneCount, 1);
      expect(p?.sessionCount, 3);
      expect(p?.lastDay, _d(6));
    });

    test('2 absolvierte: kein Vorschlag; 2 mit RPE >= 6: wiederholen', () {
      expect(find(units(runIds: [1, 2, null])), isNull);
      expect(
        find(units(runIds: [1, 2, null]), rpe: {1: 6, 2: 7})?.programWeek,
        0,
      );
      expect(find(units(runIds: [1, 2, null]), rpe: {1: 5, 2: 7}), isNull);
    });

    test('Woche noch nicht vorbei oder nächste Woche begonnen: keiner', () {
      expect(find(units(), today: 6), isNull);
      final u = units(runIds: [null, null, null]);
      u[3] = _unit(9, PlanUnitKind.walkRun, 30, runId: 9);
      expect(find(u, today: 12), isNull);
    });

    test('Start mitten in der Abfolge zählt ab dieser Stelle', () {
      final p = walkRunWeekProposal(
        units: [
          for (var i = 0; i < 3; i++)
            _unit(2 + 2 * i, PlanUnitKind.walkRun, 30),
        ],
        start: const WalkRunPosition(1),
        rpeByRunId: const {},
        today: _d(8),
      );
      expect(p?.programWeek, 1);
    });

    // Woche 5 (Programmwoche 4): drei Läufe an den Tagen 2, 4 und 6.
    WalkRunWeekProposal? week5(
      List<int?> runIds, {
      required Map<int, int> rpe,
      int today = 5,
      WalkRunPosition start = const WalkRunPosition(4),
    }) => walkRunWeekProposal(
      units: [
        for (var i = 0; i < runIds.length; i++)
          _unit(2 + 2 * i, PlanUnitKind.walkRun, 30, runId: runIds[i]),
      ],
      start: start,
      rpeByRunId: rpe,
      today: _d(today),
    );

    test('vor Woche 5, Lauf 3: Lauf 2 mit RPE >= 6 wiederholen', () {
      final p = week5([1, 2, null], rpe: {1: 4, 2: 6})!;
      expect(p.suggestion.scope, WalkRunRepeatScope.session);
      expect(p.suggestion.position, const WalkRunPosition(4, 1));
      expect(p.programWeek, 4);
      expect(p.lastDay, _d(4));
    });

    test('kein Vorschlag bei RPE 5, bei Lauf 3 schon absolviert, ohne Lauf 2 '
        'und in anderen Wochen', () {
      expect(week5([1, 2, null], rpe: {2: 5}), isNull);
      expect(week5([1, 2, 3], rpe: {2: 8}), isNull);
      expect(week5([1, null, null], rpe: {1: 8}), isNull);
      expect(
        week5([1, 2, null], rpe: {2: 8}, start: const WalkRunPosition(1)),
        isNull,
      );
    });

    test('nach dem Wiederholen (Abfolge beginnt bei Lauf 2): kein neuer '
        'Vorschlag, bis wieder Lauf 2 gelaufen ist', () {
      final start = const WalkRunPosition(4, 1);
      expect(
        week5([null, null], rpe: const {}, start: start, today: 1),
        isNull,
      );
      // Lauf 2 gelaufen (erste Einheit), schwer: wieder der Vorschlag.
      final p = week5([7, null], rpe: {7: 7}, start: start, today: 3)!;
      expect(p.suggestion.position, const WalkRunPosition(4, 1));
      expect(p.lastDay, _d(2));
    });
  });
}
