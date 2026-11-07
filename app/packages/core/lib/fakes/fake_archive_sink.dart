import '../ports/archive_sink.dart';
import '../src/archive/archive_schema.dart';

/// Ziel für Archivtests: merkt sich Aufrufe und Zeilen im Speicher.
class FakeArchiveSink implements ArchiveSink {
  /// Aufrufe in Reihenfolge: `begin`, `insert:<abschnitt>`, `commit`, `abort`.
  final List<String> calls = [];

  /// Eingefügte Zeilen je Abschnitt in Eingangsreihenfolge.
  final Map<String, List<Map<String, Object?>>> rows = {};

  /// Größen der Stapel je `insert`.
  final List<int> batchSizes = [];

  /// Wirft beim [failAtInsert]-ten `insert` (1-basiert) / bei `commit`.
  int? failAtInsert;
  bool failCommit = false;
  Object failWith = StateError('Ziel gescheitert (Test)');

  /// Wird nach jedem erfolgreichen `insert` mit dem Abschnittsnamen gerufen.
  void Function(String section)? onInsert;

  int _inserts = 0;

  int get commits => calls.where((c) => c == 'commit').length;
  int get aborts => calls.where((c) => c == 'abort').length;

  @override
  Future<void> begin() async => calls.add('begin');

  @override
  Future<void> insert(
    ArchiveSectionSpec section,
    List<Map<String, Object?>> batch,
  ) async {
    calls.add('insert:${section.name}');
    if (++_inserts == failAtInsert) throw failWith;
    batchSizes.add(batch.length);
    (rows[section.name] ??= []).addAll(batch);
    onInsert?.call(section.name);
  }

  @override
  Future<void> commit() async {
    calls.add('commit');
    if (failCommit) throw failWith;
  }

  @override
  Future<void> abort() async => calls.add('abort');
}
