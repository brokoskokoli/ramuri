import 'dart:math' as math;

/// Variationskoeffizient: Standardabweichung der Grundgesamtheit durch Mittel.
/// Bei Mittel <= 0 unendlich (nicht bestimmbar, nie "stabil"). [xs] darf nicht
/// leer sein. Gemeinsame Funktion von Abschnittsauswahl (PAR-022) und
/// Tempostabilität der Prognose.
double variationCoefficient(List<double> xs) {
  final m = xs.reduce((a, b) => a + b) / xs.length;
  if (!(m > 0)) return double.infinity;
  final v = xs.fold<double>(0, (a, x) => a + (x - m) * (x - m)) / xs.length;
  return math.sqrt(v) / m;
}
