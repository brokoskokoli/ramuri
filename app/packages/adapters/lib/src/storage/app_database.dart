import 'package:drift/drift.dart';

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
        throw StateError('schema downgrade $from -> $to is not supported');
      }
      for (var v = from; v < to; v++) {
        final step = migrationSteps[v];
        if (step == null) {
          throw StateError('missing migration step $v -> ${v + 1}');
        }
        await step(m);
      }
    },
  );
}
