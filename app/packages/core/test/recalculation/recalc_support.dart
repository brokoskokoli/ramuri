import 'dart:typed_data';

import 'package:core/core.dart';

final recalcKey = Uint8List.fromList(List.generate(32, (i) => i));

/// Fester Zeitpunkt der Tests (UTC).
final recalcNow = DateTime.utc(2030, 3, 1, 12);

const double _metersPerDegree = earthRadiusMeters * 3.141592653589793 / 180;

const ProfileRecord profile190 = ProfileRecord(
  maxHeartRateBpm: 190,
  restingHeartRateBpm: 60,
);
const ProfileRecord profile180 = ProfileRecord(
  maxHeartRateBpm: 180,
  restingHeartRateBpm: 60,
);

class RecalcWorld {
  RecalcWorld._(this.session, this.clock);

  final StorageSession session;
  final FakeClock clock;

  static Future<RecalcWorld> create({
    ProfileRecord profile = profile190,
    FakeStorage? storage,
  }) async {
    final s = await (storage ?? FakeStorage()).open(recalcKey);
    await s.profile.save(profile);
    return RecalcWorld._(s, FakeClock(recalcNow));
  }

  ValueCalculationService calc({
    StorageSession? over,
    FitnessParameters fitness = const FitnessParameters.v4(),
    PreprocessingParameters pre = const PreprocessingParameters.v4(),
  }) => ValueCalculationService(
    session: over ?? session,
    clock: clock,
    fitness: fitness,
    preprocessing: pre,
  );

  RecalculationService recalc({StorageSession? over}) => RecalculationService(
    session: over ?? session,
    clock: clock,
    calculation: calc(over: over),
  );

  /// Legt einen beendeten Lauf an: [minutes] gleichmäßig mit [speed] m/s,
  /// Puls [bpm], flache Höhe; Quelle [source]. Setzt die Uhr auf das Ende.
  Future<int> seedRun(
    DateTime start, {
    int minutes = 30,
    double speed = 3.0,
    int bpm = 150,
    String source = 'strap',
    Duration? utcOffset,
    double heartRateShare = 1,
  }) async {
    final run = await session.runs.create(startedAt: start);
    final seconds = minutes * 60;
    final positions = <RawPosition>[];
    final hrs = <RawHeartRate>[];
    final alts = <RawAltitude>[];
    for (var s = 0; s <= seconds; s++) {
      final t = start.add(Duration(seconds: s));
      positions.add(
        RawPosition(
          time: t,
          source: 'gps',
          latitude: 10 + s * speed / _metersPerDegree,
          longitude: 20,
          accuracyMeters: 5,
        ),
      );
      // Puls nur im ersten Teil des Laufs (Pulsabdeckung unter 100 %).
      if (s <= seconds * heartRateShare) {
        hrs.add(
          RawHeartRate(
            time: t,
            source: source,
            bpm: bpm,
            contact: SensorContact.good,
          ),
        );
      }
      alts.add(
        RawAltitude(
          time: t,
          source: 'baro',
          meters: 100,
          verticalAccuracyMeters: 3,
        ),
      );
    }
    await session.rawData.append(
      run.id,
      RawBatch(positions: positions, heartRates: hrs, altitudes: alts),
    );
    final end = start.add(Duration(seconds: seconds));
    await session.runs.setState(
      run.id,
      RunState.finished,
      endedAt: end,
      endedUtcOffset: utcOffset,
    );
    clock.set(end.add(const Duration(minutes: 1)));
    return run.id;
  }

  /// Vier Läufe: zwei im aktuellen, zwei im Vergleichsfenster der aerobe
  /// Effizienz (4 Wochen vor `recalcNow` und davor), jeweils sofort berechnet.
  Future<List<int>> seedFourRunsCalculated() async {
    final ids = <int>[];
    for (final (d, speed) in [
      (DateTime.utc(2030, 1, 20, 8), 3.0),
      (DateTime.utc(2030, 1, 25, 8), 3.0),
      (DateTime.utc(2030, 2, 20, 8), 3.15),
      (DateTime.utc(2030, 2, 25, 8), 3.15),
    ]) {
      final id = await seedRun(d, speed: speed);
      await calc().calculateAfterRun(id);
      ids.add(id);
    }
    return ids;
  }

  /// Alle Werte aller Läufe und Tage, als Text (Vergleich vorher/nachher).
  Future<String> dump() async {
    final out = StringBuffer();
    final owners = <ValueOwner>[
      for (final r in await session.runs.list()) ValueOwner.run(r.id),
      for (final d in await _days()) ValueOwner.day(d),
    ];
    for (final o in owners) {
      for (final p in await session.values.read(o)) {
        out.writeln(
          '${o.runId}/${o.day} ${_v(p.original)} || ${_v(p.current)}',
        );
      }
    }
    return out.toString();
  }

  Future<Set<String>> _days() async => {
    for (final r in await session.runs.list())
      if (r.endedAt != null) dayOfRun(r),
    isoDay(recalcNow),
    isoDay(clock.now()),
  };

  /// Alle Tage von [from] bis [to] (UTC-Tage, einschließlich), die Werte haben.
  Future<Map<String, List<ValuePair>>> daysWithValues(
    String from,
    String to,
  ) async {
    final out = <String, List<ValuePair>>{};
    for (
      var d = DateTime.parse('${from}T00:00:00Z');
      isoDay(d).compareTo(to) <= 0;
      d = d.add(const Duration(days: 1))
    ) {
      final v = await session.values.read(ValueOwner.day(isoDay(d)));
      if (v.isNotEmpty) out[isoDay(d)] = v;
    }
    return out;
  }

  Future<List<ValuePair>> allPairs() async => [
    for (final r in await session.runs.list())
      ...await session.values.read(ValueOwner.run(r.id)),
    for (final d in await _days())
      ...await session.values.read(ValueOwner.day(d)),
  ];

  static String _v(ComputedValue v) =>
      '${v.key}=${v.value}|${v.quality.name}|${v.method}/${v.methodVersion}'
      '|p${v.parameterVersion}|n${v.measurementCount}|${v.sources}'
      '|${v.computedAt.toIso8601String()}|${v.dataFrom}|${v.dataTo}'
      '|${[for (final s in v.sections) '${s.start.microsecondsSinceEpoch}-${s.end.microsecondsSinceEpoch}:${s.status.name}:${s.estimate}:${s.reasons}']}';
}

/// Session, die einzelne Bereiche durch Fehlerinjektion ersetzt.
class FaultySession implements StorageSession {
  FaultySession(this.inner, {required this.rawData, required this.values});

  final StorageSession inner;
  @override
  final RawDataStore rawData;
  @override
  final ComputedValueStore values;

  @override
  RunStore get runs => inner.runs;
  @override
  RunMarkerStore get markers => inner.markers;
  @override
  PreprocessingStore get preprocessing => inner.preprocessing;
  @override
  RatedSectionStore get sections => inner.sections;
  @override
  ProfileStore get profile => inner.profile;
  @override
  SettingsStore get settings => inner.settings;
  @override
  KnownDeviceStore get devices => inner.devices;
  @override
  ConsentStore get consents => inner.consents;
  @override
  Future<void> deleteRun(int runId) => inner.deleteRun(runId);
  @override
  Future<void> deleteAll() => inner.deleteAll();
  @override
  Future<void> close() => inner.close();
}

/// Rohdaten, die beim n-ten Lesen scheitern.
class FailingRawData implements RawDataStore {
  FailingRawData(this.inner, {required this.failOnRead});

  final RawDataStore inner;
  final int failOnRead;
  int reads = 0;

  @override
  Future<void> append(int runId, RawBatch batch) => inner.append(runId, batch);

  @override
  Future<StoredRawData> read(int runId) {
    if (++reads == failOnRead) {
      throw const StorageException(StorageFailure.failed);
    }
    return inner.read(runId);
  }
}

/// Rohdaten, die beim ersten Lesen einen Rückruf ausführen (Rennen).
class HookedRawData implements RawDataStore {
  HookedRawData(this.inner, this.onFirstRead);

  final RawDataStore inner;
  final Future<void> Function() onFirstRead;
  bool _fired = false;

  @override
  Future<void> append(int runId, RawBatch batch) => inner.append(runId, batch);

  @override
  Future<StoredRawData> read(int runId) async {
    if (!_fired) {
      _fired = true;
      await onFirstRead();
    }
    return inner.read(runId);
  }
}

/// Werte, bei denen der Sammel-Tausch scheitert; zählt die Einzel-Tausche.
class FailingValues implements ComputedValueStore {
  FailingValues(this.inner);

  final ComputedValueStore inner;
  int singleSwaps = 0;
  bool failSwapAll = true;
  bool failWriteAll = false;
  bool failRead = false;
  int writeAlls = 0;

  @override
  Future<void> createOriginals(ValueOwner owner, List<ComputedValue> values) =>
      inner.createOriginals(owner, values);

  @override
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values) {
    singleSwaps++;
    return inner.swapCurrent(owner, values);
  }

  @override
  Future<void> swapCurrentAll(Map<ValueOwner, List<ComputedValue>> changes) {
    if (failSwapAll) throw const StorageException(StorageFailure.failed);
    return inner.swapCurrentAll(changes);
  }

  @override
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) {
    writeAlls++;
    if (failWriteAll) throw const StorageException(StorageFailure.failed);
    return inner.writeAll(create: create, swap: swap);
  }

  @override
  Future<List<ValuePair>> read(ValueOwner owner) {
    if (failRead) throw const StorageException(StorageFailure.failed);
    return inner.read(owner);
  }

  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(Set<String> keys) {
    if (failRead) throw const StorageException(StorageFailure.failed);
    return inner.readRunValues(keys);
  }
}

/// Reicht alles durch und merkt sich, dass ein Sammel-Tausch gelang.
class SwapSignalValues implements ComputedValueStore {
  SwapSignalValues(this.inner);
  final ComputedValueStore inner;
  bool swapped = false;

  @override
  Future<void> createOriginals(ValueOwner owner, List<ComputedValue> values) =>
      inner.createOriginals(owner, values);
  @override
  Future<void> swapCurrent(ValueOwner owner, List<ComputedValue> values) =>
      inner.swapCurrent(owner, values);
  @override
  Future<void> swapCurrentAll(
    Map<ValueOwner, List<ComputedValue>> changes,
  ) async {
    await inner.swapCurrentAll(changes);
    swapped = true;
  }

  @override
  Future<void> writeAll({
    Map<ValueOwner, List<ComputedValue>> create = const {},
    Map<ValueOwner, List<ComputedValue>> swap = const {},
  }) => inner.writeAll(create: create, swap: swap);
  @override
  Future<List<ValuePair>> read(ValueOwner owner) => inner.read(owner);
  @override
  Future<Map<int, Map<String, ComputedValue>>> readRunValues(
    Set<String> keys,
  ) => inner.readRunValues(keys);
}

/// Wie [FaultySession], aber Schreiben in die Einstellungen scheitert, solange
/// [failSettingsWhen] wahr ist.
class SettingsFailingSession extends FaultySession {
  SettingsFailingSession(
    super.inner, {
    required super.rawData,
    required super.values,
    required this.failSettingsWhen,
  });

  final bool Function() failSettingsWhen;

  @override
  SettingsStore get settings =>
      _FailingSettings(inner.settings, failSettingsWhen);
}

class _FailingSettings implements SettingsStore {
  _FailingSettings(this.inner, this.failWhen);
  final SettingsStore inner;
  final bool Function() failWhen;
  @override
  Future<String?> get(String key) => inner.get(key);
  @override
  Future<Map<String, String>> all() => inner.all();
  @override
  Future<void> set(String key, String value, {required DateTime at}) {
    if (failWhen()) throw const StorageException(StorageFailure.failed);
    return inner.set(key, value, at: at);
  }
}

/// Die VO2max-Laufwerte (genau einer oder keiner) eines Laufs; die Zonen- und
/// TRIMP-Werte (`runLoadValueKeys`) zählen hier nicht.
Future<List<ValuePair>> runVo2Pairs(StorageSession s, int runId) async => [
  for (final p in await s.values.read(ValueOwner.run(runId)))
    if (p.original.key == vo2maxRunValueKey) p,
];

Future<ValuePair> runVo2(StorageSession s, int runId) async =>
    (await runVo2Pairs(s, runId)).single;
