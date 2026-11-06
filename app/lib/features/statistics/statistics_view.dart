import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/unit_format.dart';
import 'fitness_section.dart' show reasonText;

/// Eine Zeile „Name – Wert“; Beschriftung und Wert werden zusammen vorgelesen.
class StatRow extends StatelessWidget {
  StatRow({
    required this.id,
    required this.label,
    required this.value,
    this.note,
  }) : super(key: Key(id));

  /// Kennung für Tests: Zeile `id`, Wert `id_value`.
  final String id;
  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: Text(label, style: theme.bodyMedium)),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    key: Key('${id}_value'),
                    textAlign: TextAlign.end,
                    style: theme.titleMedium,
                  ),
                  if (note != null)
                    Text(
                      note!,
                      textAlign: TextAlign.end,
                      style: theme.bodySmall,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Überschrift eines Abschnitts (für die Bedienungshilfe als Überschrift).
class StatHeading extends StatelessWidget {
  const StatHeading(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    ),
  );
}

/// Kennzahlen des Zeitraums [period] aus den bereits gelesenen [overviews]
/// (FR-0043). Bei einem einzelnen Lauf kommen Bestpace und Runden aus der
/// Zusammenfassung dieses Laufs.
class PeriodStatisticsView extends StatefulWidget {
  const PeriodStatisticsView({
    super.key,
    required this.period,
    required this.overviews,
    required this.formatter,
    required this.session,
    required this.clock,
    required this.offload,
  });

  final StatisticsPeriod period;
  final List<RunOverview> overviews;
  final UnitFormatter formatter;
  final StorageSession session;
  final Clock clock;
  final Offload offload;

  @override
  State<PeriodStatisticsView> createState() => _PeriodStatisticsViewState();
}

class _PeriodStatisticsViewState extends State<PeriodStatisticsView> {
  late final Future<RunSummary?> _single = _loadSingle();

  Future<RunSummary?> _loadSingle() async {
    final id = widget.period.runId;
    if (id == null) return null;
    try {
      return await RunSummaryService(
        session: widget.session,
        clock: widget.clock,
        offload: widget.offload,
      ).load(id);
    } on Object {
      // Ohne Zusammenfassung bleiben Bestpace und Runden „nicht verfügbar“.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final figures = [for (final o in widget.overviews) o.toFigures()];
    final stats = computePeriodStatistics(period, figures);
    final comparison = comparePeriod(period, figures);
    final inPeriod = [
      for (final o in widget.overviews)
        if (period.contains(id: o.run.id, day: o.toFigures().day)) o,
    ];
    if (period.runId == null) {
      return _Body(
        stats: stats,
        comparison: comparison,
        inPeriod: inPeriod,
        formatter: widget.formatter,
        single: null,
      );
    }
    return FutureBuilder<RunSummary?>(
      future: _single,
      builder: (context, snapshot) => _Body(
        stats: stats,
        comparison: comparison,
        inPeriod: inPeriod,
        formatter: widget.formatter,
        single: snapshot.connectionState == ConnectionState.done
            ? snapshot.data
            : null,
        singlePending: snapshot.connectionState != ConnectionState.done,
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.stats,
    required this.comparison,
    required this.inPeriod,
    required this.formatter,
    required this.single,
    this.singlePending = false,
  });

  final PeriodStatistics stats;
  final PeriodComparison? comparison;
  final List<RunOverview> inPeriod;
  final UnitFormatter formatter;
  final RunSummary? single;
  final bool singlePending;

  String _signed(String text, num sign) =>
      sign > 0 ? '+$text' : (sign < 0 ? '−$text' : text);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final empty = stats.runCount == 0;

    /// Wert einer Kennzahl oder „nicht verfügbar“ mit Grund.
    StatRow row<T>(
      String id,
      String label,
      StatValue<T> v,
      String Function(T) format, {
      required String missing,
    }) {
      if (v.value == null) {
        return StatRow(
          id: id,
          label: label,
          value: empty ? l10n.statNoRunsInPeriod : missing,
        );
      }
      return StatRow(
        id: id,
        label: label,
        value: format(v.value as T),
        note: v.isPartial
            ? l10n.statPartial(v.runsWithValue, v.runsTotal)
            : null,
      );
    }

    final unavailable = l10n.statNoValue;
    final zonesReason = _loadReason(
      inPeriod,
      (l) => l.zonesReason,
      (l) => l.zonesStored,
      l10n,
    );
    final trimpReason = _loadReason(
      inPeriod,
      (l) => l.trimpReason,
      (l) => l.trimpStored,
      l10n,
    );
    final zones = stats.zoneTimes.value;
    final below = stats.belowZone1Time.value;
    final laps = single?.laps.length;
    final bestSingle = single?.bestPace.secondsPerKm;
    final singleMissing = stats.period.runId != null
        ? l10n.runUnavailable
        : l10n.statSingleRunOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatHeading(l10n.statScope),
        StatRow(
          id: 'stat_runs',
          label: l10n.statRuns,
          value: '${stats.runCount}',
        ),
        StatRow(
          id: 'stat_days',
          label: l10n.statTrainingDays,
          value: '${stats.trainingDays}',
        ),
        row<double>(
          'stat_distance',
          l10n.runDistance,
          stats.distanceMeters,
          formatter.distance,
          missing: unavailable,
        ),
        row<Duration>(
          'stat_moving',
          l10n.runMovingTime,
          stats.movingTime,
          formatClock,
          missing: unavailable,
        ),
        row<Duration>(
          'stat_total',
          l10n.sumTotalTime,
          stats.totalTime,
          formatClock,
          missing: unavailable,
        ),
        StatHeading(l10n.statSpeed),
        row<double>(
          'stat_avg_pace',
          l10n.runAvgPace,
          stats.averagePaceSecondsPerKm,
          formatter.pace,
          missing: unavailable,
        ),
        // Bestpace und Runden sind nicht in der Kurzfassung; sie werden nur für
        // einen einzelnen Lauf gelesen (kein Zugriff je Lauf).
        StatRow(
          id: 'stat_best_pace',
          label: l10n.sumBestPace,
          value: empty
              ? l10n.statNoRunsInPeriod
              : (bestSingle != null
                    ? formatter.pace(bestSingle)
                    : (singlePending ? '…' : singleMissing)),
        ),
        StatRow(
          id: 'stat_laps',
          label: l10n.runLaps,
          value: empty
              ? l10n.statNoRunsInPeriod
              : (laps != null
                    ? '$laps'
                    : (singlePending ? '…' : singleMissing)),
        ),
        StatHeading(l10n.statHeart),
        row<double>(
          'stat_avg_hr',
          l10n.sumAvgHeartRate,
          stats.heartRateAverageBpm,
          (v) => l10n.runBpm(v.round()),
          missing: l10n.sumNoHeartRate,
        ),
        row<int>(
          'stat_max_hr',
          l10n.sumMaxHeartRate,
          stats.heartRateMaxBpm,
          l10n.runBpm,
          missing: l10n.sumNoHeartRate,
        ),
        if (zones == null)
          StatRow(
            id: 'stat_zones',
            label: l10n.sumZones,
            value: empty ? l10n.statNoRunsInPeriod : zonesReason,
          )
        else
          MergeSemantics(
            child: Column(
              key: const Key('stat_zones'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l10n.sumZones),
                ),
                for (var i = 0; i < zones.length; i++)
                  Text(l10n.sumZoneRow(i + 1, formatClock(zones[i]))),
                if (below != null) Text(l10n.sumBelowZone1(formatClock(below))),
                if (stats.zoneTimes.isPartial)
                  Text(
                    l10n.statPartial(
                      stats.zoneTimes.runsWithValue,
                      stats.zoneTimes.runsTotal,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        StatHeading(l10n.statLoad),
        row<double>(
          'stat_trimp',
          l10n.sumTrimp,
          stats.trimpPoints,
          (v) => stats.trimpIncomplete
              ? l10n.sumTrimpPartial(v.round().toString())
              : l10n.sumTrimpValue(v.round().toString()),
          missing: trimpReason,
        ),
        StatHeading(l10n.statDevelopment),
        if (comparison == null)
          Text(l10n.statCompareOnly, key: const Key('stat_compare_only'))
        else
          Column(
            key: const Key('stat_compare'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.statCompareTitle),
              StatRow(
                id: 'stat_delta_runs',
                label: l10n.statRuns,
                value: _signed(
                  '${comparison!.runCountDelta.abs()}',
                  comparison!.runCountDelta,
                ),
              ),
              StatRow(
                id: 'stat_delta_distance',
                label: l10n.runDistance,
                value: comparison!.distanceDeltaMeters == null
                    ? l10n.statCompareNone
                    : _signed(
                        formatter.distance(
                          comparison!.distanceDeltaMeters!.abs(),
                        ),
                        comparison!.distanceDeltaMeters!,
                      ),
              ),
              StatRow(
                id: 'stat_delta_moving',
                label: l10n.runMovingTime,
                value: comparison!.movingTimeDelta == null
                    ? l10n.statCompareNone
                    : _signed(
                        formatClock(
                          Duration(
                            microseconds: comparison!
                                .movingTimeDelta!
                                .inMicroseconds
                                .abs(),
                          ),
                        ),
                        comparison!.movingTimeDelta!.inMicroseconds,
                      ),
              ),
            ],
          ),
      ],
    );
  }

  /// Grund, warum Zonen oder TRIMP fehlen: der gespeicherte Grund eines Laufs,
  /// sonst „nicht gespeichert“ (ältere Läufe), sonst allgemein.
  String _loadReason(
    List<RunOverview> runs,
    UnavailableReason? Function(StoredRunLoad) reason,
    bool Function(StoredRunLoad) stored,
    AppLocalizations l10n,
  ) {
    for (final r in runs) {
      final why = reason(r.load);
      if (why != null) return reasonText(l10n, why);
    }
    if (runs.isNotEmpty && !runs.any((r) => stored(r.load))) {
      return l10n.sumLoadNotStored;
    }
    return l10n.statNoValue;
  }
}
