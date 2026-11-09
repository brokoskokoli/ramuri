import 'dart:math' as math;

import 'prediction_parameters.dart';

/// FR-0130: `T2 = T1 · (D2 / D1)^1,06`. Zeit in Sekunden, Distanz in Metern.
/// [ArgumentError] bei Werten <= 0 oder nicht endlich.
double riegelSeconds({
  required double referenceSeconds,
  required double referenceMeters,
  required double targetMeters,
  double exponent = 1.06,
}) {
  for (final v in [referenceSeconds, referenceMeters, targetMeters]) {
    if (!(v > 0) || !v.isFinite) {
      throw ArgumentError.value(v, 'value', 'muss positiv und endlich sein');
    }
  }
  return referenceSeconds * math.pow(targetMeters / referenceMeters, exponent);
}

/// Riegel mit den Parametern der Prognose.
double riegelWithParameters(
  PredictionParameters p, {
  required double referenceSeconds,
  required double referenceMeters,
  required double targetMeters,
}) => riegelSeconds(
  referenceSeconds: referenceSeconds,
  referenceMeters: referenceMeters,
  targetMeters: targetMeters,
  exponent: p.riegelExponent,
);

/// Verhältnis zweier Distanzen, immer >= 1 (symmetrisch, PAR-144).
double distanceRatio(double a, double b) => math.max(a / b, b / a);
