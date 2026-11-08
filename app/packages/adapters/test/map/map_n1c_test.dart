// WP13 N1c: Kachel-Gesundheit des Tors (M1), Alter von Stil und TileJSON (M2), Zeitgrenze und Höchstgröße (S7).
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'map_fakes.dart';

final _style = Uri.https(host, '/styles/liberty');
final _tilejson = Uri.https(host, '/planet');
Uri _tile(int x) => Uri.https(host, '/planet/20260101_000000_pt/14/$x/5.pbf');

void main() {
  late FakeInner inner;
  late MemoryStore store;
  late DateTime now;
  late bool consent;

  MapGate gate({
    Duration timeout = mapRequestTimeout,
    int maxBody = mapMaxBodyBytes,
    MapTileStore? s,
  }) => MapGate(
    provider: MapProvider.openFreeMap,
    consent: () => consent,
    store: s ?? store,
    inner: inner,
    now: () => now,
    requestTimeout: timeout,
    maxBodyBytes: maxBody,
  );

  setUp(() {
    inner = FakeInner();
    store = MemoryStore();
    now = DateTime.utc(2026, 11, 1);
    consent = true;
  });

  Future<void> ignore(Future<Object?> f) async {
    try {
      await f;
    } catch (_) {}
  }

  group('M1 Kachel-Gesundheit', () {
    test('Fehler ohne Treffer: nach dem Limit gescheitert, ein Treffer holt zurück', () async {
      final g = gate();
      final seen = <bool>[];
      g.tilesFailed.addListener(() => seen.add(g.tilesFailed.value));
      inner.failWhere = (u) => u.path.endsWith('.pbf');
      for (var i = 0; i < mapTileFailureLimit - 1; i++) {
        await ignore(g.read(_tile(i)));
      }
      expect(g.tilesFailed.value, isFalse, reason: 'unter dem Limit');
      await ignore(g.read(_tile(9)));
      expect(g.tilesFailed.value, isTrue);
      inner.failWhere = null;
      await g.read(_tile(10));
      expect(g.tilesFailed.value, isFalse, reason: 'Erholung beim Treffer');
      expect(seen, [true, false]);
    });

    test(
      'ein einzelner Fehlschlag fällt noch nicht zurück (Limit größer als 1)',
      () async {
        final g = gate();
        inner.failWhere = (u) => u.path.endsWith('.pbf');
        await ignore(g.read(_tile(1)));
        expect(g.tilesFailed.value, isFalse);
        expect(mapTileFailureLimit, greaterThan(1));
      },
    );

    test('durchgehend 404 zählt als Fehlschlag', () async {
      final g = gate();
      inner.statusWhere = (u) => u.path.endsWith('.pbf') ? 404 : null;
      for (var i = 0; i < mapTileFailureLimit; i++) {
        final r = await g.send(http.Request('GET', _tile(i)));
        expect(r.statusCode, 404);
      }
      expect(g.tilesFailed.value, isTrue);
      expect(g.failures, 0, reason: '404 bleibt für die Miniatur kein Fehler');
    });

    test(
      'Treffer aus dem Speicher zählt; danach scheitert nichts mehr',
      () async {
        final g = gate();
        await g.read(_tile(1)); // Netz, Treffer, gespeichert
        inner.failWhere = (u) => true;
        for (var i = 0; i < 5; i++) {
          await ignore(g.read(_tile(100 + i)));
        }
        expect(g.tilesFailed.value, isFalse, reason: 'es gab einen Treffer');
        // frischer Tor-Zustand, nur der Speicher trifft
        final g2 = gate();
        await g2.read(_tile(1)); // aus dem Speicher
        expect(g2.counts.stored[MapResource.tile], 1);
        for (var i = 0; i < 5; i++) {
          await ignore(g2.read(_tile(200 + i)));
        }
        expect(g2.tilesFailed.value, isFalse);
      },
    );

    test(
      'Stil, Sprites, Glyphen und fehlende Einwilligung zählen nicht',
      () async {
        final g = gate();
        inner.failWhere = (u) => true;
        for (var i = 0; i < 5; i++) {
          await ignore(g.read(Uri.https(host, '/fonts/F/$i-255.pbf')));
          await ignore(g.read(Uri.https(host, '/sprites/test/sprite$i.json')));
        }
        consent = false;
        for (var i = 0; i < 5; i++) {
          await ignore(g.read(_tile(i)));
        }
        expect(g.tilesFailed.value, isFalse);
      },
    );

    test('resetTileHealth beginnt neu', () async {
      final g = gate();
      inner.failWhere = (u) => u.path.endsWith('.pbf');
      for (var i = 0; i < mapTileFailureLimit; i++) {
        await ignore(g.read(_tile(i)));
      }
      expect(g.tilesFailed.value, isTrue);
      g.resetTileHealth();
      expect(g.tilesFailed.value, isFalse);
    });
  });

  group('M2 Alter von Stil und TileJSON', () {
    test(
      'jung: aus dem Speicher, kein Netz; Alter nur im gespeicherten Wert',
      () async {
        await gate().read(_tilejson);
        expect(inner.count((u) => u.path == '/planet'), 1);
        expect(store.data.keys, ['map:/planet'], reason: 'kein Nebeneintrag');
        expect(store.data['map:/planet']!.length, greaterThan(8));
        now = now.add(mapStyleMaxAge - const Duration(minutes: 1));
        await gate().read(_tilejson);
        expect(inner.count((u) => u.path == '/planet'), 1);
      },
    );

    test('datierter Wechsel: nach dem Höchstalter neu geholt, neuer Kachelpfad gilt', () async {
      final first = await gate().read(_tilejson);
      expect(first, contains('20260101_000000_pt'));
      inner.tileDate = '20261108_000000_pt';
      now = now.add(mapStyleMaxAge + const Duration(minutes: 1));
      final second = await gate().read(_tilejson);
      expect(second, contains('20261108_000000_pt'));
      expect(inner.count((u) => u.path == '/planet'), 2);
      // der neue Stand ist gespeichert und wieder jung
      final third = await gate().read(_tilejson);
      expect(third, contains('20261108_000000_pt'));
      expect(inner.count((u) => u.path == '/planet'), 2);
    });

    test('abgelaufen und Netz weg: der alte Eintrag gilt weiter', () async {
      await gate().read(_style);
      now = now.add(mapStyleMaxAge + const Duration(days: 30));
      inner.failWhere = (u) => true;
      final g = gate();
      final body = await g.read(_style);
      expect(jsonDecode(body), isA<Map>());
      expect(g.failures, 0);
      // Fehlerstatus des Anbieters ebenso
      inner.failWhere = null;
      inner.statusWhere = (u) => 503;
      expect(await gate().read(_style), isNotEmpty);
    });

    test(
      'Widerruf während des Abrufs: kein Rückgriff auf den alten Eintrag',
      () async {
        await gate().read(_style);
        now = now.add(mapStyleMaxAge + const Duration(days: 1));
        inner.hold = Completer<void>();
        final f = gate().read(_style);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        consent = false;
        inner.hold!.complete();
        await expectLater(
          f,
          throwsA(
            isA<MapGateException>().having(
              (e) => e.reason,
              'reason',
              MapGateReason.noConsent,
            ),
          ),
        );
      },
    );

    test('abgelaufen, Netz weg, kein Eintrag: Fehler', () async {
      inner.failWhere = (u) => true;
      await expectLater(gate().read(_style), throwsA(isA<MapGateException>()));
    });

    test('kaputter Stil (200) wird nicht gespeichert', () async {
      inner.bodyWhere = (u) => Uint8List.fromList(utf8.encode('{"a":'));
      await expectLater(
        gate().read(_style),
        throwsA(
          isA<MapGateException>().having(
            (e) => e.reason,
            'reason',
            MapGateReason.invalidStyle,
          ),
        ),
      );
      expect(store.writes, 0);
      // Stil ohne sources/layers und TileJSON ohne tiles ebenso
      inner.bodyWhere = (u) => Uint8List.fromList(utf8.encode('{"x":1}'));
      await expectLater(gate().read(_style), throwsA(isA<MapGateException>()));
      await expectLater(
        gate().read(_tilejson),
        throwsA(isA<MapGateException>()),
      );
      expect(store.writes, 0);
    });

    test('abgelaufen und der neue Stil ist kaputt: alter bleibt, nichts überschrieben', () async {
      await gate().read(_style);
      final before = Uint8List.fromList(store.data['map:/styles/liberty']!);
      now = now.add(mapStyleMaxAge + const Duration(days: 1));
      inner.bodyWhere = (u) => Uint8List.fromList(utf8.encode('kaputt'));
      expect(jsonDecode(await gate().read(_style)), isA<Map>());
      expect(store.data['map:/styles/liberty'], before);
    });

    test(
      'unlesbarer gespeicherter Eintrag wird entfernt und neu geholt',
      () async {
        store.data['map:/styles/liberty'] = Uint8List.fromList(
          utf8.encode('kein Zeitstempel, kein Stil'),
        );
        final body = await gate().read(_style);
        expect(jsonDecode(body), isA<Map>());
        expect(store.removes, 1);
        expect(inner.count((u) => u.path.startsWith('/styles/')), 1);
        // nun lesbar und jung: kein Abruf, kein weiteres Entfernen
        await gate().read(_style);
        expect(store.removes, 1);
        expect(inner.count((u) => u.path.startsWith('/styles/')), 1);
      },
    );

    test('Rückwärtssprung der Uhr: gilt als abgelaufen', () async {
      await gate().read(_tilejson);
      now = now.subtract(const Duration(days: 2));
      await gate().read(_tilejson);
      expect(inner.count((u) => u.path == '/planet'), 2);
    });
  });

  group('S7 Zeitgrenze und Größe', () {
    test('Vorgaben: Grenze über den 431 kB aus R008', () {
      expect(mapMaxBodyBytes, greaterThan(431 * 1000));
      expect(mapRequestTimeout, greaterThan(const Duration(seconds: 10)));
    });

    test('keine Antwort: Zeitgrenze, Fehler, nichts gespeichert', () async {
      inner.hold = Completer<void>();
      final g = gate(timeout: const Duration(milliseconds: 40));
      await expectLater(
        g.read(_tilejson),
        throwsA(
          isA<MapGateException>().having(
            (e) => e.reason,
            'reason',
            MapGateReason.timeout,
          ),
        ),
      );
      await expectLater(g.read(_tile(1)), throwsA(isA<MapGateException>()));
      expect(store.writes, 0);
      expect(g.inFlight, 0);
      await Future<void>.delayed(Duration.zero);
      expect(
        inner.aborted,
        inner.requests.length,
        reason: 'jede Anfrage wurde abgebrochen',
      );
      expect(inner.aborted, greaterThanOrEqualTo(2));
    });

    test('Netzfehler: die Verbindung wird abgebrochen', () async {
      inner.failWhere = (u) => true;
      final g = gate();
      await expectLater(g.read(_tilejson), throwsA(isA<MapGateException>()));
      await Future<void>.delayed(Duration.zero);
      expect(inner.aborted, 1);
    });

    for (final chunked in [false, true]) {
      test(
        'Körper über der Grenze (${chunked ? 'ohne' : 'mit'} Längenangabe): Fehler, nichts gespeichert',
        () async {
          inner.chunked = chunked;
          inner.bodyWhere = (u) => Uint8List(1001);
          final g = gate(maxBody: 1000);
          await expectLater(
            g.read(_tile(1)),
            throwsA(
              isA<MapGateException>().having(
                (e) => e.reason,
                'reason',
                MapGateReason.tooLarge,
              ),
            ),
          );
          expect(store.writes, 0);
          await Future<void>.delayed(Duration.zero);
          expect(
            inner.aborted,
            1,
            reason: 'Verbindung nach Überschreitung abgebrochen',
          );
          inner.bodyWhere = (u) => Uint8List(1000); // genau die Grenze geht
          expect((await g.readBytes(_tile(2))).length, 1000);
          expect(store.writes, 1);
        },
      );
    }
  });
}
