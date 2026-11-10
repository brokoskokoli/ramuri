import '../src/goals/training_goal.dart';
import 'storage.dart' show StorageException, StorageFailure;

/// Das Trainingsziel (FR-0135 bis FR-0137). Es gibt höchstens ein Ziel
/// (mehrere gleichzeitige Ziele sind nicht im Umfang, goals.md).
abstract interface class GoalStore {
  /// Das Ziel oder `null`.
  Future<TrainingGoal?> goal();

  /// Legt das Ziel an oder ersetzt es (Ändern, PAR-203). Ungültig
  /// ([TrainingGoal.validate]): `rejected`, das bisherige Ziel bleibt.
  ///
  /// [today] (Ortstag „heute“, kein Uhr-Zugriff im Speicher) ist Pflicht,
  /// damit ein Zieldatum in der Vergangenheit abgelehnt wird, auch wenn
  /// `createdAt` älter ist. Beim Anlegen gilt `today = createdAt`.
  Future<void> save(TrainingGoal goal, {required DateTime today});

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
/// nicht. Maßgeblich ist [today] (beim Anlegen `createdAt`). Der Stand (PAR-192)
/// wird nicht verlangt: Läufe ersetzen ihn, die Planung prüft ihn.
void checkGoalForStorage(TrainingGoal g, {required DateTime today}) {
  if (g.validate(today, null, false) != null) {
    throw const StorageException(StorageFailure.rejected);
  }
}
