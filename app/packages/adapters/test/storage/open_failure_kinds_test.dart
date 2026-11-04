import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'support.dart';

/// Welche Art Fehler beim Öffnen als `unreadable` (sofortiger Neubeginn) gilt,
/// an echten Dateien über den Hintergrund-Isolate gemessen (WP02 fix4):
/// falscher Schlüssel, Müll, abgeschnittene und beschädigte erste Seite ergeben
/// SQLite-Code 26; ein Verzeichnis statt Datei Code 14. Nur 26 und 11 sind
/// `unreadable`, alles andere `openFailed`.
void main() {
  late Directory dir;
  late String path;
  late Uint8List bytes;
  setUp(() async {
    dir = tempDir();
    path = '${dir.path}/t.db';
    final s = await EncryptedStorage(path).open(testKey(0));
    await s.close();
    bytes = File(path).readAsBytesSync();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<StorageFailure> failureAt(String p, Uint8List key) async {
    try {
      await (await EncryptedStorage(p).open(key)).close();
    } on StorageException catch (e) {
      return e.failure;
    }
    fail('Öffnen hätte scheitern müssen');
  }

  test('falscher Schlüssel: unreadable', () async {
    expect(await failureAt(path, testKey(1)), StorageFailure.unreadable);
  });

  test(
    'beschädigte erste Seite, Müll und abgeschnittene Datei: unreadable',
    () async {
      final damaged = Uint8List.fromList(bytes);
      for (var i = 100; i < 600; i++) {
        damaged[i] ^= 0xff;
      }
      File('${dir.path}/damaged.db').writeAsBytesSync(damaged);
      File('${dir.path}/garbage.db').writeAsBytesSync(List.filled(5000, 7));
      File('${dir.path}/short.db').writeAsBytesSync(bytes.sublist(0, 100));
      for (final name in ['damaged', 'garbage', 'short']) {
        expect(
          await failureAt('${dir.path}/$name.db', testKey(0)),
          StorageFailure.unreadable,
          reason: name,
        );
      }
    },
  );

  test(
    'Verzeichnis statt Datei (CANTOPEN, Datei nicht schuld): openFailed',
    () async {
      Directory('${dir.path}/dir.db').createSync();
      expect(
        await failureAt('${dir.path}/dir.db', testKey(0)),
        StorageFailure.openFailed,
      );
    },
  );

  test(
    'storageFailureOf: unbekannter Fehler ist openFailed, nicht unreadable',
    () {
      expect(storageFailureOf(StateError('x')), StorageFailure.openFailed);
    },
  );

  test('storageFailureOf: SQLite-Code 11 (CORRUPT) und seine Unterarten sind '
      'unreadable, Code 10 (IOERR) und 13 (FULL) sind openFailed', () {
    expect(
      storageFailureOf(SqliteException(extendedResultCode: 11, message: 'x')),
      StorageFailure.unreadable,
    );
    expect(
      storageFailureOf(
        SqliteException(extendedResultCode: 267, message: 'x'),
      ), // CORRUPT_INDEX
      StorageFailure.unreadable,
    );
    expect(
      storageFailureOf(SqliteException(extendedResultCode: 26, message: 'x')),
      StorageFailure.unreadable,
    );
    expect(
      storageFailureOf(SqliteException(extendedResultCode: 10, message: 'x')),
      StorageFailure.openFailed,
    );
    expect(
      storageFailureOf(SqliteException(extendedResultCode: 13, message: 'x')),
      StorageFailure.openFailed,
    );
  });
}
