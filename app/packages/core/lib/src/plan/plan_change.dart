import 'plan_parameters.dart';
import 'plan_unit.dart';

/// Wochenzeit einer Woche vor und nach der Neuberechnung.
class WeekMinutesChange {
  const WeekMinutesChange(this.weekIndex, this.oldMinutes, this.newMinutes);

  final int weekIndex;
  final int oldMinutes;
  final int newMinutes;

  /// Betrag der Änderung im Verhältnis zur alten Wochenzeit (PAR-204);
  /// bei alter Wochenzeit 0 und neuer > 0 unendlich.
  double get relative {
    final diff = (newMinutes - oldMinutes).abs();
    if (diff == 0) return 0;
    return oldMinutes == 0 ? double.infinity : diff / oldMinutes;
  }

  Map<String, Object?> toJson() => {
    'weekIndex': weekIndex,
    'oldMinutes': oldMinutes,
    'newMinutes': newMinutes,
  };
}

/// Eine geänderte Einheit; `oldUnit` oder `newUnit` ist `null`, wenn sie
/// entfällt beziehungsweise neu ist.
class UnitChange {
  const UnitChange(this.day, this.oldUnit, this.newUnit);

  final DateTime day;
  final PlanUnit? oldUnit;
  final PlanUnit? newUnit;

  /// Wechsel zwischen hart, locker und Ruhetag oder Einheit entfällt bzw.
  /// kommt hinzu (PAR-204).
  bool get changesClass => _class(oldUnit) != _class(newUnit);

  Map<String, Object?> toJson() => {
    'day':
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}',
    'old': oldUnit == null
        ? null
        : {'kind': oldUnit!.kind.name, 'minutes': oldUnit!.minutes},
    'new': newUnit == null
        ? null
        : {'kind': newUnit!.kind.name, 'minutes': newUnit!.minutes},
  };
}

/// 0 hart, 1 locker (einschließlich langer Lauf, Geh-Lauf), 2 Ruhetag,
/// 3 keine Einheit.
int _class(PlanUnit? u) => u == null
    ? 3
    : u.kind == PlanUnitKind.rest
    ? 2
    : u.isHard
    ? 0
    : 1;

/// Zusammenfassung einer Neuberechnung (ADR-0010 Punkt 5, PAR-204).
class PlanChangeSummary {
  const PlanChangeSummary({
    required this.weeks,
    required this.headline,
    required this.changedUnits,
    required this.isLarger,
  });

  /// Wochen, deren Wochenzeit sich geändert hat.
  final List<WeekMinutesChange> weeks;

  /// Die Woche mit der größten relativen Änderung (bei Gleichstand die
  /// frühere): „Wochenzeit alt → neu“; `null` ohne Änderung.
  final WeekMinutesChange? headline;

  /// Geänderte Einheiten nach Tag.
  final List<UnitChange> changedUnits;

  /// „Größer“ nach PAR-204: Wochenzeit mindestens 10 % anders in einer Woche,
  /// oder eine Einheit wechselt zwischen hart, locker und Ruhetag oder entfällt.
  final bool isLarger;

  bool get isEmpty => changedUnits.isEmpty && weeks.isEmpty;

  /// Für `plans.summary`: höchstens [maxUnits] Einheiten (ADR-0010 Punkt 5).
  Map<String, Object?> toJson({int maxUnits = 5}) => {
    'headline': headline?.toJson(),
    'larger': isLarger,
    'changedUnitCount': changedUnits.length,
    'changedUnits': [for (final c in changedUnits.take(maxUnits)) c.toJson()],
  };
}

bool _sameContent(PlanUnit a, PlanUnit b) {
  if (a.kind != b.kind || a.minutes != b.minutes || a.phase != b.phase) {
    return false;
  }
  if (a.segments.length != b.segments.length) return false;
  for (var i = 0; i < a.segments.length; i++) {
    final x = a.segments[i], y = b.segments[i];
    if (x.kind != y.kind || x.minutes != y.minutes) return false;
    final ix = x.intensity, iy = y.intensity;
    if ((ix == null) != (iy == null)) return false;
    if (ix != null &&
        (ix.rpeMin != iy!.rpeMin ||
            ix.rpeMax != iy.rpeMax ||
            ix.paceFastSecondsPerKm != iy.paceFastSecondsPerKm ||
            ix.paceSlowSecondsPerKm != iy.paceSlowSecondsPerKm ||
            ix.basisCode != iy.basisCode)) {
      return false;
    }
  }
  return true;
}

/// Vergleicht die künftigen Einheiten vor und nach einer Neuberechnung.
/// Beide Listen betreffen denselben Zeitraum (ab demselben „heute“); je Tag
/// zählt die erste Einheit.
PlanChangeSummary summarizeChange(
  List<PlanUnit> oldUnits,
  List<PlanUnit> newUnits, {
  PlanParameters parameters = const PlanParameters(),
}) {
  final oldByDay = <DateTime, PlanUnit>{};
  for (final u in oldUnits) {
    oldByDay.putIfAbsent(u.day, () => u);
  }
  final newByDay = <DateTime, PlanUnit>{};
  for (final u in newUnits) {
    newByDay.putIfAbsent(u.day, () => u);
  }
  final days = {...oldByDay.keys, ...newByDay.keys}.toList()..sort();
  final changes = <UnitChange>[];
  for (final d in days) {
    final o = oldByDay[d], n = newByDay[d];
    if (o != null && n != null && _sameContent(o, n)) continue;
    changes.add(UnitChange(d, o, n));
  }

  final oldWeek = <int, int>{}, newWeek = <int, int>{};
  for (final u in oldByDay.values) {
    oldWeek[u.weekIndex] = (oldWeek[u.weekIndex] ?? 0) + u.minutes;
  }
  for (final u in newByDay.values) {
    newWeek[u.weekIndex] = (newWeek[u.weekIndex] ?? 0) + u.minutes;
  }
  final weekIds = {...oldWeek.keys, ...newWeek.keys}.toList()..sort();
  final weeks = <WeekMinutesChange>[];
  for (final w in weekIds) {
    final c = WeekMinutesChange(w, oldWeek[w] ?? 0, newWeek[w] ?? 0);
    if (c.oldMinutes != c.newMinutes) weeks.add(c);
  }
  WeekMinutesChange? headline;
  for (final w in weeks) {
    if (headline == null || w.relative > headline.relative) headline = w;
  }
  final larger =
      weeks.any((w) => w.relative >= parameters.largeChangeShare) ||
      changes.any((c) => c.changesClass);
  return PlanChangeSummary(
    weeks: weeks,
    headline: headline,
    changedUnits: changes,
    isLarger: larger,
  );
}
