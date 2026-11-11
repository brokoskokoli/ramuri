import 'plan_unit.dart';
import 'walk_run_program.dart';
import 'weekly_time.dart';

/// Stelle in der Abfolge: Programmwoche und Einheit darin, beide ab 0.
class WalkRunPosition {
  const WalkRunPosition(this.week, [this.session = 0]);

  final int week;
  final int session;

  @override
  bool operator ==(Object other) =>
      other is WalkRunPosition &&
      other.week == week &&
      other.session == session;

  @override
  int get hashCode => Object.hash(week, session);

  @override
  String toString() => 'WalkRunPosition($week, $session)';
}

/// Einheiten einer Kalenderwoche der Geh-Lauf-Abfolge.
class WalkRunWeekPlan {
  const WalkRunWeekPlan({
    required this.units,
    required this.next,
    required this.finished,
    required this.exceedsMaxSession,
  });

  /// Einheiten nach Tag sortiert.
  final List<PlanUnit> units;

  /// Stelle, an der die nächste Kalenderwoche weitermacht.
  final WalkRunPosition next;

  /// Die Abfolge ist mit dieser Woche zu Ende.
  final bool finished;

  /// Mindestens eine Einheit ist auch mit gekürztem Gehen länger als die
  /// maximale Zeit (PAR-141); der Aufrufer zeigt das an.
  final bool exceedsMaxSession;
}

/// Einheiten der Geh-Lauf-Abfolge für eine Kalenderwoche (PAR-065, PAR-140,
/// PAR-141). Rein. PAR-193 bis PAR-195 gelten hier nicht: die Schritte legt
/// der Datensatz fest.
///
/// - [position]: wo die Abfolge steht (nächste noch offene Einheit).
/// - [repeatWeek]: die Programmwoche an [position] noch einmal von vorn
///   laufen statt weiter (PAR-140). Der Aufrufer entscheidet, die App
///   schlägt es nur vor.
/// - [runDays]: Wochentage 1 bis 7. Bei mindestens so vielen Tagen wie
///   Einheiten je Woche (3) liegen die Einheiten verteilt auf den Tagen;
///   bei weniger Tagen läuft die Folge über mehr Wochen (1,5 bzw. 3, PAR-141).
/// - [maxSessionMinutes]: ist eine Einheit länger, wird das Gehen davor und
///   danach gekürzt (PAR-141).
///
/// Es braucht keinen Sensor: die Dauer je Schritt genügt (FR-0155).
WalkRunWeekPlan planWalkRunWeek({
  required PlanWeek week,
  required Set<int> runDays,
  required WalkRunPosition position,
  bool repeatWeek = false,
  int? maxSessionMinutes,
  WalkRunProgram? program,
}) {
  program ??= walkRunProgram;
  final order = program.orderedSessions;
  final days = [
    for (final d in runDays)
      if (d >= 1 && d <= 7) d,
  ]..sort();

  final from = repeatWeek ? 0 : position.session;
  final start = order.indexWhere(
    (s) => s.week == position.week && s.session >= from,
  );
  if (start < 0 || days.isEmpty) {
    return WalkRunWeekPlan(
      units: const [],
      next: start < 0 ? WalkRunPosition(program.weeks.length) : position,
      finished: start < 0,
      exceedsMaxSession: false,
    );
  }

  final perWeek = program.maxSessionsPerWeek;
  final wanted = days.length < perWeek ? days.length : perWeek;
  final count = start + wanted > order.length ? order.length - start : wanted;
  final chosen = _spread(days, count);

  var exceeds = false;
  final units = <PlanUnit>[];
  for (var i = 0; i < count; i++) {
    final o = order[start + i];
    final built = _buildUnit(
      week: week,
      weekday: chosen[i],
      steps: program.weeks[o.week].sessions[o.session],
      program: program,
      maxSessionMinutes: maxSessionMinutes,
    );
    exceeds = exceeds || built.exceeds;
    units.add(built.unit);
  }

  final after = start + count;
  final finished = after >= order.length;
  return WalkRunWeekPlan(
    units: units,
    next: finished
        ? WalkRunPosition(program.weeks.length)
        : WalkRunPosition(order[after].week, order[after].session),
    finished: finished,
    exceedsMaxSession: exceeds,
  );
}

/// [count] Tage aus [days], möglichst gleichmäßig verteilt.
List<int> _spread(List<int> days, int count) {
  if (count >= days.length) return days;
  if (count == 1) return [days.first];
  return [
    for (var i = 0; i < count; i++)
      days[(i * (days.length - 1) / (count - 1)).round()],
  ];
}

({PlanUnit unit, bool exceeds}) _buildUnit({
  required PlanWeek week,
  required int weekday,
  required List<WalkRunStep> steps,
  required WalkRunProgram program,
  required int? maxSessionMinutes,
}) {
  final core = steps.fold<int>(0, (a, s) => a + s.seconds);
  var warm = program.warmUpSeconds;
  var cool = program.coolDownSeconds;
  var exceeds = false;
  if (maxSessionMinutes != null) {
    final limit = maxSessionMinutes * 60;
    if (warm + core + cool > limit) {
      if (program.shortenedWalkSeconds < warm) {
        warm = program.shortenedWalkSeconds;
      }
      if (program.shortenedWalkSeconds < cool) {
        cool = program.shortenedWalkSeconds;
      }
      exceeds = warm + core + cool > limit;
    }
  }
  final total = warm + core + cool;

  PlanSegment seg(PlanSegmentKind kind, int seconds) => PlanSegment(
    kind: kind,
    minutes: (seconds / 60).round(),
    seconds: seconds,
  );

  final start = week.start;
  return (
    unit: PlanUnit(
      day: DateTime.utc(start.year, start.month, start.day + weekday - 1),
      kind: PlanUnitKind.walkRun,
      phase: week.phase,
      weekIndex: week.index,
      minutes: (total / 60).round(),
      segments: [
        seg(PlanSegmentKind.warmUp, warm),
        for (final s in steps)
          seg(
            s.kind == WalkRunStepKind.run
                ? PlanSegmentKind.run
                : PlanSegmentKind.walk,
            s.seconds,
          ),
        seg(PlanSegmentKind.coolDown, cool),
      ],
      method: walkRunMethod,
      methodVersion: program.version,
    ),
    exceeds: exceeds,
  );
}
