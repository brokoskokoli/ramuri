// R008 Host-Tests fmvt (flutter test, kein Emulator). Testvorlagen aus ./init.sh: R008_FIXTURES=<.../fixtures>
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:r008_fmvt/ofmvt.dart';
import 'package:r008_fmvt/route.dart';
import 'package:r008_fmvt/store.dart';
import 'package:r008_fmvt/thumbvt.dart';

final fix = Platform.environment['R008_FIXTURES'] ?? '';

List<String> plaintextHits(Directory d) {
  final sigs = <String, List<int>>{
    'pbf:transportation': utf8.encode('transportation'),
    'pbf:landcover': utf8.encode('landcover'),
    'png': [0x89, 0x50, 0x4E, 0x47],
    'gzip': [0x1f, 0x8b, 0x08],
    'sqlite': utf8.encode('SQLite format 3'),
    'json:openmaptiles': utf8.encode('openmaptiles'),
  };
  final hits = <String>[];
  if (!d.existsSync()) return hits;
  for (final f in d.listSync(recursive: true).whereType<File>()) {
    final b = f.readAsBytesSync();
    sigs.forEach((n, s) {
      for (var i = 0; i + s.length <= b.length; i++) {
        var ok = true;
        for (var j = 0; j < s.length && ok; j++) {
          ok = b[i + j] == s[j];
        }
        if (ok) {
          hits.add('$n in ${f.path.substring(d.path.length)}');
          return;
        }
      }
    });
  }
  return hits;
}

/// Liefert die Testvorlagen unter ihren OpenFreeMap-URLs; alles andere 404. Zaehlt Anfragen je Art.
class FixtureClient extends http.BaseClient {
  final calls = <String, int>{};
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    final u = r.url.toString();
    String? f;
    var kind = 'other';
    if (u == styleUrl) { f = 'liberty.json'; kind = 'style'; }
    else if (u == 'https://tiles.openfreemap.org/planet') { f = 'planet.json'; kind = 'tilejson'; }
    else if (u.contains('/sprites/')) { f = u.split('/').last.replaceFirst('ofm', 'sprite'); kind = 'sprite'; }
    else if (u.contains('/fonts/')) { kind = 'glyph'; }
    else {
      final m = RegExp(r'/planet/[^/]+/(\d+)/(\d+)/(\d+)\.pbf$').firstMatch(u);
      if (m != null) { f = 'tiles/${m[1]}-${m[2]}-${m[3]}.pbf'; kind = 'tile'; }
    }
    calls[kind] = (calls[kind] ?? 0) + 1;
    final file = f == null ? null : File('$fix/$f');
    if (file == null || !file.existsSync()) return http.StreamedResponse(Stream.value(const <int>[]), 404, request: r);
    final b = file.readAsBytesSync();
    return http.StreamedResponse(Stream.value(b), 200, contentLength: b.length, request: r);
  }
}

class FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  FakePaths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => '$root/support';
  @override
  Future<String?> getTemporaryPath() async => '$root/tmp';
  @override
  Future<String?> getApplicationDocumentsPath() async => '$root/docs';
  @override
  Future<String?> getApplicationCachePath() async => '$root/cache';
}

Future<void> settle(WidgetTester t, {int n = 40}) async {
  for (var k = 0; k < n; k++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 100)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('r008vt');
    PathProviderPlatform.instance = FakePaths(tmp.path);
    vt.VectorTileLayer.clearMemoryCache(); // Speicher der Bibliothek ist prozessweit: jeder Test frisch
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('Positivkontrolle: Signatursuche findet Klartext-Kachel, PNG und Stil', () {
    expect(fix, isNotEmpty, reason: 'R008_FIXTURES setzen (./init.sh)');
    File('${tmp.path}/a').writeAsBytesSync(File('$fix/tiles/14-8801-5376.pbf').readAsBytesSync());
    File('${tmp.path}/b').writeAsBytesSync(File('$fix/sprite@2x.png').readAsBytesSync());
    File('${tmp.path}/c').writeAsBytesSync(File('$fix/liberty.json').readAsBytesSync());
    final h = plaintextHits(tmp);
    expect(h, containsAll([startsWith('pbf:'), startsWith('png'), startsWith('json:')]));
  });

  test('fail-closed und Tor: ohne Einwilligung kein Client, fremde Hosts abgewiesen', () async {
    final st = await EncStore.open(Directory('${tmp.path}/t'));
    expect(() => GatedClient.create(consent: false, store: st), throwsA(isA<ConsentMissing>()));
    final inner = FixtureClient();
    final c = GatedClient.create(consent: true, store: st, inner: inner);
    expect(() => c.get(Uri.parse('https://api.mapbox.com/x')), throwsStateError);
    expect(() => c.get(Uri.parse('http://tiles.openfreemap.org/planet')), throwsStateError);
    expect(inner.calls, isEmpty);
  });

  for (final mode in ['tor', 'standard']) {
    testWidgets(mode == 'tor'
        ? 'fmvt mit Tor: alles ueber den Client, nur verschluesselt gespeichert'
        : 'Gegenprobe Standardwerte (Stil-Cache, Plattencache 50 MB): Klartext auf der Platte', (tester) async {
      final enc = (await tester.runAsync(() => EncStore.open(Directory('${tmp.path}/support/map-tiles'))))!;
      final inner = FixtureClient();
      final c = GatedClient.create(consent: true, store: enc, inner: inner);
      final style = mode == 'tor'
          ? (await tester.runAsync(() => loadStyle(c)))!
          : (await tester.runAsync(() => vt.StyleReader(
                uri: styleUrl,
                httpClient: c,
                resolveProvider: (id) async => id == 'openmaptiles'
                    ? vt.NetworkVectorTileProvider(urlTemplate: File('$fix/tile_template.txt').readAsStringSync().trim(), client: c)
                    : null,
              ).read()))!;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: RepaintBoundary(
                  key: key,
                  child: SizedBox(
                      width: 480,
                      height: 240,
                      child: FlutterMap(
                        options: const MapOptions(initialCenter: LatLng(centerLat, centerLon), initialZoom: 14.5),
                        children: [vtLayer(style, plain: mode != 'tor', fade: Duration.zero)],
                      ))))));
      await settle(tester);
      final img = (await tester.runAsync(() => (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage()))!;
      final png = (await tester.runAsync(() => img.toByteData(format: ui.ImageByteFormat.png)))!;
      File('${Platform.environment['R008_OUT'] ?? tmp.path}/fmvt_host_$mode.png').writeAsBytesSync(png.buffer.asUint8List());
      final files = tmp.listSync(recursive: true).whereType<File>().map((f) => f.path.substring(tmp.path.length)).toList();
      final outside = files.where((p) => !p.startsWith('/support/map-tiles/') && p != '/support/r008-research.key').toList();
      final hits = plaintextHits(tmp);
      // ignore: avoid_print
      print('R008 fmvt mode=$mode inner_calls=${inner.calls} net_req=${c.netRequests} store_hits=${c.storeHits} '
          'enc_writes=${enc.writes} files=${files.length} outside_enc=${outside.length} plaintext_hits=${hits.length} '
          'png_bytes=${png.lengthInBytes} ${hits.take(5)}');
      expect(inner.calls['tile'] ?? 0, greaterThan(0), reason: 'Kacheln ueber den Client');
      if (mode == 'tor') {
        expect(enc.writes, greaterThan(0));
        expect(outside, isEmpty, reason: 'keine Dateien ausserhalb des verschluesselten Speichers');
        expect(hits, isEmpty);
      } else {
        expect(hits, isNotEmpty, reason: 'Gegenprobe: Bibliothek speichert im Klartext');
      }
      img.dispose();
      style.dispose();
      await tester.pumpWidget(const SizedBox());
      await settle(tester, n: 3);
    });
  }

  test('Befund: StyleReader ohne resolveProvider holt Kacheln am uebergebenen Client vorbei', () async {
    final inner = FixtureClient();
    final style = await vt.StyleReader(uri: styleUrl, httpClient: inner, cache: false).read();
    final p = style.providers['openmaptiles']!;
    // Testumgebung (TestWidgetsFlutterBinding nicht aktiv): eigenes Netz verhindern, Anfrage muss scheitern statt rauszugehen
    final r = await HttpOverrides.runZoned(() => p.load(const vt.TileKey(13, 4400, 2687)), createHttpClient: (_) => throw const SocketException('R008: Netz im Test gesperrt'));
    // ignore: avoid_print
    print('R008 fmvt bypass provider=${p.runtimeType} inner_calls=${inner.calls} response=${r.runtimeType}');
    expect(inner.calls['style'], 1);
    expect(inner.calls['tilejson'], 1, reason: 'TileJSON noch ueber den Client');
    expect(inner.calls['tile'] ?? 0, 0, reason: 'Kachel ging nicht ueber den uebergebenen Client');
    expect(r, isA<vt.TileResponseError>(), reason: 'Bibliothek versuchte eigenes Netz (im Test gesperrt)');
    style.dispose();
  });

  testWidgets('Miniatur: unsichtbare Karte, Schnappschuss, verschluesselt abgelegt', (tester) async {
    final enc = (await tester.runAsync(() => EncStore.open(Directory('${tmp.path}/support/map-tiles'))))!;
    final thumbs = (await tester.runAsync(() => EncStore.open(Directory('${tmp.path}/support/map-thumbs'))))!;
    final c = GatedClient.create(consent: true, store: enc, inner: FixtureClient());
    final style = (await tester.runAsync(() => loadStyle(c)))!;
    final key = GlobalKey();
    final r = [for (final p in syntheticRun(1)) LatLng(p.lat, p.lon)];
    final sw = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(home: Stack(children: [Positioned(left: -2 * thumbW, top: 0, child: thumbMap(r, style, key))])));
    await settle(tester);
    final img = (await tester.runAsync(() => (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage()))!;
    final png = (await tester.runAsync(() => img.toByteData(format: ui.ImageByteFormat.png)))!.buffer.asUint8List();
    await tester.runAsync(() => thumbs.write('thumb:1:map', png));
    File('${Platform.environment['R008_OUT'] ?? tmp.path}/fmvt_thumb_host.png').writeAsBytesSync(png);
    // ignore: avoid_print
    print('R008 fmvt host_thumb wall_ms=${sw.elapsedMilliseconds} (inkl. fester Wartezeit settle) png_bytes=${png.length} '
        'size=${img.width}x${img.height}');
    expect(img.width, thumbW.toInt());
    expect(png.length, greaterThan(20000), reason: 'mit Karteninhalt, nicht nur Hintergrund und Linie');
    expect(plaintextHits(tmp), isEmpty);
    img.dispose();
    style.dispose();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, n: 3);
  });
}
