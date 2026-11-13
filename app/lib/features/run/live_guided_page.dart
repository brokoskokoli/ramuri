import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import '../plan/plan_texts.dart' show planKindName;
import '../settings/unit_format.dart';
import 'live_run_values.dart' show splitUnit;
import 'live_run_view.dart' show formatClock, livePaceText;
import 'run_controller.dart';
import 'treadmill_units.dart';

/// Live-Seite der geführten Einheit (FR-0027, FR-0146, FR-0205; Design
/// `Intervall.dc.html`). Bleibt in beiden Modi dunkel, die Farben kommen aus
/// dem dunklen Theme. Restzeit des Abschnitts nur in Zeit (WP24 Festlegung 1).
/// Die Pflichtanzeigen (FR-0026) bleiben auf der Werte-Seite daneben.
class LiveGuidedPage extends StatelessWidget {
  const LiveGuidedPage({
    super.key,
    required this.controller,
    required this.formatter,
    required this.segments,
    required this.controls,
  });

  final RunController controller;
  final UnitFormatter formatter;
  final List<PlanSegment> segments;

  /// Pause, Weiter, Runde, Beenden wie auf der Werte-Seite, im dunklen Theme
  /// gebaut.
  final WidgetBuilder controls;

  @override
  Widget build(BuildContext context) {
    return RamuriDarkScope(
      child: Builder(
        builder: (context) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) => _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final s = controller.snapshot;
    final moving = s.movingTime ?? Duration.zero;
    final pos = guidedPosition(segments, moving);
    final paused =
        s.phase == RecordingPhase.paused ||
        s.phase == RecordingPhase.autoPaused;
    final kind = controller.guidedUnitKind;
    final timed = [
      for (final g in segments)
        if (g.durationSeconds > 0) g,
    ];
    final before = segments
        .take(pos.index)
        .where((g) => g.durationSeconds > 0)
        .length;
    final number = pos.finished ? timed.length : before + 1;
    return Column(
      children: [
        Expanded(
          child: ListView(
            // Oben Platz für die Reiter, die über der Seite schweben.
            padding: const EdgeInsets.fromLTRB(20, 72, 20, 16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      (kind == null
                              ? l10n.guidedLiveTitle
                              : planKindName(l10n, kind))
                          .toUpperCase(),
                      key: const Key('guided_title'),
                      style: text.labelLarge?.copyWith(color: c.accent),
                    ),
                  ),
                  Text(
                    formatClock(s.totalTime),
                    key: const Key('guided_total'),
                    style: text.titleMedium?.copyWith(color: c.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _progress(c, l10n, timed, pos, number),
              const SizedBox(height: 28),
              if (pos.finished)
                Text(
                  l10n.guidedLiveDone,
                  key: const Key('guided_done'),
                  textAlign: TextAlign.center,
                  style: text.titleLarge?.copyWith(color: c.text),
                )
              else ...[
                Text(
                  l10n.guidedLiveSection(
                    number,
                    timed.length,
                    _kind(l10n, pos.segment!.kind),
                  ),
                  key: const Key('guided_section'),
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: c.accent),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatClock(pos.remaining),
                    key: const Key('guided_remaining'),
                    style: text.displayLarge?.copyWith(
                      color: c.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  l10n.guidedLiveRemaining,
                  textAlign: TextAlign.center,
                  style: text.titleMedium?.copyWith(color: c.textMuted),
                ),
                if (paused) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.guidedLivePaused,
                    key: const Key('guided_paused'),
                    textAlign: TextAlign.center,
                    style: text.titleSmall?.copyWith(color: c.ember),
                  ),
                ],
                const SizedBox(height: 20),
                _targetIs(context, l10n, pos),
                _hint(context, l10n),
                if (pos.next != null) ...[
                  const SizedBox(height: 12),
                  _next(c, l10n, text, pos.next!),
                ],
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: controls(context),
        ),
      ],
    );
  }

  /// Balken über alle Abschnitte, Breite nach Dauer (wie im Design).
  Widget _progress(
    RamuriColors c,
    AppLocalizations l10n,
    List<PlanSegment> timed,
    GuidedPosition pos,
    int number,
  ) {
    final done = pos.finished ? timed.length : number - 1;
    return Semantics(
      label: l10n.guidedLiveProgress(number, timed.length),
      excludeSemantics: true,
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            for (var i = 0; i < timed.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: timed[i].durationSeconds,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(color: c.track),
                      if (i < done)
                        ColoredBox(color: c.accent)
                      else if (i == done && !pos.finished)
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor:
                              (pos.elapsedInSegment.inSeconds /
                                      timed[i].durationSeconds)
                                  .clamp(0.0, 1.0),
                          child: ColoredBox(color: c.accent),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Soll (Pace, RPE, Puls; FR-0146) und Ist (Pace bzw. Bandgeschwindigkeit).
  Widget _targetIs(
    BuildContext context,
    AppLocalizations l10n,
    GuidedPosition pos,
  ) {
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    final t = pos.target;
    final lines = [if (t != null) ..._targetLines(l10n, t)];
    final belt = controller.runMode == RunMode.treadmill;
    final String now;
    if (belt) {
      final mps = controller.snapshot.beltSpeedMetersPerSecond;
      final unit = formatter.unit == DistanceUnit.miles
          ? l10n.treadmillUnitMph
          : l10n.treadmillUnitKmh;
      now = mps == null
          ? UnitFormatter.noValue
          : '${TreadmillUnits.speedText(formatter.unit, mps, formatter.languageCode)} $unit';
    } else {
      now = livePaceText(controller, formatter, l10n);
    }
    final bpm = controller.snapshot.heartRateBpm;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.guidedLiveTarget,
              style: text.labelMedium?.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: 4),
            if (lines.isEmpty)
              Text(
                l10n.guidedLiveNoTarget,
                key: const Key('guided_no_target'),
                style: text.bodyLarge?.copyWith(color: c.text),
              )
            else
              for (var i = 0; i < lines.length; i++)
                Text(
                  lines[i],
                  key: Key('guided_target_$i'),
                  style: text.titleMedium?.copyWith(color: c.text),
                ),
            const SizedBox(height: 12),
            Text(
              belt ? l10n.guidedLiveBeltSpeed : l10n.guidedLiveNow,
              style: text.labelMedium?.copyWith(color: c.textMuted),
            ),
            Text(
              now,
              key: const Key('guided_now'),
              style: text.headlineMedium?.copyWith(color: c.text),
            ),
            if (bpm != null)
              Text(
                '$bpm ${l10n.liveUnitBpm}',
                key: const Key('guided_now_hr'),
                style: text.titleMedium?.copyWith(color: c.textMuted),
              ),
          ],
        ),
      ),
    );
  }

  List<String> _targetLines(AppLocalizations l10n, PlanTargetIntensity t) {
    String p(double s) => splitUnit(formatter.pace(s), formatter.paceLabel).$1;
    final fast = t.paceFastSecondsPerKm;
    final slow = t.paceSlowSecondsPerKm;
    final lo = t.rpeMin;
    final hi = t.rpeMax;
    return [
      if (fast != null && slow != null && !t.paceIsLimit)
        l10n.guidedLivePace(p(fast), p(slow), formatter.paceLabel)
      else if (slow != null || fast != null)
        l10n.guidedLivePaceLimit(formatter.pace((slow ?? fast)!)),
      if (lo != null || hi != null)
        if (lo != null && hi != null && lo != hi)
          l10n.guidedLiveRpe('$lo', '$hi')
        else
          l10n.guidedLiveRpeSingle('${lo ?? hi}'),
      if (t.hrMinBpm != null && t.hrMaxBpm != null)
        l10n.guidedLiveHeartRate('${t.hrMinBpm}', '${t.hrMaxBpm}'),
    ];
  }

  /// Pulshinweis nur nach den Regeln der Ansage (PAR-107), die der Controller
  /// aus dem Ereignisgeber liefert (`guidedPulseHintDue`): Abschnitt ab 4 min,
  /// nach 3 min darin, 30 s über der oberen Grenze, im Lauf, keine
  /// Gehpausen-Umstellung. Die Seite rechnet nicht selbst.
  Widget _hint(BuildContext context, AppLocalizations l10n) {
    final bpm = controller.snapshot.heartRateBpm;
    if (bpm == null || !controller.guidedPulseHintDue) {
      return const SizedBox.shrink();
    }
    final c = RamuriColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.ember,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.favorite_rounded, color: c.onEmber),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.guidedLiveHeartHint('$bpm'),
                    key: const Key('guided_hr_hint'),
                    style: text.titleSmall?.copyWith(color: c.onEmber),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _next(
    RamuriColors c,
    AppLocalizations l10n,
    TextTheme text,
    PlanSegment next,
  ) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.guidedLiveNext,
              style: text.titleSmall?.copyWith(color: c.textMuted),
            ),
            Flexible(
              child: Text(
                '${formatClock(Duration(seconds: next.durationSeconds))} '
                '${_kind(l10n, next.kind)}',
                key: const Key('guided_next'),
                textAlign: TextAlign.end,
                style: text.titleSmall?.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _kind(AppLocalizations l, PlanSegmentKind k) => switch (k) {
    PlanSegmentKind.warmUp => l.voiceSegmentWarmUp,
    PlanSegmentKind.easy => l.voiceSegmentEasy,
    PlanSegmentKind.interval => l.voiceSegmentInterval,
    PlanSegmentKind.tempo => l.voiceSegmentTempo,
    PlanSegmentKind.recovery => l.voiceSegmentRecovery,
    PlanSegmentKind.endBlock => l.voiceSegmentEndBlock,
    PlanSegmentKind.coolDown => l.voiceSegmentCoolDown,
    PlanSegmentKind.run => l.voiceSegmentRun,
    PlanSegmentKind.walk => l.voiceSegmentWalk,
  };
}
