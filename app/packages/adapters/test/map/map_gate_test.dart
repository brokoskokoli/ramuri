import 'dart:async';

import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'map_fakes.dart';

void main() {
  late FakeInner inner;
  late bool consent;
  late MemoryStore store;
  late MapGate gate;

  setUp(() {
    vt.VectorTileLayer.clearMemoryCache(); // prozessweiter Speicher der Bibliothek (R008 Hinweis 3)
    inner = FakeInner();
    consent = true;
    store = MemoryStore();
    gate = MapGate(
      provider: MapProvider.openFreeMap,
      consent: () => consent,
      store: store,
      inner: inner,
    );
  });

  Future<void> expectReason(Future<Object?> f, MapGateReason reason) async {
    await expectLater(
      f,
      throwsA(
        isA<MapGateException>().having((e) => e.reason, 'reason', reason),
      ),
    );
  }

  testWidgets(
    'Tor zählt jede Ressourcenart, Kacheln gehen über das Tor, Rasterquellen fehlen',
    (tester) async {
      await tester.runAsync(() async {
        final source = await MapTileSource.open(gate);
        expect(source, isNotNull);
        // Kacheln: nur über das Tor, wenn resolveProvider greift (R008 "bypass").
        final provider = source!.style.providers['openmaptiles']!;
        await provider.load(const vt.TileKey(13, 4400, 2687));
        await gate.read(
          Uri.https(host, '/fonts/Noto%20Sans%20Regular/0-255.pbf'),
        );

        for (final kind in MapResource.values) {
          expect(
            gate.counts.network[kind],
            greaterThan(0),
            reason: 'Art ${kind.name} nicht gezählt',
          );
        }
        expect(
          inner.count(
            (u) => u.path.endsWith('.pbf') && u.path.startsWith('/planet/'),
          ),
          greaterThan(0),
        );
        expect(source.style.rasterSources, isEmpty);
        expect(
          inner.count((u) => u.path.contains('natural_earth')),
          0,
          reason: 'Rasterquelle entfernt',
        );
        // Nur GET, nur https, keine Weiterleitung, nur der App-Name als Kopf.
        for (final r in inner.requests) {
          expect(r.method, 'GET');
          expect(r.url.scheme, 'https');
          expect(r.url.host, host);
          expect(r.followRedirects, isFalse);
          expect(r.headers.keys.map((k) => k.toLowerCase()).toSet(), {
            'user-agent',
          });
          expect(r.headers['user-agent'], 'ramuri');
        }
        source.dispose();
      });
    },
  );

  testWidgets('ohne Einwilligung keine Quelle und keine Anfrage', (
    tester,
  ) async {
    await tester.runAsync(() async {
      consent = false;
      expect(await MapTileSource.open(gate), isNull);
      await expectReason(
        gate.read(MapProvider.openFreeMap.styleUri),
        MapGateReason.noConsent,
      );
      expect(inner.requests, isEmpty);
      expect(
        store.reads,
        0,
        reason: 'ohne Einwilligung auch kein Speicherzugriff',
      );
      expect(gate.counts.networkTotal, 0);
    });
  });

  testWidgets(
    'Widerruf mitten im Betrieb: danach keine Anfrage mehr, auch nicht aus dem Speicher',
    (tester) async {
      await tester.runAsync(() async {
        final source = (await MapTileSource.open(gate))!;
        final provider = source.style.providers['openmaptiles']!;
        await provider.load(const vt.TileKey(13, 4400, 2687));
        final before = inner.requests.length;
        expect(before, greaterThan(0));
        consent = false;
        await provider.load(
          const vt.TileKey(13, 4401, 2687),
        ); // Bibliothek fängt den Fehler ab
        await expectReason(
          gate.read(
            Uri.https(host, '/planet/20260101_000000_pt/13/4400/2687.pbf'),
          ),
          MapGateReason.noConsent,
        );
        expect(inner.requests.length, before);
        source.dispose();
      });
    },
  );

  testWidgets('Widerruf während einer Antwort: nichts gespeichert, Fehler', (
    tester,
  ) async {
    await tester.runAsync(() async {
      inner.hold = Completer<void>();
      final f = gate.read(
        Uri.https(host, '/planet/20260101_000000_pt/13/1/1.pbf'),
      );
      final failed = expectReason(f, MapGateReason.noConsent);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(inner.requests, hasLength(1));
      consent = false;
      inner.hold!.complete();
      await failed;
      expect(store.writes, 0);
    });
  });

  testWidgets(
    'Widerruf während des Speicherlesens: keine Antwort aus dem Speicher',
    (tester) async {
      await tester.runAsync(() async {
        final u = Uri.https(host, '/planet/20260101_000000_pt/13/1/1.pbf');
        store.data[MapGate.storeKey(u)] = Uint8List.fromList([1]);
        store.holdRead = Completer<void>();
        final failed = expectReason(gate.read(u), MapGateReason.noConsent);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        consent = false;
        store.holdRead!.complete();
        await failed;
        expect(gate.counts.stored[MapResource.tile], 0);
      });
    },
  );

  testWidgets(
    'fremder Host, http, POST, Port, Zugangsdaten, unbekannter Pfad: abgelehnt ohne Anfrage',
    (tester) async {
      await tester.runAsync(() async {
        await expectReason(
          gate.read(Uri.https('example.org', '/planet/x/1/1/1.pbf')),
          MapGateReason.host,
        );
        await expectReason(
          gate.read(Uri.https('$host.example.org', '/planet')),
          MapGateReason.host,
        );
        await expectReason(
          gate.read(Uri.http(host, '/planet')),
          MapGateReason.scheme,
        );
        await expectReason(
          gate.post(Uri.https(host, '/planet')),
          MapGateReason.method,
        );
        await expectReason(
          gate.read(Uri.parse('https://$host:8443/planet')),
          MapGateReason.host,
        );
        await expectReason(
          gate.read(Uri.parse('https://u:p@$host/planet')),
          MapGateReason.host,
        );
        await expectReason(
          gate.read(Uri.https(host, '/anderes')),
          MapGateReason.unknownResource,
        );
        expect(inner.requests, isEmpty);
      });
    },
  );

  testWidgets('Weiterleitung (3xx) ist ein Fehler und wird nicht verfolgt', (
    tester,
  ) async {
    await tester.runAsync(() async {
      inner.forceStatus = 302;
      await expectReason(
        gate.read(Uri.https(host, '/planet')),
        MapGateReason.redirect,
      );
      expect(inner.requests, hasLength(1));
      expect(inner.requests.single.followRedirects, isFalse);
      expect((inner.requests.single as dynamic).maxRedirects, 0);
    });
  });

  testWidgets(
    'Speicher: zweiter Abruf aus dem Speicher, Schlüssel ohne Datumspfad, nur 200 gespeichert',
    (tester) async {
      await tester.runAsync(() async {
        final a = Uri.https(host, '/planet/20260101_000000_pt/13/1/1.pbf');
        final b = Uri.https(host, '/planet/20260108_000000_pt/13/1/1.pbf');
        expect(MapGate.storeKey(a), MapGate.storeKey(b));
        await gate.readBytes(a);
        await gate.readBytes(b);
        expect(inner.requests, hasLength(1));
        expect(gate.counts.stored[MapResource.tile], 1);
        expect(store.writes, 1);
        inner.forceStatus = 404;
        await gate.get(
          Uri.https(host, '/planet/20260101_000000_pt/13/2/2.pbf'),
        );
        expect(store.writes, 1, reason: '404 wird nicht gespeichert');
      });
    },
  );

  testWidgets('Ebene ohne Plattencache; Fehler nennen keine URL', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final source = (await MapTileSource.open(gate))!;
      final layer = source.layer();
      expect(layer.diskCacheMaximumSizeInBytes, 0);
      expect(layer.rasterSources, isEmpty);
      source.dispose();
      inner.forceStatus = 302;
      try {
        await gate.read(Uri.https(host, '/planet'));
      } catch (e) {
        expect(e.toString(), isNot(contains(host)));
        expect(e.toString(), isNot(contains('planet')));
      }
      final bad = FailingInner();
      final g2 = MapGate(
        provider: MapProvider.openFreeMap,
        consent: () => true,
        inner: bad,
      );
      try {
        await g2.read(Uri.https(host, '/planet/20260101_000000_pt/13/1/1.pbf'));
        fail('erwartet Fehler');
      } on MapGateException catch (e) {
        expect(e.toString(), isNot(contains('13/1/1')));
        expect(e.reason, MapGateReason.network);
      }
      final src2 = MapGate(
        provider: MapProvider.openFreeMap,
        consent: () => true,
        inner: bad,
      );
      await expectLater(
        MapTileSource.open(src2),
        throwsA(isA<MapSourceUnavailable>()),
      );
    });
  });

  test('Stil ohne lesbares JSON ist ein Fehler', () async {
    final g = MapGate(
      provider: MapProvider.openFreeMap,
      consent: () => true,
      inner: _TextInner(),
    );
    await expectReason(
      g.read(MapProvider.openFreeMap.styleUri),
      MapGateReason.invalidStyle,
    );
  });
}

class FailingInner extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      throw Exception('connect failed to ${request.url}');
}

class _TextInner extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value('kein json'.codeUnits),
        200,
        request: request,
      );
}
