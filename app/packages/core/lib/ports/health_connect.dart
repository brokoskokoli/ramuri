enum HealthConnectAvailability {
  available,

  /// Anbieter vorhanden, aber zu alt (SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED).
  updateRequired,

  /// Nicht verfügbar (SDK_UNAVAILABLE).
  unavailable,
}

/// Port: Health Connect. Bis Phase 3 nur die Verfügbarkeitsabfrage (ADR-0007).
abstract interface class HealthConnect {
  Future<HealthConnectAvailability> availability();
}
