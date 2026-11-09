import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/section_heading.dart';
import 'recalculation_controller.dart';

/// Angebot der Neuberechnung in den Einstellungen: Grund, "Neu berechnen" und
/// "Nicht jetzt", während der Berechnung Fortschritt und Sperre, danach
/// Ergebnis oder Fehlermeldung. Ohne Angebot und ohne Ergebnis zeigt sie
/// nichts.
class RecalculationCard extends StatelessWidget {
  const RecalculationCard({super.key, required this.controller});

  final RecalculationController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l10n = AppLocalizations.of(context);
      final offer = controller.offer;
      final phase = controller.phase;
      if (offer == null && phase != RecalculationPhase.done) {
        return const SizedBox.shrink(key: Key('recalc_none'));
      }
      final busy = controller.busy;
      final statusKey = const Key('recalc_status');
      final String? status = switch (phase) {
        RecalculationPhase.running => l10n.recalcRunning,
        RecalculationPhase.failed => l10n.recalcFailed,
        RecalculationPhase.declineFailed => l10n.recalcDeclineFailed,
        RecalculationPhase.done => l10n.recalcDone(
          controller.result?.runCount ?? 0,
        ),
        RecalculationPhase.idle => null,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: RamuriCard(
          key: const Key('recalc_dialog'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (offer != null) ...[
                SectionHeading(l10n.recalcTitle),
                const SizedBox(height: 8),
                Text(l10n.recalcIntro),
                for (final c in RecalculationCause.values)
                  if (offer.causes.contains(c))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• ${_causeText(l10n, c)}',
                        key: Key('recalc_cause_${c.name}'),
                      ),
                    ),
                const SizedBox(height: 8),
                Text(l10n.recalcKeepsOriginal),
                const SizedBox(height: 12),
              ],
              if (busy)
                const LinearProgressIndicator(key: Key('recalc_progress')),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(status, key: statusKey),
                ),
              if (offer != null) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    RamuriPrimaryButton(
                      key: const Key('recalc_confirm'),
                      onPressed: busy ? null : controller.confirm,
                      label: phase == RecalculationPhase.failed
                          ? l10n.recalcRetry
                          : l10n.recalcConfirm,
                    ),
                    RamuriSecondaryButton(
                      key: const Key('recalc_decline'),
                      onPressed: busy ? null : controller.decline,
                      label: l10n.recalcDecline,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  String _causeText(AppLocalizations l10n, RecalculationCause c) => switch (c) {
    RecalculationCause.heartRateBasis => l10n.recalcCauseHeartRate,
    RecalculationCause.algorithmVersion => l10n.recalcCauseAlgorithm,
    RecalculationCause.loadProfile => l10n.recalcCauseLoadProfile,
    RecalculationCause.personalFactor => l10n.recalcCauseLoadFactor,
  };
}
