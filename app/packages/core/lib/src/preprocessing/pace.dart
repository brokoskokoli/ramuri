import 'preprocessing_parameters.dart';

/// Einheit: Meter je Kilometer.
const double _metersPerKilometer = 1000;

/// Geschwindigkeit in m/s; `null` bei Δt <= 0 oder nicht endlichen Eingaben
/// (nie Division durch 0). FR-0050.
double? speedMetersPerSecond(double meters, double seconds) {
  if (!(seconds > 0) || !meters.isFinite || !seconds.isFinite) return null;
  return meters / seconds;
}

/// Pace in s/km; `null` bei Geschwindigkeit <= 0 (Stillstand) oder ohne Wert.
double? paceSecondsPerKm(double? metersPerSecond) {
  if (metersPerSecond == null || !(metersPerSecond > 0)) return null;
  return _metersPerKilometer / metersPerSecond;
}

/// Anzeigewert des Tempos. Kein String in core (die UI formatiert, OQ-0037).
sealed class PaceDisplay {
  const PaceDisplay();
}

/// Tempo in Sekunden je Kilometer.
class PaceValue extends PaceDisplay {
  const PaceValue(this.secondsPerKm);
  final double secondsPerKm;
}

/// Stillstand (unter PAR-014-Unterschwelle); die UI zeigt "–".
class PaceStandstill extends PaceDisplay {
  const PaceStandstill();
}

/// Noch zu wenig Daten (PAR-005) oder keine Daten.
class PaceNoData extends PaceDisplay {
  const PaceNoData();
}

/// Anzeigewert zu einer Geschwindigkeit; `null` ergibt [PaceNoData].
PaceDisplay paceDisplay(double? metersPerSecond, PreprocessingParameters p) {
  if (metersPerSecond == null) return const PaceNoData();
  if (metersPerSecond < p.standstillBelow) return const PaceStandstill();
  return PaceValue(paceSecondsPerKm(metersPerSecond)!);
}
