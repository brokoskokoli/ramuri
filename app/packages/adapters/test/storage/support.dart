import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart' show pumpEventQueue;
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

/// Fängt die Log-Ausgabe des Hintergrund-Isolate von drift ab. `debugPrint` und
/// Zonen des Test-Isolate sehen sie nicht; darum leitet [setup] (als
/// `isolateSetup` übergeben) `driftRuntimeOptions.debugPrint` dort auf einen
/// Port um.
class IsolateLogs {
  IsolateLogs() {
    _port.listen((m) => _lines.add(m as String));
  }

  final _port = ReceivePort();
  final _lines = <String>[];

  FutureOr<void> Function() get setup => _redirect(_port.sendPort);

  /// Alles bisher Angekommene (wartet kurz auf Nachrichten in der Schlange).
  Future<String> text() async {
    await pumpEventQueue();
    return _lines.join('\n');
  }

  void close() => _port.close();
}

FutureOr<void> Function() _redirect(SendPort port) =>
    () => driftRuntimeOptions.debugPrint = (String s) => port.send(s);
