import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../run/live_run_values.dart' show LiveValueText, splitUnit;
import '../run/live_run_view.dart' show formatClock;
import '../settings/unit_format.dart';
import '../transparency/value_explanation_screen.dart';
import 'run_charts.dart';
import 'run_summary_body.dart';

/// Inhalt der Zusammenfassung nach dem Lauf nach dem Screen `Summary.dc.html`
/// (FR-0037): Strecke mit Route, Zeiten, Kacheln, Zonen, Einordnung, Höhenprofil,
/// Runden und Quellen. Nicht Verfügbares steht als „nicht verfügbar“, nie als 0.
/// „Fertig“ und „Details“ sitzen im Fuß der Seite ([LiveRunView]); diese
/// Ansicht ändert keine Daten.
class RunSummaryPage extends StatelessWidget {
  const RunSummaryPage({
    super.key,
    required this.summary,
    required this.detail,
    required this.formatter,
    required this.session,
    required this.runId,
  });

  final RunSummary summary;
  final RunDetailData detail;
  final UnitFormatter formatter;
  final StorageSession session;
  final int runId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const gap = SizedBox(height: 16);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(context, l10n),
        gap,
        RamuriTileGrid(children: tiles(l10n)),
        explain(context, 'sum_explain_trimp', trimpRunValueKey),
        gap,
        zones(context, l10n),
        gap,
        compare(context, l10n),
        gap,
        _altitude(context, l10n),
        gap,
        laps(context, l10n),
        notes(context, l10n),
        explain(
          context,
          'sum_explain_sources',
          runSourcesKey,
          label: l10n.explSourcesButton,
        ),
      ],
    );
  }

  Widget explain(
    BuildContext context,
    String id,
    String valueKey, {
    String? label,
    RunClassification? classification,
  }) => ExplainButton(
    id: id,
    label: label,
    onPressed: () => showValueExplanation(
      context,
      session,
      valueKey: valueKey,
      runId: runId,
      classification: classification,
      formatter: formatter,
    ),
  );

  /// Strecke groß, darunter Route und die beiden Zeiten.
  Widget _hero(BuildContext context, AppLocalizations l10n) {
    final type = RamuriType.of(context);
    final f = summary.figures;
    final (distance, distanceUnit) = f.distanceMeters == null
        ? (l10n.runUnavailable, null)
        : splitUnit(
            formatter.distance(f.distanceMeters),
            formatter.distanceLabel,
          );
    final text = Theme.of(context).textTheme;
    Widget time(String id, String label, Duration? d) => Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Text(label, style: text.labelMedium)),
        const SizedBox(width: 6),
        Text(clockText(l10n, d), key: Key(id), style: text.titleMedium),
      ],
    );
    return RamuriCard(
      tone: RamuriCardTone.accent,
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LiveValueText(
            id: 'run_distance',
            value: distance,
            unit: distanceUnit,
            valueStyle: distanceUnit == null
                ? Theme.of(context).textTheme.titleLarge!
                : type.distance,
            unitStyle: type.unitLarge,
          ),
          const SizedBox(height: 14),
          RunRouteSection(route: detail.route),
          const SizedBox(height: 14),
          Wrap(
            spacing: 24,
            runSpacing: 4,
            children: [
              time('run_moving_time', l10n.runMovingTime, f.movingTime),
              time('run_time', l10n.sumTotalTime, f.totalTime),
            ],
          ),
        ],
      ),
    );
  }

  /// Kachel mit Zahl und Einheit; ohne Wert der Grund als Text, nie 0.
  Widget _tile(
    String id,
    String label,
    String? text,
    String? unit,
    String unavailable, {
    bool estimated = false,
    String prefix = '',
  }) {
    if (text == null) {
      return RamuriValueTile(
        label: label,
        value: unavailable,
        textValue: true,
        valueKey: Key(id),
      );
    }
    final (value, found) = unit == null ? (text, null) : splitUnit(text, unit);
    // Null hat kein Vorzeichen: nicht „+0 m“ oder „−0 m“.
    final signed = prefix.isEmpty ? value : signedElevation(prefix, value);
    return RamuriValueTile(
      label: label,
      value: signed,
      unit: found == null ? null : unbreakableUnit(found),
      estimated: estimated,
      valueKey: Key(id),
    );
  }

  List<Widget> tiles(AppLocalizations l10n) {
    final f = summary.figures;
    final avgHr = f.heartRateAverageBpm;
    final maxHr = f.heartRateMaxBpm;
    final load = summary.load;
    final ascent = summary.ascentMeters;
    final descent = summary.descentMeters;
    final pace = f.averagePaceSecondsPerKm;
    final best = summary.bestPace.secondsPerKm;
    final trimp = f.trimpPoints;
    final na = l10n.runUnavailable;
    final trimpNone = load.trimpReason != null
        ? unavailableReasonText(
            l10n,
            load.trimpReason!,
            hasHeartRate: avgHr != null,
          )
        : (load.trimpStored ? na : l10n.sumLoadNotStored);
    return [
      _tile(
        'run_avg_pace',
        l10n.summaryAvgPace,
        pace == null ? null : formatter.pace(pace),
        formatter.paceLabel,
        na,
      ),
      _tile(
        'sum_best_pace',
        l10n.summaryBestPace,
        best == null ? null : formatter.pace(best),
        formatter.paceLabel,
        l10n.sumBestPaceNone,
      ),
      _tile(
        'run_ascent',
        l10n.summaryAscent,
        ascent == null ? null : formatter.elevation(ascent),
        formatter.elevationLabel,
        na,
        prefix: '+',
      ),
      _tile(
        'run_descent',
        l10n.summaryDescent,
        descent == null ? null : formatter.elevation(descent),
        formatter.elevationLabel,
        na,
        prefix: '−',
      ),
      _tile(
        'sum_avg_hr',
        l10n.summaryAvgHr,
        avgHr == null ? null : l10n.runBpm(avgHr.round()),
        l10n.liveUnitBpm,
        l10n.sumNoHeartRate,
      ),
      _tile(
        'sum_max_hr',
        l10n.summaryMaxHr,
        maxHr == null ? null : l10n.runBpm(maxHr),
        l10n.liveUnitBpm,
        l10n.sumNoHeartRate,
      ),
      if (trimp == null || f.trimpIncomplete)
        RamuriValueTile(
          label: l10n.summaryLoad,
          value: trimp == null
              ? trimpNone
              : l10n.sumTrimpPartial(trimp.round().toString()),
          textValue: true,
          estimated: trimp != null,
          valueKey: const Key('sum_trimp'),
        )
      else
        _tile(
          'sum_trimp',
          l10n.summaryLoad,
          '${trimp.round()} ${l10n.summaryLoadUnit}',
          l10n.summaryLoadUnit,
          na,
          estimated: true,
        ),
    ];
  }

  /// Zeit in Zonen: Balken, darunter je Zone die Zeit als Text.
  Widget zones(BuildContext context, AppLocalizations l10n) {
    final f = summary.figures;
    final load = summary.load;
    final times = f.zoneTimes;
    final style = Theme.of(context).textTheme.labelMedium;
    final rows = times == null
        ? const <String>[]
        : [
            for (var i = 0; i < times.length; i++)
              l10n.sumZoneRow(i + 1, formatClock(times[i])),
            if (f.belowZone1Time != null)
              l10n.sumBelowZone1(formatClock(f.belowZone1Time)),
          ];
    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(l10n.summaryZones),
          const SizedBox(height: 10),
          if (times == null)
            Text(
              load.zonesReason != null
                  ? unavailableReasonText(
                      l10n,
                      load.zonesReason!,
                      hasHeartRate: f.heartRateAverageBpm != null,
                    )
                  : (load.zonesStored
                        ? l10n.runUnavailable
                        : l10n.sumLoadNotStored),
              key: const Key('sum_zones_unavailable'),
            )
          else ...[
            ZoneBar(
              segments: [
                for (var i = 0; i < times.length && i < 5; i++)
                  ZoneBarSegment(
                    zone: i + 1,
                    weight: times[i].inSeconds.toDouble(),
                  ),
              ],
              semanticLabel: rows.join(', '),
            ),
            const SizedBox(height: 10),
            Wrap(
              key: const Key('sum_zones'),
              spacing: 14,
              runSpacing: 4,
              children: [for (final r in rows) Text(r, style: style)],
            ),
          ],
          explain(context, 'sum_explain_zones', zoneTimeValueKey(1)),
        ],
      ),
    );
  }

  /// Einordnung (letzte 5 Läufe, Pace; OQ-0037) und VO₂max auf dunkler Karte.
  Widget compare(BuildContext context, AppLocalizations l10n) {
    final vo2 = summary.vo2max;
    return RamuriCard(
      tone: RamuriCardTone.panel,
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Builder(
        builder: (context) {
          final text = Theme.of(context).textTheme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.summaryCompare, style: text.labelLarge),
              const SizedBox(height: 8),
              Text(
                classificationText(l10n, summary.classification, formatter),
                key: const Key('sum_class'),
                style: text.titleMedium,
              ),
              explain(
                context,
                'sum_explain_class',
                classificationKey,
                classification: summary.classification,
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(l10n.sumVo2max, style: text.bodyMedium),
                  Text(
                    vo2?.value == null
                        ? l10n.sumVo2maxNone
                        : l10n.sumVo2maxValue(
                            decimalText(
                              formatter,
                              vo2!.value!.toStringAsFixed(1),
                            ),
                          ),
                    key: const Key('sum_vo2max'),
                    style: text.titleSmall,
                  ),
                ],
              ),
              explain(context, 'sum_explain_vo2max', vo2maxRunValueKey),
            ],
          );
        },
      ),
    );
  }

  /// Höhenprofil; Anstieg und Gefälle stehen in den Kacheln darüber.
  Widget _altitude(BuildContext context, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final layer = ChartLayer(
      name: l10n.detAltitudeName,
      parts: detail.altitude,
      color: scheme.tertiary,
      format: formatter.elevation,
    );
    final empty = layer.parts.every((p) => p.isEmpty);
    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(l10n.summaryElevation),
          const SizedBox(height: 10),
          if (empty)
            Text(l10n.detAltitudeNone, key: const Key('sum_altitude_none'))
          else
            RunSeriesChart(
              key: const Key('sum_altitude'),
              layers: [layer],
              totalSeconds: detail.totalSeconds,
              pauses: detail.pauses,
            ),
        ],
      ),
    );
  }

  Widget laps(BuildContext context, AppLocalizations l10n) {
    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
        key: const Key('run_laps'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(l10n.runLaps),
          const SizedBox(height: 6),
          if (summary.laps.isEmpty) Text(l10n.runNoLaps),
          for (final lap in summary.laps.reversed)
            Text(l10n.runLapRow(lap.index, formatClock(lap.lapTime))),
        ],
      ),
    );
  }

  /// Datenhinweise: GPS-Lücken und was Lücken in den Zeichnungen bedeuten.
  Widget notes(BuildContext context, AppLocalizations l10n) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (summary.positionGapCount > 0)
            Text(
              l10n.runGpsGaps(summary.positionGapCount),
              key: const Key('run_gaps'),
              style: small,
            ),
          Text(l10n.detGapNote, style: small),
        ],
      ),
    );
  }
}
