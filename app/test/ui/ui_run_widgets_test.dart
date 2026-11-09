import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ui.dart';

import 'ui_widgets_test.dart' show colorsOf, expectTarget, modes, pumpUi;

/// Bausteine der Lauf-Seiten (WP16 A): Umschalter in voller Breite,
/// Live-Zonenanzeige, Startknopf, Bereitschaftszeile, Töne und Größen.
void main() {
  for (final mode in modes) {
    final name = mode == ThemeMode.dark ? 'dunkel' : 'hell';

    testWidgets('Töne und Größen aus dem Design $name', (tester) async {
      late BuildContext context;
      await pumpUi(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
        mode: mode,
      );
      final c = RamuriColors.of(context);
      expect(c, colorsOf(mode));
      if (mode == ThemeMode.light) {
        expect(c.segmentTrack, const Color(0xFFE2EAE8));
        expect(c.zoneDone, const Color(0xFFD3EEE9));
        expect(c.textLabel, const Color(0xFF3A4F4D));
        expect(c.emberTint, const Color(0xFFFFE6DA));
        expect(c.accentFaint, const Color(0xFF8DBDB4));
      }
      final t = RamuriType.of(context);
      expect(t.startButton.fontSize, 30);
      expect(t.hero.fontSize, 48);
      expect(t.sheetValue.fontSize, 44);
    });

    testWidgets('Umschalter soft in voller Breite $name', (tester) async {
      var value = 'a';
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, setState) => SizedBox(
            width: 360,
            child: RamuriSegmentedToggle<String>(
              expanded: true,
              style: RamuriSegmentedStyle.soft,
              segments: const [
                RamuriSegment(value: 'a', label: 'Eins'),
                RamuriSegment(value: 'b', label: 'Zwei'),
              ],
              selected: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
        mode: mode,
      );
      expect(
        tester.getSize(find.byType(RamuriSegmentedToggle<String>)).width,
        360,
      );
      expectTarget(
        tester,
        find.ancestor(of: find.text('Eins'), matching: find.byType(InkWell)),
      );
      final track = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(RamuriSegmentedToggle<String>),
              matching: find.byType(DecoratedBox),
            ),
          )
          .first;
      expect(
        (track.decoration as BoxDecoration).color,
        colorsOf(mode).segmentTrack,
      );
      await tester.tap(find.text('Zwei'));
      await tester.pump();
      expect(value, 'b');
    });

    testWidgets('ZoneMeter färbt Stücke nach Zone $name', (tester) async {
      final c = colorsOf(mode);
      await pumpUi(
        tester,
        const SizedBox(
          width: 300,
          child: ZoneMeter(zone: 2, semanticLabel: 'Zone 2 von 5'),
        ),
        mode: mode,
      );
      Color? at(int i) =>
          (tester
                      .widget<DecoratedBox>(find.byKey(Key('zone_meter_$i')))
                      .decoration
                  as BoxDecoration)
              .color;
      expect(
        [for (var i = 1; i <= 5; i++) at(i)],
        [c.zoneDone, c.accent, c.segmentTrack, c.segmentTrack, c.segmentTrack],
      );
      // Nur die aktuelle Zone trägt den Ring.
      final ring = [
        for (var i = 1; i <= 5; i++)
          (tester
                      .widget<DecoratedBox>(find.byKey(Key('zone_meter_$i')))
                      .decoration
                  as BoxDecoration)
              .boxShadow,
      ];
      expect(ring.map((s) => s != null).toList(), [
        false,
        true,
        false,
        false,
        false,
      ]);
      // Fünf gleich breite Stücke.
      final widths = {
        for (var i = 1; i <= 5; i++)
          tester.getSize(find.byKey(Key('zone_meter_$i'))).width,
      };
      expect(widths.length, 1);
      // Die Stücke sind sichtbar hoch (nicht 0 dp, weil die Row zentriert).
      for (var i = 1; i <= 5; i++) {
        expect(tester.getSize(find.byKey(Key('zone_meter_$i'))).height, 10);
      }
      expect(find.bySemanticsLabel('Zone 2 von 5'), findsOneWidget);
    });

    testWidgets('ZoneMeter ohne Zone: alle grau $name', (tester) async {
      final c = colorsOf(mode);
      await pumpUi(
        tester,
        const SizedBox(
          width: 300,
          child: ZoneMeter(zone: null, semanticLabel: 'keine Zone'),
        ),
        mode: mode,
      );
      for (var i = 1; i <= 5; i++) {
        final d =
            tester
                    .widget<DecoratedBox>(find.byKey(Key('zone_meter_$i')))
                    .decoration
                as BoxDecoration;
        expect(d.color, c.segmentTrack);
        expect(d.boxShadow, isNull);
      }
    });

    testWidgets('Startknopf 132 dp, aus ohne Wirkung $name', (tester) async {
      var taps = 0;
      Widget button(VoidCallback? onPressed) => RamuriStartButton(
        key: const Key('go'),
        label: 'Los',
        onPressed: onPressed,
      );
      await pumpUi(tester, button(() => taps++), mode: mode);
      expect(
        tester.getSize(find.byKey(const Key('go'))),
        const Size(132 + 24, 132 + 24),
      );
      await tester.tap(find.byKey(const Key('go')));
      expect(taps, 1);
      await pumpUi(tester, button(null), mode: mode);
      await tester.tap(find.byKey(const Key('go')));
      expect(taps, 1);
    });

    testWidgets('Bereitschaftszeile wächst mit der Schrift $name', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpUi(
        tester,
        const SizedBox(
          width: 280,
          child: RamuriReadinessRow(
            icon: Icons.place_outlined,
            title: 'Schrittfrequenz',
            subtitle: 'Optional, geht auch ohne',
            trailing: Text('Freigabe beim Start'),
          ),
        ),
        mode: mode,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(RamuriReadinessRow)).height,
        greaterThanOrEqualTo(56),
      );
    });
  }
}
