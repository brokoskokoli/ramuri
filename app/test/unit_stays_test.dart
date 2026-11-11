// WP17 B2: Auf Lauf-Seiten (Live, Verlauf, Detail/Zusammenfassung) bleibt die
// Einheit bei der Zahl: eine Zeile, kein Umbruch zwischen Zahl und Einheit,
// kein Bruch in der Einheit. Echte Schrift, 360 dp, Faktor 1,0 / 1,15 / 1,3.

import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/run/live_run_values.dart';
import 'package:running_app/ui/ui.dart';

import 'app_harness.dart';
import 'history_summary_test.dart' show seedRun, showAllRuns;

/// Einheitswort: nach dem Entfernen der Wortverbinder genau eine Einheit.
final _unitWord = RegExp(r'^(km|mi|m|ft|min/km|min/mi|bpm|spm|Punkte|points)$');

/// Eine Zahl als ganzes Wort („5:33“, „0,84“, „+1200“); „Z5“ ist keine.
final _number = RegExp(r'^[+\-−]?[\d.,:]*\d$');

/// Pace, Puls und Punkte: Die Einheit steht in der Beschriftung, die Zahl
/// bleibt groß und ohne Einheit (WP17 B3). Ein Wert ist hier nie samt Einheit
/// in der Kachel (das Schrumpfen wäre sonst nur versteckt).
const _unitInLabelKeys = {
  'run_pace',
  'run_avg_pace',
  'sum_best_pace',
  'sum_avg_hr',
  'sum_max_hr',
  'sum_trimp',
  // Kartenseite: Blatt unter der Karte.
  'live_map_pace',
  'live_map_avg_pace',
  'live_map_hr',
};
final _seenUnitInLabel = <String>{};
final _labelChecked = <String>{};

/// Einheit der Beschriftung je Schlüssel.
String _unitOfKey(String k, {required bool miles, required String lang}) =>
    switch (k) {
      'sum_avg_hr' || 'sum_max_hr' || 'live_map_hr' => 'bpm',
      'sum_trimp' => lang == 'de' ? 'Punkte' : 'points',
      _ => miles ? 'min/mi' : 'min/km',
    };

/// Die Sprachausgabe (Semantics-Label) nennt die Einheit genau einmal, wenn
/// eine Zahl da ist, und gar nicht, wenn ein Ersatztext („noch keine Daten“,
/// „nicht verfügbar“) dasteht. Nie die Einheit des anderen Maßes.
void expectUnitInLabels(
  WidgetTester tester,
  String where, {
  required bool miles,
  required String lang,
}) {
  for (final k in _unitInLabelKeys) {
    final finder = find.byKey(Key(k));
    if (finder.evaluate().isEmpty) continue;
    final w = tester.widget<Text>(finder.first);
    final plain =
        (w.data ?? w.textSpan!.toPlainText(includeSemanticsLabels: false))
            .replaceAll('\u2060', '')
            .replaceAll('\u00A0', ' ');
    final isNumber = _number.hasMatch(plain);
    final unit = _unitOfKey(k, miles: miles, lang: lang);
    final label = tester.getSemantics(finder.first).label;
    final count = RegExp('(?<![\\w/])${RegExp.escape(unit)}(?![\\w/])')
        .allMatches(label)
        .length;
    expect(
      count,
      isNumber ? 1 : 0,
      reason: '$where: $k (Wert "$plain") nennt "$unit" im Label "$label"',
    );
    for (final other in ['min/km', 'min/mi', 'bpm', 'Punkte', 'points']) {
      if (other == unit) continue;
      expect(
        label.contains(other),
        isFalse,
        reason: '$where: $k nennt fremde Einheit "$other": "$label"',
      );
    }
    _labelChecked.add(k);
  }
}

/// Prüft alle Texte auf dem Bildschirm: Kein Wort (auch keine Beschriftung,
/// keine Zahl, keine Einheit wie „min/km“) bricht mitten im Wort, und Zahl und
/// Einheit stehen in einer Zeile; sonst steht die Einheit in der Beschriftung
/// (dann folgt keine Zahl mit Einheit im selben Text). Liefert die Zahl der
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
    // Ein Text wird nie gekürzt (Beschriftung zweizeilig, Zahl schrumpft).
    expect(
      p.didExceedMaxLines,
      isFalse,
      reason: '$where: "$plain" ist abgeschnitten (maxLines)',
    );
    final ownKey = _keyOf(tester, e);
    if (_unitInLabelKeys.contains(ownKey)) {
      _seenUnitInLabel.add(ownKey!);
      // Zahl mit Einheit dahinter (nicht der Satz „kein km am Stück“).
      final words = plain.replaceAll('\u2060', '').split(RegExp(r'[ \u00A0]'));
      expect(
        words.length > 1 &&
            _unitWord.hasMatch(words.last) &&
            _number.hasMatch(words[words.length - 2]),
        isFalse,
        reason: '$where: "$plain" ($ownKey) trägt die Einheit im Wert',
      );
    }
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
      // Geprüft wird jedes Wort: auch Beschriftungen („Bewegungszeit“).
      // Ein Wort in einer Zeile: die Kästen laufen von links nach rechts.
      double? left;
      for (final b in boxes) {
        expect(
          left == null || b.left >= left - 0.5,
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
      if (!_number.hasMatch(spans[k - 1].$2)) continue;
      checked++;
      expect(
        lineOfWord[k],
        lineOfWord[k - 1],
        reason:
            '$where: "$plain" trennt Zahl und Einheit '
            '(key=${_keyOf(tester, e)})',
      );
    }
    expect(p.size.width, lessThanOrEqualTo(360), reason: '$where: "$plain"');
  }
  return checked;
}

/// Alle Zeichen des Absatzes laufen in einer Zeile von links nach rechts.
bool _oneLine(RenderParagraph p) {
  final boxes = p.getBoxesForSelection(
    TextSelection(
      baseOffset: 0,
      extentOffset: p.text.toPlainText(includeSemanticsLabels: false).length,
    ),
  );
  for (var i = 1; i < boxes.length; i++) {
    if (boxes[i].left < boxes[i - 1].right - 0.5) return false;
  }
  return true;
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

Future<void> checkScrolled(
  WidgetTester tester,
  String where, {
  required bool miles,
  required String lang,
}) async {
  final scrollable = find.byType(Scrollable);
  var seen = expectUnitsStay(tester, where);
  expectUnitInLabels(tester, where, miles: miles, lang: lang);
  if (scrollable.evaluate().isEmpty) return;
  for (var i = 0; i < 6; i++) {
    await tester.drag(scrollable.first, const Offset(0, -300));
    await tester.pump();
    seen += expectUnitsStay(tester, '$where (gescrollt $i)');
    expectUnitInLabels(
      tester,
      '$where (gescrollt $i)',
      miles: miles,
      lang: lang,
    );
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
          _seenUnitInLabel.clear();
          _labelChecked.clear();
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
          await checkScrolled(tester, 'Verlauf', miles: miles, lang: lang);
          // Detail.
          await tester.tap(key('history_distance_$id'));
          await tester.pumpAndSettle();
          await checkScrolled(tester, 'Detail', miles: miles, lang: lang);
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
          await checkScrolled(tester, 'Live Werte', miles: miles, lang: lang);
          await tester.tap(key('run_tab_1'));
          await tester.pumpAndSettle();
          expect(expectUnitsStay(tester, 'Live Karte'), greaterThan(0));
          expectUnitInLabels(tester, 'Live Karte', miles: miles, lang: lang);
          // Die Zahlen der Reihe stehen auf einer Höhe (unten ausgerichtet).
          final bottoms = [
            for (final k in [
              'live_map_pace',
              'live_map_avg_pace',
              'live_map_hr',
            ])
              tester.getRect(key(k)).bottom,
          ];
          expect(bottoms[1], closeTo(bottoms[0], 0.5), reason: 'Karte: Pace');
          expect(bottoms[2], closeTo(bottoms[0], 0.5), reason: 'Karte: Puls');
          await tester.tap(key('run_tab_0'));
          await tester.pumpAndSettle();
          // Zusammenfassung nach dem Beenden.
          await tester.tap(key('run_pause'));
          await tester.pump();
          await tester.tap(key('run_finish'));
          await tester.pumpAndSettle();
          await tester.tap(key('run_finish_confirm'));
          await tester.pumpAndSettle();
          await checkScrolled(
            tester,
            'Zusammenfassung',
            miles: miles,
            lang: lang,
          );
          expect(tester.takeException(), isNull);
          expect(
            _seenUnitInLabel,
            _unitInLabelKeys,
            reason: 'alle Werte mit Einheit in der Beschriftung gesehen',
          );
          expect(
            _labelChecked,
            _unitInLabelKeys,
            reason: 'Sprachausgabe aller Werte mit Einheit in der Beschriftung',
          );
          semantics.dispose();
        });
      }
    }
  }

  Widget app(Widget body, {double scale = 1.0}) => localizedApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(body: Center(child: body)),
    ),
  );

  // Keine Sprünge während des Laufs: Ob zwei Kacheln nebeneinander oder
  // untereinander stehen, hängt von der breitesten Form der Zahl ab (Pace
  // 88:88, Zeit 8:88:88), nicht vom aktuellen Wert. Die Pace wechselt hier
  // über 10:00 hin und her; die Zahlen einer Reihe stehen unten auf einer Höhe.
  for (final lang in ['de', 'en']) {
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('Live: Anordnung bleibt bei jedem Wert gleich: $lang, '
          'Faktor $scale', (tester) async {
        await loadManrope(tester);
        await loadSora(tester);
        final semantics = tester.ensureSemantics();
        final d = Device();
        await d.start(tester, Locale(lang));
        await d.skipSetup(tester);
        await d.session.profile.save(
          const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
        );
        await tester.tap(key('home_start_run'));
        await tester.pumpAndSettle();
        await tester.tap(key('run_start_ready'));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(360, 640);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();

        var lat = 50.0;
        var i = 0;
        Future<void> leg(
          int steps,
          int stepSeconds,
          double metersPerSecond,
        ) async {
          for (var n = 0; n < steps; n++) {
            d.clock.advance(Duration(seconds: stepSeconds));
            lat += metersPerSecond * stepSeconds / 111195;
            d.location.emit(
              LocationSample(
                time: d.clock.now(),
                latitude: lat,
                longitude: 8,
                accuracyMeters: 5,
                altitudeMeters: 100 + i++ * 0.5,
                verticalAccuracyMeters: 3,
              ),
            );
            await tester.pump(const Duration(seconds: 1));
          }
        }

        String shown(String k) =>
            (tester.widget<Text>(find.byKey(Key(k))).data ??
            tester.widget<Text>(find.byKey(Key(k))).textSpan!.toPlainText());
        // Breite der Karte je Wert: halbe oder ganze Breite.
        double cardWidth(String k) => tester
            .getSize(
              find
                  .ancestor(
                    of: find.byKey(Key(k)),
                    matching: find.byType(RamuriCard),
                  )
                  .first,
            )
            .width;
        const keys = [
          'run_pace',
          'run_avg_pace',
          'run_moving_time',
          'run_ascent',
          'run_cadence',
        ];
        final layouts = <String, List<double>>{};
        void record(String state, RegExp pace) {
          expect(shown('run_pace'), matches(pace), reason: state);
          layouts[state] = [for (final k in keys) cardWidth(k)];
          // Nebeneinander: die Zahlen stehen unten auf einer Höhe.
          for (final (a, b) in [
            ('run_pace', 'run_avg_pace'),
            ('run_moving_time', 'run_ascent'),
          ]) {
            if (tester.getTopLeft(key(b)).dx > tester.getTopLeft(key(a)).dx) {
              expect(
                tester.getRect(key(b)).bottom,
                closeTo(tester.getRect(key(a)).bottom, 0.5),
                reason: '$state: $a und $b auf einer Höhe',
              );
            }
          }
          expectUnitInLabels(tester, state, miles: false, lang: lang);
        }

        record('noch keine Daten', RegExp(r'^(noch keine Daten|no data yet)$'));
        await leg(60, 1, 3.0);
        record('5:33', RegExp(r'^5:\d\d$'));
        await leg(90, 1, 1.3);
        record('12:29', RegExp(r'^1[1-4]:\d\d$'));
        await leg(60, 1, 3.0);
        record('wieder 5:33', RegExp(r'^5:\d\d$'));
        // Über eine Stunde Bewegungszeit.
        await leg(40, 100, 3.0);
        expect(shown('run_moving_time'), matches(RegExp(r'^\d:\d\d:\d\d$')));
        layouts['Stunden'] = [for (final k in keys) cardWidth(k)];
        for (final entry in layouts.entries) {
          expect(
            entry.value,
            layouts.values.first,
            reason:
                'Faktor $scale: Anordnung bei "${entry.key}" '
                'anders als bei "noch keine Daten"',
          );
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }

  // Gleiche Höhe im Raster: Eine zweizeilige Beschriftung schiebt die Zahl
  // nicht nach oben.
  testWidgets('Raster: Zahlen einer Reihe stehen auf einer Höhe', (
    tester,
  ) async {
    await loadManrope(tester);
    await loadSora(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      app(
        const SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: RamuriTileGrid(
            children: [
              RamuriValueTile(
                label: 'Ø Pace',
                value: '5:40',
                labelUnit: 'min/km',
                valueKey: Key('a'),
              ),
              RamuriValueTile(
                label: 'Anstieg',
                value: '+12',
                unit: 'm',
                valueKey: Key('b'),
              ),
              RamuriValueTile(label: 'Max', value: '187', valueKey: Key('c')),
            ],
          ),
        ),
      ),
    );
    // Die erste Beschriftung ist zweizeilig, die anderen einzeilig.
    final label = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().startsWith('Ø Pace'));
    expect(label.size.height, greaterThan(18), reason: 'zweizeilig');
    final bottoms = [
      for (final k in ['a', 'b', 'c'])
        tester.getRect(find.byKey(Key(k))).bottom,
    ];
    expect(bottoms[1], closeTo(bottoms[0], 0.5));
    expect(bottoms[2], closeTo(bottoms[0], 0.5));
  });

  // Schrumpft „+1200 m“ in der Kachel, wird die Reihe nicht höher (keine
  // Scheinzeile vom umgebrochenen Text unter der FittedBox).
  for (final scale in [1.0]) {
    testWidgets('Raster: schrumpfende Zahl macht die Reihe nicht höher '
        '(Faktor $scale)', (tester) async {
      await loadManrope(tester);
      await loadSora(tester);
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      Future<double> height(String value) async {
        await tester.pumpWidget(
          app(
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: RamuriTileGrid(
                children: [
                  RamuriValueTile(
                    label: 'Anstieg',
                    value: value,
                    unit: 'm',
                    valueKey: const Key('v'),
                  ),
                  const RamuriValueTile(label: 'Max', value: '187'),
                  const RamuriValueTile(label: 'Min', value: '90'),
                ],
              ),
            ),
            scale: scale,
          ),
        );
        return tester.getSize(find.byType(RamuriTileGrid)).height;
      }

      final normal = await height('+12');
      final shrunk = await height('+1200');
      expect(
        tester.getRect(find.byKey(const Key('v'))).width,
        lessThan(
          tester
              .renderObject<RenderParagraph>(find.byKey(const Key('v')))
              .size
              .width,
        ),
        reason: 'die Zahl ist hier tatsächlich geschrumpft',
      );
      expect(shrunk, closeTo(normal, 0.5));
    });
  }

  // Anstieg und Gefälle: „+1200 m“ bleibt zusammen und schrumpft nur, wenn
  // es nicht in die Kachel passt.
  for (final live in [true, false]) {
    testWidgets('Zahl mit Einheit schrumpft nur bei Platzmangel '
        '(${live ? 'LiveValueText' : 'RamuriValueTile'})', (tester) async {
      await loadManrope(tester);
      await loadSora(tester);
      Widget value(double width) => SizedBox(
        width: width,
        child: live
            ? Builder(
                builder: (context) => LiveValueText(
                  id: 'v',
                  value: '+1200',
                  unit: 'm',
                  shrink: true,
                  valueStyle: RamuriType.of(context).valueSmall,
                  unitStyle: RamuriType.of(context).unit,
                ),
              )
            : const RamuriValueTile(
                label: 'Anstieg',
                value: '+1200',
                unit: 'm',
                valueKey: Key('v'),
              ),
      );
      Future<(double, double)> measure(double width, double scale) async {
        await tester.pumpWidget(app(value(width), scale: scale));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.byKey(const Key('v')),
        );
        final box = tester.getRect(find.byKey(const Key('v')));
        expect(_oneLine(paragraph), isTrue, reason: 'eine Zeile');
        return (box.width, paragraph.size.width);
      }

      // Genug Platz: unverändert groß (Schrift wirkt mit dem Faktor weiter).
      final (shownWide, naturalWide) = await measure(300, 1.0);
      expect(shownWide, naturalWide);
      final (shownScaled, naturalScaled) = await measure(300, 1.3);
      expect(naturalScaled, greaterThan(naturalWide));
      expect(shownScaled, naturalScaled);
      // Zu wenig Platz: eine Zeile, kleiner dargestellt als gesetzt.
      final (shownNarrow, naturalNarrow) = await measure(60, 1.0);
      expect(naturalNarrow, greaterThan(60));
      expect(shownNarrow, lessThanOrEqualTo(60));
    });
  }

  // Wertkacheln im Raster: Ein langes Wort der Beschriftung zwingt zu weniger
  // Spalten, statt mitten im Wort zu brechen.
  testWidgets('Raster: Wort der Beschriftung bricht nicht im Wort', (
    tester,
  ) async {
    await loadManrope(tester);
    await loadSora(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const label = 'Durchschnittspuls';
    await tester.pumpWidget(
      app(
        const SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: RamuriTileGrid(
            children: [
              RamuriValueTile(label: label, value: '150', labelUnit: 'bpm'),
              RamuriValueTile(label: 'Ø Pace', value: '5:40'),
              RamuriValueTile(label: 'Max', value: '187'),
            ],
          ),
        ),
      ),
    );
    final paragraph = tester
        .renderObjectList<RenderParagraph>(find.byType(RichText))
        .firstWhere((p) => p.text.toPlainText().startsWith(label));
    // Das Wort steht ganz in einer Zeile: Kein Kasten springt zurück.
    final boxes = paragraph.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: label.length),
    );
    for (var i = 1; i < boxes.length; i++) {
      expect(boxes[i].left, greaterThanOrEqualTo(boxes[i - 1].right - 0.5));
    }
    expect(paragraph.size.width, lessThanOrEqualTo(360));
  });

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

  // Ø Pace ab 100 min/km (langsame Proben am Start): Die Zahl schrumpft in
  // einer Zeile, statt mitten in der Zahl zu brechen. Messung mit der
  // breitesten Form „88:88“ reicht dafür nicht.
  for (final lang in ['de', 'en']) {
    for (final (width, scale) in [(360.0, 1.15), (411.0, 1.3)]) {
      testWidgets('Live: dreistellige Ø Pace bricht nicht in der Zahl: '
          '$lang, ${width.round()} dp, Faktor $scale', (tester) async {
        await loadManrope(tester);
        await loadSora(tester);
        final d = Device();
        await d.start(tester, Locale(lang));
        await d.skipSetup(tester);
        await tester.tap(key('home_start_run'));
        await tester.pumpAndSettle();
        await tester.tap(key('run_start_ready'));
        await tester.pumpAndSettle();
        tester.view.physicalSize = Size(width, 640);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();

        var lat = 50.0;
        String? avg;
        for (var n = 0; n < 60; n++) {
          d.clock.advance(const Duration(seconds: 1));
          lat += 0.1 / 111195; // 0,1 m/s: 166:40 min/km
          d.location.emit(
            LocationSample(
              time: d.clock.now(),
              latitude: lat,
              longitude: 8,
              accuracyMeters: 5,
              altitudeMeters: 100,
              verticalAccuracyMeters: 3,
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          final t = tester.widget<Text>(find.byKey(const Key('run_avg_pace')));
          avg = t.textSpan?.toPlainText() ?? t.data;
          if (RegExp(r'^\d{3}:\d\d').hasMatch(avg ?? '')) break;
        }
        expect(avg, matches(RegExp(r'^\d{3}:\d\d')), reason: 'dreistellig');
        final p = tester.renderObject<RenderParagraph>(
          find.byKey(const Key('run_avg_pace')),
        );
        expect(_oneLine(p), isTrue, reason: 'Zahl "$avg" in einer Zeile');
        expect(tester.takeException(), isNull);
      });
    }
  }

  // Kartenseite: Der Ersatztext „noch keine Daten“ steht klein, aber lesbar
  // (mindestens 12 dp wirksam), darf umbrechen (de: drei Zeilen) und wird nicht
  // auf die Kachelbreite geschrumpft; das Blatt läuft nicht über.
  for (final lang in ['de', 'en']) {
    for (final scale in [1.0, 1.15, 1.3]) {
      testWidgets('Karte: Ersatztext bleibt lesbar: $lang, Faktor $scale', (
        tester,
      ) async {
        await loadManrope(tester);
        await loadSora(tester);
        final d = Device();
        await d.start(tester, Locale(lang));
        await d.skipSetup(tester);
        await tester.tap(key('home_start_run'));
        await tester.pumpAndSettle();
        await tester.tap(key('run_start_ready'));
        await tester.pumpAndSettle();
        tester.view.physicalSize = const Size(360, 640);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpAndSettle();
        await tester.tap(key('run_tab_1'));
        await tester.pumpAndSettle();
        for (final k in ['live_map_pace', 'live_map_avg_pace']) {
          final p = tester.renderObject<RenderParagraph>(find.byKey(Key(k)));
          expect(
            p.text.toPlainText(),
            matches(RegExp(r'noch keine Daten|no data yet')),
          );
          expect(
            find.ancestor(
              of: find.byKey(Key(k)),
              matching: find.byType(FittedBox),
            ),
            findsNothing,
            reason: '$k: nicht auf die Breite geschrumpft',
          );
          final size = p.textScaler.scale(p.text.style!.fontSize!);
          expect(
            size,
            greaterThanOrEqualTo(12),
            reason: '$k: wirksame Schrift',
          );
          expect(
            p.didExceedMaxLines,
            isFalse,
            reason: '$k: nichts abgeschnitten',
          );
          expect(
            p.size.height,
            lessThanOrEqualTo(size * 1.5 * 3),
            reason: '$k: höchstens drei Zeilen',
          );
        }
        expectUnitInLabels(tester, 'Karte leer', miles: false, lang: lang);
        expect(
          tester.takeException(),
          isNull,
          reason: 'kein Überlauf im Blatt',
        );
      });
    }
  }

  // Live-Reihe: Schrumpft „+1200 m“, bleibt die Reihe so hoch wie ohne
  // Schrumpfen (keine Scheinzeile vom umgebrochenen Text unter der FittedBox).
  testWidgets('Live: schrumpfende Zahl macht die Reihe nicht höher', (
    tester,
  ) async {
    await loadManrope(tester);
    await loadSora(tester);
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<double> rowHeight(double width) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => SizedBox(
              width: width,
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: LiveValueText(
                        id: 'v',
                        value: '+1200',
                        unit: 'm',
                        shrink: true,
                        valueStyle: RamuriType.of(context).valueSmall,
                        unitStyle: RamuriType.of(context).unit,
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
          ),
          scale: 1.3,
        ),
      );
      return tester.getSize(find.byType(IntrinsicHeight)).height;
    }

    final wide = await rowHeight(600);
    final narrow = await rowHeight(120);
    expect(
      tester.getRect(find.byKey(const Key('v'))).width,
      lessThan(
        tester
            .renderObject<RenderParagraph>(find.byKey(const Key('v')))
            .size
            .width,
      ),
      reason: 'geschrumpft',
    );
    expect(narrow, closeTo(wide, 0.5));
  });

  // Bedienleiste auf 320 dp bei Faktor 1,3: kein Überlauf, alle Tasten im
  // Bild.
  testWidgets('Live: Bedienleiste läuft bei 320 dp nicht über', (tester) async {
    await loadManrope(tester);
    await loadSora(tester);
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await tester.tap(key('home_start_run'));
    await tester.pumpAndSettle();
    await tester.tap(key('run_start_ready'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(320, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'kein Überlauf');
    for (final k in ['run_lap', 'run_pause']) {
      final r = tester.getRect(key(k));
      expect(r.left, greaterThanOrEqualTo(0), reason: k);
      expect(r.right, lessThanOrEqualTo(320), reason: k);
    }
  });

  // Live-Seite, leerer Zustand: Ersatztexte schrumpfen nicht (kein FittedBox).
  testWidgets('Live: Ersatztext schrumpft nicht', (tester) async {
    await loadManrope(tester);
    await loadSora(tester);
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await tester.tap(key('home_start_run'));
    await tester.pumpAndSettle();
    await tester.tap(key('run_start_ready'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(360, 640);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpAndSettle();
    for (final k in ['run_pace', 'run_cadence']) {
      final p = tester.renderObject<RenderParagraph>(find.byKey(Key(k)));
      expect(
        p.text.toPlainText(),
        matches(RegExp(r'noch keine Daten|nicht verfügbar|–')),
        reason: '$k: Ersatztext',
      );
      expect(
        find.ancestor(of: find.byKey(Key(k)), matching: find.byType(FittedBox)),
        findsNothing,
        reason: '$k: Ersatztext ohne FittedBox',
      );
    }
  });

  // Bedienleiste wächst auf breiten Schirmen nicht (nur scaleDown).
  testWidgets('Live: Bedienleiste wächst bei 411 dp nicht', (tester) async {
    await loadManrope(tester);
    await loadSora(tester);
    final d = Device();
    await d.start(tester, const Locale('de'));
    await d.skipSetup(tester);
    await tester.tap(key('home_start_run'));
    await tester.pumpAndSettle();
    await tester.tap(key('run_start_ready'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(411, 800);
    await tester.pumpAndSettle();
    // Gezeichnete Breite (mit Skalierung der FittedBox), nicht die Layoutgröße.
    double drawn(String k) =>
        tester.getBottomRight(key(k)).dx - tester.getTopLeft(key(k)).dx;
    expect(drawn('run_pause'), closeTo(104, 0.5));
    expect(drawn('run_lap'), closeTo(68, 0.5));
  });

  // Pausierte Reihe bei 320 dp/1,3: „Weiter“/„Beenden“ in einer Zeile.
  for (final lang in ['de', 'en']) {
    testWidgets('Live: pausierte Tasten einzeilig bei 320 dp: $lang', (
      tester,
    ) async {
      await loadManrope(tester);
      await loadSora(tester);
      final d = Device();
      await d.start(tester, Locale(lang));
      await d.skipSetup(tester);
      await tester.tap(key('home_start_run'));
      await tester.pumpAndSettle();
      await tester.tap(key('run_start_ready'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(320, 640);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpAndSettle();
      await tester.tap(key('run_pause'));
      await tester.pumpAndSettle();
      for (final k in ['run_resume', 'run_finish']) {
        final t = find.descendant(of: key(k), matching: find.byType(FittedBox));
        expect(t, findsOneWidget, reason: k);
        final p = tester.renderObject<RenderParagraph>(
          find.descendant(of: t, matching: find.byType(RichText)).first,
        );
        expect(p.size.height, lessThan(40), reason: '$k: eine Zeile');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
