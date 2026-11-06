import 'package:core/core.dart';
import 'package:test/test.dart';

import '../recalculation/recalc_support.dart';

/// Zählt die Zugriffe, die je Lauf einzeln wären (N+1).
class _Counting implements StorageSession {
  _Counting(this.s);
  final StorageSession s;
  int rawReads = 0;
  int runGets = 0;
  int overviewReads = 0;
  int singleReads = 0;
  final Set<int> failRaw = {};

  @override
  RawDataStore get rawData => _Raw(s.rawData, this);
  @override
  RunStore get runs => _Runs(s.runs, this);
  @override
  PreprocessingStore get preprocessing => _Pre(s.preprocessing, this);
  @override
  RunMarkerStore get markers => s.markers;
  @override
  RatedSectionStore get sections => s.sections;
  @override
  ComputedValueStore get values => s.values;
  @override
  ProfileStore get profile => s.profile;
  @override
  SettingsStore get settings => s.settings;
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

class _Raw implements RawDataStore {
  _Raw(this.i, this.c);
  final RawDataStore i;
  final _Counting c;
  @override
  Future<void> append(int runId, RawBatch batch) => i.append(runId, batch);
  @override
  Future<StoredRawData> read(int runId) {
    c.rawReads++;
    if (c.failRaw.contains(runId)) {
      return Future.error(const StorageException(StorageFailure.failed));
    }
    return i.read(runId);
  }
}

class _Runs implements RunStore {
  _Runs(this.i, this.c);
  final RunStore i;
  final _Counting c;
  @override
  Future<StoredRun> create({required DateTime startedAt}) =>
      i.create(startedAt: startedAt);
  @override
  Future<void> setState(
    int runId,
    RunState state, {
    DateTime? endedAt,
    Duration? endedUtcOffset,
  }) => i.setState(
    runId,
    state,
    endedAt: endedAt,
    endedUtcOffset: endedUtcOffset,
  );
  @override
  Future<StoredRun?> get(int runId) {
    c.runGets++;
    return i.get(runId);
  }

  @override
  Future<List<StoredRun>> list() => i.list();
  @override
  Future<List<StoredRun>> unfinished() => i.unfinished();
}

class _Pre implements PreprocessingStore {
  _Pre(this.i, this.c);
  final PreprocessingStore i;
  final _Counting c;
  @override
  Future<void> replace(int runId, StoredPreprocessing result) =>
      i.replace(runId, result);
  @override
  Future<StoredPreprocessing?> read(int runId) {
    c.singleReads++;
    return i.read(runId);
  }

  @override
  Future<Map<int, StoredPreprocessing>> readOverviews() {
    c.overviewReads++;
    return i.readOverviews();
  }
}

void main() {
  group('Kurzfassung der Läufe (Historie)', () {
    test(
      'viele Läufe: eine gebündelte Abfrage, keine Zugriffe je Lauf',
      () async {
        final w = await RecalcWorld.create();
        final ids = <int>[];
        for (var i = 0; i < 40; i++) {
          final id = await w.seedRun(
            DateTime.utc(2030, 1, 1 + i % 28, 6 + i ~/ 28),
            minutes: 2,
            speed: 3.0 + (i % 5) * 0.1,
          );
          await w.calc().calculateAfterRun(id);
          ids.add(id);
        }
        final c = _Counting(w.session);
        final list = await RunOverviewService(
          session: c,
          clock: w.clock,
        ).load();
        expect(list, hasLength(40));
        expect(c.overviewReads, 1);
        expect(c.rawReads, 0, reason: 'nichts wird neu gerechnet');
        expect(c.runGets, 0);
        expect(c.singleReads, 0);
        for (final o in list) {
          expect(o.distanceMeters, isNotNull);
          expect(o.averagePaceSecondsPerKm, isNotNull);
          expect(o.averageHeartRateBpm, 150);
        }
      },
    );

    test('Kurzfassung ergibt dieselbe Pace wie die Zusammenfassung (K20, Lücke)', () async {
      final w = await RecalcWorld.create();
      final start = DateTime.utc(2030, 2, 1, 8);
      final run = await w.session.runs.create(startedAt: start);
      // 10 min mit 3 m/s, aber 2 min ohne Position (Lücke), Puls läuft weiter.
      await w.session.rawData.append(
        run.id,
        RawBatch(
          positions: [
            for (var s = 0; s <= 600; s++)
              if (s < 240 || s > 360)
                RawPosition(
                  time: start.add(Duration(seconds: s)),
                  source: 'gps',
                  latitude: 10 + s * 3.0 / 111194.9,
                  longitude: 20,
                  accuracyMeters: 5,
                ),
          ],
          heartRates: [
            for (var s = 0; s <= 600; s++)
              RawHeartRate(
                time: start.add(Duration(seconds: s)),
                source: 'strap',
                bpm: 150,
                contact: SensorContact.good,
              ),
          ],
        ),
      );
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(seconds: 600)),
      );
      final id = run.id;
      final o = (await RunOverviewService(
        session: w.session,
        clock: w.clock,
      ).load()).single;
      final s = (await RunSummaryService(
        session: w.session,
        clock: w.clock,
      ).load(id))!;
      expect(s.preprocessing.position.gaps, isNotEmpty);
      expect(
        o.paceTime,
        lessThan(o.movingTime!),
        reason: 'Lückenzeit abgezogen',
      );
      expect(o.averagePaceSecondsPerKm, s.figures.averagePaceSecondsPerKm);
      expect(o.movingTime, s.figures.movingTime);
      expect(o.paceTime, s.figures.paceTime);
    });

    test(
      'Lauf ohne gespeicherte Kurzfassung wird neu gerechnet und gespeichert',
      () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
        final c = _Counting(w.session);
        final first = await RunOverviewService(
          session: c,
          clock: w.clock,
        ).load();
        expect(first.single.distanceMeters, closeTo(900, 5));
        expect(c.rawReads, 1);
        // Zweiter Aufruf: gespeichert, kein Rohdatenzugriff mehr.
        final again = await RunOverviewService(
          session: c,
          clock: w.clock,
        ).load();
        expect(c.rawReads, 1);
        expect(again.single.distanceMeters, first.single.distanceMeters);
        expect(
          (await w.session.preprocessing.read(id))!.summary.method,
          runOverviewMethod,
        );
      },
    );

    test('Lauf ohne Puls: kein Puls, keine 0', () async {
      final w = await RecalcWorld.create();
      final start = DateTime.utc(2030, 2, 1, 8);
      final run = await w.session.runs.create(startedAt: start);
      await w.session.rawData.append(
        run.id,
        RawBatch(
          positions: [
            for (var s = 0; s <= 120; s++)
              RawPosition(
                time: start.add(Duration(seconds: s)),
                source: 'gps',
                latitude: 10 + s * 3.0 / 111194.9,
                longitude: 20,
                accuracyMeters: 5,
              ),
          ],
        ),
      );
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(seconds: 120)),
      );
      final o = (await RunOverviewService(
        session: w.session,
        clock: w.clock,
      ).load()).single;
      expect(o.averageHeartRateBpm, isNull);
      expect(o.maxHeartRateBpm, isNull);
      expect(o.distanceMeters, isNotNull);
    });

    test('unfertige Läufe fehlen in der Liste', () async {
      final w = await RecalcWorld.create();
      await w.session.runs.create(startedAt: DateTime.utc(2030, 2, 1, 8));
      expect(
        await RunOverviewService(session: w.session, clock: w.clock).load(),
        isEmpty,
      );
    });

    for (final (name, mutate)
        in <(String, PreprocessingSummary Function(PreprocessingSummary))>[
          ('andere Parameterversion', (s) => _with(s, parameterVersion: 1)),
          ('andere Kurzfassungs-Methode', (s) => _with(s, method: 'anders')),
          ('andere Methodenversion', (s) => _with(s, methodVersion: 99)),
        ]) {
      test('veraltete kurzfassung ($name) wird neu gerechnet', () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
        await w.calc().calculateAfterRun(id);
        final good = (await w.session.preprocessing.read(id))!;
        await w.session.preprocessing.replace(
          id,
          StoredPreprocessing(summary: mutate(good.summary), spans: good.spans),
        );
        final c = _Counting(w.session);
        final list = await RunOverviewService(
          session: c,
          clock: w.clock,
        ).load();
        expect(c.rawReads, 1);
        expect(list.single.distanceMeters, closeTo(900, 5));
        final stored = (await w.session.preprocessing.read(id))!.summary;
        expect(stored.method, runOverviewMethod);
        expect(stored.methodVersion, runOverviewMethodVersion);
        expect(stored.parameterVersion, good.summary.parameterVersion);
      });
    }

    test(
      'Lesefehler eines Laufs: nur dieser fehlt, die Historie bleibt',
      () async {
        final w = await RecalcWorld.create();
        final bad = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
        final good = await w.seedRun(DateTime.utc(2030, 2, 2, 8), minutes: 5);
        final c = _Counting(w.session)..failRaw.add(bad);
        final list = await RunOverviewService(
          session: c,
          clock: w.clock,
        ).load();
        expect(list, hasLength(2));
        final byId = {for (final o in list) o.run.id: o};
        expect(byId[bad]!.readFailed, isTrue);
        expect(byId[bad]!.distanceMeters, isNull);
        expect(byId[good]!.readFailed, isFalse);
        expect(byId[good]!.distanceMeters, closeTo(900, 5));
      },
    );
  });
}

PreprocessingSummary _with(
  PreprocessingSummary s, {
  String? method,
  int? methodVersion,
  int? parameterVersion,
}) => PreprocessingSummary(
  method: method ?? s.method,
  methodVersion: methodVersion ?? s.methodVersion,
  parameterVersion: parameterVersion ?? s.parameterVersion,
  computedAt: s.computedAt,
  totalTime: s.totalTime,
  movingTime: s.movingTime,
  distanceMeters: s.distanceMeters,
  bridgedDistanceMeters: s.bridgedDistanceMeters,
  averageBpm: s.averageBpm,
  maxBpm: s.maxBpm,
);
