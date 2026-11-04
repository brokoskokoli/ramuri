import '../src/preprocessing/measurement.dart';
import '../ports/storage.dart';
import '../ports/storage_consents.dart';
import '../ports/storage_derived.dart';
import '../ports/storage_devices.dart';
import '../ports/storage_profile.dart';
import '../ports/storage_raw.dart';
import '../ports/storage_runs.dart';
import '../ports/storage_values.dart';

/// Inhalt der Fake-"Datei". Liegt im [FakeStorage] und überlebt Sitzungen.
class FakeStorageData {
  int nextRunId = 1;
  int nextGapId = 1;
  final nextRawId = {for (final c in RawChannel.values) c: 1};

  final runs = <int, StoredRun>{};
  final laps = <int, List<StoredLap>>{};
  final gaps = <int, List<StoredGap>>{};

  /// Je Lauf und Kanal Zeilen mit Wert (typisiert) oder ohne ([RawUnavailable]).
  final raw = <int, Map<RawChannel, List<StoredRaw<RawSample>>>>{};
  final preprocessing = <int, StoredPreprocessing>{};
  final sections = <int, List<RatedSection>>{};
  final values = <ValueOwner, Map<String, ValuePair>>{};

  ProfileRecord profile = const ProfileRecord();
  final settings = <String, String>{};
  final devices = <KnownDevice>[];
  final consents = <String, ConsentState>{};

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
    preprocessing.remove(runId);
    sections.remove(runId);
    values.remove(ValueOwner.run(runId));
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
    for (final c in RawChannel.values) {
      nextRawId[c] = 1;
    }
    runs.clear();
    laps.clear();
    gaps.clear();
    raw.clear();
    preprocessing.clear();
    sections.clear();
    values.clear();
    profile = const ProfileRecord();
    settings.clear();
    devices.clear();
    consents.clear();
  }
}
