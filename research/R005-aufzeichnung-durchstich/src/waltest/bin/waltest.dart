// R005: Verschluesseltes WAL mit sqlite3mc am Rechner (gleiche Paketversion wie im Prototyp).
// Aufruf: dart run bin/waltest.dart <leerer-ordner>
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';

const marker = 'R005KLARTEXTMARKER';
const knownDouble = 48.1234567890123; // bekannter Messwert, als 8-Byte-IEEE im Datensatz
const key = 'r005-testschluessel-nicht-geheim';

int count(List<int> hay, List<int> needle) {
  var n = 0;
  outer:
  for (var i = 0; i + needle.length <= hay.length; i++) {
    for (var j = 0; j < needle.length; j++) { if (hay[i + j] != needle[j]) continue outer; }
    n++;
  }
  return n;
}
List<int> be(double d) => (ByteData(8)..setFloat64(0, d, Endian.big)).buffer.asUint8List();

Map<String, Object> scan(String path) {
  final f = File(path);
  if (!f.existsSync()) return {'size': -1};
  final b = f.readAsBytesSync();
  // Byteverteilung ohne WAL-Header (32) als grober Entropie-Hinweis: chi^2 gegen Gleichverteilung
  final h = List<int>.filled(256, 0);
  // Bei WAL nur die Seiteninhalte zaehlen; WAL-Header (32) und Frame-Header (24) sind auch verschluesselt Klartext-Struktur.
  final isWal = path.endsWith('-wal') && b.length > 32;
  var pages = 0;
  if (isWal) {
    for (var o = 32; o + 24 + 4096 <= b.length; o += 24 + 4096) { pages++; for (var i = o + 24; i < o + 24 + 4096; i++) h[b[i]]++; }
  } else { for (final x in b) h[x]++; }
  final e = (isWal ? pages * 4096 : b.length) / 256;
  var chi = 0.0;
  for (final c in h) chi += (c - e) * (c - e) / (e == 0 ? 1 : e);
  return {
    'size': b.length,
    if (isWal) 'frames': pages,
    'marker': count(b, marker.codeUnits),
    'double_be': count(b, be(knownDouble)),
    'sqliteHeader': count(b, 'SQLite format 3'.codeUnits),
    'tableName': count(b, 'messwert'.codeUnits),
    'chi2_255df': chi.round(),
  };
}

void setup(Database db, {required bool enc, String sync = 'FULL'}) {
  if (enc) db.execute("PRAGMA key = '$key'");
  final jm = db.select('PRAGMA journal_mode = WAL').first.values.first;
  db.execute('PRAGMA synchronous = $sync');
  db.execute('PRAGMA secure_delete = ON');
  db.execute('PRAGMA wal_autocheckpoint = 0');
  print('  journal_mode=$jm synchronous=${db.select('PRAGMA synchronous').first.values.first} '
      'secure_delete=${db.select('PRAGMA secure_delete').first.values.first}');
}

void fill(Database db, int n) {
  db.execute('CREATE TABLE IF NOT EXISTS messwert(seq INTEGER PRIMARY KEY, lat REAL, note TEXT)');
  final st = db.prepare('INSERT INTO messwert VALUES(?,?,?)');
  for (var i = 0; i < n; i++) {
    db.execute('BEGIN');
    st.execute([i, knownDouble, '$marker-$i']);
    db.execute('COMMIT');
  }
  st.close();
}

void copyTo(String db, String dst) {
  Directory(dst).createSync(recursive: true);
  for (final s in ['', '-wal', '-shm']) {
    if (File('$db$s').existsSync()) File('$db$s').copySync('$dst/x.db$s');
  }
}

String tryOpen(String path, String? k) {
  try {
    final d = sqlite3.open(path);
    if (k != null) d.execute("PRAGMA key = '$k'");
    final r = d.select('SELECT count(*), max(seq) FROM messwert').first.values;
    d.close();
    return 'OK rows=${r[0]} max=${r[1]}';
  } catch (e) {
    return 'FEHLER ${e.toString().split('\n').first}';
  }
}

void main(List<String> a) {
  final dir = a.first;
  Directory(dir).createSync(recursive: true);
  final n = 2000;
  print('== Version');
  {
    final d = sqlite3.openInMemory();
    print('  sqlite=${sqlite3.version.libVersion}');
    print('  sqlite3mc=${d.select('SELECT sqlite3mc_version()').first.values.first}');
    final opts = d.select('PRAGMA compile_options').map((r) => r.values.first as String).toList();
    print('  compile_options(auswahl)=${opts.where((o) => RegExp('TEMP_STORE|SECURE_DELETE|THREADSAFE|CIPHER|CODEC|MC_').hasMatch(o)).toList()}');
    d.close();
  }
  for (final enc in [false, true]) {
    final tag = enc ? 'verschluesselt' : 'KLARTEXT (Positivkontrolle)';
    print('== $tag, $n Transaktionen, kein Checkpoint');
    final p = '$dir/${enc ? 'enc' : 'plain'}.db';
    final db = sqlite3.open(p);
    setup(db, enc: enc);
    if (enc) print('  cipher=${db.select('PRAGMA cipher').first.values.first}');
    fill(db, n);
    final cp = '$dir/${enc ? 'enc' : 'plain'}-copy-vor-checkpoint';
    copyTo(p, cp);
    print('  Kopie db : ${scan('$cp/x.db')}');
    print('  Kopie wal: ${scan('$cp/x.db-wal')}');
    if (enc) {
      // Jede Oeffnung auf frischer Kopie: Schliessen der letzten Verbindung checkpointet und loescht das WAL.
      String on(String tag, String? k, {bool wal = true}) {
        final t = '$dir/open-$tag'; Directory(t).createSync();
        File('$cp/x.db').copySync('$t/x.db');
        if (wal) File('$cp/x.db-wal').copySync('$t/x.db-wal');
        return tryOpen('$t/x.db', k);
      }
      print('  Kopie mit Schluessel      : ${on('ok', key)}');
      print('  Kopie falscher Schluessel : ${on('falsch', 'falsch')}');
      print('  Kopie ohne Schluessel     : ${on('ohne', null)}');
      // Nur die Hauptdatei, WAL weggelassen: belegt, dass die Zeilen wirklich im WAL lagen
      print('  Hauptdatei ohne WAL       : ${on('nurdb', key, wal: false)}');
    } else {
      final only = '$dir/plain-only-db'; Directory(only).createSync(); File('$cp/x.db').copySync('$only/x.db');
      print('  Hauptdatei ohne WAL       : ${tryOpen('$only/x.db', null)}');
    }
    db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    print('  nach Checkpoint db : ${scan(p)}');
    print('  nach Checkpoint wal: ${scan('$p-wal')}');
    db.close();
  }
  // Schluesselwechsel (FAQ/Pragma-Doku: ab 2.4.0 in WAL erlaubt, Salt bleibt)
  print('== Schluesselwechsel im WAL-Modus mit ungecheckpointeten Daten');
  {
    final p = '$dir/rekey.db';
    final db = sqlite3.open(p);
    setup(db, enc: true);
    fill(db, 500);
    final before = File('$p-wal').lengthSync();
    final s1 = File(p).readAsBytesSync().sublist(0, 16);
    try {
      db.execute("PRAGMA rekey = 'neuer-schluessel'");
      print('  rekey ohne Fehler; wal vorher=$before nachher=${File('$p-wal').existsSync() ? File('$p-wal').lengthSync() : -1} '
          'journal=${db.select('PRAGMA journal_mode').first.values.first}');
    } catch (e) { print('  rekey FEHLER $e'); }
    db.execute("INSERT INTO messwert VALUES(100000, 1.0, '$marker-nach-rekey')");
    final s2 = File(p).readAsBytesSync().sublist(0, 16);
    print('  Salt (erste 16 Byte der Datei) gleich: ${_eq(s1, s2)}');
    final cp = '$dir/rekey-copy'; copyTo(p, cp);
    print('  Kopie wal: ${scan('$cp/x.db-wal')}');
    print('  Kopie neuer Schluessel: ${tryOpen('$cp/x.db', 'neuer-schluessel')}');
    print('  Kopie alter Schluessel: ${tryOpen('$cp/x.db', key)}');
    db.close();
    print('  nach close, neuer Schluessel: ${tryOpen(p, 'neuer-schluessel')}');
    print('  nach close, alter Schluessel: ${tryOpen(p, key)}');
  }
  // FAQ-Fall: Seitengroesse aendern, "must not be in WAL journal mode"
  print('== FAQ-Fall Seitengroesse im WAL-Modus');
  {
    final p = '$dir/pagesize.db';
    final db = sqlite3.open(p, uri: true);
    setup(db, enc: true);
    fill(db, 200);
    final ps = () => db.select('PRAGMA page_size').first.values.first;
    print('  page_size vorher=${ps()}');
    try { db.execute('PRAGMA page_size = 8192'); db.execute('VACUUM'); print('  VACUUM mit 8192 in WAL: kein Fehler, page_size=${ps()}'); }
    catch (e) { print('  VACUUM FEHLER ${e.toString().split('\n').first}'); }
    print('  Inhalt danach: ${db.select('SELECT count(*) FROM messwert').first.values.first} Zeilen, integrity=${db.select('PRAGMA integrity_check').first.values.first}');
    try { db.execute("VACUUM INTO 'file:$dir/pagesize-into.db?cipher=chacha20&key=$key'"); print('  VACUUM INTO: ${tryOpen('$dir/pagesize-into.db', key)} scan=${scan('$dir/pagesize-into.db')}'); }
    catch (e) { print('  VACUUM INTO FEHLER ${e.toString().split('\n').first}'); }
    void faq(String mode) {
      try {
        db.execute("PRAGMA rekey = ''");
        db.execute('PRAGMA page_size = 8192');
        db.execute('VACUUM');
        db.execute("PRAGMA rekey = '$key'");
        print('  FAQ-Prozedur in $mode: kein Fehler, page_size=${ps()} journal=${db.select('PRAGMA journal_mode').first.values.first} integrity=${db.select('PRAGMA integrity_check').first.values.first}');
      } catch (e) { print('  FAQ-Prozedur in $mode: FEHLER ${e.toString().split('\n').first}'); }
    }
    faq('WAL');
    db.close();
    print('  nach close mit Schluessel: ${tryOpen(p, key)}');
    print('  nach close ohne Schluessel: ${tryOpen(p, null)}');
    print('  Datei nach Fehlschlag: ${scan(p)}');
    final q = '$dir/pagesize2.db';
    final d2 = sqlite3.open(q);
    d2.execute("PRAGMA key = '$key'");
    d2.execute('PRAGMA journal_mode = DELETE');
    fill(d2, 200);
    final ps2 = () => d2.select('PRAGMA page_size').first.values.first;
    try {
      d2.execute("PRAGMA rekey = ''"); d2.execute('PRAGMA page_size = 8192'); d2.execute('VACUUM'); d2.execute("PRAGMA rekey = '$key'");
      print('  FAQ-Prozedur in DELETE: page_size=${ps2()} integrity=${d2.select('PRAGMA integrity_check').first.values.first}');
    } catch (e) { print('  FAQ-Prozedur in DELETE: FEHLER ${e.toString().split('\n').first}'); }
    d2.close();
    print('  nach close: ${tryOpen(q, key)}');
  }
  // Manipulation im WAL: Authentifizierung je Seite
  print('== Manipulation eines WAL-Frames');
  {
    final src = '$dir/enc-copy-vor-checkpoint';
    print('  Frames im WAL: ${(File('$src/x.db-wal').lengthSync() - 32) ~/ (24 + 4096)}');
    final t = '$dir/tamper'; Directory(t).createSync();
    File('$src/x.db').copySync('$t/x.db');
    final w = File('$src/x.db-wal').readAsBytesSync();
    // Byte in der Seite des ersten Frames (32 Header + 24 Frame-Header + 100). SQLite-Pruefsumme geht ueber die verschluesselten Bytes.
    w[32 + 24 + 100] ^= 0xFF;
    File('$t/x.db-wal').writeAsBytesSync(w);
    print('  gekippt im ersten Frame (SQLite-Pruefsumme verwirft ab dort): ${tryOpen('$t/x.db', key)}');
    // Inhalt UND SQLite-Pruefsumme stimmen nicht ueberein kann nur ein Angreifer mit Pruefsummenrechnung umgehen; das zeigt der Test nicht.
  }
}
bool _eq(List<int> a, List<int> b) { for (var i = 0; i < a.length; i++) { if (a[i] != b[i]) return false; } return true; }
