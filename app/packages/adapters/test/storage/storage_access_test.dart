import 'dart:io';

import 'package:adapters/adapters.dart' hide RawSteps;
import 'package:core/core.dart';
import 'package:core/testing/storage_contract.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = tempDir();
    path = '${dir.path}/test.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // Derselbe Vertrag wie gegen den Fake in core (fake_storage_contract_test).
  group('Vertrag gegen die verschlüsselte Datenbank', () {
    for (final c in storageContractCases()) {
      test(c.name, () async {
        final storage = EncryptedStorage(path);
        final opened = <StorageSession>[];
        addTearDown(() async {
          for (final s in opened) {
            await s.close();
          }
        });
        await c.run(
          StorageContractHarness(
            open: () async {
              final s = await storage.open(testKey());
              opened.add(s);
              return s;
            },
            deleteRun: (id) async {
              final s = opened.last as EncryptedStorageSession;
              await s.database.customStatement(
                'DELETE FROM runs WHERE id = ?',
                [id],
              );
            },
          ),
        );
      });
    }
  });

  group('Fehlerwege (Falle 4): Ausnahme und Log ohne Marke', () {
    late List<String> logs;
    setUp(() {
      logs = [];
      final old = driftRuntimeOptions.debugPrint;
      driftRuntimeOptions.debugPrint = logs.add;
      addTearDown(() => driftRuntimeOptions.debugPrint = old);
    });

    Future<EncryptedStorageSession> open() async =>
        await EncryptedStorage(path).open(testKey()) as EncryptedStorageSession;

    Future<StorageException> catchStorage(Future<Object?> Function() f) async {
      try {
        await f();
      } on StorageException catch (e) {
        return e;
      }
      fail('keine StorageException');
    }

    RawBatch markerBatch() => RawBatch(
      steps: [RawSteps(time: t0Marker, source: marker, count: 1)],
    );

    test('Insert scheitert an der Datenbank (abgelehnt): Art rejected, Text und Logs ohne Marke', () async {
      final s = await open();
      final id = (await s.runs.create(startedAt: t0Marker)).id;
      // Beschränkung, die nur die Datenbank kennt (nicht die Dart-Prüfung).
      await s.database.customStatement(
        "CREATE TRIGGER fail_steps BEFORE INSERT ON raw_steps BEGIN SELECT RAISE(ABORT, 'x'); END",
      );
      // Positivkontrolle: Die rohe drift-Ausnahme trägt die Marke.
      Object? raw;
      try {
        await s.database.customStatement(
          "INSERT INTO raw_steps (run_id, time_us, source, state, step_count) VALUES ($id, 1, '$marker', 'present', 1)",
        );
      } catch (e) {
        raw = e;
      }
      expect(raw.toString(), contains(marker));

      final e = await catchStorage(() => s.rawData.append(id, markerBatch()));
      expect(e.failure, StorageFailure.rejected);
      expect(e.toString(), isNot(contains(marker)));
      expect(logs.join(), isNot(contains(marker)));
      expect((await s.rawData.read(id)).steps, isEmpty);
      await s.close();
    });

    test('Insert scheitert sonst (Tabelle fehlt): Art failed, Text und Logs ohne Marke', () async {
      final s = await open();
      final id = (await s.runs.create(startedAt: t0Marker)).id;
      await s.database.customStatement('DROP TABLE raw_steps');
      final e = await catchStorage(() => s.rawData.append(id, markerBatch()));
      expect(e.failure, StorageFailure.failed);
      expect(e.toString(), isNot(contains(marker)));
      expect(e.toString(), isNot(contains('raw_steps')));
      expect(logs.join(), isNot(contains(marker)));
      await s.close();
    });

    test(
      'Fehler in anderen Zugriffen gehen ebenfalls über die Übersetzung',
      () async {
        final s = await open();
        await s.database.customStatement('DROP TABLE settings');
        final e = await catchStorage(
          () => s.settings.set(marker, marker, at: t0Marker),
        );
        expect(e.failure, StorageFailure.failed);
        expect(e.toString(), isNot(contains(marker)));
        expect(logs.join(), isNot(contains(marker)));
        await s.close();
      },
    );
  });

  group('Rohdaten über die Zugriffsschicht', () {
    test('Der Port bietet nur Anhängen und Lesen; die Trigger sperren den Rest zusätzlich', () async {
      final s = await EncryptedStorage(
        path,
      ).open(testKey()) as EncryptedStorageSession;
      final id = (await s.runs.create(startedAt: t0Marker)).id;
      await s.rawData.append(
        id,
        RawBatch(
          steps: [RawSteps(time: t0Marker, source: 's', count: 1)],
        ),
      );
      await expectLater(
        s.database.customStatement("UPDATE raw_steps SET source = 'x'"),
        throwsA(anything),
      );
      expect((await s.rawData.read(id)).steps.single.value.source, 's');
      await s.close();
    });
  });
}

final t0Marker = DateTime.utc(2030, 1, 1);
