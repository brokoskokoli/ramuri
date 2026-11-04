import 'dart:typed_data';
import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'support.dart';

Future<StorageFailure> failureOf(Future<Object?> Function() f) async {
  try {
    await f();
  } on StorageException catch (e) {
    return e.failure;
  }
  fail('keine StorageException');
}

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = tempDir();
    path = '${dir.path}/test.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<EncryptedStorageSession> openNew([int seed = 0]) async =>
      await EncryptedStorage(path).open(testKey(seed))
          as EncryptedStorageSession;

  test('Hook lädt sqlite3mc auf dem Host', () {
    final db = raw.sqlite3.openInMemory();
    addTearDown(db.close);
    expect(db.select('PRAGMA cipher').first.values.first, 'chacha20');
  });

  test(
    'Öffnen sofort: Datei existiert mit Schlüssel, Meta-Tabelle da',
    () async {
      final s = await openNew();
      expect(File(path).existsSync(), isTrue);
      final rows = await s.database
          .customSelect('SELECT count(*) c FROM storage_meta')
          .get();
      expect(rows.single.data['c'], 0);
      await s.close();
    },
  );

  test('PRAGMAs der Verbindung werden zurückgelesen', () async {
    final s = await openNew();
    final db = s.database;
    expect(await pragmaRow(db, 'journal_mode'), ['wal']);
    expect(await pragmaRow(db, 'synchronous'), ['$synchronousFullValue']);
    expect(await pragmaRow(db, 'secure_delete'), ['1']);
    expect(await pragmaRow(db, 'foreign_keys'), ['1']);
    expect(await pragmaRow(db, 'temp_store'), ['$tempStoreMemoryValue']);
    expect(await pragmaRow(db, 'cipher'), ['chacha20']);
    await s.close();
  });

  test('richtiger Schlüssel öffnet erneut, Daten bleiben', () async {
    var s = await openNew();
    await s.database.customStatement(
      "INSERT INTO storage_meta VALUES ('k','v')",
    );
    await s.close();
    s = await openNew();
    final rows = await s.database
        .customSelect('SELECT value FROM storage_meta')
        .get();
    expect(rows.single.data['value'], 'v');
    await s.close();
  });

  test(
    'falscher Schlüssel scheitert als unreadable, ohne Schlüssel im Text',
    () async {
      await (await openNew()).close();
      final wrong = testKey(1);
      try {
        await EncryptedStorage(path).open(wrong);
        fail('Öffnen hätte scheitern müssen');
      } on StorageException catch (e) {
        expect(e.failure, StorageFailure.unreadable);
        expect(e.toString(), isNot(contains(hexOfKey(wrong))));
      }
    },
  );

  test('ohne Schlüssel und mit falscher Länge scheitert fail-closed', () async {
    final s = EncryptedStorage(path);
    expect(
      await failureOf(() => s.open(Uint8List(0))),
      StorageFailure.encryptionNotActive,
    );
    expect(
      await failureOf(() => s.open(Uint8List(31))),
      StorageFailure.encryptionNotActive,
    );
    expect(
      File(path).existsSync(),
      isFalse,
      reason: 'ohne Schlüssel entsteht keine Datei',
    );
  });

  test(
    'Datei ohne Schlüssel mit roher sqlite3-Bibliothek nicht lesbar',
    () async {
      await (await openNew()).close();
      final db = raw.sqlite3.open(path);
      addTearDown(db.close);
      expect(
        () => db.select('SELECT * FROM storage_meta'),
        throwsA(isA<raw.SqliteException>()),
      );
    },
  );

  group('Marken (Falle 1)', () {
    test(
      'Positivkontrolle: unverschlüsselt stehen Marke in WAL und Hauptdatei',
      () {
        final plain = '${dir.path}/plain.db';
        final db = raw.sqlite3.open(plain);
        db.execute('PRAGMA journal_mode = WAL');
        db.execute('PRAGMA wal_autocheckpoint = 0');
        db.execute('CREATE TABLE t (v TEXT)');
        db.execute("INSERT INTO t VALUES ('$marker')");
        final wal = File('$plain-wal');
        expect(
          wal.lengthSync(),
          greaterThan(0),
          reason: 'WAL muss Frames enthalten',
        );
        expect(containsText(wal, marker), isTrue);
        db.close(); // Checkpoint beim Schließen
        expect(containsText(File(plain), marker), isTrue);
      },
    );

    test(
      'verschlüsselt: Marke weder in WAL (mit Frames) noch in Hauptdatei',
      () async {
        final s = await openNew();
        await s.database.customStatement(
          "INSERT INTO storage_meta VALUES ('m','$marker')",
        );
        final wal = File('$path-wal');
        expect(
          wal.existsSync() && wal.lengthSync() > 0,
          isTrue,
          reason: 'WAL muss beim Suchen Frames enthalten',
        );
        expect(containsText(wal, marker), isFalse);
        // Lesen bestätigt, dass die Marke wirklich gespeichert ist.
        final rows = await s.database
            .customSelect('SELECT value FROM storage_meta')
            .get();
        expect(rows.single.data['value'], marker);
        await s.close();
        expect(containsText(File(path), marker), isFalse);
        expect(containsText(File('$path-wal'), marker), isFalse);
      },
    );
  });

  group('fail-closed per Sonde', () {
    test(
      'Bibliothek ohne Verschlüsselung: öffnet nicht, Datei bleibt ohne Inhalt',
      () async {
        final s = EncryptedStorage(path, libraryProbe: noCipherLibrary);
        expect(
          await failureOf(() => s.open(testKey())),
          StorageFailure.encryptionNotActive,
        );
        final f = File(path);
        expect(!f.existsSync() || f.lengthSync() == 0, isTrue);
      },
    );

    test('Datei ohne Verschlüsselung auf der Platte: öffnet nicht', () async {
      final s = EncryptedStorage(path, fileProbe: plainFile);
      expect(
        await failureOf(() => s.open(testKey())),
        StorageFailure.encryptionNotActive,
      );
    });

    test('echte Kopfprüfung erkennt Klartextdatei', () {
      final plain = '${dir.path}/plain.db';
      raw.sqlite3.open(plain)
        ..execute('CREATE TABLE t (v TEXT)')
        ..close();
      expect(defaultFileEncryptedProbe(plain), isFalse);
    });

    test('echte Kopfprüfung erkennt verschlüsselte Datei', () async {
      await (await openNew()).close();
      expect(defaultFileEncryptedProbe(path), isTrue);
    });

    test('Messung: PRAGMA key mit leerem Wert lässt sqlite3mc unverschlüsselt (Falle 3)', () {
      final p = '${dir.path}/empty.db';
      final db = raw.sqlite3.open(p);
      expect(
        () => db.execute("PRAGMA hexkey = ''"),
        throwsA(isA<raw.SqliteException>()),
        reason: 'hexkey mit leerem Wert wird abgelehnt',
      );
      db.execute("PRAGMA key = ''");
      expect(
        db.select('PRAGMA cipher').first.values.first,
        'chacha20',
        reason: 'cipher belegt nur die Bibliothek',
      );
      db.execute('CREATE TABLE t (v TEXT)');
      db.close();
      expect(defaultFileEncryptedProbe(p), isFalse);
    });
  });

  group('Fehlertexte (Falle 4)', () {
    test('fehlschlagendes Insert: Rohfehler trägt die Marke, die Übersetzung nicht', () async {
      final logs = <String>[];
      final old = driftRuntimeOptions.debugPrint;
      driftRuntimeOptions.debugPrint = logs.add;
      addTearDown(() => driftRuntimeOptions.debugPrint = old);

      final s = await openNew();
      await s.database.customStatement(
        "INSERT INTO storage_meta VALUES ('d','x')",
      );
      Object? raw1;
      try {
        await s.database.customStatement(
          "INSERT INTO storage_meta VALUES ('d','$marker')",
        );
      } catch (e) {
        raw1 = e;
      }
      expect(raw1, isNotNull);
      // Beleg: so kommt der Fehler aus dem Hintergrund-Isolate an.
      expect(raw1.toString(), contains(marker));
      final translated = translateStorageError(raw1!);
      expect(translated.failure, StorageFailure.rejected);
      expect(translated.toString(), isNot(contains(marker)));
      expect(logs.join(), isNot(contains(marker)));
      await s.close();
    });

    test('Öffnen mit falschem Schlüssel: kein Schlüssel, keine Marke in Text und Logs', () async {
      final logs = <String>[];
      final old = driftRuntimeOptions.debugPrint;
      driftRuntimeOptions.debugPrint = logs.add;
      addTearDown(() => driftRuntimeOptions.debugPrint = old);
      await (await openNew()).close();
      final wrong = testKey(5);
      try {
        await EncryptedStorage(path).open(wrong);
        fail('hätte scheitern müssen');
      } on StorageException catch (e) {
        expect(e.toString(), isNot(contains(hexOfKey(wrong))));
      }
      expect(logs.join(), isNot(contains(hexOfKey(wrong))));
    });
  });
}
