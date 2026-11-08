// WP13 Nachbesserung N1a: "Alles löschen" und der Kartenanbieter (Review B1, M4 D6, H5, S3). Nach "Alles löschen"
// gilt der Stand des ersten Starts auch im Speicher des Prozesses: keine Einwilligung, keine Anfrage, keine
// Schreibung einer laufenden Miniatur; das Löschen eines Laufs im Detail nimmt seine Miniatur mit.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_consent_scope.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/map/miniature_service.dart';

import 'app_harness.dart';
import 'run_detail_test.dart' show seedDetailRun;

Finder key(String k) => find.byKey(Key(k));

class _Cache implements MapCacheAdmin {
  int deletes = 0;
  @override
  Future<int> sizeBytes() async => 0;
  @override
  Future<void> delete() async => deletes++;
}

class _Thumbs implements MapThumbnailStore {
  final Map<String, Uint8List> data = {};
  final List<int> deletedRuns = [];
  @override
  Future<Uint8List?> read(String key) async => data[key];
  @override
  Future<void> write(String key, Uint8List bytes) async => data[key] = bytes;
  @override
  Future<void> deleteRun(int runId) async => deletedRuns.add(runId);
}

class _World {
  final inner = FakeInner();
  final cache = _Cache();
  final thumbs = _Thumbs();
  late final MapServices services = MapServices(
    gate: (consent) => MapGate(
      provider: MapProvider.openFreeMap,
      consent: consent,
      inner: inner,
    ),
    cache: cache,
    thumbnails: thumbs,
    attribution: 'Quelle-Test',
  );
}

MapConsentController _controller(WidgetTester tester) =>
    MapConsentScope.of(tester.element(find.byType(Scaffold).first))!;

class _MemoryConsents implements ConsentStore {
  final Map<String, ConsentState> data = {};
  @override
  Future<ConsentState?> get(String sourceKey) async => data[sourceKey];
  @override
  Future<Map<String, ConsentState>> all() async => Map.of(data);
  @override
  Future<void> set(String k, ConsentState s, {required DateTime at}) async =>
      data[k] = s;
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
const _route = [
  [RoutePoint(10, 20), RoutePoint(10.001, 20.001)],
];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

MapConsentController _granted(
  _World w,
  _MemoryConsents store, {
  void Function()? onClear,
}) => MapConsentController(
  store: store,
  clock: FakeClock(DateTime.utc(2026, 6, 1)),
  services: w.services,
  clearTileMemory: onClear,
);

Future<(Device, _World)> _start(WidgetTester tester) async {
  final w = _World();
  final d = Device()..map = w.services;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  return (d, w);
}

void main() {
  setUp(() => clearMapMemoryCache());

  testWidgets(
    'B1: Alles löschen setzt die Einwilligung auch im Prozess zurück (keine Anfrage, Frage bei der nächsten Karte)',
    (tester) async {
      final (d, w) = await _start(tester);
      final controller = _controller(tester);
      expect(await controller.grant(), isTrue);
      expect(controller.granted, isTrue);

      await openOverview(tester);
      await tester.tap(key('overview_data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alles löschen'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Alles löschen'));
      await tester.pumpAndSettle();

      expect(await d.session.consents.get(mapProviderSourceKey), isNull);
      final after = _controller(tester);
      for (final c in {controller, after}) {
        expect(c.granted, isFalse, reason: 'Tor sagt nach dem Löschen nein');
        expect(c.status, MapConsentStatus.neverAsked);
      }
      await tester.runAsync(() async {
        expect(await after.openSource(), isNull);
      });
      expect(w.inner.requests, isEmpty);
      expect(w.cache.deletes, greaterThan(0), reason: 'Speicher abgeräumt');
      await d.stop(tester);
    },
  );

  testWidgets('D6: Löschen eines Laufs im Detail nimmt seine Miniatur mit', (
    tester,
  ) async {
    final (d, w) = await _start(tester);
    final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
    await tester.tap(key('home_history'));
    await tester.pumpAndSettle();
    await tester.tap(key('history_run_$id'));
    await tester.pumpAndSettle();
    // Die Karte im Detail fragt zuerst nach der Einwilligung: "Nicht jetzt".
    await tester.tap(key('map_consent_not_now'));
    await tester.pumpAndSettle();
    await tester.tap(key('detail_delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen').last);
    await tester.pumpAndSettle();
    expect(await d.session.runs.get(id), isNull);
    expect(w.thumbs.deletedRuns, [id]);
    await d.stop(tester);
  });

  group('Controller', () {
    testWidgets(
      'B1/H5: eine laufende Miniatur schreibt nach "Alles löschen" nichts, auch wenn sie währenddessen fertig wird',
      (tester) async {
        final w = _World();
        final store = _MemoryConsents()
          ..data[mapProviderSourceKey] = ConsentState.granted;
        final c = _granted(w, store);
        addTearDown(c.dispose);
        await tester.runAsync(() => c.ready);
        expect(c.granted, isTrue);
        final hold = Completer<void>();
        var captures = 0;
        debugMiniatureCapture =
            (boundary, gate, {cancelled, failuresBefore}) async {
              captures++;
              await hold.future;
              return png1x1;
            };
        addTearDown(() => debugMiniatureCapture = null);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        final svc = MiniatureService(consent: c);
        addTearDown(svc.dispose);
        svc.request(1, _route, _style, visibleTop: () => 0);
        for (var i = 0; i < 20 && captures == 0; i++) {
          await _settle(tester);
        }
        expect(captures, 1, reason: 'Aufnahme läuft und hängt');

        final seen = <String>[];
        await tester.runAsync(
          () => c.deleteAllAround(() async {
            seen.add('granted=${c.granted}');
            hold.complete(); // die Aufnahme wird fertig, während gelöscht wird
            await Future<void>.delayed(const Duration(milliseconds: 80));
            await Future<void>.delayed(Duration.zero);
          }),
        );
        await _settle(tester);
        expect(seen, ['granted=false'], reason: 'Tor schon vor dem Löschen zu');
        expect(w.thumbs.data, isEmpty, reason: 'nichts geschrieben');
        expect(c.status, MapConsentStatus.neverAsked);
        expect(c.granted, isFalse);
      },
    );

    test('Löschen scheitert ganz: der gespeicherte Stand gilt wieder; deletedNotErased: Stand des ersten Starts', () async {
      final w = _World();
      final store = _MemoryConsents()
        ..data[mapProviderSourceKey] = ConsentState.granted;
      final c = _granted(w, store);
      addTearDown(c.dispose);
      await c.ready;
      await (() async {
        Object? error;
        try {
          await c.deleteAllAround(() async => throw StateError('x'));
        } catch (e) {
          error = e;
        }
        expect(error, isA<StateError>());
        expect(c.granted, isTrue, reason: 'nichts gelöscht');
        expect(c.status, MapConsentStatus.granted);

        // Der Stand im Speicher gilt hier nicht: deletedNotErased heißt gelöscht (fail-closed), auch wenn der
        // Eintrag der Einwilligung noch lesbar wäre.
        try {
          await c.deleteAllAround(
            () async =>
                throw const StorageException(StorageFailure.deletedNotErased),
          );
        } catch (e) {
          error = e;
        }
        expect(error, isA<StorageException>());
        expect(c.granted, isFalse);
        expect(c.status, MapConsentStatus.neverAsked);
      })();
    });

    testWidgets(
      'H5: Löschen eines Laufs bricht seine laufende Aufnahme ab, danach wird nichts gespeichert (ohne Listenzeile)',
      (tester) async {
        final w = _World();
        final store = _MemoryConsents()
          ..data[mapProviderSourceKey] = ConsentState.granted;
        final c = _granted(w, store);
        addTearDown(c.dispose);
        await tester.runAsync(() => c.ready);
        final hold = Completer<void>();
        var captures = 0;
        debugMiniatureCapture =
            (boundary, gate, {cancelled, failuresBefore}) async {
              captures++;
              await hold.future;
              return png1x1;
            };
        addTearDown(() => debugMiniatureCapture = null);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        final svc = MiniatureService(consent: c);
        addTearDown(svc.dispose);
        final ticket = svc.request(3, _route, _style, visibleTop: () => 0)!;
        for (var i = 0; i < 20 && captures == 0; i++) {
          await _settle(tester);
        }
        expect(captures, 1);
        await tester.runAsync(() => c.deleteRunThumbnails(3));
        hold.complete();
        await _settle(tester);
        expect(ticket.cancelled, isTrue);
        expect(w.thumbs.data, isEmpty);
      },
    );

    test('dispose: die Tore der Sitzung sagen nein', () async {
      final w = _World();
      final store = _MemoryConsents()
        ..data[mapProviderSourceKey] = ConsentState.granted;
      final c = _granted(w, store);
      await c.ready;
      expect(c.granted, isTrue);
      c.dispose();
      expect(c.granted, isFalse);
    });

    test(
      'S3: Widerruf und Alles löschen leeren den Arbeitsspeicher der Kacheln',
      () async {
        final w = _World();
        final store = _MemoryConsents()
          ..data[mapProviderSourceKey] = ConsentState.granted;
        var cleared = 0;
        final c = _granted(w, store, onClear: () => cleared++);
        addTearDown(c.dispose);
        await c.ready;
        await c.revoke();
        expect(cleared, greaterThan(0), reason: 'Widerruf');
        final before = cleared;
        await c.deleteAllAround(() async {});
        expect(cleared, greaterThan(before), reason: 'Alles löschen');
      },
    );
  });

  test('S5: für einen eben gelöschten Lauf entsteht keine Miniatur mehr (Anfrage mit schon gelesenen Rohdaten)', () async {
    final w = _World();
    final store = _MemoryConsents()
      ..data[mapProviderSourceKey] = ConsentState.granted;
    final c = _granted(w, store);
    addTearDown(c.dispose);
    await c.ready;
    final svc = MiniatureService(consent: c);
    addTearDown(svc.dispose);
    await c.deleteRunThumbnails(5);
    expect(svc.request(5, _route, _style, visibleTop: () => 0), isNull);
  });

  group('Verdrahtung (echter Kartenspeicher)', () {
    late Directory dir;
    late String dbPath;
    late EncryptedMapTileStore map;
    final key = Uint8List.fromList(List.filled(storageKeyLength, 7));

    setUp(() {
      dir = Directory.systemTemp.createTempSync('wp13n1a_wire_');
      dbPath = '${dir.path}/running_app.db';
      map = EncryptedMapTileStore(
        directory: () async => dir.path,
        key: () async => key,
      );
    });
    tearDown(() async {
      await map.close();
      dir.deleteSync(recursive: true);
    });

    String mapFile() => '${dir.path}/$mapCacheFileName';
    Uint8List bytes(int n) => Uint8List.fromList(List.filled(n, 5));

    test(
      'D3: "Alles löschen" der Sitzung räumt den echten Kartenspeicher ab',
      () async {
        final wiring = storageWiringFor(dbPath, map);
        await map.write('map:/a', bytes(500));
        expect(File(mapFile()).existsSync(), isTrue);
        final session = await wiring.storage.open(key);
        await session.deleteAll();
        await session.close();
        expect(File(mapFile()).existsSync(), isFalse);
      },
    );

    test(
      'D4: Neubeginn nach Schlüsselverlust räumt den echten Kartenspeicher ab',
      () async {
        final wiring = storageWiringFor(dbPath, map);
        await map.write('map:/a', bytes(500));
        File(dbPath).writeAsBytesSync([1]);
        await wiring.files.deleteAll();
        expect(File(mapFile()).existsSync(), isFalse);
        expect(File(dbPath).existsSync(), isFalse);
      },
    );

    test('M3: der Tausch durch eine Wiederherstellung verwirft die Miniaturen, die Kacheln bleiben', () async {
      final files = databaseFilesFor(dbPath, map);
      await map.write('map:/a', bytes(500));
      await map.write('thumb:v1:7', bytes(300));
      File(dbPath).writeAsBytesSync([1]);
      File('$dbPath.import').writeAsBytesSync([2]);
      await files.replaceWithImport();
      expect(await map.read('thumb:v1:7'), isNull);
      expect(await map.read('map:/a'), bytes(500));
    });
  });
}
