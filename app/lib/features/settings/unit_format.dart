import 'package:core/core.dart';
import 'package:intl/intl.dart';

/// Tag der „Stand“-Angabe, immer mit Jahr (FR-0059): ein alter Wert darf nicht
/// frisch wirken. [day] ist ein Kalendertag (`yyyy-MM-dd`) oder ein Zeitpunkt.
String asOfDateText(String languageCode, DateTime day) =>
    DateFormat.yMMMEd(languageCode).format(day);

/// Der eine Formatierer für Strecke und Pace (NFR-0006). Eingaben sind immer
/// Meter beziehungsweise Sekunden je Kilometer; umgerechnet wird nur für die
/// Anzeige.
class UnitFormatter {
  const UnitFormatter({
    required this.unit,
    required this.languageCode,
    required this.distanceLabel,
    required this.paceLabel,
    required this.elevationLabel,
  });

  final DistanceUnit unit;

  /// Nur für das Dezimaltrennzeichen: Deutsch Komma, sonst Punkt.
  final String languageCode;

  static const String noValue = '–';

  String get _decimalSeparator => languageCode == 'de' ? ',' : '.';

  /// Kürzel der Streckeneinheit (aus der Übersetzung), etwa `km`.
  final String distanceLabel;

  /// Kürzel der Paceeinheit (aus der Übersetzung), etwa `min/km`.
  final String paceLabel;

  /// Kürzel der Höheneinheit (aus der Übersetzung): `m` bei Kilometern, `ft`
  /// bei Meilen.
  final String elevationLabel;

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

  /// Höhe aus Metern, ganze Zahl, etwa `120 m` beziehungsweise `394 ft`. Die
  /// gespeicherten Werte bleiben Meter.
  String elevation(double? meters) {
    if (meters == null || !meters.isFinite) return noValue;
    return '${unit.elevationFromMeters(meters).round()} $elevationLabel';
  }
}

/// Höhenwert mit Vorzeichen für Anstieg („+“) oder Gefälle („−“); null hat
/// keines („0 m“, nicht „+0 m“).
String signedElevation(String sign, String formatted) =>
    formatted.contains('0') && !RegExp(r'[1-9]').hasMatch(formatted)
    ? formatted
    : '$sign$formatted';
