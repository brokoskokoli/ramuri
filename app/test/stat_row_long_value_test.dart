import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/statistics/statistics_view.dart';
import 'package:running_app/l10n/app_localizations.dart';

import 'app_harness.dart';

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
  bool inCard = false,
}) async {
  await _loadManrope(t);
  t.view.physicalSize = Size(width, 2000);
  t.view.devicePixelRatio = 1;
  t.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(t.view.reset);
  addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
  await t.pumpWidget(
    localizedApp(
      locale: Locale(locale),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            final row = StatRow(
              id: 'row',
              label: label(l10n),
              value: value(l10n),
            );
            // Wie auf „Fortschritt“: Seitenrand 20, Karte mit Innenrand 16.
            return inCard
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: StatCard(children: [row]),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: row,
                  );
          },
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

/// Zeilen eines Absatzes, aus seiner Höhe und der Höhe einer Zeile.
int _lines(RenderParagraph p) {
  final one = TextPainter(
    text: TextSpan(text: 'x', style: p.text.style),
    textDirection: TextDirection.ltr,
    textScaler: p.textScaler,
  )..layout();
  final n = (p.size.height / one.height - 0.01).ceil();
  one.dispose();
  return n;
}

/// Kein Wort, das allein in eine Zeile passt, wird geteilt: Jedes solche
/// Wort liegt ganz in einer Zeile.
void _expectWholeWords(RenderParagraph p) {
  final text = p.text.toPlainText();
  for (final m in RegExp(r'\S+').allMatches(text)) {
    final word = TextPainter(
      text: TextSpan(text: m[0], style: p.text.style),
      textDirection: TextDirection.ltr,
      textScaler: p.textScaler,
    )..layout();
    final fitsAlone = word.width <= p.size.width;
    word.dispose();
    if (!fitsAlone) continue;
    final tops = p
        .getBoxesForSelection(
          TextSelection(baseOffset: m.start, extentOffset: m.end),
        )
        .map((b) => b.top.round())
        .toSet();
    expect(tops, hasLength(1), reason: '„${m[0]}“ mitten im Wort geteilt');
  }
}

RenderParagraph _paragraph(WidgetTester t, Finder of) =>
    t.renderObject<RenderParagraph>(
      find.descendant(of: of, matching: find.byType(RichText)).first,
    );

void main() {
  // Große Schrift bis Faktor 2,0 auf 360 dp: Beschriftung und Wert brechen
  // nicht mitten im Wort, nichts läuft über, höchstens 4 Zeilen je Wert.
  final rows =
      <
        String,
        (String Function(AppLocalizations), String Function(AppLocalizations))
      >{
        'Trainingsbelastung': (
          (l) => l.sumTrimp,
          (l) => l.sumTrimpPartial('1234'),
        ),
        'Trainingsbelastung ohne Wert': (
          (l) => l.sumTrimp,
          (l) => l.statNoValue,
        ),
        'Bestpace ohne Wert': ((l) => l.sumBestPace, (l) => l.statNoValue),
      };
  for (final locale in ['de', 'en']) {
    for (final scale in [1.3, 1.86, 2.0]) {
      for (final MapEntry(key: name, value: (label, value)) in rows.entries) {
        testWidgets('$name $locale 360 dp x $scale: kein Überlauf, '
            'höchstens 4 Zeilen', (t) async {
          await _pump(
            t,
            locale: locale,
            width: 360,
            scale: scale,
            label: label,
            value: value,
            inCard: true,
          );
          expect(t.takeException(), isNull);
          final rowBox = t.getRect(find.byKey(const Key('row')));
          final labelP = _paragraph(t, find.byKey(const Key('row')));
          final valueP = _paragraph(t, find.byKey(const Key('row_value')));
          for (final p in [labelP, valueP]) {
            expect(p.didExceedMaxLines, isFalse);
            expect(p.size.width, lessThanOrEqualTo(rowBox.width + 0.5));
            _expectWholeWords(p);
          }
          expect(_lines(valueP), lessThanOrEqualTo(4));
          expect(_lines(labelP), lessThanOrEqualTo(4));
          for (final f in [
            find.byKey(const Key('row_value')),
            find
                .descendant(
                  of: find.byKey(const Key('row')),
                  matching: find.byType(Text),
                )
                .first,
          ]) {
            final r = t.getRect(f);
            expect(r.left, greaterThanOrEqualTo(rowBox.left - 0.5));
            expect(r.right, lessThanOrEqualTo(rowBox.right + 0.5));
          }
        });
      }
    }
  }

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

  testWidgets('einzelnes zu langes Wort bricht um statt überzulaufen', (
    t,
  ) async {
    // So schmal, dass „Trainingsbelastung“ bei Faktor 2,0 allein nicht in
    // eine Zeile passt.
    await _pump(
      t,
      locale: 'de',
      width: 260,
      scale: 2.0,
      label: (l) => l.sumTrimp,
      value: (l) => l.sumTrimpValue('12'),
      inCard: true,
    );
    expect(t.takeException(), isNull);
    final rowBox = t.getRect(find.byKey(const Key('row')));
    final labelP = _paragraph(t, find.byKey(const Key('row')));
    expect(_lines(labelP), 2, reason: 'das Wort bricht um');
    expect(labelP.size.width, lessThanOrEqualTo(rowBox.width + 0.5));
    // Der Wert steht unter der Beschriftung und behält seine Wörter.
    final valueP = _paragraph(t, find.byKey(const Key('row_value')));
    _expectWholeWords(valueP);
    final label = t.getRect(
      find
          .descendant(
            of: find.byKey(const Key('row')),
            matching: find.byType(Text),
          )
          .first,
    );
    expect(
      t.getRect(find.byKey(const Key('row_value'))).top,
      greaterThanOrEqualTo(label.bottom - 0.5),
    );
  });

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
