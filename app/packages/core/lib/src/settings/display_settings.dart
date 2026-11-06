/// Anzeigeeinheit für Strecken (NFR-0006). Reine Anzeige: gespeichert und
/// berechnet wird immer in Metern beziehungsweise Sekunden je Kilometer.
enum DistanceUnit {
  kilometers('km'),
  miles('mi');

  const DistanceUnit(this.storageValue);

  /// Wert in den Einstellungen ([SettingKeys.distanceUnit]).
  final String storageValue;

  /// Meter je internationale Meile (exakt).
  static const double metersPerMile = 1609.344;

  /// Unbekannter oder fehlender Wert ergibt Kilometer.
  static DistanceUnit fromStorage(String? value) =>
      value == miles.storageValue ? miles : kilometers;

  /// Strecke in der Anzeigeeinheit (km oder mi).
  double distanceFromMeters(double meters) => switch (this) {
    kilometers => meters / 1000,
    miles => meters / metersPerMile,
  };

  /// Pace in Sekunden je Anzeigeeinheit aus Sekunden je Kilometer.
  double paceFromSecondsPerKm(double secondsPerKm) => switch (this) {
    kilometers => secondsPerKm,
    miles => secondsPerKm * metersPerMile / 1000,
  };
}

/// Schlüssel in [SettingsStore], die WP05 belegt.
abstract final class SettingKeys {
  /// `km` oder `mi`.
  static const String distanceUnit = 'display.distance_unit';

  /// `1`, sobald die Ersteinrichtung abgeschlossen oder übersprungen wurde
  /// (FR-0001); danach wird sie nicht mehr angeboten.
  static const String setupDone = 'setup.done';
}
