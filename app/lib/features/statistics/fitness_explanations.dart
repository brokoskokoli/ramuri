import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_card.dart';
import 'fitness_section.dart' show fitnessNumber, reasonText;
import 'statistics_view.dart' show StatHeading;

/// Die Sätze der Erklärungen (FR-0180, FR-0181) zur Fitness: Entwicklung der
/// VO₂max-Schätzung und Datenqualität der aktuellen Werte. Nur mit Daten: Wo
/// keine Erklärung vorliegt (zu wenige Läufe, guter Wert), steht nichts da.
List<String> fitnessExplanationLines(
  BuildContext context,
  FitnessOverview fitness,
  DateTime today,
) {
  final l = AppLocalizations.of(context);
  final material = MaterialLocalizations.of(context);
  final german = Localizations.localeOf(context).languageCode == 'de';
  final lines = <String>[];

  final development = explainFitnessDevelopment([
    for (final e in fitness.runEstimates)
      if (e.value.value != null)
        FitnessPoint(DateTime.parse('${e.day}T00:00:00Z'), e.value.value!),
  ], today: today);
  if (development != null) {
    String day(EvidenceKey k) =>
        material.formatMediumDate(development.evidenceOf(k)! as DateTime);
    String value(EvidenceKey k) =>
        fitnessNumber(german, (development.evidenceOf(k)! as num).toDouble());
    final n = (development.evidenceOf(EvidenceKey.runCount)! as num).round();
    final text = switch (development.code) {
      'up' => l.progressExplainFitnessUp,
      'down' => l.progressExplainFitnessDown,
      _ => l.progressExplainFitnessSame,
    };
    // Die drei Texte haben dieselben Platzhalter.
    lines.add(
      text(
        day(EvidenceKey.fromDay),
        day(EvidenceKey.toDay),
        value(EvidenceKey.fromValue),
        value(EvidenceKey.toValue),
        n,
      ),
    );
  }

  void quality(String label, ComputedValue? v) {
    if (v == null) return;
    final q = explainDataQuality(v);
    if (q == null) return;
    if (q.code == 'quality.provisional') {
      lines.add(
        l.progressExplainQualityProvisional(
          label,
          v.measurementCount,
          v.method,
          v.methodVersion.toString(),
        ),
      );
    } else if (v.unavailableReason != null) {
      lines.add(
        l.progressExplainQualityMissing(
          label,
          reasonText(l, v.unavailableReason!),
        ),
      );
    }
  }

  quality(l.statVo2Current, fitness.longTerm);
  quality(l.statEfficiency, fitness.efficiency);
  return lines;
}

/// „Was bedeutet das?“ auf der Fortschritt-Seite: Erklärungen zur Fitness
/// (FR-0179, FR-0180). Ohne Erklärung gibt es die Karte nicht.
class FitnessExplanationCard extends StatelessWidget {
  const FitnessExplanationCard({
    super.key,
    required this.fitness,
    required this.today,
  });

  final FitnessOverview fitness;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final lines = fitnessExplanationLines(context, fitness, today);
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: RamuriCard(
        key: const Key('stat_explain_card'),
        radius: 22,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatHeading(l.progressExplainTitle),
            for (var i = 0; i < lines.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(lines[i], key: Key('stat_explain_line_$i')),
              ),
          ],
        ),
      ),
    );
  }
}
