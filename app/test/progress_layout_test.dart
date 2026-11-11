import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/settings/unit_format.dart';
import 'package:running_app/features/statistics/progress_header.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

import 'history_summary_test.dart' show started;
import 'progress_cards_test.dart' show overview, stored;
import 'statistics_test.dart' show openStats;
import 'app_harness.dart';

/// Layout der Fortschrittskarten gegen das Design (WP15 Nachbesserung 4):
/// Positionen statt nur Texte.

const _km = UnitFormatter(
  unit: DistanceUnit.kilometers,
  languageCode: 'de',
  distanceLabel: 'km',
  paceLabel: 'min/km',
  elevationLabel: 'm',
);

class _NoSession implements StorageSession {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Speicher nicht erwartet');
}

RunFigures _run(int id, String day, double meters) => RunFigures(
  runId: id,
  endedAt: DateTime.parse('${day}T09:00:00Z'),
  day: day,
  distanceMeters: meters,
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 411,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: RamuriTheme.light,
      locale: const Locale('de'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _week(List<RunFigures> runs) => WeekDistanceCard(
  series: weeklyDistanceSeries('2026-06-03', runs),
  formatter: _km,
  hasAnyRun: runs.isNotEmpty,
);

void main() {
  group('Balkenkarte: Kopf und Fuß über die volle Breite', () {
    for (final (width, scale) in [
      (411.0, 1.0),
      (411.0, 0.55),
      (320.0, 1.0),
      (320.0, 2.0),
    ]) {
      testWidgets('Breite $width, Schrift $scale: rechte Ränder bündig, '
          'ohne Überlauf', (tester) async {
        await _pump(
          tester,
          _week([
            _run(1, '2026-06-01', 5000),
            _run(2, '2026-05-27', 8000),
            _run(3, '2026-04-14', 4000),
          ]),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        final bars = tester.getRect(key('progress_week_bars'));
        expect(
          tester.getRect(key('progress_week_range')).right,
          closeTo(bars.right, 0.5),
          reason: '„letzte 8 Wochen“ rechts bündig mit den Balken',
        );
        expect(
          tester.getRect(key('progress_week_now')).right,
          closeTo(bars.right, 0.5),
          reason: '„jetzt“ rechts bündig unter der letzten Säule',
        );
        expect(
          tester.getRect(key('progress_week_first')).left,
          closeTo(bars.left, 0.5),
          reason: '„KW“ linksbündig',
        );
      });
    }

    testWidgets('Mitte steht zwischen den Enden, nicht daneben', (
      tester,
    ) async {
      await _pump(tester, _week([_run(1, '2026-06-01', 5000)]));
      final first = tester.getRect(key('progress_week_first'));
      final last = tester.getRect(key('progress_week_last'));
      final now = tester.getRect(key('progress_week_now'));
      expect(last.left, greaterThan(first.right + 8));
      expect(now.left, greaterThan(last.right + 8));
    });

    testWidgets('ohne jeden Lauf: Hinweis „Noch keine Läufe“', (tester) async {
      await _pump(tester, _week(const []));
      expect(key('progress_week_no_runs'), findsOneWidget);
      expect(
        (tester.widget(key('progress_week_no_runs')) as Text).data,
        'Noch keine Läufe aufgezeichnet.',
      );
    });

    testWidgets('Lauf nur vor 10 Wochen: kein Hinweis, Balken ohne Strecke', (
      tester,
    ) async {
      await _pump(tester, _week([_run(1, '2026-03-25', 5000)]));
      expect(key('progress_week_no_runs'), findsNothing);
      expect(
        weeklyDistanceSeries('2026-06-03', [
          _run(1, '2026-03-25', 5000),
        ]).every((w) => w.meters == 0),
        isTrue,
      );
    });

    testWidgets('mit einem Lauf kein Hinweis', (tester) async {
      await _pump(tester, _week([_run(1, '2026-06-01', 5000)]));
      expect(key('progress_week_no_runs'), findsNothing);
    });
  });

  group('VO₂max-Karte wie im Design', () {
    Future<void> pumpVo2(WidgetTester tester, FitnessOverview f) => _pump(
      tester,
      Vo2ProgressCard(
        fitness: f,
        session: _NoSession(),
        onExplain: (context, valueKey, {runId, day}) {},
      ),
    );
    final withValue = overview(
      longTerm: stored(vo2maxLongTermValueKey, 46.04),
      weeks: const [('2026-05-25', 44.0), ('2026-06-01', 46.04)],
    );

    testWidgets('Verlauf rechts in der Zeile der Zahl, Beschriftung darunter '
        'über die volle Breite', (tester) async {
      await pumpVo2(tester, withValue);
      final card = tester.getRect(find.byType(RamuriCard));
      final hero = tester.getRect(key('progress_vo2'));
      final spark = tester.getRect(key('progress_vo2_sparkline'));
      final current = tester.getRect(key('progress_vo2_current'));
      final asOf = tester.getRect(key('progress_vo2_asof'));
      expect(spark.bottom, closeTo(hero.bottom, 2), reason: 'unten bündig');
      expect(spark.top, lessThan(hero.bottom), reason: 'gleiche Zeile');
      expect(spark.right, lessThanOrEqualTo(card.right));
      expect(spark.right, greaterThan(card.right - 24), reason: 'rechts');
      expect(current.top, greaterThanOrEqualTo(spark.bottom - 0.5));
      expect(asOf.top, greaterThanOrEqualTo(current.bottom - 0.5));
      // Volle Breite: die Beschriftung bricht nicht neben dem Verlauf um.
      expect(
        tester.getSize(key('progress_vo2_current')).width,
        greaterThan(spark.left - current.left),
      );
    });

    testWidgets('Link in Designgröße 14, Gewicht 800, Tippziel 48', (
      tester,
    ) async {
      await pumpVo2(tester, withValue);
      final p = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: key('progress_vo2_explain'),
          matching: find.byType(RichText),
        ),
      );
      expect(p.text.style!.fontSize, 14);
      expect(p.text.style!.fontWeight, FontWeight.w800);
      expect(
        tester.getSize(key('progress_vo2_explain')).height,
        greaterThanOrEqualTo(48),
      );
    });

    testWidgets('ohne Wert kein Chip „Schätzung“, der Grund bleibt', (
      tester,
    ) async {
      await pumpVo2(
        tester,
        overview(longTerm: stored(vo2maxLongTermValueKey, null)),
      );
      expect(find.text('Schätzung'), findsNothing);
      expect(key('progress_vo2_reason'), findsOneWidget);
    });

    testWidgets('mit Wert steht der Chip „Schätzung“', (tester) async {
      await pumpVo2(tester, withValue);
      expect(find.text('Schätzung'), findsOneWidget);
    });
  });

  testWidgets('Zeilenlabel „Herzfrequenzzonen“ bricht bei 390 dp nicht im '
      'Wort', (tester) async {
    final d = await started(tester);
    tester.view.physicalSize = const Size(390, 2400);
    // Die Testschrift (Ahem) ist 1 em breit je Zeichen, Manrope etwa 0,55 em.
    // Skala 0,6 gibt dem Label seine Breite auf dem Gerät (~150 dp).
    tester.platformDispatcher.textScaleFactorTestValue = 0.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openStats(d, tester);
    final label = find.descendant(
      of: key('stat_zones'),
      matching: find.text('Herzfrequenzzonen'),
    );
    expect(label, findsOneWidget);
    final p = tester.renderObject<RenderParagraph>(label);
    expect(
      p.size.height,
      lessThan(p.text.style!.fontSize! * 1.4 * 0.6 * 1.5),
      reason: 'Label einzeilig, sonst bricht es im Wort',
    );
  });
}
