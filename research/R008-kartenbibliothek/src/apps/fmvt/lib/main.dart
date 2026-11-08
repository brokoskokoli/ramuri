// R008 Mini-App fmvt: flutter_map + flutter_map_vector_tiles (ohne Patch) mit OpenFreeMap.
// Routen wie fm: /idle, /live?consent=0|1&page=1, /detail?consent=0|1, /thumbs?consent=0|1&n=50&auto=1
//   plaincache=1  Bibliothek mit Standardwerten (eigener Client, Plattencache 50 MB, Stil-Cache) = Gegenprobe
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import 'ofmvt.dart';
import 'route.dart';
import 'store.dart';
import 'thumbvt.dart';

late final Uri cfg;
late final EncStore tileStore, thumbStore;
GatedClient? client; // nur mit Einwilligung
vt.Style? style;
const attribution = '© OpenFreeMap © OpenMapTiles Daten © OpenStreetMap-Mitwirkende';
bool get plain => cfg.queryParameters['plaincache'] == '1';

void log(String s) => debugPrint('R008 $s');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cfg = Uri.parse(ui.PlatformDispatcher.instance.defaultRouteName);
  final sup = await getApplicationSupportDirectory();
  tileStore = await EncStore.open(Directory('${sup.path}/map-tiles'), maxBytes: 50 << 20);
  thumbStore = await EncStore.open(Directory('${sup.path}/map-thumbs'), maxBytes: 20 << 20);
  try {
    client = GatedClient.create(consent: cfg.queryParameters['consent'] == '1', store: tileStore);
    final t = Stopwatch()..start();
    style = await loadStyle(client!, plain: plain);
    log('style_loaded ms=${t.elapsedMilliseconds} plain=$plain');
  } on ConsentMissing {
    log('no_consent -> Linie ohne Karte');
  } catch (e) {
    log('source_error ${e.runtimeType} -> Linie ohne Karte');
    style = null;
  }
  Timer.periodic(const Duration(seconds: 10), (_) async {
    log('stats net_req=${client?.netRequests ?? 0} net_bytes=${client?.netBytes ?? 0} store_hits=${client?.storeHits ?? 0} '
        'tile_store=${await tileStore.size()} thumb_store=${await thumbStore.size()}');
  });
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) {
    final page = switch (cfg.path) {
      '/live' => const LivePage(),
      '/detail' => const DetailPage(),
      '/thumbs' => const ThumbsPage(),
      _ => const Scaffold(body: Center(child: Text('R008 fmvt idle'))),
    };
    return MaterialApp(home: page, debugShowCheckedModeBanner: false);
  }
}

List<LatLng> ll(List<P> p) => [for (final q in p) LatLng(q.lat, q.lon)];
List<Widget> baseLayers() => style == null ? const [] : [vtLayer(style!, plain: plain)];

Widget attributionLayer() => style == null
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
  int i = 1, frames = 0;
  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((ts) => frames += ts.length);
    Timer.periodic(const Duration(seconds: 1), (_) {
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
  final offKey = GlobalKey();
  int? offRun; // Lauf, dessen Karte gerade unsichtbar gerendert wird
  Future<void> queue = Future.value(); // Schnappschuesse nacheinander
  int generated = 0, genMsTotal = 0, loaded = 0, timeouts = 0;

  Future<Uint8List> thumb(int i) async {
    final key = 'thumb:$i:${style == null ? 'line' : 'map'}';
    final have = await thumbStore.read(key);
    if (have != null) {
      loaded++;
      return have;
    }
    final done = Completer<Uint8List>();
    queue = queue.then((_) async {
      final t = Stopwatch()..start();
      setState(() => offRun = i);
      await SchedulerBinding.instance.endOfFrame;
      final (png, idle) = await snapshot(offKey, client);
      setState(() => offRun = null);
      await thumbStore.write(key, png);
      generated++;
      if (!idle) timeouts++;
      genMsTotal += t.elapsedMilliseconds;
      log('thumb gen ms=${t.elapsedMilliseconds} png_bytes=${png.length} idle=$idle generated=$generated avg_ms=${genMsTotal ~/ generated}');
      done.complete(png);
    });
    return done.future;
  }

  // Grobe Bildrate der Historie: Flutter-FrameTiming je 5 s (Bilder, mittlere Build-/Raster-Zeit, Bilder ueber 16,7 ms)
  int fr = 0, slow = 0, buildUs = 0, rasterUs = 0;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback((ts) {
      for (final t in ts) {
        fr++;
        buildUs += t.buildDuration.inMicroseconds;
        rasterUs += t.rasterDuration.inMicroseconds;
        if (t.totalSpan.inMicroseconds > 16667) slow++;
      }
    });
    Timer.periodic(const Duration(seconds: 5), (_) {
      log('thumbs frames_5s=$fr build_ms=${fr == 0 ? 0 : (buildUs / fr / 1000).toStringAsFixed(1)} raster_ms=${fr == 0 ? 0 : (rasterUs / fr / 1000).toStringAsFixed(1)} over16ms=$slow');
      fr = slow = buildUs = rasterUs = 0;
    });
    if (cfg.queryParameters['auto'] == '1') {
      Future.delayed(const Duration(seconds: 5), () async {
        for (var k = 0; k < 3; k++) {
          await sc.animateTo(sc.position.maxScrollExtent, duration: const Duration(seconds: 8), curve: Curves.linear);
          await sc.animateTo(0, duration: const Duration(seconds: 8), curve: Curves.linear);
        }
        await queue;
        log('autoscroll_done generated=$generated loaded=$loaded timeouts=$timeouts');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Stack(children: [
          if (offRun != null)
            Positioned(left: -2 * thumbW, top: 0, child: thumbMap(ll(syntheticRun(offRun! + 1)), style, offKey)),
          ListView.builder(
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
              subtitle: Text(style == null ? 'ohne Karte' : attribution, style: const TextStyle(fontSize: 9)),
            ),
          ),
        ]),
      );
}
