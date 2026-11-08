// WP13 D: Miniatur der Route: Aufnahme der unsichtbaren Karte nach Ladeende, Zeitgrenze, Fehler, gleichzeitige
// Anfragen, Speicher (Löschen je Lauf, Größe und Zeit nach 50 Miniaturen, kein Klartext). Ohne Netz.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../storage/support.dart' show testKey;
import 'map_fakes.dart';
import 'plaintext_scan.dart';

const _style = RouteMapStyle(
  lineColor: Color(0xFF112233),
  startColor: Color(0xFF00AA00),
  endColor: Color(0xFFAA0000),
  markerBorderColor: Color(0xFFFFFFFF),
  backgroundColor: Color(0xFFEEEEEE),
  attributionBackground: Color(0xCCFFFFFF),
  attributionForeground: Color(0xFF000000),
);

const _a = RoutePoint(52.5200, 13.4000);
const _b = RoutePoint(52.5230, 13.4100);
const _c = RoutePoint(52.5270, 13.4150);
const _d = RoutePoint(52.5300, 13.4250);
final _route = [
  [_a, _b],
  [_c, _d],
];

/// Zählt gleichzeitige Anfragen.
class _Counting extends FakeInner {
  int now = 0;
  int peak = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest r) async {
    now++;
    if (now > peak) peak = now;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return await super.send(r);
    } finally {
      now--;
    }
  }
}

void main() {
  late FakeInner inner;
  late MapGate gate;

  setUp(() {
    vt.VectorTileLayer.clearMemoryCache();
    inner = FakeInner();
    gate = MapGate(
      provider: MapProvider.openFreeMap,
      consent: () => true,
      inner: inner,
    );
  });

  Future<Uint8List?> capture(
    WidgetTester tester,
    GlobalKey key, {
    Duration quiet = const Duration(milliseconds: 80),
    Duration limit = const Duration(seconds: 8),
    bool Function()? cancelled,
  }) async {
    final source = (await tester.runAsync(() => MapTileSource.open(gate)))!;
    final before = gate.failures;
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -700,
              top: 0,
              child: ThumbnailMap(
                boundary: key,
                source: source,
                route: _route,
                style: _style,
              ),
            ),
          ],
        ),
      ),
    );
    return tester.runAsync<Uint8List?>(
      () => captureThumbnail(
        key,
        gate,
        quiet: quiet,
        settle: const Duration(milliseconds: 40),
        limit: limit,
        cancelled: cancelled,
        failuresBefore: before,
        frame: () async {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
        },
      ),
    );
  }

  test('Vorgaben aus R008 Hinweis 5', () {
    expect(thumbnailQuiet, const Duration(milliseconds: 400));
    expect(thumbnailSettle, const Duration(milliseconds: 250));
    expect(thumbnailTimeLimit, const Duration(seconds: 15));
  });

  testWidgets(
    'Aufnahme nach Ladeende: PNG, zwei Linien (Lücke nicht verbunden), Kacheln nur zur Route',
    (tester) async {
      // Alle Verzeichnisse, die path_provider liefern könnte (Plattencache der Bibliothek), zeigen auf ein leeres
      // Verzeichnis; danach muss es leer sein (R008 Hinweis 2).
      final scan = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('thumb_scan'),
      ))!;
      addTearDown(() => scan.deleteSync(recursive: true));
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => scan.path,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final key = GlobalKey();
      final png = await capture(tester, key);
      expect(png, isNotNull);
      final left = await tester.runAsync(
        () => scan.list(recursive: true).map((e) => e.path).toList(),
      );
      expect(
        left,
        isEmpty,
        reason: 'kein Plattencache außerhalb des Speichers',
      );
      expect(png!.sublist(0, 8), [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]);
      expect(
        mapPolylineCount(key.currentContext!),
        2,
        reason: 'Pause und Lücke: zwei Teile, nie verbunden',
      );
      expect(inner.count((u) => u.path.endsWith('.pbf')), greaterThan(0));
      expect(gate.failures, 0);
    },
  );

  testWidgets('wartet, bis das Netz ruhig ist: nie vor der letzten Antwort', (
    tester,
  ) async {
    final source = (await tester.runAsync(() => MapTileSource.open(gate)))!;
    inner.hold = Completer<void>();
    final before = gate.failures;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -700,
              child: ThumbnailMap(
                boundary: key,
                source: source,
                route: _route,
                style: _style,
              ),
            ),
          ],
        ),
      ),
    );
    final sw = Stopwatch()..start();
    var releasedAt = Duration.zero;
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
        releasedAt = sw.elapsed;
        inner.hold!.complete();
      }),
    );
    final png = await tester.runAsync<Uint8List?>(
      () => captureThumbnail(
        key,
        gate,
        quiet: const Duration(milliseconds: 80),
        settle: const Duration(milliseconds: 40),
        failuresBefore: before,
        frame: () async {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
        },
      ),
    );
    expect(png, isNotNull);
    expect(releasedAt, greaterThan(Duration.zero));
    expect(
      sw.elapsed,
      greaterThanOrEqualTo(releasedAt + const Duration(milliseconds: 80)),
      reason: 'erst nach der letzten Antwort und der Ruhezeit',
    );
  });

  testWidgets('Fehler beim Laden der Kacheln: nichts zum Speichern', (
    tester,
  ) async {
    inner.failWhere = (u) => u.path.endsWith('.pbf');
    final png = await capture(tester, GlobalKey());
    expect(png, isNull);
    expect(gate.failures, greaterThan(0));
    // Die Bibliothek wiederholt fehlgeschlagene Kacheln mit Wartezeit (Zeitgeber der Test-Uhr).
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(seconds: 2));
    }
  });

  testWidgets('Zeitgrenze: das Laden endet nicht, nichts zum Speichern', (
    tester,
  ) async {
    final source = (await tester.runAsync(() => MapTileSource.open(gate)))!;
    inner.hold = Completer<void>(); // Kacheln kommen nie an
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -700,
              child: ThumbnailMap(
                boundary: key,
                source: source,
                route: _route,
                style: _style,
              ),
            ),
          ],
        ),
      ),
    );
    final sw = Stopwatch()..start();
    final png = await tester.runAsync<Uint8List?>(
      () => captureThumbnail(
        key,
        gate,
        quiet: const Duration(milliseconds: 50),
        settle: const Duration(milliseconds: 30),
        limit: const Duration(milliseconds: 600),
        frame: () async {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          await tester.pump(const Duration(milliseconds: 16));
        },
      ),
    );
    expect(png, isNull);
    expect(sw.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 600)));
    inner.hold!.complete();
  });

  testWidgets('Abbruch (wegscrollen, Widerruf): nichts zum Speichern', (
    tester,
  ) async {
    final png = await capture(tester, GlobalKey(), cancelled: () => true);
    expect(png, isNull);
  });

  test('höchstens 4 Anfragen zugleich über das Tor', () async {
    final counting = _Counting();
    final g = MapGate(
      provider: MapProvider.openFreeMap,
      consent: () => true,
      inner: counting,
    )..maxParallel = 4;
    final uris = [
      for (var i = 0; i < 12; i++)
        Uri.parse(
          'https://tiles.openfreemap.org/planet/20260101_000000_pt/14/${8800 + i}/5370.pbf',
        ),
    ];
    await Future.wait([for (final u in uris) g.readBytes(u)]);
    expect(counting.peak, lessThanOrEqualTo(4));
    expect(counting.peak, greaterThan(1), reason: 'es lief wirklich parallel');
    expect(counting.requests.length, 12);
    // Gegenprobe: ohne Grenze laufen alle zugleich.
    final free = _Counting();
    final g2 = MapGate(
      provider: MapProvider.openFreeMap,
      consent: () => true,
      inner: free,
    );
    await Future.wait([for (final u in uris) g2.readBytes(u)]);
    expect(free.peak, 12);
  });

  group('Speicher', () {
    late Directory dir;
    late String path;
    final key = testKey(3);
    setUp(() {
      dir = Directory.systemTemp.createTempSync('wp13d_');
      path = '${dir.path}/$mapCacheFileName';
    });
    tearDown(() => dir.deleteSync(recursive: true));

    EncryptedMapTileStore store() => EncryptedMapTileStore(
      directory: () async => dir.path,
      key: () async => key,
    );

    test(
      'Löschen eines Laufs entfernt seine Miniaturen, nicht fremde',
      () async {
        final s = store();
        final v1 = thumbnailKey('v1-a', 1);
        final v2 = thumbnailKey('v1-b', 1);
        await s.write(v1, Uint8List.fromList([1]));
        await s.write(v2, Uint8List.fromList([2]));
        await s.write(thumbnailKey('v1-a', 11), Uint8List.fromList([3]));
        await s.write(thumbnailKey('v1-a', 21), Uint8List.fromList([4]));
        await s.write('map:/planet/_/1', Uint8List.fromList([5]));
        await s.deleteRun(1);
        expect(await s.read(v1), isNull);
        expect(await s.read(v2), isNull);
        expect(await s.read(thumbnailKey('v1-a', 11)), isNotNull);
        expect(await s.read(thumbnailKey('v1-a', 21)), isNotNull);
        expect(await s.read('map:/planet/_/1'), isNotNull);
        await s.close();
      },
    );

    test('50 Miniaturen: PNG im Speicher, kein Klartext, Größe und Zeit', () async {
      // Ein echtes PNG aus dem Host (feste Größe wie die Miniatur).
      final s = store();
      final png = await _realPng();
      expect(
        plaintextHits(png),
        isNotEmpty,
        reason: 'Positivkontrolle: PNG-Signatur',
      );
      final big = Uint8List(48 * 1000)..setRange(0, png.length, png);
      for (var i = 0; i < big.length - png.length; i++) {
        big[png.length + i] =
            (i * 31 + 7) & 0xff; // unregelmäßig wie Bildpunkte
      }
      final w = Stopwatch()..start();
      for (var i = 1; i <= 50; i++) {
        await s.write(thumbnailKey('v1-a', i), big);
      }
      final writeMs = w.elapsedMilliseconds / 50;
      w.reset();
      for (var i = 1; i <= 50; i++) {
        expect((await s.read(thumbnailKey('v1-a', i)))!.length, big.length);
      }
      final readMs = w.elapsedMilliseconds / 50;
      await s.close();
      var total = 0;
      for (final suffix in mapCacheSuffixes) {
        final f = File('$path$suffix');
        if (f.existsSync()) {
          total += f.lengthSync();
          expect(
            plaintextHits(f.readAsBytesSync()),
            isEmpty,
            reason: 'Datei $suffix ohne Klartext',
          );
        }
      }
      // ignore: avoid_print
      print(
        'WP13D-MESSUNG 50 Miniaturen à ${big.length} B: Datei $total B, '
        'Schreiben ${writeMs.toStringAsFixed(1)} ms, Lesen ${readMs.toStringAsFixed(1)} ms je Miniatur (Host)',
      );
      expect(total, lessThan(50 * big.length * 1.3));
    });
  });
}

/// Ein echtes PNG (kleine Zeichnung) wie `toImage` es liefert.
Future<Uint8List> _realPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 64, 32),
    Paint()..color = const Color(0xFFEEDDCC),
  );
  final image = await recorder.endRecording().toImage(64, 32);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
