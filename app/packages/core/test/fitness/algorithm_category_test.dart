import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

// Gleicht die Tabelle in docs/architecture/algorithm-categories.md mit der
// Registry der Standardbestückung und den Konstanten im Code ab.
void main() {
  group('Kategorien-Tabelle gegen Registry und Code', () {
    final rows = <String, (int, String, String)>{};
    final doc = File('../../../docs/architecture/algorithm-categories.md')
        .readAsLinesSync();
    for (final l in doc) {
      final m = RegExp(
        r'^\| [^|]+ \| `([a-z0-9-]+)` v(\d+) \| ([ABC]) \|.*\| (WP\d+) \|$',
      ).firstMatch(l);
      if (m != null) rows[m[1]!] = (int.parse(m[2]!), m[3]!, m[4]!);
    }
    String letter(AlgorithmCategory c) => switch (c) {
      AlgorithmCategory.established => 'A',
      AlgorithmCategory.heuristic => 'B',
      AlgorithmCategory.calibrated => 'C',
    };

    test('Tabelle ist lesbar', () {
      expect(rows.length, greaterThanOrEqualTo(11));
    });

    test('jede registrierte Variante steht mit Version und Kategorie drin', () {
      final reg = AlgorithmRegistry.standard();
      expect(reg.allVariants, isNotEmpty);
      for (final v in reg.allVariants) {
        final row = rows[v.method];
        expect(row, isNotNull, reason: '${v.method} fehlt in der Tabelle');
        expect(row!.$1, v.methodVersion, reason: v.method);
        expect(row.$2, letter(v.category), reason: v.method);
      }
    });

    test('WP03-Zeilen tragen die Version der Konstanten im Code', () {
      final code = <String, int>{
        positionMethod: positionMethodVersion,
        paceMethod: paceMethodVersion,
        movementMethod: movementMethodVersion,
        heartRateMethod: heartRateMethodVersion,
        settlingMethod: settlingMethodVersion,
        altitudeMethod: altitudeMethodVersion,
        stepsMethod: stepsMethodVersion,
        sectionQualityMethod: sectionQualityMethodVersion,
      };
      final wp03 = {
        for (final e in rows.entries.where((e) => e.value.$3 == 'WP03'))
          e.key: e.value.$1,
      };
      expect(wp03.keys.toSet(), code.keys.toSet());
      for (final e in code.entries) {
        expect(wp03[e.key], e.value, reason: e.key);
      }
    });

    test(
      'WP03-Zeilen und Abschnittsauswahl tragen die Kategorie des Codes',
      () {
        final code = <String, AlgorithmCategory>{
          positionMethod: positionCategory,
          paceMethod: paceCategory,
          movementMethod: movementCategory,
          heartRateMethod: heartRateCategory,
          settlingMethod: settlingCategory,
          altitudeMethod: altitudeCategory,
          stepsMethod: stepsCategory,
          sectionQualityMethod: sectionQualityCategory,
          vo2maxSectionSelectionMethod: vo2maxSectionSelectionCategory,
        };
        final doc = {
          for (final e in rows.entries.where(
            (e) =>
                e.value.$3 == 'WP03' || e.key == vo2maxSectionSelectionMethod,
          ))
            e.key: e.value.$2,
        };
        expect(doc.keys.toSet(), code.keys.toSet());
        for (final e in code.entries) {
          expect(doc[e.key], letter(e.value), reason: e.key);
        }
      },
    );

    test('jede Zeile von WP04 ist registriert', () {
      final registered = {
        for (final v in AlgorithmRegistry.standard().allVariants) v.method,
      };
      for (final e in rows.entries.where((e) => e.value.$3 == 'WP04')) {
        expect(registered, contains(e.key));
      }
    });
  });
}
