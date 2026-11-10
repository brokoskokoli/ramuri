import '../goals/training_goal.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'weekly_time.dart';

/// Warum eine gewünschte harte Einheit in einer Woche nicht vorkommt
/// (PAR-198, PAR-059). Nur gemeldet, wenn der Schalter an ist.
enum HardOmission {
  /// Weniger als 3 Läufe je Woche.
  tooFewRunDays,

  /// 30 min am Stück gehen (noch) nicht.
  notContinuous30,

  /// Die gewählte Form passt nicht in die maximale Zeit je Einheit; die
  /// Einheit ist ein lockerer Lauf (PAR-198).
  exceedsMaxSession,

  /// Kein Lauftag mit vollem Tag Abstand zum langen Lauf (und zur
  /// intensiven Einheit der Vorwoche) (FR-0152, PAR-059).
  noRecoveryDay,

  /// Die Form passt nicht in den gleichmäßigen Anteil der Wochenzeit nach
  /// dem langen Lauf (PAR-197) oder die Restzeit reicht nicht.
  weekTooShort,
}

/// Einheiten einer Woche samt benanntem Rest.
class PlannedWeek {
  const PlannedWeek({
    required this.units,
    required this.unplacedMinutes,
    required this.hardOmission,
    this.droppedDays = const [],
  });

  /// Einheiten nach Tag sortiert; nur Lauftage (Ruhetage werden nicht
  /// ausgegeben).
  final List<PlanUnit> units;

  /// Wochenzeit, die wegen der maximalen Zeit je Einheit in keiner Einheit
  /// Platz fand. 0, wenn alles verteilt ist. Wird gemeldet, nicht verworfen.
  final int unplacedMinutes;

  /// Grund, wenn eine gewünschte harte Einheit fehlt; sonst `null`.
  final HardOmission? hardOmission;

  /// Lauftage, deren Einheit entfiel, weil die Wochenzeit für sie keine
  /// Minute übrig ließ (keine Einheit mit 0 min). Die Mindestdauer einer
  /// Einheit ist eine Spec-Lücke (gemeldet).
  final List<DateTime> droppedDays;
}

/// Wie [planWeekUnits], mit den Angaben aus dem Ziel.
PlannedWeek planWeekUnitsForGoal({
  required TrainingGoal goal,
  required PlanWeek week,
  required bool continuous30,
  int hardOrdinal = 0,
  int? previousIntensiveWeekday,
  PlanParameters parameters = const PlanParameters(),
}) => planWeekUnits(
  week: week,
  runDays: goal.runDays,
  maxSessionMinutes: (goal.maxSessionSeconds / 60).floor(),
  hardEnabled: goal.hardSessionEnabled,
  continuous30: continuous30,
  hardOrdinal: hardOrdinal,
  previousIntensiveWeekday: previousIntensiveWeekday,
  parameters: parameters,
);

/// Einheiten einer Woche (PAR-195, PAR-197, PAR-198, PAR-120, PAR-121,
/// FR-0151, FR-0152). Rein.
///
/// - [week]: Minuten, Phase und Art aus [planWeeklyTime]. Ohne Minuten
///   (Geh-Lauf-Abfolge) keine Einheiten.
/// - [runDays]: Wochentage 1 bis 7 (Montag bis Sonntag).
/// - [maxSessionMinutes]: keine Einheit ist länger (FR-0136).
/// - [hardEnabled], [continuous30]: Schalter und Bedingung aus PAR-198.
/// - [hardOrdinal]: wie viele harte Einheiten zuvor geplant waren; bestimmt
///   den Wechsel Intervalle, Tempodauerlauf, progressiver Lauf.
/// - [previousIntensiveWeekday]: Wochentag der letzten intensiven Einheit
///   der Vorwoche (für den Abstand über den Wochenwechsel).
PlannedWeek planWeekUnits({
  required PlanWeek week,
  required Set<int> runDays,
  required int maxSessionMinutes,
  required bool hardEnabled,
  required bool continuous30,
  int hardOrdinal = 0,
  int? previousIntensiveWeekday,
  PlanParameters parameters = const PlanParameters(),
}) {
  final p = parameters;
  final total = week.minutes;
  final days = (runDays.toList()..sort());
  if (total == null || days.isEmpty || maxSessionMinutes < 1) {
    return PlannedWeek(
      units: const [],
      unplacedMinutes: total ?? 0,
      hardOmission: null,
    );
  }
  final n = days.length;
  // Tage der Vorwoche zählen negativ: Montag der Folgewoche = 1, Sonntag
  // davor = 0.
  final prev = previousIntensiveWeekday == null
      ? null
      : previousIntensiveWeekday - 7;

  // Langer Lauf (PAR-195). Bei einem Lauftag ist er der ganze Lauf.
  final share = p.longestRunShare(n);
  final longMinutes = _min(
    _min((total * share).round(), total),
    maxSessionMinutes,
  );

  // Tag des langen Laufs: der späteste Lauftag. Die Regeln legen den Tag
  // nicht fest (Lücke, gemeldet). Bei mehreren Lauftagen liegt er mindestens
  // einen vollen Tag nach dem Montag und damit nach der intensiven Einheit
  // der Vorwoche (spätestens Sonntag davor).
  final longDay = days.last;
  final others = [
    for (final d in days)
      if (d != longDay) d,
  ];

  // Harte Einheit (PAR-198): Entscheidung und Tag.
  HardOmission? omission;
  PlanUnitKind? hardKind;
  var hardDay = 0;
  var hardMinutes = 0;
  List<PlanSegment>? hardSegments;
  if (hardEnabled) {
    if (n < p.hardMinRunDays) {
      omission = HardOmission.tooFewRunDays;
    } else if (!continuous30) {
      omission = HardOmission.notContinuous30;
    } else {
      final short =
          week.kind == WeekKind.lighter ||
          week.kind == WeekKind.reduction ||
          total < p.hardLongFromWeeklyMinutes;
      final kinds = [
        PlanUnitKind.intervals,
        PlanUnitKind.tempo,
        PlanUnitKind.progressive,
      ];
      final k = kinds[hardOrdinal % kinds.length];
      final slot = (total - longMinutes) ~/ (n - 1);
      final built = _hardForm(k, short, slot, maxSessionMinutes, p);
      if (built == null) {
        omission = HardOmission.exceedsMaxSession;
      } else if (built.minutes > slot) {
        // PAR-197: nur, wenn die Form in den gleichmäßigen Anteil nach dem
        // langen Lauf passt; sonst lockerer Lauf.
        omission = HardOmission.weekTooShort;
      } else {
        final day = _hardDay(others, longDay, prev, p.minGapDays);
        final easyCount = n - 2;
        final rest = total - longMinutes - built.minutes;
        if (day == null) {
          omission = HardOmission.noRecoveryDay;
        } else if (rest < easyCount) {
          omission = HardOmission.weekTooShort;
        } else {
          hardKind = k;
          hardDay = day;
          hardMinutes = built.minutes;
          hardSegments = built.segments;
        }
      }
    }
  }

  // Rest gleichmäßig (PAR-197), jede Einheit höchstens die maximale Zeit.
  final easyDays = [
    for (final d in others)
      if (d != hardDay) d,
  ];
  final remaining = total - longMinutes - hardMinutes;
  final easy = <int, int>{};
  var unplaced = total - longMinutes - hardMinutes;
  if (easyDays.isNotEmpty) {
    final base = remaining ~/ easyDays.length;
    final extra = remaining % easyDays.length;
    unplaced = 0;
    for (var i = 0; i < easyDays.length; i++) {
      final want = base + (i < extra ? 1 : 0);
      final got = _min(want, maxSessionMinutes);
      easy[easyDays[i]] = got;
      unplaced += want - got;
    }
  }
  // Ein Lauftag: Wochenzeit über dem langen Lauf bleibt als Rest (oben
  // gesetzt). Der lange Lauf selbst ist dann der ganze Lauf.

  PlanUnit unit(
    int weekday,
    PlanUnitKind kind,
    int minutes,
    List<PlanSegment> segments,
  ) => PlanUnit(
    day: DateTime.utc(
      week.start.year,
      week.start.month,
      week.start.day + weekday - 1,
    ),
    kind: kind,
    phase: week.phase,
    weekIndex: week.index,
    minutes: minutes,
    segments: segments,
  );
  PlanSegment easySeg(int m) =>
      PlanSegment(kind: PlanSegmentKind.easy, minutes: m);

  final units = <PlanUnit>[
    // Bei mehreren Tagen ist der lange Lauf nur der lange, bei einem Tag
    // zugleich der einzige Lauf (PAR-197: „lockerer Lauf“).
    unit(longDay, n == 1 ? PlanUnitKind.easy : PlanUnitKind.long, longMinutes, [
      easySeg(longMinutes),
    ]),
    for (final d in easyDays)
      unit(d, PlanUnitKind.easy, easy[d]!, [easySeg(easy[d]!)]),
    if (hardKind != null) unit(hardDay, hardKind, hardMinutes, hardSegments!),
  ]..sort((a, b) => a.day.compareTo(b.day));

  // Keine Einheit mit 0 min: sie entfällt und wird gemeldet.
  final kept = [
    for (final u in units)
      if (u.minutes >= 1) u,
  ];
  return PlannedWeek(
    units: kept,
    unplacedMinutes: unplaced,
    hardOmission: omission,
    droppedDays: [
      for (final u in units)
        if (u.minutes < 1) u.day,
    ],
  );
}

int _min(int a, int b) => a < b ? a : b;

/// Kleinste Wochenzeit bis [upTo] (einschließlich), bei der die harte Einheit
/// in einer regulären Woche vorkommt (PAR-197, PAR-198), oder `null`, wenn sie
/// bis [upTo] nie vorkommt (z. B. weniger als 3 Lauftage oder maximale Zeit
/// zu kurz). Die einzige Stelle dieser Rechnung: sie fragt [planWeekUnits]
/// selbst (kürzere oder reguläre Form nach Wochenzeit, langer Lauf, Anteil,
/// maximale Zeit, Lauftage) und verlangt, dass jede der drei Formen
/// (Intervalle, Tempodauerlauf, progressiver Lauf; sie wechseln) passt, damit
/// die harte Einheit in jeder Woche der Spitze erscheint.
int? hardFitWeeklyMinutes({
  required Set<int> runDays,
  required int maxSessionMinutes,
  required int upTo,
  PlanParameters parameters = const PlanParameters(),
}) {
  final monday = DateTime.utc(2001, 1, 1); // ein Montag
  for (var t = 1; t <= upTo; t++) {
    final week = PlanWeek(
      index: 0,
      start: monday,
      minutes: t,
      phase: PlanPhase.build,
      kind: WeekKind.holding,
    );
    var all = true;
    for (var ordinal = 0; ordinal < 3 && all; ordinal++) {
      final w = planWeekUnits(
        week: week,
        runDays: runDays,
        maxSessionMinutes: maxSessionMinutes,
        hardEnabled: true,
        continuous30: true,
        hardOrdinal: ordinal,
        parameters: parameters,
      );
      all = w.hardOmission == null && w.units.any((u) => u.isHard);
    }
    if (all) return t;
  }
  return null;
}

/// Tag für die harte Einheit: mindestens [gap] Tage Abstand zum langen Lauf
/// und zur Vorwoche, unter den Kandidaten der mit dem größten Abstand, bei
/// Gleichstand der frühere.
int? _hardDay(List<int> candidates, int longDay, int? prev, int gap) {
  int? best;
  var bestGap = -1;
  for (final d in candidates) {
    var g = (d - longDay).abs();
    if (prev != null && d - prev < g) g = d - prev;
    if (g < gap) continue;
    if (g > bestGap) {
      best = d;
      bestGap = g;
    }
  }
  return best;
}

class _Hard {
  const _Hard(this.minutes, this.segments);
  final int minutes;
  final List<PlanSegment> segments;
}

/// Baut die Form oder liefert `null`, wenn sie über der maximalen Zeit liegt
/// (PAR-198: dann lockerer Lauf).
_Hard? _hardForm(
  PlanUnitKind kind,
  bool short,
  int slot,
  int maxSession,
  PlanParameters p,
) {
  PlanSegment seg(PlanSegmentKind k, int m) => PlanSegment(kind: k, minutes: m);
  if (kind == PlanUnitKind.progressive) {
    final block = short ? p.progressiveBlockShort : p.progressiveBlockLong;
    if (p.hardMinContinuousMinutes > maxSession) return null;
    final total = slot.clamp(p.hardMinContinuousMinutes, maxSession);
    return _Hard(total, [
      seg(PlanSegmentKind.easy, total - block),
      seg(PlanSegmentKind.endBlock, block),
    ]);
  }
  final isIntervals = kind == PlanUnitKind.intervals;
  final b = isIntervals
      ? (short ? p.intervalsShort : p.intervalsLong)
      : (short ? p.tempoShort : p.tempoLong);
  final total = p.warmUpMinutes + b.mainMinutes + p.coolDownMinutes;
  if (total > maxSession) return null;
  final work = isIntervals ? PlanSegmentKind.interval : PlanSegmentKind.tempo;
  return _Hard(total, [
    seg(PlanSegmentKind.warmUp, p.warmUpMinutes),
    for (var i = 0; i < b.reps; i++) ...[
      if (i > 0) seg(PlanSegmentKind.recovery, b.pauseMinutes),
      seg(work, b.workMinutes),
    ],
    seg(PlanSegmentKind.coolDown, p.coolDownMinutes),
  ]);
}
