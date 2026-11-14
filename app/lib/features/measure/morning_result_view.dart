import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'morning_measure_controller.dart';
import 'morning_trend_screen.dart';
import 'resting_widgets.dart';

/// Beschriftung der Schlafstufen in Stunden (PAR-164K), in der Reihenfolge von
/// [SleepBand.values].
const List<String> morningSleepLabels = ['< 5', '5–6', '6–7', '7–8', '> 8'];

/// „Heute 6:42, liegend“ für eine gespeicherte Messung (Ortszeit).
String morningWhenLabel(
  AppLocalizations l10n,
  String locale,
  MorningMeasurement m,
) => l10n.morningResultWhen(
  DateFormat.jm(locale).format(m.measuredAt.add(m.utcOffset)),
  restingPostureLabel(l10n, m.posture).toLowerCase(),
);

/// Ruhepuls mit einer Nachkommastelle, in der Sprache der App.
String morningHrText(String locale, double? bpm) => bpm == null
    ? '–'
    : NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: 1,
      ).format(roundRestingHr(bpm));

/// Ergebnis der Morgenmessung (Design `morgen/Ergebnis`): gespeichert (gut,
/// eingeschränkt, außerhalb des Fensters, zählt nicht) mit freiwilliger
/// Schlafstufe, oder zu ungenau mit „Noch einmal messen“. Die Werte sind
/// geschätzt und tragen keine Einordnung.
class MorningResultView extends StatelessWidget {
  const MorningResultView({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final MorningMeasureController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    final locale = Localizations.localeOf(context).toString();
    final o = controller.outcome;
    final m = controller.stored;
    final bad = o == MorningOutcome.unusable;
    final failed = o == MorningOutcome.saveFailed;
    final pending = o == MorningOutcome.pending;
    final limited = o == MorningOutcome.limited;
    final marks = controller.marks;
    final rmssdMark = marks == null ? null : morningMarkText(l10n, marks.rmssd);
    final title = bad
        ? l10n.morningResultTooNoisy
        : m != null
        ? l10n.morningResultSaved
        : l10n.morningSaving;
    return RestingPage(
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              key: const Key('morning_result_title'),
              style: RamuriType.of(context).valueSmall,
            ),
          ),
          if (m != null)
            Text(
              morningWhenLabel(l10n, locale, m),
              key: const Key('morning_result_when'),
              style: theme.textTheme.labelMedium!.copyWith(color: c.textMuted),
            ),
        ],
      ),
      sections: [
        if (m != null)
          RestingCard(
            radius: 24,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _Figure(
                        label: l10n.morningRestingHr,
                        value: morningHrText(locale, m.restingHrBpm),
                        valueKey: const Key('morning_hr'),
                      ),
                    ),
                    Expanded(
                      child: _Figure(
                        label: l10n.morningRmssd,
                        value: m.rmssdMs == null
                            ? '–'
                            : m.rmssdMs!.round().toString(),
                        muted:
                            m.rmssdMs == null || (marks?.rmssdLocked ?? false),
                        valueKey: const Key('morning_rmssd'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const EmberDot(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.morningEstimated(
                          m.quality == PpgQuality.good
                              ? l10n.morningQualityGood
                              : l10n.morningQualityLimited,
                        ),
                        key: const Key('morning_quality'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
                if (rmssdMark != null && m.rmssdMs != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    rmssdMark,
                    key: const Key('morning_rmssd_mark'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                if (limited || (m.rmssdMs == null && !bad)) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.morningNoRmssd,
                    key: const Key('morning_no_rmssd'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        if (o == MorningOutcome.outsideWindow)
          _Note(
            key: const Key('morning_note_outside'),
            text: l10n.morningOutside(
              controller.window.startHour,
              controller.window.endHour,
            ),
          ),
        if (o == MorningOutcome.notCounted)
          _Note(
            key: const Key('morning_note_not_counted'),
            text: l10n.morningNotCounted,
          ),
        if (bad)
          RestingCard(
            key: const Key('morning_no_value'),
            radius: 24,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.morningNoValueTitle,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.morningNoValueBody,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        if (failed)
          _Note(
            key: const Key('morning_save_failed'),
            text: l10n.morningSaveFailed,
            warn: true,
          ),
        if (m != null) _Sleep(controller: controller),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (bad) ...[
            SizedBox(
              height: 56,
              child: RamuriPrimaryButton(
                key: const Key('morning_again'),
                label: l10n.morningAgain,
                onPressed: controller.canRepeat ? controller.repeat : null,
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('morning_not_again'),
              onPressed: onClose,
              child: Text(l10n.morningNotAgain),
            ),
          ] else if (failed) ...[
            SizedBox(
              height: 56,
              child: RamuriPrimaryButton(
                key: const Key('morning_save_retry'),
                label: l10n.morningSaveRetry,
                onPressed: controller.retrySave,
              ),
            ),
            TextButton(onPressed: onClose, child: Text(l10n.morningNotAgain)),
          ] else
            SizedBox(
              height: 56,
              child: RamuriPrimaryButton(
                key: const Key('morning_done'),
                label: l10n.morningDone,
                onPressed: pending ? null : onClose,
              ),
            ),
          const SizedBox(height: 10),
          // Außerhalb des Fensters und bei zweiter Messung sagt der Hinweis oben
          // schon, dass die Messung nicht zählt.
          if (!pending &&
              !failed &&
              o != MorningOutcome.outsideWindow &&
              o != MorningOutcome.notCounted)
            Text(
              bad ? l10n.morningFooterBad : l10n.morningFooterCounts,
              key: const Key('morning_footer'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    required this.valueKey,
    this.muted = false,
  });

  final String label;
  final String value;
  final Key valueKey;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        Text(
          value,
          key: valueKey,
          style: Theme.of(context).textTheme.displayMedium!
              .copyWith(color: muted ? c.textMuted : c.text),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.text, this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    return RestingCard(
      radius: 16,
      color: warn ? c.emberTint : c.tint,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warn ? Icons.error_outline : Icons.info_outline,
            size: 18,
            color: c.text,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

/// Freiwillige Schlafdauer in fünf Stufen; dieselbe Stufe noch einmal wählt ab.
class _Sleep extends StatelessWidget {
  const _Sleep({required this.controller});

  final MorningMeasureController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    final selected = controller.sleepBand;
    return RestingCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.morningSleepTitle, style: theme.textTheme.titleSmall),
          Text(l10n.morningSleepHint, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Semantics(
            container: true,
            label: l10n.morningSleepTitle,
            child: Row(
              children: [
                for (final b in SleepBand.values) ...[
                  if (b.index > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Semantics(
                      inMutuallyExclusiveGroup: true,
                      checked: selected == b,
                      button: true,
                      excludeSemantics: true,
                      label:
                          '${morningSleepLabels[b.index]} ${l10n.morningSleepUnit}',
                      onTap: () => controller.setSleepBand(b),
                      child: InkWell(
                        key: Key('morning_sleep_${b.code}'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: controller.savingSleep
                            ? null
                            : () => controller.setSleepBand(b),
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: RamuriTheme.minTarget,
                          ),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            color: selected == b ? c.tint : null,
                            border: Border.all(
                              color: selected == b ? c.accent : c.outline,
                            ),
                          ),
                          child: Text(
                            morningSleepLabels[b.index],
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(l10n.morningSleepUnit, style: theme.textTheme.labelSmall),
          if (controller.sleepFailed) ...[
            const SizedBox(height: 6),
            Text(
              l10n.morningSleepFailed,
              key: const Key('morning_sleep_failed'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
