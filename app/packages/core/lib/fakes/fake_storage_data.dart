import '../src/preprocessing/measurement.dart';
import '../ports/storage.dart';
import '../ports/storage_consents.dart';
import '../ports/storage_derived.dart';
import '../ports/storage_devices.dart';
import '../ports/storage_plan.dart';
import '../ports/storage_prediction.dart';
import '../src/goals/training_goal.dart';
import '../src/plan/plan_unit.dart';
import '../ports/storage_profile.dart';
import '../ports/storage_raw.dart';
import '../ports/storage_runs.dart';
import '../ports/storage_values.dart';
import '../src/subjective/manual_training.dart';
import '../src/subjective/run_subjective.dart';

/// Inhalt der Fake-"Datei". Liegt im [FakeStorage] und überlebt Sitzungen.
class FakeStorageData {
  int nextRunId = 1;
  int nextGapId = 1;
  int nextTrainingId = 1;
  final nextRawId = {for (final c in RawChannel.values) c: 1};

  final runs = <int, StoredRun>{};
  final laps = <int, List<StoredLap>>{};
  final gaps = <int, List<StoredGap>>{};

  /// Je Lauf und Kanal Zeilen mit Wert (typisiert) oder ohne ([RawUnavailable]).
  final raw = <int, Map<RawChannel, List<StoredRaw<RawSample>>>>{};
  final rrPackets = <int, List<StoredRrPacket>>{};
  int nextRrId = 1;
  final preprocessing = <int, StoredPreprocessing>{};
  final sections = <int, List<RatedSection>>{};
  final values = <ValueOwner, Map<String, ValuePair>>{};
  final subjective = <int, StoredRunSubjective>{};
  final manualTrainings = <int, ManualTraining>{};

  ProfileRecord profile = const ProfileRecord();
  final settings = <String, String>{};
  final devices = <KnownDevice>[];
  final consents = <String, ConsentState>{};
  final references = <StoredReference>[];
  final rejectedSuggestions = <int>{};
  int nextReferenceId = 1;
  TrainingGoal? goal;

  /// Plan-Fassungen und -Einheiten nach Kennung (wie `plans`, `plan_units`).
  /// Die Einheit trägt Methode und Version ihrer Fassung erst beim Lesen.
  final planVersions = <int, PlanVersionRecord>{};
  final planUnits = <int, PlanUnit>{};
  final planUnitPlan = <int, int>{};
  int nextPlanId = 1;
  int nextPlanUnitId = 1;

  /// `ON DELETE CASCADE` vom Ziel: Fassungen und Einheiten.
  void deleteGoal() {
    goal = null;
    planVersions.clear();
    planUnits.clear();
    planUnitPlan.clear();
  }

  void requireRun(int runId) {
    if (!runs.containsKey(runId)) {
      throw const StorageException(StorageFailure.notFound);
    }
  }

  /// Kaskade wie `ON DELETE CASCADE`: alles unter dem Lauf. Dazu Tageswerte,
  /// deren Datenzeitraum den Lauf überlappt oder unbekannt ist (Einstellungen
  /// und Profil bleiben). Der Lauf muss existieren.
  void deleteRun(int runId) {
    final run = runs[runId]!;
    final start = run.startedAt.microsecondsSinceEpoch;
    // Ohne Ende (aktiv oder pausiert) reicht der Lauf unbegrenzt weit.
    final end = run.endedAt?.microsecondsSinceEpoch;
    for (final owner in values.keys.toList()) {
      if (owner.day == null) continue;
      final pairs = values[owner]!;
      pairs.removeWhere(
        (_, p) =>
            _overlaps(p.original, start, end) ||
            _overlaps(p.current, start, end),
      );
    }
    values.removeWhere((o, pairs) => o.day != null && pairs.isEmpty);
    runs.remove(runId);
    laps.remove(runId);
    gaps.remove(runId);
    raw.remove(runId);
    rrPackets.remove(runId);
    preprocessing.remove(runId);
    sections.remove(runId);
    subjective.remove(runId);
    values.remove(ValueOwner.run(runId));
    references.removeWhere((r) => r.reference.runId == '$runId');
    rejectedSuggestions.remove(runId);
    // `ON DELETE SET NULL`: Die Einheit bleibt, die Zuordnung endet.
    for (final id in planUnits.keys.toList()) {
      if (planUnits[id]!.runId == runId) {
        planUnits[id] = planUnits[id]!.copyWith(clearRun: true);
      }
    }
  }

  static bool _overlaps(ComputedValue v, int runStart, int? runEnd) {
    final from = (v.dataFrom ?? v.dataTo)?.microsecondsSinceEpoch;
    final to = (v.dataTo ?? v.dataFrom)?.microsecondsSinceEpoch;
    // Unbekannter Zeitraum: sicher löschen, WP09 berechnet neu.
    if (from == null || to == null) return true;
    return from <= (runEnd ?? to) && to >= runStart;
  }

  /// Alles, auch die Zähler (wie `sqlite_sequence` in der Datenbank).
  void deleteAll() {
    nextRunId = 1;
    nextGapId = 1;
    nextTrainingId = 1;
    for (final c in RawChannel.values) {
      nextRawId[c] = 1;
    }
    runs.clear();
    laps.clear();
    gaps.clear();
    raw.clear();
    rrPackets.clear();
    nextRrId = 1;
    preprocessing.clear();
    sections.clear();
    values.clear();
    subjective.clear();
    manualTrainings.clear();
    profile = const ProfileRecord();
    settings.clear();
    devices.clear();
    consents.clear();
    references.clear();
    rejectedSuggestions.clear();
    nextReferenceId = 1;
    nextPlanId = 1;
    nextPlanUnitId = 1;
    deleteGoal();
  }
}
