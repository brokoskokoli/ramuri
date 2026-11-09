// Pluralformen der Abschnittszahl in den Beschreibungen von Route und Diagrammen (E2E 36: "1 zusammenhängende Abschnitte").
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/l10n/app_localizations.dart';

void main() {
  for (final lang in ['de', 'en']) {
    final l = lookupAppLocalizations(Locale(lang));
    final one = lang == 'de'
        ? '1 zusammenhängender Abschnitt;'
        : '1 connected section;';
    final many = lang == 'de'
        ? '2 zusammenhängende Abschnitte;'
        : '2 connected sections;';
    test('Abschnittszahl im Singular und Plural ($lang)', () {
      for (final f in <String Function(int)>[
        l.detRouteSemantics,
        (n) => l.detChartSemantics('a', 'b', 'c', n),
        (n) => l.detCompareSemantics('a', 'b', n),
        (n) => l.mapRouteSemantics(n, 'Q'),
        l.mapLiveLineSemantics,
      ]) {
        expect(f(1), contains(one));
        expect(f(2), contains(many));
        expect(f(0), isNot(contains('1 ')));
      }
    });
  }

  // E2E 31: "der letzten 1 Läufe" im Vergleichstext der Zusammenfassung.
  test('Vergleichstext mit 1 und 2 vorigen Läufen (de)', () {
    final l = lookupAppLocalizations(const Locale('de'));
    expect(
      l.sumClassFaster('5 s/km', 1, '5:00'),
      '5 s/km schneller als der letzte Lauf (5:00)',
    );
    expect(
      l.sumClassSlower('5 s/km', 1, '5:00'),
      '5 s/km langsamer als der letzte Lauf (5:00)',
    );
    expect(
      l.sumClassSame(1, '5:00'),
      'Gleiche Pace wie der letzte Lauf (5:00)',
    );
    expect(
      l.sumClassFaster('5 s/km', 2, '5:00'),
      '5 s/km schneller als der Schnitt der letzten 2 Läufe (5:00)',
    );
    expect(l.sumClassSlower('5 s/km', 2, '5:00'), contains('letzten 2 Läufe'));
    expect(l.sumClassSame(2, '5:00'), contains('letzten 2 Läufe'));
  });

  test('Vergleichstext mit 1 und 2 vorigen Läufen (en)', () {
    final l = lookupAppLocalizations(const Locale('en'));
    expect(
      l.sumClassFaster('5 s/km', 1, '5:00'),
      '5 s/km faster than the last run (5:00)',
    );
    expect(
      l.sumClassSlower('5 s/km', 1, '5:00'),
      '5 s/km slower than the last run (5:00)',
    );
    expect(l.sumClassSame(1, '5:00'), 'Same pace as the last run (5:00)');
    expect(
      l.sumClassFaster('5 s/km', 2, '5:00'),
      '5 s/km faster than the average of the last 2 runs (5:00)',
    );
    expect(l.sumClassSlower('5 s/km', 2, '5:00'), contains('last 2 runs'));
    expect(l.sumClassSame(2, '5:00'), contains('last 2 runs'));
  });

  // E2E 36 (NB5): "Neuberechnet: 1 Läufe", "Recalculated: 1 runs".
  test('Neuberechnet im Singular und Plural (de, en)', () {
    final de = lookupAppLocalizations(const Locale('de'));
    final en = lookupAppLocalizations(const Locale('en'));
    expect(
      de.recalcDone(1),
      'Neuberechnet: 1 Lauf. Die ursprünglichen Werte bleiben erhalten.',
    );
    expect(
      de.recalcDone(14),
      'Neuberechnet: 14 Läufe. Die ursprünglichen Werte bleiben erhalten.',
    );
    expect(
      en.recalcDone(1),
      'Recalculated: 1 run. The original values are kept.',
    );
    expect(
      en.recalcDone(14),
      'Recalculated: 14 runs. The original values are kept.',
    );
  });
}
