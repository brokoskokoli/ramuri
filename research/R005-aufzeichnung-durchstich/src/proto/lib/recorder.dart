// Gleicher Schreibcode fuer alle Hosts. Messpunkte: siehe ../../../README.md.
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

const hostCh = MethodChannel('r005/host');
const locCh = EventChannel('r005/location');
const testKey = 'r005-testschluessel-nicht-geheim';
const marker = 'R005KLARTEXTMARKER';

class RawDb extends GeneratedDatabase {
  RawDb(super.e);
  @override Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override int get schemaVersion => 1;
}

/// Schluessel wie ADR-0003 Punkt 2 ueber flutter_secure_storage, aber mit festem Testwert, damit der Rechner die Kopien pruefen kann.
Future<String> readKey() async {
  const s = FlutterSecureStorage();
  var k = await s.read(key: 'dbkey');
  if (k == null) { await s.write(key: 'dbkey', value: testKey); k = await s.read(key: 'dbkey'); }
  return k!;
}

Future<RawDb> openDb(String path, {required String sync, required String key, required bool enc, int autoCk = 1000}) async {
  // createInBackground: die Verbindung lebt in einem Isolat; seit den vereinten Threads laeuft der Haupt-Isolat auf dem Android-Hauptthread.
  final ex = NativeDatabase.createInBackground(File(path), setup: (raw.Database d) {
    if (enc) d.execute("PRAGMA key = '$key'");
    d.execute('PRAGMA journal_mode = WAL');
    d.execute('PRAGMA synchronous = $sync');
    d.execute('PRAGMA secure_delete = ON');
    d.execute('PRAGMA wal_autocheckpoint = $autoCk');
  });
  final db = RawDb(ex);
  await db.customStatement('CREATE TABLE IF NOT EXISTS fix(seq INTEGER PRIMARY KEY, run TEXT, lat REAL, lon REAL, tfix_ns INTEGER, trecv_ns INTEGER, trecv_up_ms INTEGER, note TEXT)');
  final c = await db.customSelect("SELECT sqlite3mc_version() v").getSingle();
  final j = await db.customSelect('PRAGMA journal_mode').getSingle();
  final sy = await db.customSelect('PRAGMA synchronous').getSingle();
  String cipher = '-';
  if (enc) cipher = (await db.customSelect('PRAGMA cipher').getSingle()).data.values.first.toString();
  print('R005DB path=$path mc=${c.read<String>('v')} journal=${j.data.values.first} sync=${sy.data.values.first} cipher=$cipher');
  return db;
}

class Recorder {
  Recorder(this.cfg);
  final Map<String, dynamic> cfg;
  late final String run = cfg['run'] as String;
  late final int tx = (cfg['tx'] as int?) ?? 1;
  late final String sync = (cfg['sync'] as String?) ?? 'FULL';
  late RawDb db;
  final List<List<Object?>> buf = [];
  int seq = 0;
  int acked = 0;
  Future<void> chain = Future.value();
  StreamSubscription? sub;

  Future<void> start() async {
    final dir = await hostCh.invokeMethod<String>('noBackupDir');
    final key = await readKey();
    db = await openDb('$dir/r005-$run.db', sync: sync, key: key, enc: cfg['enc'] != false, autoCk: (cfg['autock'] as int?) ?? 1000);
    final ok = await hostCh.invokeMethod('startLocation', {'ms': 1000});
    print('R005START run=$run host=${cfg['host']} tx=$tx sync=$sync wake=${cfg['wake']} gpsEnabled=$ok');
    sub = locCh.receiveBroadcastStream().listen(onFix);
    if (cfg['steps'] == true) print('R005STEPS ${await hostCh.invokeMethod('steps')}');
    Timer.periodic(const Duration(seconds: 1), (_) => hb());
  }

  int hbN = 0;
  Future<void> hb() async {
    hbN++;
    final s = await hostCh.invokeMapMethod<String, dynamic>('state');
    print('R005HB run=$run n=$hbN el=${s!['elapsed_ms']} up=${s['uptime_ms']} locked=${s['locked']} inter=${s['interactive']} idle=${s['idle']} wake=${s['wakeHeld']}');
  }

  void onFix(dynamic e) {
    final m = (e as Map).cast<String, Object?>();
    seq++;
    final s = seq;
    print('R005RCV run=$run seq=$s tfix=${m['tfix_ns']} trecv=${m['trecv_ns']} lat=${m['lat']} lon=${m['lon']}');
    buf.add([s, run, m['lat'], m['lon'], m['tfix_ns'], m['trecv_ns'], m['trecv_up_ms'], '$marker-$s']);
    if (buf.length >= tx) {
      final batch = List<List<Object?>>.of(buf);
      buf.clear();
      // Reihenfolge erhalten: Transaktionen laufen nacheinander.
      chain = chain.then((_) => write(batch));
    }
  }

  Future<void> write(List<List<Object?>> b) async {
    final sw = Stopwatch()..start();
    await db.transaction(() async {
      for (final r in b) {
        await db.customStatement('INSERT INTO fix VALUES(?,?,?,?,?,?,?,?)', r);
      }
    });
    // Erst hier ist die Transaktion aus Sicht der App bestaetigt. Ausserhalb der DB, auf dem Rechner mitgeschrieben.
    acked = b.last[0] as int;
    print('R005ACK run=$run seq=$acked n=${b.length} us=${sw.elapsedMicroseconds}');
  }
}

/// Schreibkosten ohne Standort: viele Commits hintereinander.
Future<void> bench(Map<String, dynamic> cfg) async {
  final dir = await hostCh.invokeMethod<String>('noBackupDir');
  final key = await readKey();
  final run = cfg['run'] as String;
  final n = (cfg['n'] as int?) ?? 300;
  for (final sync in ['FULL', 'NORMAL']) {
    for (final tx in [1, 5, 30]) {
      final db = await openDb('$dir/bench-$run-$sync-$tx.db', sync: sync, key: key, enc: true);
      var seq = 0;
      for (var i = 0; i < n; i++) {
        final sw = Stopwatch()..start();
        await db.transaction(() async {
          for (var k = 0; k < tx; k++) {
            seq++;
            await db.customStatement('INSERT INTO fix VALUES(?,?,?,?,?,?,?,?)', [seq, run, 48.1, 11.5, 1, 2, 3, '$marker-$seq']);
          }
        });
        print('R005BENCH run=$run sync=$sync tx=$tx i=$i us=${sw.elapsedMicroseconds}');
      }
      await db.close();
    }
  }
  print('R005BENCHDONE run=$run');
}

/// Prueft eine vorhandene Datei in der App selbst (Wiederherstellung auf dem Geraet).
Future<void> verify(String run) async {
  final dir = await hostCh.invokeMethod<String>('noBackupDir');
  final key = await readKey();
  final db = await openDb('$dir/r005-$run.db', sync: 'FULL', key: key, enc: true);
  final r = await db.customSelect('SELECT count(*) c, max(seq) m FROM fix').getSingle();
  final ic = await db.customSelect('PRAGMA integrity_check').getSingle();
  print('R005VERIFY run=$run count=${r.data['c']} max=${r.data['m']} integrity=${ic.data.values.first}');
  await db.close();
}
