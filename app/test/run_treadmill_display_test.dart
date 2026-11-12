// WP25 B2: Bandläufe nach dem Lauf (FR-0196): Zusammenfassung, Detail und
// Verlauf ohne Karte, Route und Höhe; Hinweis Laufband, Splits aus dem Band.

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/run_detail_page.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/features/summary/run_summary_body.dart';
import 'package:running_app/features/summary/run_summary_page.dart';
import 'package:running_app/offload_scope.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show openHistory, started, text;
import 'run_detail_test.dart' show seedDetailRun;

const _kmEn = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'en',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

const _km = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'de',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

/// Beendeter Bandlauf: 10 min mit 3 m/s (1,8 km), Steigung 2 %, Puls 150.
Future<int> seedBeltRun(StorageSession s, DateTime start) async {
  final run = await s.runs.create(startedAt: start, mode: RunMode.treadmill);
  await s.rawData.append(
    run.id,
    RawBatch(
      heartRates: [
        for (var i = 0; i <= 600; i++)
          RawHeartRate(
            time: start.add(Duration(seconds: i)),
            source: 'strap',
            bpm: 150,
            contact: SensorContact.good,
          ),
      ],
      beltSettings: const [
        BeltSetting(
          offset: Duration.zero,
          speedMetersPerSecond: 3,
          inclinePercent: 2,
        ),
      ],
    ),
  );
  await s.runs.setState(
    run.id,
    RunState.finished,
    endedAt: start.add(const Duration(minutes: 10)),
  );
  await s.values.createOriginals(ValueOwner.run(run.id), [
    ComputedValue(
      key: vo2maxRunValueKey,
      value: 45,
      unit: 'ml/kg/min',
      computedAt: DateTime.utc(2030, 1, 1, 9),
      dataFrom: start,
      dataTo: start.add(const Duration(minutes: 10)),
      measurementCount: 600,
      sources: const ['strap'],
      method: 'm',
      methodVersion: 1,
      parameterVersion: 1,
      quality: ValueQuality.good,
    ),
  ]);
  return run.id;
}

Future<void> _pump(
  WidgetTester tester,
  Device d,
  int runId, {
  required bool detail,
  bool dark = false,
  String lang = 'de',
  UnitFormatter formatter = _km,
}) async {
  const size = Size(360, 640);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    localizedApp(
      locale: Locale(lang),
      brightness: dark ? Brightness.dark : Brightness.light,
      home: MediaQuery(
        data: const MediaQueryData(size: size),
        child: OffloadScope(
          offload: inlineOffload,
          child: Scaffold(
            body: SingleChildScrollView(
              child: RunSummaryBody(
                session: d.session,
                clock: d.clock,
                runId: runId,
                fallback: () => const [],
                splitUnitMeters: detail ? kilometerMeters : null,
                contentBuilder: (context, summary, data, splits) => detail
                    ? RunDetailPage(
                        summary: summary,
                        detail: data,
                        splits: splits,
                        formatter: formatter,
                        session: d.session,
                        runId: runId,
                      )
                    : RunSummaryPage(
                        summary: summary,
                        detail: data,
                        formatter: formatter,
                        session: d.session,
                        runId: runId,
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noMapNoElevation() {
  for (final k in [
    'route_paint',
    'sum_altitude',
    'sum_altitude_none',
    'detail_altitude',
    'detail_altitude_none',
    'run_ascent',
    'run_descent',
    'sum_best_pace',
    'run_gaps',
  ]) {
    expect(key(k), findsNothing, reason: k);
  }
  expect(find.text('Höhenprofil'), findsNothing);
}

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dunkel' : 'hell';
    testWidgets('Zusammenfassung Band ($mode): Hinweis, keine Karte/Höhe', (
      tester,
    ) async {
      final d = await started(tester);
      final id = await seedBeltRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await _pump(tester, d, id, detail: false, dark: dark);
      _noMapNoElevation();
      expect(
        text('sum_treadmill_note'),
        'Laufband · Ø 10,8 km/h · Steigung Ø 2,0 %',
      );
      expect(text('run_distance'), '1,80 km');
      expect(text('run_moving_time'), '10:00');
      expect(text('run_avg_pace'), '5:33');
      expect(text('sum_vo2max_provisional'), 'vorläufig (Laufband)');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Detail Band ($mode): keine Karte/Höhe, Splits aus dem Band', (
      tester,
    ) async {
      final d = await started(tester);
      final id = await seedBeltRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await _pump(tester, d, id, detail: true, dark: dark);
      _noMapNoElevation();
      expect(key('sum_treadmill_note'), findsOneWidget);
      expect(text('run_distance'), '1,80 km');
      expect(text('detail_km_time_1'), '5:33');
      expect(text('detail_km_pace_1'), '5:33');
      expect(key('detail_km_index_2'), findsOneWidget);
      expect(key('detail_km_none'), findsNothing);
      // Pace-Diagramm aus der Bandgeschwindigkeit (Stufenreihe), nicht leer.
      expect(key('detail_compare'), findsOneWidget);
      expect(key('detail_pace_none'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('GPS-Lauf unverändert: Route, Höhe, Anstieg, kein Hinweis', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
    await _pump(tester, d, id, detail: true);
    expect(key('route_paint'), findsOneWidget);
    expect(key('detail_altitude'), findsOneWidget);
    expect(key('run_ascent'), findsOneWidget);
    expect(key('sum_treadmill'), findsNothing);
    expect(key('sum_vo2max_provisional'), findsNothing);
  });

  testWidgets('Verlauf: Bandlauf mit Hinweis, ohne Miniatur und Leerraum', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await seedBeltRun(d.session, DateTime.utc(2030, 1, 1, 8));
    final gps = await seedDetailRun(d.session, DateTime.utc(2030, 1, 2, 8));
    await openHistory(d, tester);
    expect(text('history_treadmill_$id'), 'Laufband');
    expect(key('history_miniature_$id'), findsNothing);
    expect(text('history_distance_$id'), '1,80 km');
    expect(key('history_treadmill_$gps'), findsNothing);
    expect(key('history_miniature_$gps'), findsOneWidget);
  });

  testWidgets('Englisch: Hinweis übersetzt', (tester) async {
    final d = await started(tester, locale: 'en');
    final id = await seedBeltRun(d.session, DateTime.utc(2030, 1, 1, 8));
    await _pump(tester, d, id, detail: false, lang: 'en', formatter: _kmEn);
    expect(find.textContaining('Treadmill · avg 10.8 km/h'), findsOneWidget);
  });
}
