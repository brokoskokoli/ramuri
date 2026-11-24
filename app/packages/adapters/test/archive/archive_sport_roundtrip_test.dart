// SPDX-License-Identifier: GPL-3.0-only
// Archiv: Sporteinheiten (FR-0221) hin und zurück. Je Sportart eine
// abgeschlossene Einheit ohne Standort mit Puls und TRIMP, über die Ports
// angelegt, mit echter Kryptografie exportiert und in eine leere App
// importiert. Danach sind Art, Sportart, Puls und TRIMP gleich
// (docs/contracts/archive.md, Abschnitt 1, Schema 18). Alle Daten sind
// synthetisch.

import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart' hide ComputedValue, RawHeartRate;
import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../storage/support.dart' show testKey;

const String _password = 'synthetisches Testpasswort';

final _t0 = DateTime.utc(2026, 11, 2, 7);

ComputedValue _trimp(DateTime from, DateTime to, double v) => ComputedValue(
  key: trimpRunValueKey,
  value: v,
  unit: 'au',
  computedAt: to.add(const Duration(minutes: 1)),
  dataFrom: from,
  dataTo: to,
  measurementCount: 30,
  sources: const ['heart_rate'],
  method: 'trimp',
  methodVersion: 1,
  parameterVersion: 1,
  quality: ValueQuality.good,
  heartRateBasis: const HeartRateBasis(
    maxBpm: 190,
    restingBpm: 55,
    maxIsEstimated: false,
  ),
);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'Export und Reimport: je Sportart Art, Sportart, Puls und TRIMP gleich',
    () async {
      final key = testKey(11);
      final work = Directory.systemTemp.createTempSync('sportarchiv_');
      addTearDown(() => work.deleteSync(recursive: true));
      final source = await EncryptedStorage('${work.path}/source.db').open(key);
      addTearDown(() async {
        try {
          await source.close();
        } catch (_) {}
      });

      // Je Sportart eine Einheit von 30 min, Puls je Minute, eigener TRIMP.
      final ids = <OtherSport, int>{};
      for (final (i, sport) in OtherSport.values.indexed) {
        final start = _t0.add(Duration(days: i));
        final end = start.add(const Duration(minutes: 30));
        final run = await source.runs.create(
          startedAt: start,
          mode: RunMode.sport,
          sport: sport,
        );
        ids[sport] = run.id;
        await source.rawData.append(
          run.id,
          RawBatch(
            heartRates: [
              for (var m = 0; m < 30; m++)
                RawHeartRate(
                  time: start.add(Duration(minutes: m)),
                  source: 'sensor-$i',
                  bpm: 120 + i * 5 + m,
                  contact: SensorContact.good,
                ),
            ],
          ),
        );
        await source.runs.setState(
          run.id,
          RunState.finished,
          endedAt: end,
          endedUtcOffset: const Duration(hours: 1),
        );
        await source.values.createOriginals(ValueOwner.run(run.id), [
          _trimp(start, end, 40.25 + i),
        ]);
      }

      final exportDir = Directory('${work.path}/exports')..createSync();
      final handoff = FakeFileHandoff()..directory = exportDir.path;
      final f = await ArchiveExporter(
        source: DriftArchiveSource(
          (source as EncryptedStorageSession).database,
        ),
        handoff: handoff,
        clock: FakeClock(DateTime.utc(2026, 12, 5, 12)),
        cipherFactory: createArchiveCipherInWorker,
        pageSize: 7,
      ).export(password: _password);

      final activePath = '${work.path}/app/running_app.db';
      Directory('${work.path}/app').createSync();
      var target = await EncryptedStorage(activePath).open(key);
      addTearDown(() async {
        try {
          await target.close();
        } catch (_) {}
      });
      final files = FileDatabaseFiles(activePath);
      target = await ArchiveRestoreService(
        session: target,
        sink: DriftArchiveSink(
          storage: EncryptedStorage(files.importPath),
          key: () => Uint8List.fromList(key),
          files: files,
        ),
        files: files,
        cipherFactory: createArchiveCipherInWorker,
        clock: FakeClock(DateTime.utc(2026, 12, 5, 12)),
        reopen: () async =>
            target = await EncryptedStorage(activePath).open(key),
        serialize: <T>(Future<T> Function() a) => a(),
      ).restore(path: f.path!, password: _password);

      final t0 = await source.values.readRunValues({trimpRunValueKey});
      final t1 = await target.values.readRunValues({trimpRunValueKey});
      for (final sport in OtherSport.values) {
        final id = ids[sport]!;
        final a = (await source.runs.get(id))!;
        final b = (await target.runs.get(id))!;
        expect(b.mode, RunMode.sport, reason: sport.name);
        expect(b.sport, sport, reason: sport.name);
        expect(b.state, RunState.finished);
        expect(b.startedAt, a.startedAt);
        expect(b.endedAt, a.endedAt);
        final h0 = (await source.rawData.read(id)).heartRates;
        final h1 = (await target.rawData.read(id)).heartRates;
        expect(h1, hasLength(30));
        expect(
          [for (final h in h1) (h.value.time, h.value.bpm, h.value.contact)],
          [for (final h in h0) (h.value.time, h.value.bpm, h.value.contact)],
          reason: sport.name,
        );
        expect((await target.rawData.read(id)).positions, isEmpty);
        expect(
          t1[id]![trimpRunValueKey]!.value,
          t0[id]![trimpRunValueKey]!.value,
        );
        expect(
          t1[id]![trimpRunValueKey]!.value,
          40.25 + OtherSport.values.indexOf(sport),
        );
      }
    },
  );
}
