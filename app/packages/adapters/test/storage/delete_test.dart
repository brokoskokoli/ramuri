import 'dart:io';

import 'package:adapters/adapters.dart' hide RawSteps, ComputedValue;
import 'package:core/core.dart';
import 'package:core/testing/contract_samples.dart' as cs;
import 'package:drift/drift.dart'
    show QueryRow, ResultSetImplementation, Selectable, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import 'support.dart';

const String markerB = 'ANDERE-MARKE-0815';
const String markerDay = 'TAGESWERT-MARKE-0042';
const String markerAll = 'PROFIL-GERAET-MARKE-0007';
const String markerMorning = 'MORGEN-GERAET-MARKE-0099';

/// Synthetische Morgenmessung (WP33) mit Gurt-RR; Hersteller trägt die Marke.
Future<int> addMorning(EncryptedStorageSession s) => s.morning.add(
  MorningMeasurement(
    measuredAt: at(0),
    utcOffset: const Duration(hours: 1),
    posture: RestingPosture.lying,
    deviceManufacturer: markerMorning,
    deviceModel: 'Testmodell',
    method: ppgMethod,
    methodVersion: ppgMethodVersion,
    quality: PpgQuality.good,
    restingHrBpm: 52.3,
    cameraIntervalsMs: const [1100.5, 1180.25],
    beforeValidation: true,
    outsideWindow: false,
  ),
  beltPackets: [
    RrPacket(time: at(1), source: 'strap', intervals: const [1000, 1010]),
  ],
);

final t0u = DateTime.utc(2030, 1, 1, 12);
DateTime at(int s) => t0u.add(Duration(seconds: s));

/// Klartext-Datenbank mit genau den PRAGMAs des Verbindungs-Setups, aber ohne
/// Schlüssel: Die Löschprüfung (Marke weg) muss am Klartext stattfinden, in der
/// Chiffre findet man eine Marke immer nicht (Falle 2). Die Löschlogik ist
/// dieselbe Klasse wie in der verschlüsselten Sitzung.
EncryptedStorageSession openPlain(String path) => EncryptedStorageSession(
  AppDatabase(NativeDatabase(File(path), setup: ConnectionSetup.configure)),
);

class Files {
  Files(String path) : main = File(path), wal = File('$path-wal');
  final File main;
  final File wal;
  bool has(String m) => containsText(main, m) || containsText(wal, m);
  int get walSize => wal.existsSync() ? wal.lengthSync() : 0;
}

Future<void> fill(EncryptedStorageSession s, int runId, String m) async {
  await s.rawData.append(
    runId,
    RawBatch(
      steps: [
        for (var i = 0; i < 20; i++) RawSteps(time: at(i), source: m, count: i),
      ],
      // RR-Pakete (WP26): Quelle trägt die Marke, Werte sind synthetisch.
      rrPackets: [
        for (var i = 0; i < 5; i++)
          RrPacket(time: at(i), source: m, intervals: [1000 + i, 1010]),
      ],
      // Laufbandeinstellungen (WP25), synthetisch.
      beltSettings: [
        for (var i = 0; i < 3; i++)
          BeltSetting(
            offset: Duration(seconds: i * 60),
            speedMetersPerSecond: 2.5 + i,
            inclinePercent: i.isEven ? 1.5 : null,
          ),
      ],
    ),
  );
}

ComputedValue dayValue(String m, int from, int to) => ComputedValue(
  key: 'atl',
  value: 1,
  unit: 'au',
  computedAt: at(300),
  dataFrom: at(from),
  dataTo: at(to),
  measurementCount: 1,
  sources: [m],
  method: 'm',
  methodVersion: 1,
  parameterVersion: 1,
  quality: ValueQuality.good,
);

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = tempDir();
    path = '${dir.path}/plain.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // Läufe A (gelöscht) und B (bleibt), ein überlappender und ein
  // nicht überlappender Tageswert.
  Future<(EncryptedStorageSession, int, int)> setup() async {
    final s = openPlain(path);
    final a = (await s.runs.create(startedAt: at(0))).id;
    await s.runs.setState(a, RunState.finished, endedAt: at(100));
    final b = (await s.runs.create(startedAt: at(1000))).id;
    await s.runs.setState(b, RunState.finished, endedAt: at(1100));
    await fill(s, a, marker);
    await fill(s, b, markerB);
    await s.values.createOriginals(const ValueOwner.day('2030-01-01'), [
      dayValue(markerDay, 10, 20),
    ]);
    await s.values.createOriginals(const ValueOwner.day('2030-01-02'), [
      dayValue('KEIN-TREFFER', 5000, 6000),
    ]);
    return (s, a, b);
  }

  group('Marke nach Löschen eines Laufs (Klartext, Haupt- und WAL-Datei)', () {
    for (final checkpointFirst in [false, true]) {
      test(
        checkpointFirst
            ? 'Marke steht vorher in der Hauptdatei'
            : 'Marke steht vorher nur in der WAL-Datei',
        () async {
          final (s, a, b) = await setup();
          final f = Files(path);
          // Positivkontrolle: Die Marke ist wirklich auffindbar.
          if (checkpointFirst) {
            await s.database
                .customSelect('PRAGMA wal_checkpoint(TRUNCATE)')
                .get();
            expect(containsText(f.main, marker), isTrue, reason: 'Hauptdatei');
            expect(f.walSize, 0);
          } else {
            expect(f.walSize, greaterThan(0), reason: 'WAL hat Frames');
            expect(containsText(f.wal, marker), isTrue, reason: 'WAL-Datei');
            expect(containsText(f.main, marker), isFalse);
          }
          expect(f.has(markerDay), isTrue);

          await s.deleteRun(a);

          expect(containsText(f.main, marker), isFalse, reason: 'Hauptdatei');
          expect(containsText(f.wal, marker), isFalse, reason: 'WAL-Datei');
          expect(f.has(markerDay), isFalse, reason: 'Tageswert');
          // Der andere Lauf und der andere Tageswert bleiben.
          expect(f.has(markerB), isTrue);
          expect(f.has('KEIN-TREFFER'), isTrue);
          expect(await s.runs.get(a), isNull);
          expect((await s.rawData.read(b)).steps.length, 20);
          expect(
            (await s.values.read(const ValueOwner.day('2030-01-02'))).length,
            1,
          );
          await s.close();
        },
      );
    }

    test('Löschen aller Daten: nichts bleibt in beiden Dateien', () async {
      final (s, a, b) = await setup();
      await s.profile.save(const ProfileRecord(birthYear: 1990));
      await s.settings.set('k', markerAll, at: at(0));
      await RestingHrOrigin(
        posture: RestingPosture.sitting,
        measuredAt: at(0),
      ).write(s.settings, at: at(0));
      await s.devices.upsert('dev', displayName: markerAll, at: at(0));
      await s.consents.set(markerAll, ConsentState.granted, at: at(0));
      await addMorning(s);
      final f = Files(path);
      for (final m in [
        marker,
        markerB,
        markerDay,
        markerAll,
        markerMorning,
        SettingKeys.restingHrMeasuredAt,
      ]) {
        expect(f.has(m), isTrue, reason: 'Positivkontrolle $m');
      }
      expect(f.walSize, greaterThan(0));
      await s.deleteAll();
      for (final m in [
        marker,
        markerB,
        markerDay,
        markerAll,
        markerMorning,
        SettingKeys.restingHrMeasuredAt,
      ]) {
        expect(f.has(m), isFalse, reason: m);
      }
      expect(await s.morning.list(), isEmpty);
      expect(await RestingHrOrigin.read(s.settings), isNull);
      expect(await s.settings.all(), isEmpty);
      await s.close();
    });
  });

  test(
    'RR-Pakete: deleteRun entfernt nur die des Laufs, deleteAll alle',
    () async {
      final (s, a, b) = await setup();
      Future<int> count(int runId) async =>
          (await s.rawData.read(runId)).rrPackets.length;
      Future<int> total() async =>
          (await s.database
                      .customSelect('SELECT COUNT(*) AS n FROM raw_rr_packets')
                      .get())
                  .single
                  .data['n']
              as int;
      expect(await count(a), 5, reason: 'Positivkontrolle');
      expect(await count(b), 5);
      await s.deleteRun(a);
      expect(await count(a), 0);
      expect(await count(b), 5, reason: 'anderer Lauf bleibt');
      expect(await total(), 5, reason: 'keine verwaisten Zeilen');
      await s.deleteAll();
      expect(await total(), 0);
      await s.close();
    },
  );

  test('Laufbandeinstellungen: deleteRun entfernt nur die des Laufs, deleteAll alle', () async {
    final (s, a, b) = await setup();
    Future<int> count(int runId) async =>
        (await s.rawData.read(runId)).beltSettings.length;
    Future<int> total() async =>
        (await s.database
                    .customSelect(
                      'SELECT COUNT(*) AS n FROM treadmill_settings',
                    )
                    .get())
                .single
                .data['n']
            as int;
    expect(await count(a), 3, reason: 'Positivkontrolle');
    expect(await count(b), 3);
    await s.deleteRun(a);
    expect(await count(a), 0);
    expect(await count(b), 3, reason: 'anderer Lauf bleibt');
    expect(await total(), 3, reason: 'keine verwaisten Zeilen');
    await s.deleteAll();
    expect(await total(), 0);
    await s.close();
  });

  test('Morgenmessung: deleteRun lässt sie samt Gurt-RR stehen, deleteAll leert beide Tabellen', () async {
    final (s, a, _) = await setup();
    final id = await addMorning(s);
    Future<int> total(String t) async =>
        (await s.database.customSelect('SELECT COUNT(*) AS n FROM $t').get())
                .single
                .data['n']!
            as int;
    await s.deleteRun(a);
    expect(await total('morning_measurements'), 1);
    expect(await total('morning_rr_packets'), 1);
    expect((await s.morning.beltPackets(id)).length, 1);
    await s.deleteAll();
    expect(await total('morning_measurements'), 0);
    expect(await total('morning_rr_packets'), 0);
    await s.close();
  });

  test('Alles löschen entfernt die Karteneinwilligung', () async {
    final (s, _, _) = await setup();
    await s.consents.set(mapProviderSourceKey, ConsentState.granted, at: at(0));
    expect(await s.consents.get(mapProviderSourceKey), ConsentState.granted);
    await s.deleteAll();
    expect(await s.consents.get(mapProviderSourceKey), isNull);
    await s.close();
  });

  test('Alle Tabellen laut sqlite_master sind nach deleteAll leer', () async {
    final (s, a, _) = await setup();
    final db = s.database;
    await s.runs.setState(
      (await s.runs.create(startedAt: at(2000))).id,
      RunState.paused,
    );
    await s.markers.addLap(
      a,
      StoredLap(index: 1, markedAt: at(5), lapTime: const Duration(seconds: 5)),
    );
    await s.markers.openGap(a, RunGapKind.interruption, at(2));
    await s.preprocessing.replace(a, cs.samplePreprocessing());
    await s.sections.replace(a, [cs.sampleSection(0)]);
    await s.values.createOriginals(ValueOwner.run(a), [
      cs.sampleValue('v', 1, sections: cs.sampleValueSections()),
    ]);
    await s.profile.save(const ProfileRecord(birthYear: 1990));
    await s.settings.set('k', 'v', at: at(0));
    await s.warning.set(
      WarningSignal(reportedOn: at(0), source: WarningSource.manual),
    );
    await s.devices.upsert('dev', displayName: 'x', at: at(0));
    await s.consents.set('c', ConsentState.granted, at: at(0));
    // Morgenmessung mit Gurt-RR (Schema 12): keine Kaskade vom Lauf, nur die
    // Löschschleife erreicht beide Tabellen.
    await addMorning(s);
    await db.customStatement("INSERT INTO storage_meta VALUES ('k', 'v')");
    // Leistungsprognose (Schema 5): eine Referenz ohne Lauf (hängt an keiner
    // Kaskade, nur die Löschschleife erreicht sie) und eine mit Lauf.
    for (final (kind, runId) in [('race', null), ('confirmedRun', a)]) {
      await s.prediction.addReference(
        ReferencePerformance(
          kind: ReferenceKind.values.byName(kind),
          distanceMeters: 5000,
          seconds: 1500,
          date: DateTime(2029, 12, 1),
          createdAt: at(10),
          runId: runId == null ? null : '$runId',
        ),
      );
    }
    await s.prediction.rejectSuggestion(a);
    // Trainingsziel (Schema 7): hängt an keinem Lauf, nur die Löschschleife
    // erreicht es.
    await s.goals.save(
      TrainingGoal(
        hardSessionEnabled: false,
        type: GoalType.open,
        runDays: const {1, 3},
        maxSessionSeconds: 3600,
        weeklyCapSeconds: 10800,
        createdAt: at(11),
      ),
      today: DateTime.utc(2026, 11, 1),
    );
    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' "
                  "AND name NOT LIKE 'sqlite_%' AND name != 'sqlite_sequence'",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toList();
    expect(tables.length, greaterThan(10));
    // Vorher: Tabellen mit Nutzdaten haben Zeilen (sonst wäre der Test leer).
    var filled = 0;
    for (final t in tables) {
      final n =
          (await db.customSelect('SELECT count(*) c FROM "$t"').getSingle())
              .read<int>('c');
      if (n > 0) filled++;
    }
    expect(filled, greaterThanOrEqualTo(15));
    for (final t in ['morning_measurements', 'morning_rr_packets']) {
      expect(tables, contains(t));
      expect(
        (await db.customSelect('SELECT count(*) c FROM "$t"').getSingle())
            .read<int>('c'),
        greaterThan(0),
        reason: 'Positivkontrolle $t',
      );
    }

    await s.deleteAll();

    for (final t in [...tables, 'sqlite_sequence']) {
      final n =
          (await db.customSelect('SELECT count(*) c FROM "$t"').getSingle())
              .read<int>('c');
      // Keine Ausnahme: auch storage_meta wird geleert (nur technische Werte,
      // die die App nach dem Löschen nicht braucht).
      expect(n, 0, reason: t);
    }
    await s.close();
  });

  test('Checkpoint nicht durchgelaufen (Leser hält die Datei): Fehler statt Erfolg, Löschen gilt', () async {
    final (s, a, _) = await setup();
    final reader = raw.sqlite3.open(path);
    reader.execute('BEGIN');
    reader.select('SELECT count(*) FROM runs');
    await expectLater(
      s.deleteRun(a),
      throwsA(
        isA<StorageException>().having(
          (e) => e.failure,
          'failure',
          StorageFailure.deletedNotErased,
        ),
      ),
    );
    // Das Löschen selbst ist gültig.
    expect(await s.runs.get(a), isNull);
    // Ehrlich: Die Marke kann noch in der WAL-Datei stehen.
    expect(Files(path).has(marker), isTrue);
    reader.execute('COMMIT');
    reader.close();
    // Ohne Leser läuft der nächste Löschvorgang sauber durch.
    await s.deleteAll();
    expect(Files(path).has(marker), isFalse);
    await s.close();
  });

  test('Tageswert-Paar: beide Zeilen weg, keine verwaiste Zeile in computed_values', () async {
    final (s, a, _) = await setup();
    const day = ValueOwner.day('2030-01-08');
    await s.values.createOriginals(day, [dayValue('PAAR', 0, 99)]);
    await s.values.swapCurrent(day, [dayValue('PAAR', 150, 160)]);
    Future<int> rows(String d) async =>
        (await s.database
                .customSelect(
                  'SELECT count(*) c FROM computed_values WHERE day = ?',
                  variables: [Variable<String>(d)],
                )
                .getSingle())
            .read<int>('c');
    // Positivkontrolle: original und current liegen als zwei Zeilen vor.
    expect(await rows('2030-01-08'), 2);
    await s.deleteRun(a);
    // `read` liefert nur vollständige Paare und sähe eine verwaiste Zeile
    // nicht; darum werden die Zeilen gezählt.
    expect(await rows('2030-01-08'), 0);
    expect(await rows('2030-01-01'), 0, reason: 'überlappender Tageswert');
    expect(await rows('2030-01-02'), 2, reason: 'nicht überlappend bleibt');
    await s.close();
  });

  test(
    'Checkpoint wirft nach erfolgtem Commit: deletedNotErased, nicht failed',
    () async {
      final seed = openPlain(path);
      final a = (await seed.runs.create(startedAt: at(0))).id;
      await fill(seed, a, marker);
      await seed.close();
      final s = EncryptedStorageSession(
        _CheckpointFails(
          NativeDatabase(File(path), setup: ConnectionSetup.configure),
        ),
      );
      await expectLater(
        s.deleteRun(a),
        throwsA(
          isA<StorageException>().having(
            (e) => e.failure,
            'failure',
            StorageFailure.deletedNotErased,
          ),
        ),
      );
      // Das Löschen gilt: Die Transaktion war schon abgeschlossen.
      expect(await s.runs.get(a), isNull);
      await s.close();
    },
  );

  test(
    'Verschlüsselte Sitzung: Löschen läuft und leert die Datenbank',
    () async {
      final s = await EncryptedStorage(
        '${dir.path}/enc.db',
      ).open(testKey()) as EncryptedStorageSession;
      final a = (await s.runs.create(startedAt: at(0))).id;
      await fill(s, a, marker);
      await s.deleteRun(a);
      expect(await s.runs.list(), isEmpty);
      await s.settings.set('k', 'v', at: at(0));
      await s.deleteAll();
      expect(await s.settings.all(), isEmpty);
      await s.close();
    },
  );
}

/// Datenbank, deren WAL-Checkpoint mit einer gewöhnlichen Ausnahme scheitert
/// (Ein-/Ausgabefehler), nachdem die Löschtransaktion abgeschlossen ist.
class _CheckpointFails extends AppDatabase {
  _CheckpointFails(super.e);

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    if (query.contains('wal_checkpoint')) throw StateError('E/A-Fehler');
    return super.customSelect(
      query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }
}
