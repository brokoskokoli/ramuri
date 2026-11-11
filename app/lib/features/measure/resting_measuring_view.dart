import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'resting_measure_controller.dart';
import 'resting_widgets.dart';

/// Messung (Design `Messung`): laufender Puls, Pulskurve, Qualitätshinweis,
/// Fortschritt, Abbrechen. Die Uhr läuft auch bei schlechtem Signal weiter.
/// Hinweise zum Justieren gibt es nur zu den Zuständen, die die Auswertung
/// meldet ([RestingLiveHint]); sie sind allgemeine Tipps, keine Diagnose.
class RestingMeasuringView extends StatelessWidget {
  const RestingMeasuringView({super.key, required this.controller});

  final RestingMeasureController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    final ctrl = controller;
    final starting = ctrl.phase == RestingMeasurePhase.starting;
    final quality = ctrl.liveQuality;
    final hint = ctrl.liveHint;
    final good = quality == PpgQuality.good && hint == null;
    final seconds = restingWindowSeconds();
    final done = (ctrl.progress * seconds).floor();
    final pulse = ctrl.livePulse;

    final signal = switch (quality) {
      PpgQuality.good => (l10n.measureSignalGood, 3),
      PpgQuality.limited => (l10n.measureSignalLimited, 2),
      PpgQuality.unusable => (l10n.measureSignalWeak, 1),
      null => (l10n.measureSignalChecking, 1),
    };

    final (hintTitle, hintBody, hintIcon, warn) = switch (hint) {
      RestingLiveHint.noFinger => (
        l10n.measureHintNoFingerTitle,
        l10n.measureHintNoFingerBody,
        Icons.error_outline,
        true,
      ),
      RestingLiveHint.weakSignal => (
        l10n.measureHintWeakTitle,
        l10n.measureHintWeakBody,
        Icons.error_outline,
        true,
      ),
      RestingLiveHint.flatSignal => (
        l10n.measureHintFlatTitle,
        l10n.measureHintFlatBody,
        Icons.error_outline,
        true,
      ),
      RestingLiveHint.disturbances => (
        l10n.measureHintDisturbTitle,
        l10n.measureHintDisturbBody,
        Icons.error_outline,
        true,
      ),
      null when good => (
        l10n.measureHintOkTitle,
        l10n.measureHintOkBody,
        Icons.check_circle_outline,
        false,
      ),
      null => (
        l10n.measureHintNeutralTitle,
        l10n.measureHintNeutralBody,
        Icons.info_outline,
        false,
      ),
    };

    final progressLabel = starting
        ? l10n.measureProgressStarting
        : ctrl.evaluating
        ? l10n.measureProgressEvaluating
        : ctrl.settling
        ? l10n.measureProgressSettling
        : hint != null
        ? l10n.measureProgressAdjust
        : l10n.measureProgressSteady;

    return RestingPage(
      header: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          RestingCancelButton(
            key: const Key('measure_cancel'),
            onPressed: () => controller.cancel(),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                l10n.measureMeasureHeader(
                  restingPostureLabel(l10n, ctrl.posture),
                ),
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
        ],
      ),
      sections: [
        Semantics(
          container: true,
          label: l10n.measurePulseLabel,
          child: Column(
            children: [
              Text(l10n.measurePulseLabel, style: theme.textTheme.labelSmall),
              Text(
                pulse?.toString() ?? '–',
                key: const Key('measure_pulse'),
                style: theme.textTheme.displayLarge!.copyWith(
                  color: pulse == null ? c.textMuted : c.text,
                ),
              ),
              if (pulse == null)
                Text(
                  l10n.measurePulseSearching,
                  style: theme.textTheme.labelSmall,
                )
              else
                const EstimatedMark(),
            ],
          ),
        ),
        RestingCard(
          radius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    l10n.measureCurveTitle(restingCurveSeconds.round()),
                    style: theme.textTheme.labelSmall,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SignalBars(level: signal.$2),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          signal.$1,
                          key: const Key('measure_signal'),
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Semantics(
                image: true,
                label: l10n.measureCurveSemantics,
                child: ExcludeSemantics(
                  child: PulseCurve(values: ctrl.curve, strong: good),
                ),
              ),
            ],
          ),
        ),
        Semantics(
          liveRegion: true,
          container: true,
          child: RestingCard(
            key: const Key('measure_hint'),
            radius: 20,
            color: warn ? c.emberTint : c.tint,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(hintIcon, size: 22, color: c.text),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(hintTitle, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(hintBody, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                progressLabel,
                key: const Key('measure_progress_label'),
                style: theme.textTheme.labelMedium,
              ),
              Text(
                l10n.measureProgressValue(done, seconds),
                key: const Key('measure_progress_value'),
                style: RamuriType.of(context).unitLarge.copyWith(color: c.text),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            label: l10n.measureProgressSemantics,
            value: l10n.measureProgressValue(done, seconds),
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  key: const Key('measure_progress'),
                  value: ctrl.evaluating ? null : ctrl.progress,
                  minHeight: 10,
                  backgroundColor: c.track,
                  color: c.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.measureBreatheNote, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
