import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/statistics/statistics_view.dart';
import 'package:running_app/l10n/app_localizations.dart';
import 'package:running_app/ui/ui.dart';

/// Lange Ersatztexte in `StatRow` (WP18, M1 Fehler 1): Der Satz „nicht
/// verfügbar (…)“ brach neben dem Label in 7 Zeilen. Jetzt steht der Wert
/// untereinander, sobald er nebeneinander mehr als 2 Zeilen bräuchte.
/// Mit der echten Schrift (Ahem würde falsche Breiten liefern).

Future<void> _loadManrope(WidgetTester t) => t.runAsync(() async {
  final loader = FontLoader('Manrope');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Manrope-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
});

Future<void> _pump(
  WidgetTester t, {
  required String locale,
  required double width,
  required double scale,
  required String Function(AppLocalizations) label,
  required String Function(AppLocalizations) value,
}) async {
  await _loadManrope(t);
  t.view.physicalSize = Size(width, 2000);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(
    MaterialApp(
      theme: RamuriTheme.light,
      locale: Locale(locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: StatRow(id: 'row', label: label(l10n), value: value(l10n)),
            );
          },
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

void main() {
  for (final locale in ['de', 'en']) {
    for (final width in [360.0, 320.0]) {
      testWidgets(
        'Ersatztext $locale $width dp x 1,3: untereinander, höchstens 3 Zeilen',
        (t) async {
          await _pump(
            t,
            locale: locale,
            width: width,
            scale: 1.3,
            label: (l) => l.sumBestPace,
            value: (l) => l.statNoValue,
          );
          final paragraph = t.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(const Key('row_value')),
              matching: find.byType(RichText),
            ),
          );
          final one = TextPainter(
            text: TextSpan(text: 'x', style: paragraph.text.style),
            textDirection: TextDirection.ltr,
            textScaler: paragraph.textScaler,
          )..layout();
          expect(
            paragraph.size.height,
            lessThanOrEqualTo(3 * one.height + 0.5),
            reason: 'Wert höher als 3 Zeilen: ${paragraph.size.height}',
          );
          // Neben dem Label wären es 7 Zeilen gewesen: Der Wert steht darunter.
          final value = t.getRect(find.byKey(const Key('row_value')));
          final label = t.getRect(
            find
                .descendant(
                  of: find.byKey(const Key('row')),
                  matching: find.byType(Text),
                )
                .first,
          );
          expect(value.top, greaterThanOrEqualTo(label.bottom - 0.5));
          expect(t.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('kurzer Wert bleibt neben dem Label', (t) async {
    await _pump(
      t,
      locale: 'de',
      width: 360,
      scale: 1.3,
      label: (_) => 'Distanz',
      value: (_) => '12,3 km',
    );
    final value = t.getRect(find.byKey(const Key('row_value')));
    final label = t.getRect(
      find
          .descendant(
            of: find.byKey(const Key('row')),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(value.top, lessThan(label.bottom - 0.5), reason: 'nebeneinander');
    expect(value.left, greaterThanOrEqualTo(label.right));
  });
}
