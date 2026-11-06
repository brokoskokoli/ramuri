import 'period.dart';
import 'run_figures.dart';
import 'statistics_parameters.dart';

/// Einheit: Meter je Kilometer, Mikrosekunden je Sekunde.
const double _metersPerKilometer = 1000;
const double _microsPerSecond = 1e6;

/// Ein Wert der Statistik. [value] ist `null`, wenn kein Lauf des Zeitraums
/// ihn liefert (FR-0057: nicht verfügbar, nie 0). Liefern ihn nur einige Läufe,
/// ist [isPartial] gesetzt; die Zahlen sagen, wie viele.
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
  }) : runs = List.unmodifiable(runs);

  String get method => statisticsMethod;
  int get methodVersion => statisticsMethodVersion;

  final StatisticsPeriod period;

  /// Die Läufe des Zeitraums, nach Laufende aufsteigend.
  final List<RunFigures> runs;

  /// Trainingshäufigkeit: Zahl der Läufe. Ein Zeitraum ohne Läufe hat 0 (das
  /// ist gezählt, nicht fehlend).
  int get runCount => runs.length;

  /// Zahl der verschiedenen Kalendertage mit mindestens einem Lauf.
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

  /// Mittel aller akzeptierten Pulswerte des Zeitraums (nach Anzahl gewichtet).
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

/// Rechnet die Statistik von [period] aus den Läufen in [all]; Läufe außerhalb
/// des Zeitraums werden ausgelassen. Wirft [ArgumentError] bei doppelter Lauf-Id.
PeriodStatistics computePeriodStatistics(
  StatisticsPeriod period,
  Iterable<RunFigures> all,
) {
  final seen = <int>{};
  final runs = <RunFigures>[];
  for (final r in all) {
    if (!seen.add(r.runId)) {
      throw ArgumentError.value(r.runId, 'all', 'doppelte Lauf-Id');
    }
    if (period.contains(id: r.runId, day: r.day)) runs.add(r);
  }
  runs.sort((a, b) {
    final c = a.endedAt.compareTo(b.endedAt);
    return c != 0 ? c : a.runId.compareTo(b.runId);
  });
  final n = runs.length;

  StatValue<T> sum<T>(T? Function(RunFigures) pick, T Function(T, T) add) {
    T? total;
    var count = 0;
    for (final r in runs) {
      final v = pick(r);
      if (v == null) continue;
      total = total == null ? v : add(total, v);
      count++;
    }
    return StatValue(value: total, runsWithValue: count, runsTotal: n);
  }

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

  // Puls: gewichtetes Mittel über die Anzahl akzeptierter Werte.
  var hrSum = 0.0;
  var hrCount = 0;
  var hrRuns = 0;
  for (final r in runs) {
    final avg = r.heartRateAverageBpm;
    if (avg == null || r.heartRateSampleCount <= 0) continue;
    hrSum += avg * r.heartRateSampleCount;
    hrCount += r.heartRateSampleCount;
    hrRuns++;
  }

  // Zonen: nur Läufe mit derselben Zonenzahl wie der erste Lauf mit Zonen.
  List<Duration>? zoneTotal;
  var zoneRuns = 0;
  for (final r in runs) {
    final z = r.zoneTimes;
    if (z == null) continue;
    zoneTotal ??= List.filled(z.length, Duration.zero);
    if (z.length != zoneTotal.length) continue;
    for (var i = 0; i < z.length; i++) {
      zoneTotal[i] += z[i];
    }
    zoneRuns++;
  }

  return PeriodStatistics(
    period: period,
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
      value: hrCount == 0 ? null : hrSum / hrCount,
      runsWithValue: hrRuns,
      runsTotal: n,
    ),
    heartRateMaxBpm: sum<int>(
      (r) => r.heartRateMaxBpm,
      (a, b) => a > b ? a : b,
    ),
    zoneTimes: StatValue(
      value: zoneTotal == null ? null : List.unmodifiable(zoneTotal),
      runsWithValue: zoneRuns,
      runsTotal: n,
    ),
    belowZone1Time: sum<Duration>((r) => r.belowZone1Time, plus),
    trimpPoints: sum<double>((r) => r.trimpPoints, (a, b) => a + b),
    trimpIncomplete: runs.any(
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
  Iterable<RunFigures> all, {
  StatisticsParameters parameters = const StatisticsParameters(),
}) {
  final before = period.previous(firstDayOfWeek: parameters.firstDayOfWeek);
  if (before == null) return null;
  final runs = all.toList(growable: false);
  return PeriodComparison(
    current: computePeriodStatistics(period, runs),
    previous: computePeriodStatistics(before, runs),
  );
}
