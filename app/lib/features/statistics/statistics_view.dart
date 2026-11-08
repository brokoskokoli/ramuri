import 'dart:math' show max;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/section_heading.dart';
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
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double longest(String text, TextStyle? style) {
      var max = 0.0;
      for (final word in text.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: direction,
          textScaler: scaler,
        )..layout();
        if (painter.width > max) max = painter.width;
        painter.dispose();
      }
      return max;
    }

    final valueWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          key: Key('${id}_value'),
          textAlign: TextAlign.end,
          style: theme.titleMedium,
        ),
        if (note != null)
          Text(note!, textAlign: TextAlign.end, style: theme.bodySmall),
      ],
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: LayoutBuilder(
          builder: (context, box) {
            const gap = 12.0;
            // Weder Label noch Wert darf mitten im Wort brechen. Passt das
            // längste Wort beider nicht nebeneinander, stehen sie
            // untereinander (Wert rechts).
            final labelMin = longest(label, theme.bodyMedium);
            final valueMin = max(
              longest(value, theme.titleMedium),
              note == null ? 0.0 : longest(note!, theme.bodySmall),
            );
            if (labelMin + gap + valueMin > box.maxWidth) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label, style: theme.bodyMedium),
                  valueWidget,
                ],
              );
            }
            // Das Label nimmt seine natürliche Breite bis 60 %, mindestens
            // sein längstes Wort; der Wert behält sein längstes Wort.
            final labelMax = (box.maxWidth * 0.6).clamp(
              labelMin,
              box.maxWidth - gap - valueMin,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: labelMax),
                  child: Text(label, style: theme.bodyMedium),
                ),
                const SizedBox(width: gap),
                Expanded(child: valueWidget),
              ],
            );
          },
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: SectionHeading(text),
  );
}

/// Karte eines Abschnitts der Kennzahlen (Stil des Designs).
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    ),
  );
}

/// Kennzahlen des Zeitraums [period] aus den bereits gelesenen [overviews]
/// (FR-0043). Bestpace und Runden stehen in der Kurzfassung jedes Laufs; es
/// wird nichts je Lauf nachgelesen.
class PeriodStatisticsView extends StatelessWidget {
  const PeriodStatisticsView({
    super.key,
    required this.period,
    required this.overviews,
    required this.figures,
    required this.formatter,
  });

  final StatisticsPeriod period;
  final List<RunOverview> overviews;

  /// Die Kennzahlen aller Läufe, einmal aus [overviews] gebildet.
  final List<RunFigures> figures;
  final UnitFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final stats = computePeriodStatistics(period, figures);
    final comparison = comparePeriod(period, figures);
    final inPeriod = [
      for (var i = 0; i < overviews.length; i++)
        if (period.contains(id: overviews[i].run.id, day: figures[i].day))
          overviews[i],
    ];
    return _Body(
      stats: stats,
      comparison: comparison,
      inPeriod: inPeriod,
      formatter: formatter,
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.stats,
    required this.comparison,
    required this.inPeriod,
    required this.formatter,
  });

  final PeriodStatistics stats;
  final PeriodComparison? comparison;
  final List<RunOverview> inPeriod;
  final UnitFormatter formatter;

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatCard(
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
          ],
        ),
        StatCard(
          children: [
            StatHeading(l10n.statSpeed),
            row<double>(
              'stat_avg_pace',
              l10n.runAvgPace,
              stats.averagePaceSecondsPerKm,
              formatter.pace,
              missing: unavailable,
            ),
            row<double>(
              'stat_best_pace',
              l10n.sumBestPace,
              stats.bestPaceSecondsPerKm,
              formatter.pace,
              missing: unavailable,
            ),
            row<int>(
              'stat_laps',
              l10n.runLaps,
              stats.lapCount,
              (v) => '$v',
              missing: unavailable,
            ),
          ],
        ),
        StatCard(
          children: [
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
                    if (below != null)
                      Text(l10n.sumBelowZone1(formatClock(below))),
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
          ],
        ),
        StatCard(
          children: [
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
          ],
        ),
        StatCard(
          children: [
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
