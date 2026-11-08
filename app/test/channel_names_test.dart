import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kanalnamen (`ramuri/…`) stehen auf Dart- und Kotlin-Seite als Zeichenketten. Dieser Test
/// vergleicht beide Mengen vollständig, damit eine Umbenennung oder ein neuer Kanal auf nur einer
/// Seite sofort auffällt (WP14, FR-0206). Das Archivformat bleibt davon unberührt.
void main() {
  final literal = RegExp('["\']((?:ramuri|running_app)/[A-Za-z_]+)["\']');

  Set<String> namesIn(Iterable<Directory> roots, String ext) {
    final found = <String>{};
    for (final root in roots) {
      for (final f in root.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith(ext)) continue;
        for (final m in literal.allMatches(f.readAsStringSync())) {
          found.add(m.group(1)!);
        }
      }
    }
    return found;
  }

  final dartRoots = [
    Directory('lib'),
    ...Directory('packages')
        .listSync()
        .whereType<Directory>()
        .map((d) => Directory('${d.path}/lib'))
        .where((d) => d.existsSync()),
  ];
  final kotlinRoot = Directory(
    'android/app/src/main/kotlin/io/github/brokoskokoli/ramuri',
  );

  test('Kanalnamen in Dart und Kotlin sind identisch und heißen ramuri/…', () {
    final dart = namesIn(dartRoots, '.dart');
    final kotlin = namesIn([kotlinRoot], '.kt');
    expect(dart, isNotEmpty);
    expect(kotlin, isNotEmpty);
    expect(dart.difference(kotlin), isEmpty, reason: 'nur in Dart');
    expect(kotlin.difference(dart), isEmpty, reason: 'nur in Kotlin');
    expect(dart.where((n) => !n.startsWith('ramuri/')), isEmpty);
  });
}
