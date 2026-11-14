import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart' show ArchiveRestoreService;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

// WP32 Teil B: Speicher der Health-Connect-Importdaten (nur synthetische Werte).

final _t0 = DateTime.utc(2030, 1, 1, 22);
DateTime _at(int minutes) => _t0.add(Duration(minutes: minutes));

HealthRecord _sleep(
  String id, {
  String origin = 'com.example.a',
  int len = 480,
  List<HealthSleepStage>? stages,
}) => HealthRecord(
  kind: HealthDataKind.sleep,
  id: id,
  origin: origin,
  start: _at(0),
  end: _at(len),
  offsetSeconds: 3600,
  stages:
      stages ??
      [
        HealthSleepStage(_at(0), _at(60), 4),
        HealthSleepStage(_at(60), _at(120), 5),
      ],
);

HealthRecord _value(
  HealthDataKind k,
  String id,
  double v, {
  String origin = 'com.example.a',
  int min = 480,
}) => HealthRecord(
  kind: k,
  id: id,
  origin: origin,
  start: _at(min),
  end: _at(min),
  value: v,
  unit: 'u',
);

HealthRecord _exercise(
  String id, {
  String origin = 'com.example.a',
  int type = 56,
}) => HealthRecord(
  kind: HealthDataKind.exercise,
  id: id,
  origin: origin,
  start: _at(600),
  end: _at(660),
  exerciseType: type,
);

Future<EncryptedStorageSession> _open(Directory dir) async {
  final db = AppDatabase(
    NativeDatabase(File('${dir.path}/h.db'), setup: ConnectionSetup.configure),
  );
  return EncryptedStorageSession(db);
}

Future<void> _fillAll(DriftHealthStore h) async {
  await h.upsertSleep([_sleep('s1')]);
  await h.upsertValues([
    _value(HealthDataKind.hrvRmssd, 'v1', 42.5),
    _value(HealthDataKind.restingHeartRate, 'v2', 55),
    _value(HealthDataKind.vo2Max, 'v3', 48.25),
  ]);
  await h.upsertExercises([_exercise('e1')]);
  await h.replaceExerciseHeartRate('e1', [
    HealthHeartRateSample(_at(601), 120),
    HealthHeartRateSample(_at(602), 150),
  ]);
}

Future<Map<HealthDataKind, int>> _counts(DriftHealthStore h) async => {
  for (final k in HealthDataKind.values) k: await h.count(k),
};

void main() {
  late Directory dir;
  late EncryptedStorageSession session;
  late DriftHealthStore health;

  setUp(() async {
    dir = tempDir();
    session = await _open(dir);
    health = DriftHealthStore(session.database);
  });
  tearDown(() async {
    await session.database.close();
    dir.deleteSync(recursive: true);
  });

  test(
    'Importdaten machen die Datenbank nicht leer (Wiederherstellen fragt)',
    () async {
      expect(await ArchiveRestoreService.isEmpty(session), isTrue);
      await session.health.upsertValues([
        _value(HealthDataKind.vo2Max, 'v', 48),
      ]);
      expect(await ArchiveRestoreService.isEmpty(session), isFalse);
      await session.health.deleteKind(HealthDataKind.vo2Max);
      expect(await ArchiveRestoreService.isEmpty(session), isTrue);
    },
  );

  group('Upsert je Health-Connect-ID', () {
    test('Schlaf: gleiche ID überschreibt Sitzung und ersetzt die Phasen, kein Duplikat', () async {
      await health.upsertSleep([_sleep('s1')]);
      await health.upsertSleep([
        _sleep(
          's1',
          origin: 'com.example.b',
          len: 400,
          stages: [HealthSleepStage(_at(0), _at(30), 2)],
        ),
      ]);
      final got = await health.sleepSessions(_at(-60), _at(1000));
      expect(got, hasLength(1));
      expect(got.single.origin, 'com.example.b');
      expect(got.single.end, _at(400));
      expect(got.single.stages, hasLength(1));
      expect(got.single.stages.single.stage, 2);
      // Auch die Phasentabelle hat keine Reste der alten Fassung.
      expect(
        (await session.database
                .customSelect('SELECT COUNT(*) AS n FROM health_sleep_stages')
                .getSingle())
            .read<int>('n'),
        1,
      );
    });

    test(
      'Einzelwerte: gleiche ID überschreibt, andere ID ist ein zweiter Satz',
      () async {
        await health.upsertValues([_value(HealthDataKind.hrvRmssd, 'v1', 40)]);
        await health.upsertValues([
          _value(HealthDataKind.hrvRmssd, 'v1', 41, origin: 'com.example.b'),
        ]);
        var got = await health.values(
          HealthDataKind.hrvRmssd,
          _at(0),
          _at(1000),
        );
        expect(got, hasLength(1));
        expect(got.single.value, 41);
        expect(got.single.origin, 'com.example.b');
        expect(got.single.unit, 'u');
        await health.upsertValues([
          _value(HealthDataKind.hrvRmssd, 'v2', 43, min: 500),
        ]);
        got = await health.values(HealthDataKind.hrvRmssd, _at(0), _at(1000));
        expect(got.map((r) => r.id), ['v1', 'v2']);
      },
    );

    test('Einheiten: gleiche ID überschreibt und behält die Pulswerte', () async {
      await health.upsertExercises([_exercise('e1')]);
      await health.replaceExerciseHeartRate('e1', [
        HealthHeartRateSample(_at(601), 120),
      ]);
      await health.upsertExercises([
        _exercise('e1', type: 8, origin: 'com.example.b'),
      ]);
      final got = await health.exercises(_at(0), _at(1000));
      expect(got, hasLength(1));
      expect(got.single.exerciseType, 8);
      expect(got.single.origin, 'com.example.b');
      expect(
        (await health.exerciseHeartRate('e1')).map((s) => s.beatsPerMinute),
        [120],
      );
      // Pulswerte ersetzen statt anhängen; unbekannte Einheit speichert nichts.
      expect(
        await health.replaceExerciseHeartRate('e1', [
          HealthHeartRateSample(_at(603), 99),
        ]),
        isTrue,
      );
      expect(
        (await health.exerciseHeartRate('e1')).map((s) => s.beatsPerMinute),
        [99],
      );
      expect(
        await health.replaceExerciseHeartRate('fremd', [
          HealthHeartRateSample(_at(603), 99),
        ]),
        isFalse,
      );
      expect(await health.count(HealthDataKind.heartRate), 1);
    });

    test('Die ID ist je Tabelle eindeutig: gleiche ID in zwei Tabellen sind zwei Sätze', () async {
      await health.upsertSleep([_sleep('x')]);
      await health.upsertValues([_value(HealthDataKind.vo2Max, 'x', 50)]);
      await health.upsertExercises([_exercise('x')]);
      expect(await health.count(HealthDataKind.sleep), 1);
      expect(await health.count(HealthDataKind.vo2Max), 1);
      expect(await health.count(HealthDataKind.exercise), 1);
    });

    test(
      'falsche Art oder fehlender Wert: ArgumentError, nichts gespeichert',
      () async {
        expect(
          () => health.upsertSleep([_value(HealthDataKind.vo2Max, 'a', 1)]),
          throwsArgumentError,
        );
        expect(() => health.upsertValues([_sleep('a')]), throwsArgumentError);
        expect(
          () => health.upsertValues([
            HealthRecord(
              kind: HealthDataKind.vo2Max,
              id: 'a',
              origin: 'o',
              start: _t0,
              end: _t0,
            ),
          ]),
          throwsArgumentError,
        );
        expect(
          () => health.upsertExercises([_sleep('a')]),
          throwsArgumentError,
        );
        expect((await _counts(health)).values.every((n) => n == 0), isTrue);
      },
    );
  });

  test('Lesen nach Zeitraum: Einzelwerte [von, bis), Sitzungen und Einheiten berühren das Fenster', () async {
    await health.upsertValues([
      _value(HealthDataKind.restingHeartRate, 'a', 50, min: 10),
      _value(HealthDataKind.restingHeartRate, 'b', 51, min: 20),
      _value(HealthDataKind.restingHeartRate, 'c', 52, min: 30),
      _value(HealthDataKind.hrvRmssd, 'd', 40, min: 20),
    ]);
    expect(
      (await health.values(
        HealthDataKind.restingHeartRate,
        _at(20),
        _at(30),
      )).map((r) => r.id),
      ['b'],
    );
    await health.upsertSleep([_sleep('s1', len: 60)]);
    expect(await health.sleepSessions(_at(60), _at(120)), isEmpty);
    expect(await health.sleepSessions(_at(59), _at(120)), hasLength(1));
    expect(await health.sleepSessions(_at(-60), _at(0)), isEmpty);
    await health.upsertExercises([_exercise('e1')]);
    expect(await health.exercises(_at(660), _at(700)), isEmpty);
    expect(await health.exercises(_at(659), _at(700)), hasLength(1));
    expect(
      () => health.values(HealthDataKind.sleep, _at(0), _at(1)),
      throwsArgumentError,
    );
  });

  group('Löschen', () {
    Future<void> manual() => session.database.customStatement(
      "INSERT INTO manual_trainings (day, kind, duration_s, rpe, hc_id) VALUES ('2030-01-02', 'run', 3600, 5, 'e1')",
    );

    Future<int> manualCount() async =>
        (await session.database
                .customSelect('SELECT COUNT(*) AS n FROM manual_trainings')
                .getSingle())
            .read<int>('n');

    for (final (kind, gone) in [
      (HealthDataKind.sleep, {HealthDataKind.sleep}),
      (HealthDataKind.hrvRmssd, {HealthDataKind.hrvRmssd}),
      (HealthDataKind.restingHeartRate, {HealthDataKind.restingHeartRate}),
      (HealthDataKind.vo2Max, {HealthDataKind.vo2Max}),
      (HealthDataKind.heartRate, {HealthDataKind.heartRate}),
      (
        HealthDataKind.exercise,
        {HealthDataKind.exercise, HealthDataKind.heartRate},
      ),
    ]) {
      test('${kind.key}: leert nur diese Art, Nachtrag bleibt', () async {
        await _fillAll(health);
        await manual();
        final before = await _counts(health);
        expect(before.values.every((n) => n > 0), isTrue);
        await health.deleteKind(kind);
        final after = await _counts(health);
        for (final k in HealthDataKind.values) {
          expect(
            after[k],
            gone.contains(k) ? 0 : before[k],
            reason: '${kind.key} -> ${k.key}',
          );
        }
        expect(await manualCount(), 1);
        // Schlafphasen ohne Sitzung bleiben nie stehen.
        if (kind == HealthDataKind.sleep) {
          expect(
            (await session.database
                    .customSelect(
                      'SELECT COUNT(*) AS n FROM health_sleep_stages',
                    )
                    .getSingle())
                .read<int>('n'),
            0,
          );
        }
      });
    }

    test('Alles löschen leert alle Health-Tabellen und den Nachtrag', () async {
      await _fillAll(health);
      await manual();
      await session.deleteAll();
      expect((await _counts(health)).values, everyElement(0));
      expect(await manualCount(), 0);
      for (final t in [
        'health_sleep_sessions',
        'health_sleep_stages',
        'health_values',
        'health_exercises',
        'health_exercise_heart_rates',
      ]) {
        expect(
          (await session.database
                  .customSelect('SELECT COUNT(*) AS n FROM $t')
                  .getSingle())
              .read<int>('n'),
          0,
          reason: t,
        );
      }
    });
  });

  test('manual_trainings.hc_id: eindeutig, mehrere ohne ID erlaubt, leere ID abgelehnt', () async {
    final db = session.database;
    Future<void> ins(String? hc) => db.customStatement(
      "INSERT INTO manual_trainings (day, kind, duration_s, rpe, hc_id) VALUES ('2030-01-02', 'run', 60, 1, ?)",
      [hc],
    );
    await ins(null);
    await ins(null);
    await ins('e1');
    await expectLater(ins('e1'), throwsA(anything));
    await expectLater(ins(''), throwsA(anything));
  });
}
