import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/summary/run_charts.dart';

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
            if (!inside(pause, i))
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
        'Route, ohne Karte gezeichnet. 2 zusammenhängende Abschnitte; Lücken sind nicht verbunden.',
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
}
