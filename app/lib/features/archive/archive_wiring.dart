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

/// Baut den Wiederherstellungsdienst für die geöffnete Sitzung (Reimport,
/// folgt in der Oberfläche mit D2). [serialize] schließt Aufnahme und
/// Neuberechnung aus.
typedef ArchiveRestoreFactory = Future<ArchiveRestoreService> Function(
  StorageSession session,
  SerializeAction serialize,
);
