/// Port: die Dateien der Datenbank (Haupt-, `-wal`-, `-shm`- und
/// `-journal`-Datei). Nur für den Neubeginn (OQ-0062); Inhalte liest und
/// schreibt dieser Port nie.
abstract interface class DatabaseFiles {
  /// `true`, wenn mindestens eine der vier Dateien existiert.
  Future<bool> exist();

  /// Löscht alle vorhandenen Dateien. Wirft, wenn eine nicht gelöscht werden
  /// konnte (dann können Reste bleiben; der Aufrufer prüft mit [exist]).
  Future<void> deleteAll();

  // --- Wiederherstellung aus dem Archiv (WP12, docs/contracts/archive.md 4.6)

  /// `true`, wenn mindestens eine Datei der Zwischendatenbank existiert
  /// (Haupt-, `-wal`-, `-shm`-, `-journal`-Datei). [exist] meint nur die
  /// aktive Datenbank.
  Future<bool> importExists();

  /// Löscht alle Dateien der Zwischendatenbank (auch Reste nach einem Abbruch).
  /// Fehlende sind kein Fehler. Die aktive Datenbank bleibt unberührt.
  Future<void> deleteImport();

  /// Ersetzt die aktive Datenbank durch die fertige Zwischendatenbank. Beide
  /// dürfen nicht geöffnet sein. Ablauf: Nebendateien der aktiven entfernen,
  /// Nebendateien der Zwischendatenbank entfernen, dann **ein** atomares
  /// Umbenennen der Zwischen- auf die aktive Hauptdatei. Ein Abbruch an
  /// jeder Stelle lässt entweder die alte oder die vollständige neue
  /// Hauptdatei stehen, nie eine gemischte oder fehlende. Wirft bei Fehlern.
  Future<void> replaceWithImport();
}
