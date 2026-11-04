import 'dart:io';

import 'package:test/test.dart';

/// Rechengrößen und Einheiten, die außerhalb von preprocessing_parameters.dart
/// stehen dürfen. Jede Schwelle aus PAR-001..015 gehört in die Parameterklasse.
const allowed = <String, String>{
  '0': 'Rechengröße (Start, Vergleich)',
  '0.0': 'Rechengröße (Summenstart)',
  '1': 'Rechengröße (Index, Zähler, Methodenversion)',
  '2': 'Rechengröße (Median, Halbieren, Fensterverdopplung, Haversine)',
  '1e6': 'Einheit: Mikrosekunden je Sekunde',
  '1000': 'Einheit: Meter je Kilometer',
  '180': 'Einheit: Grad zu Bogenmaß',
  '6371008.8': 'Erdradius (benannte Konstante in geo.dart)',
};

/// Zahlliterale einer Dart-Quelle ohne Kommentare und Zeichenketten.
Iterable<String> literals(String source) sync* {
  final code = source
      .split('\n')
      .map((l) => l.replaceFirst(RegExp(r'//.*'), ''))
      .map((l) => l.replaceAll(RegExp(r"'[^']*'"), "''"))
      .join('\n');
  for (final m in RegExp(
    r'(?<![\w.])\d+(?:\.\d+)?(?:[eE][+-]?\d+)?',
  ).allMatches(code)) {
    yield m.group(0)!;
  }
}

void main() {
  test('numerische Literale in lib/src/preprocessing außerhalb der '
      'Parameterklasse sind nur Rechengrößen, Einheiten, Erdradius', () {
    final files = Directory('lib/src/preprocessing')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('preprocessing_parameters.dart'))
        .toList();
    expect(files.length, greaterThan(10));
    final hits = <String, Set<String>>{};
    final unknown = <String>[];
    for (final f in files) {
      for (final lit in literals(f.readAsStringSync())) {
        hits.putIfAbsent(lit, () => {}).add(f.uri.pathSegments.last);
        if (!allowed.containsKey(lit)) {
          unknown.add('${f.path}: $lit');
        }
      }
    }
    // Trefferliste zur Durchsicht (dart test --reporter expanded).
    for (final e in hits.entries) {
      // ignore: avoid_print
      print(
        '${e.key.padRight(10)} ${(allowed[e.key] ?? 'NICHT ERLAUBT')}'
        '  [${(e.value.toList()..sort()).join(', ')}]',
      );
    }
    expect(
      unknown,
      isEmpty,
      reason: 'Schwellen gehören in PreprocessingParameters',
    );
    expect(hits['6371008.8'], {'geo.dart'});
  });

  test('der Scanner findet eine eingeschleuste Schwelle', () {
    expect(
      literals("final x = v > 0.25; // 30 s\nconst a = 'v2'; var b = 1e6;"),
      ['0.25', '1e6'],
    );
  });
}
