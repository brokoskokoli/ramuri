import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Empfehlung bei „fix“ unter der Karte „Erholung“ (FR-0216, PAR-173): nur
/// der Satz und der Knopf „Locker laufen“ (Ersetzen der heutigen Einheit
/// nach Bestätigung); der Plan selbst bleibt unverändert. Wann sie steht,
/// entscheidet `recoveryRecommendsEasy`.
class PlanAdaptRecommendation extends StatelessWidget {
  const PlanAdaptRecommendation({
    super.key = const Key('plan_adapt_recommendation'),
    required this.onEasyRun,
  });

  /// `null`, solange eine Aktion läuft oder die Einheit nicht ersetzbar ist.
  final VoidCallback? onEasyRun;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    return RamuriCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.planAdaptRecommendEasy,
            key: const Key('plan_adapt_recommendation_text'),
            style: t.bodyMedium,
          ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('plan_adapt_easy_run'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, RamuriTheme.minTarget),
            ),
            onPressed: onEasyRun,
            child: Text(l.recoveryEasyRun),
          ),
        ],
      ),
    );
  }
}
