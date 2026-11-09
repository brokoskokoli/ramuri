// WP13 B: Routenkarte im Adapter (R008 Hinweis 1, 2, 5). Alles ohne Netz: ein Fake hinter dem Tor zeichnet jede
// Anfrage auf.
import 'dart:io';
import 'dart:math' as math;

import 'package:adapters/adapters.dart';
import 'package:core/core.dart' show RoutePoint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'map_fakes.dart';

const _style = RouteMapStyle(
  lineColor: Color(0xFF112233),
  startColor: Color(0xFF00AA00),
  endColor: Color(0xFFAA0000),
  markerBorderColor: Color(0xFFFFFFFF),
  backgroundColor: Color(0xFFEEEEEE),
  attributionBackground: Color(0xCCFFFFFF),
  attributionForeground: Color(0xFF000000),
);

// Etwa 1,2 km mal 0,8 km nahe Berlin.
const _a = RoutePoint(52.5200, 13.4000);
const _b = RoutePoint(52.5230, 13.4100);
const _c = RoutePoint(52.5270, 13.4150);
const _d = RoutePoint(52.5300, 13.4250);
final _route = [
  [_a, _b],
  [_c, _d],
];

(int, int, int)? _tile(Uri u) {
  final m = RegExp(r'^/planet/[^/]+/(\d+)/(\d+)/(\d+)\.pbf$')
      .firstMatch(u.path);
  if (m == null) return null;
  return (int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

(int, int) _xy(double lat, double lon, int z) {
  final n = math.pow(2, z);
  final x = ((lon + 180) / 360 * n).floor();
  final r = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
      .floor();
  return (x, y);
}

/// Kacheln, die weiter als eine Kachel vom Ausschnitt der Route entfernt liegen (Muster `tilesOutside`, R008).
int tilesOutside(Iterable<Uri> urls, List<List<RoutePoint>> route) {
  var out = 0;
  for (final u in urls) {
    final t = _tile(u);
    if (t == null) continue;
    final all = [for (final p in route) ...p];
    final lo = _xy(
      all.map((p) => p.latitude).reduce(math.max),
      all.map((p) => p.longitude).reduce(math.min),
      t.$1,
    );
    final hi = _xy(
      all.map((p) => p.latitude).reduce(math.min),
      all.map((p) => p.longitude).reduce(math.max),
      t.$1,
    );
    if (t.$2 < lo.$1 - 1 ||
        t.$2 > hi.$1 + 1 ||
        t.$3 < lo.$2 - 1 ||
        t.$3 > hi.$2 + 1) {
      out++;
    }
  }
  return out;
}

Iterable<Uri> _tiles(FakeInner i) =>
    i.requests.map((r) => r.url).where((u) => _tile(u) != null);

/// Wartet (echte Zeit), bis das Netz zur Ruhe kommt, und zeichnet neu.
Future<void> _settle(WidgetTester tester, FakeInner inner) async {
  var last = -1;
  var stable = 0;
  while (stable < 6) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    stable = inner.requests.length == last ? stable + 1 : 0;
    last = inner.requests.length;
  }
}

void main() {
  late FakeInner inner;
  late bool consent;
  late MapGate gate;

  setUp(() {
    vt.VectorTileLayer.clearMemoryCache();
    inner = FakeInner();
    consent = true;
    gate = MapGate(
      provider: MapProvider.openFreeMap,
      consent: () => consent,
      inner: inner,
    );
  });

  Future<MapTileSource> open(WidgetTester tester) async {
    final s = await tester.runAsync(() => MapTileSource.open(gate));
    return s!;
  }

  Widget host(Widget child, {Size size = const Size(480, 240)}) => MaterialApp(
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: size.width, height: size.height, child: child),
    ),
  );

  testWidgets(
    'Startkamera: beim ersten Laden liegt jede Kachel im Ausschnitt der Route, Kacheln gehen über das Tor',
    (tester) async {
      final source = await open(tester);
      addTearDown(source.dispose);
      await tester.pumpWidget(
        host(RouteMap(source: source, route: _route, style: _style)),
      );
      await _settle(tester, inner);
      final tiles = _tiles(inner).toList();
      expect(tiles, isNotEmpty);
      expect(tilesOutside(tiles, _route), 0, reason: 'Fremdkacheln');
      // R008 Hinweis 1 am echten Widget: Kacheln zählen am Tor.
      expect(gate.counts.network[MapResource.tile], greaterThan(0));
    },
  );

  testWidgets('Gegenprobe: nur initialCameraFit lädt Fremdkacheln', (
    tester,
  ) async {
    final source = await open(tester);
    addTearDown(source.dispose);
    final bounds = fm.LatLngBounds.fromPoints([
      for (final p in [for (final x in _route) ...x])
        LatLng(p.latitude, p.longitude),
    ]);
    await tester.pumpWidget(
      host(
        fm.FlutterMap(
          options: fm.MapOptions(
            initialCameraFit: fm.CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.all(32),
            ),
          ),
          children: [source.layer()],
        ),
      ),
    );
    await _settle(tester, inner);
    expect(
      tilesOutside(_tiles(inner), _route),
      greaterThan(0),
      reason: 'die Gegenprobe muss Fremdkacheln zeigen, sonst prüft der Test nichts',
    );
  });

  testWidgets('ohne bekannte Größe keine Kachelebene und keine Anfrage', (
    tester,
  ) async {
    final source = await open(tester);
    addTearDown(source.dispose);
    // Unbegrenzte Höhe (ungebundenes Scrollen) und Größe 0: beide ohne Kachelebene.
    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(
          child: RouteMap(source: source, route: _route, style: _style),
        ),
      ),
    );
    await _settle(tester, inner);
    await tester.pumpWidget(
      host(
        RouteMap(source: source, route: _route, style: _style),
        size: const Size(0, 0),
      ),
    );
    await _settle(tester, inner);
    expect(_tiles(inner), isEmpty);
    expect(find.byType(fm.FlutterMap), findsNothing);
  });

  testWidgets(
    'Teilstücke sind getrennte Polylines, Start und Ende markiert, Quellenangabe sichtbar',
    (tester) async {
      final source = await open(tester);
      addTearDown(source.dispose);
      await tester.pumpWidget(
        host(RouteMap(source: source, route: _route, style: _style)),
      );
      await _settle(tester, inner);
      final lines = tester
          .widget<fm.PolylineLayer>(find.byType(fm.PolylineLayer))
          .polylines;
      expect(lines.length, 2, reason: 'Lücke nie verbinden');
      expect(lines[0].points.length, 2);
      expect(lines[1].points.length, 2);
      expect(lines[0].color, _style.lineColor);
      final circles = tester
          .widgetList<fm.CircleLayer>(find.byType(fm.CircleLayer))
          .expand((l) => l.circles)
          .toList();
      expect(
        circles.map((c) => c.color).toSet(),
        containsAll([_style.startColor, _style.endColor]),
      );
      expect(
        circles.firstWhere((c) => c.color == _style.startColor).point,
        LatLng(_a.latitude, _a.longitude),
      );
      expect(
        circles.firstWhere((c) => c.color == _style.endColor).point,
        LatLng(_d.latitude, _d.longitude),
      );
      expect(find.byKey(const Key('map_attribution')), findsOneWidget);
      expect(find.text(MapProvider.openFreeMap.attribution), findsOneWidget);
      // Nicht verdeckbar: kein Tippziel.
      expect(
        find.descendant(
          of: find.byKey(const Key('map_attribution')),
          matching: find.byType(IgnorePointer),
        ),
        findsWidgets,
      );
    },
  );

  testWidgets('Kilometermarken liegen über Start und Ende (Runde 4)', (
    tester,
  ) async {
    final source = await open(tester);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      host(
        RouteMap(
          source: source,
          route: _route,
          style: _style,
          marks: [RouteMapMark(index: 2, position: _d)],
        ),
      ),
    );
    await _settle(tester, inner);
    final layers = tester
        .widget<fm.FlutterMap>(find.byType(fm.FlutterMap))
        .children;
    final endLayer = layers.indexWhere(
      (l) =>
          l is fm.CircleLayer &&
          l.circles.any((c) => c.color == _style.endColor),
    );
    final markLayer = layers.indexWhere((l) => l is fm.MarkerLayer);
    expect(endLayer, isNonNegative);
    expect(
      markLayer,
      greaterThan(endLayer),
      reason: 'später gezeichnet = oben',
    );
  });

  testWidgets('Fehler des Anbieters (500): Linie bleibt in der Karte', (
    tester,
  ) async {
    final source = await open(tester);
    addTearDown(source.dispose);
    inner.forceStatus = 500;
    await tester.pumpWidget(
      host(RouteMap(source: source, route: _route, style: _style)),
    );
    await _settle(tester, inner);
    expect(_tiles(inner), isNotEmpty);
    expect(
      tester.widget<fm.PolylineLayer>(find.byType(fm.PolylineLayer)).polylines,
      hasLength(2),
    );
  });

  testWidgets(
    'Widerruf bei offener Karte: danach keine Anfrage mehr, Linie bleibt',
    (tester) async {
      final source = await open(tester);
      addTearDown(source.dispose);
      final controller = fm.MapController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        host(
          RouteMap(
            source: source,
            route: _route,
            style: _style,
            gestures: RouteMapGestures.full,
            mapController: controller,
          ),
        ),
      );
      await _settle(tester, inner);
      // Positivkontrolle: mit Einwilligung löst Bedienen (Verschieben) neue Anfragen aus.
      final start = inner.requests.length;
      controller.move(const LatLng(52.60, 13.60), 14);
      await _settle(tester, inner);
      final granted = inner.requests.length;
      expect(granted, greaterThan(start));
      consent = false;
      controller.move(const LatLng(52.70, 13.80), 14);
      await _settle(tester, inner);
      expect(
        inner.requests.length,
        granted,
        reason: 'nach Widerruf keine Anfrage',
      );
      expect(
        tester
            .widget<fm.PolylineLayer>(find.byType(fm.PolylineLayer))
            .polylines,
        hasLength(2),
      );
    },
  );

  group('Gesten in einer scrollbaren Seite', () {
    Future<(fm.MapController, ScrollController)> pumpInList(
      WidgetTester tester,
      MapTileSource source,
      RouteMapGestures gestures,
    ) async {
      final map = fm.MapController();
      final scroll = ScrollController();
      addTearDown(map.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ListView(
            controller: scroll,
            children: [
              SizedBox(
                height: 240,
                child: RouteMap(
                  source: source,
                  route: _route,
                  style: _style,
                  gestures: gestures,
                  mapController: map,
                ),
              ),
              const SizedBox(height: 2000),
            ],
          ),
        ),
      );
      await _settle(tester, inner);
      return (map, scroll);
    }

    testWidgets('ein Finger scrollt die Seite, die Karte bleibt stehen', (
      tester,
    ) async {
      final source = await open(tester);
      addTearDown(source.dispose);
      final (map, scroll) = await pumpInList(
        tester,
        source,
        RouteMapGestures.twoFinger,
      );
      final cam = map.camera;
      await tester.drag(find.byType(RouteMap), const Offset(0, -150));
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.offset, greaterThan(100));
      expect(map.camera.center, cam.center);
      expect(map.camera.zoom, cam.zoom);
      // Auch waagerechtes Ziehen verschiebt die Karte nicht.
      await tester.drag(find.byType(RouteMap), const Offset(-120, 0));
      await tester.pump(const Duration(seconds: 1));
      expect(map.camera.center, cam.center);
    });

    testWidgets('zwei Finger zoomen und verschieben die Karte', (tester) async {
      final source = await open(tester);
      addTearDown(source.dispose);
      final (map, _) = await pumpInList(
        tester,
        source,
        RouteMapGestures.twoFinger,
      );
      final cam = map.camera;
      final c = tester.getCenter(find.byType(RouteMap));
      final a = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
      for (var i = 1; i <= 10; i++) {
        await a.moveTo(c - Offset(20.0 + 10 * i, 0));
        await b.moveTo(c + Offset(20.0 + 10 * i, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pump(const Duration(seconds: 1));
      expect(map.camera.zoom, greaterThan(cam.zoom));
    });

    testWidgets('ohne Gesten (Miniatur, D) bewegt sich nichts', (tester) async {
      final source = await open(tester);
      addTearDown(source.dispose);
      final (map, _) = await pumpInList(tester, source, RouteMapGestures.none);
      final cam = map.camera;
      final c = tester.getCenter(find.byType(RouteMap));
      final a = await tester.startGesture(c - const Offset(20, 0), pointer: 1);
      final b = await tester.startGesture(c + const Offset(20, 0), pointer: 2);
      for (var i = 1; i <= 10; i++) {
        await a.moveTo(c - Offset(20.0 + 10 * i, 0));
        await b.moveTo(c + Offset(20.0 + 10 * i, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await tester.pump(const Duration(seconds: 1));
      expect(map.camera.zoom, cam.zoom);
      expect(map.camera.center, cam.center);
    });
  });

  testWidgets('nach der Kartenansicht keine Datei außerhalb des Speichers', (
    tester,
  ) async {
    // Alle Verzeichnisse, die path_provider liefern könnte (Plattencache der Bibliothek), zeigen auf ein leeres
    // Verzeichnis; danach muss es leer sein (R008 Hinweis 2).
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('route_map_scan'),
    ))!;
    addTearDown(() => dir.deleteSync(recursive: true));
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      ),
    );
    final source = await open(tester);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      host(RouteMap(source: source, route: _route, style: _style)),
    );
    await _settle(tester, inner);
    expect(_tiles(inner), isNotEmpty);
    final left = await tester.runAsync(
      () => dir.list(recursive: true).map((e) => e.path).toList(),
    );
    expect(left, isEmpty, reason: 'Plattencache muss aus sein');
  });

  // WP13 C: Live-Karte. Ohne Position keine Kachelebene (R008 Hinweis 5), mit Position nur Kacheln um sie.
  testWidgets('LiveRouteMap ohne Position: keine Kachelebene, keine Anfrage', (
    tester,
  ) async {
    final source = await open(tester);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      host(
        LiveRouteMap(
          source: source,
          route: const [],
          position: null,
          following: true,
          onUserMove: () {},
          style: _style,
        ),
      ),
    );
    await _settle(tester, inner);
    expect(_tiles(inner), isEmpty);
    expect(find.byType(fm.FlutterMap), findsNothing);
    expect(gate.counts.network[MapResource.tile] ?? 0, 0);
  });

  testWidgets('LiveRouteMap mit Position: nur Kacheln um sie, Punkt markiert', (
    tester,
  ) async {
    final source = await open(tester);
    addTearDown(source.dispose);
    await tester.pumpWidget(
      host(
        LiveRouteMap(
          source: source,
          route: [
            [_a, _b],
          ],
          position: _b,
          following: true,
          onUserMove: () {},
          style: _style,
        ),
      ),
    );
    await _settle(tester, inner);
    final tiles = _tiles(inner).toList();
    expect(tiles, isNotEmpty);
    expect(
      tilesOutside(tiles, [
        [_b],
      ]),
      0,
      reason: 'Fremdkacheln',
    );
    expect(find.text(MapProvider.openFreeMap.attribution), findsOneWidget);
  });
}
