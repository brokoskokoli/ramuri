import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Live-Zonenanzeige (Design „Live“): fünf gleich breite Stücke. Die aktuelle
/// Zone ist gefüllt und trägt einen Ring, die Stücke darunter sind hell, die
/// darüber grau. Ohne [zone] (kein Puls, keine Zonenbasis) sind alle grau.
/// [semanticLabel] sagt die Zone in Worten, weil Farben allein nichts sagen.
class ZoneMeter extends StatelessWidget {
  const ZoneMeter({
    super.key,
    required this.zone,
    required this.semanticLabel,
    this.height = 10,
  });

  /// 1 bis 5 oder `null`.
  final int? zone;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    final current = zone;
    assert(current == null || (current >= 1 && current <= 5));
    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Padding(
        // Platz für den Ring (3 dp), damit er nicht abgeschnitten wird.
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 1; i <= 5; i++) ...[
                if (i > 1) const SizedBox(width: 4),
                Expanded(
                  child: DecoratedBox(
                    key: Key('zone_meter_$i'),
                    decoration: BoxDecoration(
                      color: current == null || i > current
                          ? c.segmentTrack
                          : i == current
                          ? c.accent
                          : c.zoneDone,
                      borderRadius: BorderRadius.circular(height / 2),
                      boxShadow: i == current
                          ? [BoxShadow(color: c.actionSoft, spreadRadius: 3)]
                          : null,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
