import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import 'statistics_screen.dart' show ExplainValue;
import 'statistics_view.dart';

/// Text zu einem Grund, warum ein Fitnesswert fehlt (FR-0068). Jeder Grund hat
/// einen eigenen Text; fehlende Profilwerte weisen auf das Profil hin
/// (FR-0055).
String reasonText(AppLocalizations l10n, UnavailableReason reason) =>
    switch (reason) {
      UnavailableReason.missingMaxHeartRate ||
      UnavailableReason.missingRestingHeartRate ||
      UnavailableReason.maxNotAboveResting ||
      UnavailableReason.reserveTooSmall => l10n.runZoneNoBasis,
      UnavailableReason.noHeartRate => l10n.sumNoHeartRate,
      UnavailableReason.insufficientCoverage => l10n.sumCoverageLow,
      UnavailableReason.noMovingTime => l10n.statReasonNoMoving,
      UnavailableReason.insufficientData => l10n.statReasonInsufficient,
      UnavailableReason.noValidSection => l10n.statReasonNoSection,
      UnavailableReason.allEstimatesImplausible => l10n.statReasonImplausible,
      UnavailableReason.spreadTooHigh => l10n.statReasonSpread,
      UnavailableReason.currentWindowTooSmall => l10n.statReasonCurrentWindow,
      UnavailableReason.referenceWindowTooSmall =>
        l10n.statReasonReferenceWindow,
    };

/// Fitness in der Statistik: drei getrennte, benannte Sichten auf die VO₂max
/// (FR-0081) und die aerobe Effizienz (FR-0084), abgegrenzt von der VO₂max
/// (FR-0088). Die VO₂max erscheint immer als Schätzung (FR-0067, ACC-05) und
/// nur, wenn ein gespeicherter Wert vorliegt; sonst steht der Grund da.
class FitnessSection extends StatelessWidget {
  const FitnessSection({
    super.key,
    required this.period,
    required this.runsInPeriod,
    required this.fitness,
    required this.session,
    required this.onExplain,
  });

  final StatisticsPeriod? period;
  final int runsInPeriod;
  final FitnessOverview fitness;
  final StorageSession session;
  final ExplainValue? onExplain;

  static const int _trendRows = 12;

  static DateTime _date(String day) => DateTime.parse('${day}T00:00:00Z');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    String number(double v, {bool sign = false}) {
      final text = v.toStringAsFixed(1);
      final signed = sign && v > 0 ? '+$text' : text;
      return german ? signed.replaceAll('.', ',') : signed;
    }

    String estimate(double v) => l10n.sumVo2maxValue(number(v));
    String dateOf(String day) => material.formatMediumDate(_date(day));

    Widget explain(String id, String valueKey) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: TextButton(
        key: Key(id),
        onPressed: () {
          final handler = onExplain;
          if (handler != null) {
            handler(context, valueKey);
          } else {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(l10n.statExplainSoon)));
          }
        },
        child: Text(l10n.statExplain),
      ),
    );

    String valueOrReason(ComputedValue v, String Function(double) format) =>
        v.value != null
        ? format(v.value!)
        : (v.unavailableReason == null
              ? l10n.runUnavailable
              : reasonText(l10n, v.unavailableReason!));

    // Sicht 1: Schätzung aus einem Lauf, der neueste im Zeitraum.
    RunEstimate? inPeriod;
    final p = period;
    if (p != null) {
      for (final e in fitness.runEstimates) {
        if (p.contains(id: e.runId, day: e.day)) inPeriod = e;
      }
    }
    final runText = inPeriod != null
        ? l10n.statVo2OfRun(
            dateOf(inPeriod.day),
            valueOrReason(inPeriod.value, estimate),
          )
        : (runsInPeriod == 0 ? l10n.statVo2NoRunInPeriod : l10n.statVo2NoValue);

    final trend = [
      for (final e in fitness.runEstimates.reversed)
        if (e.value.value != null) e,
    ].take(_trendRows).toList();

    final longTerm = fitness.longTerm;
    final eff = fitness.efficiency;
    final day = fitness.day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      key: const Key('stat_fitness'),
      children: [
        StatHeading(l10n.statFitness),
        Text(l10n.statVo2Note, key: const Key('stat_vo2_note')),
        if (fitness.readFailed)
          Text(l10n.statFitnessFailed, key: const Key('stat_fitness_failed')),
        if (fitness.pendingRuns > 0)
          Text(
            l10n.statPending(fitness.pendingRuns),
            key: const Key('stat_pending'),
          ),
        StatRow(id: 'stat_vo2_run', label: l10n.statVo2Run, value: runText),
        if (inPeriod != null) _ZeroWeightHint(session, inPeriod.runId),
        explain('stat_explain_vo2_run', vo2maxRunValueKey),
        StatRow(
          id: 'stat_vo2_current',
          label: l10n.statVo2Current,
          value: longTerm == null
              ? l10n.statVo2NoValue
              : l10n.statVo2Day(
                  day == null ? '' : dateOf(day),
                  valueOrReason(longTerm, estimate),
                ),
        ),
        explain('stat_explain_vo2_current', vo2maxLongTermValueKey),
        Semantics(
          container: true,
          label: l10n.statVo2Trend,
          child: Column(
            key: const Key('stat_vo2_trend'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l10n.statVo2Trend),
              ),
              if (trend.isEmpty)
                Text(
                  l10n.statVo2TrendNone,
                  key: const Key('stat_vo2_trend_none'),
                )
              else
                for (final e in trend)
                  Text(
                    l10n.statVo2TrendRow(
                      dateOf(e.day),
                      estimate(e.value.value!),
                    ),
                  ),
            ],
          ),
        ),
        const Divider(),
        StatRow(
          id: 'stat_efficiency',
          label: l10n.statEfficiency,
          value: eff == null
              ? l10n.statEfficiencyNone
              : valueOrReason(
                  eff,
                  (v) => l10n.statEfficiencyValue(
                    number(v, sign: true),
                    day == null ? '' : dateOf(day),
                  ),
                ),
        ),
        Text(l10n.statEfficiencyNote, key: const Key('stat_efficiency_note')),
        explain('stat_explain_efficiency', aerobicEfficiencyValueKey),
      ],
    );
  }
}

/// Hinweis zu einer Schätzung, bei der ein Abschnitt Gewicht 0 hatte
/// (`EstimateDiscard.zeroWeight`). Liest die Abschnitte des einen Laufs.
class _ZeroWeightHint extends StatelessWidget {
  const _ZeroWeightHint(this.session, this.runId);

  final StorageSession session;
  final int runId;

  @override
  Widget build(BuildContext context) => FutureBuilder<ComputedValue?>(
    future: FitnessOverviewService(session: session)
        .runValueWithSections(runId),
    builder: (context, snapshot) {
      final v = snapshot.data;
      if (v == null || !hasZeroWeightSection(v)) return const SizedBox.shrink();
      return Text(
        AppLocalizations.of(context).statVo2ZeroWeight,
        key: const Key('stat_vo2_zero_weight'),
      );
    },
  );
}
