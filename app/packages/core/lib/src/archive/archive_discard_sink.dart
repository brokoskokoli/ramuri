import '../../ports/archive_sink.dart';
import 'archive_schema.dart';

/// Ziel, das alles verwirft: Der Leser prüft das ganze Archiv (Passwort,
/// Rahmen, gzip, Zeilen, Zähler, Endzeile), ohne irgendwo zu schreiben
/// (SEC-0009: erst prüfen, dann die alte Datei löschen). Hält nichts im
/// Speicher und legt keine Datei an.
class DiscardArchiveSink implements ArchiveSink {
  @override
  Future<void> begin() async {}

  @override
  Future<void> insert(
    ArchiveSectionSpec section,
    List<Map<String, Object?>> rows,
  ) async {}

  @override
  Future<void> commit() async {}

  @override
  Future<void> abort() async {}
}
