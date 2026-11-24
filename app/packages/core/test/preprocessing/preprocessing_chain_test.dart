// Kettenversion der Vorverarbeitung (ADR-0004, NFR-0001, NFR-0005): jede
// Stufe mit eigener `*MethodVersion` in lib/src/preprocessing steht in
// preprocessingChainVersion(), und jede Stufenerhöhung ändert den Wert.

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Alle Deklarationen `<name>MethodVersion` in lib/src/preprocessing und
/// seinen Unterordnern: auf oberster Ebene und `static`, als `const` mit oder
/// ohne Typ `int` und als `final`. Ein Wert, der kein einfaches
/// Ganzzahl-Literal ist, macht den Test rot (Datei und Name in der Meldung).
Map<String, int> _stageConstants() {
  final pattern = RegExp(
    r'(?<![\w$])(?:static\s+)?(?:const|final)\s+(?:int\s+)?'
    r'(\w*MethodVersion)\s*=\s*([^;]*);',
  );
  final literal = RegExp(r'^\d+$');
  final files =
      Directory('lib/src/preprocessing')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final stages = <String, int>{};
  for (final f in files) {
    for (final m in pattern.allMatches(f.readAsStringSync())) {
      final name = m.group(1)!;
      final value = m.group(2)!.trim();
      if (!literal.hasMatch(value)) {
        fail(
          '${f.path}: $name = $value ist kein einfaches Ganzzahl-Literal; '
          'die Konstante als Literal schreiben (z. B. `const int $name = 1;`)',
        );
      }
      if (stages.containsKey(name)) {
        fail('${f.path}: $name ist mehrfach deklariert');
      }
      stages[name] = int.parse(value);
    }
  }
  return stages;
}

void main() {
  final chainSource = File('lib/src/preprocessing/preprocessing_chain.dart')
      .readAsStringSync();

  test('jede *MethodVersion der Vorverarbeitung steht als Vorgabe in der '
      'Kettenversion, und die Kette hat genau so viele Glieder', () {
    final stages = _stageConstants();
    expect(stages, isNotEmpty);
    // Vorgaben der Parameter: `int <name> = <Konstante>,`.
    final defaults = {
      for (final m in RegExp(
        r'int\s+\w+\s*=\s*(\w+MethodVersion)\s*,',
      ).allMatches(chainSource))
        m.group(1)!,
    };
    expect(
      stages.keys.toSet().difference(defaults),
      isEmpty,
      reason: 'neue Stufe ohne Eintrag in preprocessingChainVersion()',
    );
    expect(defaults.difference(stages.keys.toSet()), isEmpty);
    expect(preprocessingChainVersion().split('.'), hasLength(stages.length));
    // Jede Zahl der Kette stammt aus einer der Konstanten.
    expect(
      [
        for (final s in preprocessingChainVersion().split('.'))
          int.parse(RegExp(r'\d+$').stringMatch(s)!),
      ]..sort(),
      stages.values.toList()..sort(),
    );
  });

  test('jede Stufe um 1 erhöht ändert die Kette, jede anders', () {
    final now = preprocessingChainVersion();
    final raised = [
      preprocessingChainVersion(heartRate: heartRateMethodVersion + 1),
      preprocessingChainVersion(pace: paceMethodVersion + 1),
      preprocessingChainVersion(movement: movementMethodVersion + 1),
      preprocessingChainVersion(position: positionMethodVersion + 1),
      preprocessingChainVersion(altitude: altitudeMethodVersion + 1),
      preprocessingChainVersion(settling: settlingMethodVersion + 1),
      preprocessingChainVersion(
        sectionQuality: sectionQualityMethodVersion + 1,
      ),
      preprocessingChainVersion(steps: stepsMethodVersion + 1),
    ];
    // Die Suche findet genau die Stufen, die dieser Test erhöht.
    expect(_stageConstants().keys.toSet(), {
      'heartRateMethodVersion',
      'paceMethodVersion',
      'movementMethodVersion',
      'positionMethodVersion',
      'altitudeMethodVersion',
      'settlingMethodVersion',
      'sectionQualityMethodVersion',
      'stepsMethodVersion',
    });
    expect(raised, hasLength(_stageConstants().length));
    for (final r in raised) {
      expect(r, isNot(now));
    }
    expect(raised.toSet(), hasLength(raised.length));
    // Stabil: gleiche Versionen, gleicher Text.
    expect(preprocessingChainVersion(), now);
  });

  test('Kette der Bestandswerte (vor Schema 19) ist die heutige', () {
    // Gilt bis zur ersten Stufenerhöhung; dann diesen Test streichen, die
    // Konstante bleibt unverändert (Bestandswerte bekommen ein Angebot).
    expect(
      legacyPreprocessingChainVersion,
      preprocessingChainVersion(),
      reason:
          'Nach einer Stufenerhöhung wird dieser Test gestrichen; '
          'legacyPreprocessingChainVersion bleibt unverändert, sonst bekommen '
          'Bestandswerte (vor Schema 19) kein Angebot zur Neuberechnung.',
    );
  });
}
