import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Ein Abschnitt des [ZoneBar]: Zone 1 bis 5 und ihr Anteil (Minuten oder
/// beliebige Gewichte; nur das Verhältnis zählt).
class ZoneBarSegment {
  const ZoneBarSegment({required this.zone, required this.weight});

  final int zone;
  final double weight;
}

/// Zonenbalken: ein Streifen, je Zone ein Stück, Breite nach Anteil. Abschnitte
/// ohne Anteil entfallen. [semanticLabel] beschreibt den Balken (etwa
/// „Zone 1: 8 Minuten, ...“), weil Farben allein nichts sagen.
class ZoneBar extends StatelessWidget {
  const ZoneBar({
    super.key,
    required this.segments,
    required this.semanticLabel,
    this.height = 14,
  });

  final List<ZoneBarSegment> segments;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final shown = [
      for (final s in segments)
        if (s.weight > 0) s,
    ];
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                flex: (shown[i].weight * 1000).round().clamp(1, 1 << 30),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.zone(shown[i].zone),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
