import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../ui/ui.dart';
import 'readiness_detail_screen.dart';
import 'readiness_service.dart';
import 'readiness_texts.dart';

/// Karte „Erholung“ auf „Heute“, erweiterte Stufe (WP34 Teil D1, Design
/// `design/screens/readiness/Heute.dc.html`): Zahl mit Ring, Zustand, Stufe und
/// bis zu zwei Ursachen; eingeschränkt und unzureichend ohne Zahl. Die Stufe
/// steht immer in der Überschrift (FR-0105). Der Entwicklermodus kennzeichnet
/// nichts (K62 Punkt 6); den unauffälligen Hinweis „Entwicklermodus aktiv“
/// zeigt auf „Heute“ wie in WP33 nur die Morgenmessungs-Karte, damit er nicht
/// doppelt steht.
class ReadinessCard extends StatelessWidget {
  const ReadinessCard({super.key, required this.snapshot, this.onWhereFrom});

  final ReadinessSnapshot snapshot;

  /// Öffnet die Detailseite; Voreinstellung: Route aus Teil D1.
  final VoidCallback? onWhereFrom;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = Theme.of(context).textTheme;
    final c = RamuriColors.of(context);
    final r = snapshot.result;
    final number = r.state == ReadinessState.number && r.value != null;
    final title = switch (r.state) {
      ReadinessState.number =>
        r.band == null ? '' : readinessBandName(l, r.band!),
      ReadinessState.limited => l.readinessLimitedTitle,
      ReadinessState.insufficient => l.readinessInsufficientTitle,
    };
    return RamuriCard(
      key: const Key('readiness_card'),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Semantics(
                label: number
                    ? l.readinessRingValue(r.value!)
                    : l.readinessRingNone,
                excludeSemantics: true,
                child: _Ring(value: number ? r.value : null),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        '${l.recoveryTitle} · ${l.readinessStageExtended}'
                            .toUpperCase(),
                        key: const Key('readiness_stage'),
                        style: t.labelMedium?.copyWith(
                          color: c.textLabel,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      key: const Key('readiness_title'),
                      style: t.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (number) ...[
                      const SizedBox(height: 4),
                      const EstimatedMark(),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      readinessCardText(l, r),
                      key: const Key('readiness_text'),
                      style: t.bodySmall?.copyWith(color: c.textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          TextButton(
            key: const Key('readiness_where_from'),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, RamuriTheme.minTarget),
            ),
            onPressed:
                onWhereFrom ??
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReadinessDetailScreen(snapshot: snapshot),
                  ),
                ),
            child: Text(l.readinessWhereFrom),
          ),
        ],
      ),
    );
  }
}

/// Ring mit Zahl; ohne Zahl ein gestrichelter Kreis (keine Zahl, kein Zustand).
class _Ring extends StatelessWidget {
  const _Ring({required this.value});

  final int? value;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 84,
      height: 84,
      child: CustomPaint(
        painter: _RingPainter(
          value: value,
          track: c.track,
          arc: c.accent,
          dashes: c.textMuted,
        ),
        child: value == null
            ? null
            : Center(
                child: Text(
                  '$value',
                  key: const Key('readiness_value'),
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.track,
    required this.arc,
    required this.dashes,
  });

  final int? value;
  final Color track;
  final Color arc;
  final Color dashes;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    const radius = 34.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final v = value;
    if (v == null) {
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = dashes;
      const n = 21;
      for (var i = 0; i < n; i++) {
        final a = 2 * math.pi * i / n;
        canvas.drawArc(rect, a, 2 * math.pi * 0.3 / n, false, p);
      }
      return;
    }
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = track;
    canvas.drawCircle(center, radius, p);
    p
      ..strokeCap = StrokeCap.round
      ..color = arc;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * v / 100, false, p);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.track != track || old.arc != arc;
}
