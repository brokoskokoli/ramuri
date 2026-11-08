import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kanalnamen (`ramuri/…`) stehen auf Dart- und Kotlin-Seite als Zeichenketten. Dieser Test
/// vergleicht beide Mengen vollständig, damit eine Umbenennung oder ein neuer Kanal auf nur einer
/// Seite sofort auffällt (WP14, FR-0206). Das Archivformat bleibt davon unberührt.
///
/// Ein Kanalname ist ein Literal an einem Kanalkonstruktor (`MethodChannel(`, `EventChannel(`; in
/// Kotlin steht der Messenger davor) oder der Wert einer Konstante, deren Name `Channel` enthält.
/// Benachrichtigungskanäle (`CHANNEL_ID`) sind keine Flutter-Kanäle. Das Präfix spielt für die Erkennung keine Rolle: auch `other/x` wird gefunden und dann abgelehnt.
final _constructor = RegExp(
  '(?:Method|Event)Channel\\(\\s*(?:[\\w.]+\\s*,\\s*)?["\']([^"\']+)["\']',
);
final _constant = RegExp(
  '\\b\\w*(?:Channel|CHANNEL)(?!_ID\\b|Id\\b)\\w*\\s*=\\s*["\']([^"\']+)["\']',
);

/// Kanalnamen im Quelltext; Zeilenkommentare zählen nicht.
Set<String> channelNames(String source) {
  final code = source.replaceAll(RegExp(r'//.*'), '');
  return {
    for (final re in [_constructor, _constant])
      for (final m in re.allMatches(code)) m.group(1)!,
  };
}

Set<String> namesIn(Iterable<Directory> roots, String ext) {
  final found = <String>{};
  for (final root in roots) {
    for (final f in root.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith(ext)) continue;
      found.addAll(channelNames(f.readAsStringSync()));
    }
  }
  return found;
}

void main() {
  test('Erkennung: Konstruktor, Konstante, beliebiges Präfix (Gegenprobe)', () {
    expect(channelNames("const MethodChannel('other/x');"), {'other/x'});
    expect(channelNames('EventChannel(\n  "a/b",\n)'), {'a/b'});
    expect(channelNames('MethodChannel(m.binaryMessenger, "k/l")'), {'k/l'});
    expect(channelNames("const String fooChannelName = 'p/q';"), {'p/q'});
    expect(channelNames('const val METHOD_CHANNEL = "r/s"'), {'r/s'});
    expect(channelNames('const val CHANNEL_ID = "recording"'), isEmpty);
    expect(channelNames("MethodChannel(someName)"), isEmpty);
    expect(channelNames("final t = 'ramuri/kein_kanal';"), isEmpty);
    expect(channelNames("// MethodChannel('c/d')"), isEmpty);
  });

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
    expect(dart.length, greaterThanOrEqualTo(7));
    expect(kotlin.length, greaterThanOrEqualTo(7));
    expect(dart.difference(kotlin), isEmpty, reason: 'nur in Dart');
    expect(kotlin.difference(dart), isEmpty, reason: 'nur in Kotlin');
    expect(dart.where((n) => !n.startsWith('ramuri/')), isEmpty);
    expect(kotlin.where((n) => !n.startsWith('ramuri/')), isEmpty);
  });
}
