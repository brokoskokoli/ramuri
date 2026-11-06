import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/recalculation/recalculation_controller.dart';
import 'package:running_app/features/run/run_controller.dart';
import 'package:running_app/features/storage/deletion.dart';

final _t0 = DateTime.utc(2030, 3, 1, 22, 30);

/// Sitzung, deren Werte-Speicher nicht schreibt (Fehler der Berechnung).
class _ValuesFailSession implements StorageSession {
  _ValuesFailSession(this.s);
  final StorageSession s;
  bool fail = true;
  @override
  ComputedValueStore get values => fail ? _FailValues() : s.values;
  @override
  RawDataStore get rawData => s.rawData;
  @override
  SettingsStore get settings => s.settings;
  @override
  ProfileStore get profile => s.profile;
  @override
  RunStore get runs => s.runs;
  @override
  RunMarkerStore get markers => s.markers;
  @override
  PreprocessingStore get preprocessing => s.preprocessing;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _FailValues implements ComputedValueStore {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw const StorageException(StorageFailure.failed);
}

Future<({FakeClock clock, StorageSession session, FakeLocationSource location})>
_world() async {
  final session = await FakeStorage().open(Uint8List(32));
  await session.profile.save(
    const ProfileRecord(maxHeartRateBpm: 190, restingHeartRateBpm: 60),
  );
  return (
    clock: FakeClock(_t0, utcOffset: const Duration(hours: 2)),
    session: session,
    location: FakeLocationSource(),
  );
}

RunController _controller(
  FakeClock clock,
  StorageSession session,
  FakeLocationSource location, {
  Future<void> Function(Future<void> Function())? serialize,
}) => RunController(
  clock: clock,
  storage: session,
  location: location,
  tickEvery: const Duration(hours: 1),
  serialize: serialize,
);

Future<void> _runAndFinish(RunController c, FakeClock clock) async {
  await c.start();
  clock.advance(const Duration(minutes: 5));
  await c.finish();
}

void main() {
  test(
    'Ende: Werte werden berechnet, Versatz und lokaler Tag gespeichert',
    () async {
      final w = await _world();
      final c = _controller(w.clock, w.session, w.location);
      addTearDown(c.dispose);
      await _runAndFinish(c, w.clock);

      final run = (await w.session.runs.list()).single;
      expect(run.endedUtcOffset, const Duration(hours: 2));
      // 22:35 UTC + 2 h = 00:35 des Folgetags (lokaler Kalendertag).
      expect(dayOfRun(run), '2030-03-02');
      expect(c.calculationFailed, isFalse);
      expect(await w.session.values.read(ValueOwner.run(run.id)), hasLength(1));
      expect(
        await w.session.values.read(const ValueOwner.day('2030-03-02')),
        isNotEmpty,
      );
      expect(
        await w.session.settings.get(
          ValueCalculationService.calculationPendingKey,
        ),
        '',
      );
    },
  );

  test(
    'Fehler der Berechnung: Lauf bleibt, Meldung ohne Daten, Nachholen',
    () async {
      final w = await _world();
      final failing = _ValuesFailSession(w.session);
      final c = _controller(w.clock, failing, w.location);
      addTearDown(c.dispose);
      await _runAndFinish(c, w.clock);

      final run = (await w.session.runs.list()).single;
      expect(run.state, RunState.finished);
      expect(c.calculationFailed, isTrue);
      expect(c.phase, RecordingPhase.finished);
      expect(await w.session.values.read(ValueOwner.run(run.id)), isEmpty);
      expect(
        await w.session.settings.get(
          ValueCalculationService.calculationPendingKey,
        ),
        '${run.id}',
      );

      // Beim nächsten Start.
      await completePendingValueRefresh(w.session, w.clock);
      expect(await w.session.values.read(ValueOwner.run(run.id)), hasLength(1));
      expect(
        await w.session.settings.get(
          ValueCalculationService.calculationPendingKey,
        ),
        '',
      );
    },
  );

  test(
    'Berechnung nach dem Lauf wartet auf den Start (Nachholen beim Start)',
    () async {
      final w = await _world();
      final gate = Completer<void>();
      final service = RecalculationService(
        session: w.session,
        clock: w.clock,
        calculation: ValueCalculationService(
          session: w.session,
          clock: w.clock,
        ),
      );
      addTearDown(service.dispose);
      final recalc = RecalculationController(
        service,
        onStart: () => gate.future,
      );
      addTearDown(recalc.dispose);
      final started = recalc.start();

      final c = _controller(
        w.clock,
        w.session,
        w.location,
        serialize: recalc.exclusive,
      );
      addTearDown(c.dispose);
      final done = _runAndFinish(c, w.clock);

      // Der Start hängt: die Berechnung darf nicht laufen (kein Laufwert, kein
      // Merker), obwohl der Lauf längst beendet ist.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final run = (await w.session.runs.list()).single;
      expect(run.state, RunState.finished);
      expect(await w.session.values.read(ValueOwner.run(run.id)), isEmpty);
      expect(
        await w.session.settings.get(
          ValueCalculationService.calculationPendingKey,
        ),
        isNull,
      );

      gate.complete();
      await started;
      await done;
      expect(await w.session.values.read(ValueOwner.run(run.id)), hasLength(1));
    },
  );
}
