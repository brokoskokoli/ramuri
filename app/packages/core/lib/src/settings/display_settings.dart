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

  /// Meter je internationalem Fuß (exakt).
  static const double metersPerFoot = 0.3048;

  /// Höhe in der Anzeigeeinheit: Meter bei km, Fuß bei Meilen.
  double elevationFromMeters(double meters) => switch (this) {
    kilometers => meters,
    miles => meters / metersPerFoot,
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

  /// Grenzen der fünf Reservezonen in ganzen Prozent, kommagetrennt
  /// (FR-0061), zum Beispiel `50,60,70,80,90,100`.
  static const String reserveZoneBounds = 'zones.reserve_bounds';

  /// `1`, wenn die Autopause eingeschaltet ist (FR-0029); fehlt der Eintrag,
  /// gilt sie als aus (OQ-0065).
  static const String autoPause = 'recording.auto_pause';

  /// Aktives Belastungsprofil (FR-0197): `edwards` oder `banister`; fehlt der
  /// Eintrag, gilt `edwards`. Geschrieben wird er nur von der Neuberechnung
  /// nach Bestätigung (OQ-0053), siehe `LoadSettings`.
  static const String loadProfile = 'load.profile';

  /// Koeffizienten-Angabe des Profils (FR-0002): `male` oder `female`; fehlt
  /// oder leer = keine Angabe.
  static const String loadCoefficients = 'load.coefficients';

  /// `1`, wenn der Nutzer zusagt, dass alle Trainings erfasst sind (FR-0103);
  /// fehlt der Eintrag, gilt keine Zusage.
  static const String loadAllRecorded = 'load.all_recorded';

  /// Technischer Merker: das mit einem offenen Angebot gewählte, noch nicht
  /// bestätigte Belastungsprofil. Nicht im Archiv (Vertrag 4.3).
  static const String loadProfilePending = 'load.profile_pending';

  /// Angewandter persönlicher Faktor TRIMP/sRPE (FR-0097, PAR-087) mit Profil,
  /// Zahl der Läufe und Datum: `profil;wert;läufe;JJJJ-MM-TT`. Fehlt der
  /// Eintrag oder ist er unlesbar, gibt es keinen Faktor. Kommt ins Archiv.
  static const String loadFactor = 'load.factor';

  /// Technischer Merker: der zu einem offenen Angebot berechnete neue Faktor
  /// (gleiches Format wie [loadFactor]). Nicht im Archiv (Vertrag 4.3).
  static const String loadFactorPending = 'load.factor_pending';

  /// Technischer Merker: der zuletzt abgelehnte neue Faktor; solange der
  /// berechnete Faktor innerhalb der Toleranz davon liegt, wird er nicht
  /// erneut angeboten. Nicht im Archiv (Vertrag 4.3).
  static const String loadFactorDeclined = 'load.factor_declined';
}
