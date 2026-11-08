import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:adapters/src/map/map_cache_core.dart';
import 'package:core/core.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../storage/support.dart' show noCipherLibrary, testKey;
import 'map_fakes.dart';
import 'plaintext_scan.dart';

String _hex(Uint8List k) => hexOfKey(k);

Uint8List _bytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

String _tile(int i) => 'map:/planet/_/13/$i/2687.pbf';
String _thumb(int i) => 'thumb:run$i';

/// Inhalt, der überall verräterische Signaturen trägt (so sähe eine Klartext-Ablage aus).
Uint8List _revealing(int seed) {
  final b = BytesBuilder();
  b.add(utf8.encode('transportation landcover water '));
  b.add([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  b.add([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
  b.add(utf8.encode('RIFF'));
  b.add([1, 2, 3, 4]);
  b.add(utf8.encode('WEBP'));
  b.add(utf8.encode('SQLite format 3\u0000'));
  b.add(gzipWithTail('Nutzlast $seed ${'x' * 200}'));
  b.add(_bytes(5000, seed));
  return b.takeBytes();
}

void main() {
  late Directory dir;
  late String path;
  final key = testKey(3);

  EncryptedMapTileStore store({
    Uint8List? k,
    int tileLimit = mapTileLimitBytes,
    int thumbLimit = mapThumbnailLimitBytes,
    LibraryCipherProbe probe = defaultLibraryCipherProbe,
  }) => EncryptedMapTileStore(
    directory: () async => dir.path,
    key: () async => k ?? key,
    tileLimit: tileLimit,
    thumbnailLimit: thumbLimit,
    libraryProbe: probe,
  );

  MapCacheCore core({
    Uint8List? k,
    int tileLimit = mapTileLimitBytes,
    int thumbLimit = mapThumbnailLimitBytes,
  }) => MapCacheCore.open(
    path: path,
    hexKey: _hex(k ?? key),
    tileLimit: tileLimit,
    thumbnailLimit: thumbLimit,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp13a2_');
    path = '${dir.path}/$mapCacheFileName';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('Einrichtung', () {
    test('PRAGMAs, kein -wal, verschlüsselt, Ort der Datei', () async {
      final c = core();
      expect(c.pragma('journal_mode'), 'delete');
      expect(c.pragma('synchronous'), 1);
      expect(c.pragma('secure_delete'), 1);
      expect(c.pragma('auto_vacuum'), 2);
      expect(c.pragma('temp_store'), 2);
      for (var i = 0; i < 20; i++) {
        c.write(_tile(i), _bytes(3000, i));
      }
      expect(File('$path-wal').existsSync(), isFalse);
      expect(File('$path-shm').existsSync(), isFalse);
      expect(File('$path-journal').existsSync(), isFalse);
      c.close();
      expect(defaultFileEncryptedProbe(path), isTrue);
      expect(dir.listSync().map((e) => e.path.split('/').last), [
        mapCacheFileName,
      ]);
    });

    test(
      'Ohne belegte Verschlüsselung entsteht kein Speicher und keine Datei',
      () async {
        final s = store(probe: noCipherLibrary);
        await s.write(_tile(1), _bytes(100, 1));
        expect(await s.read(_tile(1)), isNull);
        expect(dir.listSync(), isEmpty);
        await s.close();
      },
    );

    test(
      'Klartextdatei (Verschlüsselung wirkungslos) wird gelöscht, nie benutzt',
      () {
        expect(
          () => MapCacheCore.open(
            path: path,
            hexKey: _hex(key),
            fileProbe: (_) => false,
          ),
          throwsA(isA<ConnectionSetupFailure>()),
        );
        expect(File(path).existsSync(), isFalse);
      },
    );

    test(
      'Ort: Datei liegt im Verzeichnis ohne Backup (getNoBackupFilesDir)',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(noBackupChannel, (call) async {
          expect(call.method, 'getNoBackupFilesDir');
          return dir.path;
        });
        addTearDown(
          () => messenger.setMockMethodCallHandler(noBackupChannel, null),
        );
        final s = EncryptedMapTileStore(
          directory: noBackupFilesDir,
          key: () async => key,
        );
        await s.write(_tile(1), _bytes(10, 1));
        expect(await s.read(_tile(1)), isNotNull);
        expect(File('${dir.path}/map_cache.db').existsSync(), isTrue);
        expect(await s.sizeBytes(), greaterThan(0));
        await s.close();
      },
    );
  });

  group('Lesen, Schreiben, Grenzen', () {
    test('Rundgang über den Isolate; Art aus dem Schlüssel', () async {
      final s = store();
      expect(await s.read(_tile(1)), isNull);
      final t = _bytes(2000, 1), m = _bytes(900, 2);
      await s.write(_tile(1), t);
      await s.write(_thumb(1), m);
      expect(await s.read(_tile(1)), t);
      expect(await s.read(_thumb(1)), m);
      await s.close();
      final c = core();
      expect(c.count(MapStoreKind.tile), 1);
      expect(c.count(MapStoreKind.thumbnail), 1);
      c.close();
    });

    test('Grenze je Art greift (Kacheln), jüngste bleiben', () {
      final c = core(tileLimit: 100000);
      for (var i = 0; i < 60; i++) {
        c.write(_tile(i), _bytes(5000, i));
      }
      expect(c.contentBytes(MapStoreKind.tile), lessThanOrEqualTo(100000));
      expect(c.count(MapStoreKind.tile), 20);
      expect(c.read(_tile(59)), isNotNull);
      expect(c.read(_tile(40)), isNotNull);
      expect(c.read(_tile(0)), isNull);
      c.close();
    });

    test('Grenze für Miniaturen greift eigenständig; zu großer Eintrag wird nicht gespeichert', () {
      final c = core(thumbLimit: 30000);
      for (var i = 0; i < 20; i++) {
        c.write(_thumb(i), _bytes(5000, i));
      }
      expect(c.contentBytes(MapStoreKind.thumbnail), lessThanOrEqualTo(30000));
      c.write(_thumb(99), _bytes(30001, 1));
      expect(c.read(_thumb(99)), isNull);
      c.close();
    });

    test('Miniatur übersteht das Füllen mit Kacheln', () {
      final c = core(tileLimit: 50000, thumbLimit: 50000);
      c.write(_thumb(1), _bytes(4000, 7));
      for (var i = 0; i < 100; i++) {
        c.write(_tile(i), _bytes(5000, i));
      }
      expect(c.contentBytes(MapStoreKind.tile), lessThanOrEqualTo(50000));
      expect(c.read(_thumb(1)), _bytes(4000, 7));
      c.close();
    });

    test('LRU: ein berührter alter Eintrag bleibt, der ungenutzte geht', () {
      final c = core(tileLimit: 50000);
      for (var i = 0; i < 10; i++) {
        c.write(_tile(i), _bytes(5000, i));
      }
      expect(c.read(_tile(0)), isNotNull); // berührt, Marke nur im Speicher
      for (var i = 10; i < 14; i++) {
        c.write(_tile(i), _bytes(5000, i));
      }
      expect(c.read(_tile(0)), isNotNull, reason: 'berührt, bleibt');
      expect(c.read(_tile(1)), isNull, reason: 'am längsten ungenutzt');
      expect(c.read(_tile(4)), isNull);
      expect(c.read(_tile(5)), isNotNull);
      c.close();
    });

    test(
      'Zugriffsmarken überleben das Schließen nicht, die Datei bleibt lesbar',
      () {
        var c = core();
        c.write(_tile(1), _bytes(100, 1));
        c.close();
        c = core();
        expect(c.read(_tile(1)), _bytes(100, 1));
        c.close();
      },
    );

    test('Speicherplatz wird nach dem Verdrängen zurückgegeben (incremental_vacuum)', () {
      final c = core(tileLimit: 200000);
      for (var i = 0; i < 40; i++) {
        c.write(_tile(i), _bytes(10000, i));
      }
      c.close();
      expect(File(path).lengthSync(), lessThan(200000 + 60000));
    });
  });

  group('Fehler und Schlüssel', () {
    test('falscher Schlüssel liest nichts; die Datei wird neu aufgebaut', () {
      var c = core();
      c.write(_tile(1), _bytes(1000, 1));
      c.close();
      c = core(k: testKey(9));
      expect(c.read(_tile(1)), isNull);
      c.close();
      c = core();
      expect(c.read(_tile(1)), isNull, reason: 'alter Inhalt ist weg');
      c.close();
    });

    test(
      'beschädigte Datei: löschen und neu aufbauen, Speicher bricht nichts',
      () async {
        final s0 = store();
        await s0.write(_tile(1), _bytes(1000, 1));
        await s0.close();
        File(path).writeAsBytesSync(_bytes(20000, 4));
        final s = store();
        expect(await s.read(_tile(1)), isNull);
        await s.write(_tile(2), _bytes(100, 2));
        expect(await s.read(_tile(2)), _bytes(100, 2));
        await s.close();
      },
    );

    test('Fehler im Betrieb werden nie geworfen (zerstörte Seiten)', () async {
      final s = store();
      for (var i = 0; i < 5; i++) {
        await s.write(_tile(i), _bytes(5000, i));
      }
      final f = File(path).openSync(mode: FileMode.append);
      f.setPositionSync(0);
      f.writeFromSync(_bytes(20000, 1));
      f.closeSync();
      for (var i = 0; i < 5; i++) {
        await s.read(_tile(i));
        await s.write(_tile(10 + i), _bytes(3000, i));
      }
      await s.close();
    });

    test('Schlüssel fehlt oder hat falsche Länge: aus, ohne Fehler', () async {
      final s = EncryptedMapTileStore(
        directory: () async => dir.path,
        key: () async => null,
      );
      await s.write(_tile(1), _bytes(10, 1));
      expect(await s.read(_tile(1)), isNull);
      expect(dir.listSync(), isEmpty);
      await s.close();
    });
  });

  group('Klartext-Scan', () {
    test(
      'Scanner selbst: Positivkontrolle je Signatur, gzip nur mit Ausgabe',
      () {
        final sigs = {
          'pbf': utf8.encode('xx transportation yy'),
          'png': [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
          'jpeg': [0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46],
          'webp': [...utf8.encode('RIFF'), 1, 2, 3, 4, ...utf8.encode('WEBP')],
          'sqlite': utf8.encode('SQLite format 3\u0000'),
          'gzip': gzipWithTail('hallo ${'y' * 100}'),
        };
        for (final e in sigs.entries) {
          final hits = plaintextHits(Uint8List.fromList(e.value));
          expect(hits.map((h) => h.name), contains(e.key), reason: e.key);
        }
        // Dreibyte-Signatur ohne Ausgabe zählt nicht.
        final noise = Uint8List.fromList([
          0x1f,
          0x8b,
          0x08,
          ..._bytes(4000, 1),
        ]);
        expect(plaintextHits(noise), isEmpty);
        // Zufallsdaten ohne Signaturen: leer.
        expect(plaintextHits(_bytes(300000, 5)), isEmpty);
      },
    );

    test('Datei und -journal ohne Treffer; dieselbe Datei ohne Schlüssel findet Treffer', () {
      final plainPath = '${dir.path}/plain.db';
      final c = core();
      final plain = raw.sqlite3.open(plainPath);
      plain.execute('PRAGMA auto_vacuum = INCREMENTAL');
      plain.execute(
        'CREATE TABLE entries (kind INTEGER, key TEXT, data BLOB, size INTEGER, last_used INTEGER)',
      );
      for (var i = 0; i < 30; i++) {
        final b = _revealing(i);
        c.write(_tile(i), b);
        plain.execute('INSERT INTO entries VALUES (0, ?, ?, ?, ?)', [
          _tile(i),
          b,
          b.length,
          i,
        ]);
      }
      c.close();

      // Offene Transaktion: ein -journal mit Seitenabbildern existiert (Lauf der Verdrängung, Absturz mitten im Schreiben).
      final enc = raw.sqlite3.open(path);
      ConnectionSetup.unlock(enc, _hex(key), defaultLibraryCipherProbe);
      enc.execute('PRAGMA journal_mode = DELETE');
      enc.execute('PRAGMA secure_delete = ON');
      enc.execute('BEGIN IMMEDIATE');
      enc.execute('DELETE FROM entries WHERE last_used < 20');
      plain.execute('PRAGMA journal_mode = DELETE');
      plain.execute('PRAGMA secure_delete = ON');
      plain.execute('BEGIN IMMEDIATE');
      plain.execute('DELETE FROM entries WHERE last_used < 20');
      final journal = File('$path-journal');
      final plainJournal = File('$plainPath-journal');
      expect(journal.existsSync() && journal.lengthSync() > 0, isTrue);
      expect(
        plainJournal.existsSync() && plainJournal.lengthSync() > 0,
        isTrue,
      );

      for (final f in [File(path), journal]) {
        final hits = plaintextHits(f.readAsBytesSync());
        expect(
          hits,
          isEmpty,
          reason: '${f.path.split('/').last} (${f.lengthSync()} B): $hits',
        );
      }
      // Gegenprobe: dieselben Inhalte ohne Schlüssel sind lesbar, in Datei und Journal.
      for (final f in [File(plainPath), plainJournal]) {
        final names = plaintextHits(f.readAsBytesSync())
            .map((h) => h.name)
            .toSet();
        expect(
          names,
          containsAll(['pbf', 'png', 'jpeg', 'webp', 'sqlite', 'gzip']),
          reason: f.path.split('/').last,
        );
      }
      enc.execute('ROLLBACK');
      plain.execute('ROLLBACK');
      enc.close();
      plain.close();
    });
  });

  group('Löschen', () {
    test(
      'delete() entfernt Datei und -journal und schließt die Verbindung',
      () async {
        final s = store();
        await s.write(_tile(1), _bytes(1000, 1));
        File('$path-journal').writeAsBytesSync([1, 2, 3]);
        File('$path-wal').writeAsBytesSync([1, 2, 3]);
        expect(await s.sizeBytes(), greaterThan(0));
        await s.delete();
        expect(File(path).existsSync(), isFalse);
        expect(File('$path-journal').existsSync(), isFalse);
        expect(File('$path-wal').existsSync(), isFalse);
        expect(await s.sizeBytes(), 0);
        // Danach entsteht der Speicher wieder.
        await s.write(_tile(2), _bytes(10, 2));
        expect(await s.read(_tile(2)), _bytes(10, 2));
        await s.close();
      },
    );

    test('Alles löschen (Sitzung) räumt den Kartenspeicher ab', () async {
      final s = store();
      await s.write(_tile(1), _bytes(1000, 1));
      File('$path-journal').writeAsBytesSync([1, 2, 3]);
      final dbPath = '${dir.path}/running_app.db';
      final session = await EncryptedStorage(
        dbPath,
        onDeleteAll: s.delete,
      ).open(key);
      await session.deleteAll();
      await session.close();
      expect(File(path).existsSync(), isFalse);
      expect(File('$path-journal').existsSync(), isFalse);
      await s.close();
    });

    test('Alles löschen: scheitert das Abräumen, meldet die Sitzung deletedNotErased', () async {
      final session = await EncryptedStorage(
        '${dir.path}/running_app.db',
        onDeleteAll: () async => throw const FileSystemException('x'),
      ).open(key);
      await expectLater(
        session.deleteAll(),
        throwsA(
          isA<StorageException>().having(
            (e) => e.failure,
            'failure',
            StorageFailure.deletedNotErased,
          ),
        ),
      );
      await session.close();
    });

    test('Neubeginn nach Schlüsselverlust (FileDatabaseFiles.deleteAll) räumt ihn ab, exist() zählt ihn nicht', () async {
      final s = store();
      await s.write(_tile(1), _bytes(1000, 1));
      final files = FileDatabaseFiles(
        '${dir.path}/running_app.db',
        alsoDelete: s.delete,
      );
      expect(
        await files.exist(),
        isFalse,
        reason: 'er allein ist kein Datenbestand',
      );
      File('${dir.path}/running_app.db').writeAsBytesSync([1]);
      await files.deleteAll();
      expect(File(path).existsSync(), isFalse);
      expect(File('${dir.path}/running_app.db').existsSync(), isFalse);
      await s.close();
    });
  });

  group('Nicht in Archiv und Wiederherstellung', () {
    test('Abschnitte des Archivs kennen keine Kartentabelle; Tausch der Datenbank lässt die Kartendatei stehen', () async {
      final names = {for (final s in archiveSections) s.name};
      expect(
        names.where((n) => n.contains('entries') || n.contains('map')),
        isEmpty,
      );
      final s = store();
      await s.write(_tile(1), _bytes(1000, 1));
      await s.close();
      final dbPath = '${dir.path}/running_app.db';
      File(dbPath).writeAsBytesSync([1]);
      File('$dbPath.import').writeAsBytesSync([2]);
      await FileDatabaseFiles(dbPath).replaceWithImport();
      await FileDatabaseFiles(dbPath).deleteImport();
      expect(File(path).existsSync(), isTrue);
    });
  });

  group('Tor und Speicher', () {
    late FakeInner inner;
    setUp(() {
      vt.VectorTileLayer.clearMemoryCache();
      inner = FakeInner();
    });

    MapGate gateWith(MapTileStore? st) => MapGate(
      provider: MapProvider.openFreeMap,
      consent: () => true,
      store: st,
      inner: inner,
    );

    int styles() => inner.count((u) => u.path.startsWith('/styles/'));

    testWidgets('Stil geht ohne Speicher nur einmal ins Netz', (tester) async {
      await tester.runAsync(() async {
        final g = gateWith(null);
        final src = (await MapTileSource.open(g))!;
        expect(styles(), 1);
        expect(g.counts.network[MapResource.style], 1);
        src.dispose();
      });
    });

    testWidgets(
      'echter Speicher: zweite Quelle holt Stil und Kachel nicht mehr aus dem Netz',
      (tester) async {
        await tester.runAsync(() async {
          final s = store();
          final g1 = gateWith(s);
          final src1 = (await MapTileSource.open(g1))!;
          await src1.style.providers['openmaptiles']!.load(
            const vt.TileKey(13, 4400, 2687),
          );
          src1.dispose();
          expect(styles(), 1);
          final before = inner.requests.length;
          expect(before, greaterThan(0));

          vt.VectorTileLayer.clearMemoryCache();
          final g2 = gateWith(s);
          final src2 = (await MapTileSource.open(g2))!;
          await src2.style.providers['openmaptiles']!.load(
            const vt.TileKey(13, 4400, 2687),
          );
          src2.dispose();
          expect(
            inner.requests.length,
            before,
            reason: 'alles aus dem Speicher',
          );
          expect(g2.counts.networkTotal, 0);
          expect(g2.counts.stored[MapResource.style], 1);
          expect(g2.counts.stored[MapResource.tile], 1);
          await s.close();
        });
      },
    );
  });

  test(
    'remove entfernt genau einen Eintrag, ohne Datei tut es nichts',
    () async {
      final s = store();
      await s.remove(_tile(1));
      expect(File(path).existsSync(), isFalse, reason: 'legt nichts an');
      await s.write(_tile(1), _bytes(100, 1));
      await s.write(_tile(2), _bytes(100, 2));
      await s.remove(_tile(1));
      expect(await s.read(_tile(1)), isNull);
      expect(await s.read(_tile(2)), isNotNull);
      await s.close();
    },
  );

  test('MESSUNG (Host, nur Rangfolgen): Lesen 431 kB, Schreiben, Verdrängen', () async {
    final s = store(tileLimit: 5000000);
    final big = _bytes(431000, 1);
    final sw = Stopwatch()..start();
    await s.write(_tile(0), big);
    final writeFirst = sw.elapsedMicroseconds;
    final writes = <int>[], reads = <int>[], evict = <int>[];
    for (var i = 1; i <= 10; i++) {
      sw
        ..reset()
        ..start();
      await s.write(_tile(i), big);
      writes.add(sw.elapsedMicroseconds);
    }
    for (var i = 0; i < 20; i++) {
      sw
        ..reset()
        ..start();
      final r = await s.read(_tile(i % 11));
      reads.add(sw.elapsedMicroseconds);
      expect(r, isNotNull);
    }
    await s.close();
    final c = core(tileLimit: 1300000);
    for (var i = 0; i < 3; i++) {
      c.write(_tile(i), big);
    }
    for (var i = 3; i < 13; i++) {
      sw
        ..reset()
        ..start();
      c.write(_tile(i), big); // schreibt und verdrängt jedes Mal eine Kachel
      evict.add(sw.elapsedMicroseconds);
    }
    c.close();
    double med(List<int> l) => (l..sort())[l.length ~/ 2] / 1000;
    // ignore: avoid_print
    print(
      'MESSUNG ms: Schreiben erste ${writeFirst / 1000}, Schreiben Median ${med(writes)}, '
      'Lesen 431 kB Median ${med(reads)}, Schreiben mit Verdrängen Median ${med(evict)}',
    );
  });
}
