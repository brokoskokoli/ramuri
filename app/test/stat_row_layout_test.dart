import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/statistics/statistics_view.dart';

import 'history_summary_test.dart' show seedRun, started;
import 'statistics_test.dart' show calc, choose, openStats;

/// Zeilen der Kennzahlen mit der echten Schrift (WP15 Nachbesserung 5):
/// Weder Label noch Wert bricht mitten im Wort; passt beides nicht
/// nebeneinander, stehen sie untereinander.

const _profile = ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60);

Future<void> _loadManrope() async {
  final loader = FontLoader('Manrope');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/Manrope-$w.ttf').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

double _longestWord(RenderParagraph p) {
  var max = 0.0;
  for (final w in p.text.toPlainText().split(RegExp(r'\s+'))) {
    final tp = TextPainter(
      text: TextSpan(text: w, style: p.text.style),
      textDirection: TextDirection.ltr,
      textScaler: p.textScaler,
    )..layout();
    if (tp.width > max) max = tp.width;
  }
  return max;
}

/// Prüft alle Zeilen; liefert die Zahl der untereinander stehenden.
int _check(WidgetTester t, String tag, {required bool sideBySide}) {
  final rows = find.byType(StatRow).evaluate().toList();
  expect(rows, isNotEmpty, reason: tag);
  var stacked = 0;
  for (final e in rows) {
    final row = find.byWidget(e.widget);
    final texts = find.descendant(of: row, matching: find.byType(RichText));
    final rowWidth = t.getSize(row).width;
    for (final p in t.renderObjectList<RenderParagraph>(texts)) {
      // Ein Wort, das schon allein breiter als die Zeile ist (etwa
      // „Trainingsbelastung“ bei 320 dp und doppelter Schrift), lässt sich
      // durch keine Anordnung retten.
      if (_longestWord(p) > rowWidth) continue;
      expect(
        _longestWord(p),
        lessThanOrEqualTo(p.size.width + 0.5),
        reason:
            '$tag ${(e.widget as StatRow).id}: Wort gebrochen in '
            '"${p.text.toPlainText()}"',
      );
    }
    final id = (e.widget as StatRow).id;
    final value = t.getRect(find.byKey(Key('${id}_value')));
    final label = t.getRect(
      find.descendant(of: row, matching: find.byType(Text)).first,
    );
    if (value.top >= label.bottom - 0.5) {
      stacked++;
      // Lange Ersatztexte („nicht verfügbar (…)“, Sätze) stehen untereinander,
      // sobald sie neben dem Label mehr als 2 Zeilen bräuchten (WP18, M1
      // Fehler 1), auch wenn sonst alles nebeneinander passt.
      final text = t.widget<Text>(find.byKey(Key('${id}_value'))).data ?? '';
      final placeholder = text.length > 30;
      expect(
        sideBySide && !placeholder,
        isFalse,
        reason: '$tag $id steht untereinander',
      );
    } else {
      expect(value.left, greaterThanOrEqualTo(label.right), reason: '$tag $id');
    }
  }
  return stacked;
}

void main() {
  for (final locale in ['de', 'en']) {
    for (final (w, s) in [(390.0, 1.0), (320.0, 1.0), (320.0, 2.0)]) {
      testWidgets('Zeilen $locale $w x $s: kein Wortbruch', (t) async {
        await _loadManrope();
        final d = await started(t, locale: locale);
        t.view.physicalSize = Size(w, 9000);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = s;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        d.clock.set(DateTime.utc(2026, 6, 4, 12));
        await d.session.profile.save(_profile);
        for (final day in [1, 2, 3]) {
          final id = await seedRun(
            d.session,
            DateTime.utc(2026, 6, day, 8),
            minutes: 30,
          );
          await calc(d, id);
        }
        await openStats(d, t);
        final big = w < 390;
        var stacked = _check(t, '$locale $w/$s Woche', sideBySide: !big);
        await choose(t, 'run');
        stacked += _check(t, '$locale $w/$s Lauf', sideBySide: !big);
        expect(t.takeException(), isNull);
        if (w == 320 && s == 2) {
          expect(stacked, greaterThan(0), reason: 'Stapelung wird geprüft');
        }
      });
    }
  }
}
