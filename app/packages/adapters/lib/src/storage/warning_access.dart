import 'package:core/core.dart';
import 'package:drift/drift.dart' show Value;

import 'access_support.dart';
import 'app_database.dart' as d;

/// Das aktive Warnsignal (FR-0203): eine Zeile mit `id = 1`. `run_id` ist kein
/// Fremdschlüssel, die Zeile übersteht das Löschen des Laufs.
class DriftWarningStore implements WarningStore {
  DriftWarningStore(this._db);
  final d.AppDatabase _db;

  @override
  Future<WarningSignal?> read() => guarded(() async {
    final r = await _db.select(_db.activeWarning).getSingleOrNull();
    if (r == null) return null;
    final source = WarningSource.fromCode(r.source);
    final day = DateTime.tryParse('${r.reportedOn}T00:00:00Z');
    if (source == null || day == null) {
      throw const StorageException(StorageFailure.failed);
    }
    return WarningSignal(reportedOn: day, source: source, runId: r.runId);
  });

  @override
  Future<void> set(WarningSignal warning) => guarded(() async {
    checkWarningForStorage(warning);
    await _db
        .into(_db.activeWarning)
        .insertOnConflictUpdate(
          d.ActiveWarningCompanion.insert(
            id: const Value(1),
            reportedOn: isoDay(warning.reportedOn),
            source: warning.source.code,
            runId: Value(warning.runId),
          ),
        );
  });

  @override
  Future<void> lift() => guarded(() async {
    await _db.delete(_db.activeWarning).go();
  });
}
