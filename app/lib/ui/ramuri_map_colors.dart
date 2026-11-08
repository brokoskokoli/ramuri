import 'package:flutter/painting.dart';

/// Farben auf der Karte. Das Kartenmaterial ist hell, auch im dunklen Theme; die Karte nimmt deshalb feste Werte.
abstract final class RamuriMapColors {
  /// Grund der Quellenangabe auf der Karte (weiß, leicht durchscheinend).
  static const Color attributionScrim = Color(0xCCFFFFFF);
}
