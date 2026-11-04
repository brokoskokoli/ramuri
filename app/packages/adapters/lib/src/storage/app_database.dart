import 'package:core/core.dart' show StorageFailure;
import 'package:drift/drift.dart';

import 'connection_setup.dart' show ConnectionSetupFailure;

part 'app_database.g.dart';

/// Ein Migrationsschritt von Version `n` auf `n + 1`.
typedef MigrationStep = Future<void> Function(Migrator m);

/// Die Tabellen stehen in `schema.drift` (Schema Phase 1, Version 1).
@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Phase 1 ist Version 1 (WP02 Teil B). Jede spätere Änderung erhöht die
  /// Zahl (Literal, damit `drift_dev schema dump` sie lesen kann), ergänzt
  /// einen Eintrag in [migrationSteps] und einen neuen Dump in `drift_schemas/`.
  @override
  int get schemaVersion => 1;

  /// Schritt `n` überführt Version `n` in `n + 1`. Es gibt noch keinen. Tests
  /// überschreiben das mit einem synthetischen Schritt.
  Map<int, MigrationStep> get migrationSteps => const {};

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      // onUpgrade gilt auch für Herabstufen (from > to): Eine neuere Datei
      // darf eine ältere App nicht öffnen. Fehlt ein Schritt, öffnet die
      // Datenbank ebenfalls nicht (fail-closed).
      if (to < from) {
        throw const ConnectionSetupFailure(StorageFailure.newerVersion);
      }
      try {
        // Alle Schritte in einer Transaktion: Scheitert einer, bleibt nichts
        // von den früheren zurück, und "Erneut versuchen" startet sauber.
        await transaction(() async {
          for (var v = from; v < to; v++) {
            final step = migrationSteps[v];
            if (step == null) {
              throw const ConnectionSetupFailure(
                StorageFailure.migrationFailed,
              );
            }
            await step(m);
          }
        });
      } catch (_) {
        // Jeder Fehler eines Schritts ist ein Migrationsfehler, ohne Ursache:
        // Sie könnte Statement und Parameter tragen. Die Ausnahme verlässt den
        // Hintergrund-Isolate nur als Text; die Kennung bleibt erkennbar.
        throw const ConnectionSetupFailure(StorageFailure.migrationFailed);
      }
    },
  );
}
