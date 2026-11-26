import 'package:core/core.dart';

/// Eingaben und Schritte des Laufbands (FR-0196, K57, PAR-209, PAR-210).
/// Gespeichert wird die Geschwindigkeit in m/s; gerechnet und angezeigt wird in
/// km/h oder mph je nach Einheit der App, in Schritten von 0,1 der Anzeigeeinheit.
class TreadmillUnits {
  const TreadmillUnits._();

  /// PAR-209: 1 bis 25 km/h.
  static const double minMetersPerSecond = 1 / 3.6;
  static const double maxMetersPerSecond = 25 / 3.6;

  /// PAR-210: 0 bis 15 %, Schritte von 0,5 %.
  static const double maxIncline = 15;
  static const double inclineStep = 0.5;

  static const double _eps = 1e-9;

  static double displayFromMps(DistanceUnit unit, double mps) => switch (unit) {
    DistanceUnit.kilometers => mps * 3.6,
    DistanceUnit.miles => mps * 3600 / DistanceUnit.metersPerMile,
  };

  static double mpsFromDisplay(DistanceUnit unit, double value) =>
      switch (unit) {
        DistanceUnit.kilometers => value / 3.6,
        DistanceUnit.miles => value * DistanceUnit.metersPerMile / 3600,
      };

  /// Kleinster und größter zulässiger Wert in Zehnteln der Anzeigeeinheit.
  static int minTenths(DistanceUnit unit) =>
      (displayFromMps(unit, minMetersPerSecond) * 10 - _eps).ceil();
  static int maxTenths(DistanceUnit unit) =>
      (displayFromMps(unit, maxMetersPerSecond) * 10 + _eps).floor();

  static double _mps(DistanceUnit unit, int tenths) =>
      mpsFromDisplay(unit, tenths / 10);

  /// Geschwindigkeit der Eingabe in m/s, auf 0,1 der Anzeigeeinheit gerundet;
  /// `null`, wenn sie fehlt, keine Zahl ist oder außerhalb des Bereichs liegt.
  static double? parseSpeed(DistanceUnit unit, String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null || !v.isFinite) return null;
    final tenths = (v * 10).round();
    if (tenths < minTenths(unit) || tenths > maxTenths(unit)) return null;
    return _mps(unit, tenths);
  }

  /// Steigung der Eingabe: leer = `null` (gültig, unbekannt); sonst muss sie
  /// ein Vielfaches von 0,5 im Bereich sein. [valid] sagt, ob die Eingabe gilt.
  static (bool valid, double? value) parseIncline(String text) {
    final t = text.trim().replaceAll(',', '.');
    if (t.isEmpty) return (true, null);
    final v = double.tryParse(t);
    if (v == null || !v.isFinite || v < 0 || v > maxIncline) {
      return (false, null);
    }
    if (((v / inclineStep) - (v / inclineStep).round()).abs() > 1e-6) {
      return (false, null);
    }
    return (true, v);
  }

  /// Ein Schritt der Geschwindigkeit: aus 0 (Stillstand) auf das Minimum, unter
  /// das Minimum auf 0, sonst 0,1 der Anzeigeeinheit, begrenzt auf das Maximum.
  static double stepSpeed(DistanceUnit unit, double? mps, int direction) {
    final k = mps == null ? 0 : (displayFromMps(unit, mps) * 10).round();
    final lo = minTenths(unit);
    final hi = maxTenths(unit);
    final next = direction > 0
        ? (k < lo ? lo : (k + 1 > hi ? hi : k + 1))
        : (k <= lo ? 0 : k - 1);
    return next == 0 ? 0 : _mps(unit, next);
  }

  /// Ein Schritt der Steigung; aus „unbekannt“ geht es mit + auf 0 und mit −
  /// bleibt sie unbekannt.
  static double? stepIncline(double? percent, int direction) {
    if (percent == null) return direction > 0 ? 0 : null;
    final next = percent + direction * inclineStep;
    return next.clamp(0, maxIncline).toDouble();
  }

  /// Zahl für die Anzeige, eine Nachkommastelle.
  static String speedText(DistanceUnit unit, double mps, String languageCode) {
    final t = displayFromMps(unit, mps).toStringAsFixed(1);
    return languageCode == 'de' ? t.replaceAll('.', ',') : t;
  }

  static String inclineText(double percent, String languageCode) {
    final t = percent.toStringAsFixed(1);
    return languageCode == 'de' ? t.replaceAll('.', ',') : t;
  }

  /// Aktuelle Pace aus der Bandgeschwindigkeit in s/km; `null` bei Stillstand.
  static double? paceSecondsPerKm(double? mps) =>
      mps == null || mps <= 0 ? null : 1000 / mps;
}
