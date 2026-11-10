import '../goals/training_goal.dart';
import 'walk_run_program.dart';
import 'walk_run_units.dart';
import 'weekly_time.dart';

/// Obergrenze der Suche; die längste Abfolge (1 Lauftag) dauert 27 Wochen.
const int _maxWalkRunWeeks = 120;

/// Wert für „endet nicht“ in `walkRunWeeks` (PAR-141: bleibt bei der letzten
/// passenden Woche).
const int walkRunNeverEnds = 100000;

class _Entry {
  const _Entry(this.position, this.repeat, this.days);
  final WalkRunPosition position;
  final bool repeat;

  /// Lauftage dieser Kalenderwoche (vor dem Beginn der Abfolge entfallen
  /// sie).
  final Set<int> days;
}

/// Die Geh-Lauf-Abfolge als Kalenderfolge ab dem Anker (PAR-065, PAR-141):
/// welche Stelle in welcher Kalenderwoche läuft. Die Länge in Kalenderwochen
/// folgt aus Lauftagen und maximaler Zeit je Einheit (2 Tage 1,5 Wochen je
/// Programmwoche, 1 Tag 3). Rein.
///
/// Ist eine Einheit auch mit gekürztem Gehen länger als die maximale Zeit,
/// bleibt die Abfolge bei der letzten passenden Programmwoche und wiederholt
/// sie ([stuck], PAR-141); passt schon die erste nicht, bleibt sie dort
/// ([noWeekFits]). Der Aufrufer zeigt das an.
class WalkRunSchedule {
  WalkRunSchedule._(
    this._entries,
    this._runDays,
    this._anchor,
    this._from,
    this._maxSession,
    this._program,
    this.stuck,
    this.noWeekFits,
    this.stayWeek,
  );

  /// Abfolge für [runDays] ab [start]. [maxSessionMinutes] `null`: keine
  /// Grenze. [anchor] (Montag der Kalenderwoche 0) und [from]: Lauftage vor
  /// [from] gehören nicht zur Abfolge (der Plan entsteht mitten in der Woche;
  /// die erste Einheit liegt auf dem ersten Lauftag ab [from]).
  factory WalkRunSchedule.build({
    required Set<int> runDays,
    required int? maxSessionMinutes,
    WalkRunPosition start = const WalkRunPosition(0),
    DateTime? anchor,
    DateTime? from,
    WalkRunProgram? program,
  }) {
    final prog = program ?? walkRunProgram;
    final probe = PlanWeek(
      index: 0,
      start: DateTime.utc(2001, 1, 1),
      minutes: null,
      phase: PlanPhase.entry,
      kind: WeekKind.walkRun,
    );
    final entries = <_Entry>[];
    var pos = start;
    WalkRunPosition? lastFit;
    var stuck = false, noFit = false;
    int? stay;
    for (var w = 0; w < _maxWalkRunWeeks; w++) {
      final days = _daysOfWeek(runDays, w, anchor, from);
      if (days.isEmpty) {
        entries.add(_Entry(pos, false, days));
        continue;
      }
      final plan = planWalkRunWeek(
        week: probe,
        runDays: days,
        position: pos,
        maxSessionMinutes: maxSessionMinutes,
        program: prog,
      );
      if (plan.units.isEmpty) break; // Ende oder keine Lauftage
      if (plan.exceedsMaxSession) {
        stuck = true;
        noFit = lastFit == null;
        final at = lastFit ?? pos;
        stay = at.week;
        entries.add(_Entry(at, true, days));
        break;
      }
      entries.add(_Entry(pos, false, days));
      lastFit = pos;
      if (plan.finished) break;
      pos = plan.next;
    }
    return WalkRunSchedule._(
      entries,
      runDays,
      anchor,
      from,
      maxSessionMinutes,
      prog,
      stuck,
      noFit,
      stay,
    );
  }

  /// Für ein Ziel: Lauftage und maximale Zeit je Einheit aus dem Ziel.
  factory WalkRunSchedule.forGoal(
    TrainingGoal goal, {
    WalkRunPosition start = const WalkRunPosition(0),
    DateTime? anchor,
    DateTime? from,
    WalkRunProgram? program,
  }) => WalkRunSchedule.build(
    runDays: goal.runDays,
    maxSessionMinutes: (goal.maxSessionSeconds / 60).floor(),
    start: start,
    anchor: anchor,
    from: from,
    program: program,
  );

  final List<_Entry> _entries;
  final Set<int> _runDays;
  final DateTime? _anchor;
  final DateTime? _from;
  final int? _maxSession;
  final WalkRunProgram _program;

  /// Die Abfolge bleibt bei einer Programmwoche, weil die nächste nicht in
  /// die maximale Zeit passt (PAR-141).
  final bool stuck;

  /// Auch die erste Einheit passt nicht (bei [stuck]).
  final bool noWeekFits;

  /// Programmwoche (ab 0), bei der die Abfolge bleibt; sonst `null`.
  final int? stayWeek;

  /// Kalenderwochen vor der ersten Laufwoche (PAR-192); [walkRunNeverEnds],
  /// wenn die Abfolge bleibt.
  int get weeks => stuck ? walkRunNeverEnds : _entries.length;

  /// Einheiten der Kalenderwoche [calendarWeek] (ab Anker, 0 beginnend).
  WalkRunWeekPlan? plan(int calendarWeek, PlanWeek week) {
    if (calendarWeek < 0) return null;
    final _Entry e;
    if (calendarWeek < _entries.length) {
      e = _entries[calendarWeek];
    } else if (stuck && _entries.isNotEmpty) {
      e = _entries.last;
    } else {
      return null;
    }
    final days = calendarWeek < _entries.length
        ? e.days
        : _daysOfWeek(_runDays, calendarWeek, _anchor, _from);
    return planWalkRunWeek(
      week: week,
      runDays: days,
      position: e.position,
      repeatWeek: e.repeat,
      maxSessionMinutes: _maxSession,
      program: _program,
    );
  }
}

/// Lauftage der Kalenderwoche [week] (ab [anchor]) am oder nach [from].
Set<int> _daysOfWeek(
  Set<int> runDays,
  int week,
  DateTime? anchor,
  DateTime? from,
) {
  if (anchor == null || from == null) return runDays;
  final monday = planDay(anchor).add(Duration(days: 7 * week));
  final first = planDay(from);
  return {
    for (final d in runDays)
      if (!monday.add(Duration(days: d - 1)).isBefore(first)) d,
  };
}
