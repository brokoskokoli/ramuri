import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/e2e_support.dart';

// Schrittmarken der E2E-Tests stehen im oeffentlichen CI-Log (PUB_-Zeilen,
// tool/ci_e2e.sh). Sie duerfen nie Werte tragen (SEC-0001..0010): jeder Aufruf
// von step(...) uebergibt ein einzelnes Literal ohne Interpolation.

/// Aufrufe von `step(` ausser der Definition (`void step(`), nicht als Methode
/// (`x.step(`) oder Teil eines anderen Namens (`_step(`).
final _call = RegExp(r'(?<![\w.$])(?<!void )step\(');

/// Ein Literal in einfachen Anfuehrungszeichen ohne `$` und ohne Escape, dann
/// die schliessende Klammer (kein `+`, kein angehaengter Ausdruck).
final _literal = RegExp(r"step\(\s*'[^'\\$\n]*'\s*,?\s*\)");

/// Aufrufe in [source], die kein reines Literal uebergeben (Zeilennummern).
List<int> nonLiteralSteps(String source) => [
  for (final m in _call.allMatches(source))
    if (_literal.matchAsPrefix(source, m.start) == null)
      '\n'.allMatches(source.substring(0, m.start)).length + 1,
];

void main() {
  test('step schreibt eine PUB_-Zeile "SCHRITT <name>"', () {
    final lines = <String>[];
    runZoned(
      () => step('HC4 loeschen'),
      zoneSpecification: ZoneSpecification(
        print: (_, _, _, line) => lines.add(line),
      ),
    );
    expect(lines, hasLength(1));
    expect(
      lines.single,
      matches(RegExp(r'^PUB_\d\d:\d\d:\d\d\.\d{3} SCHRITT HC4 loeschen$')),
    );
    // Nicht mit E2E_: diese Zeilen filtert tool/ci_e2e.sh aus dem Log.
    expect(lines.single, isNot(contains('E2E_')));
  });

  group('Pruefung der Aufrufe', () {
    test('Literal ist erlaubt, auch ueber mehrere Zeilen', () {
      expect(nonLiteralSteps("  step('S1 ok');\n"), isEmpty);
      expect(nonLiteralSteps("  step(\n    'S1 ok',\n  );\n"), isEmpty);
      expect(nonLiteralSteps('void step(String name) => x;'), isEmpty);
      expect(nonLiteralSteps("t.step(v); _step(v);"), isEmpty);
    });

    test('Interpolation, Variable, Verkettung und Ausdruck sind verboten', () {
      expect(nonLiteralSteps(r"step('S1 $wert');"), [1]);
      expect(nonLiteralSteps(r"step('S1 ${w.x}');"), [1]);
      expect(nonLiteralSteps('a;\nstep(name);'), [2]);
      expect(nonLiteralSteps("step('S1 ' + name);"), [1]);
      expect(nonLiteralSteps("step('S1 ' 'x');"), [1]);
      expect(nonLiteralSteps("step(d ? 'a' : 'b');"), [1]);
      expect(nonLiteralSteps('step("S1 \$x");'), [1]);
      expect(nonLiteralSteps(r"step('S1 \x41');"), [1]);
    });
  });

  // Laeuft in app/ (flutter test); die E2E-Tests liegen in integration_test/.
  final files =
      Directory('integration_test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('E2E-Quellen gefunden', () {
    expect(files.where((f) => f.path.contains('e2e_')), isNotEmpty);
  });

  for (final f in files) {
    test('${f.path}: step(...) nur mit Literal ohne Interpolation', () {
      expect(nonLiteralSteps(f.readAsStringSync()), isEmpty);
    });
  }

  // Jeder E2E-Test markiert seine Abschnitte; ohne Marke zeigt ein roter Lauf
  // im oeffentlichen Log nicht, wie weit er kam.
  for (final f in files.where(
    (f) => RegExp(r'e2e_\w+_test\.dart$').hasMatch(f.path),
  )) {
    test('${f.path}: setzt Schrittmarken', () {
      expect(_call.hasMatch(f.readAsStringSync()), isTrue);
    });
  }
}
