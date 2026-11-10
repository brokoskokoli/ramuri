import '../src/goals/training_goal.dart';
import 'storage.dart' show StorageException, StorageFailure;

/// Das Trainingsziel (FR-0135 bis FR-0137). Es gibt höchstens ein Ziel
/// (mehrere gleichzeitige Ziele sind nicht im Umfang, goals.md).
abstract interface class GoalStore {
  /// Das Ziel oder `null`.
  Future<TrainingGoal?> goal();

  /// Legt das Ziel an oder ersetzt es (Ändern, PAR-203). Ungültig
  /// ([TrainingGoal.validate] zum Anlegezeitpunkt `createdAt`):
  /// `rejected`, das bisherige Ziel bleibt.
  Future<void> save(TrainingGoal goal);

  /// Löscht das Ziel. Kein Ziel: `notFound`.
  Future<void> delete();
}

/// Ein Speicher, der das Ziel führt; bewusst getrennt von
/// [StorageSession] (wie `PredictionStorage`).
abstract interface class GoalStorage {
  GoalStore get goals;
}

/// Prüfung vor dem Speichern, gleich für Fake und Datenbank. Gültig wird zum
/// Anlegezeitpunkt beurteilt: Ein Datum von heute ist gültig, ein früheres
/// nicht. Der Stand (PAR-192) wird nicht verlangt: Läufe ersetzen ihn, die
/// Planung prüft ihn.
void checkGoalForStorage(TrainingGoal g) {
  if (g.validate(g.createdAt, null, false) != null) {
    throw const StorageException(StorageFailure.rejected);
  }
}
