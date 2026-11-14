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

  /// Zuletzt gewählte Laufart der Seite „Lauf vorbereiten“ (FR-0196):
  /// `treadmill` oder `gps`; fehlt der Eintrag, gilt `gps`.
  static const String runMode = 'recording.run_mode';

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

  /// Technischer Merker: die mit einem offenen Angebot geänderte, noch nicht
  /// bestätigte Koeffizienten-Angabe (`male`, `female` oder `none` für
  /// „Angabe entfernen“). Nicht im Archiv (Vertrag 4.3).
  static const String loadCoefficientsPending = 'load.coefficients_pending';

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

  /// Haltung bei der Kamera-Messung des gespeicherten Ruhepulses (FR-0214):
  /// `sitting` oder `lying`. Fehlt oder leer: der Ruhepuls wurde nicht mit der
  /// Kamera gemessen. Kommt ins Archiv (ADR-0011 Punkt 8).
  static const String restingHrPosture = 'resting_hr.posture';

  /// Zeitpunkt dieser Messung, UTC im ISO-8601-Format. Kommt ins Archiv.
  static const String restingHrMeasuredAt = 'resting_hr.measured_at';

  /// Quelle des Ruhepulses: `camera`. Kommt ins Archiv.
  static const String restingHrSource = 'resting_hr.source';

  /// Technischer Merker (WP22): die über „Einheit starten“ gestartete
  /// Plan-Einheit, bis ihr Lauf zugeordnet ist, `einheit;JJJJ-MM-TT;sekunden`
  /// (Kennung der Einheit, Ortstag des Starts, Startzeit in Sekunden seit
  /// 1970, UTC). Leer = keine. Überlebt Absturz und Wiederaufnahme (FR-0193).
  static const String planStartedUnit = 'plan.started_unit';

  /// `1`, wenn Erinnerungen vor geplanten Einheiten eingeschaltet sind
  /// (FR-0174); fehlt der Eintrag, sind sie aus. Nutzereinstellung, kommt ins
  /// Archiv; nach einem Import plant die App nur mit erteilter Berechtigung.
  static const String reminderEnabled = 'reminder.enabled';

  /// Trainingszeit `HH:MM` (Ortszeit, für alle Tage gleich); fehlt der
  /// Eintrag, gilt 18:00 (Vorschlag WP22).
  static const String reminderTime = 'reminder.time';

  /// Vorlauf der Erinnerung in Minuten: 15, 30 oder 60; fehlt der Eintrag,
  /// gilt 30 (Vorschlag WP22).
  static const String reminderLeadMinutes = 'reminder.lead_minutes';

  /// Ansagen (WP24, Festlegung 10): Hauptschalter und je Art ein Schalter.
  /// `0` = aus; fehlt der Eintrag, gilt „an“. Nutzereinstellungen, kommen ins
  /// Archiv.
  static const String guidanceEnabled = 'guidance.enabled';
  static const String guidanceKilometer = 'guidance.kilometer';
  static const String guidanceHeartRate = 'guidance.heart_rate';
  static const String guidanceSegments = 'guidance.segments';

  /// Technischer Merker (WP24): Abschnitte der geführten Einheit, beim Start
  /// kopiert (JSON, `GuidedUnitSnapshot`), mit Lauf-Kennung. Nicht im Archiv
  /// (Vertrag 4.3).
  static const String guidedUnitSnapshot = 'guided.unit_snapshot';

  /// Entwicklermodus (FR-0217, WP33): `1` = an; fehlt der Eintrag, aus. Gerätezustand,
  /// nicht im Archiv (Vertrag 4.3); „Alles löschen“ leert die Tabelle und setzt ihn zurück.
  static const String developerMode = 'developer.mode';

  /// Morgenfenster der Morgenmessung (PAR-160K) als `H-H` in ganzen Stunden Ortszeit, etwa
  /// `4-11`; fehlt der Eintrag oder ist er ungültig, gilt 4-11. Nutzereinstellung, kommt ins Archiv.
  static const String morningWindow = 'morning.window';

  /// Opt-in „Kamera-RMSSD einbeziehen“ (K-1, Validierungssperre): `1` = an; fehlt der Eintrag, aus.
  /// Bewusste Nutzerentscheidung, kommt mit ins Archiv.
  static const String morningCameraRmssdOptIn = 'morning.camera_rmssd_optin';

  /// Erinnerung am Morgen (WP33 Teil D): `1` = an; fehlt der Eintrag, aus.
  /// Nutzereinstellung, kommt ins Archiv.
  static const String morningReminderEnabled = 'morning.reminder_enabled';

  /// Uhrzeit der Morgen-Erinnerung `HH:MM` (Ortszeit); fehlt sie, gilt 06:30.
  /// Liegt nur hier in der verschlüsselten Datenbank (SEC-0009), nicht im
  /// System-Speicher des Adapters.
  static const String morningReminderTime = 'morning.reminder_time';
}
