import '../src/subjective/manual_training.dart';
import '../src/subjective/run_subjective.dart';
import '../src/subjective/srpe.dart';

/// Angaben zum Lauf (FR-0038): höchstens ein Satz je Lauf. Gelöscht wird mit
/// dem Lauf (`deleteRun`) oder komplett (`deleteAll`); sonst über [save] mit
/// leeren Angaben.
abstract interface class RunSubjectiveStore {
  /// `null`, wenn zum Lauf nichts gespeichert ist.
  Future<StoredRunSubjective?> read(int runId);

  /// Alle gespeicherten Sätze in einer Abfrage, Schlüssel ist die Lauf-ID.
  Future<Map<int, StoredRunSubjective>> readAll();

  /// Ersetzt den Satz des Laufs samt sRPE-Wert. Leere Angaben ohne [srpe]
  /// entfernen den Satz. Unbekannter Lauf: `notFound`. [srpe] ohne passendes
  /// RPE in [subjective]: `rejected`.
  Future<void> save(int runId, RunSubjective subjective, {SrpeLoad? srpe});

  /// Setzt nur die vier sRPE-Spalten des Satzes, alle übrigen Angaben bleiben
  /// unberührt. Greift nur, wenn der Satz existiert und sein RPE noch
  /// [expectedRpe] ist (atomar); sonst bleibt alles wie es ist. Gibt zurück,
  /// ob geschrieben wurde. [srpe] mit anderem RPE als [expectedRpe]: `rejected`.
  Future<bool> setSrpe(int runId, SrpeLoad? srpe, {required int? expectedRpe});
}

/// Nachgetragene Trainings (FR-0199), unabhängig von Läufen.
abstract interface class ManualTrainingStore {
  Future<StoredManualTraining> add(ManualTraining training);

  /// Unbekannte Id: `notFound`.
  Future<void> update(int id, ManualTraining training);

  /// Unbekannte Id: `notFound`.
  Future<void> delete(int id);

  Future<StoredManualTraining?> get(int id);

  /// Neuester Tag zuerst, dann höhere Id zuerst.
  Future<List<StoredManualTraining>> list();
}
