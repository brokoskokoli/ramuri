// WP13 N1c: gemeinsamer Halter der Kachelquelle (M5, Rennen "Widerruf während des Öffnens", S4, M1), Parallelgrenze
// und Fehlerliste des Miniaturen-Dienstes mit echter Quelle (M4), Pause im Hintergrund (S6). Ohne Netz: ein Fake hinter
// dem Tor.
import 'dart:async';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/run_miniature.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/map/map_source_holder.dart';
import 'package:running_app/features/map/miniature_service.dart';

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

class _Thumbs implements MapThumbnailStore {
  final Map<String, Uint8List> data = {};
  int writes = 0;
  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    data[key] = bytes;
  }

  @override
  Future<void> remove(String key) async => data.remove(key);
  @override
  Future<void> deleteRun(int runId) async {}
}

class _Inner extends FakeInner {
  bool closed = false;
  @override
  void close() => closed = true;
}

/// Controller, dessen Quelle erst nach einem Signal ausgeliefert wird: die Quelle ist offen, der Aufrufer wartet noch.
class _SlowController extends MapConsentController {
  _SlowController({
    required super.store,
    required super.clock,
    required super.services,
  });
  Completer<void>? deliver;
  @override
  Future<MapTileSource?> openSource({int? maxParallel}) async {
    final s = await super.openSource(maxParallel: maxParallel);
    if (deliver != null) await deliver!.future;
    return s;
  }
}

class _World {
  _World({ConsentState? consent, bool slow = false}) {
    if (consent != null) consents.data[mapProviderSourceKey] = consent;
    final services = MapServices(
      gate: (c) =>
          MapGate(provider: MapProvider.openFreeMap, consent: c, inner: inner),
      cache: _Cache(),
      thumbnails: thumbs,
      attribution: MapProvider.openFreeMap.attribution,
    );
    final clock = FakeClock(DateTime.utc(2026, 6, 1));
    controller = slow
        ? (_SlowController(store: consents, clock: clock, services: services))
        : MapConsentController(
            store: consents,
            clock: clock,
            services: services,
          );
  }
  final inner = _Inner();
  final consents = _Consents();
  final thumbs = _Thumbs();
  late final MapConsentController controller;
}

const _a = RoutePoint(52.5200, 13.4000);
const _b = RoutePoint(52.5230, 13.4100);
final _route = [
  [_a, _b],
];

Future<void> _wait(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => clearMapMemoryCache());

  group('MapSourceHolder', () {
    late BuildContext context;
    Future<MapSourceHolder> holder(
      WidgetTester tester,
      _World w, {
      bool wanted = true,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              context = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.runAsync(() => w.controller.ready);
      final h = MapSourceHolder(askContext: () => context)..bind(w.controller);
      addTearDown(h.dispose);
      h.setWanted(wanted);
      return h;
    }

    testWidgets('öffnet bei Einwilligung; nichts, solange nicht gebraucht', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      final h = await holder(tester, w, wanted: false);
      await _wait(tester);
      expect(h.source, isNull);
      expect(w.inner.requests, isEmpty);
      h.setWanted(true);
      await _wait(tester);
      expect(h.usable, isNotNull);
    });

    testWidgets(
      'Widerruf während des Öffnens: die fertige Quelle wird sofort freigegeben (Prüfung nach dem Öffnen)',
      (tester) async {
        final w = _World(consent: ConsentState.granted, slow: true);
        (w.controller as _SlowController).deliver = Completer<void>();
        final h = await holder(tester, w);
        await _wait(tester); // Quelle ist fertig, wird aber noch zurückgehalten
        expect(h.source, isNull);
        expect(w.inner.requests, isNotEmpty);
        await tester.runAsync(w.controller.revoke);
        (w.controller as _SlowController).deliver!.complete();
        await _wait(tester);
        expect(h.source, isNull, reason: 'nach dem Widerruf keine Quelle');
        expect(h.usable, isNull);
        expect(w.inner.closed, isTrue, reason: 'Tor der Quelle geschlossen');
        final n = w.inner.requests.length;
        await _wait(tester);
        expect(w.inner.requests.length, n);
      },
    );

    testWidgets('Widerruf bei offener Quelle schließt sie', (tester) async {
      final w = _World(consent: ConsentState.granted);
      final h = await holder(tester, w);
      await _wait(tester);
      expect(h.usable, isNotNull);
      var notified = 0;
      h.addListener(() => notified++);
      await tester.runAsync(w.controller.revoke);
      await _wait(tester, 2);
      expect(h.source, isNull);
      expect(w.inner.closed, isTrue);
      expect(notified, greaterThan(0));
    });

    testWidgets(
      'verweigert gestartet, später erteilt: die Quelle öffnet (S4)',
      (tester) async {
        final w = _World(consent: ConsentState.revoked);
        final h = await holder(tester, w);
        await _wait(tester);
        expect(h.source, isNull);
        expect(w.inner.requests, isEmpty);
        await tester.runAsync(w.controller.grant);
        await _wait(tester);
        expect(h.usable, isNotNull, reason: 'erneut erteilt öffnet die Quelle');
      },
    );

    testWidgets('Widerruf, dann erneut erteilt: die Quelle öffnet neu (S4)', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      final h = await holder(tester, w);
      await _wait(tester);
      await tester.runAsync(w.controller.revoke);
      await _wait(tester, 2);
      expect(h.source, isNull);
      await tester.runAsync(w.controller.grant);
      await _wait(tester);
      expect(h.usable, isNotNull);
    });

    testWidgets(
      'alle Kacheln scheitern: usable ist null, Erholung beim Treffer, neuer Versuch bei erneutem Bedarf',
      (tester) async {
        final w = _World(consent: ConsentState.granted);
        final h = await holder(tester, w);
        await _wait(tester);
        final s = h.source!;
        final gate = s.gate;
        w.inner.failWhere = (u) => u.path.endsWith('.pbf');
        for (var i = 0; i < mapTileFailureLimit; i++) {
          await tester.runAsync(
            () => gate
                .read(Uri.https(host, '/planet/20260101_000000_pt/14/$i/1.pbf'))
                .then((_) {}, onError: (_) {}),
          );
        }
        expect(h.source, isNotNull);
        expect(h.usable, isNull, reason: 'Rückfall auf die Linie');
        // Pause und Rückkehr: neuer Versuch
        h.setWanted(false);
        h.setWanted(true);
        expect(h.usable, isNotNull, reason: 'Zählung neu begonnen');
      },
    );

    testWidgets('anderer Controller: alte Quelle zu, neue öffnet', (
      tester,
    ) async {
      final w = _World(consent: ConsentState.granted);
      final h = await holder(tester, w);
      await _wait(tester);
      final old = w.inner;
      expect(h.usable, isNotNull);
      final w2 = _World(consent: ConsentState.granted);
      await tester.runAsync(() => w2.controller.ready);
      h.bind(w2.controller);
      expect(h.source, isNull);
      expect(old.closed, isTrue);
      await _wait(tester);
      expect(h.usable, isNotNull);
    });
  });

  group('MiniatureService mit echter Quelle', () {
    late MiniatureService service;
    late _World w;
    int captures = 0;

    Future<void> setup(
      WidgetTester tester,
      MiniatureCapture capture, {
      ConsentState consent = ConsentState.granted,
    }) async {
      w = _World(consent: consent);
      captures = 0;
      await tester.runAsync(() => w.controller.ready);
      service = MiniatureService(consent: w.controller, capture: capture);
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(children: [MiniatureHost(service: service)]),
        ),
      );
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pump(const Duration(milliseconds: 100));
      service.dispose();
      await tester.pump(const Duration(milliseconds: 100));
    }

    MiniatureTicket? ask(int id) =>
        service.request(id, _route, _style, visibleTop: () => 0);

    testWidgets(
      'höchstens 4 Anfragen zugleich, auch bei vielen gleichzeitigen Kacheln (H3)',
      (tester) async {
        await setup(tester, (
          boundary,
          gate, {
          cancelled,
          failuresBefore,
        }) async {
          captures++;
          await Future.wait([
            for (var i = 0; i < 12; i++)
              gate
                  .readBytes(
                    Uri.https(
                      host,
                      '/planet/20260101_000000_pt/14/${8800 + i}/5375.pbf',
                    ),
                  )
                  .then((_) {}),
          ]);
          return png1x1;
        });
        w.inner.delay = const Duration(milliseconds: 15);
        final out = await _drive(tester, ask(1)!);
        expect(out, isNotNull);
        expect(captures, 1);
        expect(
          w.inner.count((u) => u.path.endsWith('.pbf')),
          greaterThanOrEqualTo(12),
        );
        expect(
          w.inner.maxActive,
          lessThanOrEqualTo(miniatureMaxParallel),
          reason: 'Parallelgrenze der Quelle',
        );
        expect(w.inner.maxActive, greaterThan(1), reason: 'es lief parallel');
        await finish(tester);
      },
    );

    testWidgets(
      'gescheiterter Lauf wird im selben Aufbau nicht erneut versucht (X4)',
      (tester) async {
        await setup(tester, (
          boundary,
          gate, {
          cancelled,
          failuresBefore,
        }) async {
          captures++;
          return null;
        });
        expect(await _drive(tester, ask(7)!), isNull);
        expect(captures, 1);
        expect(ask(7), isNull, reason: 'gescheitert: nicht noch einmal');
        final other = ask(8);
        expect(other, isNotNull, reason: 'andere Läufe gehen');
        await _drive(tester, other!);
        expect(captures, 2);
        expect(w.thumbs.writes, 0);
      },
    );

    Future<void> until(WidgetTester tester, bool Function() ok) async {
      for (var i = 0; i < 200 && !ok(); i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(ok(), isTrue);
    }

    for (final cause in ['App im Hintergrund', 'Route verdeckt']) {
      void pause(WidgetTester tester) => cause == 'App im Hintergrund'
          ? <AppLifecycleState>[
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ].forEach(tester.binding.handleAppLifecycleStateChanged)
          : service.routeCurrent = false;
      void resume(WidgetTester tester) => cause == 'App im Hintergrund'
          ? tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            )
          : service.routeCurrent = true;

      testWidgets(
        'Pause ($cause) vor der Anfrage: keine Aufnahme, kein Netz, danach geht es weiter (S6)',
        (tester) async {
          addTearDown(
            () => tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            ),
          );
          await setup(tester, (
            boundary,
            gate, {
            cancelled,
            failuresBefore,
          }) async {
            captures++;
            return png1x1;
          });
          pause(tester);
          expect(service.paused, isTrue);
          final t = ask(1)!;
          for (var i = 0; i < 10; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(captures, 0);
          expect(w.inner.requests, isEmpty);
          resume(tester);
          expect(await _drive(tester, t), isNotNull);
          expect(captures, 1);
          expect(w.thumbs.writes, 1);
          await finish(tester);
        },
      );

      testWidgets(
        'Pause ($cause) während der Aufnahme: Abbruch, nichts gespeichert, Tor zu, danach neu (S6)',
        (tester) async {
          addTearDown(
            () => tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            ),
          );
          var sawCancel = false;
          await setup(tester, (
            boundary,
            gate, {
            cancelled,
            failuresBefore,
          }) async {
            captures++;
            if (captures == 1) {
              while (!(cancelled?.call() ?? false)) {
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
              sawCancel = true;
              return null;
            }
            return png1x1;
          });
          final t = ask(1)!;
          await until(tester, () => captures == 1);
          pause(tester);
          await until(tester, () => sawCancel);
          expect(w.thumbs.writes, 0);
          expect(
            w.inner.closed,
            isTrue,
            reason: 'Quelle zu: keine Wiederholungen',
          );
          final n = w.inner.requests.length;
          await tester.pump(const Duration(milliseconds: 200));
          expect(w.inner.requests.length, n);
          expect(captures, 1, reason: 'kein Fehlversuch, keine neue Aufnahme');
          resume(tester);
          expect(await _drive(tester, t), isNotNull);
          expect(captures, 2);
          expect(w.thumbs.writes, 1);
          await finish(tester);
        },
      );
    }

    testWidgets('abgebrochener Lauf (kein Fehler) darf neu angefragt werden', (
      tester,
    ) async {
      await setup(tester, (boundary, gate, {cancelled, failuresBefore}) async {
        captures++;
        return png1x1;
      });
      ask(3)!.cancel();
      final again = ask(3);
      expect(again, isNotNull);
      expect(await _drive(tester, again!), isNotNull);
      await finish(tester);
    });
  });
}

const _style = RouteMapStyle(
  lineColor: Color(0xFF112233),
  startColor: Color(0xFF00AA00),
  endColor: Color(0xFFAA0000),
  markerBorderColor: Color(0xFFFFFFFF),
  backgroundColor: Color(0xFFEEEEEE),
  attributionBackground: Color(0xCCFFFFFF),
  attributionForeground: Color(0xFF000000),
);

/// Treibt Bilder und echte Zeit, bis der Auftrag fertig ist.
Future<Uint8List?> _drive(WidgetTester tester, MiniatureTicket t) async {
  Uint8List? out;
  var done = false;
  unawaited(
    t.result.then((v) {
      out = v;
      done = true;
    }),
  );
  for (var i = 0; i < 200 && !done; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  return out;
}
