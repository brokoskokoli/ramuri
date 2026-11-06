/// Wie genau der Standort ist, den die App nutzen darf (OQ-0064, FR-0195).
enum LocationAccess {
  /// Genauer Standort erteilt.
  precise,

  /// Nur ungefährer Standort erteilt.
  approximateOnly,

  /// Kein Standort erteilt.
  denied,
}

/// Port: Standortberechtigung prüfen und anfordern, GPS-Schalter lesen.
/// (Der Stand für die Berechtigungsseite liegt in [PermissionStatusPort].)
abstract interface class LocationAccessPort {
  /// Aktueller Stand, ohne den Nutzer zu fragen.
  Future<LocationAccess> access();

  /// Fragt den Nutzer (System-Dialog) und liefert den Stand danach.
  Future<LocationAccess> request();

  /// Ob der GPS-Anbieter im System eingeschaltet ist.
  Future<bool> gpsEnabled();
}
