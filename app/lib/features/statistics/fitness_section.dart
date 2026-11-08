import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_card.dart';
import '../transparency/value_explanation_screen.dart';
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

/// Zahl mit einer Nachkommastelle, im Deutschen mit Komma; mit [sign] steht
/// bei positiven Werten ein Plus (FR-0087: 5,56 wird „5,6“).
String fitnessNumber(bool german, double v, {bool sign = false}) {
  final text = v.toStringAsFixed(1);
  final signed = sign && v > 0 ? '+$text' : text;
  return german ? signed.replaceAll('.', ',') : signed;
}

/// Wert eines gespeicherten Fitnesswerts oder, wenn er fehlt, sein Grund
/// (FR-0068, FR-0057).
String valueOrReasonText(
  AppLocalizations l10n,
  ComputedValue v,
  String Function(double) format,
) => v.value != null
    ? format(v.value!)
    : (v.unavailableReason == null
          ? l10n.runUnavailable
          : reasonText(l10n, v.unavailableReason!));

/// Öffnet die Erklärung eines Werts: über [onExplain], sonst die
/// Erklärungsseite aus den gespeicherten Angaben.
void openValueExplanation(
  BuildContext context, {
  required StorageSession session,
  required ExplainValue? onExplain,
  required String valueKey,
  int? runId,
  String? day,
}) {
  if (onExplain != null) {
    onExplain(context, valueKey, runId: runId, day: day);
  } else {
    showValueExplanation(
      context,
      session,
      valueKey: valueKey,
      runId: runId,
      day: day,
    );
  }
}

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

  /// Wochen im Verlauf (Sicht 3): rund drei Monate.
  static const int _trendWeeks = 12;

  static DateTime _date(String day) => DateTime.parse('${day}T00:00:00Z');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final material = MaterialLocalizations.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    String number(double v, {bool sign = false}) =>
        fitnessNumber(german, v, sign: sign);

    String estimate(double v) => l10n.sumVo2maxValue(number(v));
    String dateOf(String day) => material.formatMediumDate(_date(day));

    Widget explain(String id, String valueKey, {int? runId, String? day}) =>
        ExplainButton(
          id: id,
          onPressed: () => openValueExplanation(
            context,
            session: session,
            onExplain: onExplain,
            valueKey: valueKey,
            runId: runId,
            day: day,
          ),
        );

    String valueOrReason(ComputedValue v, String Function(double) format) =>
        valueOrReasonText(l10n, v, format);

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

    // Sicht 3: Verlauf über Wochen aus den Tageswerten (nicht aus den
    // Laufschätzungen, FR-0081, FR-0078).
    final trend = fitness.weeklyLongTerm(maxWeeks: _trendWeeks);

    final longTerm = fitness.longTerm;
    final eff = fitness.efficiency;
    final day = fitness.day;

    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: Column(
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
          if (inPeriod != null)
            _ZeroWeightHint(
              key: ValueKey(inPeriod.runId),
              session: session,
              runId: inPeriod.runId,
            ),
          if (inPeriod != null)
            explain(
              'stat_explain_vo2_run',
              vo2maxRunValueKey,
              runId: inPeriod.runId,
            ),
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
          if (day != null)
            explain(
              'stat_explain_vo2_current',
              vo2maxLongTermValueKey,
              day: day,
            ),
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
                Text(
                  l10n.statVo2TrendNote,
                  key: const Key('stat_vo2_trend_note'),
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
                      key: Key('stat_vo2_trend_${e.day}'),
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
          if (day != null)
            explain(
              'stat_explain_efficiency',
              aerobicEfficiencyValueKey,
              day: day,
            ),
        ],
      ),
    );
  }
}

/// Hinweis zu einer Schätzung, bei der ein Abschnitt Gewicht 0 hatte
/// (`EstimateDiscard.zeroWeight`). Liest die Abschnitte des einen Laufs, einmal
/// je Lauf (nicht bei jedem Neuaufbau).
class _ZeroWeightHint extends StatefulWidget {
  const _ZeroWeightHint({
    super.key,
    required this.session,
    required this.runId,
  });

  final StorageSession session;
  final int runId;

  @override
  State<_ZeroWeightHint> createState() => _ZeroWeightHintState();
}

class _ZeroWeightHintState extends State<_ZeroWeightHint> {
  late final Future<ComputedValue?> _value = FitnessOverviewService(
    session: widget.session,
  ).runValueWithSections(widget.runId);

  @override
  Widget build(BuildContext context) => FutureBuilder<ComputedValue?>(
    future: _value,
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
