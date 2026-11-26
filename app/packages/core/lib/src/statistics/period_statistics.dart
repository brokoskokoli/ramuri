import 'period.dart';
import 'run_figures.dart';
import '../recalculation/statistics_parameters.dart';

/// Einheit: Meter je Kilometer, Mikrosekunden je Sekunde.
const double _metersPerKilometer = 1000;
const double _microsPerSecond = 1e6;

/// Ein Wert der Statistik. [value] ist `null`, wenn kein Lauf des Zeitraums
/// ihn liefert (FR-0057: nicht verfügbar, nie 0). Liefern ihn nur einige Läufe,
/// ist [isPartial] gesetzt; die Zahlen sagen, wie viele. [runsTotal] ist bei
/// Umfang und Geschwindigkeit die Zahl der Läufe, bei Puls, Zonen und TRIMP die
/// aller Einheiten samt Sporteinheiten (FR-0043, Festlegung FR-0221).
class StatValue<T> {
  const StatValue({
    required this.value,
    required this.runsWithValue,
    required this.runsTotal,
  });

  final T? value;
  final int runsWithValue;
  final int runsTotal;

  bool get isAvailable => value != null;
  bool get isPartial => value != null && runsWithValue < runsTotal;
}

/// Kennzahlen eines Zeitraums (FR-0043, soweit die liefernde Funktion in
/// Phase 1 liegt). Summen sind die Summen der Einzelläufe.
class PeriodStatistics {
  PeriodStatistics({
    required this.period,
    required List<RunFigures> units,
    required List<RunFigures> runs,
    required this.trainingDays,
    required this.distanceMeters,
    required this.movingTime,
    required this.totalTime,
    required this.averagePaceSecondsPerKm,
    required this.bestPaceSecondsPerKm,
    required this.lapCount,
    required this.heartRateAverageBpm,
    required this.heartRateMaxBpm,
    required this.zoneTimes,
    required this.belowZone1Time,
    required this.trimpPoints,
    required this.trimpIncomplete,
  }) : units = List.unmodifiable(units),
       runs = List.unmodifiable(runs);

  String get method => statisticsMethod;
  int get methodVersion => statisticsMethodVersion;

  final StatisticsPeriod period;

  /// Alle Einheiten des Zeitraums (Läufe und Sporteinheiten, FR-0221), nach
  /// Laufende aufsteigend. Aus ihnen kommen Puls, Zonen und TRIMP.
  final List<RunFigures> units;

  /// Nur die Läufe (GPS und Laufband) aus [units], gleiche Reihenfolge. Aus
  /// ihnen kommen Umfang, Geschwindigkeit und Runden.
  final List<RunFigures> runs;

  /// Trainingshäufigkeit: Zahl der Läufe, ohne Sporteinheiten. Ein Zeitraum
  /// ohne Läufe hat 0 (das ist gezählt, nicht fehlend).
  int get runCount => runs.length;

  /// Zahl der verschiedenen Kalendertage mit mindestens einem Lauf; ein Tag
  /// nur mit Sporteinheit zählt nicht.
  final int trainingDays;

  final StatValue<double> distanceMeters;
  final StatValue<Duration> movingTime;
  final StatValue<Duration> totalTime;

  /// Strecke / Zeit über die Läufe, die beides haben (nicht Mittel der Paces).
  final StatValue<double> averagePaceSecondsPerKm;

  /// Schnellste Bestpace eines Laufs des Zeitraums.
  final StatValue<double> bestPaceSecondsPerKm;

  /// Summe der Runden aller Läufe.
  final StatValue<int> lapCount;

  /// Mittel der Durchschnittspulse der Läufe, gewichtet nach der Zeit mit
  /// bekanntem Puls (nicht nach der Länge des Laufs).
  final StatValue<double> heartRateAverageBpm;
  final StatValue<int> heartRateMaxBpm;

  /// Summe der Zeit je Zone (Index 0 = Zone 1) und unter Zone 1.
  final StatValue<List<Duration>> zoneTimes;
  final StatValue<Duration> belowZone1Time;

  /// Summe der Edwards-TRIMP-Punkte.
  final StatValue<double> trimpPoints;

  /// Mindestens ein Lauf trägt TRIMP mit unvollständiger Pulsabdeckung.
  final bool trimpIncomplete;
}

/// Rechnet die Statistik von [period] aus den Einheiten in [all]; Einheiten
/// außerhalb des Zeitraums werden ausgelassen. Umfang, Geschwindigkeit und
/// Runden zählen nur Läufe ([RunFigures.isRunning]), Puls, Zonen und TRIMP alle
/// Einheiten (FR-0043, Festlegung FR-0221). Wirft [ArgumentError] bei doppelter
/// Lauf-Id.
PeriodStatistics computePeriodStatistics(
  StatisticsPeriod period,
  Iterable<RunFigures> all,
) {
  final seen = <int>{};
  final units = <RunFigures>[];
  for (final r in all) {
    if (!seen.add(r.runId)) {
      throw ArgumentError.value(r.runId, 'all', 'doppelte Lauf-Id');
    }
    if (period.contains(id: r.runId, day: r.day)) units.add(r);
  }
  units.sort((a, b) {
    final c = a.endedAt.compareTo(b.endedAt);
    return c != 0 ? c : a.runId.compareTo(b.runId);
  });
  final runs = [
    for (final u in units)
      if (u.isRunning) u,
  ];
  final n = runs.length;
  final nUnits = units.length;

  StatValue<T> sumOf<T>(
    List<RunFigures> over,
    T? Function(RunFigures) pick,
    T Function(T, T) add,
  ) {
    T? total;
    var count = 0;
    for (final r in over) {
      final v = pick(r);
      if (v == null) continue;
      total = total == null ? v : add(total, v);
      count++;
    }
    return StatValue(
      value: total,
      runsWithValue: count,
      runsTotal: over.length,
    );
  }

  StatValue<T> sum<T>(T? Function(RunFigures) pick, T Function(T, T) add) =>
      sumOf(runs, pick, add);
  StatValue<T> sumUnits<T>(
    T? Function(RunFigures) pick,
    T Function(T, T) add,
  ) => sumOf(units, pick, add);

  Duration plus(Duration a, Duration b) => a + b;

  // Durchschnittspace: nur Läufe mit Strecke und Zeit; beides aus denselben.
  var paceMeters = 0.0;
  var paceMicros = 0;
  var paceRuns = 0;
  for (final r in runs) {
    final d = r.distanceMeters;
    final t = r.paceTime;
    if (r.averagePaceSecondsPerKm == null) continue;
    paceMeters += d!;
    paceMicros += t!.inMicroseconds;
    paceRuns++;
  }

  // Puls: Mittel der Durchschnittspulse, gewichtet nach der Zeit mit Puls.
  var hrSum = 0.0;
  var hrMicros = 0;
  var hrRuns = 0;
  for (final r in units) {
    final avg = r.heartRateAverageBpm;
    final t = r.heartRateTime?.inMicroseconds ?? 0;
    if (avg == null || t <= 0) continue;
    hrSum += avg * t;
    hrMicros += t;
    hrRuns++;
  }

  // Zonen: nur Läufe mit derselben Zonenzahl wie der erste Lauf mit Zonen.
  List<Duration>? zoneTotal;
  var zoneRuns = 0;
  var belowMicros = 0;
  var belowRuns = 0;
  for (final r in units) {
    final z = r.zoneTimes;
    if (z == null) continue;
    zoneTotal ??= List.filled(z.length, Duration.zero);
    if (z.length != zoneTotal.length) continue;
    for (var i = 0; i < z.length; i++) {
      zoneTotal[i] += z[i];
    }
    zoneRuns++;
    // Zeit unter Zone 1 nur aus denselben Läufen wie die Zonen.
    final below = r.belowZone1Time;
    if (below != null) {
      belowMicros += below.inMicroseconds;
      belowRuns++;
    }
  }

  return PeriodStatistics(
    period: period,
    units: units,
    runs: runs,
    trainingDays: {for (final r in runs) r.day}.length,
    distanceMeters: sum<double>((r) => r.distanceMeters, (a, b) => a + b),
    movingTime: sum<Duration>((r) => r.movingTime, plus),
    totalTime: sum<Duration>((r) => r.totalTime, plus),
    averagePaceSecondsPerKm: StatValue(
      value: paceRuns == 0 || !(paceMeters > 0)
          ? null
          : paceMicros / _microsPerSecond / (paceMeters / _metersPerKilometer),
      runsWithValue: paceRuns,
      runsTotal: n,
    ),
    bestPaceSecondsPerKm: sum<double>(
      (r) => r.bestPaceSecondsPerKm,
      (a, b) => a < b ? a : b,
    ),
    lapCount: sum<int>((r) => r.lapCount, (a, b) => a + b),
    heartRateAverageBpm: StatValue(
      value: hrMicros == 0 ? null : hrSum / hrMicros,
      runsWithValue: hrRuns,
      runsTotal: nUnits,
    ),
    heartRateMaxBpm: sumUnits<int>(
      (r) => r.heartRateMaxBpm,
      (a, b) => a > b ? a : b,
    ),
    zoneTimes: StatValue(
      value: zoneTotal == null ? null : List.unmodifiable(zoneTotal),
      runsWithValue: zoneRuns,
      runsTotal: nUnits,
    ),
    belowZone1Time: StatValue(
      value: belowRuns == 0 ? null : Duration(microseconds: belowMicros),
      runsWithValue: belowRuns,
      runsTotal: nUnits,
    ),
    trimpPoints: sumUnits<double>((r) => r.trimpPoints, (a, b) => a + b),
    trimpIncomplete: units.any(
      (r) => r.trimpPoints != null && r.trimpIncomplete,
    ),
  );
}

/// Vergleich einer Woche oder eines Monats mit dem vorigen (FR-0043
/// „Entwicklung“). Unterschiede sind `null`, wenn eine Seite den Wert nicht hat.
class PeriodComparison {
  PeriodComparison({required this.current, required this.previous});

  final PeriodStatistics current;
  final PeriodStatistics previous;

  /// Aktuell minus vorher.
  double? get distanceDeltaMeters =>
      _delta(current.distanceMeters.value, previous.distanceMeters.value);
  Duration? get movingTimeDelta {
    final a = current.movingTime.value;
    final b = previous.movingTime.value;
    return a == null || b == null ? null : a - b;
  }

  int get runCountDelta => current.runCount - previous.runCount;

  static double? _delta(double? a, double? b) =>
      a == null || b == null ? null : a - b;
}

/// Vergleich mit dem vorigen gleichartigen Zeitraum; `null` für Lauf und freien
/// Zeitraum (kein Vorgänger definiert).
PeriodComparison? comparePeriod(
  StatisticsPeriod period,
  Iterable<RunFigures> all,
) {
  final before = period.previous();
  if (before == null) return null;
  final runs = all.toList(growable: false);
  return PeriodComparison(
    current: computePeriodStatistics(period, runs),
    previous: computePeriodStatistics(before, runs),
  );
}
