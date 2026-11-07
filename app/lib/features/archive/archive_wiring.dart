import 'package:core/core.dart';

/// Export des Gesamtarchivs aus Sicht der Oberfläche (FR-0192, SEC-0011):
/// schreibt das verschlüsselte Archiv in den Exportordner und liefert die
/// Datei zur Übergabe. Wirft `ArchiveExportException`.
typedef ArchiveExportRunner = Future<ExportFile> Function({
  required String password,
  ArchiveCancel? cancel,
});

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

/// Prüft ein Archiv vollständig, ohne etwas zu schreiben (SEC-0009). Wirft
/// `ArchiveImportException`.
typedef ArchiveVerifier = Future<void> Function({
  required String path,
  required String password,
  ArchiveCancel? cancel,
});
