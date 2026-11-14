import '../health/health_processing.dart';
import 'readiness_parameters.dart';

/// PAR-163: Teilskala HRV und Ruhepuls aus `z` (günstig positiv).
/// Unter 0: `60 + 25·z`, mindestens 0; ab 0: `60 + 20·z`, höchstens 90.
double readinessScaleZ(double z) {
  if (z < 0) {
    final s = readinessZBase + readinessZSlopeBelow * z;
    return s < 0 ? 0 : s;
  }
  final s = readinessZBase + readinessZSlopeAbove * z;
  return s > readinessZMax ? readinessZMax : s;
}

/// PAR-165: Teilskala Schlafdauer in Stunden. Keine Abwertung über 9 h.
double readinessScaleSleepDuration(double hours) {
  if (hours < readinessSleepAnchorHours) {
    final s =
        readinessSleepAnchorScore -
        readinessSleepSlopeBelow * (readinessSleepAnchorHours - hours);
    return s < 0 ? 0 : s;
  }
  if (hours < readinessSleepCapHours) {
    return readinessSleepAnchorScore +
        readinessSleepSlopeAbove * (hours - readinessSleepAnchorHours);
  }
  return readinessSleepCapScore;
}

/// PAR-167: Teilskala Schlaf; ohne Effizienz nur die Dauer (Schlaf gilt dann
/// weiter als vorhanden). Die Effizienz-Teilskala (PAR-166) kommt aus
/// [HealthProcessing.efficiencyScore].
double readinessScaleSleep({
  required double hours,
  required double? efficiencyPercent,
  HealthProcessing processing = const HealthProcessing(),
}) {
  final d = readinessScaleSleepDuration(hours);
  if (efficiencyPercent == null) return d;
  return readinessSleepDurationShare * d +
      readinessSleepEfficiencyShare *
          processing.efficiencyScore(efficiencyPercent);
}

/// PAR-168: Teilskala Trainingsbelastung aus TSB% (Mittel PAR-073). Bis TSB%
/// −10 gleich 60, darunter fallend bis 0: nur Bremse.
double readinessScaleLoad(double tsbPercent) {
  final s =
      readinessLoadMaxScore +
      readinessLoadSlope * (tsbPercent - readinessLoadNeutralTsbPercent);
  if (s > readinessLoadMaxScore) return readinessLoadMaxScore;
  return s < 0 ? 0 : s;
}

/// PAR-169: Teilskala Befinden, Stufe 1 bis 5.
double readinessScaleWellbeing(int level) {
  if (level < 1 || level > readinessWellbeingScores.length) {
    throw RangeError.range(level, 1, readinessWellbeingScores.length);
  }
  return readinessWellbeingScores[level - 1];
}
