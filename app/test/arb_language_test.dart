import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sprachregeln für alle Texte (WP10 Punkt 6): keine Genauigkeits- oder
/// Validierungsaussage (FR-0054, FR-0072, NFR-0003, NFR-0004), Zonen nicht als
/// Schwellen (FR-0064), TRIMP nicht als Ermüdung (FR-0094), Schätzungen
/// erkennbar (CON-0009, FR-0088).
///
/// Die Wortliste ist bewusst eng: Jeder Treffer ist eine Aussage, die ohne
/// dokumentierten Nachweis nicht stehen darf. Wo ein Wort nur in einer
/// ausdrücklichen Verneinung vorkommt (etwa „keine gemessenen Schwellen“),
/// steht der Schlüssel in [negated]: Nur diese Phrase wird aus dem Text
/// genommen, der Rest wird gegen alle Muster geprüft.
final List<RegExp> forbidden = [
  // Genauigkeit und Zuverlässigkeit als Eigenschaft des Werts
  RegExp(r'genauigkeit|präzis|accura|precision', caseSensitive: false),
  RegExp(
    r'validier|validat|wissenschaftlich|scientific|klinisch|clinical',
    caseSensitive: false,
  ),
  RegExp(r'±|fehlergrenze|margin of error|error margin', caseSensitive: false),
  // Zonen als Schwellen, TRIMP als Ermüdung
  RegExp(r'schwelle|threshold|laktat|lactate', caseSensitive: false),
  RegExp(
    r'ermüd|fatigue|überlastung|overtrain|trainingsanpassung|adaptation',
    caseSensitive: false,
  ),
  // Sicherheitsversprechen, Medizin, Erholung
  RegExp(
    r'exakt|exact|bewiesen|proven|medizin|medical|diagnos|erholung|recovery',
    caseSensitive: false,
  ),
];

/// Schlüssel, deren Text ein Wort der Liste nur verneint enthält, mit den
/// Wörtern, die die Verneinung anzeigen.
final Map<String, RegExp> negated = {
  'zonesNote': RegExp(
    r'keine gemessenen Schwellen und ersetzen keine individuell bestimmten '
    r'ventilatorischen oder Laktatschwellen|'
    r'not measured thresholds and do not replace individually determined '
    r'ventilatory or lactate thresholds',
  ),
  'explKindZones': RegExp(
    r'keine gemessenen Schwellen|not measured thresholds',
  ),
  'explKindTrimp': RegExp(
    r'sagt nichts über Ermüdung oder Trainingsanpassung|'
    r'says nothing about fatigue or training adaptation',
  ),
  'explQualityNote': RegExp(
    r'keine Angabe zur Genauigkeit|not a statement about the accuracy',
  ),
  // FR-0203: fester Text, Wortlaut vorbehaltlich OQ-0048.
  'planWarnBannerText': RegExp(
    r'Diese App stellt keine Diagnose|This app does not provide a diagnosis',
  ),
};

Map<String, String> load(String locale) {
  final json = jsonDecode(
    File('lib/l10n/app_$locale.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  return {
    for (final e in json.entries)
      if (!e.key.startsWith('@') && e.value is String) e.key: e.value as String,
  };
}

/// Treffer als `locale/key: Wort`.
List<String> violations(Map<String, Map<String, String>> byLocale) {
  final out = <String>[];
  byLocale.forEach((locale, texts) {
    texts.forEach((key, text) {
      for (final re in forbidden) {
        // Nur die erlaubte Verneinung herausnehmen, der Rest bleibt geprüft.
        final rest = negated[key] == null
            ? text
            : text.replaceAll(negated[key]!, ' ');
        final m = re.firstMatch(rest);
        if (m == null) continue;
        out.add('$locale/$key: "${m.group(0)}"');
      }
    });
  });
  return out;
}

void main() {
  final all = {'de': load('de'), 'en': load('en')};

  test(
    'keine Genauigkeits-, Validierungs-, Schwellen- oder Ermüdungsaussage',
    () {
      expect(violations(all), isEmpty);
    },
  );

  test('die Prüfung erkennt Verstöße (auch eine Verneinung, die fehlt)', () {
    expect(
      violations({
        'de': {'a': 'Genauigkeit von 95 %', 'b': 'Deine anaerobe Schwelle'},
      }),
      hasLength(2),
    );
    expect(
      violations({
        'en': {
          'a': 'Estimate is scientifically validated',
          'b': 'Fatigue score',
        },
      }),
      hasLength(2),
    );
    // Neue Wörter der Liste.
    expect(
      violations({
        'de': {'a': 'Exakte Werte', 'b': 'Zeit zur Erholung', 'c': 'bewiesen'},
        'en': {'a': 'Exact', 'b': 'recovery time', 'c': 'medical advice'},
      }),
      hasLength(6),
    );
    // Erlaubte Verneinung darf keine weitere Aussage im selben Text decken.
    expect(
      violations({
        'de': {
          'explQualityNote':
              'Sie ist keine Angabe zur Genauigkeit des Werts, aber '
              'wissenschaftlich validiert.',
        },
      }),
      isNotEmpty,
    );
    // Schlüssel mit erlaubter Verneinung, aber ohne sie im Text.
    expect(
      violations({
        'de': {'explKindTrimp': 'Der Wert beschreibt die Ermüdung.'},
      }),
      hasLength(1),
    );
  });

  test('Verneinungen stehen in beiden Sprachen im Text', () {
    for (final locale in all.keys) {
      for (final key in negated.keys) {
        expect(
          negated[key]!.hasMatch(all[locale]![key]!),
          isTrue,
          reason: '$locale/$key',
        );
      }
    }
  });

  test('geschätzte Werte sind als Schätzung erkennbar (CON-0009)', () {
    final marks = {
      'de': RegExp('Schätzung|Geschätzt'),
      'en': RegExp('estimate|Estimated', caseSensitive: false),
    };
    const estimateKeys = [
      'sumVo2max',
      'sumVo2maxValue',
      'statVo2Run',
      'statVo2Current',
      'statVo2Trend',
      'statEfficiencyValue',
      'explKindVo2Run',
      'explKindVo2LongTerm',
      'explKindEfficiency',
      'explEstimateBadge',
    ];
    for (final locale in all.keys) {
      for (final key in estimateKeys) {
        expect(
          marks[locale]!.hasMatch(all[locale]![key]!),
          isTrue,
          reason: '$locale/$key',
        );
      }
    }
  });

  test('Abgrenzung der Effizienz zur VO₂max (FR-0088)', () {
    expect(
      all['de']!['statEfficiencyNote'],
      contains('keine Änderung der VO₂max'),
    );
    expect(
      all['en']!['statEfficiencyNote'],
      contains('not a change in VO₂max'),
    );
    expect(
      all['de']!['explKindEfficiency'],
      contains('keine Veränderung der VO₂max'),
    );
  });
}
