// WP17 B2: Auf Lauf-Seiten (Live, Verlauf, Detail/Zusammenfassung) bleibt die
// Einheit bei der Zahl: eine Zeile, kein Umbruch zwischen Zahl und Einheit,
// kein Bruch in der Einheit. Echte Schrift, 360 dp, Faktor 1,0 / 1,15 / 1,3.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show key, seedRun, showAllRuns;

/// Einheitswort: nach dem Entfernen der Wortverbinder genau eine Einheit.
final _unitWord = RegExp(r'^(km|mi|m|ft|min/km|min/mi|bpm|spm|Punkte|points)$');

/// Werte in schmalen Kacheln: Reicht die Spalte für Zahl und Einheit nicht
/// (Design: drei Spalten auf 360 dp), steht die Einheit als Ganzes unter der
/// Zahl. Nur diese Schlüssel dürfen so stehen (Befund im Bericht).
const _tileKeys = {
  'run_pace',
  'run_avg_pace',
  'run_ascent',
  'run_descent',
  'sum_best_pace',
  'sum_avg_hr',
  'sum_max_hr',
  'sum_trimp',
};

/// Prüft alle Texte auf dem Bildschirm: Kein Wort (auch keine Zahl, keine
/// Einheit wie „min/km“) bricht mitten im Wort, und Zahl und Einheit stehen in
/// einer Zeile, außer in den Kacheln aus [_tileKeys]. Liefert die Zahl der
/// geprüften Einheiten.
int expectUnitsStay(WidgetTester tester, String where) {
  var checked = 0;
  // Die Sprachausgabe liest den Wortverbinder nicht: nie in einem Label.
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    for (final t in [data.label, data.value, data.hint]) {
      expect(
        t.contains('\u2060') || t.contains('\u00A0'),
        isFalse,
        reason: '$where: Label "$t"',
      );
    }
    node.visitChildren((c) {
      visit(c);
      return true;
    });
  }

  // ignore: deprecated_member_use
  visit(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode!);
  for (final e in find.byType(RichText).evaluate()) {
    final p = e.renderObject;
    if (p is! RenderParagraph) continue;
    final plain = p.text.toPlainText(includeSemanticsLabels: false);
    // Wörter: getrennt an gewöhnlichen Leerzeichen (nicht am geschützten).
    final words = RegExp(r'[^ \n]+').allMatches(plain);
    final lineOfWord = <int>[];
    var line = 0;
    double? lastLeft;
    final spans = <(int, String)>[];
    for (final w in words) {
      final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: w.start, extentOffset: w.end),
      );
      if (boxes.isEmpty) continue;
      // Geprüft werden Zahlen und Einheiten, nicht Beschriftungen („Bewegungs-
      // zeit“ bricht bei Faktor 1,3 in der halben Live-Kachel; kein Befund
      // dieses Pakets, im Bericht genannt).
      final bare = w.group(0)!.replaceAll('\u2060', '');
      final relevant = RegExp(r'\d').hasMatch(bare) || _unitWord.hasMatch(bare);
      // Ein Wort in einer Zeile: die Kästen laufen von links nach rechts.
      double? left;
      for (final b in boxes) {
        expect(
          !relevant || left == null || b.left >= left - 0.5,
          isTrue,
          reason: '$where: "${w.group(0)}" in "$plain" bricht im Wort',
        );
        left = b.right;
      }
      if (lastLeft != null && boxes.first.left < lastLeft - 0.5) line++;
      lastLeft = boxes.last.right;
      lineOfWord.add(line);
      spans.add((lineOfWord.length - 1, w.group(0)!.replaceAll('\u2060', '')));
    }
    for (var k = 1; k < spans.length; k++) {
      if (!_unitWord.hasMatch(spans[k].$2)) continue;
      if (!RegExp(r'\d$').hasMatch(spans[k - 1].$2)) continue;
      checked++;
      if (lineOfWord[k] == lineOfWord[k - 1]) continue;
      final key = _keyOf(tester, e);
      expect(
        _tileKeys,
        contains(key),
        reason: '$where: "$plain" trennt Zahl und Einheit (key=$key)',
      );
    }
    expect(p.size.width, lessThanOrEqualTo(360), reason: '$where: "$plain"');
  }
  return checked;
}

/// Schlüssel des Text-Widgets über dem Absatz.
String? _keyOf(WidgetTester tester, Element richText) {
  String? found;
  richText.visitAncestorElements((a) {
    final k = a.widget.key;
    if (a.widget is Text && k is ValueKey<String>) {
      found = k.value;
      return false;
    }
    return a.widget is! Text;
  });
  return found;
}

Future<void> checkScrolled(WidgetTester tester, String where) async {
  final scrollable = find.byType(Scrollable);
  var seen = expectUnitsStay(tester, where);
  if (scrollable.evaluate().isEmpty) return;
  for (var i = 0; i < 6; i++) {
    await tester.drag(scrollable.first, const Offset(0, -300));
    await tester.pump();
    seen += expectUnitsStay(tester, '$where (gescrollt $i)');
  }
  expect(seen, greaterThan(0), reason: where);
}

void main() {
  for (final lang in ['de', 'en']) {
    for (final miles in [false, true]) {
      for (final scale in [1.0, 1.15, 1.3]) {
        testWidgets('Einheit bleibt bei der Zahl: $lang, '
            '${miles ? 'Meilen' : 'km'}, Faktor $scale', (tester) async {
          await loadManrope(tester);
          await loadSora(tester);
          final semantics = tester.ensureSemantics();
          final cadence = FakeCadenceSensor();
          final d = Device()..cadence = cadence;
          d.clock.set(DateTime.utc(2026, 6, 17, 12));
          final s = await d.storage.open(
            Uint8List.fromList(List.filled(32, 7)),
          );
          await s.settings.set(
            SettingKeys.setupDone,
            '1',
            at: DateTime.utc(2026),
          );
          if (miles) {
            await s.settings.set(
              SettingKeys.distanceUnit,
              DistanceUnit.miles.storageValue,
              at: DateTime.utc(2026),
            );
          }
          // Profil vor dem Verlaufslauf: Puls und TRIMP (Belastung) sind da.
          await s.profile.save(
            const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
          );
          // Langsamer Lauf: breiteste Pace (rund 15 min/km), mehrere km.
          final id = await seedRun(
            s,
            DateTime.utc(2026, 6, 16, 8),
            minutes: 240,
            speed: 1.1,
          );
          await d.start(tester, Locale(lang));
          tester.view.physicalSize = const Size(360, 640);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpAndSettle();

          // Verlauf.
          await tester.tap(key('home_history'));
          await tester.pumpAndSettle();
          await showAllRuns(tester);
          await checkScrolled(tester, 'Verlauf');
          // Detail.
          await tester.tap(key('history_distance_$id'));
          await tester.pumpAndSettle();
          await checkScrolled(tester, 'Detail');
          expect(tester.takeException(), isNull);

          // Live: langsam (rund 15 min/km), 1200 m Anstieg, dann 1200 m
          // Gefälle, Puls 187 über die ganze Zeit (TRIMP), 180 spm.
          Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
          await tester.pumpAndSettle();
          await tester.tap(key('home_today'));
          await tester.pumpAndSettle();
          await d.session.profile.save(
            const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
          );
          await tester.tap(key('home_start_run'));
          await tester.pumpAndSettle();
          await tester.tap(key('run_start_ready'));
          await tester.pumpAndSettle();
          for (var i = 0; i < 80; i++) {
            d.clock.advance(const Duration(seconds: 10));
            d.location.emit(
              LocationSample(
                time: d.clock.now(),
                latitude: 50 + i * 0.0001,
                longitude: 8,
                accuracyMeters: 5,
                altitudeMeters: i < 60
                    ? 100 + i * 20.0
                    : 1300 - (i - 59) * 60.0,
                verticalAccuracyMeters: 3,
              ),
            );
            d.heartRate.emitReading('hr1', d.clock.now(), 187);
            cadence.emit(d.clock.now(), 180);
            await tester.pump(const Duration(seconds: 1));
          }
          await checkScrolled(tester, 'Live Werte');
          await tester.tap(key('run_tab_1'));
          await tester.pumpAndSettle();
          expect(expectUnitsStay(tester, 'Live Karte'), greaterThan(0));
          await tester.tap(key('run_tab_0'));
          await tester.pumpAndSettle();
          // Zusammenfassung nach dem Beenden.
          await tester.tap(key('run_pause'));
          await tester.pump();
          await tester.tap(key('run_finish'));
          await tester.pumpAndSettle();
          await tester.tap(key('run_finish_confirm'));
          await tester.pumpAndSettle();
          await checkScrolled(tester, 'Zusammenfassung');
          expect(tester.takeException(), isNull);
          semantics.dispose();
        });
      }
    }
  }

  // Im Fließtext (Sätze mit Pace, Puls, Länge) steht die Einheit bei der
  // Zahl, bei jeder Breite: „150“ und „bpm“ nie auf zwei Zeilen.
  testWidgets('unitTogether: Satz bricht nie zwischen Zahl und Einheit', (
    tester,
  ) async {
    await loadManrope(tester);
    for (final (before, value, unit, after) in [
      ('Ø Puls ', '150 bpm', 'bpm', ''),
      ('', '0:05 min/km', 'min/km', ' langsamer als der letzte Lauf'),
      ('angebrochen: ', '0,84 km', 'km', ''),
    ]) {
      final sentence = '$before$value$after';
      final number = value.split(' ').first;
      final text = '$before${unitTogether(value, unit)}$after';
      expect(spokenUnit(text), sentence, reason: 'Sprachausgabe unverändert');
      // Schmaler als Zahl samt Einheit geht es nicht ohne Zeichenbruch.
      final chunk = text.substring(text.indexOf(number));
      final chunkWidth = (TextPainter(
        text: TextSpan(
          text: RegExp(r'^[^ ]+').firstMatch(chunk)!.group(0),
          style: const TextStyle(fontFamily: 'Manrope', fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).width;
      for (var w = chunkWidth.ceilToDouble(); w <= 300; w += 1) {
        final p = TextPainter(
          text: TextSpan(
            text: text,
            style: const TextStyle(fontFamily: 'Manrope', fontSize: 14),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: w);
        final at = text.indexOf(number);
        final line = p.getLineBoundary(TextPosition(offset: at));
        final unitAt = text.indexOf(unit.replaceAll('/', '\u2060/\u2060'), at);
        expect(
          unitAt >= line.start && unitAt + 1 <= line.end,
          isTrue,
          reason: '"$text" bei Breite $w: Einheit nicht bei der Zahl',
        );
        p.dispose();
      }
    }
  });
}
