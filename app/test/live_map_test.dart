// WP13 C: Kartenseite des Lauf-Bildschirms (FR-0204): Einwilligung erst beim Wechsel, Kachelebene erst mit Position,
// Folgen/Zentrieren, nichts bei Werte-Seite und Hintergrund, Rückfall auf die Linie. Ohne Netz: ein Fake hinter dem
// Tor zählt jede Anfrage. Die Aufzeichnung läuft über Fakes (ADR-0005: die Karte kennt sie nicht, sie die Karte nicht).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:adapters/adapters.dart';
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_consent_scope.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/run/live_map_page.dart';
import 'package:running_app/features/run/live_run_view.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

class _Consents implements ConsentStore {
  final Map<String, ConsentState> data = {};
  @override
  Future<ConsentState?> get(String k) async => data[k];
  @override
  Future<Map<String, ConsentState>> all() async => Map.of(data);
  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async =>
      data[k] = s;
}

class _Cache implements MapCacheAdmin {
  @override
  Future<int> sizeBytes() async => 0;
  @override
  Future<void> delete() async {}
}

const _fmt = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'de',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

/// Lauf mit Karte: Uhr, Fakes für Speicher und Standort, Tor mit Fake-Netz.
class _World {
  _World({FakeInner? net, ConsentState? consent}) : inner = net ?? FakeInner() {
    if (consent != null) consents.data[mapProviderSourceKey] = consent;
    map = MapConsentController(
      store: consents,
      clock: clock,
      services: MapServices(
        gate: (c) => MapGate(
          provider: MapProvider.openFreeMap,
          consent: c,
          inner: inner,
        ),
        cache: _Cache(),
        attribution: MapProvider.openFreeMap.attribution,
      ),
    );
    holder = MapConsentHolder()..bind(map);
  }

  final FakeInner inner;
  final clock = FakeClock(DateTime.utc(2030, 1, 1, 12));
  final location = FakeLocationSource();
  final consents = _Consents();
  late final MapConsentController map;
  late final MapConsentHolder holder;
  late final RunController run;
  int _i = 0;

  int get requests => inner.requests.length;
  List<Uri> get tiles => [
    for (final r in inner.requests)
      if (r.url.path.endsWith('.pbf')) r.url,
  ];

  Future<void> startRun() async {
    final session = await FakeStorage().open(Uint8List(32));
    _worlds.add(this);
    run = RunController(
      clock: clock,
      storage: session,
      location: location,
      tickEvery: const Duration(seconds: 1),
    );
    await run.start();
  }

  /// Ein Punkt je Sekunde nach Norden (rund 3 m/s) und ein Tick der Anzeige.
  Future<void> step(WidgetTester tester, {int n = 1}) async {
    for (var k = 0; k < n; k++) {
      clock.advance(const Duration(seconds: 1));
      location.emit(
        LocationSample(
          time: clock.now(),
          latitude: 50 + _i * 0.000027,
          longitude: 8,
          accuracyMeters: 5,
        ),
      );
      _i++;
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Zeit vergeht ohne Position (Lücke).
  Future<void> silence(WidgetTester tester, int seconds) async {
    for (var k = 0; k < seconds; k++) {
      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  double get lat => 50 + (_i - 1) * 0.000027;
}

Widget _app(_World w, {ThemeData? theme}) => MaterialApp(
  locale: const Locale('de'),
  theme: theme ?? RamuriTheme.light,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: MapConsentScope(
    holder: w.holder,
    child: ListenableBuilder(
      listenable: w.run,
      builder: (context, _) => LiveRunView(controller: w.run, formatter: _fmt),
    ),
  ),
);

final List<_World> _worlds = [];

/// Wie testWidgets; danach wird die Anzeige abgebaut und der Lauf beendet (sein Takt darf nicht überleben).
void _testRun(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final w in _worlds) {
        w.run.dispose();
      }
      _worlds.clear();
    }
  });
}

Future<void> _toMap(WidgetTester tester) async {
  await tester.tap(key('run_tab_1'));
  await tester.pumpAndSettle();
}

Future<void> _toValues(WidgetTester tester) async {
  await tester.tap(key('run_tab_0'));
  await tester.pumpAndSettle();
}

({double lat, double lon, double zoom}) _camera(WidgetTester tester) =>
    mapCameraOf(tester.element(key('live_route_map')));

/// Kachel (x, y) der Position bei Zoom z.
(int, int) _tileOf(double lat, double lon, int z) {
  final n = math.pow(2, z).toDouble();
  final x = ((lon + 180) / 360 * n).floor();
  final r = lat * math.pi / 180;
  final y = ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
      .floor();
  return (x, y);
}

void main() {
  setUp(() => clearMapMemoryCache());

  group('Einwilligung', () {
    _testRun('nicht beim Laufstart, erst beim Wechsel auf die Karte', (
      tester,
    ) async {
      final w = _World();
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await tester.pump(const Duration(seconds: 1));
      await w.step(tester, n: 3);
      expect(key('map_consent_dialog'), findsNothing, reason: 'Werte-Seite');
      expect(w.requests, 0);
      await tester.tap(key('run_tab_1'));
      await tester.pumpAndSettle();
      expect(key('map_consent_dialog'), findsOneWidget);
      expect(w.requests, 0, reason: 'vor der Antwort keine Anfrage');
    });

    _testRun(
      'der Dialog bremst den Lauf nicht und verdeckt Pause nicht dauerhaft',
      (tester) async {
        final w = _World();
        await w.startRun();
        await tester.pumpWidget(_app(w));
        await tester.tap(key('run_tab_1'));
        await tester.pumpAndSettle();
        expect(key('map_consent_dialog'), findsOneWidget);
        // Der Lauf läuft hinter dem Dialog weiter: Zeit und Punkte kommen an.
        final before = w.run.snapshot.totalTime!;
        await w.step(tester, n: 5);
        expect(w.run.snapshot.totalTime! - before, greaterThan(Duration.zero));
        expect(w.run.hasFix, isTrue);
        // Tippen neben den Dialog schließt ihn ("Nicht jetzt"); dann ist Pause erreichbar.
        await tester.tapAt(const Offset(4, 4));
        await tester.pumpAndSettle();
        expect(key('map_consent_dialog'), findsNothing);
        await tester.tap(key('live_map_pause'));
        await tester.pump();
        expect(w.run.phase, RecordingPhase.paused);
        expect(key('live_map_resume'), findsOneWidget);
        expect(w.requests, 0, reason: 'ohne Einwilligung keine Anfrage');
      },
    );

    _testRun('abgelehnt: Linie mit Position und gleichem Blatt, 0 Anfragen', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.revoked);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await w.step(tester, n: 20);
      await _toMap(tester);
      await w.step(tester, n: 2);
      expect(key('map_consent_dialog'), findsNothing);
      expect(key('live_route_map'), findsNothing);
      expect(key('live_map_line'), findsOneWidget);
      expect(key('live_map_sheet'), findsOneWidget);
      expect(find.text(formatClock(w.run.snapshot.totalTime)), findsWidgets);
      expect(w.requests, 0);
    });
  });

  group('Kachelebene erst mit Position (ADR-0009 Punkt 2)', () {
    _testRun('keine Position: 0 Kacheln und keine Karte', (tester) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await _toMap(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsNothing);
      expect(key('live_map_waiting'), findsOneWidget);
      expect(w.tiles, isEmpty);
      await w.silence(tester, 5);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.tiles, isEmpty, reason: 'auch nach Zeit ohne Position');
    });

    _testRun('erste Position: nur Kacheln um sie, Quellenangabe sichtbar', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await _toMap(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.tiles, isEmpty);
      await w.step(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsOneWidget);
      expect(w.tiles, isNotEmpty);
      for (final u in w.tiles) {
        final seg = u.pathSegments;
        final z = int.parse(seg[seg.length - 3]);
        final x = int.parse(seg[seg.length - 2]);
        final y = int.parse(seg.last.replaceAll('.pbf', ''));
        final (px, py) = _tileOf(50, 8, z);
        expect(
          (x - px).abs() <= 2 && (y - py).abs() <= 2,
          isTrue,
          reason: 'Kachel z$z nur um die Position, nicht am Standardzentrum',
        );
      }
      expect(
        find.text(MapProvider.openFreeMap.attribution),
        findsOneWidget,
        reason: 'Quellenangabe sichtbar',
      );
    });
  });

  group('Folgen und Zentrieren', () {
    _testRun('folgt der Position; Verschieben stoppt, Zentrieren stellt her', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await _toMap(tester);
      await w.step(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_map_center'), findsNothing, reason: 'folgt noch');
      final c0 = _camera(tester);
      expect(c0.lat, closeTo(50, 1e-6));

      // Folgt: nach 60 Punkten (~180 m) steht die Mitte auf der neuen Position.
      await w.step(tester, n: 60);
      await tester.pump();
      expect(_camera(tester).lat, closeTo(w.lat, 1e-5));

      // Ein Finger verschiebt die Karte: Folgen endet, der Knopf erscheint, die Seite bleibt.
      await tester.drag(key('live_route_map'), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(key('live_map_center'), findsOneWidget);
      expect(
        tester.getTopLeft(key('run_page_map')).dx,
        0,
        reason: 'die Seite wischt nicht mit',
      );
      final moved = _camera(tester);
      expect(moved.lon, greaterThan(8), reason: 'Karte nach links gezogen');

      await w.step(tester, n: 60);
      await tester.pump();
      expect(
        _camera(tester).lat,
        closeTo(moved.lat, 1e-9),
        reason: 'Kamera folgt nicht mehr',
      );
      expect(_camera(tester).lon, closeTo(moved.lon, 1e-9));

      // Tippen stellt das Folgen wieder her.
      await tester.tap(key('live_map_center'));
      await tester.pump();
      await tester.pump();
      expect(key('live_map_center'), findsNothing);
      expect(_camera(tester).lat, closeTo(w.lat, 1e-5));
      expect(_camera(tester).lon, closeTo(8, 1e-5));
    });

    _testRun(
      'Wischen und Verschieben: auf der Karte verschiebt ein Zug, vom Rand geht es zurück',
      (tester) async {
        final w = _World(consent: ConsentState.granted);
        await w.startRun();
        await tester.pumpWidget(_app(w));
        await w.step(tester, n: 3);
        // Werte-Seite: Wisch nach links öffnet die Karte.
        await tester.fling(key('run_pages'), const Offset(-300, 0), 1500);
        await tester.pumpAndSettle();
        expect(key('run_page_map'), findsOneWidget);
        expect(tester.getTopLeft(key('run_page_map')).dx, 0);
        await settleUntilRequestsStable(tester, () => w.requests);
        final before = _camera(tester);
        // Ein Zug von rechts nach links verschiebt die Karte, die Seite wechselt nicht.
        // Langsam wie ein Finger (kleine Schritte): so entscheiden die Erkennungen den Streit um den Zug.
        final g = await tester.startGesture(
          tester.getCenter(key('live_route_map')),
        );
        for (var i = 0; i < 40; i++) {
          await g.moveBy(const Offset(-5, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        expect(
          tester.getTopLeft(key('run_page_map')).dx,
          0,
          reason: 'während des Zugs wischt die Seite nicht',
        );
        await g.up();
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(key('run_page_map')).dx, 0);
        expect(_camera(tester).lon, isNot(closeTo(before.lon, 1e-7)));
        // Ein Zug von links nach rechts in der Mitte verschiebt ebenfalls (kein Rückwisch).
        await tester.fling(key('live_route_map'), const Offset(200, 0), 1500);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(key('run_page_map')).dx, 0);
        // Vom linken Rand zurück zur Werte-Seite.
        final map = tester.getRect(key('live_route_map'));
        await tester.flingFrom(
          Offset(6, map.center.dy),
          const Offset(300, 0),
          1500,
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('run_page_map'), skipOffstage: false),
          findsOneWidget,
          reason: 'die Kartenseite behält ihren Zustand (Quelle, Folgen)',
        );
        expect(key('live_route_map'), findsNothing, reason: 'nicht sichtbar');
        expect(key('run_pause'), findsOneWidget, reason: 'Werte-Seite');
      },
    );
  });

  group('Seitenwechsel', () {
    _testRun(
      'Wisch auf dem Blatt führt zurück; Werte und Pause bleiben unberührt',
      (tester) async {
        final w = _World(consent: ConsentState.granted);
        await w.startRun();
        await tester.pumpWidget(_app(w));
        await w.step(tester, n: 10);
        await _toMap(tester);
        await tester.tap(key('live_map_pause'));
        await tester.pump();
        expect(w.run.phase, RecordingPhase.paused);
        final time = w.run.snapshot.totalTime;
        await tester.fling(key('live_map_sheet'), const Offset(300, 0), 1500);
        await tester.pumpAndSettle();
        expect(
          key('run_resume'),
          findsOneWidget,
          reason: 'Werte-Seite, pausiert',
        );
        expect(
          w.run.phase,
          RecordingPhase.paused,
          reason: 'Seitenwechsel ändert nichts',
        );
        expect(w.run.snapshot.totalTime, time);
        expect(key('run_banner_paused'), findsOneWidget);
        // Und wieder hin: der Zustand der Pause steht auch auf dem Blatt.
        await tester.fling(key('run_pages'), const Offset(-300, 0), 1500);
        await tester.pumpAndSettle();
        expect(key('live_map_resume'), findsOneWidget);
      },
    );
  });

  group('Zeichnen nur sichtbar und im Vordergrund', () {
    _testRun('Werte-Seite: keine Karte, keine Anfragen, einmal aufholen', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await w.step(tester, n: 3);
      await _toMap(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsOneWidget);
      await _toValues(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsNothing);
      final requests = w.requests;
      final builds = liveMapRouteBuilds;
      await w.step(tester, n: 120);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, requests, reason: 'keine Anfrage auf der Werte-Seite');
      expect(liveMapRouteBuilds, builds, reason: 'Strecke nicht neu berechnet');
      expect(key('live_route_map'), findsNothing);
      // Zurück: einmal aufholen, Karte steht auf der aktuellen Position.
      await _toMap(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(liveMapRouteBuilds, builds + 1);
      expect(
        w.inner.count((u) => u.path.startsWith('/styles/')),
        1,
        reason: 'die Quelle bleibt offen, kein neuer Stil',
      );
      expect(_camera(tester).lat, closeTo(w.lat, 1e-5));
      final live = tester.widget<LiveRouteMap>(key('live_route_map'));
      expect(live.route.expand((p) => p).length, greaterThan(100));
    });

    _testRun('Hintergrund und Bildschirm aus: nichts, danach aufholen', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await w.step(tester, n: 3);
      await _toMap(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(key('live_route_map'), findsNothing);
      final requests = w.requests;
      final builds = liveMapRouteBuilds;
      await w.step(tester, n: 120);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, requests);
      expect(liveMapRouteBuilds, builds);
      // Die Aufzeichnung lief weiter.
      expect(w.run.snapshot.distanceMeters, greaterThan(300));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsOneWidget);
      expect(liveMapRouteBuilds, builds + 1);
      expect(_camera(tester).lat, closeTo(w.lat, 1e-5));
    });
  });

  group('Strecke', () {
    _testRun('Lücke und Pause trennen, nichts wird verbunden', (tester) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await _toMap(tester);
      await w.step(tester, n: 30);
      await settleUntilRequestsStable(tester, () => w.requests);
      List<List<RoutePoint>> parts() =>
          tester.widget<LiveRouteMap>(key('live_route_map')).route;
      expect(parts(), hasLength(1));
      // Pause über das Blatt.
      await tester.tap(key('live_map_pause'));
      await tester.pump();
      await w.silence(tester, 20);
      await tester.tap(key('live_map_resume'));
      await tester.pump();
      await w.step(tester, n: 30);
      expect(parts(), hasLength(2), reason: 'Pause trennt');
      // GPS-Lücke: 40 s ohne Position.
      await w.silence(tester, 40);
      await w.step(tester, n: 30);
      expect(parts(), hasLength(3), reason: 'Lücke trennt zusätzlich');
      for (var i = 1; i < parts().length; i++) {
        expect(
          parts()[i - 1].last.latitude,
          lessThan(parts()[i].first.latitude),
        );
      }
    });

    _testRun('lange Läufe: die Punktzahl ist begrenzt, die Daten nicht', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await _toMap(tester);
      await w.step(tester);
      // 3000 Punkte ohne Bild dazwischen, dann ein Tick.
      for (var i = 0; i < 3000; i++) {
        w.clock.advance(const Duration(seconds: 1));
        w.location.emit(
          LocationSample(
            time: w.clock.now(),
            latitude: 50 + (i + 1) * 0.000027,
            longitude: 8,
            accuracyMeters: 5,
          ),
        );
        await tester.idle(); // die Standortmeldung zustellen, ohne Bild
      }
      await tester.pump(const Duration(seconds: 1));
      await settleUntilRequestsStable(tester, () => w.requests);
      final live = tester.widget<LiveRouteMap>(key('live_route_map'));
      final shown = live.route.fold<int>(0, (n, p) => n + p.length);
      expect(shown, lessThanOrEqualTo(liveMapMaxPoints + live.route.length));
      expect(
        w.run.preprocessing!.position.acceptedPoints.length,
        greaterThan(2900),
        reason: 'die Daten bleiben vollständig',
      );
    });
  });

  group('Fehler und Widerruf', () {
    _testRun('Tor-Fehler ändern den Aufzeichnungszustand nicht', (
      tester,
    ) async {
      final w = _World(net: ThrowingInner(), consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await _toMap(tester);
      await w.step(tester, n: 20);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsNothing, reason: 'Quelle fehlt');
      expect(key('live_map_line'), findsOneWidget, reason: 'Linie bleibt');
      expect(w.run.phase, RecordingPhase.running);
      expect(w.run.writeFailure, isNull);
      expect(w.run.serviceFailed, isFalse);
      expect(w.run.locationError, isFalse);
      expect(w.run.hasFix, isTrue);
      expect(w.run.snapshot.distanceMeters, greaterThan(40));
      expect(w.run.snapshot.gaps, isEmpty);
    });

    for (final mode in ['Flugmodus', '404']) {
      _testRun(
        'alle Kacheln scheitern ($mode, Stil vorhanden): Linie mit Position und Blatt, keine Karte',
        (tester) async {
          final net = FakeInner();
          if (mode == '404') {
            net.statusWhere = (u) => u.path.endsWith('.pbf') ? 404 : null;
          } else {
            net.failWhere = (u) => u.path.endsWith('.pbf');
          }
          final w = _World(net: net, consent: ConsentState.granted);
          await w.startRun();
          await tester.pumpWidget(_app(w));
          await _toMap(tester);
          await w.step(tester, n: 20);
          await settleUntilRequestsStable(tester, () => w.requests);
          expect(w.tiles, isNotEmpty, reason: 'Kacheln wurden versucht');
          // Rückfall (FR-0204): Linie mit Position und Blatt, keine Karte, keine Quellenangabe.
          expect(key('live_route_map'), findsNothing);
          expect(key('live_map_line'), findsOneWidget);
          expect(find.text(MapProvider.openFreeMap.attribution), findsNothing);
          expect(key('live_map_sheet'), findsOneWidget);
          expect(w.run.phase, RecordingPhase.running);
          expect(w.run.writeFailure, isNull);
        },
      );
    }

    _testRun(
      'Kachelfehler, dann Hintergrund und Rückkehr bei wieder erreichbarem Netz: die Karte kommt zurück (N10)',
      (tester) async {
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        final net = FakeInner()..failWhere = (u) => u.path.endsWith('.pbf');
        final w = _World(net: net, consent: ConsentState.granted);
        await w.startRun();
        await tester.pumpWidget(_app(w));
        await _toMap(tester);
        await w.step(tester, n: 20);
        await settleUntilRequestsStable(tester, () => w.requests);
        expect(
          key('live_route_map'),
          findsNothing,
          reason: 'Rückfall auf die Linie',
        );
        expect(key('live_map_line'), findsOneWidget);
        net.failWhere = null; // Netz wieder da
        for (final st in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(st);
        }
        await tester.pump();
        await w.step(tester, n: 5);
        await settleUntilRequestsStable(tester, () => w.requests);
        expect(
          key('live_route_map'),
          findsOneWidget,
          reason: 'neuer Versuch bei Rückkehr',
        );
        expect(w.run.phase, RecordingPhase.running);
      },
    );

    _testRun('Widerruf bei offener Karte: Linie, keine Anfrage mehr', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(_app(w));
      await _toMap(tester);
      await w.step(tester, n: 20);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsOneWidget);
      await tester.runAsync(w.map.revoke);
      await tester.pump();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('live_route_map'), findsNothing);
      expect(key('live_map_line'), findsOneWidget);
      final requests = w.requests;
      await w.step(tester, n: 60);
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, requests, reason: 'nach dem Widerruf keine Anfrage');
      expect(w.run.phase, RecordingPhase.running);
    });
  });

  // Bildschirmfoto hell und dunkel mit den echten Schriften. Nur mit SHOT_DIR, sonst nur die Prüfung.
  for (final dark in [false, true]) {
    _testRun('Darstellung ${dark ? 'dunkel' : 'hell'}: Karte, Blatt, Reiter', (
      tester,
    ) async {
      await tester.runAsync(() async {
        // Symbole: die Schrift liegt im Flutter-SDK (sonst Kästchen im Bild).
        final icons = File(
          '${File(Platform.resolvedExecutable).parent.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf',
        );
        if (icons.existsSync()) {
          final loader = FontLoader('MaterialIcons')
            ..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync())),
            );
          await loader.load();
        }
        for (final f in [
          ('Manrope', ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']),
          ('Sora', ['Medium', 'SemiBold', 'Bold']),
        ]) {
          final loader = FontLoader(f.$1);
          for (final weight in f.$2) {
            final data = await File('assets/fonts/${f.$1}-$weight.ttf')
                .readAsBytes();
            loader.addFont(Future.value(ByteData.sublistView(data)));
          }
          await loader.load();
        }
      });
      tester.view.physicalSize = const Size(780, 1688);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final w = _World(consent: ConsentState.granted);
      await w.startRun();
      await tester.pumpWidget(
        RepaintBoundary(
          key: const Key('shot'),
          child: _app(w, theme: dark ? RamuriTheme.dark : RamuriTheme.light),
        ),
      );
      await w.step(tester, n: 80);
      await _toMap(tester);
      await settleUntilRequestsStable(tester, () => w.requests);
      // Blatt unten, Reiter oben links, Quellenangabe in der Karte, nichts ragt über den Rand.
      final screen = tester.getRect(find.byType(Scaffold).first);
      final sheet = tester.getRect(key('live_map_sheet'));
      expect(sheet.bottom, lessThanOrEqualTo(screen.bottom));
      final attr = tester.getRect(
        find.text(MapProvider.openFreeMap.attribution),
      );
      expect(attr.bottom, lessThanOrEqualTo(sheet.top + 0.5));
      expect(tester.getRect(key('run_tab_1')).left, greaterThanOrEqualTo(0));
      final dir = Platform.environment['SHOT_DIR'];
      if (dir != null) {
        await tester.runAsync(() async {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            key('shot'),
          );
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$dir/wp13-c-shot-${dark ? 'dunkel' : 'hell'}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
