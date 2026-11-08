import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ui.dart';

import 'ui_widgets_test.dart' show colorsOf, modes, pumpUi;

Color? barColor(WidgetTester tester, int i) =>
    ((tester.widget<Container>(find.byKey(Key('week_bar_$i')))).decoration!
            as BoxDecoration)
        .color;

double barHeightOf(WidgetTester tester, int i) =>
    tester.getSize(find.byKey(Key('week_bar_$i'))).height;

void main() {
  for (final mode in modes) {
    final name = mode == ThemeMode.dark ? 'dunkel' : 'hell';

    group('RamuriWeekBars $name', () {
      testWidgets('Höhe relativ zum Maximum, Töne je Rolle', (tester) async {
        final c = colorsOf(mode);
        await pumpUi(
          tester,
          const SizedBox(
            width: 360,
            child: RamuriWeekBars(
              values: [10, 20, 5, 40, 30, 20, 40, 20],
              semanticLabel: 'Wochenkilometer: Beispiel',
            ),
          ),
          mode: mode,
        );
        expect(barHeightOf(tester, 3), closeTo(130, 0.01));
        expect(barHeightOf(tester, 0), closeTo(32.5, 0.01));
        expect(barHeightOf(tester, 1), closeTo(65, 0.01));
        expect(barColor(tester, 0), c.weekBarOlder);
        expect(barColor(tester, 5), c.weekBarOlder);
        expect(barColor(tester, 6), c.weekBarLast);
        expect(barColor(tester, 7), c.weekBarCurrent);
        expect(find.byKey(const Key('week_bars_baseline')), findsOneWidget);
        expect(find.byType(RamuriWeekBars), findsOneWidget);
      });

      testWidgets('alle 0: keine Division durch 0, Nulllinie sichtbar', (
        tester,
      ) async {
        await pumpUi(
          tester,
          const SizedBox(
            width: 360,
            child: RamuriWeekBars(
              values: [0, 0, 0, 0, 0, 0, 0, 0],
              semanticLabel: 'Wochenkilometer: alle 0',
            ),
          ),
          mode: mode,
        );
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 8; i++) {
          expect(barHeightOf(tester, i), ramuriWeekBarMinHeight);
        }
        final line = tester.getSize(
          find.byKey(const Key('week_bars_baseline')),
        );
        expect(line.height, greaterThanOrEqualTo(2));
        expect(line.width, greaterThan(300));
      });

      testWidgets('Woche ohne Wert: Strich, Nullwoche bleibt in Balkenfarbe', (
        tester,
      ) async {
        final c = colorsOf(mode);
        await pumpUi(
          tester,
          const SizedBox(
            width: 360,
            child: RamuriWeekBars(
              values: [0, null, 12, 0, 0, 0, 24, 6],
              semanticLabel: 'x',
            ),
          ),
          mode: mode,
        );
        expect(barHeightOf(tester, 1), ramuriWeekBarMinHeight);
        expect(barColor(tester, 1), c.outlineStrong);
        expect(barColor(tester, 0), c.weekBarOlder);
        expect(barHeightOf(tester, 0), ramuriWeekBarMinHeight);
        expect(barHeightOf(tester, 6), closeTo(130, 0.01));
        expect(barHeightOf(tester, 7), closeTo(32.5, 0.01));
      });

      testWidgets('kleiner Wert bleibt sichtbar; Semantics vom Aufrufer', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await pumpUi(
          tester,
          const SizedBox(
            width: 360,
            child: RamuriWeekBars(
              values: [0.01, 100],
              semanticLabel: 'Wochenkilometer: 0,01 und 100 km',
            ),
          ),
          mode: mode,
        );
        expect(barHeightOf(tester, 0), ramuriWeekBarMinHeight);
        expect(
          find.bySemanticsLabel('Wochenkilometer: 0,01 und 100 km'),
          findsOneWidget,
        );
        handle.dispose();
      });
    });

    group('RamuriSparkline $name', () {
      testWidgets('ab zwei Punkten gezeichnet, in Aktionsfarbe', (
        tester,
      ) async {
        final c = colorsOf(mode);
        await pumpUi(
          tester,
          const RamuriSparkline(
            values: [44, 45, 46],
            semanticLabel: 'Trend steigend',
          ),
          mode: mode,
        );
        final paint = tester.widget<CustomPaint>(
          find.byKey(const Key('sparkline')),
        );
        final painter = paint.painter! as SparklinePainter;
        expect(painter.points, hasLength(3));
        expect(painter.color, c.action);
        expect(
          tester.getSize(find.byKey(const Key('sparkline'))),
          const Size(120, 44),
        );
        expect(find.bySemanticsLabel('Trend steigend'), findsOneWidget);
      });

      testWidgets('unter zwei Punkten nichts', (tester) async {
        for (final v in [
          <double>[],
          <double>[46],
        ]) {
          await pumpUi(
            tester,
            RamuriSparkline(values: v, semanticLabel: 'x'),
            mode: mode,
          );
          expect(find.byKey(const Key('sparkline')), findsNothing);
        }
      });
    });

    testWidgets('RamuriSegmentedToggle volle Breite $name', (tester) async {
      await pumpUi(
        tester,
        SizedBox(
          width: 340,
          child: RamuriSegmentedToggle<int>(
            expanded: true,
            segments: const [
              RamuriSegment(value: 1, label: 'Woche'),
              RamuriSegment(value: 2, label: 'Monat'),
            ],
            selected: 1,
            onChanged: (_) {},
          ),
        ),
        mode: mode,
      );
      expect(
        tester.getSize(find.byType(RamuriSegmentedToggle<int>)).width,
        340,
      );
      final a = tester.getSize(find.text('Woche')).width;
      expect(a, lessThan(100));
      final left = tester.getTopLeft(find.text('Monat')).dx;
      expect(left, greaterThan(170));
    });

    testWidgets('RamuriSegmentedToggle Vorgabe bleibt schmal $name', (
      tester,
    ) async {
      await pumpUi(
        tester,
        SizedBox(
          width: 340,
          child: Align(
            alignment: Alignment.topLeft,
            child: RamuriSegmentedToggle<int>(
              segments: const [
                RamuriSegment(value: 1, label: 'Woche'),
                RamuriSegment(value: 2, label: 'Monat'),
              ],
              selected: 1,
              onChanged: (_) {},
            ),
          ),
        ),
        mode: mode,
      );
      expect(
        tester.getSize(find.byType(RamuriSegmentedToggle<int>)).width,
        lessThan(250),
      );
    });

    testWidgets('Theme-Stile hero 48 und pageTitle 34/800 $name', (
      tester,
    ) async {
      late RamuriType type;
      await pumpUi(
        tester,
        Builder(
          builder: (context) {
            type = RamuriType.of(context);
            return const SizedBox();
          },
        ),
        mode: mode,
      );
      final c = colorsOf(mode);
      expect(type.hero.fontSize, 48);
      expect(type.hero.fontFamily, ramuriHeadingFamily);
      expect(type.hero.color, c.text);
      expect(type.pageTitle.fontSize, 34);
      expect(type.pageTitle.fontWeight, FontWeight.w800);
      expect(type.pageTitle.color, c.text);
    });
  }

  test('Sparkline: Mindestspanne, y-Achse aufwärts, Ränder', () {
    const size = Size(120, 44);
    // 0,1 ml/kg/min Änderung bewegt die Linie nur wenige dp.
    final flat = RamuriSparkline.pointsFor([46.0, 46.1], size);
    expect((flat[0].dy - flat[1].dy).abs(), lessThan(3));
    expect(flat[1].dy, lessThan(flat[0].dy)); // höher = weiter oben
    // Echte Spanne nutzt die Höhe.
    final big = RamuriSparkline.pointsFor([40.0, 50.0], size);
    expect((big[0].dy - big[1].dy).abs(), greaterThan(35));
    // Alle gleich: Linie in der Mitte, kein NaN.
    final same = RamuriSparkline.pointsFor([46.0, 46.0, 46.0], size);
    expect(same.every((p) => p.dy == 22 && p.dy.isFinite), isTrue);
    // Punkte liegen in der Fläche, erster links, letzter rechts.
    for (final p in big) {
      expect(p.dx, inInclusiveRange(0, 120));
      expect(p.dy, inInclusiveRange(0, 44));
    }
    expect(big.first.dx, lessThan(big.last.dx));
    // Weniger als zwei Werte: keine Punkte.
    expect(RamuriSparkline.pointsFor([46.0], size), isEmpty);
  });

  test('WeekBars.barHeight: Randfälle', () {
    expect(RamuriWeekBars.barHeight(0, 0, 130), ramuriWeekBarMinHeight);
    expect(RamuriWeekBars.barHeight(null, 10, 130), ramuriWeekBarMinHeight);
    expect(RamuriWeekBars.barHeight(10, 10, 130), 130);
    expect(RamuriWeekBars.barHeight(5, 10, 130), 65);
  });
}
