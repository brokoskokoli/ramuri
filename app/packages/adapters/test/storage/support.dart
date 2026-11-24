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

/// Baut `runs` in den Stand vor Version 10 zurück (ohne `mode` und `sport`).
/// SQLite kann `mode` nicht einzeln entfernen, weil der Tabellen-CHECK aus
/// Version 18 die Spalte nennt. Ids und Werte bleiben, Kindzeilen ebenso
/// (Fremdschlüssel aus, Verweise bleiben auf `runs`). [withOffset]: Stand ab
/// Version 3 mit `ended_utc_offset_s` und den beiden Triggern.
Future<void> rebuildRunsBeforeMode(
  Future<void> Function(String sql) exec, {
  required bool withOffset,
}) async {
  final offset = withOffset ? ', ended_utc_offset_s' : '';
  await exec('PRAGMA foreign_keys = OFF');
  await exec(
    'CREATE TABLE runs_before_mode ('
    'id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    "state TEXT NOT NULL CHECK (state IN ('active', 'paused', 'finished')), "
    'started_at_us INTEGER NOT NULL, ended_at_us INTEGER'
    '${withOffset ? ', ended_utc_offset_s INTEGER CHECK '
              '(ended_utc_offset_s BETWEEN -64800 AND 64800)' : ''})',
  );
  await exec(
    'INSERT INTO runs_before_mode (id, state, started_at_us, ended_at_us'
    '$offset) SELECT id, state, started_at_us, ended_at_us$offset FROM runs',
  );
  await exec('DROP TABLE runs');
  await exec('PRAGMA legacy_alter_table = ON');
  await exec('ALTER TABLE runs_before_mode RENAME TO runs');
  await exec('PRAGMA legacy_alter_table = OFF');
  await exec('PRAGMA foreign_keys = ON');
  if (!withOffset) return;
  for (final (name, event) in [
    ('runs_offset_insert', 'INSERT'),
    ('runs_offset_update', 'UPDATE'),
  ]) {
    await exec(
      'CREATE TRIGGER $name BEFORE $event ON runs '
      'WHEN NEW.ended_utc_offset_s IS NOT NULL AND NEW.ended_at_us IS NULL '
      "BEGIN SELECT RAISE(ABORT, 'offset without end'); END",
    );
  }
}
