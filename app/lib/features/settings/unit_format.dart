import 'package:core/core.dart';

/// Der eine Formatierer für Strecke und Pace (NFR-0006). Eingaben sind immer
/// Meter beziehungsweise Sekunden je Kilometer; umgerechnet wird nur für die
/// Anzeige.
class UnitFormatter {
  const UnitFormatter({required this.unit, required this.languageCode});

  final DistanceUnit unit;

  /// Nur für das Dezimaltrennzeichen: Deutsch Komma, sonst Punkt.
  final String languageCode;

  static const String noValue = '–';

  String get _decimalSeparator => languageCode == 'de' ? ',' : '.';

  String get distanceLabel => unit == DistanceUnit.miles ? 'mi' : 'km';

  String get paceLabel => unit == DistanceUnit.miles ? 'min/mi' : 'min/km';

  /// Strecke aus Metern, zwei Nachkommastellen, etwa `5,23 km`.
  String distance(double? meters) {
    if (meters == null || !meters.isFinite || meters < 0) return noValue;
    final value = unit.distanceFromMeters(meters).toStringAsFixed(2);
    return '${value.replaceAll('.', _decimalSeparator)} $distanceLabel';
  }

  /// Pace aus Sekunden je Kilometer als `m:ss min/km` beziehungsweise
  /// `min/mi`, auf ganze Sekunden gerundet.
  String pace(double? secondsPerKm) {
    if (secondsPerKm == null || !secondsPerKm.isFinite || secondsPerKm <= 0) {
      return noValue;
    }
    final total = unit.paceFromSecondsPerKm(secondsPerKm).round();
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '${total ~/ 60}:$seconds $paceLabel';
  }
}
