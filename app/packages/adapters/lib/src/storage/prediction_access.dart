import 'package:core/core.dart';
import 'package:drift/drift.dart' show InsertMode, Value;

import 'access_support.dart';
import 'app_database.dart' as d;

/// Referenzleistungen und abgelehnte Vorschläge (FR-0129, FR-0131). Beides
/// hängt per Fremdschlüssel am Lauf (ON DELETE CASCADE, SEC-0004).
class DriftPredictionStore implements PredictionStore {
  DriftPredictionStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<int> addReference(ReferencePerformance reference) => guarded(() async {
    checkReferenceForStorage(reference);
    final runText = reference.runId;
    final runId = runText == null ? null : int.tryParse(runText);
    if (runText != null && runId == null) {
      throw const StorageException(StorageFailure.rejected);
    }
    // Prüfen und Einfügen in einer Transaktion: Zwei gleichzeitige Aufrufe
    // (Doppeltippen) dürfen nicht beide „noch keine Zeile“ sehen.
    return _db.transaction(() async {
      if (runId != null) {
        final run = await (_db.select(
          _db.runs,
        )..where((t) => t.id.equals(runId))).getSingleOrNull();
        if (run == null) throw const StorageException(StorageFailure.rejected);
        // Idempotent je Lauf: Ist der Lauf schon als Referenz gespeichert,
        // entsteht keine zweite Zeile, die vorhandene Kennung kommt zurück.
        final existing = await (_db.select(
          _db.referencePerformances,
        )..where((t) => t.runId.equals(runId))).get();
        if (existing.isNotEmpty) return existing.first.id;
      }
      return _db
          .into(_db.referencePerformances)
          .insert(
            d.ReferencePerformancesCompanion.insert(
              kind: reference.kind.name,
              distanceM: reference.distanceMeters,
              timeS: reference.seconds,
              performedOn: isoDay(calendarDay(reference.date)),
              createdAtUs: usOf(reference.createdAt),
              runId: Value(runId),
            ),
          );
    });
  });

  @override
  Future<void> deleteReference(int id) => guarded(() async {
    // Eine Referenz aus einem bestätigten Lauf hinterlässt eine Ablehnung für
    // diesen Lauf (wie rejectSuggestion), in derselben Transaktion: Sonst
    // würde der Lauf sofort wieder vorgeschlagen. Die Ablehnung ist Teil des
    // Archivs und überlebt Export und Reimport.
    await _db.transaction(() async {
      final row = await (_db.select(
        _db.referencePerformances,
      )..where((t) => t.id.equals(id))).getSingleOrNull();
      if (row == null) throw const StorageException(StorageFailure.notFound);
      await (_db.delete(
        _db.referencePerformances,
      )..where((t) => t.id.equals(id))).go();
      final runId = row.runId;
      if (row.kind == ReferenceKind.confirmedRun.name && runId != null) {
        await _db
            .into(_db.rejectedSuggestions)
            .insert(
              d.RejectedSuggestionsCompanion.insert(runId: runId),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
  });

  @override
  Future<List<StoredReference>> references() => guarded(() async {
    final rows = await _db.select(_db.referencePerformances).get();
    return sortedReferences([
      for (final r in rows)
        StoredReference(
          id: r.id,
          reference: ReferencePerformance(
            kind: enumOf(ReferenceKind.values, r.kind, (v) => v.name),
            distanceMeters: r.distanceM,
            seconds: r.timeS,
            date: DateTime.parse(r.performedOn),
            createdAt: timeOf(r.createdAtUs),
            runId: r.runId == null ? null : '${r.runId}',
          ),
        ),
    ]);
  });

  @override
  Future<ReferencePerformance?> activeReference() async {
    final all = await references();
    return all.isEmpty ? null : all.first.reference;
  }

  @override
  Future<void> rejectSuggestion(int runId) => guarded(() async {
    await requireRun(_db, runId);
    await _db
        .into(_db.rejectedSuggestions)
        .insert(
          d.RejectedSuggestionsCompanion.insert(runId: runId),
          mode: InsertMode.insertOrIgnore,
        );
  });

  @override
  Future<Set<int>> rejectedSuggestions() => guarded(() async {
    final rows = await _db.select(_db.rejectedSuggestions).get();
    return {for (final r in rows) r.runId};
  });
}
