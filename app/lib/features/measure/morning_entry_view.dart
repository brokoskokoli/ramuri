import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'morning_belt.dart';
import 'morning_measure_controller.dart';
import 'resting_widgets.dart';

/// Einstieg der Morgenmessung (Design `morgen/Main`): drei Schritte, Haltung
/// (liegend als Vorgabe, nie stehend), Fingerhinweis, Start der festen
/// Ruhephase. Keine Wahl der Ruhephasenlänge und kein sofortiges Messen.
class MorningEntryView extends StatelessWidget {
  const MorningEntryView({
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
    final engine = controller.engine;
    final lying = engine.posture == RestingPosture.lying;
    return RestingPage(
      header: Row(
        children: [
          RestingRoundButton(
            key: const Key('measure_back'),
            icon: Icons.chevron_left,
            label: l10n.measureBack,
            onPressed: onClose,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                l10n.morningTitle,
                style: RamuriType.of(context).valueSmall,
              ),
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
              for (final (i, t) in [
                l10n.morningStep1,
                l10n.morningStep2,
                l10n.morningStep3,
              ].indexed) ...[
                if (i > 0) const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ExcludeSemantics(
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: c.tint,
                        child: Text(
                          '${i + 1}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(t, style: theme.textTheme.bodyMedium)),
                  ],
                ),
              ],
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
              selected: engine.posture,
              onChanged: engine.setPosture,
              segments: [
                RamuriSegment(
                  value: RestingPosture.lying,
                  key: const Key('morning_posture_lying'),
                  label: l10n.measurePostureLying,
                ),
                RamuriSegment(
                  value: RestingPosture.sitting,
                  key: const Key('morning_posture_sitting'),
                  label: l10n.measurePostureSitting,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              lying ? l10n.morningPoseNoteLying : l10n.morningPoseNoteSitting,
              key: const Key('morning_pose_note'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
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
      ],
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.beltHint) ...[
            MorningBeltHint(text: l10n.morningBeltConnected),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 56,
            child: RamuriPrimaryButton(
              key: const Key('morning_start'),
              label: l10n.morningStart,
              onPressed: engine.startRest,
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
                  l10n.morningCameraNote,
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
