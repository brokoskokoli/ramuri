import 'package:flutter/material.dart';

/// Farben auf der Karte. Das Kartenmaterial ist hell, auch im dunklen Theme; die Karte nimmt deshalb feste Werte.
abstract final class RamuriMapColors {
  /// Grund der Quellenangabe auf der Karte (weiß, leicht durchscheinend).
  static const Color attributionScrim = Color(0xCCFFFFFF);

  /// Griff des Blatts unter der Live-Karte (hell; im Dunkeln die kräftige Linie des Themes, `LiveKarte.dc.html`).
  static const Color sheetHandleLight = Color(0xFF8DBDB4);

  /// Beschriftung der Werte im Blatt (hell; im Dunkeln die gedämpfte Textfarbe des Themes).
  static const Color sheetLabelLight = Color(0xFF3A4F4D);

  /// Schatten der schwebenden Knöpfe und Reiter auf der Karte (Tinte, 12 %).
  static const Color floatingShadow = Color(0x1F0E1A1A);
}
