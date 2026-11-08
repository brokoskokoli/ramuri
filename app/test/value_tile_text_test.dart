// WP16 Runde 4, Punkt 1: Ersatztexte in Wertkacheln stehen klein, der Grund in
// einer eigenen Zeile, und kein Wort bricht mitten im Wort (echte Schrift).

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/l10n/app_localizations_de.dart';
import 'package:running_app/l10n/app_localizations_en.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';

Widget _app(Widget body, {required double scale, required Size size}) =>
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
      'load': l10n.runZoneNoBasis,
      'stored': l10n.sumLoadNotStored,
      'plain': l10n.runUnavailable,
    };
    testWidgets('echte Schrift, $lang, ${width.round()} dp, Faktor $scale: '
        'Ersatztext klein, Grund eigene Zeile, kein Bruch im Wort', (
      tester,
    ) async {
      await loadManrope(tester);
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
}
