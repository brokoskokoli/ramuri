import 'package:core/core.dart';
import 'package:test/test.dart';

/// Montag, 9.11.2026.
final DateTime _mon = DateTime.utc(2026, 11, 9);
DateTime _d(int n) => _mon.add(Duration(days: n));

const _cet = Duration(hours: 1);

PlanUnit _u(
  int id,
  int day, {
  PlanUnitKind kind = PlanUnitKind.easy,
  int? runId,
}) => PlanUnit(
  id: id,
  day: _d(day),
  kind: kind,
  phase: PlanPhase.build,
  weekIndex: day ~/ 7,
  minutes: 30,
  runId: runId,
  segments: const [],
);

/// Beendeter Lauf, Beginn am Tag [day] um [hour]:[minute] Ortszeit (UTC+1),
/// [minutes] lang.
StoredRun _run(
  int id,
  int day, {
  int hour = 17,
  int minute = 30,
  int minutes = 30,
  Duration? offset = _cet,
  RunState state = RunState.finished,
}) {
  final start = _d(day)
      .add(Duration(hours: hour, minutes: minute))
      .subtract(offset ?? _cet);
  return StoredRun(
    id: id,
    state: state,
    startedAt: start,
    endedAt: state == RunState.finished
        ? start.add(Duration(minutes: minutes))
        : null,
    endedUtcOffset: state == RunState.finished ? offset : null,
  );
}

List<PlanRunCandidate> _candidates(
  List<StoredRun> runs, {
  Map<int, Duration> moving = const {},
  Duration fallbackOffset = _cet,
}) => [
  for (final r in runs)
    ?PlanRunCandidate.of(
      r,
      movingTime: moving[r.id],
      fallbackOffset: fallbackOffset,
    ),
];

List<PlanRunAssignment> _assign(
  List<PlanUnit> units,
  List<StoredRun> runs, {
  int today = 2,
  int from = 0,
  Map<int, Duration> moving = const {},
}) => planAutoAssignments(
  units: units,
  runs: _candidates(runs, moving: moving),
  today: _d(today),
  from: _d(from),
);

PlanRunAssignment _a(int unit, int run) =>
    PlanRunAssignment(unitId: unit, runId: run);

void main() {
  group('PAR-207 Zuordnung von Läufen zu Einheiten', () {
    test('Lauf um 17:30, Plan um 19:00 desselben Tags: heutige Einheit '
        'bekommt den Lauf (FR-0156)', () {
      // Der Plan beginnt heute (Mi); der Lauf lief vor dem Anlegen.
      final units = [_u(1, 2), _u(2, 4)];
      expect(_assign(units, [_run(7, 2)]), [_a(1, 7)]);
    });

    test('Lauf gestern, Plan heute: keine Einheit gestern, nichts '
        'zugeordnet', () {
      final units = [_u(1, 2), _u(2, 4)];
      expect(_assign(units, [_run(7, 1)]), isEmpty);
    });

    test('zwei Läufe an einem Tag: der mit der längeren Bewegungszeit', () {
      final units = [_u(1, 2)];
      final runs = [_run(7, 2, hour: 7), _run(8, 2, hour: 18)];
      expect(
        _assign(
          units,
          runs,
          moving: {
            7: const Duration(minutes: 20),
            8: const Duration(minutes: 40),
          },
        ),
        [_a(1, 8)],
      );
      // Umgekehrt: der frühere ist länger.
      expect(
        _assign(
          units,
          runs,
          moving: {
            7: const Duration(minutes: 45),
            8: const Duration(minutes: 40),
          },
        ),
        [_a(1, 7)],
      );
    });

    test('gleiche Bewegungszeit: der frühere Lauf', () {
      final units = [_u(1, 2)];
      final runs = [_run(8, 2, hour: 18), _run(7, 2, hour: 7)];
      const same = Duration(minutes: 30);
      expect(_assign(units, runs, moving: {7: same, 8: same}), [_a(1, 7)]);
    });

    test('Bewegungszeit zählt, nicht die Dauer (Pausen)', () {
      final units = [_u(1, 2)];
      // Lauf 7 dauert länger (Pause), bewegt sich aber kürzer.
      final runs = [_run(7, 2, hour: 7, minutes: 60), _run(8, 2, minutes: 40)];
      expect(
        _assign(
          units,
          runs,
          moving: {
            7: const Duration(minutes: 25),
            8: const Duration(minutes: 38),
          },
        ),
        [_a(1, 8)],
      );
    });

    test('ohne Bewegungszeit zählt die Dauer von Beginn bis Ende', () {
      final units = [_u(1, 2)];
      final runs = [_run(7, 2, hour: 7, minutes: 20), _run(8, 2, minutes: 40)];
      expect(_assign(units, runs), [_a(1, 8)]);
    });

    test('ein Lauf, zwei Einheiten am selben Tag: nur eine bekommt ihn', () {
      final units = [_u(1, 2), _u(2, 2)];
      expect(_assign(units, [_run(7, 2)]), [_a(1, 7)]);
    });

    test('bestehende Zuordnung bleibt, der Lauf zählt kein zweites Mal '
        '(FR-0157, PAR-203)', () {
      // Einheit 1 trägt schon Lauf 6; der längere Lauf 7 ändert nichts.
      final units = [_u(1, 2, runId: 6), _u(2, 3)];
      final runs = [_run(6, 2, hour: 7), _run(7, 2, minutes: 90)];
      expect(_assign(units, runs, today: 3), isEmpty);
      // Ein Lauf, der schon einer Einheit (auch außerhalb des Zeitraums)
      // gehört, zählt nicht für eine andere.
      final moved = [_u(1, 2, runId: 7), _u(2, 2)];
      expect(_assign(moved, [_run(7, 2)]), isEmpty);
    });

    test('Ruhetag und Einheit ohne Kennung bekommen keinen Lauf', () {
      final rest = [_u(1, 2, kind: PlanUnitKind.rest)];
      expect(_assign(rest, [_run(7, 2)]), isEmpty);
      final unsaved = [
        PlanUnit(
          day: _d(2),
          kind: PlanUnitKind.easy,
          phase: PlanPhase.build,
          weekIndex: 0,
          minutes: 30,
          segments: const [],
        ),
      ];
      expect(_assign(unsaved, [_run(7, 2)]), isEmpty);
    });

    test('unbeendeter Lauf zählt nicht', () {
      expect(
        _assign([_u(1, 2)], [_run(7, 2, state: RunState.paused)]),
        isEmpty,
      );
    });

    test('Einheit nach heute oder vor dem Zeitraum: keine Zuordnung', () {
      // Lauf am Do, heute ist Mi: die Einheit am Do ist noch nicht dran.
      expect(_assign([_u(1, 3)], [_run(7, 3)], today: 2), isEmpty);
      // Einheit am Mo, Zeitraum ab Di.
      expect(_assign([_u(1, 0)], [_run(7, 0)], from: 1), isEmpty);
      // Grenzen eingeschlossen.
      expect(_assign([_u(1, 1)], [_run(7, 1)], from: 1, today: 1), [_a(1, 7)]);
    });

    test('Lauf von 23:50 bis 00:20 zählt für den Starttag', () {
      final run = _run(7, 1, hour: 23, minute: 50, minutes: 30);
      expect(_assign([_u(1, 2)], [run]), isEmpty);
      expect(_assign([_u(1, 1)], [run]), [_a(1, 7)]);
    });

    test('Zeitzonenwechsel: es zählt der Versatz des Laufs, nicht der des '
        'Geräts jetzt', () {
      // Beginn Di 00:30 in UTC+2, also Mo 22:30 UTC. Das Gerät steht jetzt
      // in UTC-5 (Ersatzversatz); der Lauf zählt trotzdem für Dienstag.
      final run = _run(
        7,
        1,
        hour: 0,
        minute: 30,
        offset: const Duration(hours: 2),
      );
      final units = [_u(1, 0), _u(2, 1)];
      final runs = [
        for (final r in [run])
          ?PlanRunCandidate.of(
            r,
            movingTime: null,
            fallbackOffset: const Duration(hours: -5),
          ),
      ];
      expect(
        planAutoAssignments(
          units: units,
          runs: runs,
          today: _d(2),
          from: _d(0),
        ),
        [_a(2, 7)],
      );
      expect(runs.single.day, _d(1));
    });

    test('Lauf ohne gespeicherten Versatz: Ersatzversatz', () {
      // Beginn Mo 23:30 UTC; in UTC+1 ist das Dienstag.
      final run = StoredRun(
        id: 7,
        state: RunState.finished,
        startedAt: _d(0).add(const Duration(hours: 23, minutes: 30)),
        endedAt: _d(1).add(const Duration(minutes: 10)),
      );
      expect(planRunStartDay(run, fallbackOffset: _cet), _d(1));
      expect(planRunStartDay(run, fallbackOffset: Duration.zero), _d(0));
    });

    test('verschobene Einheit: Lauf am neuen Tag zählt, am alten nicht', () {
      // Einheit von Mo auf Di verschoben (Tag ist der aktuelle).
      final moved = PlanUnit(
        id: 1,
        day: _d(1),
        kind: PlanUnitKind.easy,
        phase: PlanPhase.build,
        weekIndex: 0,
        minutes: 30,
        segments: const [],
        pinned: true,
      );
      expect(_assign([moved], [_run(7, 0)]), isEmpty);
      expect(_assign([moved], [_run(8, 1)]), [_a(1, 8)]);
    });

    test('GPS- und Laufbandlauf gleich behandelt', () {
      final belt = StoredRun(
        id: 8,
        state: RunState.finished,
        startedAt: _d(2).add(const Duration(hours: 17)),
        endedAt: _d(2).add(const Duration(hours: 18)),
        endedUtcOffset: _cet,
        mode: RunMode.treadmill,
      );
      expect(
        _assign(
          [_u(1, 2)],
          [_run(7, 2), belt],
          moving: {
            7: const Duration(minutes: 30),
            8: const Duration(minutes: 50),
          },
        ),
        [_a(1, 8)],
      );
    });

    test('mehrere Tage: jede Einheit ihren Lauf; idempotent', () {
      final units = [_u(1, 0), _u(2, 2), _u(3, 4)];
      final runs = [_run(7, 0), _run(8, 1), _run(9, 2), _run(10, 4)];
      final first = _assign(units, runs);
      expect(first, [_a(1, 7), _a(2, 9)]);
      final applied = [
        for (final u in units)
          u.copyWith(
            runId: first.where((a) => a.unitId == u.id).firstOrNull?.runId,
          ),
      ];
      expect(_assign(applied, runs), isEmpty);
    });
  });
}
