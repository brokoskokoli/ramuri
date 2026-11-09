import '../ports/storage.dart';
import '../ports/storage_subjective.dart';
import '../src/subjective/manual_training.dart';
import '../src/subjective/run_subjective.dart';
import '../src/subjective/srpe.dart';
import 'fake_storage_data.dart';

class FakeRunSubjectiveStore implements RunSubjectiveStore {
  FakeRunSubjectiveStore(this._d);
  final FakeStorageData _d;

  @override
  Future<StoredRunSubjective?> read(int runId) async => _d.subjective[runId];

  @override
  Future<Map<int, StoredRunSubjective>> readAll() async =>
      Map.of(_d.subjective);

  @override
  Future<void> save(
    int runId,
    RunSubjective subjective, {
    SrpeLoad? srpe,
  }) async {
    _d.requireRun(runId);
    // Wie die CHECK-Bedingung: sRPE nur mit RPE, und dasselbe RPE.
    if (srpe != null && srpe.rpe != subjective.rpe) {
      throw const StorageException(StorageFailure.rejected);
    }
    if (subjective.isEmpty) {
      _d.subjective.remove(runId);
      return;
    }
    _d.subjective[runId] = StoredRunSubjective(
      subjective: subjective,
      srpe: srpe,
    );
  }

  @override
  Future<bool> setSrpe(
    int runId,
    SrpeLoad? srpe, {
    required int? expectedRpe,
  }) async {
    if (srpe != null && srpe.rpe != expectedRpe) {
      throw const StorageException(StorageFailure.rejected);
    }
    final cur = _d.subjective[runId];
    if (cur == null || cur.subjective.rpe != expectedRpe) return false;
    _d.subjective[runId] = StoredRunSubjective(
      subjective: cur.subjective,
      srpe: srpe,
    );
    return true;
  }
}

class FakeManualTrainingStore implements ManualTrainingStore {
  FakeManualTrainingStore(this._d);
  final FakeStorageData _d;

  @override
  Future<StoredManualTraining> add(ManualTraining training) async {
    final id = _d.nextTrainingId++;
    _d.manualTrainings[id] = training;
    return StoredManualTraining(id: id, training: training);
  }

  void _require(int id) {
    if (!_d.manualTrainings.containsKey(id)) {
      throw const StorageException(StorageFailure.notFound);
    }
  }

  @override
  Future<void> update(int id, ManualTraining training) async {
    _require(id);
    _d.manualTrainings[id] = training;
  }

  @override
  Future<void> delete(int id) async {
    _require(id);
    _d.manualTrainings.remove(id);
  }

  @override
  Future<StoredManualTraining?> get(int id) async {
    final t = _d.manualTrainings[id];
    return t == null ? null : StoredManualTraining(id: id, training: t);
  }

  @override
  Future<List<StoredManualTraining>> list() async {
    final all = [
      for (final e in _d.manualTrainings.entries)
        StoredManualTraining(id: e.key, training: e.value),
    ];
    all.sort((a, b) {
      final c = b.training.day.compareTo(a.training.day);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    return all;
  }
}
