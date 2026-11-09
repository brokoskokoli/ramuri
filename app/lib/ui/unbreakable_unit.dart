import 'package:flutter/painting.dart' show TextSpan;

/// Wortverbinder (U+2060): Eine Einheit wie `min/km` bricht nicht am „/“ um.
const String _joiner = '\u2060';

/// Einheit so gesetzt, dass sie in einem Stück bleibt (Schriftfaktor 1,3,
/// schmales Display).
String unbreakableUnit(String unit) =>
    unit.replaceAll('/', '$_joiner/$_joiner');

/// Leerraum zwischen Zahl und Einheit, der nicht umbricht („150 bpm“ nie
/// „150“ / „bpm“): ein geschütztes Leerzeichen (U+00A0). Der Wortverbinder um
/// ein normales Leerzeichen sperrt den Umbruch nach dem Leerzeichen nicht
/// (gemessen in `unit_stays_test.dart`). Nur für Sätze und breite Behälter:
/// In einer Spalte, die Zahl und Einheit nicht fasst, bräche die Zeile sonst
/// mitten im Wort statt vor der Einheit.
const String unitSeparator = '\u00A0';

/// Dieselbe Einheit ohne Wortverbinder und mit gewöhnlichen Leerzeichen, für
/// die Sprachausgabe.
String spokenUnit(String unit) =>
    unit.replaceAll(_joiner, '').replaceAll(unitSeparator, ' ');

/// Ein fertig formatierter Wert („5:40 min/km“, „1,12 km“) mit der [unit] als
/// Endung, gesetzt ohne Umbruch zwischen Zahl und Einheit und in der Einheit.
/// Ohne diese Endung (etwa „–“) bleibt der Text, wie er ist. Für die
/// Sprachausgabe gilt [spokenUnit] auf dem Ergebnis.
String unitTogether(String formatted, String unit) {
  final suffix = ' $unit';
  if (formatted.length <= suffix.length || !formatted.endsWith(suffix)) {
    return formatted;
  }
  return '${formatted.substring(0, formatted.length - suffix.length)}'
      '$unitSeparator${unbreakableUnit(unit)}';
}

/// Beschriftung einer Kachel; mit [unit] steht die Einheit hinter dem Namen
/// („Ø Pace min/km“), die Zahl darunter bleibt groß und ohne Einheit. Die
/// Einheit bricht nicht in sich um, die Sprachausgabe nennt sie genau einmal.
TextSpan labelWithUnit(String label, String? unit) => TextSpan(
  text: label,
  children: [
    if (unit != null)
      TextSpan(
        text: ' ${unbreakableUnit(unit)}',
        semanticsLabel: ' ${spokenUnit(unit)}',
      ),
  ],
);
