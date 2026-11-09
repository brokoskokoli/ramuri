import '../ports/storage.dart';
import '../ports/storage_prediction.dart';
import '../src/prediction/reference_performance.dart';
import 'fake_storage_data.dart';

class FakePredictionStore implements PredictionStore {
  FakePredictionStore(this._d);
  final FakeStorageData _d;

  @override
  Future<int> addReference(ReferencePerformance reference) async {
    checkReferenceForStorage(reference);
    final runText = reference.runId;
    if (runText != null && !_d.runs.containsKey(int.tryParse(runText))) {
      throw const StorageException(StorageFailure.rejected);
    }
    final id = _d.nextReferenceId++;
    _d.references.add(StoredReference(id: id, reference: reference));
    return id;
  }

  @override
  Future<void> deleteReference(int id) async {
    final n = _d.references.length;
    _d.references.removeWhere((r) => r.id == id);
    if (_d.references.length == n) {
      throw const StorageException(StorageFailure.notFound);
    }
  }

  @override
  Future<List<StoredReference>> references() async =>
      sortedReferences(_d.references);

  @override
  Future<ReferencePerformance?> activeReference() async {
    final all = await references();
    return all.isEmpty ? null : all.first.reference;
  }

  @override
  Future<void> rejectSuggestion(int runId) async {
    _d.requireRun(runId);
    _d.rejectedSuggestions.add(runId);
  }

  @override
  Future<Set<int>> rejectedSuggestions() async =>
      Set.of(_d.rejectedSuggestions);
}
