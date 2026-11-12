import '../goals/training_goal.dart';
import '../prediction/reference_performance.dart' show calendarDay;
import 'plan_parameters.dart';

/// Phase einer Planwoche (FR-0141). Weitere Phasen sind nicht vorgesehen.
enum PlanPhase { entry, build, reduction }

/// Art der Woche im Verlauf.
enum WeekKind {
  /// Geh-Lauf-Abfolge (PAR-065); die Zeit legt die Abfolge fest, nicht dieser
  /// Verlauf. [PlanWeek.minutes] ist `null`.
  walkRun,

  /// Die Wochenzeit steigt (PAR-193).
  climbing,

  /// Regler oder Zielspitze erreicht, die Wochenzeit bleibt (PAR-196).
  holding,

  /// Leichtere Woche (PAR-194).
  lighter,

  /// Reduktion vor dem Zieltermin (PAR-199).
  reduction,
}

class PlanWeek {
  const PlanWeek({
    required this.index,
    required this.start,
    required this.minutes,
    required this.phase,
    required this.kind,
    int? baseMinutes,
  }) : baseMinutes = baseMinutes ?? minutes;

  /// Nummer der Woche ab dem Anker (0 = Ankerwoche).
  final int index;

  /// Montag der Woche (Kalendertag, UTC-Mitternacht wie `calendarDay`).
  final DateTime start;

  /// Wochenzeit in Minuten, ganzzahlig; `null` in der Geh-Lauf-Abfolge.
  final int? minutes;
  final PlanPhase phase;
  final WeekKind kind;

  /// Wochenzeit ohne die Verringerung einer leichteren Woche (PAR-194): der
  /// Wert, von dem es danach weitergeht; sonst gleich [minutes]. `null` in
  /// der Geh-Lauf-Abfolge.
  final int? baseMinutes;
}

/// Verlauf der Wochenzeit ab der Woche von „heute“.
class WeeklyTimeResult {
  const WeeklyTimeResult({
    required this.weeks,
    required this.levelMinutes,
    required this.dampingFactor,
    required this.reachedLevelWeek,
  });

  final List<PlanWeek> weeks;

  /// Höhe, auf der der Plan hält: Regler oder Zielspitze (PAR-196), mindestens
  /// die Startwochenzeit, höchstens der Regler.
  final int levelMinutes;

  /// Faktor auf die Steigerung bei fernem Ziel (PAR-199); 1 = ungedämpft.
  final double dampingFactor;

  /// Wochennummer (ab Anker), in der [levelMinutes] erstmals erreicht ist;
  /// `null`, wenn nicht vor Ende des Verlaufs bzw. der Reduktion.
  final int? reachedLevelWeek;
}

/// Wochenzeit, bei der der längste Lauf [longestRunMinutes] erreicht (PAR-195,
/// PAR-205): Zielspitze als Wochenzeit. Aufgerundet.
int peakWeeklyMinutes({
  required int longestRunMinutes,
  required int runDays,
  PlanParameters parameters = const PlanParameters(),
}) => (longestRunMinutes / parameters.longestRunShare(runDays)).ceil();

/// Kalendertag im Plan als UTC-Mitternacht, die einzige Stelle für `src/plan`.
/// Ein Wert, der schon UTC-Mitternacht ist, ist ein Kalendertag und bleibt
/// unverändert; `calendarDay` würde ihn westlich von UTC auf den Vortag
/// legen. Alles andere (lokale Zeit, UTC-Zeitpunkt) zählt als Zeitpunkt und
/// wird wie bei `calendarDay` im Ortstag gelesen.
DateTime planDay(DateTime t) {
  if (t.isUtc &&
      t.hour == 0 &&
      t.minute == 0 &&
      t.second == 0 &&
      t.millisecond == 0 &&
      t.microsecond == 0) {
    return t;
  }
  return calendarDay(t);
}

DateTime _monday(DateTime day) {
  final d = planDay(day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}

int _weeksBetween(DateTime from, DateTime to) =>
    to.difference(from).inDays ~/ 7;

/// Rundung der Wochenzeit: die einzige Stelle (Minuten ganzzahlig).
int _toMinutes(double value) => value.round();

/// Verlauf der Wochenzeit (PAR-192 bis PAR-196, PAR-199, FR-0141, FR-0148
/// bis FR-0150). Rein: kein `DateTime.now()`, kein Zufall.
///
/// - [startMinutes]: Wochenzeit der ersten Laufwoche (PAR-192), höchstens
///   [capMinutes].
/// - [capMinutes]: Regler (PAR-196).
/// - [peakMinutes]: Zielspitze als Wochenzeit (PAR-205, siehe
///   [peakWeeklyMinutes]); `null` beim offenen Ziel.
/// - [anchor]: Anker der Wochenzählung (ein Neustart setzt einen neuen).
/// - [walkRunWeeks]: Länge der Geh-Lauf-Abfolge (Startfall „nein“, PAR-192,
///   PAR-065), 0 sonst. Die Laufwochen mit [startMinutes] beginnen danach;
///   PAR-194 zählt erst ab da.
/// - [targetDate] mit [distance]: Zieltermin; das Ende des Verlaufs ist die
///   Woche des Termins, die letzten Wochen sind die Reduktion (PAR-199).
///   Ohne Datum läuft der Plan [PlanParameters.openHorizonWeeks] Wochen
///   fort.
/// - [lighterOffset]: Wochen, die PAR-194 schon vor dem Anker gezählt hat
///   (Neustart nach Anpassung: die Zählung läuft weiter).
WeeklyTimeResult planWeeklyTime({
  required int startMinutes,
  required int capMinutes,
  required DateTime anchor,
  required DateTime today,
  int? peakMinutes,
  GoalDistance? distance,
  DateTime? targetDate,
  int walkRunWeeks = 0,
  int lighterOffset = 0,
  PlanParameters parameters = const PlanParameters(),
}) {
  if (lighterOffset < 0) {
    throw ArgumentError.value(lighterOffset, 'lighterOffset', 'nicht negativ');
  }
  if (startMinutes < 1) {
    throw ArgumentError.value(startMinutes, 'startMinutes', 'mindestens 1');
  }
  if (capMinutes < 1) {
    throw ArgumentError.value(capMinutes, 'capMinutes', 'mindestens 1');
  }
  if (walkRunWeeks < 0) {
    throw ArgumentError.value(walkRunWeeks, 'walkRunWeeks', 'nicht negativ');
  }
  final p = parameters;
  final anchorMonday = _monday(anchor);
  final first = walkRunWeeks;
  final start = startMinutes < capMinutes ? startMinutes : capMinutes;
  final level = peakMinutes == null
      ? capMinutes
      : _clamp(peakMinutes, start, capMinutes);
  final todayWeek = _weeksBetween(anchorMonday, _monday(today));
  final firstOut = todayWeek < 0 ? 0 : todayWeek;

  final int last;
  int? reductionStart;
  double reductionShare = 0;
  if (targetDate != null) {
    last = _weeksBetween(anchorMonday, _monday(targetDate));
    if (distance != null) {
      reductionStart = last - p.reductionWeeks(distance) + 1;
      if (reductionStart < first) reductionStart = first;
      reductionShare = p.reductionShare(distance);
    }
  } else {
    last = firstOut + p.openHorizonWeeks - 1;
  }
  if (last < firstOut) {
    return WeeklyTimeResult(
      weeks: const [],
      levelMinutes: level,
      dampingFactor: 1,
      reachedLevelWeek: null,
    );
  }
  final buildEnd = (reductionStart ?? last + 1) - 1; // letzte Aufbauwoche

  var damping = 1.0;
  if (reductionStart != null && peakMinutes != null) {
    final peakWeek = reductionStart - p.peakLeadWeeks;
    final undamped = _arrival(
      start,
      level,
      first,
      buildEnd,
      1,
      p,
      lighterOffset,
    );
    if (undamped != null && undamped < peakWeek) {
      var lo = 0.0, hi = 1.0;
      for (var i = 0; i < p.dampingIterations; i++) {
        final mid = (lo + hi) / 2;
        final a = _arrival(
          start,
          level,
          first,
          buildEnd,
          mid,
          p,
          lighterOffset,
        );
        if (a != null && a <= peakWeek) {
          hi = mid;
        } else {
          lo = mid;
        }
      }
      damping = hi;
    }
  }

  final base = _bases(start, level, first, buildEnd, damping, p, lighterOffset);
  final reached = _firstReached(base, level, first);
  final entryEnd = walkRunWeeks > 0 ? walkRunWeeks : p.entryWeeks;
  // Wochenzeit der Reduktion: Bezug ist der letzte Aufbauwert (PAR-199).
  final reductionBase = base.isEmpty ? start.toDouble() : base.last;

  final weeks = <PlanWeek>[];
  for (var i = firstOut; i <= last; i++) {
    final monday = anchorMonday.add(Duration(days: 7 * i));
    if (i < first) {
      weeks.add(
        PlanWeek(
          index: i,
          start: monday,
          minutes: null,
          phase: PlanPhase.entry,
          kind: WeekKind.walkRun,
        ),
      );
      continue;
    }
    final inReduction = reductionStart != null && i >= reductionStart;
    final int minutes;
    final WeekKind kind;
    if (inReduction) {
      minutes = _toMinutes(reductionBase * (1 - reductionShare));
      kind = WeekKind.reduction;
    } else {
      final b = base[i - first];
      final lighter = (i - first + 1 + lighterOffset) % p.lighterWeekEvery == 0;
      if (lighter) {
        minutes = _toMinutes(b * (1 - p.lighterWeekReduction));
        kind = WeekKind.lighter;
      } else {
        minutes = _toMinutes(b);
        kind = b >= level ? WeekKind.holding : WeekKind.climbing;
      }
    }
    weeks.add(
      PlanWeek(
        index: i,
        start: monday,
        minutes: minutes,
        baseMinutes: inReduction ? minutes : _toMinutes(base[i - first]),
        phase: inReduction
            ? PlanPhase.reduction
            : i < entryEnd
            ? PlanPhase.entry
            : PlanPhase.build,
        kind: kind,
      ),
    );
  }
  return WeeklyTimeResult(
    weeks: weeks,
    levelMinutes: level,
    dampingFactor: damping,
    reachedLevelWeek: reached,
  );
}

int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

/// Steigerung je Woche nach der Höhe der Vorwoche (PAR-193), mal [damping].
double _rate(double minutes, double damping, PlanParameters p) =>
    (minutes < p.midThresholdMinutes
        ? p.rateBelowMid
        : minutes < p.highThresholdMinutes
        ? p.rateMid
        : p.rateHigh) *
    damping;

/// Grundwerte der Aufbauwochen von [first] bis [buildEnd], ohne leichtere
/// Wochen: In einer leichteren Woche steigt der Grundwert nicht (PAR-194), danach
/// geht es vom Wert davor weiter.
List<double> _bases(
  int start,
  int level,
  int first,
  int buildEnd,
  double damping,
  PlanParameters p, [
  int lighterOffset = 0,
]) {
  final out = <double>[];
  for (var i = first; i <= buildEnd; i++) {
    if (i == first) {
      out.add(start.toDouble());
      continue;
    }
    final prev = out.last;
    final lighter = (i - first + 1 + lighterOffset) % p.lighterWeekEvery == 0;
    if (lighter || prev >= level) {
      out.add(prev);
    } else {
      final next = prev * (1 + _rate(prev, damping, p));
      out.add(next > level ? level.toDouble() : next);
    }
  }
  return out;
}

int? _arrival(
  int start,
  int level,
  int first,
  int buildEnd,
  double damping,
  PlanParameters p, [
  int lighterOffset = 0,
]) => _firstReached(
  _bases(start, level, first, buildEnd, damping, p, lighterOffset),
  level,
  first,
);

int? _firstReached(List<double> base, int level, int first) {
  for (var k = 0; k < base.length; k++) {
    if (base[k] >= level) return first + k;
  }
  return null;
}
