import 'package:core/core.dart' show StorageFailure;
import 'package:drift/drift.dart';

import 'connection_setup.dart' show ConnectionSetupFailure;

part 'app_database.g.dart';

/// Ein Migrationsschritt von Version `n` auf `n + 1`.
typedef MigrationStep = Future<void> Function(Migrator m);

/// Die Tabellen stehen in `schema.drift` (Schema Phase 1, ab Version 3 mit value_sections).
@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Version 1: Phase 1 (WP02 Teil B). Version 2: Tempo, Tempo- und
  /// Vertikalgenauigkeit je Rohposition (WP06 Teil C, K12). Version 3: value_sections
  /// und Grund-, Basis- und Versatzspalten (WP09 D1/D2a). Version 4: Bestpace, Rundenzahl und Zeit mit Puls in
  /// `preprocessing_results` (WP10). Version 5: Angaben zum Lauf
  /// (`run_feedback`) und nachgetragene Trainings (`manual_trainings`, WP18).
  /// Version 6: Referenzleistungen und abgelehnte Vorschläge der
  /// Leistungsprognose (WP20). Version 7: Trainingsziel (`goals`,
  /// WP21 Teil B) und Plan (`plans`, `plan_units`, WP21 Teil C).
  /// Version 8: Festlegung des Nutzers je Einheit (`plan_units.fixed`, WP22:
  /// Art ersetzt, Ruhetag). Jede spätere Änderung erhöht die
  /// Zahl (Literal, damit `drift_dev schema dump` sie lesen kann), ergänzt
  /// einen Eintrag in [migrationSteps] und einen neuen Dump in `drift_schemas/`.
  @override
  int get schemaVersion => 8;

  /// Schritt `n` überführt Version `n` in `n + 1`. Tests hängen für die
  /// nächste Version einen synthetischen Schritt an.
  Map<int, MigrationStep> get migrationSteps => {
    1: (m) async {
      // Bestehende Zeilen bekommen NULL (nicht geliefert), nie 0.
      await m.addColumn(rawPositions, rawPositions.speedMps);
      await m.addColumn(rawPositions, rawPositions.speedAccuracyMps);
      await m.addColumn(rawPositions, rawPositions.verticalAccuracyM);
    },
    // 2 -> 3 (WP09): neue Tabelle samt Triggern, Grund-, Basis- und Versatzspalten.
    2: (Migrator m) async {
      await m.create(valueSections);
      await m.create(valueSectionsOriginalImmutable);
      await m.create(valueSectionsOriginalNoLateInsert);
      await m.addColumn(computedValues, computedValues.unavailableReason);
      // Alte Zeilen ohne Wert hatten keinen Grund; sie bekommen den
      // allgemeinen (insufficientData), damit die Regel für alle Zeilen gilt.
      // Das Original ist per Trigger unveränderlich: nur hierfür ausnehmen.
      await m.drop(computedValuesOriginalImmutable);
      await customStatement(
        "UPDATE computed_values SET unavailable_reason = 'insufficientData' "
        'WHERE value_real IS NULL',
      );
      await m.create(computedValuesOriginalImmutable);
      await m.create(computedValuesReasonInsert);
      await m.create(computedValuesReasonUpdate);
      // D2a: Basis-Schnappschuss (alte Zeilen: unbekannt = NULL) und UTC-Versatz
      // des Laufendes (alte Läufe: unbekannt = NULL).
      await m.addColumn(computedValues, computedValues.hrMaxBpm);
      await m.addColumn(computedValues, computedValues.hrRestBpm);
      await m.addColumn(computedValues, computedValues.hrMaxIsEstimated);
      await m.create(computedValuesBasisInsert);
      await m.create(computedValuesBasisUpdate);
      await m.addColumn(runs, runs.endedUtcOffsetS);
      await m.create(runsOffsetInsert);
      await m.create(runsOffsetUpdate);
    },
    // 3 -> 4 (WP10): Bestpace, Rundenzahl und Zeit mit Puls in der Kurzfassung.
    // Alte Zeilen bekommen NULL (nicht bekannt, nie 0); sie tragen noch die
    // alte methodVersion und werden beim Lesen neu gerechnet.
    3: (Migrator m) async {
      await m.addColumn(
        preprocessingResults,
        preprocessingResults.bestPaceSPerKm,
      );
      await m.addColumn(preprocessingResults, preprocessingResults.lapCount);
      await m.addColumn(
        preprocessingResults,
        preprocessingResults.heartRateTimeS,
      );
    },
    // 4 -> 5 (WP18): zwei neue Tabellen, kein Eingriff in bestehende Daten.
    4: (Migrator m) async {
      await m.create(runFeedback);
      await m.create(manualTrainings);
      await m.create(manualTrainingsDay);
    },
    // 5 -> 6 (WP20): zwei neue Tabellen, bestehende Zeilen bleiben unberührt.
    5: (Migrator m) async {
      await m.create(referencePerformances);
      await m.create(referencePerformancesRun);
      await m.create(rejectedSuggestions);
    },
    // 6 -> 7 (WP21): Trainingsziel, Plan-Fassungen und -Einheiten;
    // bestehende Zeilen bleiben unberührt.
    6: (Migrator m) async {
      await m.create(goals);
      await m.create(plans);
      await m.create(plansGoal);
      await m.create(planUnits);
      await m.create(planUnitsDay);
      await m.create(planUnitsPlan);
      await m.create(planUnitsRun);
    },
    // 7 -> 8 (WP22): Spalte `fixed`; bestehende Einheiten bekommen 'none'
    // (Standardwert der Spalte), Termine (`pinned`) bleiben.
    // Kommt die Datei von Version 6 oder älter, hat Schritt 6 `plan_units`
    // schon mit der aktuellen Definition (samt `fixed`) angelegt: `m.create`
    // nutzt immer den Stand der App. Dann fehlt nichts mehr.
    7: (Migrator m) async {
      final columns = await m.database
          .customSelect("SELECT name FROM pragma_table_info('plan_units')")
          .get();
      if (columns.any((r) => r.data['name'] == 'fixed')) return;
      await m.addColumn(planUnits, planUnits.fixed);
    },
  };

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
          // Die Version gehört in dieselbe Transaktion: drift schreibt sie
          // erst nach beforeOpen (drift 2.35.3 engines.dart), also nach dem
          // Commit. Ein Abbruch dazwischen würde die Schritte wiederholen
          // (etwa doppelte Spalte) und die Datei dauerhaft "migrationFailed"
          // machen. `to` ist eine Ganzzahl der App, kein Nutzerwert.
          await customStatement('PRAGMA user_version = $to');
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
