import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/readiness/readiness_detail_screen.dart';
import 'package:running_app/features/readiness/readiness_history_screen.dart';
import 'package:running_app/features/readiness/readiness_service.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

// WP34 Teil D2: Detailseite „Erholung“ in den drei Fällen (Zahl,
// Eingeschränkt, Unzureichend) und Verlauf der Reihen. Snapshots aus dem
// Modell mit erfundenen Werten; heute ist der 14.11.2026.

const _p = HealthProcessing();
final _days = localDayRanges(DateTime(2026, 10, 17), 29);
final _today = DateTime.utc(2026, 11, 14);
final _now = DateTime.utc(2026, 11, 14, 12);

DateTime _at(int i, int h) => DateTime(2026, 10, 17 + i, h).toUtc();

List<double?> _wave(double base, {int to = 29}) => [
  for (var i = 0; i < 29; i++) i < to ? base + (i % 5) * 2 : null,
];

List<HealthSample> _hrv(String origin, List<double?> v) => [
  for (var i = 0; i < v.length; i++)
    if (v[i] != null)
      HealthSample(time: _at(i, 3), value: v[i]!, origin: origin),
];

List<HealthSample> _rhr(String origin, List<double?> v) => [
  for (var i = 0; i < v.length; i++)
    if (v[i] != null)
      HealthSample(time: _at(i, 7), value: v[i]!, origin: origin),
];

SleepSession _sleep(int i) =>
    SleepSession(origin: 'app.a', start: _at(i - 1, 22), end: _at(i, 6));

MorningMeasurement _morning(
  int i, {
  RestingPosture posture = RestingPosture.lying,
  double hr = 58,
  double rmssd = 42,
}) {
  final t = DateTime(2026, 10, 17 + i, 7);
  return MorningMeasurement(
    measuredAt: t.toUtc(),
    utcOffset: t.timeZoneOffset,
    posture: posture,
    deviceManufacturer: 'Hersteller',
    deviceModel: 'Modell',
    method: 'ppg',
    methodVersion: 1,
    quality: PpgQuality.good,
    restingHrBpm: hr + (i % 4),
    rmssdMs: rmssd + (i % 6),
    timingNoiseMs: 10,
    cameraIntervalsMs: const [],
    beforeValidation: false,
    outsideWindow: false,
  );
}

DeviationResult _hcHrv(List<HealthSample> s) => healthConnectHrvDeviation(
  processing: _p,
  samples: s,
  sessions: [for (var i = 0; i < 29; i++) _sleep(i)],
  days: _days,
);

DeviationResult _hcRhr(List<HealthSample> s) =>
    healthConnectRestingHrDeviation(processing: _p, samples: s, days: _days);

ReadinessSnapshot _snap(
  ReadinessInputs inputs, {
  bool dev = false,
  List<DeviationResult> series = const [],
}) => ReadinessSnapshot(
  result: computeReadiness(inputs),
  developerMode: dev,
  extended: true,
  series: series,
  release: inputs.release,
  today: _today,
);

ReadinessSnapshot _number({bool full = true}) {
  // Heute deutlich günstiger als die Referenz: hohe Zahl (Kappung greift ohne
  // Belastung).
  final hrv = _hcHrv(_hrv('app.a', [..._wave(40).take(28), 95]));
  final rhr = _hcRhr(_rhr('app.a', [..._wave(55).take(28), 40]));
  return _snap(
    ReadinessInputs(
      today: _today,
      now: _now,
      hrvHealthConnect: hrv,
      restingHrHealthConnect: rhr,
      sleepSessions: [for (var i = 0; i < 29; i++) _sleep(i)],
      tsbPercent: full ? -5 : null,
      wellbeing: full ? ReadinessWellbeing(level: 4, day: _today) : null,
    ),
    series: [hrv, rhr],
  );
}

/// HRV fehlt heute, Ruhepuls und Schlaf liegen vor.
ReadinessSnapshot _limited() => _snap(
  ReadinessInputs(
    today: _today,
    now: _now,
    hrvHealthConnect: _hcHrv(_hrv('app.a', _wave(40, to: 28))),
    restingHrHealthConnect: _hcRhr(_rhr('app.a', _wave(55))),
    sleepSessions: [for (var i = 0; i < 29; i++) _sleep(i)],
  ),
);

ReadinessSnapshot _insufficient() =>
    _snap(ReadinessInputs(today: _today, now: _now));

const _passed = {
  ValidationQuantity.restingHr: ValidationState.passed,
  ValidationQuantity.lnRmssdSupine: ValidationState.passed,
  ValidationQuantity.lnRmssdSitting: ValidationState.passed,
};

/// Kamera: Stand bestanden ohne Opt-in, HRV gesperrt (markiert), kein Uhr-HRV.
ReadinessSnapshot _marked() {
  final cams = cameraDeviations([
    for (var i = 0; i < 29; i++) _morning(i),
  ], today: _today);
  return _snap(
    ReadinessInputs(
      today: _today,
      now: _now,
      cameraDeviations: cams,
      release: const CameraRelease(
        developerMode: false,
        rmssdOptIn: false,
        state: _passed,
      ),
      sleepBand: SleepBand.from7to8,
    ),
    series: cams,
  );
}

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  String locale = 'de',
  bool dark = false,
  double width = 411,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(
        size: Size(width, 3000),
        textScaler: TextScaler.linear(scale),
      ),
      child: MaterialApp(
        theme: dark ? RamuriTheme.dark : RamuriTheme.light,
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(Key(k));
String _text(String k) => (_key(k).evaluate().single.widget as Text).data!;

void main() {
  for (final (name, dark, locale, width, scale) in [
    ('hell, de', false, 'de', 411.0, 1.0),
    ('dunkel, en, 320 dp, Schrift 2.0', true, 'en', 320.0, 2.0),
  ]) {
    final de = locale == 'de';
    group('Detail ($name)', () {
      Future<void> open(
        WidgetTester t,
        ReadinessSnapshot s, {
        bool w = false,
      }) => _pump(
        t,
        ReadinessDetailScreen(snapshot: s, warning: w),
        locale: locale,
        dark: dark,
        width: width,
        scale: scale,
      );

      testWidgets('Zahl: Ring, Zustand, Skala, Faktoren, nichts fehlt', (
        tester,
      ) async {
        final s = _number();
        await open(tester, s);
        expect(_key('readiness_detail_case_number'), findsOneWidget);
        expect(_key('readiness_detail_case_limited'), findsNothing);
        expect(_text('readiness_detail_value'), '${s.result.value}');
        final band = s.result.band!;
        expect(_key('readiness_detail_band_${band.name}_current'), findsOne);
        expect(_key('readiness_detail_scale'), findsOneWidget);
        expect(_key('readiness_detail_level_word'), findsOneWidget);
        expect(_key('readiness_detail_drivers'), findsOneWidget);
        // Befund 8: Ursache (7-Tage-Mittel) getrennt von Tatsache (Referenzmedian).
        expect(
          _text('readiness_detail_drivers_basis'),
          contains(
            de ? 'Mittel der letzten 7 Tage' : 'mean of the last 7 days',
          ),
        );
        // Alle fünf Faktoren mit Quelle, Gewicht, Teilwert.
        for (final id in ReadinessFactorId.values) {
          expect(_key('readiness_detail_factor_${id.name}'), findsOneWidget);
        }
        expect(
          find.text(
            '${de ? 'Gewicht' : 'Weight'} ${(readinessWeightHrv * 100).round()} %',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(de ? 'Teilwert ' : 'Part score '),
          findsWidgets,
        );
        expect(find.text('Health Connect'), findsWidgets);
        expect(
          find.text(
            de ? 'Aus deinen Läufen in ramuri' : 'From your runs in ramuri',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            de
                ? 'Keine. Alle fünf Faktoren liegen vor.'
                : 'None. All five factors are present.',
          ),
          findsOneWidget,
        );
        expect(_key('readiness_detail_model'), findsOneWidget);
        expect(_text('readiness_detail_model'), contains('readiness v1'));
        expect(
          find.text(de ? 'Entwicklermodus aktiv' : 'Developer mode active'),
          findsNothing,
        );
        expect(_key('readiness_detail_warning'), findsNothing);
      });

      testWidgets(
        'Zahl ohne Belastung und Befinden: fehlende Faktoren, Kappung',
        (tester) async {
          final s = _number(full: false);
          expect(s.result.state, ReadinessState.number);
          await open(tester, s);
          expect(_key('readiness_detail_missing_load'), findsOneWidget);
          expect(_key('readiness_detail_missing_wellbeing'), findsOneWidget);
          expect(_key('readiness_detail_missing_hrv'), findsNothing);
          expect(
            find.text(
              de
                  ? 'Ohne Trainingsbelastung steigt die Zahl nicht über 74.'
                  : 'Without training load the number does not rise above 74.',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'Eingeschränkt: keine Zahl, Grund, fehlende Faktoren, Tatsache',
        (tester) async {
          final s = _limited();
          expect(s.result.state, ReadinessState.limited);
          await open(tester, s);
          expect(_key('readiness_detail_case_limited'), findsOneWidget);
          expect(_key('readiness_detail_case_number'), findsNothing);
          expect(_key('readiness_detail_value'), findsNothing);
          expect(_key('readiness_detail_scale'), findsNothing);
          expect(_key('readiness_detail_factors'), findsNothing);
          expect(_key('readiness_detail_missing_hrv'), findsOneWidget);
          expect(_key('readiness_detail_missing_sleep'), findsNothing);
          expect(
            _text('readiness_detail_title'),
            de ? 'Eingeschränkte Einschätzung' : 'Limited estimate',
          );
          expect(
            _text('readiness_detail_text'),
            startsWith(
              de
                  ? 'Heute fehlt der HRV-Wert der letzten Nacht.'
                  : 'Today there is no HRV value from last night.',
            ),
          );
          expect(_key('readiness_detail_reason_0'), findsOneWidget);
          expect(_key('readiness_detail_series_link'), findsOneWidget);
          // Die ersten zwei Tatsachen stehen schon im Text oben; unten nur
          // die weiteren, nichts doppelt.
          expect(s.result.facts, isNotEmpty);
          final further = s.result.facts.length > 2
              ? s.result.facts.length - 2
              : 0;
          expect(
            find.byWidgetPredicate(
              (w) =>
                  w.key is ValueKey<String> &&
                  (w.key! as ValueKey<String>).value.startsWith(
                    'readiness_detail_fact_',
                  ) &&
                  !(w.key! as ValueKey<String>).value.endsWith('basis'),
            ),
            findsNWidgets(further),
          );
        },
      );

      testWidgets('Unzureichend: fester Satz, alle Faktoren fehlen', (
        tester,
      ) async {
        final s = _insufficient();
        await open(tester, s);
        expect(_key('readiness_detail_case_insufficient'), findsOneWidget);
        expect(
          _text('readiness_detail_text'),
          de
              ? 'Heute liegen weder Schlaf noch eine frische Messung vor.'
              : 'Today there is neither sleep data nor a fresh measurement.',
        );
        for (final id in ReadinessFactorId.values) {
          expect(_key('readiness_detail_missing_${id.name}'), findsOneWidget);
        }
        expect(_key('readiness_detail_factors'), findsNothing);
      });

      testWidgets('markierte Tatsache: „geht in keine Zahl ein“, keine Zahl', (
        tester,
      ) async {
        final s = _marked();
        expect(s.result.markedFacts, isNotEmpty);
        await open(tester, s);
        expect(_key('readiness_detail_facts'), findsOneWidget);
        expect(
          _text('readiness_detail_facts_basis'),
          contains(de ? 'Median der Referenz' : 'median of the reference'),
        );
        expect(_key('readiness_detail_drivers_basis'), findsNothing);
        expect(
          find.textContaining(
            de ? 'geht in keine Zahl ein' : 'does not enter any number',
          ),
          findsWidgets,
        );
        expect(_key('readiness_detail_value'), findsNothing);
      });

      testWidgets(
        'Warnsignal steht vor der Einschätzung, Entwicklermodus nur als Hinweis',
        (tester) async {
          final base = _number();
          final s = ReadinessSnapshot(
            result: base.result,
            developerMode: true,
            extended: true,
            series: base.series,
          );
          await open(tester, s, w: true);
          final warn = tester.getTopLeft(_key('readiness_detail_warning')).dy;
          final est = tester
              .getTopLeft(_key('readiness_detail_case_number'))
              .dy;
          expect(warn, lessThan(est));
          expect(_key('readiness_detail_dev'), findsOneWidget);
          // Keine Kennzeichnung im Inhalt, derselbe Fall und dieselbe Zahl.
          expect(_text('readiness_detail_value'), '${base.result.value}');
        },
      );

      testWidgets('48 dp und Sprache: kein „erholt“/„bereit“ in Sätzen', (
        tester,
      ) async {
        await open(tester, _number());
        await tester.ensureVisible(_key('readiness_detail_series_link'));
        expect(
          tester.getSize(_key('readiness_detail_series_link')).height,
          greaterThanOrEqualTo(48),
        );
        final all = [
          for (final w in tester.widgetList<Text>(find.byType(Text)))
            if (w.key != const Key('readiness_detail_title')) w.data ?? '',
        ].join(' ');
        expect(
          RegExp(r'\b(bereit|ready|Diagnose gestellt)\b').hasMatch(all),
          isFalse,
        );
      });
    });

    group('Verlauf ($name)', () {
      Future<void> open(WidgetTester t, ReadinessSnapshot s) => _pump(
        t,
        ReadinessHistoryScreen(snapshot: s),
        locale: locale,
        dark: dark,
        width: width,
        scale: scale,
      );

      testWidgets(
        'Quellen getrennt: Uhr-App und zwei Kamerareihen, nie gemischt',
        (tester) async {
          final hrvA = _hcHrv(_hrv('app.a', _wave(40)));
          final cams = cameraDeviations([
            for (var i = 0; i < 29; i++) _morning(i),
            for (var i = 10; i < 29; i++)
              _morning(i, posture: RestingPosture.sitting, rmssd: 30),
          ], today: _today);
          final s = ReadinessSnapshot(
            result: _number().result,
            developerMode: true,
            extended: true,
            series: [hrvA, ...cams],
            today: _today,
          );
          // 1 Uhr-Reihe + (HRV, Ruhepuls) je zwei Haltungen.
          expect(cams.length, 4);
          await open(tester, s);
          final cards = find.byWidgetPredicate(
            (w) =>
                w.key.toString().startsWith("[<'readiness_series_hc_") ||
                w.key.toString().startsWith("[<'readiness_series_camera_"),
          );
          expect(cards, findsNWidgets(5));
          expect(_key('readiness_series_hc_hrv_0'), findsOneWidget);
          expect(find.text('Health Connect · app.a'), findsOneWidget);
          // Jede Karte zeichnet nur ihre eigene Reihe.
          for (var i = 0; i < 4; i++) {
            final key = 'camera_${cams[i].factor.name}_$i';
            final p =
                tester
                        .widget<CustomPaint>(
                          _key('readiness_series_chart_$key'),
                        )
                        .painter!
                    as ReadinessSeriesPainter;
            expect(
              p.values.whereType<double>().length,
              cams[i].byDay.length.clamp(0, 28),
              reason: key,
            );
            expect(p.values.whereType<double>().toSet().length, greaterThan(1));
          }
          final hcP =
              tester
                      .widget<CustomPaint>(
                        _key('readiness_series_chart_hc_hrv_0'),
                      )
                      .painter!
                  as ReadinessSeriesPainter;
          expect(hcP.values.whereType<double>().length, 28);
          // Die HC-Reihe hat keine Kamera-Quellzeile, Kamera keine App-Quelle.
          expect(find.textContaining('app.a'), findsOneWidget);
          expect(find.textContaining(de ? 'Liegend' : 'Lying'), findsWidgets);
          // Keine Bevölkerungswerte, Hinweis steht da.
          expect(_key('readiness_history_note'), findsOneWidget);
          expect(_key('readiness_history_dev'), findsOneWidget);
        },
      );

      testWidgets('Lücken bleiben Lücken, wenige Messungen sind genannt', (
        tester,
      ) async {
        // Kamera: nur 4 Werte in 7 Tagen, einzelne Lücken davor.
        final days = [
          for (var i = 0; i < 20; i++)
            if (i != 9 && i != 10) i,
          25,
          26,
          27,
          28,
        ];
        final cams = cameraDeviations([
          for (final i in days) _morning(i),
        ], today: _today);
        final s = ReadinessSnapshot(
          result: _number().result,
          developerMode: true,
          extended: true,
          series: cams,
          today: _today,
        );
        expect(cams.any((c) => c.fewMeasurements), isTrue);
        await open(tester, s);
        final p =
            tester
                    .widget<CustomPaint>(
                      _key('readiness_series_chart_camera_hrv_0'),
                    )
                    .painter!
                as ReadinessSeriesPainter;
        // Tag 9 und 10 (Index 8, 9 im 28-Tage-Fenster ab Tag 1) fehlen.
        expect(p.values.length, 28);
        expect(p.values[8], isNull);
        expect(p.values[9], isNull);
        expect(p.values[10], isNotNull);
        expect(_key('readiness_series_few_camera_hrv_0'), findsOneWidget);
        final render = tester.renderObject(
          _key('readiness_series_chart_camera_hrv_0'),
        );
        // Mehrere Linienstücke: die Lücke unterbricht die Linie.
        expect(
          render,
          paints
            ..path()
            ..path()
            ..path(),
        );
      });

      testWidgets(
        'gesperrte Kamerareihe gestrichelt und markiert, nicht im Entwicklermodus',
        (tester) async {
          final s = _marked();
          await open(tester, s);
          final p =
              tester
                      .widget<CustomPaint>(
                        _key('readiness_series_chart_camera_hrv_0'),
                      )
                      .painter!
                  as ReadinessSeriesPainter;
          expect(p.dashed, isTrue);
          expect(_key('readiness_series_mark_camera_hrv_0'), findsOneWidget);
          final d = ReadinessSnapshot(
            result: s.result,
            developerMode: true,
            extended: true,
            series: s.series,
            release: const CameraRelease(
              developerMode: true,
              rmssdOptIn: false,
            ),
            today: _today,
          );
          await open(tester, d);
          final pd =
              tester
                      .widget<CustomPaint>(
                        _key('readiness_series_chart_camera_hrv_0'),
                      )
                      .painter!
                  as ReadinessSeriesPainter;
          expect(pd.dashed, isFalse);
          expect(_key('readiness_series_mark_camera_hrv_0'), findsNothing);
        },
      );

      testWidgets('ohne Reihen: Hinweis statt Diagrammen', (tester) async {
        await open(tester, _insufficient());
        expect(_key('readiness_history_none'), findsOneWidget);
      });
    });
  }
}
