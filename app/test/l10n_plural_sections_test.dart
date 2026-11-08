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
}
