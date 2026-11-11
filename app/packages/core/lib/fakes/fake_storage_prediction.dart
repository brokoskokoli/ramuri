import '../ports/storage.dart';
import '../ports/storage_prediction.dart';
import '../src/prediction/reference_performance.dart';
import '../src/prediction/reference_performance.dart'
    as rp
    show activeReference;
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
    // Idempotent je Lauf (wie die Datenbank).
    if (runText != null) {
      for (final r in _d.references) {
        if (r.reference.runId == runText) return r.id;
      }
    }
    final id = _d.nextReferenceId++;
    _d.references.add(StoredReference(id: id, reference: reference));
    return id;
  }

  @override
  Future<void> deleteReference(int id) async {
    final hit = _d.references.where((r) => r.id == id).toList();
    if (hit.isEmpty) throw const StorageException(StorageFailure.notFound);
    _d.references.removeWhere((r) => r.id == id);
    // Wie die Datenbank: Referenz aus einem bestätigten Lauf hinterlässt eine
    // Ablehnung für diesen Lauf.
    final ref = hit.first.reference;
    final runId = int.tryParse(ref.runId ?? '');
    if (ref.kind == ReferenceKind.confirmedRun && runId != null) {
      _d.rejectedSuggestions.add(runId);
    }
  }

  @override
  Future<List<StoredReference>> references() async =>
      sortedReferences(_d.references);

  @override
  Future<ReferencePerformance?> activeReference() async {
    final all = await references();
    return rp.activeReference([for (final s in all) s.reference]);
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
