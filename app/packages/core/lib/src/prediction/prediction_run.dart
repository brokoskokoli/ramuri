/// Lauf als Eingabe der Prognose. Reine Werte, keine Speicherung.
class PredictionRun {
  const PredictionRun({
    required this.id,
    required this.date,
    required this.movingSeconds,
    this.distanceMeters,
    this.rpe,
    this.paceSamples,
  });

  final String id;

  /// Datum des Laufs (lokaler Kalendertag).
  final DateTime date;

  /// Bewegungszeit in Sekunden.
  final double movingSeconds;

  /// Gemessene Distanz; `null`, wenn nicht gemessen.
  final double? distanceMeters;

  /// Anstrengung 0 bis 10 (WP18); `null`, solange es sie nicht gibt.
  final int? rpe;

  /// 30-s-Tempowerte (m/s) für die Tempostabilität (PAR-022); `null` oder
  /// leer: nicht bestimmbar.
  final List<double>? paceSamples;
}
