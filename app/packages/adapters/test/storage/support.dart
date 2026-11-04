import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

const String marker = 'SYNTHETISCHE-MARKE-4711';

Uint8List testKey([int seed = 0]) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 7 + seed) % 256));

Directory tempDir() => Directory.systemTemp.createTempSync('wp02a_');

bool containsText(File f, String needle) {
  if (!f.existsSync()) return false;
  final bytes = f.readAsBytesSync();
  final n = needle.codeUnits;
  outer:
  for (var i = 0; i + n.length <= bytes.length; i++) {
    for (var j = 0; j < n.length; j++) {
      if (bytes[i + j] != n[j]) continue outer;
    }
    return true;
  }
  return false;
}

Future<List<String>> pragmaRow(AppDatabase db, String pragma) async =>
    (await db.customSelect('PRAGMA $pragma').get())
        .map((r) => r.data.values.first.toString())
        .toList();

// Sonden müssen top-level sein, damit sie in den Isolate gehen.
bool noCipherLibrary(raw.Database db) => false;
bool plainFile(String path) => false;
