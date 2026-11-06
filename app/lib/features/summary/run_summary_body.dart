import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../run/live_run_view.dart' show formatClock;
import '../settings/unit_format.dart';
import 'run_charts.dart';

/// Wo die reine Rechnung der Zusammenfassung läuft: in der App in einem eigenen
/// Isolate, damit die Oberfläche bei langen Läufen nicht einfriert (Lesen und
/// Speichern bleiben im Haupt-Isolate). Tests stellen [inlineOffload] ein, weil
/// ein Isolate in der Test-Uhr nicht abläuft.
Offload summaryOffload = isolateOffload;

/// Zeit für die Anzeige; fehlt sie, „nicht verfügbar“ (nie „–“ oder 0).
String clockText(AppLocalizations l10n, Duration? d) =>
    d == null ? l10n.runUnavailable : formatClock(d);

/// Zusammenfassung eines beendeten Laufs (FR-0037). Liest und rechnet beim
/// Öffnen aus den gespeicherten Rohdaten ([RunSummaryService]). Fehlendes steht
/// als „nicht verfügbar“, nie als 0. Route und Diagramme zeichnet
/// [RunDetailCharts]. Scheitert das Lesen oder fehlt der Lauf im Speicher, zeigt
/// [fallback] die Werte der Aufzeichnung.
class RunSummaryBody extends StatefulWidget {
  const RunSummaryBody({
    super.key,
    required this.session,
    required this.clock,
    required this.runId,
    required this.formatter,
    required this.fallback,
  });

  final StorageSession session;
  final Clock clock;
  final int runId;
  final UnitFormatter formatter;
  final List<Widget> Function() fallback;

  @override
  State<RunSummaryBody> createState() => _RunSummaryBodyState();
}

class _RunSummaryBodyState extends State<RunSummaryBody> {
  late final Future<_Loaded?> _future = _load();

  Future<_Loaded?> _load() async {
    try {
      final summary = await RunSummaryService(
        session: widget.session,
        clock: widget.clock,
        offload: summaryOffload,
      ).load(widget.runId);
      if (summary == null) return null;
      // Einmal gebaut, nicht bei jedem Neuzeichnen.
      return _Loaded(
        summary,
        await summaryOffload(buildRunDetailJob, (
          pre: summary.preprocessing,
          start: summary.run.startedAt,
          end: summary.run.endedAt!,
          pauses: summary.manualPauses,
        )),
      );
    } on Object {
      // Keine Gesundheitsdaten in Meldungen; die Ansicht fällt zurück.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<_Loaded?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(l10n.sumLoading, key: const Key('sum_loading')),
              ],
            ),
          );
        }
        final loaded = snapshot.data;
        if (loaded == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.sumFallback, key: const Key('sum_fallback')),
              const SizedBox(height: 8),
              ...widget.fallback(),
            ],
          );
        }
        return _SummaryContent(
          summary: loaded.summary,
          detail: loaded.detail,
          formatter: widget.formatter,
        );
      },
    );
  }
}

class _Loaded {
  _Loaded(this.summary, this.detail);
  final RunSummary summary;
  final RunDetailData detail;
}

class _SummaryContent extends StatelessWidget {
  const _SummaryContent({
    required this.summary,
    required this.detail,
    required this.formatter,
  });

  final RunSummary summary;
  final RunDetailData detail;
  final UnitFormatter formatter;

  String _unavailable(AppLocalizations l10n, UnavailableReason reason) =>
      switch (reason) {
        UnavailableReason.noHeartRate => l10n.sumNoHeartRate,
        UnavailableReason.missingMaxHeartRate ||
        UnavailableReason.missingRestingHeartRate ||
        UnavailableReason.maxNotAboveResting ||
        UnavailableReason.reserveTooSmall => l10n.runZoneNoBasis,
        UnavailableReason.insufficientCoverage => l10n.sumCoverageLow,
        _ => l10n.runUnavailable,
      };

  String _number(String text) =>
      formatter.languageCode == 'de' ? text.replaceAll('.', ',') : text;

  String _classification(AppLocalizations l10n) {
    final c = summary.classification;
    if (!c.isAvailable) {
      return c.unavailable == ClassificationUnavailable.noPaceForRun
          ? l10n.sumClassNoPace
          : l10n.sumClassNoPrevious;
    }
    final delta = c.deltaSecondsPerKm!;
    final reference = formatter.pace(c.referenceSecondsPerKm);
    // Nur der Unterschied, ohne Stufen; unter der Toleranz der Einordnung
    // (|Δ| < 1 s/km) gilt er als gleich.
    if (c.relation == PaceRelation.same) {
      return l10n.sumClassSame(c.comparedRuns, reference);
    }
    final text = formatter.pace(delta.abs());
    return delta < 0
        ? l10n.sumClassFaster(text, c.comparedRuns, reference)
        : l10n.sumClassSlower(text, c.comparedRuns, reference);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final f = summary.figures;
    final theme = Theme.of(context).textTheme;
    final avgHr = f.heartRateAverageBpm;
    final maxHr = f.heartRateMaxBpm;
    final load = summary.load;
    final vo2 = summary.vo2max;
    final best = summary.bestPace;

    Widget row(String id, String label, String value, {bool big = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(flex: 2, child: Text(label, style: theme.bodyMedium)),
              Expanded(
                flex: 3,
                child: Text(
                  value,
                  key: Key(id),
                  textAlign: TextAlign.end,
                  style: big ? theme.headlineSmall : theme.titleMedium,
                ),
              ),
            ],
          ),
        );

    final zoneTimes = f.zoneTimes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(
          'run_time',
          l10n.sumTotalTime,
          clockText(l10n, f.totalTime),
          big: true,
        ),
        row(
          'run_distance',
          l10n.runDistance,
          f.distanceMeters == null
              ? l10n.runUnavailable
              : formatter.distance(f.distanceMeters),
          big: true,
        ),
        row(
          'run_moving_time',
          l10n.runMovingTime,
          clockText(l10n, f.movingTime),
        ),
        row(
          'run_avg_pace',
          l10n.runAvgPace,
          f.averagePaceSecondsPerKm == null
              ? l10n.runUnavailable
              : formatter.pace(f.averagePaceSecondsPerKm),
        ),
        row(
          'sum_best_pace',
          l10n.sumBestPace,
          best.secondsPerKm == null
              ? l10n.sumBestPaceNone
              : formatter.pace(best.secondsPerKm),
        ),
        row(
          'sum_avg_hr',
          l10n.sumAvgHeartRate,
          avgHr == null ? l10n.sumNoHeartRate : l10n.runBpm(avgHr.round()),
        ),
        row(
          'sum_max_hr',
          l10n.sumMaxHeartRate,
          maxHr == null ? l10n.sumNoHeartRate : l10n.runBpm(maxHr),
        ),
        if (summary.positionGapCount > 0)
          row(
            'run_gaps',
            l10n.runGps,
            l10n.runGpsGaps(summary.positionGapCount),
          ),
        row(
          'run_ascent',
          l10n.runAscent,
          summary.ascentMeters == null
              ? l10n.runUnavailable
              : formatter.elevation(summary.ascentMeters),
        ),
        const SizedBox(height: 8),
        Text(l10n.sumZones, style: theme.titleSmall),
        if (zoneTimes == null)
          Text(
            load.zonesReason != null
                ? _unavailable(l10n, load.zonesReason!)
                : (load.zonesStored
                      ? l10n.runUnavailable
                      : l10n.sumLoadNotStored),
            key: const Key('sum_zones_unavailable'),
          )
        else
          Column(
            key: const Key('sum_zones'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < zoneTimes.length; i++)
                Text(l10n.sumZoneRow(i + 1, formatClock(zoneTimes[i]))),
              if (f.belowZone1Time != null)
                Text(l10n.sumBelowZone1(formatClock(f.belowZone1Time))),
            ],
          ),
        const SizedBox(height: 8),
        row(
          'sum_trimp',
          l10n.sumTrimp,
          f.trimpPoints == null
              ? (load.trimpReason != null
                    ? _unavailable(l10n, load.trimpReason!)
                    : (load.trimpStored
                          ? l10n.runUnavailable
                          : l10n.sumLoadNotStored))
              : (f.trimpIncomplete
                    ? l10n.sumTrimpPartial(f.trimpPoints!.round().toString())
                    : l10n.sumTrimpValue(f.trimpPoints!.round().toString())),
        ),
        row('sum_class', l10n.sumClassification, _classification(l10n)),
        row(
          'sum_vo2max',
          l10n.sumVo2max,
          vo2?.value == null
              ? l10n.sumVo2maxNone
              : l10n.sumVo2maxValue(_number(vo2!.value!.toStringAsFixed(1))),
        ),
        const SizedBox(height: 8),
        RunDetailCharts(
          key: const Key('run_detail_charts'),
          data: detail,
          formatter: formatter,
        ),
        const SizedBox(height: 8),
        Column(
          key: const Key('run_laps'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.runLaps, style: theme.titleSmall),
            if (summary.laps.isEmpty) Text(l10n.runNoLaps),
            for (final lap in summary.laps.reversed)
              Text(l10n.runLapRow(lap.index, formatClock(lap.lapTime))),
          ],
        ),
      ],
    );
  }
}
