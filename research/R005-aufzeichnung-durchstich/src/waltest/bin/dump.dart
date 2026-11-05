// Oeffnet eine vom Geraet gezogene Kopie (Datei + ggf. -wal) und gibt die Zeilen als TSV aus. dump.dart <db> [--plain]
import 'package:sqlite3/sqlite3.dart';
void main(List<String> a) {
  final d = sqlite3.open(a[0]);
  if (!a.contains('--plain')) d.execute("PRAGMA key = 'r005-testschluessel-nicht-geheim'");
  print('#integrity\t${d.select('PRAGMA integrity_check').first.values.first}');
  for (final r in d.select('SELECT seq,lat,lon,tfix_ns,trecv_ns,trecv_up_ms FROM fix ORDER BY seq')) {
    print(r.values.join('\t'));
  }
  d.close();
}
