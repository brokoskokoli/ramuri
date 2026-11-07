import '../ports/archive_source.dart';
import '../src/archive/archive_schema.dart';

/// Datenbank im Speicher für Archivtests. [rows] je Abschnittsname, Zeilen
/// werden beim Lesen nach dem Schlüssel sortiert und seitenweise geliefert.
class FakeArchiveSource implements ArchiveSource {
  FakeArchiveSource(this.rows);

  final Map<String, List<Map<String, Object?>>> rows;

  /// Wirft beim [failAtRead]-ten Aufruf von `readPage` (1-basiert), wenn gesetzt.
  int? failAtRead;

  /// Größen der gelieferten Seiten (Prüfung: seitenweise).
  final List<int> pageSizes = [];

  int _reads = 0;

  @override
  Future<ArchiveSnapshot> open() async => _Snapshot(this);
}

class _Snapshot implements ArchiveSnapshot {
  _Snapshot(this._s);
  final FakeArchiveSource _s;

  @override
  Future<List<Map<String, Object?>>> readPage(
    ArchiveSectionSpec section, {
    Object? after,
    required int limit,
  }) async {
    if (++_s._reads == _s.failAtRead) throw StateError('Lesefehler (Test)');
    final key = section.key!;
    final all = [...?_s.rows[section.name]]
      ..sort(
        (a, b) =>
            Comparable.compare(a[key]! as Comparable, b[key]! as Comparable),
      );
    final page = [
      for (final r in all)
        if (after == null ||
            Comparable.compare(r[key]! as Comparable, after as Comparable) > 0)
          r,
    ].take(limit).toList();
    _s.pageSizes.add(page.length);
    return page;
  }
}
