// WP13 Nachbesserung N1a: Kartenspeicher nach Löschen und Tausch der Datenbank, Beschädigung im Betrieb, Platz nach
// dem Verdrängen, Tor der Quelle (Review S1, S2, S5, S6, M3).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:adapters/src/map/map_cache_core.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';

import '../storage/support.dart' show testKey;
import 'map_fakes.dart';

Uint8List _bytes(int n, int seed) {
  final r = Random(seed);
  return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
}

String _tile(int i) => 'map:/planet/_/13/$i/2687.pbf';
String _thumb(int runId) => 'thumb:v1-test:$runId';

class _ClosingInner extends FakeInner {
  bool closed = false;
  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  late Directory dir;
  late String path;
  final key = testKey(3);

  EncryptedMapTileStore store({
    int tileLimit = mapTileLimitBytes,
    int thumbLimit = mapThumbnailLimitBytes,
  }) => EncryptedMapTileStore(
    directory: () async => dir.path,
    key: () async => key,
    tileLimit: tileLimit,
    thumbnailLimit: thumbLimit,
  );

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp13n1a_');
    path = '${dir.path}/$mapCacheFileName';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('S2: deleteRun und deleteAllThumbnails legen den Speicher nach dem Löschen nicht neu an', () async {
    final s = store();
    await s.write(_tile(1), _bytes(1000, 1));
    await s.delete();
    expect(File(path).existsSync(), isFalse);
    await s.deleteRun(7);
    await s.deleteAllThumbnails();
    expect(File(path).existsSync(), isFalse, reason: 'keine leere Datei');
    expect(await s.sizeBytes(), 0);
    // Schreiben danach legt ihn wieder an.
    await s.write(_tile(2), _bytes(10, 2));
    expect(await s.read(_tile(2)), _bytes(10, 2));
    await s.close();
  });

  test('M3: Tausch der Datenbank verwirft die Miniaturen (gleiche Lauf-Nummer, anderes Archiv), Kacheln bleiben', () async {
    final s = store();
    await s.write(_tile(1), _bytes(1000, 1));
    await s.write(_thumb(7), _bytes(500, 7));
    expect(await s.read(_thumb(7)), _bytes(500, 7));
    final dbPath = '${dir.path}/running_app.db';
    File(dbPath).writeAsBytesSync([1]);
    File('$dbPath.import').writeAsBytesSync([2]);
    await FileDatabaseFiles(
      dbPath,
      beforeReplace: s.deleteAllThumbnails,
    ).replaceWithImport();
    expect(
      await s.read(_thumb(7)),
      isNull,
      reason: 'Lauf 7 des Archivs ist ein anderer Lauf',
    );
    expect(await s.read(_tile(1)), _bytes(1000, 1));
    expect(File(dbPath).readAsBytesSync(), [2], reason: 'Tausch geschah');
    await s.close();
  });

  test('N7: scheitert das Verwerfen, löscht der Tausch den ganzen Kartenspeicher und tauscht dann', () async {
    final dbPath = '${dir.path}/running_app.db';
    File(dbPath).writeAsBytesSync([1]);
    File('$dbPath.import').writeAsBytesSync([2]);
    var fallback = 0;
    Object? seenAtFallback;
    await FileDatabaseFiles(
      dbPath,
      beforeReplace: () async => throw const FileSystemException('x'),
      beforeReplaceFallback: () async {
        fallback++;
        seenAtFallback = File(dbPath).readAsBytesSync().first;
      },
    ).replaceWithImport();
    expect(fallback, 1);
    expect(seenAtFallback, 1, reason: 'vor dem Umbenennen');
    expect(File(dbPath).readAsBytesSync(), [2]);
  });

  test('N7: Miniaturen werden vor dem Umbenennen verworfen (alte Datenbank steht noch)', () async {
    final dbPath = '${dir.path}/running_app.db';
    File(dbPath).writeAsBytesSync([1]);
    File('$dbPath.import').writeAsBytesSync([2]);
    int? atHook;
    await FileDatabaseFiles(
      dbPath,
      beforeReplace: () async => atHook = File(dbPath).readAsBytesSync().first,
    ).replaceWithImport();
    expect(atHook, 1);
    expect(File(dbPath).readAsBytesSync(), [2]);
  });

  test('N7: scheitert auch das Löschen, bricht der Tausch vor dem Umbenennen ab; die alte Datenbank bleibt, nichts verloren', () async {
    final dbPath = '${dir.path}/running_app.db';
    File(dbPath).writeAsBytesSync([1]);
    File('$dbPath.import').writeAsBytesSync([2]);
    await expectLater(
      FileDatabaseFiles(
        dbPath,
        beforeReplace: () async => throw const FileSystemException('x'),
        beforeReplaceFallback: () async => throw const FileSystemException('y'),
      ).replaceWithImport(),
      throwsA(isA<FileSystemException>()),
    );
    expect(File(dbPath).readAsBytesSync(), [1]);
    expect(File('$dbPath.import').readAsBytesSync(), [2]);
  });

  test('N7: deleteAllThumbnails wirft, wenn die Datei da ist, aber der Speicher nicht erreichbar (geschlossen)', () async {
    final s = store();
    await s.write(_thumb(7), _bytes(100, 7));
    await s.close();
    await expectLater(
      s.deleteAllThumbnails(),
      throwsA(isA<FileSystemException>()),
    );
    await s.delete();
    await s.deleteAllThumbnails(); // keine Datei: nichts zu tun
  });

  test('N3-S1: deleteAllThumbnails wirft, wenn das Löschen im Arbeiter scheitert (Ordner nur lesbar)', () async {
    final s = store();
    await s.write(_thumb(7), _bytes(100, 7));
    await Process.run('chmod', ['555', dir.path]);
    try {
      await expectLater(
        s.deleteAllThumbnails(),
        throwsA(isA<FileSystemException>()),
      );
    } finally {
      await Process.run('chmod', ['755', dir.path]);
    }
    await s.close();
  });

  test('S6: im Betrieb zerstörte Datei (offene Verbindung): Lesen liefert nichts, die Datei ist danach klein und neu, Schreiben geht', () async {
    final s = store();
    for (var i = 0; i < 40; i++) {
      await s.write(_tile(i), _bytes(10000, i));
    }
    final before = File(path).lengthSync();
    expect(before, greaterThan(300000));
    // Die ganze Datei überschreiben, während die Verbindung offen ist.
    final f = File(path).openSync(mode: FileMode.append);
    f.setPositionSync(0);
    f.writeFromSync(_bytes(before, 99));
    f.closeSync();
    // Gleich nach dem ersten Fehlschlag, noch vor jedem Neustart des Isolate: Der Isolate hat aufgeräumt, bevor er
    // antwortete (Datei weg), nicht erst der nächste Start beim Öffnen.
    expect(await s.read(_tile(0)), isNull);
    expect(
      File(path).existsSync() ? File(path).lengthSync() : 0,
      lessThan(before ~/ 4),
      reason: 'beschädigte Datei ist ersetzt, nicht liegen geblieben',
    );
    var hits = 0;
    for (var i = 1; i < 40; i++) {
      if (await s.read(_tile(i)) != null) hits++;
    }
    expect(hits, 0, reason: 'nie falscher Inhalt');
    await s.write(_tile(100), _bytes(100, 100));
    expect(await s.read(_tile(100)), _bytes(100, 100));
    expect(File(path).lengthSync(), lessThan(before ~/ 4));
    await s.close();
  });

  test('S5: unterschreitet die Grenze den Bestand weit, schrumpft die Datei (Vakuum), sie wird nicht nur wiederverwendbar', () {
    var c = MapCacheCore.open(
      path: path,
      hexKey: hexOfKey(key),
      tileLimit: 2000000,
    );
    for (var i = 0; i < 60; i++) {
      c.write(_tile(i), _bytes(10000, i));
    }
    c.close();
    final full = File(path).lengthSync();
    expect(full, greaterThan(550000));
    // Strenge Grenze: ein Schreiben verdrängt fast alles.
    c = MapCacheCore.open(path: path, hexKey: hexOfKey(key), tileLimit: 100000);
    c.write(_tile(1000), _bytes(10000, 1000));
    c.close();
    expect(
      File(path).lengthSync(),
      lessThan(100000 + 60000),
      reason: 'Platz ging an das Dateisystem zurück (voll: $full)',
    );
  });

  group('Quelle', () {
    setUp(() => vt.VectorTileLayer.clearMemoryCache());

    testWidgets('S1: dispose schließt das Tor (Verbindungen der Quelle)', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final inner = _ClosingInner();
        final g = MapGate(
          provider: MapProvider.openFreeMap,
          consent: () => true,
          inner: inner,
        );
        final src = (await MapTileSource.open(g))!;
        expect(inner.closed, isFalse);
        src.dispose();
        expect(inner.closed, isTrue);
      });
    });

    testWidgets('S1: scheitert open, ist das Tor geschlossen', (tester) async {
      await tester.runAsync(() async {
        final inner = _ClosingInner();
        var granted = true;
        final g = MapGate(
          provider: MapProvider.openFreeMap,
          consent: () {
            final v = granted;
            granted = false; // nach der Prüfung in open: Widerruf
            return v;
          },
          inner: inner,
        );
        await expectLater(
          MapTileSource.open(g),
          throwsA(isA<MapSourceUnavailable>()),
        );
        expect(inner.closed, isTrue);
      });
    });
  });
}
