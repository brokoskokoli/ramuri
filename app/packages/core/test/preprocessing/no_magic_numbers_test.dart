import 'dart:io';

import 'package:test/test.dart';

/// Rechengrößen, die überall stehen dürfen. Jede Schwelle aus PAR-001..015
/// gehört in die Parameterklasse.
const common = <String, String>{
  '0': 'Rechengröße (Start, Vergleich)',
  '0.0': 'Rechengröße (Summenstart)',
  '1': 'Rechengröße (Index, Zähler, Methodenversion)',
  '2': 'Rechengröße (Median, Halbieren, Fensterverdopplung, Haversine)',
};

/// Einheiten und Konstanten, nur in den genannten Dateien erlaubt.
const perFile = <String, Set<String>>{
  '1e6': {
    'heart_rate_processor.dart',
    'motion_segments.dart',
    'pace_processor.dart',
    'position_processor.dart',
    'settling_processor.dart',
  }, // Mikrosekunden je Sekunde
  '1000': {'pace.dart'}, // Meter je Kilometer
  '1e-9': {'vo2max_estimator.dart'}, // Gleitkomma-Toleranz, kein Grenzwert
  '180': {'geo.dart', 'personal_load_factor.dart'}, // Grad zu Bogenmaß; Tage
  // WP19: benannte Parameter in eigenen Klassen (FR-0197, PAR-086, PAR-087),
  // nicht in FitnessParameters, weil sie nicht zur Parameterversion der
  // Vorverarbeitung gehören.
  '20': {'personal_load_factor.dart'}, // PAR-087, PAR-087 gesichert
  '10': {'personal_load_factor.dart'}, // PAR-086 Mindestläufe
  '6': {'personal_load_factor.dart'}, // PAR-086 hohe RPE
  '4': {'personal_load_factor.dart'}, // PAR-086 niedrige RPE
  '0.25': {'personal_load_factor.dart'}, // PAR-087 Toleranz
  '183': {'personal_load_factor.dart'}, // PAR-087 Vorwert 6 Monate (Festlegung)
  '0.64': {'banister_trimp.dart'}, // k männlich (K43)
  '1.92': {'banister_trimp.dart'}, // b männlich
  '0.86': {'banister_trimp.dart'}, // k weiblich
  '1.67': {'banister_trimp.dart'}, // b weiblich
  '6371008.8': {'geo.dart'}, // Erdradius (benannte Konstante)
};

bool isAllowed(String file, String literal) =>
    common.containsKey(literal) || (perFile[literal]?.contains(file) ?? false);

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
  test('numerische Literale in lib/src/preprocessing und lib/src/fitness '
      'außerhalb der Parameterklassen sind nur Rechengrößen, Einheiten, '
      'Erdradius', () {
    final files = [
      for (final dir in ['lib/src/preprocessing', 'lib/src/fitness'])
        ...Directory(dir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where(
              (f) =>
                  !f.path.endsWith('preprocessing_parameters.dart') &&
                  !f.path.endsWith('fitness_parameters.dart'),
            ),
    ];
    expect(files.length, greaterThan(10));
    expect(
      files.where((f) => f.path.contains('src/fitness/')),
      isNotEmpty,
      reason: 'src/fitness muss mitgeprüft werden',
    );
    final hits = <String, Set<String>>{};
    final unknown = <String>[];
    for (final f in files) {
      for (final lit in literals(f.readAsStringSync())) {
        hits.putIfAbsent(lit, () => {}).add(f.uri.pathSegments.last);
        if (!isAllowed(f.uri.pathSegments.last, lit)) {
          unknown.add('${f.path}: $lit');
        }
      }
    }
    // Trefferliste zur Durchsicht (dart test --reporter expanded).
    for (final e in hits.entries) {
      // ignore: avoid_print
      print(
        '${e.key.padRight(10)} ${(common[e.key] ?? 'Einheit/Konstante')}'
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

  test('Einheiten gelten nur in ihrer Datei', () {
    expect(isAllowed('pace.dart', '1000'), isTrue);
    expect(isAllowed('settling_processor.dart', '1000'), isFalse);
    expect(isAllowed('settling_processor.dart', '180'), isFalse);
    expect(isAllowed('geo.dart', '180'), isTrue);
    expect(isAllowed('section_quality.dart', '1e6'), isFalse);
  });

  test('der Scanner findet eine eingeschleuste Schwelle', () {
    expect(
      literals("final x = v > 0.25; // 30 s\nconst a = 'v2'; var b = 1e6;"),
      ['0.25', '1e6'],
    );
  });
}
