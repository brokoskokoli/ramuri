import '../ports/file_handoff.dart';

/// Merkt sich übergebene Dateien und liefert [nextResult].
class FakeFileHandoff implements FileHandoff {
  /// Ergebnis der nächsten Aufrufe (Abbruch, Fehler nachstellen).
  FileHandoffResult nextResult = FileHandoffResult.completed;

  final List<ExportFile> shared = [];
  final List<ExportFile> saved = [];

  /// Antwort von [exportDirectory].
  String? directory;

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

  /// Ergebnis von [pickFile]; Vorgabe: abgebrochen.
  FilePickResult nextPick = const FilePickResult.cancelled();

  int pickCount = 0;
  int discardCount = 0;

  @override
  Future<FilePickResult> pickFile() async {
    pickCount++;
    return nextPick;
  }

  @override
  Future<void> discardPicked() async {
    discardCount++;
  }

  @override
  Future<String?> exportDirectory() async => directory;
}
