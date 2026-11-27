import 'package:core/core.dart';

/// Export des Gesamtarchivs aus Sicht der Oberfläche (FR-0192, SEC-0011):
/// schreibt das verschlüsselte Archiv in den Exportordner und liefert die
/// Datei zur Übergabe. Wirft `ArchiveExportException`.
typedef ArchiveExportRunner = Future<ExportFile> Function({
  required String password,
  ArchiveCancel? cancel,
});

/// Ziel der neuen Sitzung nach einem Import (FR-0198): übernimmt sie nach dem
/// Tausch oder startet das Öffnen neu, wenn es danach scheiterte. In der App
/// `StorageStartController`; so hängt das Archiv nicht am Speicher-Feature.
abstract interface class ArchiveSessionTarget {
  /// Übernimmt die neue Sitzung nach dem Tausch der Datenbank.
  void adoptSession(StorageSession session);

  /// Startet den normalen Ablauf neu (Tausch erfolgt, Öffnen gescheitert).
  Future<void> restart();
}

/// Reiht eine Aktion hinter Aufnahme und Neuberechnung ein (in der App
/// `RecalculationController.exclusive`).
typedef SerializeAction = Future<T> Function<T>(Future<T> Function() action);

/// Baut den Export für die geöffnete Sitzung.
typedef ArchiveExportFactory = ArchiveExportRunner Function(StorageSession s);

/// Eine Wiederherstellung aus dem Archiv (Reimport, FR-0198): ersetzt die
/// Datenbank und liefert die neue Sitzung. Wirft `ArchiveImportException` oder
/// `ArchiveRestoreException`. In der App `ArchiveRestoreService.restore`.
typedef ArchiveRestoreRunner = Future<StorageSession> Function({
  required String path,
  required String password,
  bool resetConfirmed,
  ArchiveCancel? cancel,
});

/// Baut den Wiederherstellungsdienst für die geöffnete Sitzung. [serialize]
/// schließt Aufnahme und Neuberechnung aus. Wirft
/// `ArchiveRestoreException(keyUnavailable)`, wenn der Schlüssel fehlt.
typedef ArchiveRestoreFactory = Future<ArchiveRestoreRunner> Function(
  StorageSession session,
  SerializeAction serialize,
);

/// Vorprüfung des unverschlüsselten Kopfes der gewählten Datei, bevor nach dem
/// Passwort gefragt wird (FR-0198). Wirft `ArchiveImportException`. In der App
/// `precheckArchiveFile`.
typedef ArchiveHeaderCheck = Future<void> Function(String path);

/// Prüft ein Archiv vollständig, ohne etwas zu schreiben (SEC-0009). Wirft
/// `ArchiveImportException`.
typedef ArchiveVerifier = Future<void> Function({
  required String path,
  required String password,
  ArchiveCancel? cancel,
});
