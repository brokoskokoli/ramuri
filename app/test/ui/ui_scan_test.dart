import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Muster, die außerhalb von `lib/ui/` nicht vorkommen dürfen (FR-0205). Sie werden auf die ganze
/// Datei angewendet, `\s` greift also auch über Zeilenumbrüche.
final forbidden = <String, RegExp>{
  'Color(': RegExp(r'\bColor\s*\('),
  'Color.from': RegExp(r'\bColor\s*\.\s*from'),
  'Colors.': RegExp(r'\bColors\s*\.'),
  'CupertinoColors': RegExp(r'\bCupertinoColors\b'),
  'HSLColor': RegExp(r'\bHSLColor\b'),
  'HSVColor': RegExp(r'\bHSVColor\b'),
  'fontSize:': RegExp(r'\bfontSize\s*:'),
};

/// Quelltext ohne Kommentare und ohne Inhalt der Zeichenketten; Zeilenumbrüche bleiben erhalten,
/// damit Zeilennummern stimmen. Kommentare und Texte dürfen die Namen enthalten.
String stripCommentsAndStrings(String source) {
  final out = StringBuffer();
  var i = 0;
  final n = source.length;
  while (i < n) {
    final c = source[i];
    final next = i + 1 < n ? source[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < n && source[i] != '\n') {
        i++;
      }
    } else if (c == '/' && next == '*') {
      var depth = 1;
      i += 2;
      while (i < n && depth > 0) {
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          if (source[i] == '\n') out.write('\n');
          i++;
        }
      }
    } else if (c == "'" || c == '"') {
      final raw = i > 0 && source[i - 1] == 'r';
      final triple = source.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      out.write(quote);
      i += quote.length;
      while (i < n && !source.startsWith(quote, i)) {
        if (source[i] == '\\' && !raw) i++;
        if (i < n && source[i] == '\n') out.write('\n');
        i++;
      }
      out.write(quote);
      i += quote.length;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// Verstöße einer Datei (mit Zeile); Kommentare und Zeichenketten zählen nicht.
List<String> violations(String path, String source) {
  final code = stripCommentsAndStrings(source);
  final result = <String>[];
  forbidden.forEach((name, pattern) {
    for (final m in pattern.allMatches(code)) {
      final line = '\n'.allMatches(code.substring(0, m.start)).length + 1;
      result.add('$path:$line: $name');
    }
  });
  return result;
}

void main() {
  test('Scanner erkennt die verbotenen Muster (Gegenprobe)', () {
    for (final code in [
      'final c = Color(0xFF000000);',
      'final c = Color(4278190080);',
      'final c = const Color (\n  0xFF000000,\n);',
      'final c = Color.fromARGB(1, 2, 3, 4);',
      'final c = Color.fromRGBO(1, 2, 3, 1);',
      'final c = Color.from(alpha: 1, red: 0, green: 0, blue: 0);',
      'final c = Color\n    .from(alpha: 1, red: 0, green: 0, blue: 0);',
      'color: Colors.red,',
      'color: CupertinoColors.black,',
      'final c = HSLColor.fromAHSL(1, 0, 0, 0);',
      'final c = HSVColor.fromAHSV(1, 0, 0, 0);',
      'TextStyle(fontSize: 12)',
      'TextStyle(\n  fontSize\n      : 12)',
    ]) {
      expect(violations('a', code), isNotEmpty, reason: code);
    }
  });

  test('Scanner lässt erlaubten Code und Kommentare durch (Gegenprobe)', () {
    for (final code in [
      '// Colors.red und fontSize: 3',
      '/* Color(0xFF000000) \n Colors.red */',
      '/* a /* verschachtelt Colors.red */ Colors.red */',
      "final t = 'Colors.red und Color(0xFF000000)';",
      'final t = """\nColor(0xFF000000)\n""";',
      r"final t = r'\d+ Colors.red';",
      "final t = 'it\\'s Colors.red';",
      'final c = RamuriColors.of(context);',
      'final c = scheme.outlineVariant.withValues(alpha: 0.5);',
      'final Color? c = null;',
    ]) {
      expect(violations('a', code), isEmpty, reason: code);
    }
    // Code nach einer Zeichenkette mit // wird weiter geprüft.
    expect(violations('a', "f('http://x', Colors.red);"), isNotEmpty);
    // Roh-Zeichenkette endet am nächsten Anführungszeichen, ein Schrägstrich schützt nicht.
    expect(violations('a', r"f(r'\'); Colors.red;"), isNotEmpty);
    expect(violations('a', 'x;\n\ny = Colors.red;').single, 'a:3: Colors.');
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
