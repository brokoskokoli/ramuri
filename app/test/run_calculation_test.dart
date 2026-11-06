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

/// Sitzung, deren Pausen-Marker beim ersten Öffnen einmal nicht schreibt.
class _GapFailOnceSession extends _ValuesFailSession {
  _GapFailOnceSession(super.s) {
    super.fail = false;
  }
  bool failed = false;
  @override
  RunMarkerStore get markers => _OnceMarkers(s.markers, this);
}

class _OnceMarkers implements RunMarkerStore {
  _OnceMarkers(this.inner, this.owner);
  final RunMarkerStore inner;
  final _GapFailOnceSession owner;
  @override
  Future<int> openGap(int runId, RunGapKind kind, DateTime at) {
    if (!owner.failed) {
      owner.failed = true;
      throw const StorageException(StorageFailure.failed);
    }
    return inner.openGap(runId, kind, at);
  }

  @override
  Future<void> addLap(int runId, StoredLap lap) => inner.addLap(runId, lap);
  @override
  Future<List<StoredLap>> laps(int runId) => inner.laps(runId);
  @override
  Future<void> closeGap(int gapId, DateTime end) => inner.closeGap(gapId, end);
  @override
  Future<List<StoredGap>> gaps(int runId) => inner.gaps(runId);
}

/// Hält das Schreiben des ersten Merkers fest, bis [release] kommt (Berechnung
/// nach dem Lauf steht dann mitten in der Reihe).
class _HoldSettingsSession extends _ValuesFailSession {
  _HoldSettingsSession(super.s) {
    super.fail = false;
  }
  final reached = Completer<void>();
  final release = Completer<void>();
  @override
  SettingsStore get settings => _HoldSettings(s.settings, this);
}

class _HoldSettings implements SettingsStore {
  _HoldSettings(this.inner, this.owner);
  final SettingsStore inner;
  final _HoldSettingsSession owner;
  @override
  Future<String?> get(String key) => inner.get(key);
  @override
  Future<Map<String, String>> all() => inner.all();
  @override
  Future<void> set(String key, String value, {required DateTime at}) async {
    if (key == ValueCalculationService.calculationPendingKey &&
        !owner.reached.isCompleted) {
      owner.reached.complete();
      await owner.release.future;
    }
    await inner.set(key, value, at: at);
  }
}

/// Zählt, wann confirm tatsächlich läuft.
class _CountingService extends RecalculationService {
  _CountingService({
    required super.session,
    required super.clock,
    required super.calculation,
  });
  int confirms = 0;
  @override
  Future<RecalculationResult> confirm(RecalculationOffer offer) {
    confirms++;
    return super.confirm(offer);
  }
}

/// Ein beendeter Lauf mit Laufwert, damit eine Profiländerung etwas anbietet.
Future<void> _seedValuedRun(
  FakeClock clock,
  StorageSession session,
  FakeLocationSource location,
) async {
  final c = _controller(clock, session, location);
  await _runAndFinish(c, clock);
  c.dispose();
  clock.advance(const Duration(hours: 1));
}

Future<void> _pump() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
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

  test(
    'Vorübergehender Schreibfehler im Lauf: nach dem Ende entsteht der Wert',
    () async {
      final w = await _world();
      final flaky = _GapFailOnceSession(w.session);
      final c = _controller(w.clock, flaky, w.location);
      addTearDown(c.dispose);
      await c.start();
      w.clock.advance(const Duration(minutes: 2));
      await c.pause();
      expect(flaky.failed, isTrue, reason: 'Der Fehler muss im Lauf passieren');
      w.clock.advance(const Duration(minutes: 1));
      await c.resume();
      w.clock.advance(const Duration(minutes: 2));
      await c.finish();

      expect(c.phase, RecordingPhase.finished);
      final run = (await w.session.runs.list()).single;
      expect(run.state, RunState.finished);
      expect(c.calculationFailed, isFalse);
      expect(await w.session.values.read(ValueOwner.run(run.id)), hasLength(1));
    },
  );

  test(
    'App-Ende während Warten in der Reihe: nach dem Neustart ist der Wert da',
    () async {
      final w = await _world();
      // Die Reihe hängt für immer (Start nicht fertig); die App wird beendet.
      final never = Completer<void>();
      final c = _controller(
        w.clock,
        w.session,
        w.location,
        serialize: (action) => never.future,
      );
      addTearDown(c.dispose);
      unawaited(_runAndFinish(c, w.clock));
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      final run = (await w.session.runs.list()).single;
      expect(run.state, RunState.finished);
      expect(await w.session.values.read(ValueOwner.run(run.id)), isEmpty);
      // Es steht kein Merker: die Berechnung kam nie in die Reihe.
      expect(
        await w.session.settings.get(
          ValueCalculationService.calculationPendingKey,
        ),
        isNull,
      );

      // Neustart: Nachholen findet den beendeten Lauf ohne Laufwert.
      await completePendingValueRefresh(w.session, w.clock);
      expect(await w.session.values.read(ValueOwner.run(run.id)), hasLength(1));
    },
  );

  test('confirm wartet auf den Start (Nachholen beim Start)', () async {
    final w = await _world();
    await _seedValuedRun(w.clock, w.session, w.location);
    final gate = Completer<void>();
    final service = _CountingService(
      session: w.session,
      clock: w.clock,
      calculation: ValueCalculationService(session: w.session, clock: w.clock),
    );
    addTearDown(service.dispose);
    final recalc = RecalculationController(service, onStart: () => gate.future);
    addTearDown(recalc.dispose);
    final started = recalc.start();
    await service.profileChanged(
      before: const ProfileRecord(
        maxHeartRateBpm: 190,
        restingHeartRateBpm: 60,
      ),
      after: const ProfileRecord(maxHeartRateBpm: 180, restingHeartRateBpm: 60),
    );
    await _pump();
    expect(recalc.offer, isNotNull);

    final confirming = recalc.confirm();
    await _pump();
    expect(recalc.busy, isTrue);
    expect(
      service.confirms,
      0,
      reason: 'confirm darf nicht vor dem Start laufen',
    );

    gate.complete();
    await started;
    await confirming;
    expect(service.confirms, 1);
    expect(recalc.phase, RecalculationPhase.done);
  });

  test('confirm läuft nicht parallel zur Berechnung nach dem Lauf', () async {
    final w = await _world();
    await _seedValuedRun(w.clock, w.session, w.location);
    final held = _HoldSettingsSession(w.session);
    final service = _CountingService(
      session: w.session,
      clock: w.clock,
      calculation: ValueCalculationService(session: w.session, clock: w.clock),
    );
    addTearDown(service.dispose);
    final recalc = RecalculationController(service);
    addTearDown(recalc.dispose);
    await recalc.start();
    final c = _controller(
      w.clock,
      held,
      w.location,
      serialize: recalc.exclusive,
    );
    addTearDown(c.dispose);
    final finishing = _runAndFinish(c, w.clock);
    await held.reached.future; // Berechnung steht mitten in der Reihe.

    await service.profileChanged(
      before: const ProfileRecord(
        maxHeartRateBpm: 190,
        restingHeartRateBpm: 60,
      ),
      after: const ProfileRecord(maxHeartRateBpm: 180, restingHeartRateBpm: 60),
    );
    await _pump();
    final confirming = recalc.confirm();
    await _pump();
    expect(service.confirms, 0, reason: 'confirm hinter der Berechnung');

    held.release.complete();
    await finishing;
    await confirming;
    expect(service.confirms, 1);
    final run = (await w.session.runs.list()).reduce(
      (a, b) => a.id > b.id ? a : b,
    );
    expect(await w.session.values.read(ValueOwner.run(run.id)), hasLength(1));
  });
}
