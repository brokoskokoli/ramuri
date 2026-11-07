// R008 Host-Tests (flutter test, kein Emulator). Testvorlagen aus ./init.sh: R008_FIXTURES=<.../fixtures>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:r008_fm/ofm.dart';
import 'package:r008_fm/route.dart';
import 'package:r008_fm/store.dart';
import 'package:r008_fm/thumb.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

final fix = Platform.environment['R008_FIXTURES'] ?? '';

/// Klartext-Signaturen: PBF-Ebenennamen der OpenMapTiles, PNG, gzip, SQLite.
List<String> plaintextHits(Directory d) {
  final sigs = <String, List<int>>{
    'pbf:transportation': utf8.encode('transportation'),
    'pbf:landcover': utf8.encode('landcover'),
    'png': [0x89, 0x50, 0x4E, 0x47],
    'gzip': [0x1f, 0x8b, 0x08],
    'sqlite': utf8.encode('SQLite format 3'),
  };
  final hits = <String>[];
  for (final f in d.listSync(recursive: true).whereType<File>()) {
    final b = f.readAsBytesSync();
    sigs.forEach((n, s) {
      for (var i = 0; i + s.length <= b.length; i++) {
        var ok = true;
        for (var j = 0; j < s.length && ok; j++) {
          ok = b[i + j] == s[j];
        }
        if (ok) {
          hits.add('$n in ${f.path.split('/').last}');
          return;
        }
      }
    });
  }
  return hits;
}

Uint8List tileBytes(int z, int x, int y) => File('$fix/tiles/$z-$x-$y.pbf').readAsBytesSync();

vtr.Theme theme() {
  final s = jsonDecode(File('$fix/liberty.json').readAsStringSync()) as Map<String, dynamic>;
  s['layers'] = (s['layers'] as List).where((l) => (l as Map)['source'] != 'ne2_shaded').toList();
  (s['sources'] as Map).remove('ne2_shaded');
  return vtr.ThemeReader().read(s);
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('r008'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('Positivkontrolle: Signatursuche findet Klartext-Kachel und PNG', () {
    expect(fix, isNotEmpty, reason: 'R008_FIXTURES setzen (./init.sh)');
    File('${tmp.path}/a').writeAsBytesSync(tileBytes(14, 8801, 5376));
    File('${tmp.path}/b').writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0, 0]);
    final h = plaintextHits(tmp);
    expect(h, contains(startsWith('pbf:')));
    expect(h, contains(startsWith('png')));
  });

  test('EncStore: Rundweg, kein Klartext, Groessengrenze greift', () async {
    final st = await EncStore.open(Directory('${tmp.path}/tiles'), maxBytes: 400 * 1024);
    final t = tileBytes(14, 8802, 5376);
    for (var i = 0; i < 40; i++) {
      await st.write('tile:14/$i/0', t);
    }
    expect(await st.read('tile:14/39/0'), t);
    expect(plaintextHits(Directory('${tmp.path}/tiles')), isEmpty);
    await st.evict();
    expect(await st.size(), lessThanOrEqualTo(400 * 1024));
    // Dateinamen ohne Kachelkoordinaten
    expect(Directory('${tmp.path}/tiles').listSync().map((e) => e.path).where((p) => p.contains('14')), isEmpty);
  });

  test('fail-closed: ohne Einwilligung keine Quelle', () async {
    final st = await EncStore.open(Directory('${tmp.path}/t'));
    expect(() => OfmSource.create(consent: false, store: st), throwsA(isA<ConsentMissing>()));
  });

  test('Miniatur offscreen aus Vektorkacheln, einmal erzeugt und verschluesselt abgelegt', () async {
    final th = theme();
    final st = await EncStore.open(Directory('${tmp.path}/thumbs'));
    final requested = <String>[];
    final sw = Stopwatch()..start();
    final png = await renderThumb(syntheticRun(1), w: 480, h: 240, theme: th, tiles: (z, x, y) async {
      requested.add('$z/$x/$y');
      final f = File('$fix/tiles/$z-$x-$y.pbf');
      return f.existsSync() ? f.readAsBytesSync() : null;
    });
    final ms = sw.elapsedMilliseconds;
    await st.write('thumb:1:map', png);
    final line = await renderThumb(syntheticRun(1), w: 480, h: 240);
    // ignore: avoid_print
    print('R008 host_thumb ms=$ms png_bytes=${png.length} line_png_bytes=${line.length} tiles=$requested');
    File('${Platform.environment['R008_OUT'] ?? tmp.path}/thumb_host.png').writeAsBytesSync(png);
    expect(requested.every((k) => File('$fix/tiles/${k.replaceAll('/', '-')}.pbf').existsSync()), isTrue,
        reason: 'Testvorlagen decken die Miniatur ab: $requested');
    expect(png.length, greaterThan(line.length * 2), reason: 'mit Karte deutlich mehr Inhalt als nur Linie');
    expect(plaintextHits(Directory('${tmp.path}/thumbs')), isEmpty);
  });

  for (final patched in [true, false]) {
    testWidgets('vector_map_tiles schreibt ${patched ? 'ueber den Hook verschluesselt' : 'ohne Hook im Klartext (Gegenprobe)'}',
        (tester) async {
      final th = theme();
      final enc = await tester.runAsync(() => EncStore.open(Directory('${tmp.path}/enc')));
      final plainDir = Directory('${tmp.path}/plain');
      final provider = _FixtureProvider();
      await tester.pumpWidget(MaterialApp(
          home: SizedBox(
              width: 400,
              height: 400,
              child: FlutterMap(
                options: const MapOptions(initialCenter: LatLng(centerLat, centerLon), initialZoom: 14.5),
                children: [
                  VectorTileLayer(
                    theme: th,
                    tileProviders: TileProviders({'openmaptiles': provider}),
                    layerMode: VectorTileLayerMode.vector,
                    cacheStorage: patched ? EncByteStorage(enc!) : null,
                    cacheFolder: () async => plainDir as dynamic,
                  ),
                ],
              ))));
      for (var k = 0; k < 30; k++) {
        await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      // ignore: avoid_print
      print('R008 vmt patched=$patched provided=${provider.calls} enc_writes=${enc!.writes} '
          'plain_files=${plainDir.existsSync() ? plainDir.listSync(recursive: true).whereType<File>().length : 0}');
      expect(provider.calls, greaterThan(0));
      if (patched) {
        expect(enc.writes, greaterThan(0));
        expect(plainDir.existsSync() && plainDir.listSync(recursive: true).isNotEmpty, isFalse);
        expect(plaintextHits(tmp), isEmpty);
      } else {
        expect(plaintextHits(plainDir), isNotEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 200)));
    });
  }
}

class _FixtureProvider extends VectorTileProvider {
  int calls = 0, missing = 0;
  @override
  int get maximumZoom => 14;
  @override
  int get minimumZoom => 0;
  @override
  TileOffset get tileOffset => TileOffset.DEFAULT;
  @override
  Future<Uint8List> provide(TileIdentity t) async {
    calls++;
    final f = File('$fix/tiles/${t.z}-${t.x}-${t.y}.pbf');
    if (!f.existsSync()) missing++;
    return f.existsSync() ? f.readAsBytesSync() : Uint8List(0); // fehlende Kachel = leere Kachel
  }
}
