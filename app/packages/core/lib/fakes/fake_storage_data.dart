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

  /// Kaskade wie `ON DELETE CASCADE`: alles unter dem Lauf. Tageswerte,
  /// Einstellungen und Profil bleiben.
  void deleteRun(int runId) {
    runs.remove(runId);
    laps.remove(runId);
    gaps.remove(runId);
    raw.remove(runId);
    preprocessing.remove(runId);
    sections.remove(runId);
    values.remove(ValueOwner.run(runId));
  }
}
