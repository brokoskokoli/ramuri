import '../fitness/fitness_parameters.dart';
import '../fitness/variation_coefficient.dart';

/// Tempostabilität nach PAR-022 für freie Läufe: Variationskoeffizient der
/// 30-s-Werte und Unterschied der Hälften (Mittel der ersten gegen zweite
/// Hälfte der Werte) liegen innerhalb der Grenzen. `null`, wenn nicht
/// bestimmbar (weniger als 2 Werte, nicht endlich oder Mittel <= 0).
///
/// Die Grenzen sind die von [SectionSelectionParameters] (`paceMaxVariation`,
/// `paceMaxHalfDifference`), nicht dupliziert.
bool? isPaceStable(List<double>? samples, SectionSelectionParameters p) {
  if (samples == null || samples.length < 2) return null;
  if (samples.any((s) => !s.isFinite || s <= 0)) return null;
  double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
  final cv = variationCoefficient(samples);
  final half = samples.length ~/ 2;
  final first = mean(samples.sublist(0, half));
  final second = mean(samples.sublist(samples.length - half));
  final diff = (first - second).abs() / ((first + second) / 2);
  return cv <= p.paceMaxVariation && diff <= p.paceMaxHalfDifference;
}
