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

/// Warum ein Archiv nicht eingelesen wurde. Die Fehler tragen nie Inhalte,
/// Zeilenzahlen oder das Passwort (SEC-0011, SEC-0010).
enum ArchiveImportFailure {
  /// Keine Archivdatei (Magic fehlt oder die Datei ist zu kurz dafür).
  notAnArchive,

  /// Formatversion unbekannt (auch neuere).
  unsupportedVersion,

  /// Die Parameter im Kopf weichen von denen der Formatversion ab.
  unsupportedParameters,

  /// Das erste Stück ist nicht lesbar: falsches Passwort oder beschädigter
  /// Anfang; beides ist technisch nicht unterscheidbar (ADR-0008 Punkt 5).
  wrongPasswordOrDamaged,

  /// Beschädigt: Verschlüsselung ab dem zweiten Stück, gzip, JSON, Zeilen-,
  /// Abschnitts- oder Spaltenregeln, Zähler, Endzeile oder Bytes danach.
  damaged,

  /// Das Archiv stammt aus einem neueren Datenbankschema als dieser App
  /// (Entscheidung C: ablehnen, nichts ändern).
  newerSchema,

  /// Das Archiv hat ein älteres Schema als 4; es gibt keine Migration.
  unsupportedSchema,

  /// Die Datei war nicht lesbar (Betriebssystem).
  readFailed,

  /// Das Ziel (Zwischendatenbank) hat das Archiv oder einen Schreibvorgang
  /// abgelehnt, ohne es als beschädigt zu melden (zum Beispiel Speicher voll).
  targetFailed,

  /// Vom Aufrufer abgebrochen.
  cancelled,
}

class ArchiveImportException implements Exception {
  const ArchiveImportException(this.failure);

  final ArchiveImportFailure failure;

  @override
  String toString() => 'ArchiveImportException(${failure.name})';
}

/// Warum eine Wiederherstellung aus dem Archiv nicht ausgeführt wurde
/// (außer den Fehlern des Lesens, die als [ArchiveImportException] kommen).
enum ArchiveRestoreFailure {
  /// Die App enthält Daten und das ausdrückliche Zurücksetzen fehlt.
  notEmpty,

  /// Prüfen der App oder Tausch scheiterte. Die Datenbank ist vollständig und
  /// wieder geöffnet: der alte Stand, oder (Fehler erst nach dem atomaren
  /// Umbenennen) der vollständig neue, nie ein gemischter.
  swapFailed,

  /// Der Tausch ist erfolgt (oder unklar), aber das Öffnen danach scheiterte:
  /// Der Aufrufer startet den normalen Startablauf neu.
  reopenFailed,
}

class ArchiveRestoreException implements Exception {
  const ArchiveRestoreException(this.failure);

  final ArchiveRestoreFailure failure;

  @override
  String toString() => 'ArchiveRestoreException(${failure.name})';
}
