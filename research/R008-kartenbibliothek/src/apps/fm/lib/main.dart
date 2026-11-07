// R008 Mini-App fm: flutter_map + vector_map_tiles (gepatcht) mit OpenFreeMap.
// Start ueber die Route der Activity, z. B. adb shell am start -n <pkg>/.MainActivity --es route "/live?consent=1"
//   /idle                      leerer Bildschirm (Grundlast)
//   /live?consent=0|1&page=1   Live-Seite (PageView, Seite 1 = Karte), Position wandert mit 1 Hz
//   /detail?consent=0|1        Detailkarte, bedienbar
//   /thumbs?consent=0|1&n=50&auto=1   Historie mit Miniaturen, auto=1 scrollt selbst
//   plaincache=1               ohne Hook: vector_map_tiles nutzt seinen Klartext-Dateicache (Gegenprobe)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

import 'ofm.dart';
import 'route.dart';
import 'store.dart';
import 'thumb.dart';

late final Uri cfg;
late final EncStore tileStore, thumbStore;
OfmSource? source; // nur mit Einwilligung
const attribution = '© OpenFreeMap © OpenMapTiles Daten © OpenStreetMap-Mitwirkende';

void log(String s) => debugPrint('R008 $s');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cfg = Uri.parse(ui.PlatformDispatcher.instance.defaultRouteName);
  final sup = await getApplicationSupportDirectory();
  tileStore = await EncStore.open(_dir(sup, 'map-tiles'), maxBytes: 50 << 20);
  thumbStore = await EncStore.open(_dir(sup, 'map-thumbs'), maxBytes: 20 << 20);
  final consent = cfg.queryParameters['consent'] == '1';
  try {
    source = OfmSource.create(consent: consent, store: tileStore);
    final t = Stopwatch()..start();
    await source!.load();
    log('style_loaded ms=${t.elapsedMilliseconds}');
  } on ConsentMissing {
    log('no_consent -> Linie ohne Karte');
  } catch (e) {
    log('source_error ${e.runtimeType} -> Linie ohne Karte');
    source = null;
  }
  Timer.periodic(const Duration(seconds: 10), (_) async {
    log('stats net_req=${source?.netRequests ?? 0} net_bytes=${source?.netBytes ?? 0} '
        'tile_store=${await tileStore.size()} thumb_store=${await thumbStore.size()}');
  });
  runApp(const App());
}

Directory _dir(Directory base, String n) => Directory('${base.path}/$n');

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    final page = switch (cfg.path) {
      '/live' => const LivePage(),
      '/detail' => const DetailPage(),
      '/thumbs' => const ThumbsPage(),
      _ => const Scaffold(body: Center(child: Text('R008 fm idle'))),
    };
    return MaterialApp(home: page, debugShowCheckedModeBanner: false);
  }
}

List<LatLng> ll(List<P> p) => [for (final q in p) LatLng(q.lat, q.lon)];

List<Widget> baseLayers() {
  final s = source;
  if (s == null) return const [];
  final plain = cfg.queryParameters['plaincache'] == '1';
  return [
    VectorTileLayer(
      theme: s.theme,
      sprites: s.sprites(),
      tileProviders: TileProviders({'openmaptiles': s.provider()}),
      cacheStorage: plain ? null : EncByteStorage(tileStore),
      layerMode: VectorTileLayerMode.vector,
    ),
  ];
}

Widget attributionLayer() => source == null
    ? const SizedBox.shrink()
    : const Align(
        alignment: Alignment.bottomRight,
        child: ColoredBox(color: Color(0xCCFFFFFF), child: Padding(padding: EdgeInsets.all(2), child: Text(attribution, style: TextStyle(fontSize: 9)))));

class LivePage extends StatefulWidget {
  const LivePage({super.key});
  @override
  State<LivePage> createState() => _LiveState();
}

class _LiveState extends State<LivePage> {
  final route = ll(syntheticRun(0));
  final ctrl = MapController();
  late final PageController pc = PageController(initialPage: int.parse(cfg.queryParameters['page'] ?? '1'));
  int i = 1;
  Timer? t;
  int frames = 0;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((ts) => frames += ts.length);
    t = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => i = (i + 1) % route.length);
      try {
        ctrl.move(route[i], 16);
      } catch (_) {}
    });
    Timer.periodic(const Duration(seconds: 30), (_) => log('live frames_30s=$frames'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PageView(controller: pc, children: [
          Center(child: Text('Werte\nPunkt $i', textAlign: TextAlign.center, style: const TextStyle(fontSize: 40))),
          FlutterMap(
            mapController: ctrl,
            options: MapOptions(initialCenter: route[0], initialZoom: 16, backgroundColor: const Color(0xFFF2EFE9)),
            children: [
              ...baseLayers(),
              PolylineLayer(polylines: [Polyline(points: route.sublist(0, i + 1), strokeWidth: 4, color: Colors.red)]),
              MarkerLayer(markers: [Marker(point: route[i], width: 16, height: 16, child: const DecoratedBox(decoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle)))]),
              attributionLayer(),
            ],
          ),
        ]),
      );
}

class DetailPage extends StatelessWidget {
  const DetailPage({super.key});
  @override
  Widget build(BuildContext context) {
    final r = ll(syntheticRun(0));
    return Scaffold(
      body: FlutterMap(
        options: MapOptions(initialCameraFit: CameraFit.coordinates(coordinates: r, padding: const EdgeInsets.all(24)), backgroundColor: const Color(0xFFF2EFE9)),
        children: [...baseLayers(), PolylineLayer(polylines: [Polyline(points: r, strokeWidth: 4, color: Colors.red)]), attributionLayer()],
      ),
    );
  }
}

class ThumbsPage extends StatefulWidget {
  const ThumbsPage({super.key});
  @override
  State<ThumbsPage> createState() => _ThumbsState();
}

class _ThumbsState extends State<ThumbsPage> {
  final n = int.parse(cfg.queryParameters['n'] ?? '50');
  final sc = ScrollController();
  final cache = <int, Future<Uint8List>>{};
  int generated = 0, genMsTotal = 0, loaded = 0;

  Future<Uint8List> thumb(int i) async {
    final key = 'thumb:$i:${source == null ? 'line' : 'map'}';
    final have = await thumbStore.read(key);
    if (have != null) {
      loaded++;
      return have;
    }
    final t = Stopwatch()..start();
    final s = source;
    final png = await renderThumb(syntheticRun(i + 1), w: 480, h: 240, theme: s?.theme, tiles: s == null ? null : (z, x, y) => s.tile(z, x, y));
    await thumbStore.write(key, png);
    generated++;
    genMsTotal += t.elapsedMilliseconds;
    log('thumb gen ms=${t.elapsedMilliseconds} png_bytes=${png.length} generated=$generated avg_ms=${genMsTotal ~/ generated}');
    return png;
  }

  @override
  void initState() {
    super.initState();
    if (cfg.queryParameters['auto'] == '1') {
      Future.delayed(const Duration(seconds: 5), () async {
        for (var k = 0; k < 3; k++) {
          await sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(seconds: 8), curve: Curves.linear);
          await sc.animateTo(0, duration: const Duration(seconds: 8), curve: Curves.linear);
        }
        log('autoscroll_done generated=$generated loaded=$loaded');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView.builder(
          controller: sc,
          itemCount: n,
          itemExtent: 112,
          itemBuilder: (c, i) => ListTile(
            leading: SizedBox(
              width: 160,
              height: 80,
              child: FutureBuilder(
                future: cache.putIfAbsent(i, () => thumb(i)),
                builder: (c, s) => s.hasData ? Image.memory(s.data!, gaplessPlayback: true) : const ColoredBox(color: Color(0xFFE0E0E0)),
              ),
            ),
            title: Text('Lauf ${i + 1}'),
            subtitle: Text(source == null ? 'ohne Karte' : attribution, style: const TextStyle(fontSize: 9)),
          ),
        ),
      );
}
