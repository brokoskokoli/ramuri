// WP16 C2: Detailansicht nach Detail.dc.html (FR-0041, FR-0042, FR-0211, FR-0204): Kilometertabelle, Marken,
// Pace und Puls, Höhenprofil, vollständige Inhalte, Schriftfaktor 1,3 auf 360x640.
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/history/run_detail_page.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/features/summary/kilometer_table.dart';
import 'package:running_app/features/summary/run_charts.dart';
import 'package:running_app/features/summary/run_summary_body.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show key, openHistory, started, text;
import 'run_detail_test.dart' show seedDetailRun;
import 'run_summary_page_test.dart' show seedLoad;

const _km = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'de',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);
const _mi = UnitFormatter(
  unit: DistanceUnit.miles,
  languageCode: 'de',
  distanceLabel: 'mi',
  paceLabel: 'min/mi',
  elevationLabel: 'ft',
);

Widget _app(Widget body, {bool dark = false, double scale = 1, Size? size}) =>
    MaterialApp(
      theme: dark ? RamuriTheme.dark : RamuriTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(
          size: size ?? const Size(360, 640),
          textScaler: TextScaler.linear(scale),
        ),
        child: OffloadScope(
          offload: inlineOffload,
          child: Scaffold(body: SingleChildScrollView(child: body)),
        ),
      ),
    );

Future<void> pumpDetail(
  WidgetTester tester,
  Device d,
  int runId, {
  UnitFormatter formatter = _km,
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      Padding(
        padding: const EdgeInsets.all(16),
        child: RunSummaryBody(
          session: d.session,
          clock: d.clock,
          runId: runId,
          fallback: () => const [],
          splitUnitMeters: formatter.unit == DistanceUnit.miles
              ? mileMeters
              : kilometerMeters,
          contentBuilder: (context, summary, detail, splits) => RunDetailPage(
            summary: summary,
            detail: detail,
            splits: splits,
            formatter: formatter,
            session: d.session,
            runId: runId,
          ),
        ),
      ),
      dark: dark,
      scale: scale,
    ),
  );
  await tester.pumpAndSettle();
}

/// Alle Abschnitte der Tabelle auf der Seite: Zeit, Pace, Puls und Beschriftungen je Nummer.
List<({int index, String time, String pace, String hr})> tableRows() {
  final rows = <({int index, String time, String pace, String hr})>[];
  for (var i = 1; key('detail_km_index_$i').evaluate().isNotEmpty; i++) {
    rows.add((
      index: i,
      time: text('detail_km_time_$i'),
      pace: text('detail_km_pace_$i'),
      hr: text('detail_km_hr_$i'),
    ));
  }
  return rows;
}

Duration clock(String s) {
  final p = s.split(':').map(int.parse).toList();
  return p.length == 3
      ? Duration(hours: p[0], minutes: p[1], seconds: p[2])
      : Duration(minutes: p[0], seconds: p[1]);
}

KilometerSplit _split(
  int i, {
  required int seconds,
  double? pace,
  double? hr,
  int gapSeconds = 0,
  bool partial = false,
  double meters = 1000,
}) => KilometerSplit(
  index: i,
  lengthMeters: meters,
  isPartial: partial,
  time: Duration(seconds: seconds),
  positionGapTime: Duration(seconds: gapSeconds),
  paceSecondsPerKm: pace,
  heartRateAverageBpm: hr,
);

KilometerSplits _splits(List<KilometerSplit> s, {double unit = 1000}) =>
    KilometerSplits(
      unitMeters: unit,
      splits: s,
      marks: const [],
      ascentMeters: null,
      descentMeters: null,
    );

void main() {
  group('Kilometertabelle (nur Anzeige)', () {
    final splits = _splits([
      _split(1, seconds: 330, pace: 330, hr: 140.4),
      // Lückenkilometer: 30 s lagen in einer Positionslücke; die Zeit zählt sie, die Pace nicht.
      _split(2, seconds: 390, pace: 360, hr: 150, gapSeconds: 30),
      // Ohne Puls, ganze Zeit in der Lücke: keine Pace.
      _split(3, seconds: 60, gapSeconds: 60),
      // Angebrochen: 420 m.
      _split(4, seconds: 120, pace: 285.7, partial: true, meters: 420),
    ]);

    testWidgets(
      'Zeit, Pace, Puls; „–“ statt 0; Lücke und angebrochen gekennzeichnet',
      (tester) async {
        await tester.pumpWidget(
          _app(KilometerTable(splits: splits, formatter: _km)),
        );
        final rows = tableRows();
        expect(rows.map((r) => r.time), ['5:30', '6:30', '1:00', '2:00']);
        expect(rows.map((r) => r.pace), ['5:30', '6:00', '–', '4:46']);
        expect(rows.map((r) => r.hr), ['140', '150', '–', '–']);
        // Die Zeit enthält die Lückenzeit, die Pace nicht: 6:30 Zeit, aber 6:00 Pace bei 1 km.
        expect(key('detail_km_gap_2'), findsOneWidget);
        expect(text('detail_km_gap_2'), contains('0:30'));
        expect(key('detail_km_gap_1'), findsNothing);
        expect(key('detail_km_gap_3'), findsOneWidget);
        expect(text('detail_km_partial_4'), 'angebrochen: 0,42 km');
        expect(key('detail_km_partial_3'), findsNothing);
        expect(find.text('0'), findsNothing);
        // Kopf: Einheit der Einstellungen.
        expect(find.text('km'), findsOneWidget);
      },
    );

    testWidgets('Meilen: Kopf „mi“, Rest in Meilen', (tester) async {
      final miles = _splits([
        _split(1, seconds: 540, pace: 335.5, hr: 141),
        _split(2, seconds: 100, pace: 300, partial: true, meters: 400),
      ], unit: mileMeters);
      await tester.pumpWidget(
        _app(KilometerTable(splits: miles, formatter: _mi)),
      );
      expect(find.text('mi'), findsOneWidget);
      expect(find.text('km'), findsNothing);
      // 335,5 s/km sind 9:00 min/mi.
      expect(text('detail_km_pace_1'), '9:00');
      expect(text('detail_km_partial_2'), 'angebrochen: 0,25 mi');
    });

    testWidgets('ohne Abschnitte: Hinweis statt leerer Tabelle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(KilometerTable(splits: _splits([]), formatter: _km)),
      );
      expect(key('detail_km_none'), findsOneWidget);
      expect(key('detail_km_table'), findsNothing);
    });
  });

  testWidgets(
    'Seite: Tabellenzeiten summieren sich zur Bewegungszeit, Marken, Anstieg/Gefälle',
    (tester) async {
      final d = await started(tester);
      final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await pumpDetail(tester, d, id);
      final rows = tableRows();
      // 1,83 km: ein voller Kilometer und der angebrochene Rest.
      expect(rows, hasLength(2));
      expect(key('detail_km_partial_2'), findsOneWidget);
      final sum = rows.fold(Duration.zero, (a, r) => a + clock(r.time));
      expect(sum, clock(text('run_moving_time')));
      expect(text('run_moving_time'), '10:00');
      // Kilometermarke 1 auf der Route (Zeichnung, ohne Einwilligung).
      final painter =
          tester.widget<CustomPaint>(key('route_paint')).painter!
              as RoutePainter;
      final shapes = painter.shapes(tester.getSize(key('route_paint')));
      expect([for (final m in shapes.marks) m.index], [1]);
      expect(text('route_legend_marks'), 'Nummern: volle km');
      // Anstieg und Gefälle: Kopf des Höhenprofils und Kacheln zeigen dieselben Werte.
      expect(text('detail_ascent'), text('run_ascent'));
      expect(text('detail_descent'), text('run_descent'));
      final summary = await RunSummaryService(
        session: d.session,
        clock: d.clock,
        offload: inlineOffload,
      ).load(id);
      final splits = computeKilometerSplits(summary!.preprocessing);
      expect(splits.ascentMeters, summary.ascentMeters);
      expect(splits.descentMeters, summary.descentMeters);
      expect(summary.ascentMeters, isNotNull);
      expect(text('detail_ascent'), '+${_km.elevation(summary.ascentMeters)}');
      expect(
        text('detail_descent'),
        '−${_km.elevation(summary.descentMeters)}',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Seite mit GPS-Lücke: Lückenkilometer gekennzeichnet, Summe stimmt',
    (tester) async {
      final d = await started(tester);
      final id = await seedDetailRun(
        d.session,
        DateTime.utc(2030, 1, 1, 8),
        noPosition: (200, 260),
      );
      await pumpDetail(tester, d, id);
      final rows = tableRows();
      expect(key('detail_km_gap_1'), findsOneWidget);
      final sum = rows.fold(Duration.zero, (a, r) => a + clock(r.time));
      expect(sum, clock(text('run_moving_time')));
      // Die Karte zeigt zwei Teile; Pace und Puls: Pace getrennt, Puls durchgehend.
      expect(chartLayerParts('detail_compare', 0), 2);
      expect(chartLayerParts('detail_compare', 1), 1);
      expect(key('run_gaps'), findsOneWidget);
    },
  );

  testWidgets('Seite ohne Puls: Tabelle mit „–“, nie 0 bpm', (tester) async {
    final d = await started(tester);
    final id = await seedDetailRun(
      d.session,
      DateTime.utc(2030, 1, 1, 8),
      heartRate: false,
    );
    await pumpDetail(tester, d, id);
    expect(tableRows().map((r) => r.hr), everyElement('–'));
    expect(key('detail_hr_none'), findsOneWidget);
    expect(key('detail_pace'), findsOneWidget);
    expect(find.textContaining(RegExp(r'(^|\s)0 bpm')), findsNothing);
  });

  testWidgets('Seite in Meilen: Tabelle, Legende, Anstieg in ft', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
    await pumpDetail(tester, d, id, formatter: _mi);
    // 1,14 mi: eine volle Meile und der Rest.
    final rows = tableRows();
    expect(rows, hasLength(2));
    expect(text('detail_km_partial_2'), startsWith('angebrochen: 0,'));
    expect(text('detail_km_partial_2'), endsWith(' mi'));
    expect(text('route_legend_marks'), 'Nummern: volle mi');
    expect(text('detail_ascent'), endsWith(' ft'));
    expect(find.text('Meilen'), findsOneWidget);
    final sum = rows.fold(Duration.zero, (a, r) => a + clock(r.time));
    expect(sum, clock(text('run_moving_time')));
  });

  testWidgets('Seite ohne Positionen: keine Tabelle, Hinweis, keine Marken', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await seedDetailRun(
      d.session,
      DateTime.utc(2030, 1, 1, 8),
      noPosition: (0, 601),
    );
    await pumpDetail(tester, d, id);
    expect(key('detail_km_none'), findsOneWidget);
    expect(key('detail_route_none'), findsOneWidget);
    expect(text('run_distance'), 'nicht verfügbar');
    expect(text('detail_started'), startsWith('Gelaufen am'));
  });

  testWidgets('alle Inhalte der Detailansicht bleiben', (tester) async {
    final d = await started(tester);
    final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
    await seedLoad(d.session, id);
    await pumpDetail(tester, d, id);
    for (final k in [
      'detail_started',
      'route_paint',
      'run_distance',
      'run_moving_time',
      'run_time',
      'run_avg_pace',
      'sum_best_pace',
      'run_ascent',
      'run_descent',
      'sum_avg_hr',
      'sum_max_hr',
      'sum_trimp',
      'sum_zones',
      'sum_class',
      'sum_vo2max',
      'run_laps',
      'detail_compare',
      'detail_compare_note',
      'detail_altitude',
      'detail_km_table',
      'sum_explain_trimp',
      'sum_explain_zones',
      'sum_explain_class',
      'sum_explain_vo2max',
      'sum_explain_sources',
    ]) {
      expect(key(k), findsOneWidget, reason: k);
    }
    expect(find.byType(ZoneBar), findsOneWidget);
    expect(find.text('Zone 2: 8:00'), findsOneWidget);
    expect(text('sum_trimp'), '58 Punkte');
    expect(find.text('Pace & Puls'), findsOneWidget);
    expect(find.text('Höhenprofil'), findsOneWidget);
    expect(find.text('Kilometer'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'Schriftfaktor 1,3 auf 360x640 ohne Überlauf, ${dark ? 'dunkel' : 'hell'}; '
      'Tabelle bleibt in der Breite, Ziele mindestens 48 dp',
      (tester) async {
        final d = await started(tester);
        final id = await seedDetailRun(
          d.session,
          DateTime.utc(2030, 1, 1, 8),
          seconds: 1000,
          noPosition: (200, 260),
        );
        await seedLoad(d.session, id);
        await pumpDetail(tester, d, id, scale: 1.3, dark: dark);
        expect(tester.takeException(), isNull);
        expect(tableRows(), hasLength(3));
        // Tabelle innerhalb Seitenrand (360 - 2 * 16) und Karte (2 * 16).
        final table = tester.getRect(key('detail_km_table'));
        expect(table.left, greaterThanOrEqualTo(32));
        expect(table.right, lessThanOrEqualTo(360 - 32));
        for (final k in [
          'detail_km_time_1',
          'detail_km_pace_1',
          'detail_km_hr_1',
        ]) {
          final r = tester.getRect(key(k));
          expect(r.right, lessThanOrEqualTo(table.right), reason: k);
        }
        // Die Beschriftung des Lückenkilometers bricht um, läuft aber nicht über.
        final gap = tester.getRect(key('detail_km_gap_1'));
        expect(gap.right, lessThanOrEqualTo(table.right));
        await tester.scrollUntilVisible(
          key('sum_explain_sources'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        for (final k in [
          'sum_explain_trimp',
          'sum_explain_zones',
          'sum_explain_sources',
        ]) {
          expect(
            tester.getSize(key(k)).height,
            greaterThanOrEqualTo(RamuriTheme.minTarget),
            reason: k,
          );
        }
      },
    );
  }

  testWidgets(
    'Kopfzeile: Export und Löschen bleiben, 48 dp, bei Schriftfaktor 1,3',
    (tester) async {
      final d = await started(tester);
      final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await openHistory(d, tester);
      // Bei großer Schrift auf dem kleinen Display liegt der Eintrag unter dem Kopf der Seite.
      await tester.ensureVisible(key('history_run_$id'));
      await tester.pumpAndSettle();
      await tester.tap(key('history_run_$id'));
      await tester.pumpAndSettle();
      for (final k in ['detail_export', 'detail_delete']) {
        expect(key(k), findsOneWidget, reason: k);
        expect(
          tester.getSize(key(k)).height,
          greaterThanOrEqualTo(RamuriTheme.minTarget),
          reason: k,
        );
      }
      expect(key('detail_km_table'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

/// Zahl der gezeichneten Teile einer Reihe des Pace-und-Puls-Diagramms (0 Pace, 1 Puls).
int chartLayerParts(String id, int layer) {
  final paint = find.descendant(
    of: key(id),
    matching: find.byKey(const Key('chart_paint')),
  );
  final p =
      (paint.evaluate().single.widget as CustomPaint).painter!
          as SeriesChartPainter;
  return p.layers[layer].parts.where((x) => x.length >= 2).length;
}
