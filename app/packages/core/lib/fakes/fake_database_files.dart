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

  /// Zwischendatenbank vorhanden und Aufrufe (für Tests des Startablaufs).
  bool importPresent = false;
  int deleteImportCalls = 0;
  int replaceCalls = 0;
  bool failDeleteImport = false;
  bool failReplace = false;

  @override
  Future<bool> importExists() async => importPresent;

  @override
  Future<void> deleteImport() async {
    deleteImportCalls++;
    if (failDeleteImport) throw StateError('Löschen nicht möglich');
    importPresent = false;
  }

  @override
  Future<void> replaceWithImport() async {
    replaceCalls++;
    if (failReplace) throw StateError('Tausch nicht möglich');
    present = true;
    importPresent = false;
  }
}
