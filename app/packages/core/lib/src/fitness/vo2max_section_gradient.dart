import 'dart:math' as math;

import '../preprocessing/run_preprocessor.dart';
import '../recording/belt_track.dart';
import 'fitness_parameters.dart';
import 'vo2max_section_types.dart';

/// PAR-027: `G` nur einrechnen, wenn |G| ≥ 1 % und |Δh| ≥ 2 · Vertikal-
/// genauigkeit (größte gemeldete in `[from, to]`); sonst 0. Δh ist die
/// Differenz zwischen erstem und letztem 30-s-Höhenmedian (PAR-013).
/// Gemeinsam für die Abschnittsauswahl und den erwarteten Puls (PAR-247).
(double, GradientBasis) gradientOf(
  RunPreprocessing run,
  DateTime from,
  DateTime to,
  double? distance,
  SectionSelectionParameters p,
) {
  final heights = [
    for (final a in run.altitude.smoothed)
      if (!a.time.isBefore(from) && !a.time.isAfter(to)) a.meters,
  ];
  if (heights.length < 2 || distance == null || !(distance > 0)) {
    return (0, GradientBasis.noAltitude);
  }
  final accuracies = [
    for (final a in run.altitude.processed)
      if (a.accepted &&
          !a.input.time.isBefore(from) &&
          !a.input.time.isAfter(to) &&
          a.input.verticalAccuracyMeters != null)
        a.input.verticalAccuracyMeters!,
  ];
  if (accuracies.isEmpty) return (0, GradientBasis.noVerticalAccuracy);
  final rise = heights.last - heights.first;
  final g = rise / distance;
  final noise = accuracies.reduce(math.max) * p.gradientAltitudeFactor;
  if (g.abs() >= p.gradientUseFrom && rise.abs() >= noise) {
    return (g, GradientBasis.measured);
  }
  return (0, GradientBasis.belowThreshold);
}

/// Steigung des Bands: eingestellt in %, als Anteil (nicht gemessen).
/// Ohne Angabe 0 mit dem Hinweis „keine Höhendaten“ (nie 0 statt unbekannt).
(double, GradientBasis) beltGradientOf(BeltPiece? piece) {
  final g = piece?.inclinePercent;
  return g == null
      ? (0, GradientBasis.noAltitude)
      : (g / FitnessParameters.percent, GradientBasis.measured);
}
