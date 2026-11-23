// Lesen und Abgleichen der PAR-Tabellen aus den Parameter-Dokumenten.
//
// Gemeinsam genutzt vom PAR-Abgleich in core
// (test/fitness/par_constants_test.dart) und im App-Paket
// (app/test/par_constants_app_test.dart). Nur Imports aus `dart:`, weder
// package:test noch package:flutter_test: Die Funktionen geben Fehlerlisten
// zurück, die Tests werten sie mit `expect` aus.

/// Zahl der Zelle, die kein Wert aus dem Code ist (Beispiel, Skala,
/// Verweis), festgehalten mit Grund in einer Zeile.
class DocOnly {
  const DocOnly(this.value, this.reason);
  final num value;
  final String reason;
}

/// Eine Zeile einer PAR-Tabelle.
class ParRow {
  ParRow(this.id, this.value, this.source);
  final String id;
  final String value;
  final String source;
  bool get annulled => value.toLowerCase().startsWith('annulliert');
}

final _idCell = RegExp(r'^PAR-\d{3}K?(?:/\d{3}K)?$');

/// Liest die PAR-Tabellen eines Dokuments: nur Tabellen mit Kopf „| ID |“,
/// Wert ist die Spalte „Startwert“ bzw. „Stand“.
List<ParRow> parseParTables(String text, String source) {
  final rows = <ParRow>[];
  List<String>? header;
  var inTable = false;
  for (final line in text.split('\n')) {
    if (!line.startsWith('|')) {
      inTable = false;
      header = null;
      continue;
    }
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (!inTable) {
      inTable = true;
      header = cells;
      continue;
    }
    final h = header!;
    if (h.length < 3 || h[1] != 'ID' || cells.length < 4) continue;
    if (!_idCell.hasMatch(cells[1])) continue;
    var col = h.indexOf('Startwert');
    if (col < 0) col = h.indexOf('Stand');
    if (col < 0 || col >= cells.length) continue;
    rows.add(ParRow(cells[1], cells[col], source));
  }
  return rows;
}

final _references = RegExp(
  r'\b\d{4}-\d{2}-\d{2}\b|\b(?:PAR|FR|NFR|OQ|DEC|SEC|ADR|SRC)-\d+K?(?:/\d+K)?|\[[A-Z]+\d+\]|\bK-?\d+\b|\bR\d+\b',
);
final _number = RegExp(
  r'([−-]?)(\d+):(\d{2})(?!\d)|([−-]?)(\d{1,3}(?:[  ]\d{3})+(?!\d)|\d+(?:,\d+)?)',
);

/// Zahlen einer Zelle: Verweise (PAR-, FR-, Quellen) und Datumsangaben
/// entfallen, Dezimalkomma wird gelesen, „m:ss“ ergibt Minuten, ein Bereich
/// „2–4“ ergibt beide Grenzen, „−2“ (Minuszeichen) ist negativ.
List<double> extractNumbers(String cell) {
  final s = cell.replaceAll(_references, ' ');
  final out = <double>[];
  for (final m in _number.allMatches(s)) {
    final before = m.start == 0 ? ' ' : s[m.start - 1];
    final signed = before == ' ' || before == '(' || before == '`';
    if (m.group(2) != null) {
      final v = int.parse(m.group(2)!) + int.parse(m.group(3)!) / 60;
      out.add(m.group(1)!.isNotEmpty && signed ? -v : v);
    } else {
      final raw = m.group(5)!.replaceAll(RegExp('[  ]'), '');
      final v = double.parse(raw.replaceAll(',', '.'));
      out.add(m.group(4)!.isNotEmpty && signed ? -v : v);
    }
  }
  return out;
}

bool _equal(double doc, num code) =>
    (doc - code).abs() <= 1e-9 * (1 + code.abs());

String _fmt(num v) {
  final d = v.toDouble();
  final r = (d * 1e9).roundToDouble() / 1e9;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

/// Abweichungen zwischen Zuordnung und Tabellen, je eine Zeile mit ID,
/// Doku-Werten und Code-Wert.
List<String> compareParValues(
  List<ParRow> rows,
  Map<String, List<Object>> code,
  Map<String, String> exceptions,
) {
  final problems = <String>[];
  final byId = <String, List<ParRow>>{};
  for (final r in rows) {
    byId.putIfAbsent(r.id, () => []).add(r);
  }
  for (final e in byId.entries) {
    final id = e.key;
    final row = e.value.first;
    if (e.value.length > 1) {
      problems.add('$id: mehrfach in den Tabellen');
    }
    final mapped = code.containsKey(id);
    final excepted = exceptions.containsKey(id);
    if (row.annulled) {
      if (mapped || excepted) problems.add('$id: annulliert, aber zugeordnet');
      continue;
    }
    if (mapped && excepted) {
      problems.add('$id: zugleich zugeordnet und Ausnahme');
    } else if (!mapped && !excepted) {
      problems.add('$id (${row.source}): weder zugeordnet noch Ausnahme');
    }
    if (!mapped) continue;
    final doc = extractNumbers(row.value);
    final rest = [...doc];
    final missing = <num>[];
    for (final entry in code[id]!) {
      final num v;
      if (entry is DocOnly) {
        v = entry.value;
        if (entry.reason.trim().isEmpty || entry.reason.contains('\n')) {
          problems.add('$id: Doku-Zahl ${_fmt(v)} ohne einzeiligen Grund');
        }
      } else {
        v = entry as num;
      }
      final i = rest.indexWhere((d) => _equal(d, v));
      if (i < 0) {
        missing.add(v);
      } else {
        rest.removeAt(i);
      }
    }
    if (missing.isNotEmpty || rest.isNotEmpty) {
      problems.add(
        '$id: Code [${missing.map(_fmt).join(', ')}] nicht in der Doku, '
        'Doku [${rest.map(_fmt).join(', ')}] nicht zugeordnet '
        '(Zelle: [${doc.map(_fmt).join(', ')}])',
      );
    }
  }
  for (final id in {...code.keys, ...exceptions.keys}) {
    if (!byId.containsKey(id)) {
      problems.add('$id: zugeordnet, aber in keinem Dokument');
    }
  }
  for (final e in exceptions.entries) {
    if (e.value.trim().isEmpty || e.value.contains('\n')) {
      problems.add('${e.key}: Ausnahme ohne einzeiligen Grund');
    }
  }
  return problems;
}

final _parLine = RegExp(r'^\|\s*(PAR-\d+[^\s|]*)\s*\|');

/// Gegenprobe zu [parseParTables]: Jede Zeile von [text], die mit „| PAR-“ und
/// einer Nummer beginnt, muss unter [rows] erfasst sein (gleiche ID, gleiche
/// Quelle). Sonst je Zeile ein Fehler mit Datei, Zeile und ID, etwa für eine
/// PAR-Tabelle mit anderem Kopf als „| ID |“.
List<String> unparsedParLines(String text, String source, List<ParRow> rows) {
  final parsed = {
    for (final r in rows)
      if (r.source == source) r.id,
  };
  final problems = <String>[];
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final m = _parLine.firstMatch(lines[i]);
    if (m == null) continue;
    final id = m.group(1)!;
    if (!parsed.contains(id)) {
      problems.add(
        '$id ($source:${i + 1}): Zeile einer PAR-Tabelle nicht erfasst',
      );
    }
  }
  return problems;
}

/// Grund, mit dem core eine ID bzw. eine Doku-Zahl führt, die der Abgleich im
/// App-Paket prüft.
const parCheckedInApp = 'geprüft in app/test/par_constants_app_test.dart';

/// Abgleich der Zuständigkeit zwischen App-Test und core-Test.
///
/// [app] ist die Zuordnung des App-Tests. Jede ID darin muss in core
/// entweder als Ausnahme mit dem Grund [parCheckedInApp] stehen
/// ([coreExceptions]) oder, wenn core den Rest der Zelle selbst prüft, die
/// Code-Werte des App-Tests als [DocOnly] mit diesem Grund führen
/// ([coreValues]). Umgekehrt muss jede Ausnahme bzw. Doku-Zahl mit diesem
/// Grund im App-Test zugeordnet sein. So prüft keine ID zweimal und keine
/// fällt heraus.
List<String> compareAppCoverage(
  Map<String, List<Object>> app,
  Map<String, String> coreExceptions,
  Map<String, List<Object>> coreValues,
) {
  final problems = <String>[];
  List<num> fromApp(String id) => [
    for (final e in app[id] ?? const <Object>[])
      if (e is! DocOnly) e as num,
  ];
  List<num> deferred(String id) => [
    for (final e in coreValues[id] ?? const <Object>[])
      if (e is DocOnly && e.reason == parCheckedInApp) e.value,
  ];
  bool sameValues(List<num> a, List<num> b) {
    final rest = [...b];
    for (final v in a) {
      final i = rest.indexWhere((d) => _equal(d.toDouble(), v));
      if (i < 0) return false;
      rest.removeAt(i);
    }
    return rest.isEmpty;
  }

  for (final id in app.keys) {
    if (coreExceptions[id] == parCheckedInApp) continue;
    final codeHere = fromApp(id);
    final codeThere = deferred(id);
    if (codeThere.isNotEmpty && sameValues(codeHere, codeThere)) continue;
    problems.add(
      '$id: im App-Test geprüft, in core aber nicht als Ausnahme '
      '„$parCheckedInApp“ (Code-Werte hier [${codeHere.map(_fmt).join(', ')}], '
      'in core als Doku-Zahl mit Verweis [${codeThere.map(_fmt).join(', ')}])',
    );
  }
  for (final e in coreExceptions.entries) {
    if (e.value == parCheckedInApp && !app.containsKey(e.key)) {
      problems.add(
        '${e.key}: in core als „$parCheckedInApp“, im App-Test nicht zugeordnet',
      );
    }
  }
  for (final id in coreValues.keys) {
    if (deferred(id).isNotEmpty && !app.containsKey(id)) {
      problems.add(
        '$id: in core Doku-Zahl mit „$parCheckedInApp“, im App-Test nicht '
        'zugeordnet',
      );
    }
  }
  return problems;
}
