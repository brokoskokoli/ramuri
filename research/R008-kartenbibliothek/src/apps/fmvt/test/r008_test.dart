// R008 Host-Tests fmvt (flutter test, kein Emulator). Testvorlagen aus ./init.sh: R008_FIXTURES=<.../fixtures>
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:r008_fmvt/ofmvt.dart';
import 'package:r008_fmvt/route.dart';
import 'package:r008_fmvt/store.dart';
import 'package:r008_fmvt/thumbvt.dart';

final fix = Platform.environment['R008_FIXTURES'] ?? '';

/// gzip-Signatur (3 Byte) kommt in Zufallsdaten etwa einmal je 16 MiB vor (verschluesselte Dateien!). Ein Treffer
/// zaehlt nur, wenn ab dort ein Streaming-Inflate tatsaechlich Ausgabe liefert; Anhang hinter dem Strom ist erlaubt.
/// Frueher gzip.decode(rest): lehnte echtes gzip mit >= 8 Byte Anhang ab und "entpackte" Zufallsbytes zu leerer Ausgabe
/// (Review R008 Runde 2, Befund 3).
class _CountSink implements Sink<List<int>> {
  int n = 0;
  @override
  void add(List<int> c) => n += c.length;
  @override
  void close() {}
}

int gunzipOutput(List<int> b, int i) {
  final sink = _CountSink();
  try {
    final conv = gzip.decoder.startChunkedConversion(sink);
    conv.add(b.sublist(i));
    conv.close();
  } catch (_) {
    // Fehler am Ende (Anhang, abgeschnitten) zaehlen nicht; zaehlt, was bis dahin herauskam.
  }
  return sink.n;
}

bool gunzipOk(List<int> b, int i) => gunzipOutput(b, i) > 0;

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
        if (ok && n == 'gzip') {
          ok = gunzipOk(b, i);
          // ignore: avoid_print
          if (ok) print('R008 gzip_hit offset=$i dateigroesse=${b.length} ${f.path.substring(d.path.length)}');
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
  final urls = <Uri>{};
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    final u = r.url.toString();
    urls.add(r.url);
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

/// Gate-Test M2: Kein Dateiname im Speicher darf sich aus einer angefragten URL ohne Geheimnis nachrechnen lassen.
/// Kandidaten je URL: SHA-256 von Speicherschluessel (GatedClient.key), roher URL und URL mit Datumspfad.
Future<List<String>> guessableNames(Directory store, Iterable<Uri> urls) async {
  String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  final cand = <String, String>{};
  for (final u in urls) {
    for (final t in {GatedClient.key(u), u.toString(), 'http:$u'}) {
      cand[hex((await Sha256().hash(utf8.encode(t))).bytes)] = u.path;
    }
  }
  return [
    for (final f in store.listSync().whereType<File>())
      if (cand.containsKey(f.uri.pathSegments.last.replaceFirst('.bin', ''))) cand[f.uri.pathSegments.last.replaceFirst('.bin', '')]!
  ];
}

/// Kachel-URLs (Vektor und Raster), die ausserhalb des Sollausschnitts liegen (mit einer Kachel Rand je Richtung, weil
/// die Kachelebene am Rand etwas vorauslaedt). Gate-Vorlage fuer WP13: jede vom Tor gesehene Kachel liegt im Umfeld der Route.
(List<String>, int, Set<int>) tilesOutside(Iterable<Uri> urls, MapCamera soll) {
  final re = RegExp(r'/(\d+)/(\d+)/(\d+)\.(pbf|png)$');
  final b = soll.visibleBounds;
  double tx(double lon, int z) => (lon + 180) / 360 * (1 << z);
  double ty(double lat, int z) => (1 - log(tan(lat * pi / 180) + 1 / cos(lat * pi / 180)) / pi) / 2 * (1 << z);
  final out = <String>[];
  final zs = <int>{};
  var n = 0;
  for (final u in urls) {
    if (u.path.startsWith('/fonts/')) continue;
    final m = re.firstMatch(u.path);
    if (m == null) continue;
    n++;
    final z = int.parse(m[1]!), x = int.parse(m[2]!), y = int.parse(m[3]!);
    zs.add(z);
    final inX = x >= tx(b.west, z).floor() - 1 && x <= tx(b.east, z).floor() + 1;
    final inY = y >= ty(b.north, z).floor() - 1 && y <= ty(b.south, z).floor() + 1;
    if (!inX || !inY) out.add('$z/$x/$y');
  }
  return (out, n, zs);
}

/// Baut die Kachelebene erst, wenn die Karte ihre Groesse kennt und die Kamera eingepasst ist.
class _LayerAfterFit extends StatefulWidget {
  const _LayerAfterFit({required this.fit, required this.layer});
  final CameraFit fit;
  final Widget layer;
  @override
  State<_LayerAfterFit> createState() => _LayerAfterFitState();
}

class _LayerAfterFitState extends State<_LayerAfterFit> {
  bool ready = false;
  @override
  Widget build(BuildContext context) => FlutterMap(
        options: MapOptions(initialCameraFit: widget.fit, onMapReady: () => setState(() => ready = true)),
        children: [if (ready) widget.layer],
      );
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
    final gz = gzip.encode(utf8.encode('{"r008": "gzip-Positivkontrolle"}'));
    File('${tmp.path}/d').writeAsBytesSync(gz);
    // gzip mit Anhang und in Nonce + Inhalt + Tag (so saehe ein Speicher mit ausgeschalteter Verschluesselung aus)
    for (final n in [1, 8, 16, 28, 64]) {
      File('${tmp.path}/g$n').writeAsBytesSync([...gz, ...List<int>.filled(n, 0x5a)]);
    }
    File('${tmp.path}/box').writeAsBytesSync([...List<int>.filled(12, 0x11), ...gz, ...List<int>.filled(16, 0x22)]);
    // Negativkontrolle: Zufallsbytes mit eingestreuter gzip-Signatur sind kein Treffer
    final rnd = List<int>.generate(4096, (i) => (i * 2654435761 >> 7) & 0xff)..setRange(1000, 1003, [0x1f, 0x8b, 0x08]);
    File('${tmp.path}/e').writeAsBytesSync(rnd);
    final h = plaintextHits(tmp);
    expect(h, containsAll([startsWith('pbf:'), startsWith('png'), startsWith('json:'), 'gzip in /d']));
    expect(h.where((x) => x.endsWith('/e')), isEmpty, reason: 'zufaellige gzip-Signatur ohne gzip-Strom');
    expect(h, containsAll(['gzip in /g1', 'gzip in /g8', 'gzip in /g16', 'gzip in /g28', 'gzip in /g64', 'gzip in /box']),
        reason: 'gzip mit Anhang wird erkannt');
  });

  test('Fehlalarm-Rate: Zufallsbytes hinter gzip-Signatur liefern keine Ausgabe', () {
    final rng = Random(8);
    final out = <int, int>{};
    for (final len in [64, 20000]) {
      var yes = 0;
      for (var k = 0; k < 3000; k++) {
        final b = [0x1f, 0x8b, 0x08, ...List<int>.generate(len, (_) => rng.nextInt(256))];
        if (gunzipOk(b, 0)) yes++;
      }
      out[len] = yes;
    }
    // ignore: avoid_print
    print('R008 fmvt gzip_false_positive of3000 $out');
    expect(out.values.reduce((a, b) => a + b), lessThanOrEqualTo(3), reason: 'hoechstens seltener Fehlalarm');
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

  for (final mode in ['tor', 'tor-altnamen', 'standard']) {
    testWidgets(switch (mode) {
      'tor' => 'fmvt mit Tor: alles ueber den Client, nur verschluesselt gespeichert, Dateinamen nicht erratbar',
      'tor-altnamen' => 'Gegenprobe Dateinamen: alte Benennung SHA-256(URL) ist per URL-Hash auffindbar',
      _ => 'Gegenprobe Standardwerte (Stil-Cache, Plattencache 50 MB): Klartext auf der Platte',
    }, (tester) async {
      final enc = (await tester.runAsync(
          () => EncStore.open(Directory('${tmp.path}/support/map-tiles'), legacyNames: mode == 'tor-altnamen')))!;
      final inner = FixtureClient();
      final c = GatedClient.create(consent: true, store: enc, inner: inner);
      final style = mode != 'standard'
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
                        children: [vtLayer(style, plain: mode == 'standard', fade: Duration.zero)],
                      ))))));
      await settle(tester);
      final img = (await tester.runAsync(() => (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage()))!;
      final png = (await tester.runAsync(() => img.toByteData(format: ui.ImageByteFormat.png)))!;
      File('${Platform.environment['R008_OUT'] ?? tmp.path}/fmvt_host_$mode.png').writeAsBytesSync(png.buffer.asUint8List());
      final files = tmp.listSync(recursive: true).whereType<File>().map((f) => f.path.substring(tmp.path.length)).toList();
      final outside = files.where((p) => !p.startsWith('/support/map-tiles/') && p != '/support/r008-research.key').toList();
      final hits = plaintextHits(tmp);
      final encFiles = Directory('${tmp.path}/support/map-tiles').listSync().whereType<File>().length;
      final guessed = (await tester.runAsync(() => guessableNames(Directory('${tmp.path}/support/map-tiles'), inner.urls)))!;
      // ignore: avoid_print
      print('R008 fmvt mode=$mode inner_calls=${inner.calls} net_req=${c.netRequests} store_hits=${c.storeHits} '
          'enc_writes=${enc.writes} files=${files.length} outside_enc=${outside.length} plaintext_hits=${hits.length} '
          'png_bytes=${png.lengthInBytes} ${hits.take(5)} enc_files=$encFiles urls=${inner.urls.length} '
          'names_guessable=${guessed.length} ${guessed.take(3)}');
      expect(inner.calls['tile'] ?? 0, greaterThan(0), reason: 'Kacheln ueber den Client');
      if (mode != 'standard') {
        expect(enc.writes, greaterThan(0));
        expect(outside, isEmpty, reason: 'keine Dateien ausserhalb des verschluesselten Speichers');
        expect(hits, isEmpty);
      }
      if (mode == 'tor') {
        expect(guessed, isEmpty, reason: 'kein Dateiname = SHA-256 einer angefragten URL');
      } else if (mode == 'tor-altnamen') {
        expect(guessed.length, encFiles, reason: 'Gegenprobe: jede Datei per URL-Hash zuzuordnen');
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

  test('Dateinamen haengen vom Geheimnis ab: zwei Speicher mit verschiedenen Schluesseln, gleicher Eintrag', () async {
    // Review R008 Runde 2, Befund 4: "nicht SHA-256 der URL" allein bestuende auch ein fest eingebauter HMAC-Schluessel.
    final a = await EncStore.open(Directory('${tmp.path}/a/tiles'));
    final b = await EncStore.open(Directory('${tmp.path}/b/tiles'));
    final a2 = await EncStore.open(Directory('${tmp.path}/a/tiles')); // gleicher Schluessel
    final t = Uint8List.fromList(List<int>.filled(100, 7));
    await a.write('http:eintrag', t);
    await b.write('http:eintrag', t);
    final na = a.dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    final nb = b.dir.listSync().map((f) => f.uri.pathSegments.last).toSet();
    // ignore: avoid_print
    print('R008 fmvt names_per_key verschieden=${na.intersection(nb).isEmpty}');
    expect(na.intersection(nb), isEmpty, reason: 'gleicher Eintrag, anderer Schluessel: anderer Name');
    expect(await a2.read('http:eintrag'), t, reason: 'gleicher Schluessel findet den Eintrag wieder');
  });

  // Review R008 Runde 2, Befund 1: initialCameraFit greift erst nach bekannter Groesse; bis dahin steht die Kamera auf
  // dem Standard von MapOptions (50.5/30.51, Zoom 13), und die Kachelebene fragt dort schon an.
  for (final (name, size) in [('miniatur', const Size(thumbW, thumbH)), ('detail', const Size(800, 600))]) {
    for (final mode in ['wie-gemessen', 'nur-zentrum', 'startkamera', 'ebene-danach']) {
      testWidgets('Fremdkacheln $name $mode', (tester) async {
        final enc = (await tester.runAsync(() => EncStore.open(Directory('${tmp.path}/support/map-tiles'))))!;
        final inner = FixtureClient();
        final c = GatedClient.create(consent: true, store: enc, inner: inner);
        final style = (await tester.runAsync(() => loadStyle(c)))!;
        final r = [for (final p in syntheticRun(1)) LatLng(p.lat, p.lon)];
        const pad = EdgeInsets.all(16);
        final fit = CameraFit.coordinates(coordinates: r, padding: pad);
        final soll = fit.fit(MapCamera.initialCamera(const MapOptions()).withNonRotatedSize(size));
        final Widget map = switch (mode) {
          'wie-gemessen' => FlutterMap(options: MapOptions(initialCameraFit: fit), children: [vtLayer(style, fade: Duration.zero)]),
          'nur-zentrum' => FlutterMap(options: MapOptions(initialCenter: soll.center, initialCameraFit: fit), children: [vtLayer(style, fade: Duration.zero)]),
          'startkamera' => FlutterMap(options: MapOptions(initialCenter: soll.center, initialZoom: soll.zoom, initialCameraFit: fit), children: [vtLayer(style, fade: Duration.zero)]),
          _ => _LayerAfterFit(fit: fit, layer: vtLayer(style, fade: Duration.zero)),
        };
        await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: size.width, height: size.height, child: map))));
        await settle(tester, n: 15);
        final (ausserhalb, tiles, zs) = tilesOutside(inner.urls, soll);
        // ignore: avoid_print
        print('R008 fmvt fremd $name $mode kacheln=$tiles zooms=$zs soll_zoom=${soll.zoom.toStringAsFixed(2)} ausserhalb=${ausserhalb.length} $ausserhalb');
        expect(tiles, greaterThan(0));
        if (mode == 'wie-gemessen') {
          expect(ausserhalb.where((t) => t.startsWith('12/239')), isNotEmpty, reason: 'Befund: Kacheln am Standardzentrum');
        }
        if (mode == 'startkamera' || mode == 'ebene-danach') {
          expect(ausserhalb, isEmpty, reason: 'keine Kachel ausserhalb des Ausschnitts');
        }
        style.dispose();
        await tester.pumpWidget(const SizedBox());
        await settle(tester, n: 3);
      });
    }
  }

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
    final thumbNames = thumbs.dir.listSync().map((f) => f.uri.pathSegments.last).toList();
    final plainName = (await tester.runAsync(() => Sha256().hash(utf8.encode('thumb:1:map'))))!.bytes
        .map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    expect(thumbNames, isNot(contains('$plainName.bin')), reason: 'Miniatur-Name nicht aus der Lauf-Nummer erratbar');
    img.dispose();
    style.dispose();
    await tester.pumpWidget(const SizedBox());
    await settle(tester, n: 3);
  });
}
