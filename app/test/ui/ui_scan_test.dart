import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Muster, die außerhalb von `lib/ui/` nicht vorkommen dürfen (FR-0205).
final forbidden = <String, RegExp>{
  'Color(0x': RegExp(r'Color\(\s*0x'),
  'Color.fromARGB': RegExp(r'Color\.fromARGB'),
  'Color.fromRGBO': RegExp(r'Color\.fromRGBO'),
  'Colors.': RegExp(r'\bColors\.'),
  'fontSize:': RegExp(r'\bfontSize\s*:'),
};

/// Verstöße je Datei; Zeilenkommentare zählen nicht.
List<String> violations(String path, String source) {
  final result = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final code = lines[i].replaceFirst(RegExp(r'//.*'), '');
    forbidden.forEach((name, pattern) {
      if (pattern.hasMatch(code)) result.add('$path:${i + 1}: $name');
    });
  }
  return result;
}

void main() {
  test('Scanner erkennt die verbotenen Muster (Gegenprobe)', () {
    expect(violations('a', 'final c = Color(0xFF000000);'), isNotEmpty);
    expect(
      violations('a', 'final c = Color.fromARGB(1, 2, 3, 4);'),
      isNotEmpty,
    );
    expect(violations('a', 'color: Colors.red,'), isNotEmpty);
    expect(violations('a', 'TextStyle(fontSize: 12)'), isNotEmpty);
    expect(violations('a', '// Colors.red und fontSize: 3'), isEmpty);
    expect(violations('a', 'final c = RamuriColors.of(context);'), isEmpty);
  });

  test('lib/ ohne ui/ und l10n/: keine Farbwerte, keine Schriftgrößen', () {
    final root = Directory('lib');
    final found = <String>[];
    var scanned = 0;
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      final path = f.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      if (path.startsWith('lib/ui/') || path.startsWith('lib/l10n/')) continue;
      scanned++;
      found.addAll(violations(path, f.readAsStringSync()));
    }
    expect(scanned, greaterThan(10), reason: 'Scan findet die Dateien');
    expect(found, isEmpty);
  });
}
