import '../ports/health_import.dart';
import '../ports/storage_health.dart';

/// Speicher im Arbeitsspeicher für Tests: je Art nach Health-Connect-ID, gleiche
/// ID überschreibt.
class FakeHealthImportStore implements HealthImportStore {
  final Map<HealthDataKind, Map<String, HealthRecord>> _byKind = {};
  final Map<String, List<HealthHeartRateSample>> _heartRates = {};

  /// Wie oft ein Upsert aufgerufen wurde (Tests).
  int upsertCalls = 0;

  List<HealthRecord> records(HealthDataKind kind) =>
      List.unmodifiable((_byKind[kind] ?? const {}).values);

  @override
  Future<List<HealthHeartRateSample>> exerciseHeartRate(String hcId) async =>
      List.unmodifiable(_heartRates[hcId] ?? const []);

  @override
  Future<List<HealthRecord>> values(
    HealthDataKind kind,
    DateTime from,
    DateTime to,
  ) async {
    final out = [
      for (final r in records(kind))
        if (!r.start.isBefore(from) && r.start.isBefore(to)) r,
    ];
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  @override
  Future<List<HealthRecord>> exercises(DateTime from, DateTime to) async {
    final out = [
      for (final r in records(HealthDataKind.exercise))
        if (r.start.isBefore(to) && r.end.isAfter(from)) r,
    ];
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  void _put(List<HealthRecord> records) {
    upsertCalls++;
    for (final r in records) {
      (_byKind[r.kind] ??= {})[r.id] = r;
    }
  }

  @override
  Future<void> upsertSleep(List<HealthRecord> records) async => _put(records);

  @override
  Future<void> upsertValues(List<HealthRecord> records) async => _put(records);

  @override
  Future<void> upsertExercises(List<HealthRecord> records) async =>
      _put(records);

  @override
  Future<bool> replaceExerciseHeartRate(
    String exerciseHcId,
    List<HealthHeartRateSample> samples,
  ) async {
    if (!(_byKind[HealthDataKind.exercise]?.containsKey(exerciseHcId) ??
        false)) {
      return false;
    }
    _heartRates[exerciseHcId] = List.of(samples);
    return true;
  }

  @override
  Future<int> count(HealthDataKind kind) async {
    if (kind == HealthDataKind.heartRate) {
      return _heartRates.values.fold<int>(0, (a, l) => a + l.length);
    }
    return _byKind[kind]?.length ?? 0;
  }

  @override
  Future<void> deleteKind(HealthDataKind kind) async {
    if (kind == HealthDataKind.heartRate) {
      _heartRates.clear();
      return;
    }
    _byKind.remove(kind);
    if (kind == HealthDataKind.exercise) _heartRates.clear();
  }
}
