import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../settings/unit_format.dart';
import '../transparency/quality_text.dart';
import 'fitness_section.dart';
import 'statistics_screen.dart' show ExplainValue;

/// Kopf der Fortschrittsseite nach dem Design (FR-0043, OQ-0075): Kilometer der
/// letzten 8 Wochen, VO₂max mit Verlauf, aerobe Effizienz. Prognose, Belastung
/// und Wochenziel des Designs gehören zu späteren Phasen und fehlen hier.

/// Karte „Kilometer pro Woche“: acht Balken, älteste Woche links. Die Werte
/// stammen aus `weeklyDistanceSeries`, also aus derselben Rechnung wie die
/// Wochenstatistik; eine Woche ohne Lauf steht als 0, eine Woche mit Läufen
/// ohne lesbare Strecke als „nicht verfügbar“ (FR-0057), eine Woche mit
/// teilweise lesbaren Strecken mit Teilhinweis.
class WeekDistanceCard extends StatelessWidget {
  const WeekDistanceCard({
    super.key,
    required this.series,
    required this.formatter,
    required this.hasAnyRun,
  });

  final List<WeeklyDistance> series;
  final UnitFormatter formatter;

  /// Gibt es überhaupt einen Lauf (auch älter als die 8 Wochen)? Nur ohne
  /// jeden Lauf steht der Hinweis „Noch keine Läufe“.
  final bool hasAnyRun;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final theme = Theme.of(context).textTheme;
    final miles = formatter.unit == DistanceUnit.miles;
    final title = miles ? l10n.progressWeekTitleMi : l10n.progressWeekTitleKm;
    final last = series.length - 1;

    String shown(WeeklyDistance w) => formatter.distance(w.meters);
    String partialOf(WeeklyDistance w) =>
        l10n.statPartial(w.distance.runsWithValue, w.distance.runsTotal);

    final spoken = <String>[];
    final notes = <String>[];
    for (var i = 0; i < series.length; i++) {
      final w = series[i];
      if (w.isUnavailable) {
        final text = l10n.progressWeekUnavailable(w.isoWeek);
        spoken.add(text);
        notes.add(text);
        continue;
      }
      final partial = w.hasRuns && w.distance.isPartial;
      final value = partial ? '${shown(w)} (${partialOf(w)})' : shown(w);
      spoken.add(
        i == last
            ? l10n.progressWeekCurrent(w.isoWeek, value)
            : l10n.progressWeekValue(w.isoWeek, value),
      );
      if (partial) notes.add(l10n.progressWeekValue(w.isoWeek, partialOf(w)));
    }
    final label = l10n.progressWeekSemantics(
      title,
      l10n.progressLast8,
      spoken.join('; '),
    );
    final lastFull = series.length >= 2 ? series[last - 1] : null;

    return RamuriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Volle Breite, Enden bündig (Design: space-between). Ein Expanded
          // neben einem Flexible teilt den Platz 1:1 und ließ den rechten
          // Text in der Mitte beginnen.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    key: const Key('progress_week_title'),
                    style: theme.titleSmall,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.progressLast8,
                  key: const Key('progress_week_range'),
                  textAlign: TextAlign.end,
                  style: theme.labelMedium!.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RamuriWeekBars(
            key: const Key('progress_week_bars'),
            values: [for (final w in series) w.meters],
            semanticLabel: label,
          ),
          const SizedBox(height: 12),
          // Ein Wrap schrumpft auf seinen Inhalt, spaceBetween hatte dann keinen
          // Raum; die Row füllt die Breite, „KW“ links, „jetzt“ rechts.
          Row(
            key: const Key('progress_week_footer'),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (series.isNotEmpty)
                Flexible(
                  child: Text(
                    l10n.progressWeekShort(series.first.isoWeek),
                    key: const Key('progress_week_first'),
                    style: theme.labelSmall!.copyWith(color: c.textMuted),
                  ),
                ),
              if (lastFull != null)
                Flexible(
                  child: Text(
                    l10n.progressLastWeek(
                      lastFull.isUnavailable
                          ? UnitFormatter.noValue
                          : shown(lastFull),
                    ),
                    key: const Key('progress_week_last'),
                    textAlign: TextAlign.center,
                    style: theme.labelSmall!.copyWith(color: c.textMuted),
                  ),
                ),
              Flexible(
                child: Text(
                  l10n.progressNow,
                  key: const Key('progress_week_now'),
                  textAlign: TextAlign.end,
                  style: theme.labelSmall!.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),
          if (!hasAnyRun) ...[
            const SizedBox(height: 8),
            Text(
              l10n.statNoRunYet,
              key: const Key('progress_week_no_runs'),
              style: theme.bodySmall!.copyWith(color: c.textMuted),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Column(
              key: const Key('progress_week_notes'),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final n in notes)
                  Text(n, style: theme.bodySmall!.copyWith(color: c.textMuted)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Dunkle Karte VO₂max: der langfristige Wert als Schätzung (FR-0067, ohne
/// Genauigkeitsangabe, FR-0072), der Verlauf je Woche, die Zahl der
/// verwertbaren Läufe und die Qualitätsstufe (FR-0053) und der Weg zur
/// Erklärung. Fehlt der Wert, steht der Grund statt einer Zahl (FR-0068).
class Vo2ProgressCard extends StatelessWidget {
  const Vo2ProgressCard({
    super.key,
    required this.fitness,
    required this.session,
    required this.onExplain,
  });

  final FitnessOverview fitness;
  final StorageSession session;
  final ExplainValue? onExplain;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    final longTerm = fitness.longTerm;
    final value = longTerm?.value;
    // Im Hero ganzzahlig nach dem Design (FR-0205); die Sichten darunter
    // zeigen eine Stelle. Gerundet wird der angezeigte Wert, damit 45,46
    // (dort 45,5) nicht als 45 daneben steht.
    String heroText(double v) =>
        double.parse(v.toStringAsFixed(1)).round().toString();
    final day = fitness.day;
    // Eine Liste für Linie und Beschreibung, ältester Wert zuerst.
    final trendValues = [
      for (final e in fitness.weeklyLongTerm()) e.value.value!,
    ];
    final trend = [for (final v in trendValues) fitnessNumber(german, v)];
    final asOf = day == null
        ? null
        : l10n.progressEfficiencyAsOf(
            asOfDateText(
              Localizations.localeOf(context).languageCode,
              DateTime.parse(day),
            ),
          );

    return RamuriCard(
      tone: RamuriCardTone.panel,
      child: Builder(
        builder: (context) {
          // Unter der dunklen Karte gilt das dunkle Theme erst hier.
          final c = RamuriColors.of(context);
          final type = RamuriType.of(context);
          final theme = Theme.of(context).textTheme;
          final String reason = fitness.readFailed
              ? l10n.statFitnessFailed
              : (longTerm == null
                    ? l10n.statVo2NoValue
                    : valueOrReasonText(l10n, longTerm, (_) => ''));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                l10n.progressVo2Title,
                eyebrow: true,
                trailing: value == null
                    ? null
                    : RamuriBadge(l10n.progressEstimateBadge),
              ),
              const SizedBox(height: 10),
              if (value == null)
                Text(
                  reason,
                  key: const Key('progress_vo2_reason'),
                  style: theme.bodyMedium,
                )
              else ...[
                // Design: große Zahl links, Verlauf rechts unten bündig in
                // derselben Zeile; die Beschriftung darunter über die ganze
                // Breite. Die Zahl trägt den ganzen Vorlesetext, die
                // Beschriftung wird nicht doppelt vorgelesen.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Semantics(
                        key: const Key('progress_vo2_semantics'),
                        container: true,
                        excludeSemantics: true,
                        label: [
                          l10n.progressVo2Semantics(
                            '${heroText(value)} ${l10n.progressVo2Unit}',
                          ),
                          l10n.statVo2Current,
                          ?asOf,
                        ].join(', '),
                        child: Text.rich(
                          key: const Key('progress_vo2'),
                          TextSpan(
                            children: [
                              TextSpan(text: heroText(value), style: type.hero),
                              TextSpan(
                                text: ' ${l10n.progressVo2Unit}',
                                style: type.unit.copyWith(
                                  color: c.onPanelSoft,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (trendValues.length >= 2) ...[
                      const SizedBox(width: 12),
                      RamuriSparkline(
                        key: const Key('progress_vo2_sparkline'),
                        values: trendValues,
                        semanticLabel: l10n.progressVo2TrendSemantics(
                          '${trend.join(', ')} ${l10n.progressVo2Unit}',
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                ExcludeSemantics(
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.statVo2Current,
                          key: const Key('progress_vo2_current'),
                          style: theme.bodySmall!.copyWith(
                            color: c.onPanelSoft,
                          ),
                        ),
                        if (asOf != null)
                          Text(
                            asOf,
                            key: const Key('progress_vo2_asof'),
                            style: theme.bodySmall!.copyWith(
                              color: c.onPanelSoft,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (value != null && longTerm != null) ...[
                const SizedBox(height: 10),
                Text(
                  l10n.progressVo2Basis(
                    l10n.explCountRuns(longTerm.measurementCount),
                    qualityStageText(l10n, longTerm.quality),
                  ),
                  key: const Key('progress_vo2_basis'),
                  style: theme.bodySmall!.copyWith(color: c.onPanelSoft),
                ),
              ],
              if (day != null)
                TextButton(
                  key: const Key('progress_vo2_explain'),
                  style: TextButton.styleFrom(
                    foregroundColor: c.action,
                    alignment: AlignmentDirectional.centerStart,
                    minimumSize: const Size(0, RamuriTheme.minTarget),
                    padding: EdgeInsets.zero,
                    textStyle: theme.labelLarge!.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () => openValueExplanation(
                    context,
                    session: session,
                    onExplain: onExplain,
                    valueKey: vo2maxLongTermValueKey,
                    day: day,
                  ),
                  child: Text(l10n.progressVo2Link),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Kachel aerobe Effizienz: Veränderung in Prozent mit Vorzeichen (FR-0087),
/// der Vergleich der letzten 4 mit den 4 Wochen davor, als Schätzung gekennzeichnet
/// und von der VO₂max abgegrenzt (FR-0088). Fehlt der Wert, steht der Grund.
class EfficiencyCard extends StatelessWidget {
  const EfficiencyCard({super.key, required this.fitness});

  final FitnessOverview fitness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final german = Localizations.localeOf(context).languageCode == 'de';
    final c = RamuriColors.of(context);
    final type = RamuriType.of(context);
    final theme = Theme.of(context).textTheme;
    final eff = fitness.efficiency;
    final day = fitness.day;
    final value = eff?.value;
    final reason = fitness.readFailed
        ? l10n.statFitnessFailed
        : (eff == null
              ? l10n.statEfficiencyNone
              : valueOrReasonText(l10n, eff, (_) => ''));
    final shown = value == null
        ? null
        : fitnessNumber(german, value, sign: true);
    final asOf = day == null
        ? null
        : l10n.progressEfficiencyAsOf(
            asOfDateText(
              Localizations.localeOf(context).languageCode,
              DateTime.parse(day),
            ),
          );

    return RamuriCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              container: true,
              label: shown == null
                  ? '${l10n.statEfficiency}: $reason'
                  : [
                      '${l10n.statEfficiency}: $shown %',
                      l10n.progressEfficiencyCompare,
                      ?asOf,
                      l10n.uiEstimated,
                    ].join(', '),
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.statEfficiency,
                    style: theme.labelMedium!.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: 4),
                  if (shown == null)
                    Text(
                      reason,
                      key: const Key('progress_efficiency_reason'),
                      style: theme.bodyMedium,
                    )
                  else ...[
                    Text.rich(
                      key: const Key('progress_efficiency'),
                      TextSpan(
                        children: [
                          TextSpan(text: shown, style: type.value),
                          TextSpan(text: ' %', style: type.unit),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.progressEfficiencyCompare,
                      key: const Key('progress_efficiency_compare'),
                      style: theme.labelMedium!.copyWith(color: c.textMuted),
                    ),
                    if (asOf != null)
                      Text(
                        asOf,
                        style: theme.labelMedium!.copyWith(color: c.textMuted),
                      ),
                    const SizedBox(height: 4),
                    const EstimatedMark(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.statEfficiencyNote,
              key: const Key('progress_efficiency_note'),
              style: theme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
