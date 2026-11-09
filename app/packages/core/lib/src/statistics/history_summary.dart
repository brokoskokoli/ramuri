import 'period.dart';
import 'period_statistics.dart';
import 'run_figures.dart';
import 'statistics_parameters.dart';

/// Zeitraum über der Liste des Verlaufs (FR-0212).
enum HistoryRange { week, month, year, all }

/// Der Zeitraum der Statistik, den [range] am Tag [today] (`JJJJ-MM-TT`, lokal,
/// K21) meint: die Kalenderwoche, der Monat, das Kalenderjahr von [today]; „Alle“
/// reicht vom ersten Lauftag in [runs] (sonst [today]) bis [today] bzw. zum
/// letzten Lauftag, falls der später liegt. Woche und Monat sind die der
/// Statistik (FR-0044), das Jahr und „Alle“ sind freie Zeiträume derselben.
StatisticsPeriod historyPeriod(
  HistoryRange range,
  String today, {
  Iterable<RunFigures> runs = const [],
  StatisticsParameters parameters = const StatisticsParameters(),
}) {
  switch (range) {
    case HistoryRange.week:
      return StatisticsPeriod.weekOf(today, parameters: parameters);
    case HistoryRange.month:
      return StatisticsPeriod.monthOf(today);
    case HistoryRange.year:
      final y = today.substring(0, 4);
      return StatisticsPeriod.custom(from: '$y-01-01', to: '$y-12-31');
    case HistoryRange.all:
      var first = today;
      var last = today;
      for (final r in runs) {
        if (r.day.compareTo(first) < 0) first = r.day;
        if (r.day.compareTo(last) > 0) last = r.day;
      }
      return StatisticsPeriod.custom(from: first, to: last);
  }
}

/// Summen über der Liste: Strecke, Zeit, Zahl der Läufe. Sie sind die der
/// Statistik für denselben Zeitraum ([statistics] ist genau
/// `computePeriodStatistics`), keine zweite Rechnung.
class HistoryTotals {
  HistoryTotals({required this.range, required this.statistics});

  final HistoryRange range;
  final PeriodStatistics statistics;

  StatisticsPeriod get period => statistics.period;

  /// `null`, wenn kein Lauf des Zeitraums eine Strecke hat (nie 0).
  double? get distanceMeters => statistics.distanceMeters.value;

  /// Bewegungszeit; `null` ohne Wert (nie 0).
  Duration? get movingTime => statistics.movingTime.value;
  Duration? get totalTime => statistics.totalTime.value;

  /// Zahl der Läufe (0 ist gezählt, nicht fehlend).
  int get runCount => statistics.runCount;
}

HistoryTotals historyTotals(
  HistoryRange range,
  String today,
  Iterable<RunFigures> runs, {
  StatisticsParameters parameters = const StatisticsParameters(),
}) {
  final all = runs.toList(growable: false);
  return HistoryTotals(
    range: range,
    statistics: computePeriodStatistics(
      historyPeriod(range, today, runs: all, parameters: parameters),
      all,
    ),
  );
}

/// Kennung der Wochengruppe; die Texte macht die Oberfläche.
enum WeekGroupKind { thisWeek, lastWeek, dated }

class WeekGroup<T> {
  WeekGroup({required this.kind, required this.week, required List<T> items})
    : items = List.unmodifiable(items);

  final WeekGroupKind kind;

  /// Die Kalenderwoche (Wochenbeginn nach [StatisticsParameters.firstDayOfWeek]);
  /// [StatisticsPeriod.firstDay] ist der Tag für die Datumsüberschrift.
  final StatisticsPeriod week;
  final List<T> items;
}

/// Gruppiert [items] nach Kalenderwochen, neueste Woche zuerst, darin neuester
/// Eintrag zuerst ([endedAtOf], bei Gleichheit unverändert). Die Woche von
/// [today] heißt [WeekGroupKind.thisWeek], die davor [WeekGroupKind.lastWeek],
/// alle übrigen [WeekGroupKind.dated]; Wochen ohne Eintrag fehlen.
List<WeekGroup<T>> groupByWeek<T>(
  Iterable<T> items,
  String today, {
  required String Function(T) dayOf,
  required DateTime Function(T) endedAtOf,
  StatisticsParameters parameters = const StatisticsParameters(),
}) {
  final thisWeek = StatisticsPeriod.weekOf(today, parameters: parameters);
  final lastWeek = thisWeek.previous()!;
  final byWeek = <String, List<T>>{};
  final weeks = <String, StatisticsPeriod>{};
  for (final item in items) {
    final w = StatisticsPeriod.weekOf(dayOf(item), parameters: parameters);
    weeks[w.firstDay!] = w;
    (byWeek[w.firstDay!] ??= []).add(item);
  }
  final keys = weeks.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final k in keys)
      WeekGroup<T>(
        kind: k == thisWeek.firstDay
            ? WeekGroupKind.thisWeek
            : k == lastWeek.firstDay
            ? WeekGroupKind.lastWeek
            : WeekGroupKind.dated,
        week: weeks[k]!,
        items: [...byWeek[k]!]
          ..sort((a, b) => endedAtOf(b).compareTo(endedAtOf(a))),
      ),
  ];
}
