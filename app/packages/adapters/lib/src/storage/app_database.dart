import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Meta-Tabelle der ersten Version. Die Tabellen von Phase 1 kommen mit Teil B.
class StorageMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [StorageMeta])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
