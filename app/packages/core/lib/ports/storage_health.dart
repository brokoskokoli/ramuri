import 'health_import.dart';

/// Speicher der aus Health Connect importierten Daten (WP32 Teil B/C). Gleiche
/// Health-Connect-ID: überschreiben, nie doppelt speichern.
abstract interface class HealthImportStore {
  Future<void> upsertSleep(List<HealthRecord> records);
  Future<void> upsertValues(List<HealthRecord> records);
  Future<void> upsertExercises(List<HealthRecord> records);

  /// Ersetzt die Pulswerte einer Einheit; `false`, wenn die Einheit fehlt.
  Future<bool> replaceExerciseHeartRate(
    String exerciseHcId,
    List<HealthHeartRateSample> samples,
  );

  /// Anzahl gespeicherter Sätze der Art.
  Future<int> count(HealthDataKind kind);

  /// Löscht die importierten Daten genau dieser Art.
  Future<void> deleteKind(HealthDataKind kind);
}

/// Optionaler Zugriff der Sitzung auf die importierten Gesundheitsdaten (wie
/// `PredictionStorage`): Sitzungen ohne ihn gelten als ohne Importdaten.
abstract interface class HealthStorage {
  HealthImportStore get health;
}
