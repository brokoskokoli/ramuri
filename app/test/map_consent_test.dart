// WP13 A3: Einwilligung zum Kartenanbieter (SEC-0002, SEC-0007, SEC-0008, ADR-0009 Punkt 3).
import 'package:adapters/adapters.dart';
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_consent_scope.dart';
import 'package:running_app/features/map/map_services.dart';

import 'app_harness.dart';
import 'settings_gate_storage.dart';

class _Cache implements MapCacheAdmin {
  int size = 1572864; // 1,5 MB
  int deletes = 0;
  bool failDelete = false;
  @override
  Future<int> sizeBytes() async => size;
  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('x');
    deletes++;
    size = 0;
  }
}

class _MapWorld {
  final inner = FakeInner();
  final cache = _Cache();
  final List<MapGate> gates = [];
  late final MapServices services = MapServices(
    gate: (consent) {
      final g = MapGate(
        provider: MapProvider.openFreeMap,
        consent: consent,
        inner: inner,
      );
      gates.add(g);
      return g;
    },
    cache: cache,
    attribution: 'Quelle-Test',
  );
}

class _MemoryConsents implements ConsentStore {
  final Map<String, ConsentState> data = {};
  bool failGet = false;
  bool failSet = false;
  @override
  Future<ConsentState?> get(String sourceKey) async {
    if (failGet) throw StateError('x');
    return data[sourceKey];
  }

  @override
  Future<Map<String, ConsentState>> all() async => Map.of(data);
  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async {
    if (failSet) throw StateError('x');
    data[k] = s;
  }
}

MapConsentController _controller(_MemoryConsents store, _MapWorld w) =>
    MapConsentController(
      store: store,
      clock: FakeClock(DateTime.utc(2026, 6, 1)),
      services: w.services,
    );

/// Öffnet eine Probeseite mit einem Knopf, der die Frage auslöst (Teil B setzt das Karten-Widget darauf).
Future<List<bool>> _openProbe(WidgetTester tester) async {
  final results = <bool>[];
  final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
  nav.push(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            key: const Key('probe_open_map'),
            onPressed: () async => results.add(
              await MapConsentScope.of(context)!.ensureAsked(context),
            ),
            child: const Text('Karte'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return results;
}

Future<void> _openSettings(WidgetTester tester) async {
  await openOverview(tester);
  await tester.tap(find.byKey(const Key('home_settings')));
  await tester.pumpAndSettle();
}

Future<void> _startApp(WidgetTester tester, Device d) async {
  await d.start(tester, const Locale('de'));
  if (find.byKey(const Key('setup_skip')).evaluate().isNotEmpty) {
    await d.skipSetup(tester);
  }
}

void main() {
  group('Controller', () {
    test(
      'Lesefehler: nicht erteilt, keine Frage, keine Quelle, 0 Anfragen',
      () async {
        final w = _MapWorld();
        final store = _MemoryConsents()
          ..data[mapProviderSourceKey] = ConsentState.granted
          ..failGet = true;
        final c = _controller(store, w);
        await c.ready;
        expect(c.granted, isFalse);
        expect(c.status, MapConsentStatus.declined);
        expect(await c.openSource(), isNull);
        expect(w.inner.requests, isEmpty);
        expect(w.gates, isEmpty);
      },
    );

    test('Widerruf sperrt sofort, auch wenn das Speichern scheitert', () async {
      final w = _MapWorld();
      final store = _MemoryConsents()
        ..data[mapProviderSourceKey] = ConsentState.granted;
      final c = _controller(store, w);
      await c.ready;
      expect(c.granted, isTrue);
      store.failSet = true;
      final result = await c.revoke();
      expect(result.saveFailed, isTrue);
      expect(result.askDeleteCache, isTrue);
      expect(c.granted, isFalse);
      expect(c.status, MapConsentStatus.declined);
      expect(await c.openSource(), isNull);
      expect(w.inner.requests, isEmpty);
      // Im Speicher steht noch "erteilt": gilt in dieser Sitzung trotzdem nicht.
      expect(store.data[mapProviderSourceKey], ConsentState.granted);
    });

    test('Widerruf: gespeichert, fragt nach dem Löschen', () async {
      final w = _MapWorld();
      final store = _MemoryConsents()
        ..data[mapProviderSourceKey] = ConsentState.granted;
      final c = _controller(store, w);
      await c.ready;
      final r = await c.revoke();
      expect((r.askDeleteCache, r.saveFailed), (true, false));
      expect(store.data[mapProviderSourceKey], ConsentState.revoked);
    });

    test(
      'Widerruf bei unlesbarem Stand fragt trotzdem nach dem Löschen',
      () async {
        final w = _MapWorld();
        final store = _MemoryConsents()..failGet = true;
        final c = _controller(store, w);
        await c.ready;
        final r = await c.revoke();
        expect(r.askDeleteCache, isTrue);
      },
    );

    test('Erteilen scheitert beim Speichern: bleibt verweigert', () async {
      final w = _MapWorld();
      final store = _MemoryConsents()..failSet = true;
      final c = _controller(store, w);
      await c.ready;
      expect(c.status, MapConsentStatus.neverAsked);
      expect(await c.grant(), isFalse);
      expect(c.granted, isFalse);
      expect(await c.openSource(), isNull);
      expect(w.inner.requests, isEmpty);
    });

    testWidgets(
      'ohne Einwilligung keine Quelle und keine Anfrage; mit Einwilligung ja; nach Widerruf wieder keine',
      (tester) async {
        await tester.runAsync(() async {
          final w = _MapWorld();
          final store = _MemoryConsents();
          final c = _controller(store, w);
          await c.ready;
          expect(await c.openSource(), isNull);
          expect(w.inner.requests, isEmpty);
          expect(
            w.gates,
            isEmpty,
            reason: 'nicht einmal ein Tor ohne Einwilligung',
          );

          expect(await c.grant(), isTrue);
          final source = await c.openSource();
          expect(source, isNotNull);
          final before = w.inner.requests.length;
          expect(before, greaterThan(0));

          await c.revoke();
          // Das Tor des geöffneten Quelle liest die Einwilligung bei jeder Anfrage neu.
          await expectLater(
            source!.gate.read(
              Uri.https(MapProvider.openFreeMapHost, '/planet'),
            ),
            throwsA(
              isA<MapGateException>().having(
                (e) => e.reason,
                'reason',
                MapGateReason.noConsent,
              ),
            ),
          );
          expect(w.inner.requests.length, before);
          expect(await c.openSource(), isNull);
          source.dispose();
        });
      },
    );
  });

  group('Oberfläche', () {
    testWidgets('kein Dialog und keine Anfrage beim App-Start', (tester) async {
      final d = Device();
      final w = _MapWorld();
      d.map = w.services;
      await _startApp(tester, d);
      expect(find.byKey(const Key('map_consent_dialog')), findsNothing);
      expect(w.inner.requests, isEmpty);
      expect(await d.session.consents.get(mapProviderSourceKey), isNull);
    });

    testWidgets(
      'erste Karte: Frage, Mehr erfahren klappt auf, Erteilen speichert',
      (tester) async {
        final d = Device();
        final w = _MapWorld();
        d.map = w.services;
        await _startApp(tester, d);
        final results = await _openProbe(tester);
        await tester.tap(find.byKey(const Key('probe_open_map')));
        await tester.pumpAndSettle();
        expect(find.text('Karte aus dem Netz laden?'), findsOneWidget);
        expect(find.textContaining('bis zu 7 Tage'), findsNothing);
        await tester.tap(find.byKey(const Key('map_consent_more')));
        await tester.pumpAndSettle();
        expect(find.textContaining('bis zu 7 Tage'), findsOneWidget);

        await tester.tap(find.byKey(const Key('map_consent_load')));
        await tester.pumpAndSettle();
        expect(results, [true]);
        expect(
          await d.session.consents.get(mapProviderSourceKey),
          ConsentState.granted,
        );
        // Zweites Öffnen: erteilt, keine Frage mehr.
        await tester.tap(find.byKey(const Key('probe_open_map')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('map_consent_dialog')), findsNothing);
        expect(results, [true, true]);
      },
    );

    testWidgets(
      'Nicht jetzt: nichts gespeichert, in dieser Sitzung keine zweite Frage, im nächsten Start wieder',
      (tester) async {
        final d = Device();
        final w = _MapWorld();
        d.map = w.services;
        await _startApp(tester, d);
        final results = await _openProbe(tester);
        await tester.tap(find.byKey(const Key('probe_open_map')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('map_consent_not_now')));
        await tester.pumpAndSettle();
        expect(results, [false]);
        expect(await d.session.consents.get(mapProviderSourceKey), isNull);

        await tester.tap(find.byKey(const Key('probe_open_map')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('map_consent_dialog')), findsNothing);
        expect(results, [false, false]);
        expect(w.inner.requests, isEmpty);

        await d.stop(tester);
        await _startApp(tester, d);
        final again = await _openProbe(tester);
        await tester.tap(find.byKey(const Key('probe_open_map')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('map_consent_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('map_consent_not_now')));
        await tester.pumpAndSettle();
        expect(again, [false]);
      },
    );

    testWidgets(
      'Einstellungen: Stand, Größe, Quelle; Erteilen und Widerrufen mit Löschen',
      (tester) async {
        final d = Device();
        final w = _MapWorld();
        d.map = w.services;
        await _startApp(tester, d);
        await _openSettings(tester);
        expect(find.byKey(const Key('map_settings')), findsOneWidget);
        expect(find.byKey(const Key('map_status')), findsOneWidget);
        expect(find.text('Kartenspeicher: 1,5 MB'), findsOneWidget);
        expect(find.text('Quelle: Quelle-Test'), findsOneWidget);

        await tester.tap(find.byKey(const Key('map_grant')));
        await tester.pumpAndSettle();
        expect(
          await d.session.consents.get(mapProviderSourceKey),
          ConsentState.granted,
        );
        expect(find.byKey(const Key('map_revoke')), findsOneWidget);

        await tester.tap(find.byKey(const Key('map_revoke')));
        await tester.pumpAndSettle();
        expect(
          await d.session.consents.get(mapProviderSourceKey),
          ConsentState.revoked,
        );
        expect(find.byKey(const Key('map_delete_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('map_delete_confirm')));
        await tester.pumpAndSettle();
        expect(w.cache.deletes, 1);
        expect(find.text('Kartenspeicher: 0 B'), findsOneWidget);
        expect(find.byKey(const Key('map_grant')), findsOneWidget);
        expect(w.inner.requests, isEmpty);
      },
    );

    testWidgets('Widerruf und Behalten: Speicher bleibt', (tester) async {
      final d = Device();
      final w = _MapWorld();
      d.map = w.services;
      await _startApp(tester, d);
      await d.session.consents.set(
        mapProviderSourceKey,
        ConsentState.granted,
        at: DateTime.utc(2026),
      );
      await d.stop(tester);
      await _startApp(tester, d);
      await _openSettings(tester);
      await tester.tap(find.byKey(const Key('map_revoke')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('map_delete_keep')));
      await tester.pumpAndSettle();
      expect(w.cache.deletes, 0);
      expect(w.cache.size, 1572864);
      expect(
        await d.session.consents.get(mapProviderSourceKey),
        ConsentState.revoked,
      );
    });

    testWidgets(
      'Widerruf, Speichern scheitert: sperrt trotzdem und fragt nach dem Löschen',
      (tester) async {
        final d = Device();
        final w = _MapWorld();
        d.map = w.services;
        final gate = SettingsGateStorage(d.storage);
        d.storageOverride = gate;
        await _startApp(tester, d);
        await d.session.consents.set(
          mapProviderSourceKey,
          ConsentState.granted,
          at: DateTime.utc(2026),
        );
        await d.stop(tester);
        await _startApp(tester, d);
        final controller = MapConsentScope.of(
          tester.element(find.byType(Scaffold).first),
        )!;
        expect(controller.granted, isTrue);
        gate.failConsentSets = true;
        await _openSettings(tester);
        await tester.tap(find.byKey(const Key('map_revoke')));
        await tester.pumpAndSettle();
        expect(controller.granted, isFalse);
        expect(find.byKey(const Key('map_delete_dialog')), findsOneWidget);
        expect(
          find.text(
            'Der Widerruf konnte nicht gespeichert werden. In dieser Sitzung lädt die App trotzdem keine Karte mehr.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('map_delete_confirm')));
        await tester.pumpAndSettle();
        expect(w.cache.deletes, 1);
      },
    );

    testWidgets(
      'Lesefehler beim Start: nicht erteilt, keine Frage, 0 Anfragen',
      (tester) async {
        final d = Device();
        final w = _MapWorld();
        d.map = w.services;
        final gate = SettingsGateStorage(d.storage);
        d.storageOverride = gate;
        await _startApp(tester, d);
        await d.session.consents.set(
          mapProviderSourceKey,
          ConsentState.granted,
          at: DateTime.utc(2026),
        );
        await d.stop(tester);
        gate.failConsentGets = true;
        await _startApp(tester, d);
        final results = await _openProbe(tester);
        await tester.tap(find.byKey(const Key('probe_open_map')));
        await tester.pumpAndSettle();
        expect(results, [false]);
        expect(find.byKey(const Key('map_consent_dialog')), findsNothing);
        expect(w.inner.requests, isEmpty);
      },
    );

    testWidgets('ohne verdrahteten Kartenanbieter kein Eintrag', (
      tester,
    ) async {
      final d = Device();
      await _startApp(tester, d);
      await _openSettings(tester);
      expect(find.byKey(const Key('map_settings')), findsNothing);
    });

    testWidgets('dunkel: Dialog und Einstellungen bauen ohne Fehler', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      final d = Device();
      d.map = _MapWorld().services;
      await _startApp(tester, d);
      await _openProbe(tester);
      await tester.tap(find.byKey(const Key('probe_open_map')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('map_consent_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('map_consent_not_now')));
      await tester.pumpAndSettle();
    });
  });
}
