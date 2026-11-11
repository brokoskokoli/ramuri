import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'resting_measure_controller.dart';
import 'resting_widgets.dart';

/// Ergebnis mit Wert (Design `Ergebnis`): der Wert als Schätzung mit Glutpunkt
/// vor „geschätzt“, Qualität, Haltung und Zeitpunkt, Übernehmen oder
/// Verwerfen. Übernommen wird nur auf den Tipp auf „Ins Profil übernehmen“.
class RestingResultView extends StatelessWidget {
  const RestingResultView({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final RestingMeasureController controller;

  /// Schließen ohne Übernehmen und ohne Verwerfen.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    final ctrl = controller;
    final r = ctrl.result!;
    final lang = Localizations.localeOf(context).toString();
    final at = r.measuredAt.toLocal();
    final time =
        '${DateFormat.MMMEd(lang).format(at)} · ${DateFormat.Hm(lang).format(at)}';
    final limited = r.quality == PpgQuality.limited;
    final rest = r.restElapsed;
    final prev = ctrl.previousRestingBpm;
    final source = l10n.measureResultSource(restingWindowSeconds());
    final previous = prev == null
        ? null
        : ctrl.previousOrigin == null
        ? l10n.measureResultPreviousManual(prev)
        : l10n.measureResultPreviousCamera(prev);
    final error = ctrl.adoptRejection != null
        ? l10n.measureAdoptRejected
        : ctrl.adoptFailed
        ? l10n.measureAdoptFailed
        : null;

    Widget row(String label, String value, {bool last = false}) => Container(
      constraints: const BoxConstraints(minHeight: 48),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.track)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium!.copyWith(color: c.textMuted),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );

    return RestingPage(
      header: Row(
        children: [
          RestingRoundButton(
            key: const Key('measure_close'),
            icon: Icons.close,
            label: l10n.measureCloseNoAdopt,
            onPressed: ctrl.adopting ? null : onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.measureResultTitle,
              style: RamuriType.of(context).valueSmall,
            ),
          ),
        ],
      ),
      sections: [
        RestingCard(
          color: c.accentPanel,
          radius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.measureResultLabel,
                style: theme.textTheme.labelMedium!.copyWith(color: c.textSoft),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${r.bpm}',
                    key: const Key('measure_result_bpm'),
                    style: theme.textTheme.displayMedium!.copyWith(
                      fontFeatures: null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Flexible(child: EstimatedMark()),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                previous == null ? source : '$source $previous',
                style: theme.textTheme.bodyMedium!.copyWith(color: c.textSoft),
              ),
            ],
          ),
        ),
        RestingCard(
          radius: 20,
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
                    l10n.measureResultQualityTitle,
                    style: theme.textTheme.titleSmall,
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SignalBars(level: limited ? 2 : 3),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          limited
                              ? l10n.measureQualityLimited
                              : l10n.measureQualityGood,
                          key: const Key('measure_result_quality'),
                          style: theme.textTheme.titleSmall!.copyWith(
                            color: limited ? c.text : c.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (limited) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.measureResultLimitedNote,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        RestingCard(
          radius: 20,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              row(
                l10n.measureResultPosture,
                restingPostureLabel(l10n, r.posture),
              ),
              row(l10n.measureResultTime, time),
              row(
                l10n.measureResultBefore,
                rest == null
                    ? l10n.measureResultBeforeNone
                    : l10n.measureResultBeforeRest(restingClock(rest)),
                last: true,
              ),
            ],
          ),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: RestingCard(
              key: const Key('measure_adopt_error'),
              radius: 20,
              color: c.emberTint,
              child: Text(error, style: theme.textTheme.bodyMedium),
            ),
          ),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: RamuriPrimaryButton(
              key: const Key('measure_adopt'),
              label: l10n.measureAdopt,
              onPressed: ctrl.canAdopt ? () => ctrl.adopt() : null,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 56,
            child: RamuriSecondaryButton(
              key: const Key('measure_discard'),
              label: l10n.measureDiscard,
              onPressed: ctrl.adopting ? null : ctrl.discard,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.measureResultNote,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
