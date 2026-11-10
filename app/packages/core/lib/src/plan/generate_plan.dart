import '../goals/training_goal.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'week_units.dart';
import 'weekly_time.dart';

/// Ergebnis von [generatePlan].
class GeneratedPlan {
  const GeneratedPlan({
    required this.version,
    required this.weeks,
    required this.units,
    required this.frozenUnits,
    required this.unplacedByWeek,
    required this.hardOmissions,
  });

  final PlanVersion version;

  /// Verlauf der Wochenzeit ab der Woche von „heute“.
  final List<PlanWeek> weeks;

  /// Die neuen künftigen Einheiten (Tag ab heute, ohne feste Einheit auf dem
  /// Tag), nach Tag sortiert.
  final List<PlanUnit> units;

  /// Die übergebenen eingefrorenen Einheiten, unverändert, nach Tag sortiert.
  final List<PlanUnit> frozenUnits;

  /// Wochenzeit, die wegen der maximalen Zeit je Einheit keinen Platz fand
  /// (gemeldet, nicht verworfen).
  int get unplacedMinutes => unplacedByWeek.values.fold(0, (a, b) => a + b);

  /// Nicht untergebrachte Minuten je Woche (Nummer ab Anker), nur Wochen mit
  /// künftigen Einheiten und Rest > 0.
  final Map<int, int> unplacedByWeek;

  /// Wochen (Nummer ab Anker), in denen eine gewünschte harte Einheit fehlt.
  final Map<int, HardOmission> hardOmissions;

  /// Eingefrorene und neue Einheiten, nach Tag sortiert.
  List<PlanUnit> get allUnits => _byDay([...frozenUnits, ...units]);
}

List<PlanUnit> _byDay(List<PlanUnit> l) {
  // Stabil: gleicher Tag behält die Reihenfolge.
  final idx = {for (var i = 0; i < l.length; i++) l[i]: i};
  return [...l]..sort((a, b) {
    final c = a.day.compareTo(b.day);
    return c != 0 ? c : idx[a]!.compareTo(idx[b]!);
  });
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Plan ab heute (ADR-0010 Punkt 2, 3, 6; PAR-192 bis PAR-199, FR-0141 bis
/// FR-0152). Rein: kein `DateTime.now()`, kein Zufall, kein Speicher.
///
/// [frozenUnits] (Tag vor heute oder Lauf zugeordnet) bleiben unverändert, ihre
/// Minuten zählen zur Wochenzeit ihrer Woche. Tage vor [today] ohne Einheit
/// gelten als ausgefallen und werden nicht nachgeholt (PAR-201). Weicht die
/// Summe der eingefrorenen Einheiten einer Woche von der Planung ab, gleichen
/// die künftigen lockeren und langen Einheiten dieser Woche den Unterschied
/// aus; harte Einheiten bleiben unverändert.
GeneratedPlan generatePlan(
  TrainingGoal goal,
  PlanInputs inputs,
  List<PlanUnit> frozenUnits,
  DateTime today, {
  PlanParameters parameters = const PlanParameters(),
}) {
  final p = parameters;
  final todayDay = _day(today);
  final n = goal.runDays.length;
  final cap = (goal.weeklyCapSeconds / 60).floor();
  final maxSession = (goal.maxSessionSeconds / 60).floor();
  final distance = goal.type == GoalType.open ? null : goal.distance;

  int? peak;
  if (distance != null) {
    peak = peakWeeklyMinutes(
      longestRunMinutes: targetLongestRunMinutes(
        distance: distance,
        easyPaceSecondsPerKm: inputs.easyPaceSecondsPerKm,
        easyRunCount: inputs.easyRunCount,
        parameters: p,
      ),
      runDays: n,
      parameters: p,
    );
  }

  final course = planWeeklyTime(
    startMinutes: inputs.startWeeklyMinutes,
    capMinutes: cap < 1 ? 1 : cap,
    anchor: inputs.anchor,
    today: todayDay,
    peakMinutes: peak,
    distance: distance,
    targetDate: goal.targetDate,
    walkRunWeeks: inputs.walkRunWeeks,
    parameters: p,
  );

  final frozen = _byDay([...frozenUnits]);
  final firstStart = course.weeks.isEmpty ? null : course.weeks.first.start;
  var hardOrdinal = firstStart == null
      ? 0
      : frozen.where((u) => u.isHard && u.day.isBefore(firstStart)).length;

  // Einheiten je Woche (Montag -> Einheiten), eingefroren und neu, für den
  // Abstand über den Wochenwechsel.
  final byWeek = <DateTime, List<PlanUnit>>{};
  for (final u in frozen) {
    final m = u.day.subtract(Duration(days: u.day.weekday - 1));
    (byWeek[m] ??= []).add(u);
  }

  final created = <PlanUnit>[];
  final omissions = <int, HardOmission>{};
  final unplaced = <int, int>{};

  for (final week in course.weeks) {
    final start = week.start;
    final end = start.add(const Duration(days: 7));
    final frozenWeek = [
      for (final u in frozen)
        if (!u.day.isBefore(start) && u.day.isBefore(end)) u,
    ];
    final frozenDays = {for (final u in frozenWeek) u.day};
    final frozenHard = frozenWeek.any((u) => u.isHard);

    int? prevWeekday;
    final prevUnits = byWeek[start.subtract(const Duration(days: 7))];
    if (prevUnits != null) {
      for (final u in prevUnits) {
        if (u.isIntensive &&
            (prevWeekday == null || u.day.weekday > prevWeekday)) {
          prevWeekday = u.day.weekday;
        }
      }
    }

    final planned = planWeekUnits(
      week: week,
      runDays: goal.runDays,
      maxSessionMinutes: maxSession,
      hardEnabled: goal.hardSessionEnabled,
      continuous30: canRunContinuous30(
        goal,
        weekIndex: week.index,
        walkRunWeeks: inputs.walkRunWeeks,
        parameters: p,
      ),
      hardOrdinal: hardOrdinal,
      previousIntensiveWeekday: prevWeekday,
      parameters: p,
    );

    // Höchstens eine harte Einheit je Woche (PAR-198): Ist schon eine
    // eingefroren, wird die geplante künftige zu einem lockeren Lauf gleicher
    // Dauer.
    var future = <PlanUnit>[
      for (final u in planned.units)
        if (!u.day.isBefore(todayDay) && !frozenDays.contains(u.day))
          frozenHard && u.isHard ? _asEasy(u) : u,
    ];

    // Wochenminuten der eingefrorenen Einheiten anrechnen: Unterschied zur
    // Planung auf diesen Tagen.
    var deviation = 0;
    for (final u in frozenWeek) {
      deviation += u.minutes;
    }
    for (final u in planned.units) {
      if (frozenDays.contains(u.day)) deviation -= u.minutes;
    }
    if (deviation != 0) {
      future = _absorb(future, -deviation, maxSession);
    }

    if (future.isNotEmpty) {
      if (planned.unplacedMinutes > 0) {
        unplaced[week.index] = planned.unplacedMinutes;
      }
      final om = planned.hardOmission;
      if (om != null) omissions[week.index] = om;
    }
    created.addAll(future);
    byWeek[start] = [...frozenWeek, ...future];
    if (byWeek[start]!.any((u) => u.isHard)) hardOrdinal++;
  }

  return GeneratedPlan(
    version: PlanVersion.current,
    weeks: course.weeks,
    units: _byDay(created),
    frozenUnits: frozen,
    unplacedByWeek: unplaced,
    hardOmissions: omissions,
  );
}

PlanUnit _asEasy(PlanUnit u) => PlanUnit(
  day: u.day,
  kind: PlanUnitKind.easy,
  phase: u.phase,
  weekIndex: u.weekIndex,
  minutes: u.minutes,
  segments: [PlanSegment(kind: PlanSegmentKind.easy, minutes: u.minutes)],
  pinned: u.pinned,
  method: u.method,
  methodVersion: u.methodVersion,
);

/// Verteilt [delta] Minuten (auch negativ) gleichmäßig auf die nicht harten
/// Einheiten; Reste auf die früheren. Jede Einheit bleibt zwischen 1 min und
/// der maximalen Zeit.
List<PlanUnit> _absorb(List<PlanUnit> units, int delta, int maxSession) {
  final idx = [
    for (var i = 0; i < units.length; i++)
      if (!units[i].isHard) i,
  ];
  if (idx.isEmpty) return units;
  final out = [...units];
  final base = delta ~/ idx.length; // zur Null hin gerundet
  var rest = delta - base * idx.length;
  final step = rest < 0 ? -1 : 1;
  for (final i in idx) {
    var d = base;
    if (rest != 0) {
      d += step;
      rest -= step;
    }
    final u = out[i];
    var m = u.minutes + d;
    if (m < 1) m = 1;
    if (m > maxSession) m = maxSession;
    if (m == u.minutes) continue;
    out[i] = PlanUnit(
      day: u.day,
      kind: u.kind,
      phase: u.phase,
      weekIndex: u.weekIndex,
      minutes: m,
      segments: [PlanSegment(kind: PlanSegmentKind.easy, minutes: m)],
      pinned: u.pinned,
      method: u.method,
      methodVersion: u.methodVersion,
    );
  }
  return out;
}
