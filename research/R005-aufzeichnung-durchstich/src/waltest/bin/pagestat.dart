// R005: Oeffnet eine KOPIE von Hauptdatei und WAL (das Schliessen checkpointet sie, deshalb nie das Original) und gibt die B-Baum-Belegung der Tabelle fix aus: je Seite Nummer, Art und Zellen.
// pagestat.dart <db> [--plain]. Ausgabe je Zeile: page<TAB>pfad<TAB>art<TAB>zellen
import 'package:sqlite3/sqlite3.dart';
void main(List<String> a) {
  final d = sqlite3.open(a[0]);
  if (!a.contains('--plain')) d.execute("PRAGMA key = 'r005-testschluessel-nicht-geheim'");
  for (final r in d.select("SELECT pageno,path,pagetype,ncell FROM dbstat WHERE name='fix' ORDER BY path")) {
    print(r.values.join('\t'));
  }
  final mm = d.select('SELECT count(*),min(seq),max(seq) FROM fix').first.values;
  print('#rows\t${mm.join('\t')}');
  d.close();
}
