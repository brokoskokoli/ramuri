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
  int valueReads = 0;
  int valueBulkReads = 0;
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
  ComputedValueStore get values => _Vals(s.values, this);
  @override
  ProfileStore get profile => s.profile;
  @override
  SettingsStore get settings => s.settings;
  @override
  KnownDeviceStore get devices => s.devices;
  @override
  ConsentStore get consents => s.consents;
  @override
  RunSubjectiveStore get subjective => s.subjective;
  @override
  ManualTrainingStore get manualTrainings => s.manualTrainings;
  @override
  Future<void> deleteRun(int runId) => s.deleteRun(runId);
  @override
  Future<void> deleteAll() => s.deleteAll();
  @override
  Future<void> close() => s.close();
}

class _Vals implements ComputedValueStore {
  _Vals(this.i, this.c);
  final ComputedValueStore i;
  final _Counting c;
  @override
  Future<void> createOriginals(ValueOwner o, List<ComputedValue> v) =>
      i.createOriginals(o, v);
  @override
  Future<void> swapCurrent(ValueOwner o, List<ComputedValue> v) =>
      i.swapCurrent(o, v);
  @override
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> c) =>
      i.swapCurrentAll(c);
  @override
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) => i.writeAll(create: create, swap: swap);
  @override
  Future<List<ValuePair>> read(ValueOwner o) {
    c.valueReads++;
    return i.read(o);
  }

  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(Set<String> keys) {
    c.valueBulkReads++;
    return i.readRunValues(keys);
  }

  @override
  Future<Map<String, Map<String, ComputedValue>>> readDayValues(
    Set<String> keys,
  ) => i.readDayValues(keys);
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
  Future<StoredRun> create({
    required DateTime startedAt,
    RunMode mode = RunMode.gps,
  }) => i.create(startedAt: startedAt, mode: mode);
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
  Future<List<StoredRun>> finishedBetween(DateTime from, DateTime to) =>
      i.finishedBetween(from, to);

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
        expect(c.valueBulkReads, 1, reason: 'Zonen und TRIMP gebündelt');
        expect(c.valueReads, 0, reason: 'kein Lesen der Werte je Lauf');
        for (final o in list) {
          expect(o.load.zoneTimes, isNotNull);
          expect(o.load.trimpPoints, isNotNull);
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

    test('Lauf mit Stillstand: Kurzfassung führt die Gesamtzeit, nicht die '
        'Bewegungszeit (WP17 NB1)', () async {
      final w = await RecalcWorld.create();
      final start = DateTime.utc(2030, 2, 2, 8);
      final run = await w.session.runs.create(startedAt: start);
      // 10 min: 3 min laufen, 3 min stehen (gleiche Position), 4 min laufen.
      double lat(int s) {
        final moved = s <= 180 ? s : (s <= 360 ? 180 : s - 180);
        return 10 + moved * 3.0 / 111194.9;
      }

      await w.session.rawData.append(
        run.id,
        RawBatch(
          positions: [
            for (var s = 0; s <= 600; s++)
              RawPosition(
                time: start.add(Duration(seconds: s)),
                source: 'gps',
                latitude: lat(s),
                longitude: 20,
                accuracyMeters: 5,
              ),
          ],
        ),
      );
      await w.session.runs.setState(
        run.id,
        RunState.finished,
        endedAt: start.add(const Duration(seconds: 600)),
      );
      final o = (await RunOverviewService(
        session: w.session,
        clock: w.clock,
      ).load()).single;
      expect(o.totalTime, const Duration(seconds: 600));
      expect(o.movingTime, lessThan(const Duration(seconds: 500)));
      expect(o.totalTime, greaterThan(o.movingTime!));
      final s = (await RunSummaryService(
        session: w.session,
        clock: w.clock,
      ).load(run.id))!;
      expect(o.totalTime, s.preprocessing.movement.totalTime);
      expect(o.toFigures().totalTime, o.totalTime);
    });

    test('Veraltete Läufe werden über den Offload neu gerechnet', () async {
      final w = await RecalcWorld.create();
      await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
      await w.seedRun(DateTime.utc(2030, 2, 2, 8), minutes: 5);
      final jobs = <Object>[];
      Future<R> counting<A, R>(R Function(A) job, A argument) {
        jobs.add(job);
        return inlineOffload(job, argument);
      }

      final first = await RunOverviewService(
        session: w.session,
        clock: w.clock,
        offload: counting,
      ).load();
      expect(first, hasLength(2));
      expect(first.every((o) => o.distanceMeters! > 800), isTrue);
      expect(jobs, [replayJob, replayJob]);
      // Gespeichert: kein weiterer Offload.
      await RunOverviewService(
        session: w.session,
        clock: w.clock,
        offload: counting,
      ).load();
      expect(jobs, hasLength(2));
    });

    test('Neu gerechnete Kurzfassung zieht sRPE des Laufs nach (Bewegungszeit)', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
      // RPE vor der Berechnung: noch keine Bewegungszeit, also kein sRPE-Wert.
      await w.session.subjective.save(id, RunSubjective(rpe: 5));
      await RunOverviewService(session: w.session, clock: w.clock).load();
      final moving = (await w.session.preprocessing.read(id))!
          .summary
          .movingTime!;
      final srpe = (await w.session.subjective.read(id))!.srpe!;
      expect(srpe.duration, moving);
      expect(
        srpe.points,
        moving.inMicroseconds * 5 / Duration.microsecondsPerMinute,
      );
    });

    test('Wirft der Offload für einen Lauf: Lesefehler, Rest normal', () async {
      final w = await RecalcWorld.create();
      await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 5);
      await w.seedRun(DateTime.utc(2030, 2, 2, 8), minutes: 5);
      var calls = 0;
      Future<R> failing<A, R>(R Function(A) job, A argument) {
        calls++;
        if (calls == 1) throw StateError('Isolate kaputt');
        return inlineOffload(job, argument);
      }

      final all = await RunOverviewService(
        session: w.session,
        clock: w.clock,
        offload: failing,
      ).load();
      expect(all, hasLength(2));
      final bad = all.singleWhere((o) => o.readFailed);
      expect(
        all.singleWhere((o) => !o.readFailed).distanceMeters,
        greaterThan(800),
      );
      // Nichts gespeichert für den fehlerhaften Lauf.
      expect(await w.session.preprocessing.read(bad.run.id), isNull);
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

    test(
      'Kurzfassung trägt Bestpace, Runden und Zeit mit Puls; Zeitraum '
      '(Woche/Monat/frei) daraus ohne Rohdaten und ohne Zugriff je Lauf',
      () async {
        final w = await RecalcWorld.create();
        final slow = await w.seedRun(
          DateTime.utc(2030, 1, 7, 8),
          minutes: 10,
          speed: 3.0,
        );
        final fast = await w.seedRun(
          DateTime.utc(2030, 1, 8, 8),
          minutes: 10,
          speed: 4.0,
        );
        for (var i = 1; i <= 2; i++) {
          await w.session.markers.addLap(
            slow,
            StoredLap(
              index: i,
              markedAt: DateTime.utc(2030, 1, 7, 8, i),
              lapTime: const Duration(minutes: 1),
            ),
          );
        }
        await w.session.markers.addLap(
          fast,
          StoredLap(
            index: 1,
            markedAt: DateTime.utc(2030, 1, 8, 8, 1),
            lapTime: const Duration(minutes: 1),
          ),
        );
        await w.calc().calculateAfterRun(slow);
        await w.calc().calculateAfterRun(fast);
        final c = _Counting(w.session);
        final list = await RunOverviewService(
          session: c,
          clock: w.clock,
        ).load();
        expect(c.rawReads, 0, reason: 'alles aus der Kurzfassung');
        expect(c.runGets, 0);
        final byId = {for (final o in list) o.run.id: o};
        expect(byId[slow]!.bestPaceSecondsPerKm, closeTo(1000 / 3, 1));
        expect(byId[fast]!.bestPaceSecondsPerKm, closeTo(250, 1));
        expect(byId[slow]!.lapCount, 2);
        expect(byId[fast]!.lapCount, 1);
        expect(
          byId[slow]!.heartRateTime!.inSeconds,
          closeTo(byId[slow]!.movingTime!.inSeconds, 2),
        );
        for (final period in [
          StatisticsPeriod.weekOf('2030-01-09'),
          StatisticsPeriod.monthOf('2030-01-09'),
          StatisticsPeriod.custom(from: '2030-01-01', to: '2030-01-31'),
        ]) {
          final stats = computePeriodStatistics(period, [
            for (final o in list) o.toFigures(),
          ]);
          expect(stats.bestPaceSecondsPerKm.value, closeTo(250, 1));
          expect(stats.lapCount.value, 3);
          expect(stats.lapCount.runsWithValue, 2);
        }
      },
    );

    test('Lauf ohne Runden: Rundenzahl 0 (gezählt, nicht fehlend)', () async {
      final w = await RecalcWorld.create();
      final id = await w.seedRun(DateTime.utc(2030, 1, 7, 8), minutes: 5);
      await w.calc().calculateAfterRun(id);
      final o = (await RunOverviewService(
        session: w.session,
        clock: w.clock,
      ).load()).single;
      expect(o.lapCount, 0);
    });

    test(
      'Kurzfassung der Version 1 (ohne Bestpace, Runden, Zeit mit Puls) wird '
      'neu gerechnet und trägt die neuen Teile',
      () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(DateTime.utc(2030, 2, 1, 8), minutes: 10);
        await w.session.markers.addLap(
          id,
          StoredLap(
            index: 1,
            markedAt: DateTime.utc(2030, 2, 1, 8, 5),
            lapTime: const Duration(minutes: 5),
          ),
        );
        await w.calc().calculateAfterRun(id);
        final good = (await w.session.preprocessing.read(id))!;
        // Stand vor WP10: Version 1 und ohne die neuen Teile.
        await w.session.preprocessing.replace(
          id,
          StoredPreprocessing(
            summary: PreprocessingSummary(
              method: runOverviewMethod,
              methodVersion: 1,
              parameterVersion: good.summary.parameterVersion,
              computedAt: good.summary.computedAt,
              totalTime: good.summary.totalTime,
              movingTime: good.summary.movingTime,
              distanceMeters: good.summary.distanceMeters,
              averageBpm: good.summary.averageBpm,
              maxBpm: good.summary.maxBpm,
            ),
            spans: good.spans,
          ),
        );
        final c = _Counting(w.session);
        final o = (await RunOverviewService(
          session: c,
          clock: w.clock,
        ).load()).single;
        expect(c.rawReads, 1, reason: 'neu gerechnet');
        expect(o.bestPaceSecondsPerKm, closeTo(1000 / 3, 1));
        expect(o.lapCount, 1);
        expect(o.heartRateTime, isNotNull);
        final stored = (await w.session.preprocessing.read(id))!.summary;
        expect(stored.methodVersion, runOverviewMethodVersion);
        expect(runOverviewMethodVersion, greaterThan(1));
        expect(stored.lapCount, 1);
        expect(stored.bestPaceSecondsPerKm, isNotNull);
        expect(stored.heartRateTime, isNotNull);
        // Beim nächsten Lesen ist sie aktuell.
        final again = _Counting(w.session);
        await RunOverviewService(session: again, clock: w.clock).load();
        expect(again.rawReads, 0);
      },
    );

    test(
      'Kurzfassung der Vorgängerversion (vor Laufband) wird neu gerechnet',
      () async {
        final w = await RecalcWorld.create();
        final id = await w.seedRun(DateTime.utc(2030, 2, 3, 8), minutes: 10);
        await w.calc().calculateAfterRun(id);
        final good = (await w.session.preprocessing.read(id))!;
        await w.session.preprocessing.replace(
          id,
          StoredPreprocessing(
            summary: PreprocessingSummary(
              method: runOverviewMethod,
              methodVersion: 2, // Stand vor WP25
              parameterVersion: good.summary.parameterVersion,
              computedAt: good.summary.computedAt,
              totalTime: good.summary.totalTime,
              movingTime: good.summary.movingTime,
              distanceMeters: good.summary.distanceMeters,
              averageBpm: good.summary.averageBpm,
              maxBpm: good.summary.maxBpm,
              lapCount: good.summary.lapCount,
              heartRateTime: good.summary.heartRateTime,
              bestPaceSecondsPerKm: good.summary.bestPaceSecondsPerKm,
            ),
            spans: good.spans,
          ),
        );
        final c = _Counting(w.session);
        await RunOverviewService(session: c, clock: w.clock).load();
        expect(c.rawReads, 1, reason: 'neu gerechnet');
        expect(
          (await w.session.preprocessing.read(id))!.summary.methodVersion,
          runOverviewMethodVersion,
        );
      },
    );

    test(
      'Ø-Puls im Zeitraum nach Zeit mit Puls gewichtet, nicht nach '
      'Bewegungszeit: Lauf mit Pulslücke zählt nur mit bekanntem Puls',
      () async {
        final w = await RecalcWorld.create();
        // 20 min, aber nur die erste Hälfte mit Puls (100 bpm).
        await w.seedRun(
          DateTime.utc(2030, 1, 1, 8),
          minutes: 20,
          bpm: 100,
          heartRateShare: 0.5,
        );
        // 10 min durchgehend mit Puls (160 bpm).
        await w.seedRun(DateTime.utc(2030, 1, 2, 8), minutes: 10, bpm: 160);
        final list = await RunOverviewService(
          session: w.session,
          clock: w.clock,
        ).load();
        final gappy = list.firstWhere((o) => o.averageHeartRateBpm == 100);
        expect(gappy.heartRateTime!.inSeconds, closeTo(600, 15));
        expect(gappy.movingTime!.inSeconds, closeTo(1200, 15));
        final stats = computePeriodStatistics(
          StatisticsPeriod.custom(from: '2030-01-01', to: '2030-01-02'),
          [for (final o in list) o.toFigures()],
        );
        // Je 10 min mit Puls: (100 + 160) / 2 = 130. Nach Bewegungszeit wären
        // es (20*100 + 10*160) / 30 = 120.
        expect(stats.heartRateAverageBpm.value, closeTo(130, 1.5));
      },
    );

    test(
      'Durchschnittspuls der Zeitraumstatistik: nach Zeit mit Puls gewichtet, '
      'Lauf ohne Puls geht nicht ein',
      () async {
        final w = await RecalcWorld.create();
        final a = await w.seedRun(
          DateTime.utc(2030, 1, 1, 8),
          minutes: 10,
          bpm: 120,
        );
        final b = await w.seedRun(
          DateTime.utc(2030, 1, 2, 8),
          minutes: 30,
          bpm: 160,
        );
        final none = await w.seedRun(
          DateTime.utc(2030, 1, 3, 8),
          minutes: 10,
          heartRateShare: -1,
        );
        final list = await RunOverviewService(
          session: w.session,
          clock: w.clock,
        ).load();
        expect(
          list.firstWhere((o) => o.run.id == none).averageHeartRateBpm,
          isNull,
        );
        final stats = computePeriodStatistics(
          StatisticsPeriod.custom(from: '2030-01-01', to: '2030-01-03'),
          [for (final o in list) o.toFigures()],
        );
        // 10 min mit 120 und 30 min mit 160 bpm: (10*120 + 30*160) / 40 = 150.
        expect(stats.heartRateAverageBpm.value, closeTo(150, 0.5));
        expect(stats.heartRateAverageBpm.runsWithValue, 2);
        expect(stats.heartRateAverageBpm.runsTotal, 3);
        expect({a, b}, hasLength(2));
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
  bestPaceSecondsPerKm: s.bestPaceSecondsPerKm,
  lapCount: s.lapCount,
  heartRateTime: s.heartRateTime,
);
