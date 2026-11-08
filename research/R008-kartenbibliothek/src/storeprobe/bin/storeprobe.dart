// R008 (Review Runde 2, M2): Host-Probe des empfohlenen Kachel- und Miniaturspeichers: eigene sqlite3mc-Datei.
// Kein Netz, kein Emulator; Inhalte aus den Testvorlagen, Eintragsgroessen wie im Emulator-Abzug (42 Dateien) und im Nachlauf.
// Misst: Oeffnen, Schreiben, Lesen (bis 430 875 Byte), Dateigroesse, Verdraengung, Klartext-Scan mit Gegenprobe ohne Schluessel,
// was Dateisystem-Beobachter sehen (WAL-Rahmenkoepfe, Journal, Seitenvergleich zweier Abzuege). Vergleich: Prueffeld AES-GCM je Datei.
// Aufruf: dart run bin/storeprobe.dart <fixtures-ordner> <leerer-arbeitsordner>
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

const key = 'r008-testschluessel-nicht-geheim';
// Klartextgroessen der 42 Dateien aus emu-20261108-003341/files-fmvt-consent (src/foreign_tiles.py), ohne die Kiew-Kacheln
// waeren es 30; die Probe braucht nur die Verteilung.
const sizes = [
  87767, 177109, 86064, 19254, 27822, 118872, 43311, 81170, 79907, 132406, 34787, 76580, //
  228261, 168441, 222385, 136101, 126182, 116499, 126191, 93287, 75469, 120098, 94500, 60822, //
  340726, 123746, 164280, 430875, 225741, 151506, //
  31520, 41125, 88478, 92047, 28111, 43256, 85319, 102869, 22486, 31574, 51197, 69802
];
const thumbSize = 48500; // Median Nachlauf
const pageSize = 4096;

late Uint8List pool;
Uint8List payload(int n, int seed) {
  final o = seed * 7919 % pool.length;
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) b[i] = pool[(o + i) % pool.length];
  return b;
}

Database open(String path, {String mode = 'DELETE', bool enc = true}) {
  final db = sqlite3.open(path);
  if (enc) db.execute("PRAGMA key = '$key'");
  db.execute('PRAGMA auto_vacuum = INCREMENTAL');
  db.select('PRAGMA journal_mode = $mode');
  db.execute('PRAGMA synchronous = NORMAL');
  db.execute('PRAGMA secure_delete = ON');
  db.execute('CREATE TABLE IF NOT EXISTS entry(kind INTEGER NOT NULL, k TEXT NOT NULL, data BLOB NOT NULL, size INTEGER NOT NULL, '
      'last INTEGER NOT NULL, PRIMARY KEY(kind, k)) WITHOUT ROWID');
  db.execute('CREATE INDEX IF NOT EXISTS entry_last ON entry(kind, last)');
  return db;
}

int clock = 0;
void put(Database db, int kind, String k, Uint8List v) =>
    db.execute('INSERT OR REPLACE INTO entry VALUES(?,?,?,?,?)', [kind, k, v, v.length, ++clock]);

int evict(Database db, int kind, int limit) {
  var total = db.select('SELECT COALESCE(SUM(size),0) s FROM entry WHERE kind=?', [kind]).first['s'] as int;
  if (total <= limit) return 0;
  var removed = 0;
  db.execute('BEGIN');
  for (final r in db.select('SELECT k, size FROM entry WHERE kind=? ORDER BY last', [kind])) {
    if (total <= limit) break;
    db.execute('DELETE FROM entry WHERE kind=? AND k=?', [kind, r['k']]);
    total -= r['size'] as int;
    removed++;
  }
  db.execute('COMMIT');
  db.select('PRAGMA incremental_vacuum');
  return removed;
}

double med(List<num> v) {
  final s = [...v]..sort();
  return s[s.length ~/ 2].toDouble();
}

double us(void Function() f) {
  final t = Stopwatch()..start();
  f();
  return t.elapsedMicroseconds / 1000;
}

final sigs = <String, List<int>>{
  'pbf:transportation': utf8.encode('transportation'),
  'pbf:landcover': utf8.encode('landcover'),
  'png': [0x89, 0x50, 0x4E, 0x47],
  'sqlite': utf8.encode('SQLite format 3'),
  'json:openmaptiles': utf8.encode('openmaptiles'),
};
List<String> scan(List<int> b) {
  final h = <String>[];
  sigs.forEach((n, s) {
    outer:
    for (var i = 0; i + s.length <= b.length; i++) {
      for (var j = 0; j < s.length; j++) {
        if (b[i + j] != s[j]) continue outer;
      }
      h.add(n);
      break;
    }
  });
  return h;
}

/// WAL: je Commit die Zahl der Rahmen und die Seitennummern, nur aus den Klartext-Koepfen.
List<int> walCommits(String path) {
  final b = File(path).readAsBytesSync();
  if (b.length < 32) return [];
  final d = ByteData.sublistView(b);
  final page = d.getUint32(8);
  final out = <int>[];
  var n = 0;
  for (var i = 32; i + 24 + page <= b.length; i += 24 + page) {
    n++;
    if (d.getUint32(i + 4) != 0) {
      out.add(n);
      n = 0;
    }
  }
  return out;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int changedPages(Uint8List a, Uint8List b) {
  var c = 0;
  final n = max(a.length, b.length) ~/ pageSize;
  for (var p = 0; p < n; p++) {
    final s = p * pageSize;
    if (s + pageSize > a.length || s + pageSize > b.length) {
      c++;
      continue;
    }
    for (var i = s; i < s + pageSize; i++) {
      if (a[i] != b[i]) {
        c++;
        break;
      }
    }
  }
  return c;
}

void main(List<String> argv) async {
  final fix = argv[0], work = argv[1];
  final bb = BytesBuilder();
  for (final f in Directory('$fix/tiles').listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path))) {
    bb.add(f.readAsBytesSync());
  }
  bb.add(File('$fix/sprite@2x.png').readAsBytesSync());
  bb.add(File('$fix/liberty.json').readAsBytesSync());
  pool = bb.toBytes();
  Directory(work).createSync(recursive: true);
  final res = <String, Object>{};

  // --- Version und Laufzeitpruefung
  final v0 = sqlite3.open('$work/ver.db');
  v0.execute("PRAGMA key = '$key'");
  res['sqlite'] = v0.select('SELECT sqlite_version() v').first['v'] as String;
  res['cipher'] = v0.select('PRAGMA cipher').first.values.first.toString();
  v0.close();

  // --- A: Empfehlung (DELETE-Journal), 42 Kacheln + 50 Miniaturen
  final a = '$work/a.db';
  var db = open(a);
  final wr = <double>[];
  for (var i = 0; i < sizes.length; i++) {
    final v = payload(sizes[i], i);
    wr.add(us(() => put(db, 0, 'k$i', v)));
  }
  final plainTiles = sizes.reduce((x, y) => x + y);
  final sizeAfterTiles = File(a).lengthSync();
  for (var i = 0; i < 50; i++) {
    final v = payload(thumbSize, 1000 + i);
    put(db, 1, 't$i', v);
  }
  db.close();
  final fileA = File(a).lengthSync();
  res['A'] = {
    'tiles': sizes.length, 'tiles_bytes': plainTiles, 'file_after_tiles': sizeAfterTiles,
    'overhead_tiles_pct': ((sizeAfterTiles / plainTiles - 1) * 100).toStringAsFixed(1),
    'thumbs': 50, 'file_total': fileA, 'write_ms_median': med(wr), 'write_ms_max': wr.reduce(max),
    'scan': scan(File(a).readAsBytesSync()),
    'other_files': Directory(work).listSync().where((f) => f.path.contains('a.db-')).map((f) => f.path).toList(),
  };

  // Oeffnen (inkl. Schluesselableitung)
  final op = <double>[];
  for (var i = 0; i < 5; i++) {
    op.add(us(() {
      final d = sqlite3.open(a);
      d.execute("PRAGMA key = '$key'");
      d.select('SELECT count(*) FROM entry');
      d.close();
    }));
  }
  res['open_ms_median'] = med(op);

  // Lesen je Groesse. warm: Seiten im Cache der Verbindung (kein Entschluesseln, nur Kopieren). kalt: Cache vorher geleert
  // (PRAGMA shrink_memory), jede Seite wird wieder entschluesselt; der Dateicache des Systems bleibt warm.
  // Massgeblich ist kalt; die erste Fassung der Probe mass nur warm und zeigte 0,13 ms fuer 431 kB (Kopieren, nicht Entschluesseln).
  db = open(a);
  final st = db.prepare('SELECT data FROM entry WHERE kind=0 AND k=?');
  final rd = <String, Object>{};
  for (final (i, label) in [(34, '28 kB'), (15, '136 kB'), (28, '226 kB'), (24, '341 kB'), (27, '431 kB')]) {
    final w = <double>[], t = <double>[], u = <double>[];
    for (var r = 0; r < 25; r++) {
      w.add(us(() => st.select(['k$i']).first['data']));
      db.select('PRAGMA shrink_memory');
      t.add(us(() => st.select(['k$i']).first['data']));
      db.select('PRAGMA shrink_memory');
      u.add(us(() {
        st.select(['k$i']).first['data'];
        db.execute('UPDATE entry SET last=? WHERE kind=0 AND k=?', [++clock, 'k$i']);
      }));
    }
    final got = st.select(['k$i']).first['data'] as List<int>;
    rd['${sizes[i]} ($label)'] = {'warm_ms_median': med(w), 'cold_ms_median': med(t), 'cold_ms_max': t.reduce(max), 'cold_plus_update_ms_median': med(u), 'content_ok': got.length == sizes[i] && _same(got, payload(sizes[i], i))};
  }
  st.close();
  res['read'] = rd;
  db.close();

  // Falscher Schluessel darf nichts lesen
  final bad = sqlite3.open(a);
  bad.execute("PRAGMA key = 'falsch'");
  var badOk = false;
  try {
    bad.select('SELECT count(*) FROM entry');
    badOk = true;
  } catch (_) {}
  bad.close();
  res['wrong_key_reads'] = badOk;

  // Gleicher Schluessel, zwei Dateien: Kopf (Salz) verschieden?
  final b2 = open('$work/a2.db');
  b2.close();
  final s1 = File(a).openSync()..setPositionSync(0);
  final s2 = File('$work/a2.db').openSync();
  res['salt_differs'] = s1.readSync(16).toString() != s2.readSync(16).toString();
  s1.closeSync();
  s2.closeSync();

  // --- Gegenprobe ohne Schluessel: Scan muss anschlagen
  final c = '$work/plain.db';
  final dp = open(c, enc: false);
  for (var i = 0; i < 5; i++) put(dp, 0, 'k$i', payload(sizes[i + 24], i + 24));
  put(dp, 1, 't', Uint8List.fromList(File('$fix/sprite.png').readAsBytesSync()));
  dp.close();
  res['control_plain_scan'] = scan(File(c).readAsBytesSync());

  // --- Verdraengung: Grenzen Kacheln 5 MB, Miniaturen 1 MB; 300 Kacheln, 60 Miniaturen
  final e = '$work/evict.db';
  db = open(e);
  const limT = 5 * 1000 * 1000, limM = 1000 * 1000;
  final ev = <double>[];
  var removed = 0, maxFile = 0;
  for (var i = 0; i < 360; i++) {
    final thumb = i % 6 == 5;
    final kind = thumb ? 1 : 0;
    final n = thumb ? thumbSize : sizes[i % sizes.length];
    put(db, kind, thumb ? 'tn$i' : 'k$i', payload(n, i));
    ev.add(us(() => removed += evict(db, kind, thumb ? limM : limT)));
    maxFile = max(maxFile, File(e).lengthSync());
  }
  // LRU: den aeltesten Eintrag beruehren, weiter schreiben: er muss bleiben, der danach aelteste muss gehen.
  final old2 = db.select('SELECT k FROM entry WHERE kind=0 ORDER BY last LIMIT 2');
  db.execute('UPDATE entry SET last=? WHERE kind=0 AND k=?', [++clock, old2[0]['k']]);
  put(db, 0, 'lru-neu', payload(300000, 77));
  evict(db, 0, limT);
  final lruKept = db.select('SELECT 1 FROM entry WHERE kind=0 AND k=?', [old2[0]['k']]).isNotEmpty;
  final lruGone = db.select('SELECT 1 FROM entry WHERE kind=0 AND k=?', [old2[1]['k']]).isEmpty;
  final rows = db.select('SELECT kind, count(*) n, SUM(size) s FROM entry GROUP BY kind');
  final free = db.select('PRAGMA freelist_count').first.values.first;
  db.select('PRAGMA incremental_vacuum');
  final newestOk = db.select("SELECT size FROM entry WHERE kind=0 AND k='lru-neu'").isNotEmpty;
  final oldestGone = db.select("SELECT size FROM entry WHERE kind=0 AND k='k0'").isEmpty;
  db.close();
  res['evict'] = {
    'limit_tiles': limT, 'limit_thumbs': limM,
    'rows': [for (final r in rows) {'kind': r['kind'], 'n': r['n'], 'bytes': r['s']}],
    'removed': removed, 'file_max': maxFile, 'file_end': File(e).lengthSync(), 'freelist': free,
    'evict_ms_median': med(ev), 'evict_ms_max': ev.reduce(max), 'newest_present': newestOk, 'oldest_gone': oldestGone, 'lru_touched_kept': lruKept, 'lru_next_oldest_gone': lruGone,
  };

  // --- Was ein Beobachter des Dateisystems sieht
  // 1) Ein Abzug: nur Gesamtgroesse. Zwei Abzuege: geaenderte Seiten je Eintrag.
  final s = '$work/snap.db';
  db = open(s);
  for (var i = 0; i < 20; i++) put(db, 0, 'k$i', payload(sizes[i], i));
  final snap = <Map<String, Object>>[];
  for (final n in [28111, 88478, 225741, 430875]) {
    final before = File(s).readAsBytesSync();
    put(db, 0, 'neu$n', payload(n, n));
    final after = File(s).readAsBytesSync();
    snap.add({'entry': n, 'entry_pages': (n / (pageSize - 32)).ceil(), 'changed_pages': changedPages(before, after), 'file_growth': after.length - before.length});
  }
  res['two_snapshots'] = snap;

  // 2) Journal waehrend einer offenen Transaktion (DELETE)
  db.execute('BEGIN');
  put(db, 0, 'j', payload(225741, 5));
  final jIns = File('$s-journal');
  final jInsSize = jIns.existsSync() ? jIns.lengthSync() : -1;
  final jScan = jIns.existsSync() ? scan(jIns.readAsBytesSync()) : <String>[];
  db.execute('COMMIT');
  final jAfter = jIns.existsSync();
  db.execute('BEGIN');
  db.execute("DELETE FROM entry WHERE kind=0 AND k='neu430875'");
  db.select('SELECT 1');
  final jDelSize = jIns.existsSync() ? jIns.lengthSync() : -1;
  final jDelScan = jIns.existsSync() ? scan(jIns.readAsBytesSync()) : <String>[];
  db.execute('COMMIT');
  db.close();
  res['journal'] = {'insert_226kB_size': jInsSize, 'scan_insert': jScan, 'exists_after_commit': jAfter, 'delete_431kB_size': jDelSize, 'scan_delete': jDelScan};

  // 3) WAL (nur Vergleich, nicht empfohlen): Rahmen je Commit aus den Klartext-Koepfen
  final w = '$work/wal.db';
  db = open(w, mode: 'WAL');
  db.execute('PRAGMA wal_autocheckpoint = 0');
  db.select('PRAGMA wal_checkpoint(TRUNCATE)');
  final walSizes = [28111, 43256, 88478, 123746, 225741, 340726, 430875];
  for (final n in walSizes) put(db, 0, 'w$n', payload(n, n));
  final commits = walCommits('$w-wal');
  res['wal'] = {
    'entries': walSizes, 'frames_per_commit_from_plain_headers': commits,
    'entry_pages': [for (final n in walSizes) (n / (pageSize - 32)).ceil()],
    'scan': scan(File('$w-wal').readAsBytesSync()), 'wal_bytes': File('$w-wal').lengthSync(),
  };
  db.close();

  // --- Vergleich: Prueffeld (AES-GCM + HMAC je Datei, reines Dart wie in der Mini-App)
  final dirF = Directory('$work/files')..createSync();
  final aes = AesGcm.with256bits();
  final sk = SecretKey(List<int>.filled(32, 7)), nk = SecretKey(List<int>.filled(32, 9));
  final fw = <double>[];
  Future<String> nm(String k) async => (await Hmac.sha256().calculateMac(utf8.encode(k), secretKey: nk)).bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  Future<void> wf(String k, Uint8List v) async {
    final b = await aes.encrypt(v, secretKey: sk, aad: k.codeUnits);
    File('${dirF.path}/${await nm(k)}.bin').writeAsBytesSync([...b.nonce, ...b.cipherText, ...b.mac.bytes]);
  }
  Future<Uint8List> rf(String k) async {
    final b = File('${dirF.path}/${await nm(k)}.bin').readAsBytesSync();
    return Uint8List.fromList(await aes.decrypt(SecretBox(b.sublist(12, b.length - 16), nonce: b.sublist(0, 12), mac: Mac(b.sublist(b.length - 16))), secretKey: sk, aad: k.codeUnits));
  }
  for (var i = 0; i < sizes.length; i++) {
    final v = payload(sizes[i], i);
    final t = Stopwatch()..start();
    await wf('k$i', v);
    fw.add(t.elapsedMicroseconds / 1000);
  }
  final fr = <String, Object>{};
  for (final (i, label) in [(34, '28 kB'), (15, '136 kB'), (27, '431 kB')]) {
    final t = <double>[];
    for (var r = 0; r < 10; r++) {
      final sw = Stopwatch()..start();
      await rf('k$i');
      t.add(sw.elapsedMicroseconds / 1000);
    }
    fr['${sizes[i]} ($label)'] = {'read_ms_median': med(t)};
  }
  final allF = dirF.listSync().whereType<File>().map((f) => f.lengthSync()).toList();
  res['files_aesgcm'] = {
    'write_ms_median': med(fw), 'read': fr, 'files': allF.length, 'bytes': allF.reduce((x, y) => x + y),
    'exact_size_visible': {for (final n in [430875, 225741]) '$n': allF.contains(n + 28)},
  };

  final out = const JsonEncoder.withIndent(' ').convert(res);
  File('$work/store.json').writeAsStringSync(out);
  print(out);
}
