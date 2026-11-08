import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/features/summary/run_summary_body.dart';
import 'package:running_app/features/summary/run_summary_page.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/offload_scope.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show key, started, text;
import 'run_detail_test.dart' show seedDetailRun;

const _km = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'de',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

/// Zonen und Belastung wie nach dem Laufende gespeichert.
Future<void> seedLoad(StorageSession s, int runId) async {
  ComputedValue v(String k, double value, String unit) => ComputedValue(
    key: k,
    value: value,
    unit: unit,
    computedAt: DateTime.utc(2030, 1, 1, 9),
    dataFrom: DateTime.utc(2030, 1, 1, 8),
    dataTo: DateTime.utc(2030, 1, 1, 8, 10),
    measurementCount: 600,
    sources: const ['gps'],
    method: 'm',
    methodVersion: 1,
    parameterVersion: 1,
    quality: ValueQuality.good,
  );
  await s.values.createOriginals(ValueOwner.run(runId), [
    for (var z = 1; z <= zoneValueCount; z++)
      v(zoneTimeValueKey(z), z == 2 ? 480 : (z == 3 ? 120 : 0), secondsUnit),
    v(zoneBelowValueKey, 0, secondsUnit),
    v(trimpRunValueKey, 58, pointsUnit),
  ]);
}

Future<void> pumpPage(
  WidgetTester tester,
  Device d,
  int runId, {
  double scale = 1,
  bool dark = false,
  Size size = const Size(360, 640),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
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
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: OffloadScope(
          offload: inlineOffload,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RunSummaryBody(
                session: d.session,
                clock: d.clock,
                runId: runId,
                fallback: () => const [],
                contentBuilder: (context, summary, detail, _) => RunSummaryPage(
                  summary: summary,
                  detail: detail,
                  formatter: _km,
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

void main() {
  const keys = [
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
    'sum_class',
    'sum_vo2max',
    'run_laps',
    'sum_explain_trimp',
    'sum_explain_zones',
    'sum_explain_class',
    'sum_explain_vo2max',
    'sum_explain_sources',
  ];

  testWidgets('alle Inhalte der Zusammenfassung (FR-0037), mit Puls und Höhe', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
    await seedLoad(d.session, id);
    await pumpPage(tester, d, id);
    for (final k in keys) {
      expect(key(k), findsOneWidget, reason: k);
    }
    expect(text('run_distance'), '1,83 km');
    expect(text('run_moving_time'), '10:00');
    expect(text('run_time'), '10:00');
    expect(text('sum_best_pace'), contains('min/km'));
    expect(text('run_ascent'), startsWith('+'));
    expect(text('run_descent'), startsWith('−'));
    expect(text('sum_avg_hr'), endsWith(' bpm'));
    expect(text('sum_trimp'), '58 Punkte');
    expect(find.text('geschätzt'), findsOneWidget);
    // Zonen mit Balken und Zeit je Zone, Höhenprofil und Route gezeichnet.
    expect(key('sum_zones'), findsOneWidget);
    expect(find.byType(ZoneBar), findsOneWidget);
    expect(find.text('Zone 2: 8:00'), findsOneWidget);
    expect(key('sum_altitude'), findsOneWidget);
    expect(key('route_paint'), findsOneWidget);
    expect(find.text('Höhenprofil'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ohne Puls, Höhe und Positionen: nicht verfügbar, nie 0', (
    tester,
  ) async {
    final d = await started(tester);
    final id = await seedDetailRun(
      d.session,
      DateTime.utc(2030, 1, 1, 8),
      heartRate: false,
      noPosition: (0, 601),
    );
    await pumpPage(tester, d, id);
    expect(text('sum_avg_hr'), 'nicht verfügbar (kein Puls)');
    expect(text('sum_max_hr'), 'nicht verfügbar (kein Puls)');
    expect(text('run_ascent'), 'nicht verfügbar');
    expect(text('run_descent'), 'nicht verfügbar');
    expect(text('run_distance'), 'nicht verfügbar');
    expect(text('run_avg_pace'), 'nicht verfügbar');
    expect(text('sum_best_pace'), contains('nicht verfügbar'));
    expect(text('sum_trimp'), contains('nicht verfügbar'));
    expect(key('sum_zones_unavailable'), findsOneWidget);
    expect(key('sum_altitude_none'), findsOneWidget);
    expect(key('detail_route_none'), findsOneWidget);
    expect(find.textContaining(RegExp(r'(^|\s)0 (bpm|m)\b')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('Schriftfaktor 1,3 auf 360x640 ohne Überlauf, '
        '${dark ? 'dunkel' : 'hell'}; Einheiten brechen nicht am "/"', (
      tester,
    ) async {
      final d = await started(tester);
      final id = await seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await seedLoad(d.session, id);
      await pumpPage(tester, d, id, scale: 1.3, dark: dark);
      expect(tester.takeException(), isNull);
      // Die Einheit „min/km“ ist mit Wortverbindern gesetzt (kein Umbruch
      // am „/“) und steht in einem Stück in der Zeile.
      for (final k in ['run_avg_pace', 'sum_best_pace']) {
        final span = (key(k).evaluate().single.widget as Text).textSpan!;
        expect(span.toPlainText(), contains('min⁠/⁠km'), reason: k);
        final box = tester.renderObject<RenderParagraph>(key(k));
        final lines = box
            .getBoxesForSelection(
              TextSelection(
                baseOffset: span.toPlainText().indexOf('min'),
                extentOffset: span.toPlainText().length,
              ),
            )
            .map((b) => b.top.round())
            .toSet();
        expect(lines, hasLength(1), reason: '$k bricht um');
      }
      await tester.scrollUntilVisible(
        key('sum_explain_sources'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
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
    });
  }
}
