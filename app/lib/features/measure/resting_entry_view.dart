import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'resting_measure_controller.dart';
import 'resting_widgets.dart';

import 'package:core/core.dart';

/// Einstieg der Ruhepuls-Messung (Design `Main`): Erklärbild, Haltung,
/// Ruhephase 1 bis 15 min oder sofort messen.
class RestingEntryView extends StatefulWidget {
  const RestingEntryView({
    super.key,
    required this.controller,
    required this.onClose,
  });

  final RestingMeasureController controller;
  final VoidCallback onClose;

  @override
  State<RestingEntryView> createState() => _RestingEntryViewState();
}

class _RestingEntryViewState extends State<RestingEntryView> {
  /// Erst entspannen (Vorgabe, empfohlen) oder sofort messen.
  bool _relax = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    final ctrl = widget.controller;
    final seconds = restingWindowSeconds();
    return RestingPage(
      header: Row(
        children: [
          RestingRoundButton(
            key: const Key('measure_back'),
            icon: Icons.chevron_left,
            label: l10n.measureBack,
            onPressed: widget.onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.measureTitle,
              style: RamuriType.of(context).valueSmall,
            ),
          ),
        ],
      ),
      sections: [
        RestingCard(
          radius: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const FingerIllustration(),
              const SizedBox(height: 10),
              Text(l10n.measureFingerTitle, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(l10n.measureFingerBody, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.measurePostureLabel, style: theme.textTheme.labelSmall),
            const SizedBox(height: 8),
            RamuriSegmentedToggle<RestingPosture>(
              semanticLabel: l10n.measurePostureLabel,
              expanded: true,
              style: RamuriSegmentedStyle.soft,
              selected: ctrl.posture,
              onChanged: ctrl.setPosture,
              segments: [
                RamuriSegment(
                  value: RestingPosture.sitting,
                  label: l10n.measurePostureSitting,
                ),
                RamuriSegment(
                  value: RestingPosture.lying,
                  label: l10n.measurePostureLying,
                ),
              ],
            ),
          ],
        ),
        RestingCard(
          radius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              _ModeTile(
                key: const Key('measure_mode_relax'),
                selected: _relax,
                title: l10n.measureModeRelaxTitle,
                body: l10n.measureModeRelaxBody(seconds),
                onTap: () => setState(() => _relax = true),
              ),
              if (_relax)
                Padding(
                  padding: const EdgeInsets.only(left: 34, bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.measureDuration,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      RestingRoundButton(
                        key: const Key('measure_minutes_minus'),
                        icon: Icons.remove,
                        label: l10n.measureShorter,
                        onPressed: ctrl.restMinutes > restingMinRestMinutes
                            ? () => ctrl.setRestMinutes(ctrl.restMinutes - 1)
                            : null,
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 72),
                        child: Text(
                          l10n.measureMinutes(ctrl.restMinutes),
                          key: const Key('measure_minutes'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      RestingRoundButton(
                        key: const Key('measure_minutes_plus'),
                        icon: Icons.add,
                        label: l10n.measureLonger,
                        onPressed: ctrl.restMinutes < restingMaxRestMinutes
                            ? () => ctrl.setRestMinutes(ctrl.restMinutes + 1)
                            : null,
                      ),
                    ],
                  ),
                ),
              Divider(height: 1, color: c.track),
              _ModeTile(
                key: const Key('measure_mode_now'),
                selected: !_relax,
                title: l10n.measureModeNowTitle,
                body: l10n.measureModeNowBody(seconds),
                onTap: () => setState(() => _relax = false),
              ),
            ],
          ),
        ),
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 56,
            child: RamuriPrimaryButton(
              key: const Key('measure_start'),
              label: _relax ? l10n.measureStartRelax : l10n.measureStartNow,
              onPressed: () => _relax ? ctrl.startRest() : ctrl.startNow(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.photo_camera_outlined, size: 18, color: c.textMuted),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.measureCameraNote,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    super.key,
    required this.selected,
    required this.title,
    required this.body,
    required this.onTap,
  });

  final bool selected;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      excludeSemantics: true,
      label: '$title. $body',
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: RamuriTheme.minTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 22,
                  color: selected ? c.accent : c.textMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(body, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
