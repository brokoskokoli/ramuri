import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schlüssel einer ARB-Datei ohne `@`-Metadaten.
Set<String> arbKeys(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).toSet();

/// Liefert je Sprachkürzel die Schlüssel aller `app_*.arb` im Ordner.
Map<String, Set<String>> loadArbKeys(Directory dir) {
  final result = <String, Set<String>>{};
  for (final file in dir.listSync().whereType<File>()) {
    final m = RegExp(r'app_([A-Za-z_]+)\.arb$').firstMatch(file.path);
    if (m == null) continue;
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    result[m.group(1)!] = arbKeys(json);
  }
  return result;
}

/// Fehlerliste: fehlende Sprachen und abweichende Schlüssel.
List<String> arbProblems(Map<String, Set<String>> byLocale) {
  final problems = <String>[];
  for (final required in ['de', 'en']) {
    if (!byLocale.containsKey(required)) {
      problems.add('app_$required.arb fehlt');
    }
  }
  final all = byLocale.values.expand((k) => k).toSet();
  byLocale.forEach((locale, keys) {
    for (final k in all.difference(keys)) {
      problems.add('app_$locale.arb: Schlüssel "$k" fehlt');
    }
  });
  return problems;
}

void main() {
  test('ARB-Dateien: de und en vorhanden, gleiche Schlüssel', () {
    final keys = loadArbKeys(Directory('lib/l10n'));
    expect(arbProblems(keys), isEmpty);
  });

  test('Prüfung erkennt fehlenden Schlüssel und fehlende Sprache', () {
    expect(
      arbProblems({
        'de': {'a', 'b'},
        'en': {'a'},
      }),
      ['app_en.arb: Schlüssel "b" fehlt'],
    );
    expect(
      arbProblems({
        'de': {'a'},
      }),
      ['app_en.arb fehlt'],
    );
  });
}
