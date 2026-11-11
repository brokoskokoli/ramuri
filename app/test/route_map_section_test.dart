// WP13 B: Karte der Route in Zusammenfassung und Detail (FR-0204): Einwilligung beim ersten Öffnen, Rückfall auf
// die Linie, Umschalter, Widerruf bei offener Karte. Ohne Netz: ein Fake hinter dem Tor zählt jede Anfrage.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:adapters/adapters.dart';
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_consent_scope.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/map/route_map_section.dart';
import 'package:running_app/features/summary/run_charts.dart';
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

const _a = RoutePoint(52.5200, 13.4000);
const _b = RoutePoint(52.5230, 13.4100);
const _c = RoutePoint(52.5270, 13.4150);
const _d = RoutePoint(52.5300, 13.4250);
final _route = [
  [_a, _b],
  [_c, _d],
];

class _World {
  _World({FakeInner? net, ConsentState? consent}) {
    inner = net ?? FakeInner();
    if (consent != null) consents.data[mapProviderSourceKey] = consent;
    controller = MapConsentController(
      store: consents,
      clock: FakeClock(DateTime.utc(2026, 6, 1)),
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
    holder = MapConsentHolder()..bind(controller);
  }
  late final FakeInner inner;
  final consents = _Consents();
  late final MapConsentController controller;
  late final MapConsentHolder holder;
  int get requests => inner.requests.length;
  int get tileRequests => inner.count((u) => u.path.endsWith('.pbf'));
}

Widget _app(
  _World? w,
  List<List<RoutePoint>> route, {
  ThemeData? theme,
  bool scope = true,
}) {
  final body = Scaffold(
    body: SingleChildScrollView(
      child: RouteMapSection(
        route: route,
        lineBuilder: (context, map, style) => RunRouteView(
          route: route,
          map: map,
          startColor: style?.startColor,
          endColor: style?.endColor,
        ),
      ),
    ),
  );
  return MaterialApp(
    locale: const Locale('de'),
    theme: theme ?? RamuriTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: w == null || !scope
        ? body
        : MapConsentScope(holder: w.holder, child: body),
  );
}

Widget _host(_World? w, Widget child) {
  final body = Scaffold(body: SingleChildScrollView(child: child));
  return MaterialApp(
    locale: const Locale('de'),
    theme: RamuriTheme.light,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: w == null ? body : MapConsentScope(holder: w.holder, child: body),
  );
}

final _t0 = DateTime.utc(2030);

void main() {
  setUp(() => clearMapMemoryCache());

  testWidgets('ohne verdrahteten Anbieter: nur die Linie, kein Umschalter', (
    tester,
  ) async {
    await tester.pumpWidget(_app(null, _route));
    await tester.pump(const Duration(seconds: 1));
    expect(key('route_paint'), findsOneWidget);
    expect(key('route_view_toggle'), findsNothing);
    expect(key('route_map'), findsNothing);
  });

  testWidgets('erteilt: Karte mit Quellenangabe, Umschalter Linie/Karte', (
    tester,
  ) async {
    final w = _World(consent: ConsentState.granted);
    await tester.pumpWidget(_app(w, _route));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_map'), findsOneWidget);
    expect(key('route_paint'), findsNothing);
    expect(find.text(MapProvider.openFreeMap.attribution), findsOneWidget);
    expect(key('route_view_toggle'), findsOneWidget);
    expect(w.tileRequests, greaterThan(0));
    // Legende bleibt, Start und Ende der Karte.
    expect(key('route_legend_start'), findsOneWidget);

    await tester.tap(find.text('Linie'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(key('route_paint'), findsOneWidget);
    expect(key('route_map'), findsNothing);
    // Ohne Karte keine Quellenangabe.
    expect(find.text(MapProvider.openFreeMap.attribution), findsNothing);

    await tester.tap(find.text('Karte'));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_map'), findsOneWidget);
    expect(find.text(MapProvider.openFreeMap.attribution), findsOneWidget);
  });

  testWidgets(
    'erste Karte fragt: "Nicht jetzt" ergibt Linie, keinen Umschalter, 0 Anfragen',
    (tester) async {
      final w = _World();
      await tester.pumpWidget(_app(w, _route));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      expect(key('map_consent_dialog'), findsOneWidget);
      expect(w.requests, 0, reason: 'vor der Antwort keine Anfrage');
      await tester.tap(key('map_consent_not_now'));
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_paint'), findsOneWidget);
      expect(key('route_view_toggle'), findsNothing);
      expect(key('route_map'), findsNothing);
      expect(w.requests, 0);
    },
  );

  testWidgets('erste Karte fragt: Erteilen zeigt die Karte', (tester) async {
    final w = _World();
    await tester.pumpWidget(_app(w, _route));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(key('map_consent_load'));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_map'), findsOneWidget);
    expect(key('route_view_toggle'), findsOneWidget);
  });

  testWidgets('widerrufen: keine Frage, Linie, 0 Anfragen', (tester) async {
    final w = _World(consent: ConsentState.revoked);
    await tester.pumpWidget(_app(w, _route));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('map_consent_dialog'), findsNothing);
    expect(key('route_paint'), findsOneWidget);
    expect(key('route_view_toggle'), findsNothing);
    expect(w.requests, 0);
  });

  testWidgets('Anbieter antwortet 500: Linie, kein Umschalter', (tester) async {
    final inner = FakeInner()..forceStatus = 500;
    final w = _World(net: inner, consent: ConsentState.granted);
    await tester.pumpWidget(_app(w, _route));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_paint'), findsOneWidget);
    expect(key('route_map'), findsNothing);
    expect(key('route_view_toggle'), findsNothing);
  });

  testWidgets('Netz wirft: Linie, kein Umschalter', (tester) async {
    final w = _World(net: ThrowingInner(), consent: ConsentState.granted);
    await tester.pumpWidget(_app(w, _route));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_paint'), findsOneWidget);
    expect(key('route_map'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Widerruf bei offener Karte: Linie, keine Anfrage mehr', (
    tester,
  ) async {
    final w = _World(consent: ConsentState.granted);
    await tester.pumpWidget(_app(w, _route));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_map'), findsOneWidget);
    final before = w.requests;
    await tester.runAsync(w.controller.revoke);
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_paint'), findsOneWidget);
    expect(key('route_map'), findsNothing);
    expect(key('route_view_toggle'), findsNothing);
    expect(w.requests, before);
  });

  testWidgets('Lauf ohne Positionen: keine Frage, keine Anfrage', (
    tester,
  ) async {
    final w = _World();
    await tester.pumpWidget(_app(w, const []));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('map_consent_dialog'), findsNothing);
    expect(w.requests, 0);
  });

  testWidgets('RunRouteSection nimmt die Karte (Zusammenfassung und Detail)', (
    tester,
  ) async {
    final w = _World(consent: ConsentState.granted);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        theme: RamuriTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MapConsentScope(
          holder: w.holder,
          child: Scaffold(
            body: SingleChildScrollView(child: RunRouteSection(route: _route)),
          ),
        ),
      ),
    );
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_map'), findsOneWidget);
    expect(key('route_paint'), findsNothing);
  });

  final marks = [
    KilometerMark(index: 1, position: _b, time: _t0),
    KilometerMark(index: 2, position: _c, time: _t0),
  ];

  testWidgets('Kilometermarken: auf der Karte mit Einwilligung', (
    tester,
  ) async {
    final w = _World(consent: ConsentState.granted);
    await tester.pumpWidget(
      _host(
        w,
        RunRouteSection(route: _route, marks: marks, markUnitLabel: 'km'),
      ),
    );
    await settleUntilRequestsStable(tester, () => w.requests);
    final map = tester.widget<RouteMap>(key('route_map'));
    expect([for (final m in map.marks) m.index], [1, 2]);
    expect(find.text('2'), findsWidgets);
    expect(key('route_legend_marks'), findsOneWidget);
  });

  testWidgets('Kilometermarken: auch im Rückfall ohne Karte gezeichnet', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        null,
        RunRouteSection(route: _route, marks: marks, markUnitLabel: 'mi'),
      ),
    );
    await tester.pump();
    expect(key('route_map'), findsNothing);
    final painter =
        tester.widget<CustomPaint>(key('route_paint')).painter! as RoutePainter;
    final shapes = painter.shapes(tester.getSize(key('route_paint')));
    expect([for (final m in shapes.marks) m.index], [1, 2]);
    // Die Marken liegen in der Zeichnung innerhalb der Fläche.
    final box = Offset.zero & tester.getSize(key('route_paint'));
    for (final m in shapes.marks) {
      expect(box.contains(m.at), isTrue);
    }
    expect(
      tester.widget<Text>(key('route_legend_marks')).data,
      'Nummern: volle mi',
    );
  });

  for (final mode in ['Flugmodus', '404']) {
    testWidgets(
      'alle Kacheln scheitern ($mode, Stil vorhanden): Linie, kein Umschalter, keine Quellenangabe',
      (tester) async {
        final net = FakeInner();
        if (mode == '404') {
          net.statusWhere = (u) => u.path.endsWith('.pbf') ? 404 : null;
        } else {
          net.failWhere = (u) => u.path.endsWith('.pbf');
        }
        final w = _World(net: net, consent: ConsentState.granted);
        await tester.pumpWidget(_app(w, _route));
        await settleUntilRequestsStable(tester, () => w.requests);
        expect(
          w.tileRequests,
          greaterThan(0),
          reason: 'Kacheln wurden versucht',
        );
        expect(key('route_map'), findsNothing);
        expect(key('route_paint'), findsOneWidget);
        expect(key('route_view_toggle'), findsNothing);
        expect(find.text(MapProvider.openFreeMap.attribution), findsNothing);
      },
    );
  }

  testWidgets(
    'Rückkehr aus dem Hintergrund bei aktivem Rückfall: neuer Versuch, Karte erholt sich (E2E 36)',
    (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final net = FakeInner()..failWhere = (u) => u.path.endsWith('.pbf');
      final w = _World(net: net, consent: ConsentState.granted);
      await tester.pumpWidget(_app(w, _route));
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_map'), findsNothing, reason: 'Rückfall aktiv');
      for (final st in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pump();
      net.failWhere =
          null; // Netz wieder da, während die App im Hintergrund ist
      final n = w.requests;
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, n, reason: 'im Hintergrund kein Verkehr');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_map'), findsOneWidget);
    },
  );

  testWidgets(
    'Pause (App im Hintergrund, Route verdeckt): keine Karte, keine Anfrage; danach wieder da (S6)',
    (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final w = _World(consent: ConsentState.granted);
      await tester.pumpWidget(_app(w, _route));
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_map'), findsOneWidget);
      // App im Hintergrund
      for (final st in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pump();
      expect(key('route_map'), findsNothing);
      expect(key('route_paint'), findsOneWidget);
      final n = w.requests;
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, n);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_map'), findsOneWidget);
      // Route verdeckt
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('oben')),
        ),
      );
      await tester.pumpAndSettle();
      // find.byKey lässt Offstage-Teile aus: ohne skipOffstage: false fände der Test die Karte hier nie (N3).
      expect(
        find.byKey(const Key('route_map'), skipOffstage: false),
        findsNothing,
      );
      expect(
        find.byKey(const Key('route_paint'), skipOffstage: false),
        findsOneWidget,
      );
      nav.pop();
      await tester.pumpAndSettle();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_map'), findsOneWidget);
    },
  );

  testWidgets(
    'Rückkehr aus dem Hintergrund bei verdeckter Route und gescheitertem Öffnen: keine Anfrage (S4)',
    (tester) async {
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final net = FakeInner()..failWhere = (u) => true;
      final w = _World(net: net, consent: ConsentState.granted);
      await tester.pumpWidget(_app(w, _route));
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_map'), findsNothing, reason: 'Öffnen gescheitert');
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('oben')),
        ),
      );
      await tester.pumpAndSettle();
      await settleUntilRequestsStable(tester, () => w.requests);
      final n = w.requests;
      for (final st in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await tester.pump();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, n, reason: 'im Hintergrund kein Verkehr');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, n, reason: 'Route verdeckt: kein neuer Versuch');
      nav.pop();
      await tester.pumpAndSettle();
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(w.requests, greaterThan(n), reason: 'Route wieder oben: Versuch');
    },
  );

  testWidgets(
    'Dialog über der Seite: die Karte bleibt im Baum und wird nicht neu aufgebaut (N6)',
    (tester) async {
      final w = _World(consent: ConsentState.granted);
      await tester.pumpWidget(_app(w, _route));
      await settleUntilRequestsStable(tester, () => w.requests);
      expect(key('route_map'), findsOneWidget);
      final before = tester.element(key('route_map'));
      final n = w.requests;
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      showDialog<void>(
        context: nav.context,
        builder: (_) => const AlertDialog(content: Text('Frage')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Frage'), findsOneWidget);
      expect(key('route_map'), findsOneWidget);
      expect(identical(tester.element(key('route_map')), before), isTrue);
      expect(w.requests, n, reason: 'keine neuen Anfragen durch den Dialog');
      nav.pop();
      await tester.pumpAndSettle();
      expect(identical(tester.element(key('route_map')), before), isTrue);
    },
  );

  testWidgets('einzelne Kachel scheitert, andere treffen: Karte bleibt', (
    tester,
  ) async {
    var n = 0;
    final net = FakeInner()
      ..statusWhere = (u) => u.path.endsWith('.pbf') && n++ == 0 ? 404 : null;
    final w = _World(net: net, consent: ConsentState.granted);
    await tester.pumpWidget(_app(w, _route));
    await settleUntilRequestsStable(tester, () => w.requests);
    expect(key('route_map'), findsOneWidget);
    expect(key('route_view_toggle'), findsOneWidget);
  });

  // Bildschirmfoto hell und dunkel (Layout statt Emulator). Nur mit SHOT_DIR, sonst nur die Prüfung.
  for (final dark in [false, true]) {
    testWidgets(
      'Darstellung ${dark ? 'dunkel' : 'hell'}: Karte, Umschalter, Quellenangabe',
      (tester) async {
        tester.view.physicalSize = const Size(780, 900);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final w = _World(consent: ConsentState.granted);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('shot'),
            child: _app(
              w,
              _route,
              theme: dark ? RamuriTheme.dark : RamuriTheme.light,
            ),
          ),
        );
        await settleUntilRequestsStable(tester, () => w.requests);
        expect(key('route_map'), findsOneWidget);
        expect(find.text(MapProvider.openFreeMap.attribution), findsOneWidget);
        // Die Quellenangabe liegt vollständig im Bild der Karte.
        final map = tester.getRect(key('route_map'));
        final attr = tester.getRect(
          find.text(MapProvider.openFreeMap.attribution),
        );
        expect(map.contains(attr.topLeft), isTrue);
        expect(map.contains(attr.bottomRight - const Offset(1, 1)), isTrue);
        final dir = Platform.environment['SHOT_DIR'];
        if (dir != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              key('shot'),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('$dir/wp13-b-shot-${dark ? 'dunkel' : 'hell'}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      },
    );
  }
}
