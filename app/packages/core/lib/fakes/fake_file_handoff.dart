import '../ports/file_handoff.dart';

/// Merkt sich übergebene Dateien und liefert [nextResult].
class FakeFileHandoff implements FileHandoff {
  /// Ergebnis der nächsten Aufrufe (Abbruch, Fehler nachstellen).
  FileHandoffResult nextResult = FileHandoffResult.completed;

  final List<ExportFile> shared = [];
  final List<ExportFile> saved = [];

  @override
  Future<FileHandoffResult> share(ExportFile file) async {
    shared.add(file);
    return nextResult;
  }

  @override
  Future<FileHandoffResult> save(ExportFile file) async {
    saved.add(file);
    return nextResult;
  }
}
