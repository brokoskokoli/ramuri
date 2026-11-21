import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ramuri_buttons.dart';
import '../../ui/ramuri_card.dart';
import '../../ui/section_heading.dart';
import 'recalculation_controller.dart';

/// Angebot der Neuberechnung in den Einstellungen: Grund, "Neu berechnen" und
/// "Nicht jetzt", während der Berechnung Fortschritt und Sperre, danach eine
/// Fehlermeldung in der Karte. Das Ergebnis kommt als Snackbar mit der
/// Standarddauer wie die übrigen Bestätigungen der App (FR-0058); die Karte
/// steht danach nicht mehr da, außer es gibt schon ein weiteres Angebot.
/// Ohne Angebot zeigt sie, solange ein Lauf nicht berechenbar ist, eine
/// eigene Karte mit „Neu berechnen“, die nur diese Läufe erneut versucht
/// (FR-0219); nach einem gescheiterten Versuch steht dort die Fehlermeldung.
/// Sonst zeigt sie nichts.
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
      if (offer == null) {
        if (controller.hasUncomputable ||
            phase == RecalculationPhase.running ||
            phase == RecalculationPhase.retryFailed) {
          return _uncomputableCard(l10n);
        }
        return const SizedBox.shrink(key: Key('recalc_none'));
      }
      final busy = controller.busy;
      final statusKey = const Key('recalc_status');
      final String? status = switch (phase) {
        RecalculationPhase.running => l10n.recalcRunning,
        RecalculationPhase.failed => l10n.recalcFailed,
        RecalculationPhase.declineFailed => l10n.recalcDeclineFailed,
        RecalculationPhase.idle || RecalculationPhase.retryFailed => null,
      };
      return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: RamuriCard(
          key: const Key('recalc_dialog'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
              if (busy)
                const LinearProgressIndicator(key: Key('recalc_progress')),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(status, key: statusKey),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  RamuriPrimaryButton(
                    key: const Key('recalc_confirm'),
                    onPressed: busy ? null : () => _confirm(context),
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
          ),
        ),
      );
    },
  );

  /// Karte „Nicht berechenbare Läufe“ ohne Angebot (FR-0219). Die
  /// Schaltfläche steht nur, solange es einen solchen Lauf gibt: nach einem
  /// gescheiterten Versuch beginnt der Zähler neu, der Start versucht ihn
  /// wieder.
  Widget _uncomputableCard(AppLocalizations l10n) {
    final busy = controller.busy;
    final failed = controller.phase == RecalculationPhase.retryFailed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: RamuriCard(
        key: const Key('recalc_uncomputable'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(l10n.recalcUncomputableTitle),
            const SizedBox(height: 8),
            Text(l10n.recalcUncomputableIntro),
            if (busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(key: Key('recalc_progress')),
            ],
            if (failed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.recalcUncomputableFailed,
                  key: const Key('recalc_status'),
                ),
              ),
            if (busy || controller.hasUncomputable) ...[
              const SizedBox(height: 12),
              RamuriPrimaryButton(
                key: const Key('recalc_uncomputable_confirm'),
                onPressed: busy ? null : controller.retryUncomputable,
                label: l10n.recalcConfirm,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Bestätigt und meldet den Erfolg als Snackbar ohne eigene Dauer. Der
  /// Messenger wird vor dem Warten geholt: die Karte kann danach verschwunden
  /// sein.
  Future<void> _confirm(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = AppLocalizations.of(context);
    final result = await controller.confirm();
    if (result == null) return;
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('recalc_done'),
          content: Text(l10n.recalcDone(result.runCount)),
        ),
      );
  }

  String _causeText(AppLocalizations l10n, RecalculationCause c) => switch (c) {
    RecalculationCause.heartRateBasis => l10n.recalcCauseHeartRate,
    RecalculationCause.algorithmVersion => l10n.recalcCauseAlgorithm,
    RecalculationCause.loadProfile => l10n.recalcCauseLoadProfile,
    RecalculationCause.personalFactor => l10n.recalcCauseLoadFactor,
    RecalculationCause.loadCoefficients => l10n.recalcCauseLoadCoefficients,
  };
}
