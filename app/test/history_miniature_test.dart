// WP13 D: Miniatur je Lauf im Verlauf (FR-0204, FR-0056): nur mit Einwilligung ein Kartenbild, sonst die Linie;
// nacheinander erzeugt, bei Bedarf, einmal je Lauf; Löschen eines Laufs entfernt die Miniatur. Ohne Netz: ein Fake
// hinter dem Tor zählt jede Anfrage, die Aufnahme ist ersetzt (der Rendertest steht in den Adapter-Tests).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:adapters/adapters.dart' hide RawHeartRate;
import 'package:adapters/map_testing.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/run_miniature.dart';
import 'package:running_app/features/map/map_consent_controller.dart';
import 'package:running_app/features/map/map_consent_scope.dart';
import 'package:running_app/features/map/map_services.dart';
import 'package:running_app/features/map/miniature_service.dart';
import 'package:running_app/features/map/route_map_section.dart'
    show routeMapStyle;

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun;

Finder key(String k) => find.byKey(Key(k));

class _Cache implements MapCacheAdmin {
  @override
  Future<int> sizeBytes() async => 0;
  @override
  Future<void> delete() async {}
}

class _Thumbs implements MapThumbnailStore {
  final Map<String, Uint8List> data = {};
  final List<String> writtenKeys = [];
  final List<int> deletedRuns = [];
  int reads = 0;
  @override
  Future<Uint8List?> read(String key) async {
    reads++;
    return data[key];
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    writtenKeys.add(key);
    data[key] = bytes;
  }

  @override
  Future<void> remove(String key) async => data.remove(key);
  @override
  Future<void> deleteRun(int runId) async {
    deletedRuns.add(runId);
    data.removeWhere((k, _) => k.endsWith(':$runId'));
  }
}

class _World {
  final inner = FakeInner();
  final thumbs = _Thumbs();
  int captures = 0;
  int running = 0;
  int peak = 0;
  Duration captureTime = const Duration(milliseconds: 5);
  bool captureFails = false;
  Completer<void>? hold;
  Uint8List? pngOverride;

  /// Die hängende Aufnahme prüft `cancelled` und gibt auf, sobald es wahr wird (Pause der Route).
  bool pollCancel = false;
  int sawCancelled = 0;

  late final MapServices services = MapServices(
    gate: (consent) => MapGate(
      provider: MapProvider.openFreeMap,
      consent: consent,
      inner: inner,
    ),
    cache: _Cache(),
    thumbnails: thumbs,
    attribution: 'Quelle-Test',
  );

  void install() {
    debugMiniatureCapture =
        (boundary, gate, {cancelled, failuresBefore}) async {
          captures++;
          running++;
          if (running > peak) peak = running;
          try {
            if (hold != null && pollCancel) {
              while (!hold!.isCompleted) {
                if (cancelled?.call() ?? false) {
                  sawCancelled++;
                  return null;
                }
                await Future<void>.delayed(const Duration(milliseconds: 10));
              }
            } else if (hold != null) {
              await hold!.future;
            }
            await Future<void>.delayed(captureTime);
            return captureFails ? null : (pngOverride ?? png1x1);
          } finally {
            running--;
          }
        };
  }
}

Future<(Device, _World)> _start(
  WidgetTester tester, {
  bool consent = false,
  List<int> runs = const [2],
}) async {
  final w = _World()..install();
  addTearDown(() => debugMiniatureCapture = null);
  final d = Device()..map = w.services;
  await d.start(tester, const Locale('de'));
  await d.skipSetup(tester);
  for (var i = 0; i < runs.length; i++) {
    await seedRun(
      d.session,
      DateTime.utc(2030, 1, 1 + i, 8),
      minutes: runs[i],
      bpm: null,
    );
  }
  if (consent) await _controller(tester).grant();
  return (d, w);
}

MapConsentController _controller(WidgetTester tester) =>
    MapConsentScope.of(tester.element(find.byType(Scaffold).first))!;

Future<void> _openHistory(WidgetTester tester) async {
  await tester.tap(key('home_history'));
  await tester.pumpAndSettle();
  await _settle(tester);
}

Future<void> _closeHistory(WidgetTester tester) async {
  await tester.tap(key('home_today'));
  await tester.pumpAndSettle();
  await _settle(tester);
}

/// Lässt Lesen, Aufnahme und Speichern (echte Zeit) zur Ruhe kommen.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => clearMapMemoryCache());

  testWidgets('ohne Einwilligung: nur die Linie, 0 Anfragen, keine Bilder', (
    tester,
  ) async {
    final (d, w) = await _start(tester, runs: [2, 3]);
    // Ein Kartenbild liegt noch im Speicher (etwa nach Widerruf ohne Löschen).
    final ids = (await d.session.runs.list()).map((r) => r.id).toList();
    for (final id in ids) {
      w.thumbs.data[thumbnailKey(miniatureVariant(_styleOf(tester)), id)] =
          png1x1;
    }
    await _openHistory(tester);
    expect(key('miniature_line'), findsNWidgets(2));
    expect(key('miniature_image'), findsNothing);
    expect(w.inner.requests, isEmpty);
    expect(w.thumbs.reads, 0);
    expect(w.captures, 0);
  });

  testWidgets('Laufband ohne Positionen: keine Miniatur', (tester) async {
    final (d, _) = await _start(tester, runs: [2]);
    final run = await d.session.runs.create(
      startedAt: DateTime.utc(2030, 2, 1, 8),
    );
    await d.session.rawData.append(
      run.id,
      RawBatch(
        heartRates: [
          for (var i = 0; i < 90; i++)
            RawHeartRate(
              time: DateTime.utc(2030, 2, 1, 8).add(Duration(seconds: i)),
              source: 'strap',
              bpm: 140,
              contact: SensorContact.good,
            ),
        ],
      ),
    );
    await d.session.runs.setState(
      run.id,
      RunState.finished,
      endedAt: DateTime.utc(2030, 2, 1, 8, 1, 30),
    );
    await _openHistory(tester);
    expect(key('history_run_${run.id}'), findsOneWidget);
    expect(key('miniature_line'), findsOneWidget, reason: 'nur der GPS-Lauf');
    expect(tester.getSize(key('history_miniature_${run.id}')).width, 0);
  });

  testWidgets(
    'mit Einwilligung: nacheinander erzeugt, PNG im Speicher, einmal je Lauf',
    (tester) async {
      final (_, w) = await _start(tester, consent: true, runs: [2, 3, 4]);
      await _openHistory(tester);
      expect(key('miniature_image'), findsNWidgets(3));
      expect(w.peak, 1, reason: 'strikt nacheinander');
      expect(w.captures, 3);
      expect(w.thumbs.writtenKeys.length, 3);
      expect(w.thumbs.writtenKeys.every((k) => k.startsWith('thumb:')), isTrue);
      expect(find.text('Quelle-Test'), findsNWidgets(3));
      // Erneut öffnen: aus dem Speicher, keine neue Aufnahme.
      await _closeHistory(tester);
      await _openHistory(tester);
      expect(key('miniature_image'), findsNWidgets(3));
      expect(w.captures, 3);
    },
  );

  testWidgets(
    'Detail eines Laufs darüber: Aufnahme pausiert, nichts gespeichert; zurück: weiter (S6, Verdrahtung)',
    (tester) async {
      final (d, w) = await _start(tester, consent: true, runs: [2]);
      w.hold = Completer<void>();
      w.pollCancel = true;
      await _openHistory(tester);
      expect(w.captures, 1);
      final id = (await d.session.runs.list()).first.id;
      await tester.tap(key('history_run_$id'));
      await tester.pumpAndSettle();
      await _settle(tester);
      expect(w.sawCancelled, 1, reason: 'verdeckte Route: Aufnahme gibt auf');
      expect(w.thumbs.writtenKeys, isEmpty);
      expect(w.captures, 1);
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pumpAndSettle();
      w.hold!.complete();
      await _settle(tester);
      expect(w.captures, 2, reason: 'nach der Rückkehr neu aufgenommen');
      expect(w.thumbs.writtenKeys.length, 1);
    },
  );

  testWidgets('Widerruf: keine Kartenbilder mehr, kein Lesen, keine Anfrage', (
    tester,
  ) async {
    final (_, w) = await _start(tester, consent: true, runs: [2, 3]);
    await _openHistory(tester);
    expect(key('miniature_image'), findsNWidgets(2));
    await _controller(tester).revoke();
    await _settle(tester);
    expect(key('miniature_image'), findsNothing);
    expect(key('miniature_line'), findsNWidgets(2));
    final reads = w.thumbs.reads;
    final requests = w.inner.requests.length;
    expect(w.thumbs.data, isNotEmpty, reason: 'Widerruf löscht nicht');
    await _closeHistory(tester);
    await _openHistory(tester);
    expect(key('miniature_image'), findsNothing);
    expect(w.thumbs.reads, reads);
    expect(w.inner.requests.length, requests);
    expect(w.captures, 2);
  });

  testWidgets(
    'Fehler: Linie, nichts gespeichert, Wiederholung erst beim nächsten Aufbau',
    (tester) async {
      final (_, w) = await _start(tester, consent: true, runs: [2]);
      w.captureFails = true;
      await _openHistory(tester);
      expect(key('miniature_line'), findsOneWidget);
      expect(key('miniature_image'), findsNothing);
      expect(w.thumbs.writtenKeys, isEmpty);
      expect(w.captures, 1);
      await _settle(tester);
      expect(w.captures, 1, reason: 'kein Dauerversuch');
      await _closeHistory(tester);
      w.captureFails = false;
      await _openHistory(tester);
      expect(w.captures, 2);
      expect(key('miniature_image'), findsOneWidget);
    },
  );

  testWidgets(
    'Verdrängung: fehlt die Miniatur im Speicher, wird sie neu erzeugt',
    (tester) async {
      final (_, w) = await _start(tester, consent: true, runs: [2]);
      await _openHistory(tester);
      expect(w.captures, 1);
      w.thumbs.data.clear();
      await _closeHistory(tester);
      await _openHistory(tester);
      expect(w.captures, 2);
      expect(key('miniature_image'), findsOneWidget);
    },
  );

  testWidgets('Löschen eines Laufs entfernt seine Miniatur', (tester) async {
    final (d, w) = await _start(tester, consent: true, runs: [2, 3]);
    await _openHistory(tester);
    final ids = (await d.session.runs.list()).map((r) => r.id).toList();
    final gone = ids.first;
    await tester.tap(key('history_delete_$gone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen').last);
    await tester.pumpAndSettle();
    await _settle(tester);
    expect(w.thumbs.deletedRuns, [gone]);
    expect(w.thumbs.data.keys.any((k) => k.endsWith(':$gone')), isFalse);
    expect(w.thumbs.data.keys.any((k) => k.endsWith(':${ids.last}')), isTrue);
  });

  testWidgets(
    'Löschen eines Laufs, dessen Miniatur gerade entsteht: Abbruch, danach wird nichts gespeichert',
    (tester) async {
      final (d, w) = await _start(tester, consent: true, runs: [2, 3]);
      w.hold = Completer<void>(); // die erste Aufnahme hängt
      await _openHistory(tester);
      expect(w.captures, 1);
      final ids = (await d.session.runs.list()).map((r) => r.id).toList();
      final gone = ids.first; // der oberste Eintrag ist der laufende
      await tester.tap(key('history_delete_$gone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lauf löschen').last);
      await tester.pumpAndSettle();
      w.hold!.complete();
      await _settle(tester);
      expect(
        w.thumbs.writtenKeys.where((k) => k.endsWith(':$gone')),
        isEmpty,
        reason: 'verwaistes Bild eines gelöschten Laufs',
      );
      expect(w.thumbs.data.keys.any((k) => k.endsWith(':$gone')), isFalse);
    },
  );

  testWidgets(
    'Warteschlange: wegscrollen nimmt Einträge heraus, sichtbare zuerst',
    (tester) async {
      final (d, w) = await _start(
        tester,
        consent: true,
        runs: List.filled(14, 2),
      );
      tester.view.physicalSize = const Size(411, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      w.hold = Completer<void>(); // die erste Aufnahme hängt
      await _openHistory(tester);
      expect(w.captures, 1);
      // Ans Ende scrollen: die oberen Einträge (nur Wartende) fallen aus der Liste.
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pump();
      w.hold!.complete();
      await _settle(tester);
      final ids = (await d.session.runs.list()).map((r) => r.id).toList();
      final captured = w.thumbs.writtenKeys
          .map((k) => int.parse(k.split(':').last))
          .toList();
      // Die hängende Aufnahme gehörte zum obersten Eintrag; er scrollte weg, ihr Bild wird nicht gespeichert. Danach
      // kommen nur Einträge am Ende der Liste (sichtbar oder knapp daneben), nie die weggescrollten oberen.
      expect(captured, isNotEmpty);
      expect(captured, isNot(contains(ids.first)));
      expect(
        captured.every((id) => ids.indexOf(id) >= ids.length - 6),
        isTrue,
        reason: 'Weggescrollte Einträge wurden erzeugt: $captured',
      );
      final order = captured.map(ids.indexOf).toList();
      expect(
        order.take(2).toSet(),
        {ids.length - 2, ids.length - 1},
        reason:
            'sichtbare Einträge zuerst (die untersten), dann die knapp daneben: $order',
      );
      expect(w.captures, lessThan(14));
      expect(w.peak, 1);
    },
  );

  testWidgets(
    'Tab-Wechsel: Scrollposition bleibt, Daten werden frisch geladen',
    (tester) async {
      final (d, _) = await _start(tester, runs: List.filled(14, 2));
      tester.view.physicalSize = const Size(411, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _openHistory(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      double offset() => tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
      final before = offset();
      expect(before, greaterThan(500));
      // Ein neuer Lauf kommt dazu, während der Verlauf nicht zu sehen ist.
      await _closeHistory(tester);
      await seedRun(
        d.session,
        DateTime.utc(2031, 1, 1, 8),
        minutes: 2,
        bpm: null,
      );
      await _openHistory(tester);
      expect(offset(), before);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(key('history_run_15'), findsOneWidget, reason: 'frisch geladen');
    },
  );

  // Bildschirmfoto hell und dunkel mit echter Schrift (Layout statt Emulator). Nur mit SHOT_DIR.
  for (final dark in [false, true]) {
    testWidgets(
      'Darstellung ${dark ? 'dunkel' : 'hell'}: Verlauf mit Miniaturen',
      (tester) async {
        await tester.runAsync(() async {
          for (final (family, files) in [
            ('Manrope', ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']),
            ('Sora', ['Medium', 'SemiBold', 'Bold']),
          ]) {
            final loader = FontLoader(family);
            for (final f in files) {
              final bytes = File('assets/fonts/$family-$f.ttf')
                  .readAsBytesSync();
              loader.addFont(Future.value(ByteData.sublistView(bytes)));
            }
            await loader.load();
          }
        });
        final (_, w) = await _start(tester, consent: true, runs: [2, 4, 3, 5]);
        final fake = await tester.runAsync(_fakeMapPng);
        w.pngOverride = fake;
        tester.view.physicalSize = const Size(780, 1500);
        tester.view.devicePixelRatio = 2;
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await _openHistory(tester);
        for (
          var i = 0;
          i < 10 && key('miniature_image').evaluate().length < 4;
          i++
        ) {
          await _settle(tester);
        }
        expect(key('miniature_image'), findsNWidgets(4));
        final dir = Platform.environment['SHOT_DIR'];
        if (dir != null) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byType(RepaintBoundary).first,
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            File('$dir/wp13-d-shot-${dark ? 'dunkel' : 'hell'}.png')
                .writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      },
    );
  }

  test('Vorgaben: höchstens 4 parallele Anfragen, Variante trägt Fassung und Farben', () {
    expect(miniatureMaxParallel, 4);
    const base = RouteMapStyle(
      lineColor: Color(0xFF112233),
      startColor: Color(0xFF00AA00),
      endColor: Color(0xFFAA0000),
      markerBorderColor: Color(0xFFFFFFFF),
      backgroundColor: Color(0xFFEEEEEE),
      attributionBackground: Color(0xCCFFFFFF),
      attributionForeground: Color(0xFF000000),
    );
    const dark = RouteMapStyle(
      lineColor: Color(0xFF445566),
      startColor: Color(0xFF00AA00),
      endColor: Color(0xFFAA0000),
      markerBorderColor: Color(0xFFFFFFFF),
      backgroundColor: Color(0xFF111111),
      attributionBackground: Color(0xCCFFFFFF),
      attributionForeground: Color(0xFF000000),
    );
    expect(miniatureVariant(base), isNot(miniatureVariant(dark)));
    expect(miniatureVariant(base), startsWith('v1-480x240-'));
    expect(runMiniatureWidth / runMiniatureHeight, 2);
  });
}

RouteMapStyle _styleOf(WidgetTester tester) =>
    routeMapStyle(tester.element(find.byType(Scaffold).first));

/// Ein Kartenbild als Platzhalter für das Bildschirmfoto: helles Land, Wasser, Park und eine Route.
Future<Uint8List> _fakeMapPng() async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(
    const Rect.fromLTWH(0, 0, 480, 240),
    Paint()..color = const Color(0xFFF2EFE9),
  );
  c.drawRect(
    const Rect.fromLTWH(0, 150, 480, 50),
    Paint()..color = const Color(0xFFAAD3DF),
  );
  c.drawRect(
    const Rect.fromLTWH(300, 20, 140, 90),
    Paint()..color = const Color(0xFFC8FACC),
  );
  final line = Paint()
    ..color = const Color(0xFF0E8F7E)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 5
    ..strokeCap = StrokeCap.round;
  c.drawPath(
    Path()
      ..moveTo(60, 190)
      ..lineTo(150, 100)
      ..lineTo(260, 130)
      ..lineTo(380, 50),
    line,
  );
  final image = await recorder.endRecording().toImage(480, 240);
  return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
}
