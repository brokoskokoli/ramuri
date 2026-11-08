/// Wortverbinder (U+2060): Eine Einheit wie `min/km` bricht nicht am „/“ um.
const String _joiner = '⁠';

/// Einheit so gesetzt, dass sie in einem Stück bleibt (Schriftfaktor 1,3,
/// schmales Display).
String unbreakableUnit(String unit) =>
    unit.replaceAll('/', '$_joiner/$_joiner');
