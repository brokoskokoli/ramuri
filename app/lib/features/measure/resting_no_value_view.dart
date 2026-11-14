import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'resting_measure_controller.dart';
import 'resting_widgets.dart';

/// Kein Wert (Design `KeinWert`): der Grund aus dem Controller (Ergebnis ohne
/// Wert oder Abbruch), „Noch einmal“ nur, wenn der Controller es erlaubt, und
/// der Hinweis, dass die Eingabe von Hand bleibt. Die Tipps sind allgemein;
/// es gibt keine Diagnose, was am Finger falsch war.
class RestingNoValueView extends StatelessWidget {
  const RestingNoValueView({
    super.key,
    required this.controller,
    required this.onClose,
    this.onManual,
  });

  final RestingMeasureController controller;
  final VoidCallback onClose;

  /// „Selbst eintragen“; ohne (Morgenmessung) fehlt der Hinweis samt Knopf.
  final VoidCallback? onManual;

  /// Titel, Text und ob die Tipps zum Auflegen des Fingers passen.
  static (String, String, bool) reason(
    AppLocalizations l,
    RestingMeasureController c,
  ) {
    final result = c.result;
    if (c.phase == RestingMeasurePhase.result && result != null) {
      final r = result.reasons;
      if (r.contains(PpgQualityReason.frameGap)) {
        return (l.measureWhyGapTitle, l.measureWhyGapBody, true);
      }
      if (r.contains(PpgQualityReason.noFinger)) {
        return (l.measureWhyNoFingerTitle, l.measureWhyNoFingerBody, true);
      }
      if (r.contains(PpgQualityReason.flatSignal)) {
        return (l.measureWhyFlatTitle, l.measureWhyFlatBody, true);
      }
      if (r.contains(PpgQualityReason.weakSignal) ||
          r.contains(PpgQualityReason.lowSignalQuality)) {
        return (l.measureWhyWeakTitle, l.measureWhyWeakBody, true);
      }
      if (r.contains(PpgQualityReason.tooManyDisturbances) ||
          r.contains(PpgQualityReason.someDisturbances)) {
        return (l.measureWhyDisturbTitle, l.measureWhyDisturbBody, true);
      }
      if (r.contains(PpgQualityReason.insufficientData)) {
        return (l.measureWhyDataTitle, l.measureWhyDataBody, true);
      }
      return (l.measureWhyFailedTitle, l.measureWhyFailedBody, false);
    }
    return switch (c.stopCause) {
      RestingStopCause.permissionDenied => (
        l.measureStopPermissionTitle,
        l.measureStopPermissionBody,
        false,
      ),
      RestingStopCause.noCamera => (
        l.measureStopNoCameraTitle,
        l.measureStopNoCameraBody,
        false,
      ),
      RestingStopCause.noFlash => (
        l.measureStopNoFlashTitle,
        l.measureStopNoFlashBody,
        false,
      ),
      RestingStopCause.busy => (
        l.measureStopBusyTitle,
        l.measureStopBusyBody,
        false,
      ),
      RestingStopCause.disconnected => (
        l.measureStopDisconnectedTitle,
        l.measureStopDisconnectedBody,
        false,
      ),
      RestingStopCause.frameRate => (
        l.measureStopFrameRateTitle,
        l.measureStopFrameRateBody,
        false,
      ),
      RestingStopCause.interrupted => (
        l.measureWhyGapTitle,
        l.measureWhyGapBody,
        true,
      ),
      RestingStopCause.background => (
        l.measureStopBackgroundTitle,
        l.measureStopBackgroundBody,
        false,
      ),
      _ => (l.measureStopErrorTitle, l.measureStopErrorBody, false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    final (title, body, tips) = reason(l10n, controller);
    final dots = [l10n.measureTip1, l10n.measureTip2, l10n.measureTip3];
    return RestingPage(
      header: Row(
        children: [
          RestingRoundButton(
            key: const Key('measure_close'),
            icon: Icons.close,
            label: l10n.measureClose,
            onPressed: onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.measureNoValueTitle,
              style: RamuriType.of(context).valueSmall,
            ),
          ),
        ],
      ),
      sections: [
        Semantics(
          liveRegion: true,
          container: true,
          child: RestingCard(
            key: const Key('measure_reason'),
            color: c.emberTint,
            radius: 24,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 22, color: c.text),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(title, style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        if (tips)
          RestingCard(
            key: const Key('measure_tips'),
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.measureTipsTitle, style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                for (final t in dots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const SizedBox.square(dimension: 8),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(t, style: theme.textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.canRetry) ...[
            SizedBox(
              height: 56,
              child: RamuriPrimaryButton(
                key: const Key('measure_retry'),
                label: l10n.measureRetry,
                onPressed: () => controller.retry(),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.measureRetryNote,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          if (onManual != null) ...[
            Divider(height: 1, color: c.outline),
            const SizedBox(height: 10),
            Text(
              l10n.measureManualNote,
              style: theme.textTheme.bodyMedium!.copyWith(color: c.textMuted),
            ),
            RestingTextLink(
              key: const Key('measure_manual'),
              label: l10n.measureManualAction,
              alignment: Alignment.centerLeft,
              onPressed: onManual!,
            ),
          ],
        ],
      ),
    );
  }
}
