/// Warum ein Export scheitert. Die Fehler tragen nie Inhalte oder das Passwort.
enum ArchiveExportFailure {
  /// Passwort zu kurz (15 Zeichen).
  passwordRejected,

  /// Kein Exportordner oder unbrauchbarer Name/Pfad.
  noExportDirectory,

  /// Lesen aus der Datenbank gescheitert.
  readFailed,

  /// Ein Wert passt nicht zum Schema (Typ, NULL, nicht endlich, Unicode).
  invalidData,

  /// Verschlüsseln gescheitert.
  encryptFailed,

  /// Schreiben oder Umbenennen gescheitert.
  writeFailed,

  /// Vom Aufrufer abgebrochen.
  cancelled,
}

class ArchiveExportException implements Exception {
  const ArchiveExportException(this.failure);

  final ArchiveExportFailure failure;

  @override
  String toString() => 'ArchiveExportException(${failure.name})';
}
