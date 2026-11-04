/// Ein roher Standortpunkt (ADR-0005 Punkt 4: Filterung macht die Fachlogik).
class LocationSample {
  const LocationSample({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.altitudeMeters,
    this.speedMetersPerSecond,
  });

  final DateTime time;
  final double latitude;
  final double longitude;

  /// Fehlende Angaben bleiben `null` und werden nicht mit 0 aufgefüllt.
  final double? accuracyMeters;
  final double? altitudeMeters;
  final double? speedMetersPerSecond;
}

/// Port: Standort. Die Quelle liefert Punkte, solange jemand zuhört.
abstract interface class LocationSource {
  /// Rohe Standortpunkte. Ein Fehler im Strom bedeutet Ausfall der Quelle.
  Stream<LocationSample> samples();
}
