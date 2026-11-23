// Archiv: alle Daten der Phase 3 hin und zurück, danach
// „Alles löschen“. Die Daten entstehen über die Ports und die Kernlogik
// (Import aus Health Connect, Morgenmessung mit Gurt-RR und Rohsignal, Plan
// „adaptiv“ mit einer Lockerung nach PAR-173). Export mit echter
// Kryptografie, Reimport in eine leere App, danach ist jede Tabelle
// zeilengleich (docs/contracts/archive.md, Abschnitte 27 bis 34). „Alles
// löschen“ leert danach jede Tabelle der Phase 3 (SEC-0004). Alle Daten sind
// synthetisch.
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../storage/support.dart' show testKey;

const String _password = 'synthetisches Testpasswort';

typedef _Dump = Map<String, List<Map<String, Object?>>>;

AppDatabase _dbOf(StorageSession s) => (s as EncryptedStorageSession).database;

Future<List<String>> _tables(AppDatabase db) async => [
  for (final r
      in await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )
          .get())
    r.data['name']! as String,
];

/// Alle Tabellen außer `storage_meta`, `consents` und den technischen Merkern.
Future<_Dump> _dump(AppDatabase db) async {
  final out = <String, List<Map<String, Object?>>>{};
  for (final n in await _tables(db)) {
    if (n == 'storage_meta' || n == 'consents') continue;
    final rows = await db
        .customSelect(
          'SELECT * FROM $n ORDER BY ${n == 'settings' ? 'key' : 'rowid'}',
        )
        .get();
    out[n] = [
      for (final r in rows)
        if (n != 'settings' ||
            !archiveExcludedSettingKeys.contains(r.data['key']))
          Map<String, Object?>.of(r.data),
    ];
  }
  return out;
}

final _d0 = DateTime.utc(2026, 11, 11); // Mittwoch
DateTime _day(int n) => _d0.add(Duration(days: n));

/// Die Tabellen der Phase 3 (Schema 12 bis 15): jede muss im Quellstand Zeilen haben,
/// sonst prüft der Test nichts.
const _m3Tables = [
  'health_sleep_sessions',
  'health_sleep_stages',
  'health_values',
  'health_exercises',
  'health_exercise_heart_rates',
  'morning_measurements',
  'morning_rr_packets',
  'morning_raw_signals',
];

/// Einstellungen der Phase 3, die ins Archiv gehören.
final _m3Settings = <String, String>{
  // Schalter Plananpassung an Erholung (FR-0216).
  planAdaptationKey: PlanAdaptationMode.adaptive.storageValue,
  SettingKeys.morningCameraRmssdOptIn: '1',
};

/// Technische Merker der Phase 3: gehören nicht ins Archiv.
final _technical = <String, String>{
  SettingKeys.developerMode: '1',
  HealthImportService.lastImportKey: '2026-12-01T06:00:00.000Z',
  // Fehlerzähler der App: Gerätezustand ohne Werte, nicht im Archiv.
  SettingKeys.errorCounts:
      '[{"type":"StateError","place":"unknown","count":2}]',
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory work;
  late String activePath;
  late Uint8List key;
  late StorageSession source;
  late StorageSession target;
  late _Dump sourceDump;
  late String archivePath;

  setUp(() async {
    key = testKey(9);
    work = Directory.systemTemp.createTempSync('m3archiv_');
    final appDir = Directory('${work.path}/app')..createSync();
    activePath = '${appDir.path}/running_app.db';
    source = await EncryptedStorage('${work.path}/source.db').open(key);
    await _populate(source);
    sourceDump = await _dump(_dbOf(source));
    final exportDir = Directory('${work.path}/exports')..createSync();
    final handoff = FakeFileHandoff()..directory = exportDir.path;
    final f = await ArchiveExporter(
      source: DriftArchiveSource(_dbOf(source)),
      handoff: handoff,
      clock: FakeClock(DateTime.utc(2026, 12, 5, 12)),
      cipherFactory: createArchiveCipherInWorker,
      pageSize: 7,
    ).export(password: _password);
    archivePath = f.path!;
    target = await EncryptedStorage(activePath).open(key);
  });

  tearDown(() async {
    for (final s in [source, target]) {
      try {
        await s.close();
      } catch (_) {}
    }
    work.deleteSync(recursive: true);
  });

  Future<StorageSession> restore() {
    final files = FileDatabaseFiles(activePath);
    return ArchiveRestoreService(
      session: target,
      sink: DriftArchiveSink(
        storage: EncryptedStorage(files.importPath),
        key: () => key,
        files: files,
      ),
      files: files,
      cipherFactory: createArchiveCipherInWorker,
      clock: FakeClock(DateTime.utc(2026, 12, 5, 12)),
      reopen: () async => target = await EncryptedStorage(activePath).open(key),
      serialize: <T>(Future<T> Function() a) => a(),
    ).restore(path: archivePath, password: _password);
  }

  test('Quellstand: jede Tabelle der Phase 3 hat Zeilen, alle Datenarten, eine '
      'unbrauchbare Messung, Fassung mit Grund readiness', () async {
    for (final t in _m3Tables) {
      expect(sourceDump[t], isNotEmpty, reason: t);
    }
    final kinds = {for (final r in sourceDump['health_values']!) r['kind']};
    expect(kinds, {'hrv_rmssd', 'resting_heart_rate', 'vo2_max'});
    final qualities = {
      for (final r in sourceDump['morning_measurements']!) r['quality'],
    };
    expect(qualities, {'good', 'limited', 'unusable'});
    final postures = {
      for (final r in sourceDump['morning_measurements']!) r['posture'],
    };
    expect(postures, {'lying', 'sitting'});
    expect(
      sourceDump['morning_measurements']!.any((r) => r['sleep_band'] != null),
      isTrue,
    );
    final reasons = {for (final r in sourceDump['plans']!) r['reason']};
    expect(reasons, contains(planReasonReadiness));
    expect(
      sourceDump['plans']!.any(
        (r) => (r['summary']! as String).contains(planRecoveryKey),
      ),
      isTrue,
      reason: 'Fassung hält die Lockerung im summary',
    );
    final keys = {for (final r in sourceDump['settings']!) r['key']};
    expect(keys, containsAll(_m3Settings.keys));
    expect(keys.intersection(_technical.keys.toSet()), isEmpty);
    for (final k in _technical.keys) {
      expect(await source.settings.get(k), isNotNull, reason: k);
    }
  });

  test('Export, Reimport in leere App: jede Tabelle zeilengleich, Daten der Phase 3 '
      'über die Ports gleich, technische Merker fehlen', () async {
    expect(await ArchiveRestoreService.isEmpty(target), isTrue);
    target = await restore();
    final got = await _dump(_dbOf(target));
    expect(got.keys, sourceDump.keys);
    for (final t in sourceDump.keys) {
      expect(got[t], sourceDump[t], reason: 'Tabelle $t');
    }
    for (final t in _m3Tables) {
      expect(got[t], isNotEmpty, reason: t);
    }

    // Über die Ports: Morgenmessungen samt Gurt-RR und Rohsignal.
    final m0 = (source as MorningStorage).morning;
    final m1 = (target as MorningStorage).morning;
    final before = await m0.list();
    final after = await m1.list();
    expect(after.map((e) => e.id), before.map((e) => e.id));
    for (var i = 0; i < before.length; i++) {
      final a = before[i].value, b = after[i].value;
      expect(b.measuredAt, a.measuredAt);
      expect(b.utcOffset, a.utcOffset);
      expect(b.posture, a.posture);
      expect(b.quality, a.quality);
      expect(b.restingHrBpm, a.restingHrBpm);
      expect(b.rmssdMs, a.rmssdMs);
      expect(b.sleepBand, a.sleepBand);
      expect(b.unusableReason, a.unusableReason);
      expect(b.cameraIntervalsMs, a.cameraIntervalsMs);
      final id = before[i].id;
      expect(
        (await m1.beltPackets(
          id,
        )).map((p) => '${p.value.time}|${p.value.source}|${p.value.intervals}'),
        (await m0.beltPackets(
          id,
        )).map((p) => '${p.value.time}|${p.value.source}|${p.value.intervals}'),
      );
      final r0 = await m0.rawSignal(id), r1 = await m1.rawSignal(id);
      expect(r1 == null, r0 == null);
      if (r0 != null) {
        expect(r1!.frames.length, r0.frames.length);
        expect(r1.frames.last.g16, r0.frames.last.g16);
        expect(r1.cameraId, r0.cameraId);
      }
    }

    // Health Connect je Datenart.
    final h0 = (source as HealthStorage).health;
    final h1 = (target as HealthStorage).health;
    for (final k in HealthDataKind.values) {
      if (k == HealthDataKind.heartRate) continue; // nur an Einheiten
      expect(await h1.count(k), await h0.count(k), reason: k.name);
      expect(await h1.count(k), greaterThan(0), reason: k.name);
    }
    final sessions = await h1.sleepSessions(_day(-5), _day(40));
    expect(sessions.expand((s) => s.stages), isNotEmpty);
    expect(await h1.exerciseHeartRate('hc-ex-1'), hasLength(3));

    // Plan mit Lockerung, Schalter und Opt-in.
    final plans = (target as PlanStorage).plans;
    final history = await plans.history();
    expect(
      history.map((v) => '${v.trigger.name}/${v.reason}/${v.summary}'),
      (await (source as PlanStorage).plans.history()).map(
        (v) => '${v.trigger.name}/${v.reason}/${v.summary}',
      ),
    );
    expect(
      recoveryEasedFromSummary(
        history.lastWhere((v) => v.reason == planReasonReadiness).summary,
      ),
      isNotEmpty,
    );
    expect(
      await SettingsPlanAdaptationStore(target.settings).read(),
      PlanAdaptationMode.adaptive,
    );
    for (final e in _m3Settings.entries) {
      expect(await target.settings.get(e.key), e.value, reason: e.key);
    }
    for (final k in _technical.keys) {
      expect(await target.settings.get(k), isNull, reason: k);
    }
  });

  test('„Alles löschen“ nach dem Reimport: jede Tabelle der Phase 3 leer, auch die '
      'Kinder; die App gilt wieder als leer', () async {
    target = await restore();
    for (final t in _m3Tables) {
      expect(await _count(_dbOf(target), t), greaterThan(0), reason: t);
    }
    await target.deleteAll();
    for (final t in _m3Tables) {
      expect(await _count(_dbOf(target), t), 0, reason: t);
    }
    // Keine Tabelle behält Zeilen (auch Plan, Schalter, Opt-in).
    for (final t in await _tables(_dbOf(target))) {
      expect(await _count(_dbOf(target), t), 0, reason: t);
    }
    expect(await (target as MorningStorage).morning.list(), isEmpty);
    for (final k in HealthDataKind.values) {
      expect(await (target as HealthStorage).health.count(k), 0);
    }
    expect(await target.settings.get(planAdaptationKey), isNull);
    expect(await ArchiveRestoreService.isEmpty(target), isTrue);
  });
}

Future<int> _count(AppDatabase db, String table) async {
  final r = await db.customSelect('SELECT COUNT(*) AS c FROM $table').get();
  return r.single.data['c']! as int;
}

/// Ortszeit UTC+1 (synthetisch).
const _offset = Duration(hours: 1);

/// Health-Connect-Import über den Port: Schlaf mit Phasen, HRV, Ruhepuls und
/// VO₂max aus zwei Quell-Apps (Quellwechsel), eine Trainingseinheit mit Puls.
Future<void> _health(HealthImportStore h) async {
  final sleep = <HealthRecord>[];
  final values = <HealthRecord>[];
  for (var n = 0; n < 10; n++) {
    if (n == 4) continue; // Lücke
    final origin = n < 6 ? 'com.example.uhr.a' : 'com.example.uhr.b';
    final start = _day(n).subtract(const Duration(hours: 2));
    final end = _day(n).add(const Duration(hours: 6));
    sleep.add(
      HealthRecord(
        kind: HealthDataKind.sleep,
        id: 'hc-sleep-$n',
        origin: origin,
        start: start,
        end: end,
        offsetSeconds: _offset.inSeconds,
        stages: [
          HealthSleepStage(start, start.add(const Duration(hours: 3)), 4),
          HealthSleepStage(
            start.add(const Duration(hours: 3)),
            start.add(const Duration(hours: 3, minutes: 20)),
            1,
          ),
          HealthSleepStage(
            start.add(const Duration(hours: 3, minutes: 20)),
            end,
            5,
          ),
        ],
      ),
    );
    for (final (kind, v, unit) in [
      (HealthDataKind.hrvRmssd, 40.0 + n, 'ms'),
      (HealthDataKind.restingHeartRate, 54.0 + n % 3, 'bpm'),
    ]) {
      final t = _day(n).add(const Duration(hours: 3));
      values.add(
        HealthRecord(
          kind: kind,
          id: 'hc-${kind.key}-$n',
          origin: origin,
          start: t,
          end: t,
          offsetSeconds: _offset.inSeconds,
          value: v,
          unit: unit,
        ),
      );
    }
  }
  values.add(
    HealthRecord(
      kind: HealthDataKind.vo2Max,
      id: 'hc-vo2-1',
      origin: 'com.example.uhr.b',
      start: _day(8),
      end: _day(8),
      value: 44.5,
      unit: 'ml/kg/min',
    ),
  );
  await h.upsertSleep(sleep);
  await h.upsertValues(values);
  final exStart = _day(2).add(const Duration(hours: 17));
  await h.upsertExercises([
    HealthRecord(
      kind: HealthDataKind.exercise,
      id: 'hc-ex-1',
      origin: 'com.example.uhr.a',
      start: exStart,
      end: exStart.add(const Duration(minutes: 40)),
      offsetSeconds: _offset.inSeconds,
      exerciseType: 56,
    ),
  ]);
  expect(
    await h.replaceExerciseHeartRate('hc-ex-1', [
      for (var i = 0; i < 3; i++)
        HealthHeartRateSample(exStart.add(Duration(minutes: 10 * i)), 120 + i),
    ]),
    isTrue,
  );
}

PpgFrame _frame(int i) => PpgFrame(
  t: i / 30,
  r: 180.0 + i % 7,
  g: 60.5 - i % 3,
  r16: [for (var k = 0; k < 16; k++) 170.0 + k + i % 5],
  g16: [for (var k = 0; k < 16; k++) 55.25 + k / 4],
);

MorningMeasurement _morning(
  int n, {
  RestingPosture posture = RestingPosture.lying,
  PpgQuality quality = PpgQuality.good,
  int hour = 7,
  SleepBand? sleepBand,
}) {
  final unusable = quality == PpgQuality.unusable;
  return MorningMeasurement(
    measuredAt: _day(n).add(Duration(hours: hour) - _offset),
    utcOffset: _offset,
    posture: posture,
    deviceManufacturer: 'Hersteller',
    deviceModel: 'Modell-1',
    method: ppgMethod,
    methodVersion: ppgMethodVersion,
    quality: quality,
    restingHrBpm: unusable ? null : 52.3 + n % 4,
    rmssdMs: unusable || quality == PpgQuality.limited ? null : 38.5 + n,
    timingNoiseMs: unusable ? null : 9.5,
    sleepBand: sleepBand,
    cameraIntervalsMs: unusable ? const [] : [1100.5, 1098.25, 1102.0],
    windowStartS: 10,
    windowEndS: 70,
    unusableReason: unusable ? MorningUnusableReason.weakSignal : null,
    beforeValidation: true,
    outsideWindow: false,
  );
}

/// Morgenmessungen über den Port: liegend und sitzend (auch am selben Tag),
/// „eingeschränkt“, eine unbrauchbare, Gurt-RR und Rohsignal.
Future<void> _mornings(MorningStore m) async {
  for (var n = 0; n < 6; n++) {
    final id = await m.add(
      _morning(n, sleepBand: n.isEven ? SleepBand.from6to7 : null),
      beltPackets: [
        RrPacket(
          time: _day(n).add(const Duration(hours: 6, seconds: 1)),
          source: 'Gurt-Test',
          intervals: [1024 + n, 1030, 1018],
        ),
        RrPacket(
          time: _day(n).add(const Duration(hours: 6, seconds: 3)),
          source: 'Gurt-Test',
          intervals: const [1021],
        ),
      ],
      rawSignal: n == 1
          ? MorningRawSignal(
              frames: [for (var i = 0; i < 12; i++) _frame(i)],
              frameGapCount: 1,
              frameGapTotalS: 0.25,
              exposureTimeNs: 16000000,
              iso: 200,
              timestampSource: CameraTimestampSource.realtime,
              rollingShutterSkewNs: 8000000,
              torchStrength: 1,
              saturatedFraction: 0.02,
              cameraId: '0',
              physicalCameraId: '2',
              focalLengthMm: 4.2,
            )
          : null,
    );
    expect(id, greaterThan(0));
  }
  // Am selben Tag sitzend; „eingeschränkt“ ohne RMSSD; unbrauchbar mit Grund.
  await m.add(_morning(2, posture: RestingPosture.sitting, hour: 8));
  await m.add(_morning(3, quality: PpgQuality.limited, hour: 9));
  final unusable = await m.add(
    _morning(4, quality: PpgQuality.unusable, hour: 8),
    rawSignal: MorningRawSignal(
      frames: [for (var i = 0; i < 4; i++) _frame(i)],
      frameGapCount: 0,
      frameGapTotalS: 0,
    ),
  );
  await m.setSleepBand(unusable - 1, SleepBand.under5);
}

TrainingGoal _goal() => TrainingGoal(
  type: GoalType.distance,
  distance: GoalDistance.tenKilometers,
  targetDate: DateTime.utc(2027, 6, 1),
  runDays: const {2, 4, 6},
  maxSessionSeconds: 120 * 60.0,
  weeklyCapSeconds: 240 * 60.0,
  createdAt: DateTime.utc(2026, 11, 1),
  hardSessionEnabled: true,
  currentWeeklySeconds: 150 * 60.0,
  canRun30: ContinuousRun30.yes,
);

/// Plan „adaptiv“ mit einer Lockerung nach PAR-173 (Fassung `feedback`, Grund
/// `readiness`) wie die Nachprüfung der App nach Import oder Morgenmessung.
Future<void> _plan(StorageSession s) async {
  final plans = (s as PlanStorage).plans;
  await (s as GoalStorage).goals.save(_goal(), today: _d0);
  Future<PlanRecalculation> recalc(
    PlanTrigger t,
    int d, {
    Iterable<PlanReadinessDay> readiness = const [],
    String? reason,
  }) => recalculatePlan(
    plans: plans,
    settings: s.settings,
    trigger: t,
    today: _day(d),
    now: _day(d).add(const Duration(hours: 8)),
    readiness: readiness,
    reason: reason,
    warning: (s as WarningStorage).warning,
  );
  await recalc(PlanTrigger.create, 0);
  await SettingsPlanAdaptationStore(s.settings)
      .set(PlanAdaptationMode.adaptive, at: _day(0));
  for (var d = 0; d < 14; d++) {
    final u = await plans.unitOn(_day(d));
    if (u == null || !recoveryEasable(u)) continue;
    final r = await recalc(
      PlanTrigger.feedback,
      d,
      readiness: [
        PlanReadinessDay.number(
          day: _day(d),
          value: 30,
          drivers: const [ReadinessFactorId.sleep],
        ),
      ],
      reason: planReasonReadiness,
    );
    expect(r.wasWritten, isTrue, reason: 'Tag $d');
    return;
  }
  fail('keine harte Einheit in zwei Wochen');
}

Future<void> _populate(StorageSession s) async {
  await _health((s as HealthStorage).health);
  await _mornings((s as MorningStorage).morning);
  await _plan(s);
  for (final e in {..._m3Settings, ..._technical}.entries) {
    await s.settings.set(e.key, e.value, at: _d0);
  }
}
