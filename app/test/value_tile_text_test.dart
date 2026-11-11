// WP16 Runde 4, Punkt 1: Ersatztexte in Wertkacheln stehen klein, der Grund in
// einer eigenen Zeile, und kein Wort bricht mitten im Wort (echte Schrift).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/l10n/app_localizations_de.dart';
import 'package:running_app/l10n/app_localizations_en.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

Widget _app(Widget body, {required double scale, required Size size}) =>
    localizedApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20), // wie die Zusammenfassung
            child: body,
          ),
        ),
      ),
    );

/// Die Teile mit Text samt wirksamem Stil.
Iterable<TextSpan> _leaves(TextSpan span, [TextStyle? parent]) sync* {
  final style = parent == null ? span.style : parent.merge(span.style);
  if (span.text != null) yield TextSpan(text: span.text, style: style);
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _leaves(child as TextSpan, style);
  }
}

void main() {
  final variants = [
    for (final (lang, l10n) in <(String, AppLocalizations)>[
      ('de', AppLocalizationsDe()),
      ('en', AppLocalizationsEn()),
    ])
      for (final (width, scale) in [
        (411.0, 1.0),
        (360.0, 1.0),
        (320.0, 1.0),
        (411.0, 1.3),
        (360.0, 2.0),
      ])
        (lang, l10n, width, scale),
  ];
  for (final (lang, l10n, width, scale) in variants) {
    final texts = {
      'best': l10n.sumBestPaceNone,
      'hr': l10n.sumNoHeartRate,
      'load': l10n.sumNoBasisShort,
      'stored': l10n.sumLoadNotStored,
      'plain': l10n.runUnavailable,
    };
    testWidgets('echte Schrift, $lang, ${width.round()} dp, Faktor $scale: '
        'Ersatztext klein, Grund eigene Zeile, kein Bruch im Wort', (
      tester,
    ) async {
      await loadManrope(tester);
      await loadSora(tester);
      final size = Size(width, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          RamuriTileGrid(
            children: [
              for (final e in texts.entries)
                RamuriValueTile(
                  label: e.key,
                  value: e.value,
                  textValue: true,
                  valueKey: Key(e.key),
                ),
              const RamuriValueTile(
                label: 'Zahl',
                value: '5:40',
                unit: 'min/km',
                valueKey: Key('number'),
              ),
            ],
          ),
          scale: scale,
          size: size,
        ),
      );
      // Bei Faktor 1,0 und mindestens 360 dp bleibt es wie im Design bei drei
      // Spalten, auch wenn alle Ersatztexte gleichzeitig stehen.
      if (scale == 1.0 && width >= 360) {
        final lefts = {
          for (final t in tester.widgetList(find.byType(RamuriValueTile)))
            tester.getTopLeft(find.byWidget(t)).dx.round(),
        };
        expect(lefts.length, 3, reason: 'Spalten bei ${width.round()} dp');
      }
      final numberHeight = tester
          .getSize(find.byKey(const Key('number')))
          .height;
      for (final e in texts.entries) {
        final finder = find.byKey(Key(e.key));
        final paragraph = tester.renderObject<RenderParagraph>(finder);
        final span = paragraph.text as TextSpan;
        // Jedes Wort passt unverkürzt in die Zeile: kein Bruch im Wort.
        for (final part in _leaves(span)) {
          for (final word in part.text!.trim().split(RegExp(r'\s+'))) {
            final painter = TextPainter(
              text: TextSpan(text: word, style: part.style),
              textDirection: TextDirection.ltr,
              textScaler: TextScaler.linear(scale),
            )..layout();
            expect(
              painter.width,
              lessThanOrEqualTo(paragraph.size.width + 0.01),
              reason:
                  '"$word" in ${e.key} bricht (Breite ${paragraph.size.width})',
            );
            painter.dispose();
          }
        }
        final lines = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout(maxWidth: paragraph.size.width);
        final metrics = lines.computeLineMetrics();
        lines.dispose();
        // Höchstens vier Zeilen je Kachel.
        expect(
          metrics.length,
          // Die Aussage allein bricht in drei schmalen Spalten zwischen den
          // Wörtern („nicht / verfügbar“), nie mitten im Wort.
          lessThanOrEqualTo(e.key == 'plain' ? 2 : 4),
          reason: e.key,
        );
        // Kleiner als der Zahlenwert (Sora 22 sp).
        expect(metrics.first.height, lessThan(22.0 * scale), reason: e.key);
      }
      expect(numberHeight, greaterThan(20));
      expect(tester.takeException(), isNull);
    });
  }

  // Review 5, Befund 1: Eine Zahl bricht nie innerhalb der Ziffern („+120 / 0“).
  for (final width in [320.0, 340.0, 360.0, 411.0]) {
    for (final scale in [1.0, 1.15, 1.3, 2.0]) {
      testWidgets('große Zahlen brechen nie, ${width.round()} dp, '
          'Faktor $scale', (tester) async {
        await loadManrope(tester);
        await loadSora(tester);
        final size = Size(width, 900);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const numbers = [
          ('+1200', 'm'),
          ('−1200', 'm'),
          ('+3937', 'ft'),
          ('10,50', 'km'),
        ];
        await tester.pumpWidget(
          _app(
            RamuriTileGrid(
              children: [
                for (final (v, u) in numbers)
                  RamuriValueTile(
                    label: 'Zahl',
                    value: v,
                    unit: u,
                    valueKey: Key(v),
                  ),
              ],
            ),
            scale: scale,
            size: size,
          ),
        );
        final style = RamuriType.of(tester.element(find.byType(RamuriTileGrid)))
            .valueSmall;
        for (final (v, _) in numbers) {
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byKey(Key(v)),
          );
          final painter = TextPainter(
            text: TextSpan(text: v, style: style),
            textDirection: TextDirection.ltr,
            textScaler: TextScaler.linear(scale),
          )..layout();
          expect(
            painter.width,
            lessThanOrEqualTo(paragraph.size.width + 0.01),
            reason: '"$v" bricht (Breite ${paragraph.size.width})',
          );
          painter.dispose();
        }
        if (scale == 1.0 && width >= 360) {
          final lefts = {
            for (final t in tester.widgetList(find.byType(RamuriValueTile)))
              tester.getTopLeft(find.byWidget(t)).dx.round(),
          };
          expect(lefts.length, 3, reason: 'Spalten bei ${width.round()} dp');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  // E2E 31: 360 dp, Faktor 1,15, die Zahl "+1200" steht in einer Zeile.
  testWidgets(
    'Die Zahl +1200 steht auf 360 dp bei Faktor 1,15 in einer Zeile',
    (tester) async {
      await loadManrope(tester);
      await loadSora(tester);
      const size = Size(360, 900);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          RamuriTileGrid(
            children: const [
              RamuriValueTile(
                label: 'Zahl',
                value: '+1200',
                unit: 'm',
                valueKey: Key('n1200'),
              ),
              RamuriValueTile(label: 'Zahl', value: '5:30', unit: 'min/km'),
              RamuriValueTile(label: 'Zahl', value: '10,50', unit: 'km'),
            ],
          ),
          scale: 1.15,
          size: size,
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('n1200')),
      );
      // Alle Zeichen der Zahl (nicht der Einheit) liegen auf derselben Zeile.
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      final tops = {for (final b in boxes) b.top.round()};
      expect(tops.length, 1, reason: 'Zahl bricht: $tops');
      expect(paragraph.text.toPlainText(), contains('+1200'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Aussage und Grund sind getrennt, der Text bleibt vollständig', (
    tester,
  ) async {
    expect(RamuriValueTile.splitReason('nicht verfügbar (kein Puls)'), (
      'nicht verfügbar',
      '(kein Puls)',
    ));
    expect(RamuriValueTile.splitReason('nicht verfügbar – Ruhepuls prüfen'), (
      'nicht verfügbar',
      'Ruhepuls prüfen',
    ));
    expect(RamuriValueTile.splitReason('nicht verfügbar'), (
      'nicht verfügbar',
      null,
    ));
  });

  // WP17 B2: Passen Zahl und Einheit in die Spalte, stehen sie in einer Zeile.
  // Passen sie nicht (drei Spalten auf 360 dp, Design), steht die Einheit als
  // Ganzes unter der Zahl; die Zahl bricht nie, und das Raster nimmt keine
  // weitere Spalte weg. (Das B-Gate maß hier mit gleicher Oberkante je Kasten
  // und sah „eine Zeile“ auch bei zwei Zeilen: darum zählt dieser Test Zeilen
  // über die Höhe des Absatzes.)
  for (final scale in [1.0, 1.15, 1.3]) {
    for (final (v, u) in [('+1200', 'm'), ('+3937', 'ft')]) {
      testWidgets('Zahl und Einheit: $v $u, 360 dp, '
          'Faktor $scale', (tester) async {
        await loadManrope(tester);
        await loadSora(tester);
        const size = Size(360, 900);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          _app(
            RamuriTileGrid(
              children: [
                RamuriValueTile(
                  label: 'Zahl',
                  value: v,
                  unit: unbreakableUnit(u),
                  valueKey: const Key('wert'),
                ),
                const RamuriValueTile(label: 'Zahl', value: '5:30', unit: 'km'),
                const RamuriValueTile(label: 'Zahl', value: '1', unit: 'km'),
              ],
            ),
            scale: scale,
            size: size,
          ),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(const Key('wert')),
        );
        final span = paragraph.text as TextSpan;
        final painter = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout();
        final oneLine = painter.width <= paragraph.size.width + 0.01;
        final lines = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        )..layout(maxWidth: paragraph.size.width);
        final count = lines.computeLineMetrics().length;
        if (oneLine) {
          expect(count, 1, reason: 'passt in die Spalte, bricht aber');
        } else {
          // Zahl in einer Zeile, Einheit ganz darunter: zwei Zeilen.
          expect(count, 2, reason: 'Einheit als Ganzes unter der Zahl');
        }
        painter.dispose();
        lines.dispose();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
