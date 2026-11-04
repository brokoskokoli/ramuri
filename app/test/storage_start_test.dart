import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/storage/storage_start.dart';

import 'storage_world.dart';

void main() {
  final k0 = keyOf(1);
  final k1 = keyOf(2);

  test('keine Datei, kein Schlüssel: neuer Schlüssel, bereit', () async {
    final w = World();
    final c = w.controller();
    expect(c.state, isA<StorageLoading>());
    await c.start();
    expect(c.state, isA<StorageReady>());
    expect(await w.keys.read(storageKeyName), isNotNull);
    expect(w.files.present, isTrue);
  });

  test('Datei und passender Schlüssel: bereit mit den alten Daten', () async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k0);
    final c = w.controller();
    await c.start();
    final s = (c.state as StorageReady).session;
    expect(await s.runs.list(), hasLength(1));
  });

  test('Schlüssel fehlt: nicht zu öffnen, nichts verändert', () async {
    final w = World();
    await w.seed(fileKey: k0);
    final c = w.controller();
    await c.start();
    expect(
      (c.state as StorageNotOpenableState).cause,
      StorageNotOpenableCause.keyMissing,
    );
    expect(w.log, isEmpty, reason: 'kein verändernder Schritt');
    expect(w.files.present, isTrue);
    expect(w.inner.openSessions, 1, reason: 'nur das Anlegen im Test');
  });

  test('Schlüssel unbrauchbar: nicht zu öffnen, nichts verändert', () async {
    final w = World();
    await w.seed(fileKey: k0);
    w.keys.put(storageKeyName, Uint8List(5));
    final c = w.controller();
    await c.start();
    expect(
      (c.state as StorageNotOpenableState).cause,
      StorageNotOpenableCause.keyMalformed,
    );
    expect(w.log, isEmpty);
  });

  test('Schlüsselablage-Fehler: nicht zu öffnen, nichts verändert', () async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k0);
    w.keys.failWith = 'defekt';
    final c = w.controller();
    await c.start();
    expect(
      (c.state as StorageNotOpenableState).cause,
      StorageNotOpenableCause.keyStoreError,
    );
    expect(w.log, isEmpty);
    expect(w.files.present, isTrue);
  });

  test('falscher Schlüssel und beschädigte Datei: nicht lesbar', () async {
    final w = World();
    await w.seed(fileKey: k0, storedKey: k1);
    final c = w.controller();
    await c.start();
    expect(
      (c.state as StorageNotOpenableState).cause,
      StorageNotOpenableCause.unreadable,
    );
    expect(w.log, isEmpty);

    final w2 = World();
    await w2.seed(fileKey: k0, storedKey: k0);
    w2.inner.corrupted = true;
    final c2 = w2.controller();
    await c2.start();
    expect(
      (c2.state as StorageNotOpenableState).cause,
      StorageNotOpenableCause.unreadable,
    );
  });

  test(
    'Pfad nicht ermittelbar: nur erneut versuchen, kein Neubeginn',
    () async {
      final w = World();
      final c = StorageStartController(
        keyStore: w.keys,
        generateKey: () => k0,
        wire: () async => throw StateError('kein Pfad'),
      );
      await c.start();
      final s = c.state as StorageNotOpenableState;
      expect(s.cause, StorageNotOpenableCause.locationError);
      expect(s.canReset, isFalse);
      await c.resetStorage();
      expect(identical(c.state, s), isTrue);
    },
  );

  group('Verschlüsselung nicht aktiv', () {
    test('mit vorhandener Datei: eigener Zustand, Datei unberührt', () async {
      final w = World();
      await w.seed(fileKey: k0, storedKey: k0);
      w.inner.encryptionActive = false;
      final c = w.controller();
      await c.start();
      expect(c.state, isA<StorageEncryptionInactive>());
      expect(w.log, isEmpty);
      expect(w.files.present, isTrue);
      expect(w.files.deleteCalls, 0);
    });

    test('kein Neubeginn aus diesem Zustand', () async {
      final w = World();
      await w.seed(fileKey: k0, storedKey: k0);
      w.inner.encryptionActive = false;
      final c = w.controller();
      await c.start();
      await c.resetStorage();
      expect(c.state, isA<StorageEncryptionInactive>());
      expect(w.files.deleteCalls, 0);
      expect(w.log, isEmpty);
    });

    test('ohne Datei: kein Zugriff auf Inhalte, keine Datei', () async {
      final w = World();
      w.inner.encryptionActive = false;
      final c = w.controller();
      await c.start();
      expect(c.state, isA<StorageEncryptionInactive>());
      expect(w.files.present, isFalse);
    });

    test('erneut versuchen öffnet, sobald aktiv', () async {
      final w = World();
      await w.seed(fileKey: k0, storedKey: k0);
      w.inner.encryptionActive = false;
      final c = w.controller();
      await c.start();
      w.inner.encryptionActive = true;
      await c.start();
      expect(c.state, isA<StorageReady>());
    });
  });

  group('Neubeginn', () {
    test('nur aus "nicht zu öffnen"; sonst nichts', () async {
      final w = World();
      final c = w.controller();
      await c.resetStorage(); // Zustand "laden"
      expect(w.files.deleteCalls, 0);
      await w.seed(fileKey: k0, storedKey: k0);
      await c.start();
      expect(c.state, isA<StorageReady>());
      await c.resetStorage(); // bereit: darf die Daten nicht löschen
      expect(w.files.deleteCalls, 0);
      expect(w.files.present, isTrue);
    });

    test(
      'falscher Schlüssel: Datei weg, neuer Schlüssel, leer bereit',
      () async {
        final w = World();
        await w.seed(fileKey: k0, storedKey: k1);
        final c = w.controller();
        await c.start();
        await c.resetStorage();
        final s = (c.state as StorageReady).session;
        expect(await s.runs.list(), isEmpty);
        expect(await s.settings.get('k'), isNull);
        final stored = await w.keys.read(storageKeyName);
        expect(sameBytes(stored, k1), isFalse);
        expect(sameBytes(stored, k0), isFalse);
        expect(w.log, [
          'Dateien löschen',
          'Schlüssel löschen',
          'Schlüssel schreiben',
          'Datei anlegen',
        ], reason: 'Reihenfolge');
        expect(w.violations, isEmpty);
      },
    );

    test('Schlüssel fehlt: Neubeginn legt neuen Schlüssel erst nach dem Löschen an', () async {
      final w = World();
      await w.seed(fileKey: k0);
      final c = w.controller();
      await c.start();
      await c.resetStorage();
      expect(c.state, isA<StorageReady>());
      expect(w.log.first, 'Dateien löschen');
      expect(w.violations, isEmpty);
    });

    for (var crash = 1; crash <= 4; crash++) {
      test(
        'Abbruch vor Schritt $crash: nie neuer Schlüssel neben alter Datei',
        () async {
          final w = World();
          await w.seed(fileKey: k0, storedKey: k1);
          final c = w.controller();
          await c.start();
          w.steps = 0;
          w.log.clear();
          w.crashAt = crash;
          await c.resetStorage();
          expect(w.violations, isEmpty);
          // Zustand nach dem Abbruch: Wieder anlaufen mit einer neuen Instanz.
          w.crashAt = null;
          final again = w.controller();
          await again.start();
          expect(w.violations, isEmpty);
          if (crash == 1) {
            // Löschen kam nicht zustande: alles wie vorher, Fehler gezeigt.
            expect(
              (c.state as StorageNotOpenableState).resetProblem,
              StorageResetProblem.filesNotDeleted,
            );
            expect(w.files.present, isTrue);
            expect(w.oldFileKey, k0);
            expect(sameBytes(await w.keys.read(storageKeyName), k1), isTrue);
            expect(
              (again.state as StorageNotOpenableState).cause,
              StorageNotOpenableCause.unreadable,
            );
          } else {
            // Alte Datei ist weg; der nächste Start endet leer und bereit.
            final s = (again.state as StorageReady).session;
            expect(await s.runs.list(), isEmpty);
          }
        },
      );
    }

    test(
      'Löschen schlägt fehl: Fehler, kein neuer Schlüssel, Datei bleibt',
      () async {
        final w = World();
        await w.seed(fileKey: k0, storedKey: k1);
        final c = w.controller();
        await c.start();
        w.files.failDelete = true;
        await c.resetStorage();
        final s = c.state as StorageNotOpenableState;
        expect(s.resetProblem, StorageResetProblem.filesNotDeleted);
        expect(s.busy, isFalse);
        expect(sameBytes(await w.keys.read(storageKeyName), k1), isTrue);
        expect(w.log, ['Dateien löschen'], reason: 'kein Schlüsselschritt');
        expect(w.files.present, isTrue);
      },
    );

    test('Datei nach dem Löschen noch da: wie Fehler beim Löschen', () async {
      final w = World();
      await w.seed(fileKey: k0, storedKey: k1);
      final c = w.controller();
      await c.start();
      w.files.stubborn = true;
      await c.resetStorage();
      expect(
        (c.state as StorageNotOpenableState).resetProblem,
        StorageResetProblem.filesNotDeleted,
      );
      expect(sameBytes(await w.keys.read(storageKeyName), k1), isTrue);
      expect(w.log, ['Dateien löschen']);
    });
  });
}
