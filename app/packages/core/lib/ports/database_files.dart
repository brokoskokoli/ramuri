/// Port: die Dateien der Datenbank (Haupt-, `-wal`-, `-shm`- und
/// `-journal`-Datei). Nur für den Neubeginn (OQ-0062); Inhalte liest und
/// schreibt dieser Port nie.
abstract interface class DatabaseFiles {
  /// `true`, wenn mindestens eine der vier Dateien existiert.
  Future<bool> exist();

  /// Löscht alle vorhandenen Dateien. Wirft, wenn eine nicht gelöscht werden
  /// konnte (dann können Reste bleiben; der Aufrufer prüft mit [exist]).
  Future<void> deleteAll();
}
