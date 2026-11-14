import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'resting_measure_controller.dart';
import 'resting_widgets.dart';

/// Sekunden, nach denen der nächste beruhigende Satz erscheint.
const int restingLineSeconds = 25;

/// Ruhephase (Design `Ruhephase`): Restzeit im Ring, kurze beruhigende Sätze
/// (ohne Atemtempo), Abbrechen, Ton an/aus, sofort messen.
class RestingRestView extends StatelessWidget {
  const RestingRestView({
    super.key,
    required this.controller,
    required this.soundOn,
    this.allowSkip = true,
  });

  /// „Ich bin schon entspannt“ anbieten; die Morgenmessung hat eine feste
  /// Ruhephase (FR-0215) und lässt sie weg.
  final bool allowSkip;

  final RestingMeasureController controller;

  /// Ton oder Vibration am Ende der Ruhephase; die Oberfläche liest den Wert
  /// auch im [RestingMeasureSignal].
  final ValueNotifier<bool> soundOn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = RamuriColors.of(context);
    final total = Duration(minutes: controller.restMinutes);
    final left = controller.restRemaining;
    final passed = (total - left).inSeconds.clamp(0, total.inSeconds);
    final line = (passed ~/ restingLineSeconds) % 6;
    final (title, body) = _line(l10n, line);
    final posture = restingPostureLabel(l10n, controller.posture);
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l10n.measureRestHeader(posture),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: soundOn,
            builder: (context, on, _) => RestingRoundButton(
              key: const Key('measure_sound'),
              icon: on ? Icons.volume_up_outlined : Icons.volume_off_outlined,
              label: on ? l10n.measureSoundOnLabel : l10n.measureSoundOffLabel,
              toggled: on,
              onPressed: () => soundOn.value = !on,
            ),
          ),
        ],
      ),
      sections: [
        const SizedBox(height: 8),
        Center(
          child: Semantics(
            label: l10n.measureRestRingLabel(restingClock(left)),
            child: ExcludeSemantics(
              child: RestRing(
                fraction: total.inSeconds == 0
                    ? 0
                    : left.inSeconds / total.inSeconds,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        restingClock(left),
                        key: const Key('measure_rest_clock'),
                        style: theme.textTheme.displayMedium!.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.measureRestOf(restingClock(total)),
                      style: theme.textTheme.labelMedium!.copyWith(
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Text(
                  title,
                  key: const Key('measure_rest_line'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge!.copyWith(
                    color: c.textMuted,
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
          RestingCard(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: ValueListenableBuilder<bool>(
              valueListenable: soundOn,
              builder: (context, on, _) {
                final seconds = restingWindowSeconds();
                return Row(
                  children: [
                    Icon(Icons.schedule, size: 22, color: c.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        controller.waitingForForeground
                            ? l10n.measureRestWaitForeground
                            : on
                            ? l10n.measureRestNextSound(seconds)
                            : l10n.measureRestNextVibrate(seconds),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (allowSkip)
            RestingTextLink(
              key: const Key('measure_skip_rest'),
              label: l10n.measureRestSkip,
              onPressed: () => controller.skipRest(),
            ),
        ],
      ),
    );
  }

  static (String, String) _line(AppLocalizations l, int i) => switch (i) {
    0 => (l.measureRestLine1Title, l.measureRestLine1Body),
    1 => (l.measureRestLine2Title, l.measureRestLine2Body),
    2 => (l.measureRestLine3Title, l.measureRestLine3Body),
    3 => (l.measureRestLine4Title, l.measureRestLine4Body),
    4 => (l.measureRestLine5Title, l.measureRestLine5Body),
    _ => (l.measureRestLine6Title, l.measureRestLine6Body),
  };
}
