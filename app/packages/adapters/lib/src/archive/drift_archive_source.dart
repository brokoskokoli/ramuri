import 'package:core/core.dart';
import 'package:drift/drift.dart' show Variable;

import '../storage/app_database.dart';

/// Liest die Datenbank seitenweise für den Export (`ArchiveSource`).
///
/// Liest nur die Spalten und Tabellen aus `archiveSections`; `storage_meta`
/// und `consents` kommen nicht vor. Der Stand wird in [open] festgelegt: Je
/// Tabelle mit `id` zählt nur, was dort schon vorhanden war (größte `id`).
/// Läuft während des Exports eine Aufnahme, gehören ihre späteren Zeilen nicht
/// ins Archiv und ein Lauf ohne seine Kinder bleibt nicht zurück: Kinder werden
/// nach ihrem Lauf gelesen und sind durch dieselbe Grenze eingeschlossen.
/// Gelöschte Läufe verschwinden samt Kaskade; ein Lauf kann also ohne manche
/// Kinder im Archiv stehen, nie aber ein Kind ohne Lauf.
class DriftArchiveSource implements ArchiveSource {
  DriftArchiveSource(this._db);

  final AppDatabase _db;

  @override
  Future<ArchiveSnapshot> open() async {
    final bounds = <String, int>{};
    for (final s in archiveSections) {
      if (s.isReserved || s.keyIsText) continue;
      final rows = await _db
          .customSelect('SELECT COALESCE(MAX(${s.key}), 0) AS m FROM ${s.name}')
          .get();
      bounds[s.name] = rows.single.data['m']! as int;
    }
    return _DriftSnapshot(_db, bounds);
  }
}

class _DriftSnapshot implements ArchiveSnapshot {
  _DriftSnapshot(this._db, this._bounds);

  final AppDatabase _db;
  final Map<String, int> _bounds;

  @override
  Future<List<Map<String, Object?>>> readPage(
    ArchiveSectionSpec section, {
    Object? after,
    required int limit,
  }) async {
    if (section.isReserved) return const [];
    final cols = section.columns.map((c) => c.name).join(', ');
    final key = section.key!;
    final where = <String>[];
    final args = <Variable<Object>>[];
    if (after != null) {
      where.add('$key > ?');
      args.add(
        section.keyIsText
            ? Variable.withString(after as String)
            : Variable.withInt(after as int),
      );
    }
    final bound = _bounds[section.name];
    if (bound != null) {
      where.add('$key <= ?');
      args.add(Variable.withInt(bound));
    }
    args.add(Variable.withInt(limit));
    final rows = await _db
        .customSelect(
          'SELECT $cols FROM ${section.name}'
          '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} '
          'ORDER BY $key LIMIT ?',
          variables: args,
        )
        .get();
    return [
      for (final r in rows)
        {for (final c in section.columns) c.name: r.data[c.name]},
    ];
  }
}
