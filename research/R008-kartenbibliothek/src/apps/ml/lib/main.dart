// R008 Mini-App ml: maplibre_gl (MapLibre Native Android als Platform View) mit OpenFreeMap.
// Routen wie bei fm: /idle, /live?consent=1&page=1, /detail?consent=1, /thumbs?consent=1&n=50&auto=1
// ambient=1 laesst den Ambient-Cache von MapLibre an (Standard hier: 0 Byte, Gegenprobe zum Klartext-Cache).
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:path_provider/path_provider.dart';

import 'route.dart';
import 'store.dart';

late final Uri cfg;
late final EncStore thumbStore;
late final bool consent;
const styleUrl = 'https://tiles.openfreemap.org/styles/liberty';
const attribution = '© OpenFreeMap © OpenMapTiles Daten © OpenStreetMap-Mitwirkende';
void log(String s) => debugPrint('R008 $s');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cfg = Uri.parse(ui.PlatformDispatcher.instance.defaultRouteName);
  consent = cfg.queryParameters['consent'] == '1';
  final sup = await getApplicationSupportDirectory();
  thumbStore = await EncStore.open(Directory('${sup.path}/map-thumbs'), maxBytes: 20 << 20);
  if (cfg.queryParameters['ambient'] != '1') {
    try {
      await setMaximumAmbientCacheSize(0);
      log('ambient_cache=0');
    } catch (e) {
      log('ambient_cache_error ${e.runtimeType}');
    }
  }
  Timer.periodic(const Duration(seconds: 10), (_) async => log('stats thumb_store=${await thumbStore.size()}'));
  runApp(MaterialApp(home: switch (cfg.path) {
    '/live' => const LivePage(),
    '/detail' => const DetailPage(),
    '/thumbs' => const ThumbsPage(),
    _ => const Scaffold(body: Center(child: Text('R008 ml idle'))),
  }, debugShowCheckedModeBanner: false));
}

List<LatLng> ll(List<P> p) => [for (final q in p) LatLng(q.lat, q.lon)];

LatLngBounds bounds(List<LatLng> r) {
  var a = 90.0, b = 180.0, c = -90.0, d = -180.0;
  for (final p in r) {
    a = min(a, p.latitude); b = min(b, p.longitude); c = max(c, p.latitude); d = max(d, p.longitude);
  }
  return LatLngBounds(southwest: LatLng(a, b), northeast: LatLng(c, d));
}

Map<String, dynamic> lineGeo(List<LatLng> r) => {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {},
          'geometry': {'type': 'LineString', 'coordinates': [for (final p in r) [p.longitude, p.latitude]]}
        }
      ]
    };

Future<void> addRoute(MapLibreMapController c, List<LatLng> r) async {
  await c.addGeoJsonSource('route', lineGeo(r));
  await c.addLineLayer('route', 'route-line', const LineLayerProperties(lineColor: '#E53935', lineWidth: 4));
}

/// Ohne Einwilligung wird kein MapLibre-Widget erzeugt (keine native Karte, kein Netz): nur die Linie.
class LinePainter extends CustomPainter {
  LinePainter(this.r);
  final List<LatLng> r;
  @override
  void paint(Canvas canvas, Size s) {
    final b = bounds(r);
    final sx = s.width / (b.northeast.longitude - b.southwest.longitude), sy = s.height / (b.northeast.latitude - b.southwest.latitude);
    final k = min(sx, sy * 0.6) * 0.8;
    final path = Path();
    for (var i = 0; i < r.length; i++) {
      final x = s.width / 2 + (r[i].longitude - (b.southwest.longitude + b.northeast.longitude) / 2) * k;
      final y = s.height / 2 - (r[i].latitude - (b.southwest.latitude + b.northeast.latitude) / 2) * k / 0.6;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = const Color(0xFFE53935));
  }

  @override
  bool shouldRepaint(LinePainter o) => o.r.length != r.length;
}

class LivePage extends StatefulWidget {
  const LivePage({super.key});
  @override
  State<LivePage> createState() => _LiveState();
}

class _LiveState extends State<LivePage> {
  final route = ll(syntheticRun(0));
  MapLibreMapController? c;
  late final PageController pc = PageController(initialPage: int.parse(cfg.queryParameters['page'] ?? '1'));
  int i = 1, frames = 0;
  bool styled = false;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((ts) => frames += ts.length);
    Timer.periodic(const Duration(seconds: 1), (_) async {
      setState(() => i = (i + 1) % route.length);
      final m = c;
      if (m != null && styled) {
        await m.setGeoJsonSource('route', lineGeo(route.sublist(0, i + 1)));
        await m.moveCamera(CameraUpdate.newLatLng(route[i]));
      }
    });
    Timer.periodic(const Duration(seconds: 30), (_) => log('live frames_30s=$frames'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PageView(controller: pc, children: [
          Center(child: Text('Werte\nPunkt $i', textAlign: TextAlign.center, style: const TextStyle(fontSize: 40))),
          consent
              ? Stack(children: [
                  MapLibreMap(
                    styleString: styleUrl,
                    initialCameraPosition: CameraPosition(target: route[0], zoom: 16),
                    onMapCreated: (m) => c = m,
                    onStyleLoadedCallback: () async {
                      await addRoute(c!, route.sublist(0, 2));
                      styled = true;
                    },
                    attributionButtonPosition: AttributionButtonPosition.bottomRight,
                  ),
                ])
              : CustomPaint(painter: LinePainter(route.sublist(0, i + 1)), size: Size.infinite),
        ]),
      );
}

class DetailPage extends StatelessWidget {
  const DetailPage({super.key});
  @override
  Widget build(BuildContext context) {
    final r = ll(syntheticRun(0));
    MapLibreMapController? c;
    return Scaffold(
      body: consent
          ? MapLibreMap(
              styleString: styleUrl,
              initialCameraPosition: CameraPosition(target: r[0], zoom: 14),
              onMapCreated: (m) => c = m,
              onStyleLoadedCallback: () async {
                await addRoute(c!, r);
                await c!.moveCamera(CameraUpdate.newLatLngBounds(bounds(r), left: 24, right: 24, top: 24, bottom: 24));
              },
            )
          : CustomPaint(painter: LinePainter(r), size: Size.infinite),
    );
  }
}

/// Miniaturen: eine versteckte Generator-Karte (160 x 80 dp) rendert nacheinander je Lauf, takeSnapshot,
/// PNG verschluesselt in thumbStore. Die Liste zeigt nur Bilder.
class ThumbsPage extends StatefulWidget {
  const ThumbsPage({super.key});
  @override
  State<ThumbsPage> createState() => _ThumbsState();
}

class _ThumbsState extends State<ThumbsPage> {
  final n = int.parse(cfg.queryParameters['n'] ?? '50');
  final sc = ScrollController();
  final imgs = <int, Uint8List>{};
  MapLibreMapController? gen;
  bool genReady = false, genDone = false;
  int generated = 0, genMs = 0, loaded = 0;

  @override
  void initState() {
    super.initState();
    _loadStored();
  }

  Future<void> _loadStored() async {
    for (var i = 0; i < n; i++) {
      final b = await thumbStore.read('thumb:$i:${consent ? 'map' : 'line'}');
      if (b != null) {
        imgs[i] = b;
        loaded++;
      }
    }
    log('thumbs_loaded=$loaded');
    setState(() {});
    if (!consent || loaded == n) {
      genDone = true;
      setState(() {});
      _auto();
    }
  }

  Future<void> _generate() async {
    final m = gen!;
    await addRoute(m, ll(syntheticRun(1)));
    for (var i = 0; i < n; i++) {
      if (imgs.containsKey(i)) continue;
      final t = Stopwatch()..start();
      final r = ll(syntheticRun(i + 1));
      await m.setGeoJsonSource('route', lineGeo(r));
      await m.moveCamera(CameraUpdate.newLatLngBounds(bounds(r), left: 8, right: 8, top: 8, bottom: 8));
      await Future.delayed(const Duration(milliseconds: 300)); // Kacheln laden lassen (kein Idle-Ereignis abgewartet)
      final png = await m.takeSnapshot();
      await thumbStore.write('thumb:$i:map', png);
      generated++;
      genMs += t.elapsedMilliseconds;
      log('thumb gen ms=${t.elapsedMilliseconds} png_bytes=${png.length} generated=$generated avg_ms=${genMs ~/ generated}');
      setState(() => imgs[i] = png);
    }
    setState(() => genDone = true);
    _auto();
  }

  void _auto() {
    if (cfg.queryParameters['auto'] != '1') return;
    Future.delayed(const Duration(seconds: 5), () async {
      for (var k = 0; k < 3; k++) {
        await sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(seconds: 8), curve: Curves.linear);
        await sc.animateTo(0, duration: const Duration(seconds: 8), curve: Curves.linear);
      }
      log('autoscroll_done generated=$generated loaded=$loaded');
    });
  }

  @override
  Widget build(BuildContext context) {
    final r1 = ll(syntheticRun(1));
    return Scaffold(
      body: Column(children: [
        if (consent && !genDone)
          SizedBox(
            width: 160,
            height: 80,
            child: MapLibreMap(
              styleString: styleUrl,
              initialCameraPosition: CameraPosition(target: r1[0], zoom: 14),
              onMapCreated: (m) => gen = m,
              onStyleLoadedCallback: () {
                if (!genReady) {
                  genReady = true;
                  _generate();
                }
              },
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: sc,
            itemCount: n,
            itemExtent: 112,
            itemBuilder: (c, i) => ListTile(
              leading: SizedBox(
                width: 160,
                height: 80,
                child: consent
                    ? (imgs[i] == null ? const ColoredBox(color: Color(0xFFE0E0E0)) : Image.memory(imgs[i]!, gaplessPlayback: true))
                    : CustomPaint(painter: LinePainter(ll(syntheticRun(i + 1)))),
              ),
              title: Text('Lauf ${i + 1}'),
              subtitle: Text(consent ? attribution : 'ohne Karte', style: const TextStyle(fontSize: 9)),
            ),
          ),
        ),
      ]),
    );
  }
}
