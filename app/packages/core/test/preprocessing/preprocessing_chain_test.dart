// Kettenversion der Vorverarbeitung (ADR-0004, NFR-0001, NFR-0005): jede
// Stufe mit eigener `*MethodVersion` in lib/src/preprocessing steht in
// preprocessingChainVersion(), und jede Stufenerhöhung ändert den Wert.

import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Alle `const int <name>MethodVersion = <n>;` in lib/src/preprocessing.
Map<String, int> _stageConstants() {
  final pattern = RegExp(r'const\s+int\s+(\w+MethodVersion)\s*=\s*(\d+)\s*;');
  return {
    for (final f in Directory(
      'lib/src/preprocessing',
    ).listSync().whereType<File>().where((f) => f.path.endsWith('.dart')))
      for (final m in pattern.allMatches(f.readAsStringSync()))
        m.group(1)!: int.parse(m.group(2)!),
  };
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
    expect(legacyPreprocessingChainVersion, preprocessingChainVersion());
  });
}
