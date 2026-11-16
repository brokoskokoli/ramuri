import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';

/// Schalter „Plananpassung an Erholung: adaptiv / fix“ mit einem Satz
/// Erklärung (FR-0216). [onChanged] `null`: gesperrt (eine Aktion läuft).
class PlanAdaptationCard extends StatelessWidget {
  const PlanAdaptationCard({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final PlanAdaptationMode mode;
  final ValueChanged<PlanAdaptationMode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final change = onChanged;
    return RamuriCard(
      key: const Key('plan_adapt_card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l.planAdaptTitle, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          SegmentedButton<PlanAdaptationMode>(
            key: const Key('plan_adapt_switch'),
            segments: [
              ButtonSegment(
                value: PlanAdaptationMode.adaptive,
                label: Text(
                  l.planAdaptAdaptive,
                  key: const Key('plan_adapt_adaptive'),
                ),
              ),
              ButtonSegment(
                value: PlanAdaptationMode.fixed,
                label: Text(
                  l.planAdaptFixed,
                  key: const Key('plan_adapt_fixed'),
                ),
              ),
            ],
            selected: {mode},
            onSelectionChanged: change == null ? null : (s) => change(s.first),
          ),
          const SizedBox(height: 10),
          Text(l.planAdaptNote),
        ],
      ),
    );
  }
}
