// SEC-0004: „Alles löschen“ und „Lauf löschen“ leeren die Export- und
// Importdateien der Übergabe (FileHandoff.clearExports). Synthetische Daten.
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/storage/deletion.dart';

import 'history_summary_test.dart' show openHistory, seedRun, started;
import 'run_detail_test.dart' show openDetail, seedDetailRun;

Future<void> _direct(Future<void> Function() action) => action();

final _key = Uint8List.fromList(List.filled(storageKeyLength, 7));

/// Merkt sich je Aufruf von [clearExports], ob der Lauf da schon gelöscht war.
class _ObservingHandoff extends FakeFileHandoff {
  _ObservingHandoff(this.session, this.runId);
  final StorageSession session;
  final int runId;
  final List<bool> runGoneAtClear = [];

  @override
  Future<ExportClearResult> clearExports({bool unlessSharing = false}) async {
    runGoneAtClear.add(await session.runs.get(runId) == null);
    return super.clearExports(unlessSharing: unlessSharing);
  }
}

/// Sitzung, deren [deleteRun] scheitert, ohne etwas zu löschen.
class _FailingDeleteSession implements StorageSession {
  _FailingDeleteSession(this.inner);
  final StorageSession inner;
  @override
  RunStore get runs => inner.runs;
  @override
  RunMarkerStore get markers => inner.markers;
  @override
  RawDataStore get rawData => inner.rawData;
  @override
  PreprocessingStore get preprocessing => inner.preprocessing;
  @override
  RatedSectionStore get sections => inner.sections;
  @override
  ComputedValueStore get values => inner.values;
  @override
  ProfileStore get profile => inner.profile;
  @override
  SettingsStore get settings => inner.settings;
  @override
  KnownDeviceStore get devices => inner.devices;
  @override
  ConsentStore get consents => inner.consents;
  @override
  RunSubjectiveStore get subjective => inner.subjective;
  @override
  ManualTrainingStore get manualTrainings => inner.manualTrainings;
  @override
  Future<void> deleteRun(int runId) async =>
      throw const StorageException(StorageFailure.failed);
  @override
  Future<void> deleteAll() => inner.deleteAll();
  @override
  Future<void> close() => inner.close();
}

final _deletedNotErased = throwsA(
  isA<StorageException>().having(
    (e) => e.failure,
    'failure',
    StorageFailure.deletedNotErased,
  ),
);

void main() {
  group('Alles löschen (echte Verdrahtung, SEC-0004)', () {
    late Directory dir;
    late String dbPath;
    late EncryptedMapTileStore map;
    late FakeFileHandoff handoff;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('delete_exports_');
      dbPath = '${dir.path}/running_app.db';
      map = EncryptedMapTileStore(
        directory: () async => dir.path,
        key: () async => _key,
      );
      handoff = FakeFileHandoff();
    });
    tearDown(() async {
      await map.close();
      dir.deleteSync(recursive: true);
    });

    String mapFile() => '${dir.path}/$mapCacheFileName';

    test('räumt Kartenspeicher und Exportdateien ab', () async {
      await map.write('map:/a', Uint8List.fromList(List.filled(100, 5)));
      final session = await storageWiringFor(
        dbPath,
        map,
        handoff,
      ).storage.open(_key);
      expect(await runDeletion(session.deleteAll), DeletionResult.deleted);
      await session.close();
      expect(File(mapFile()).existsSync(), isFalse);
      // Immer leeren, auch während einer offenen Übergabe.
      expect(handoff.clearCalls, [false]);
    });

    test(
      'Exportdateien nicht leer: deletedNotErased, Daten trotzdem weg',
      () async {
        await map.write('map:/a', Uint8List.fromList(List.filled(100, 5)));
        handoff.nextClear = ExportClearResult.failed;
        final session = await encryptedStorageFor(
          dbPath,
          map,
          handoff,
        ).open(_key);
        await session.settings.set('k', 'v', at: DateTime.utc(2030));
        await expectLater(session.deleteAll(), _deletedNotErased);
        expect(await session.settings.get('k'), isNull);
        expect(File(mapFile()).existsSync(), isFalse);
        expect(
          await runDeletion(session.deleteAll),
          DeletionResult.deletedNotErased,
        );
        await session.close();
      },
    );

    test(
      'ein „behalten wegen Teilen“ gilt bei Alles löschen nicht als leer',
      () async {
        handoff.nextClear = ExportClearResult.keptWhileSharing;
        final session = await encryptedStorageFor(
          dbPath,
          map,
          handoff,
        ).open(_key);
        await expectLater(session.deleteAll(), _deletedNotErased);
        await session.close();
      },
    );

    test(
      'Kartenspeicher scheitert: Exportdateien werden trotzdem geleert',
      () async {
        final clear = deleteAllOutsideDatabase(
          () async => throw const FileSystemException('x'),
          handoff,
        );
        await expectLater(clear(), throwsA(isA<FileSystemException>()));
        expect(handoff.clearCalls, [false]);
      },
    );
  });

  group('Lauf löschen (SEC-0004)', () {
    late FakeStorage storage;
    late StorageSession s;
    final clock = FakeClock(DateTime.utc(2030, 6));

    setUp(() async {
      storage = FakeStorage();
      s = await storage.open(_key);
    });

    test(
      'leert nach erfolgreichem Löschen, nur ohne offene Übergabe',
      () async {
        final id = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
        final handoff = _ObservingHandoff(s, id);
        await deleteRunAndRefresh(
          s,
          clock,
          id,
          serialize: _direct,
          exports: handoff,
        );
        expect(handoff.clearCalls, [true]);
        expect(handoff.runGoneAtClear, [true]);
      },
    );

    test('Löschen scheitert: kein Leeren', () async {
      final id = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
      final handoff = FakeFileHandoff();
      await expectLater(
        deleteRunAndRefresh(
          _FailingDeleteSession(s),
          clock,
          id,
          serialize: _direct,
          exports: handoff,
        ),
        throwsA(isA<StorageException>()),
      );
      expect(await s.runs.get(id), isNotNull);
      expect(handoff.clearCalls, isEmpty);
    });

    test('gelöscht, Checkpoint scheitert: trotzdem leeren', () async {
      final id = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
      final handoff = FakeFileHandoff();
      storage.checkpointIncomplete = true;
      await expectLater(
        deleteRunAndRefresh(s, clock, id, serialize: _direct, exports: handoff),
        _deletedNotErased,
      );
      expect(handoff.clearCalls, [true]);
    });

    test('Leeren scheitert: deletedNotErased, Lauf bleibt gelöscht', () async {
      final id = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
      final handoff = FakeFileHandoff()..nextClear = ExportClearResult.failed;
      await expectLater(
        deleteRunAndRefresh(s, clock, id, serialize: _direct, exports: handoff),
        _deletedNotErased,
      );
      expect(await s.runs.get(id), isNull);
      expect(
        await runDeletion(() async {
          final other = (await s.runs.create(startedAt: DateTime.utc(2031))).id;
          await deleteRunAndRefresh(
            s,
            clock,
            other,
            serialize: _direct,
            exports: handoff,
          );
        }),
        DeletionResult.deletedNotErased,
      );
    });

    test(
      'Übergabe offen: Dateien bleiben, das Löschen gilt als vollständig',
      () async {
        final id = (await s.runs.create(startedAt: DateTime.utc(2030))).id;
        final handoff = FakeFileHandoff()
          ..nextClear = ExportClearResult.keptWhileSharing;
        expect(
          await runDeletion(
            () => deleteRunAndRefresh(
              s,
              clock,
              id,
              serialize: _direct,
              exports: handoff,
            ),
          ),
          DeletionResult.deleted,
        );
        expect(handoff.clearCalls, [true]);
      },
    );
  });

  group('Lauf löschen in der App', () {
    testWidgets('im Detail: leert die Exportdateien ohne offene Übergabe', (
      tester,
    ) async {
      final d = await started(tester);
      final id = await openDetail(
        tester,
        d,
        () => seedDetailRun(d.session, DateTime.utc(2030, 1, 1, 8)),
      );
      expect(d.fileHandoff.clearCalls, isEmpty);
      await tester.tap(find.byKey(const Key('detail_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lauf löschen').last);
      await tester.pumpAndSettle();
      expect(await d.session.runs.get(id), isNull);
      expect(d.fileHandoff.clearCalls, [true]);
    });

    testWidgets('am Eintrag der Historie: leert die Exportdateien', (
      tester,
    ) async {
      final d = await started(tester);
      final id = await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await openHistory(d, tester);
      await tester.tap(find.byKey(Key('history_delete_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lauf löschen').last);
      await tester.pumpAndSettle();
      expect(await d.session.runs.get(id), isNull);
      expect(d.fileHandoff.clearCalls, [true]);
    });

    testWidgets('Abbrechen: kein Leeren', (tester) async {
      final d = await started(tester);
      final id = await seedRun(d.session, DateTime.utc(2030, 1, 1, 8));
      await openHistory(d, tester);
      await tester.tap(find.byKey(Key('history_delete_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(d.fileHandoff.clearCalls, isEmpty);
    });
  });
}
