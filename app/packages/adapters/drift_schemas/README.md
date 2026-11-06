# Schema-Dumps

Ein Dump je Schema-Version (`drift_schema_vN.json`), erzeugt aus der Datenbank. Die Dumps sind die Referenz für den Test „erzeugtes Schema = Dump“ und für Migrationstests.

Bei einer Schemaänderung (Tabellen in `lib/src/storage/schema.drift`):

1. `schemaVersion` in `app_database.dart` um 1 erhöhen und den Schritt in `migrationSteps` ergänzen.
2. Aus `app/packages/adapters`: `dart run build_runner build`, dann
   `dart run drift_dev schema dump lib/src/storage/app_database.dart drift_schemas/drift_schema_vN.json` und
   `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`.
3. Generierten Code und Dump committen (das Gate führt build_runner aus, stellt die Datei danach wieder her und wird rot, wenn der erzeugte Stand vom eingecheckten abweicht oder drift_dev Warnungen oder Fehler meldet, z. B. Syntaxfehler in `schema.drift`). Alte Dumps nie ändern.
