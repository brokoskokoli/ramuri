/// Ein roher Standortpunkt (ADR-0005 Punkt 4: Filterung macht die Fachlogik).
class LocationSample {
  const LocationSample({
    required this.time,
    required this.latitude,
    required this.longitude,
    this.ageMs,
    this.accuracyMeters,
    this.altitudeMeters,
    this.speedMetersPerSecond,
    this.speedAccuracyMetersPerSecond,
    this.verticalAccuracyMeters,
  });

  final DateTime time;

  /// Alter des Punkts beim Senden in ms auf der Monotonuhr des Geräts
  /// (unabhängig von GPS-Zeit und Wanduhr); `null`, wenn nicht verfügbar. Die
  /// Aufzeichnung datiert den Punkt damit: Empfangszeit minus Alter.
  final int? ageMs;
  final double latitude;
  final double longitude;

  /// Fehlende Angaben bleiben `null` und werden nicht mit 0 aufgefüllt.
  final double? accuracyMeters;
  final double? altitudeMeters;
  final double? speedMetersPerSecond;
  final double? speedAccuracyMetersPerSecond;
  final double? verticalAccuracyMeters;
}

/// Grund eines Ausfalls der Standortquelle.
enum LocationFailureReason { permissionDenied, providerDisabled, other }

/// Fehler im Strom von [LocationSource.samples]. Der Strom läuft danach weiter,
/// sobald die Quelle wieder liefert (etwa nach erneutem Einschalten von GPS).
class LocationSourceFailure implements Exception {
  const LocationSourceFailure(this.reason);

  final LocationFailureReason reason;

  @override
  String toString() => 'LocationSourceFailure(${reason.name})';
}

/// Port: Standort. Die Quelle liefert Punkte, solange jemand zuhört.
abstract interface class LocationSource {
  /// Rohe Standortpunkte. Ein Fehler im Strom bedeutet Ausfall der Quelle.
  Stream<LocationSample> samples();
}
