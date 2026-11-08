import 'package:flutter/material.dart';

import 'ramuri_colors.dart';

/// Mindesthöhe eines Balkens in dp: Eine Woche mit 0 km bleibt als flacher
/// Strich sichtbar, ein kleiner Wert ist nie unsichtbar.
const double ramuriWeekBarMinHeight = 3;

/// Wochenbalken (Design „Fortschritt“, Kilometer pro Woche): ein Balken je
/// Woche, ältester zuerst. Der letzte Wert ist die laufende Woche, der davor
/// die letzte volle Woche, alle früheren sind ältere Wochen, jeweils in eigenem
/// Ton ([RamuriColors.weekBarOlder], `weekBarLast`, `weekBarCurrent`).
///
/// Die Höhe ist relativ zum größten Wert; sind alle 0, hat kein Balken mehr als
/// die Mindesthöhe (keine Division durch 0). Eine Nulllinie über die ganze Breite
/// bleibt immer sichtbar. Ein Wert `null` (Woche mit Läufen ohne lesbare Strecke,
/// FR-0057) steht als Strich in neutralem Ton, nicht als 0-Balken in Balkenfarbe.
///
/// Es gibt keine gestrichelte Hülle: Sie zeigt das Wochenziel aus Phase 2.
/// Einheiten und Beschriftungen liefert der Aufrufer fertig formatiert; der
/// Baustein hat nur einen [semanticLabel] für das Ganze.
class RamuriWeekBars extends StatelessWidget {
  const RamuriWeekBars({
    super.key,
    required this.values,
    required this.semanticLabel,
    this.height = 130,
  });

  /// Wert je Woche, ≥ 0, ältester zuerst; `null` = nicht verfügbar.
  final List<double?> values;

  /// Beschreibung für die Bedienungshilfe, mit Einheiten (vom Aufrufer).
  final String semanticLabel;

  /// Höhe des Balkenbereichs in dp (Design: 130).
  final double height;

  /// Höhe des Balkens zu [value] bei Höchstwert [maxValue] in dp.
  @visibleForTesting
  static double barHeight(double? value, double maxValue, double height) {
    if (value == null || !(maxValue > 0) || !(value > 0)) {
      return ramuriWeekBarMinHeight;
    }
    final h = value / maxValue * height;
    return h < ramuriWeekBarMinHeight ? ramuriWeekBarMinHeight : h;
  }

  @override
  Widget build(BuildContext context) {
    final c = RamuriColors.of(context);
    var maxValue = 0.0;
    for (final v in values) {
      if (v != null && v > maxValue) maxValue = v;
    }
    final last = values.length - 1;
    Color colorOf(int i) {
      if (i == last) return c.weekBarCurrent;
      if (i == last - 1) return c.weekBarLast;
      return c.weekBarOlder;
    }

    return Semantics(
      container: true,
      image: true,
      excludeSemantics: true,
      label: semanticLabel,
      child: SizedBox(
        height: height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                key: const Key('week_bars_baseline'),
                height: 2,
                color: c.outlineStrong,
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      key: Key('week_bar_$i'),
                      height: barHeight(values[i], maxValue, height),
                      decoration: BoxDecoration(
                        color: values[i] == null ? c.outlineStrong : colorOf(i),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
