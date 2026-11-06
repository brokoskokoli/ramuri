import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:running_app/features/summary/run_charts.dart';
import 'package:running_app/l10n/app_localizations.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show key, openHistory, started, text;

const double _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

/// Beendeter Lauf mit Höhe: [seconds] mit 3 m/s. In [noPosition] (Sekunden von,
/// bis) gibt es keine Positionen und keine Höhe, in [pause] eine manuelle
/// Pause ohne Messwerte.
Future<int> seedDetailRun(
  StorageSession s,
  DateTime start, {
  int seconds = 600,
  bool heartRate = true,
  (int, int)? noPosition,
  (int, int)? pause,
  (int, int)? noHeartRate,
}) async {
  final run = await s.runs.create(startedAt: start);
  bool inside((int, int)? r, int i) => r != null && i >= r.$1 && i < r.$2;
  await s.rawData.append(
    run.id,
    RawBatch(
      positions: [
        for (var i = 0; i <= seconds; i++)
          if (!inside(noPosition, i) && !inside(pause, i))
            RawPosition(
              time: start.add(Duration(seconds: i)),
              source: 'gps',
              latitude: 10 + i * 3 / _metersPerDegree,
              longitude: 20 + (i % 2) * 0.000005,
              accuracyMeters: 5,
            ),
      ],
      altitudes: [
        for (var i = 0; i <= seconds; i++)
          if (!inside(noPosition, i) && !inside(pause, i))
            RawAltitude(
              time: start.add(Duration(seconds: i)),
              source: 'gps',
              meters: 100 + (i % 50).toDouble(),
              verticalAccuracyMeters: 3,
            ),
      ],
      heartRates: [
        if (heartRate)
          for (var i = 0; i <= seconds; i++)
            if (!inside(pause, i) && !inside(noHeartRate, i))
              RawHeartRate(
                time: start.add(Duration(seconds: i)),
                source: 'strap',
                bpm: 140 + i % 10,
                contact: SensorContact.good,
              ),
      ],
    ),
  );
  if (pause != null) {
    final id = await s.markers.openGap(
      run.id,
      RunGapKind.manualPause,
      start.add(Duration(seconds: pause.$1)),
    );
    await s.markers.closeGap(id, start.add(Duration(seconds: pause.$2)));
  }
  await s.runs.setState(
    run.id,
    RunState.finished,
    endedAt: start.add(Duration(seconds: seconds)),
    endedUtcOffset: Duration.zero,
  );
  return run.id;
}

/// Die tatsächlich gezeichneten Pfade der Route (ein Pfad je Abschnitt).
List<Path> routePaths() {
  final paint = tester_.widget<CustomPaint>(key('route_paint'));
  return (paint.painter! as RoutePainter)
      .shapes(tester_.getSize(key('route_paint')))
      .paths;
}

late WidgetTester tester_;

/// Die tatsächlich gezeichneten Pfade eines Diagramms.
List<Path> chartPaths(String id) {
  final size = tester_.getSize(
    find.descendant(
      of: key(id),
      matching: find.byKey(const Key('chart_paint')),
    ),
  );
  return chart(id).linePaths(size);
}

SeriesChartPainter chart(String id) =>
    tester_
            .widget<CustomPaint>(
              find.descendant(
                of: key(id),
                matching: find.byKey(const Key('chart_paint')),
              ),
            )
            .painter!
        as SeriesChartPainter;

Future<int> openDetail(
  WidgetTester tester,
  Device d,
  Future<int> Function() seed,
) async {
  tester_ = tester;
  final id = await seed();
  await openHistory(d, tester);
  await tester.tap(key('history_run_$id'));
  await tester.pumpAndSettle();
  return id;
}

void main() {
  testWidgets('Detail: Kennzahlen, Route und Diagramme sind gezeichnet', (
    tester,
  ) async {
    final d = await started(tester);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
    );
    // 10 min mit 3 m/s, Kennzahlen wie in der Zusammenfassung.
    expect(text('run_distance'), '1,83 km');
    expect(text('run_time'), '10:00');
    expect(routePaths(), hasLength(1));
    expect(chartPaths('detail_pace'), hasLength(1));
    expect(chartPaths('detail_hr'), hasLength(1));
    expect(chartPaths('detail_altitude'), hasLength(1));
    // Vergleich: Pace und Puls, zwei Linien im selben Diagramm.
    expect(chart('detail_compare').layers, hasLength(2));
    expect(chartPaths('detail_compare'), hasLength(2));
    expect(key('detail_hr_none'), findsNothing);
    // Der Puls ist als geglättet gekennzeichnet (sichtbar und in der Semantik).
    expect(text('detail_hr_note'), 'Puls geglättet (Median über 30 s)');
    expect(text('detail_compare_note'), 'Puls geglättet (Median über 30 s)');
    expect(key('detail_pace_note'), findsNothing);
    final semantics = tester.ensureSemantics();
    expect(
      tester.getSemantics(key('detail_hr')).label,
      contains('Puls geglättet (Median über 30 s).'),
    );
    expect(
      tester.getSemantics(key('detail_pace')).label,
      isNot(contains('geglättet')),
    );
    semantics.dispose();
    // Alter Lauf ohne gespeicherte Zonen/TRIMP.
    expect(
      text('sum_zones_unavailable'),
      'nicht verfügbar (für diesen Lauf nicht gespeichert)',
    );
    expect(text('sum_trimp'), contains('nicht gespeichert'));
  });

  testWidgets('Positionslücke: Route, Pace und Höhe getrennt, Puls nicht', (
    tester,
  ) async {
    final d = await started(tester);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        noPosition: (200, 260),
      ),
    );
    expect(routePaths(), hasLength(2));
    expect(chartPaths('detail_pace'), hasLength(2));
    expect(chartPaths('detail_altitude'), hasLength(2));
    expect(chartPaths('detail_hr'), hasLength(1));
    // Beide Teile der Route liegen auseinander: die Lücke (60 s mal 3 m/s)
    // wird nicht überbrückt.
    final paths = routePaths();
    final upper = paths[1].getBounds();
    final lower = paths[0].getBounds();
    // Norden ist oben: zwischen den Abschnitten klafft die Lücke und ist leer.
    expect(lower.top - upper.bottom, greaterThan(10));
    expect(key('run_gaps'), findsOneWidget);
  });

  testWidgets('Pulslücke: nur der Puls ist getrennt, Route und Pace nicht', (
    tester,
  ) async {
    final d = await started(tester);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        noHeartRate: (200, 260),
      ),
    );
    expect(chartPaths('detail_hr'), hasLength(2));
    expect(routePaths(), hasLength(1));
    expect(chartPaths('detail_pace'), hasLength(1));
    expect(chartPaths('detail_altitude'), hasLength(1));
    // Vergleich: Pace (1 Pfad) und Puls (2 Pfade).
    expect(chartPaths('detail_compare'), hasLength(3));
    // Die Lücke im Puls ist nicht überbrückt: keine Linie zwischen 200 und 260 s.
    final c = chart('detail_hr');
    final layer = c.layers.single;
    expect(layer.parts, hasLength(2));
    expect(
      layer.parts[1].first.seconds - layer.parts[0].last.seconds,
      greaterThanOrEqualTo(60),
    );
  });

  testWidgets('Löschen im Detail: Checkpoint scheitert, Lauf ist trotzdem weg', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await openDetail(
      tester,
      d,
      () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
    );
    d.storage.checkpointIncomplete = true;
    await tester.tap(key('detail_delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen').last);
    await tester.pumpAndSettle();
    // Gelöscht, nur nicht gelöscht-gesichert: Detail schließt, Liste lädt neu.
    expect(key('detail_delete'), findsNothing);
    expect(key('history_run_$id'), findsNothing);
    expect(await d.session.runs.get(id), isNull);
    expect(find.textContaining('noch nicht abgeschlossen'), findsOneWidget);
  });

  testWidgets('Route: Legende Start/Ende als Text', (tester) async {
    final d = await started(tester);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
    );
    expect(text('route_legend_start'), 'Start');
    expect(text('route_legend_end'), 'Ende');
  });

  group('Diagrammachse', () {
    Widget host(Widget child, {double scale = 1}) => MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

    ChartLayer paceLayer({required bool outliers}) => ChartLayer(
      name: 'Pace',
      parts: [
        [
          for (var i = 0; i < 200; i++)
            DetailPoint(i.toDouble(), 280 + (i % 41).toDouble()),
          if (outliers) ...[
            const DetailPoint(200, 900),
            const DetailPoint(201, 950),
          ],
        ],
      ],
      color: Colors.blue,
      format: (v) => '${v!.round()}',
      inverted: true,
      robust: true,
    );

    testWidgets(
      'Ausreißer: Beschreibung nennt echte Werte, Abschneiden steht da',
      (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          host(
            RunSeriesChart(
              layers: [paceLayer(outliers: true)],
              totalSeconds: 202,
              pauses: const [],
            ),
          ),
        );
        final layer = paceLayer(outliers: true);
        // Die Achse schneidet ab, die Beschreibung nennt den echten Größtwert.
        expect(layer.range.hi, lessThan(900));
        expect(layer.clipped, isTrue);
        expect(
          find.bySemanticsLabel(
            RegExp(r'^Pace\. Kleinster Wert 280, größter Wert 950\.'),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(r'Pace: Ausreißer am Rand abgeschnitten'),
          ),
          findsOneWidget,
        );
        expect(
          text('chart_clipped'),
          'Pace: Ausreißer am Rand abgeschnitten (die Achse zeigt den Kernbereich).',
        );
        handle.dispose();
      },
    );

    testWidgets('ohne Ausreißer: kein Hinweis', (tester) async {
      await tester.pumpWidget(
        host(
          RunSeriesChart(
            layers: [paceLayer(outliers: false)],
            totalSeconds: 202,
            pauses: const [],
          ),
        ),
      );
      expect(paceLayer(outliers: false).clipped, isFalse);
      expect(key('chart_clipped'), findsNothing);
    });

    for (final (scale, width) in [
      (1.0, null),
      (2.0, null),
      (1.0, 360.0),
      (2.0, 360.0),
    ]) {
      testWidgets('Achsentexte überlappen sich nicht (Schrift ${scale}x, '
          'Breite ${width ?? 'Standard'})', (tester) async {
        if (width != null) {
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
        }
        final hr = ChartLayer(
          name: 'Puls',
          parts: [
            [
              for (var i = 0; i < 200; i++)
                DetailPoint(i.toDouble(), 150 + i % 20),
            ],
          ],
          color: Colors.red,
          format: (v) => '${v!.round()} bpm',
          inverted: false,
          robust: true,
        );
        for (final layers in [
          [paceLayer(outliers: false)],
          [hr],
          [paceLayer(outliers: false), hr],
        ]) {
          await tester.pumpWidget(
            host(
              RunSeriesChart(
                layers: layers,
                totalSeconds: 1200,
                pauses: const [],
              ),
              scale: scale,
            ),
          );
          final painter =
              tester.widget<CustomPaint>(key('chart_paint')).painter!
                  as SeriesChartPainter;
          final size = tester.getSize(key('chart_paint'));
          if (width != null) expect(size.width, lessThanOrEqualTo(width));
          final rects = painter.axisTextRects(size);
          expect(rects.length, layers.length * 2 + 2);
          for (var i = 0; i < rects.length; i++) {
            expect(
              (Offset.zero & size)
                      .inflate(0.01)
                      .contains(rects[i].rect.bottomRight) &&
                  (Offset.zero & size).contains(rects[i].rect.topLeft),
              isTrue,
              reason: '${rects[i].text} liegt außerhalb',
            );
            for (var j = i + 1; j < rects.length; j++) {
              expect(
                rects[i].rect.overlaps(rects[j].rect),
                isFalse,
                reason: '${rects[i].text} überlappt ${rects[j].text}',
              );
            }
          }
        }
      });
    }

    testWidgets('Beschriftung folgt der Schriftgröße', (tester) async {
      Future<SeriesChartPainter> painter(double scale) async {
        await tester.pumpWidget(
          host(
            RunSeriesChart(
              layers: [paceLayer(outliers: false)],
              totalSeconds: 202,
              pauses: const [],
            ),
            scale: scale,
          ),
        );
        return tester.widget<CustomPaint>(key('chart_paint')).painter!
            as SeriesChartPainter;
      }

      final normal = await painter(1);
      final normalPlot = normal.plotRect(const Size(300, 200));
      final big = await painter(2);
      final bigPlot = big.plotRect(const Size(300, 200));
      expect(big.textScaler.scale(10), 20);
      expect(bigPlot.top, closeTo(normalPlot.top * 2, 0.01));
      expect(bigPlot.height, lessThan(normalPlot.height));
    });
  });

  testWidgets('Manuelle Pause: alle Reihen getrennt', (tester) async {
    final d = await started(tester);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        pause: (200, 260),
      ),
    );
    expect(routePaths(), hasLength(2));
    expect(chartPaths('detail_pace'), hasLength(2));
    expect(chartPaths('detail_hr'), hasLength(2));
    expect(chartPaths('detail_altitude'), hasLength(2));
    expect(chartPaths('detail_compare'), hasLength(4));
    expect(chart('detail_pace').pauses.single.start, 200);
    expect(chart('detail_pace').pauses.single.end, 260);
  });

  testWidgets('Lauf ohne Puls: kein Pulsdiagramm, kein Vergleich, nie 0', (
    tester,
  ) async {
    final d = await started(tester);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        heartRate: false,
      ),
    );
    expect(key('detail_hr'), findsNothing);
    expect(text('detail_hr_none'), 'nicht verfügbar (kein Puls)');
    expect(key('detail_compare'), findsNothing);
    expect(key('detail_compare_none'), findsOneWidget);
    expect(routePaths(), hasLength(1));
    expect(chartPaths('detail_pace'), hasLength(1));
    expect(find.textContaining(RegExp(r'(^|\s)0 bpm')), findsNothing);
  });

  testWidgets(
    'Lauf ohne Positionen: Route nicht verfügbar statt leerer Fläche',
    (tester) async {
      final d = await started(tester);
      await openDetail(tester, d, () async {
        final run = await d.session.runs.create(
          startedAt: DateTime.utc(2030, 1, 1, 8),
        );
        await d.session.runs.setState(
          run.id,
          RunState.finished,
          endedAt: DateTime.utc(2030, 1, 1, 8, 5),
          endedUtcOffset: Duration.zero,
        );
        return run.id;
      });
      expect(key('route_paint'), findsNothing);
      expect(key('detail_route_none'), findsOneWidget);
      expect(key('detail_pace_none'), findsOneWidget);
      expect(key('detail_altitude_none'), findsOneWidget);
    },
  );

  testWidgets('Löschen im Detail mit Bestätigung, zurück zur Historie', (
    tester,
  ) async {
    final d = await started(tester);
    final other = await seedDetailRun(d.session, DateTime.utc(2030, 1, 2, 8));
    final id = await openDetail(
      tester,
      d,
      () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
    );
    await tester.tap(key('detail_delete'));
    await tester.pumpAndSettle();
    expect(find.text('Lauf löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(key('detail_delete'), findsOneWidget);
    expect(await d.session.runs.get(id), isNotNull);

    await tester.tap(key('detail_delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lauf löschen').last);
    await tester.pumpAndSettle();
    expect(key('detail_delete'), findsNothing);
    expect(key('history_run_$id'), findsNothing);
    expect(key('history_run_$other'), findsOneWidget);
    expect(await d.session.runs.get(id), isNull);
  });

  testWidgets('Beschreibungen für Route und Diagramme (ACC-04 bis 06)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final d = await started(tester);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        noPosition: (200, 260),
      ),
    );
    expect(
      find.bySemanticsLabel(
        'Route, ohne Karte gezeichnet. 2 zusammenhängende Abschnitte; Lücken sind nicht verbunden. Start und Ende sind markiert.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Puls\. Kleinster Wert 140 bpm')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Pace und Puls über die Zeit')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('große Schrift (2,0): keine Überläufe im Detail', (tester) async {
    final d = await started(tester);
    tester.view.physicalSize = const Size(411, 914);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openDetail(
      tester,
      d,
      () => seedDetailRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        pause: (200, 260),
      ),
    );
    expect(key('route_paint'), findsOneWidget);
    await tester.scrollUntilVisible(
      key('detail_altitude'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.takeException(), isNull);
  });

  group('Offload über AppDependencies', () {
    Future<Device> startedWith(WidgetTester tester, Offload offload) async {
      final d = Device()..offload = offload;
      await d.start(tester, const Locale('de'));
      await d.skipSetup(tester);
      return d;
    }

    testWidgets('Historie und Detail rechnen über den eingesetzten Offload', (
      tester,
    ) async {
      final jobs = <Object>[];
      Future<R> counting<A, R>(R Function(A) job, A argument) {
        jobs.add(job);
        return inlineOffload(job, argument);
      }

      final d = await startedWith(tester, counting);
      await openDetail(
        tester,
        d,
        () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
      );
      expect(chartPaths('detail_pace'), hasLength(1));
      // Historie (veralteter Lauf) und Zusammenfassung je eine Wiedergabe.
      expect(jobs.where((j) => j == replayJob), hasLength(2));
      expect(jobs, contains(buildRunDetailJob));
    });

    testWidgets('Statistik rechnet veraltete Läufe über den Offload', (
      tester,
    ) async {
      final jobs = <Object>[];
      Future<R> counting<A, R>(R Function(A) job, A argument) {
        jobs.add(job);
        return inlineOffload(job, argument);
      }

      final d = await startedWith(tester, counting);
      await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await tester.tap(key('home_statistics'));
      await tester.pumpAndSettle();
      expect(jobs, [replayJob]);
    });

    testWidgets('Offload wirft: Fallback-Hinweis sichtbar, kein Hängen', (
      tester,
    ) async {
      // Nur der Aufbau der Zeichendaten scheitert (Isolate-Fehler); die
      // Historie rechnet weiter.
      Future<R> failing<A, R>(R Function(A) job, A argument) {
        if (job == buildRunDetailJob) {
          return Future<R>.error(StateError('Isolate abgestürzt'));
        }
        return inlineOffload(job, argument);
      }

      final d = await startedWith(tester, failing);
      await openDetail(
        tester,
        d,
        () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
      );
      // pumpAndSettle in openDetail ist zurückgekehrt: nichts hängt.
      expect(key('sum_loading'), findsNothing);
      expect(key('sum_fallback'), findsOneWidget);
      expect(
        find.text('Dieser Lauf konnte nicht gelesen werden.'),
        findsOneWidget,
      );
      expect(key('route_paint'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
