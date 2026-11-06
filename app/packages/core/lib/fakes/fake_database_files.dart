import '../ports/database_files.dart';

/// Dateien im Arbeitsspeicher: ein einziger Zustand "vorhanden". Tests können
/// Ausfälle an bestimmten Stellen erzwingen.
class FakeDatabaseFiles implements DatabaseFiles {
  FakeDatabaseFiles({this.present = false});

  bool present;

  /// Simuliert eine Datei, die sich nicht löschen lässt.
  bool failDelete = false;

  /// Simuliert eine Dateiprüfung, die selbst scheitert.
  bool failExist = false;

  /// Aufrufe von [deleteAll].
  int deleteCalls = 0;

  @override
  Future<bool> exist() async {
    if (failExist) throw StateError('Prüfung nicht möglich');
    return present;
  }

  @override
  Future<void> deleteAll() async {
    deleteCalls++;
    if (failDelete) throw StateError('Löschen nicht möglich');
    present = false;
  }
}
