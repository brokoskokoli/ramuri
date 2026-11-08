import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kanalnamen (`ramuri/…`) stehen auf Dart- und Kotlin-Seite als Zeichenketten. Dieser Test
/// vergleicht beide Mengen vollständig, damit eine Umbenennung oder ein neuer Kanal auf nur einer
/// Seite sofort auffällt (WP14, FR-0206). Das Archivformat bleibt davon unberührt.
///
/// Ein Kanalname ist das, was ein Kanalkonstruktor (`MethodChannel(`, `EventChannel(`,
/// `BasicMessageChannel(`) als Name bekommt: ein Literal oder ein Bezeichner, der in derselben Datei
/// auf ein Literal aufgelöst wird (`NAME = "…"`, auch `val NAME: String = "…"`; bei `A.B` zählt `B`).
/// In Kotlin steht der Messenger vor dem Namen, in Dart der Name zuerst: es zählt das erste der
/// beiden ersten Argumente, das ein Literal oder ein auflösbarer Bezeichner ist. Ist keines von
/// beiden auflösbar, steht `unresolved:…` in der Menge und der Test wird rot. Konstanten, die an
/// keinem Konstruktor stehen (z. B. `CHANNEL_ID` für Benachrichtigungen), zählen nicht. Das Präfix
/// spielt für die Erkennung keine Rolle: auch `other/x` wird gefunden und dann abgelehnt.
final _constructor = RegExp(
  r'\b(?:Method|Event|BasicMessage)Channel\s*(?:<[^>()]*>)?\s*\(([^)]*)\)',
);
final _definition = RegExp(
  '\\b(\\w+)\\s*(?::\\s*\\w+\\??)?\\s*=\\s*["\']([^"\']*)["\']',
);
final _literal = RegExp('^["\']([^"\']*)["\']\$');

/// Kanalnamen im Quelltext; Zeilenkommentare zählen nicht.
Set<String> channelNames(String source) {
  final code = source.replaceAll(RegExp(r'//.*'), '');
  final values = <String, Set<String>>{};
  for (final m in _definition.allMatches(code)) {
    values.putIfAbsent(m.group(1)!, () => {}).add(m.group(2)!);
  }
  final names = <String>{};
  for (final m in _constructor.allMatches(code)) {
    final args = m.group(1)!.split(',').map((a) => a.trim()).take(2).toList();
    String? name;
    for (final arg in args) {
      final literal = _literal.firstMatch(arg)?.group(1);
      final resolved = values[arg.split('.').last];
      if (literal != null) {
        name = literal;
      } else if (resolved != null && resolved.length == 1) {
        name = resolved.single;
      }
      if (name != null) break;
    }
    names.add(name ?? 'unresolved:${args.join(', ')}');
  }
  return names;
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
  test(
    'Erkennung: Konstruktor, Bezeichner, beliebiges Präfix (Gegenprobe)',
    () {
      expect(channelNames("const MethodChannel('other/x');"), {'other/x'});
      expect(channelNames('EventChannel(\n  "a/b",\n)'), {'a/b'});
      expect(channelNames('MethodChannel(m.binaryMessenger, "k/l")'), {'k/l'});
      expect(channelNames('BasicMessageChannel<String>("n/o", codec)'), {
        'n/o',
      });
      // Bezeichner werden aufgelöst, gleich wie sie heißen.
      expect(
        channelNames("const String foo = 'p/q';\nMethodChannel(foo, codec);"),
        {'p/q'},
      );
      expect(
        channelNames('val NAME: String = "r/s"\nMethodChannel(m, Obj.NAME)'),
        {'r/s'},
      );
      expect(
        channelNames(
          'val X_CHANNEL_ID = "t/u"\nMethodChannel(m, X_CHANNEL_ID)',
        ),
        {'t/u'},
      );
      // Nicht auflösbar oder mehrdeutig: rot statt unsichtbar.
      expect(
        channelNames('MethodChannel(someName)').single,
        startsWith('unresolved:'),
      );
      expect(
        channelNames('MethodChannel(m, other)').single,
        startsWith('unresolved:'),
      );
      expect(
        channelNames('val A = "v/w"\nval A = "x/y"\nMethodChannel(m, A)')
            .single,
        startsWith('unresolved:'),
      );
      // Keine Kanäle: Konstanten ohne Konstruktor, Texte, Kommentare, Klassen mit dem Namen als Teil.
      expect(channelNames('const val CHANNEL_ID = "recording"'), isEmpty);
      expect(channelNames('const val METHOD_CHANNEL = "r/s"'), isEmpty);
      expect(channelNames("final t = 'ramuri/kein_kanal';"), isEmpty);
      expect(channelNames("// MethodChannel('c/d')"), isEmpty);
      expect(channelNames("MethodChannelCadenceSensor('z/z')"), isEmpty);
    },
  );

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
