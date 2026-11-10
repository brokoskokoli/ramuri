@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:test/test.dart';

import 'ppg_compare.dart';

/// Lokaler Abgleich des Ports mit der Kotlin-Referenz auf echten Messungen (WP27 Teil B).
///
/// Echte Messungen sind Gesundheitsdaten und bleiben außerhalb des Repos. Der Test läuft nur,
/// wenn zwei Umgebungsvariablen auf vorhandene Pfade zeigen, sonst wird er übersprungen:
///   PPG_REAL_FRAMES_DIR  Ordner mit `*_frames.csv` (Aufnahmen der Referenz-App `puls`)
///   PPG_REAL_REFERENCE   JSON der Kotlin-Referenz zu denselben Dateien (nur im Scratch erzeugt)
/// Ausgegeben werden ausschließlich Abweichungen (Datei-Nummer, Feld, Betrag), nie Messwerte.
Directory? _dir() {
  final p = Platform.environment['PPG_REAL_FRAMES_DIR'];
  if (p == null || p.isEmpty) return null;
  final d = Directory(p);
  return d.existsSync() ? d : null;
}

File? _reference() {
  final p = Platform.environment['PPG_REAL_REFERENCE'];
  if (p == null || p.isEmpty) return null;
  final f = File(p);
  return f.existsSync() ? f : null;
}

void main() {
  final dir = _dir();
  final refFile = _reference();
  final files = dir == null
      ? <File>[]
      : (dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('_frames.csv'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path)));
  final skip = (dir == null || refFile == null || files.isEmpty)
      ? 'ohne PPG_REAL_FRAMES_DIR/PPG_REAL_REFERENCE und Dateien übersprungen'
      : false;

  test('Port stimmt auf den lokalen Messungen mit der Referenz überein', () {
    final refs = (jsonDecode(refFile!.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
    expect(
      refs.length,
      files.length,
      reason: 'Referenz passt nicht zu den Dateien',
    );
    final problems = <String>[];
    for (var n = 0; n < files.length; n++) {
      final lines = files[n].readAsLinesSync();
      final head = lines.first.split(',');
      final rows = [
        for (final l in lines.skip(1))
          if (l.isNotEmpty) [for (final c in l.split(',')) double.parse(c)],
      ];
      List<double> col(String name) {
        final c = head.indexOf(name);
        return [for (final r in rows) r[c]];
      }

      // Wie die Referenz: Zeit der Datei + 5 s (Einschwingphase), Fensterende begrenzt.
      final t = [for (final r in rows) r[0] + 5.0];
      final blocks = [
        for (final h in head)
          if (RegExp(r'^[rg]\d+$').hasMatch(h)) PpgSeries(h, col(h)),
      ];
      final end = t.last;
      final window = PpgWindow(
        filterStart: 3,
        start: 5,
        end: math.min(65.0, end - 1.5),
        dataEnd: end,
      );
      final ref = refs[n];
      if (ref['error'] == true) {
        try {
          PpgAnalyzer.analyze(
            t,
            [PpgSeries('Rot', col('r')), PpgSeries('Grün', col('g'))],
            blocks,
            window,
          );
          problems.add('Datei $n: Referenz meldet Fehler, Port nicht');
        } on PpgInsufficientDataException {
          // beide lehnen die Datei ab
        }
        continue;
      }
      final set = PpgAnalyzer.analyze(
        t,
        [PpgSeries('Rot', col('r')), PpgSeries('Grün', col('g'))],
        blocks,
        window,
      );
      for (final d in comparePpgSet(set, ref)) {
        problems.add('Datei $n: $d');
      }
    }
    // Nur Abweichungen ausgeben, nie Werte.
    if (problems.isNotEmpty) print(problems.join('\n'));
    expect(problems, isEmpty);
  }, skip: skip);
}
