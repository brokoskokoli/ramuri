/// Wortverbinder (U+2060): Eine Einheit wie `min/km` bricht nicht am „/“ um.
const String _joiner = '\u2060';

/// Einheit so gesetzt, dass sie in einem Stück bleibt (Schriftfaktor 1,3,
/// schmales Display).
String unbreakableUnit(String unit) =>
    unit.replaceAll('/', '$_joiner/$_joiner');

/// Dieselbe Einheit ohne Wortverbinder, für die Sprachausgabe.
String spokenUnit(String unit) => unit.replaceAll(_joiner, '');

/// Leerraum zwischen Zahl und Einheit, der nicht umbricht: Die Einheit bleibt
/// bei der Zahl („+1200 m“ nie „+1200“ / „m“). Wortverbinder um das Leerzeichen
/// sperren den Umbruch davor und danach; in der Sprachausgabe fällt er weg.
const String unitSeparator = '$_joiner $_joiner';
