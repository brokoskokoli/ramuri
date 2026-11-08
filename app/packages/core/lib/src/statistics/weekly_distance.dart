import 'period.dart';
import 'period_statistics.dart';
import 'run_figures.dart';
import 'statistics_parameters.dart';

/// Zahl der Wochen der Fortschrittsansicht (FR-0043: Kilometer der letzten 8
/// Wochen).
const int weeklyDistanceWeeks = 8;

/// Eine Woche der Reihe „Kilometer pro Woche“ (FR-0043).
class WeeklyDistance {
  const WeeklyDistance({
    required this.statistics,
    required this.isoWeek,
    required this.isoWeekYear,
  });

  /// Die Wochenstatistik dieser Woche, dieselbe Rechnung wie die Wochenwahl
  /// (`computePeriodStatistics` über `StatisticsPeriod.weekOf`).
  final PeriodStatistics statistics;

  /// ISO-8601-Kalenderwoche (1 bis 53) und ihr Wochenjahr (am Jahreswechsel
  /// kann es vom Kalenderjahr des ersten Tages abweichen).
  final int isoWeek;
  final int isoWeekYear;

  StatisticsPeriod get week => statistics.period;

  /// Strecke wie in der Wochenstatistik, mit [StatValue.isPartial].
  StatValue<double> get distance => statistics.distanceMeters;

  /// Die Woche hat mindestens einen Lauf.
  bool get hasRuns => statistics.runCount > 0;

  /// Strecke der Woche in Metern: 0 ohne Lauf (gezählt, nicht fehlend), `null`
  /// bei Läufen ohne lesbare Strecke (FR-0057: nicht verfügbar, nie 0).
  double? get meters => hasRuns ? distance.value : 0;

  /// Läufe vorhanden, aber keiner liefert eine Strecke.
  bool get isUnavailable => meters == null;
}

/// Die letzten [weeks] Kalenderwochen bis einschließlich der Woche von [today]
/// (`JJJJ-MM-TT`, lokaler Tag), älteste zuerst. Jede Woche kommt vor, auch ohne
/// Lauf. Den Wochenbeginn legt [parameters] fest. Wirft [ArgumentError] bei
/// ungültigem [today] oder [weeks] unter 1.
List<WeeklyDistance> weeklyDistanceSeries(
  String today,
  Iterable<RunFigures> runs, {
  int weeks = weeklyDistanceWeeks,
  StatisticsParameters parameters = const StatisticsParameters(),
}) {
  if (weeks < 1) throw ArgumentError.value(weeks, 'weeks', 'mindestens 1');
  final all = runs.toList(growable: false);
  final periods = <StatisticsPeriod>[
    StatisticsPeriod.weekOf(today, parameters: parameters),
  ];
  while (periods.length < weeks) {
    periods.add(periods.last.previous()!);
  }
  return [
    for (final p in periods.reversed)
      _entry(computePeriodStatistics(p, all), p),
  ];
}

WeeklyDistance _entry(PeriodStatistics s, StatisticsPeriod p) {
  // Donnerstag der ISO-Woche ist ihr Bezug; bei anderem Wochenbeginn der
  // Tag drei nach Wochenbeginn (die Mitte der Woche).
  final first = DateTime.parse('${p.firstDay}T00:00:00Z');
  final mid = first.add(const Duration(days: 3));
  final thursday = mid.add(Duration(days: DateTime.thursday - mid.weekday));
  final jan1 = DateTime.utc(thursday.year);
  final week = thursday.difference(jan1).inDays ~/ 7 + 1;
  return WeeklyDistance(
    statistics: s,
    isoWeek: week,
    isoWeekYear: thursday.year,
  );
}
