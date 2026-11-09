import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../generated_migrations/schema.dart';
import 'delete_test.dart' show Files, openPlain;
import 'support.dart';

// Gesundheitsdaten (RPE, Befinden, Beschwerden, Notiz) sind hier synthetisch.
const String _noteMarker = 'NOTIZ-MARKE-5150';
const String _complaintMarker = 'BESCHWERDE-MARKE-6161';

final DateTime _t0 = DateTime.utc(2030, 1, 1, 12);
DateTime _at(int s) => _t0.add(Duration(seconds: s));

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = tempDir();
    path = '${dir.path}/test.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<AppDatabase> openDb() async => (await EncryptedStorage(
    path,
  ).open(testKey()) as EncryptedStorageSession).database;

  Future<void> exec(AppDatabase db, String sql) => db.customStatement(sql);

  Future<void> expectRejected(AppDatabase db, String sql, String why) async {
    await expectLater(
      exec(db, sql),
      throwsA(anything),
      reason: '$why muss die CHECK-Bedingung verletzen',
    );
  }

  Future<int> count(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT count(*) c FROM $table').getSingle())
              .data['c']
          as int;

  group('CHECK-Bedingungen von run_feedback (an den Modellgrenzen)', () {
    late AppDatabase db;
    setUp(() async {
      db = await openDb();
      await exec(
        db,
        "INSERT INTO runs (id, state, started_at_us) VALUES (1, 'active', 1)",
      );
    });
    tearDown(() => db.close());

    String insert(String col, String v) =>
        'INSERT INTO run_feedback (run_id, $col) VALUES (1, $v)';
    Future<void> clear() => exec(db, 'DELETE FROM run_feedback');

    for (final (v, ok) in [
      ('-1', false),
      ('0', true),
      ('10', true),
      ('11', false),
      ('5.5', false),
    ]) {
      test('RPE $v ${ok ? 'gültig' : 'abgelehnt'}', () async {
        if (ok) {
          await exec(db, insert('rpe', v));
          expect(await count(db, 'run_feedback'), 1);
        } else {
          await expectRejected(db, insert('rpe', v), 'RPE $v');
        }
      });
    }

    for (final (v, ok) in [
      ('0', false),
      ('1', true),
      ('5', true),
      ('6', false),
      ('4.5', false),
    ]) {
      test('Befinden $v ${ok ? 'gültig' : 'abgelehnt'}', () async {
        if (ok) {
          await exec(db, insert('wellbeing', v));
          expect(await count(db, 'run_feedback'), 1);
        } else {
          await expectRejected(db, insert('wellbeing', v), 'Befinden $v');
        }
      });
    }

    test('höchstens eine Zeile je Lauf', () async {
      await exec(db, insert('rpe', '3'));
      await expectRejected(db, insert('rpe', '4'), 'zweite Zeile');
    });

    test(
      'Antwort auf die Warnsignal-Frage nur mit Beschwerden und nur ja/nein',
      () async {
        await expectRejected(
          db,
          insert('warning_answer', "'yes'"),
          'Antwort ohne Beschwerden',
        );
        await exec(
          db,
          "INSERT INTO run_feedback (run_id, complaints, warning_answer) "
          "VALUES (1, 'x', 'yes')",
        );
        await clear();
        await expectRejected(
          db,
          "INSERT INTO run_feedback (run_id, complaints, warning_answer) "
              "VALUES (1, 'x', 'maybe')",
          'unbekannte Antwort',
        );
      },
    );

    test('sRPE nur ganz und nur mit RPE', () async {
      await expectRejected(
        db,
        'INSERT INTO run_feedback (run_id, wellbeing, srpe_points, srpe_duration_s, '
            "srpe_method, srpe_method_version) VALUES (1, 3, 10, 60, 'm', 1)",
        'sRPE ohne RPE',
      );
      await expectRejected(
        db,
        'INSERT INTO run_feedback (run_id, rpe, srpe_points) VALUES (1, 3, 10)',
        'unvollständiger sRPE',
      );
      await expectRejected(
        db,
        'INSERT INTO run_feedback (run_id, rpe, srpe_points, srpe_duration_s, '
            "srpe_method, srpe_method_version) VALUES (1, 3, -1, 60, 'm', 1)",
        'negative Punkte',
      );
    });

    test('Zeile ohne Lauf ist ausgeschlossen (Fremdschlüssel)', () async {
      await expectRejected(
        db,
        'INSERT INTO run_feedback (run_id, rpe) VALUES (99, 3)',
        'unbekannter Lauf',
      );
    });
  });

  group('CHECK-Bedingungen von manual_trainings', () {
    late AppDatabase db;
    setUp(() async => db = await openDb());
    tearDown(() => db.close());

    String insert({
      String day = "'2030-01-01'",
      String kind = "'other'",
      String duration = '60',
      String rpe = '5',
    }) =>
        'INSERT INTO manual_trainings (day, kind, duration_s, rpe) '
        'VALUES ($day, $kind, $duration, $rpe)';

    test('gültige Zeile', () async {
      await exec(db, insert());
      await exec(db, insert(kind: "'run'", rpe: '0', duration: '1'));
      expect(await count(db, 'manual_trainings'), 2);
    });

    for (final (v, ok) in [
      ('-1', false),
      ('0', true),
      ('10', true),
      ('11', false),
      ('5.5', false),
    ]) {
      test('RPE $v ${ok ? 'gültig' : 'abgelehnt'}', () async {
        if (ok) {
          await exec(db, insert(rpe: v));
        } else {
          await expectRejected(db, insert(rpe: v), 'RPE $v');
        }
      });
    }

    for (final v in ['0', '-1', '1.5']) {
      test('Dauer $v abgelehnt', () async {
        await expectRejected(db, insert(duration: v), 'Dauer $v');
      });
    }

    test('Datum und Art', () async {
      for (final bad in [
        "'2030-02-30'",
        "'30.01.2030'",
        "'abcd-ef-gh'",
        "'2030-1-1'",
        'NULL',
      ]) {
        await expectRejected(db, insert(day: bad), 'Datum $bad');
      }
      await expectRejected(db, insert(kind: "'walk'"), 'Art walk');
      await expectRejected(db, insert(kind: 'NULL'), 'Art fehlt');
    });

    test('RPE ist Pflicht', () async {
      await expectRejected(db, insert(rpe: 'NULL'), 'RPE fehlt');
    });

    test('nachgetragenes Training steht nie in runs', () async {
      final s = await EncryptedStorage(path).open(testKey());
      addTearDown(s.close);
      await s.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2030, 1, 1),
          kind: ManualTrainingKind.run,
          duration: const Duration(minutes: 30),
          rpe: 4,
        ),
      );
      expect(await s.runs.list(), isEmpty);
      expect(await s.preprocessing.readOverviews(), isEmpty);
    });
  });

  group('Migration von Schema 4 mit Bestandsdaten', () {
    test('Daten bleiben, neue Tabellen leer und benutzbar, Schema = Dump v5', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final v4 = await verifier.schemaAt(4);
      v4.rawDatabase
        ..execute(
          "INSERT INTO runs (id, state, started_at_us, ended_at_us) "
          "VALUES (7, 'finished', 1, 9)",
        )
        ..execute(
          "INSERT INTO preprocessing_results (run_id, method, method_version, "
          "parameter_version, computed_at_us, total_time_s, moving_time_s, "
          "distance_m, average_bpm, best_pace_s_per_km, lap_count) "
          "VALUES (7, 'run-overview', 2, 4, 5, 61.5, 60.0, 1000.5, 150.0, 300.0, 2)",
        )
        ..execute(
          "INSERT INTO computed_values (run_id, value_key, role, value_real, unit, "
          "computed_at_us, measurement_count, sources, method, method_version, "
          "parameter_version, quality) VALUES (7, 'trimp_run', 'current', 42.0, "
          "'points', 99, 3, '[]', 'edwards', 1, 4, 'good')",
        )
        ..execute("INSERT INTO settings VALUES ('units', 'km', 1)");
      final db = AppDatabase(v4.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 5);

      expect(await count(db, 'runs'), 1);
      final pre = await db
          .customSelect('SELECT * FROM preprocessing_results')
          .getSingle();
      expect(pre.data['moving_time_s'], 60.0);
      expect(pre.data['best_pace_s_per_km'], 300.0);
      final v = await db
          .customSelect('SELECT * FROM computed_values')
          .getSingle();
      expect(v.data['value_real'], 42.0);
      expect(await count(db, 'settings'), 1);
      // Neu und leer, aber benutzbar: Kaskade und CHECK greifen sofort.
      expect(await count(db, 'run_feedback'), 0);
      expect(await count(db, 'manual_trainings'), 0);
      await exec(db, 'INSERT INTO run_feedback (run_id, rpe) VALUES (7, 4)');
      await exec(
        db,
        "INSERT INTO manual_trainings (day, kind, duration_s, rpe) VALUES ('2030-01-01', 'other', 60, 3)",
      );
      await expectRejected(
        db,
        'INSERT INTO run_feedback (run_id, rpe) VALUES (7, 11)',
        'CHECK nach Migration',
      );
      // Die Prüfverbindung des Verifiers hat Fremdschlüssel aus.
      await exec(db, 'PRAGMA foreign_keys = ON');
      await exec(db, 'DELETE FROM runs WHERE id = 7');
      expect(await count(db, 'run_feedback'), 0);
      expect(await count(db, 'manual_trainings'), 1);
    });

    test('Migration läuft über die App-Strategie (Version 4 -> 5) auf verschlüsselter Datei', () async {
      // Schema 4 aus dem Dump aufbauen: zwei Tabellen der App weglassen.
      final s0 = await EncryptedStorage(path).open(testKey());
      final db0 = (s0 as EncryptedStorageSession).database;
      final r = (await s0.runs.create(startedAt: _at(0))).id;
      await s0.runs.setState(r, RunState.finished, endedAt: _at(60));
      await exec(db0, 'DROP TABLE run_feedback');
      await exec(db0, 'DROP TABLE manual_trainings');
      await exec(db0, 'PRAGMA user_version = 4');
      await s0.close();

      final s1 = await EncryptedStorage(path).open(testKey());
      addTearDown(s1.close);
      expect((await s1.runs.get(r)), isNotNull);
      await s1.subjective.save(r, RunSubjective(rpe: 6));
      expect((await s1.subjective.read(r))!.subjective.rpe, 6);
      final db1 = (s1 as EncryptedStorageSession).database;
      expect(
        (await db1.customSelect('PRAGMA user_version').getSingle())
            .data
            .values
            .single,
        5,
      );
      await db1.validateDatabaseSchema();
    });
  });

  group('Löschen', () {
    Future<EncryptedStorageSession> setup() async {
      final s = openPlain(path);
      final a = (await s.runs.create(startedAt: _at(0))).id;
      await s.runs.setState(a, RunState.finished, endedAt: _at(100));
      final b = (await s.runs.create(startedAt: _at(1000))).id;
      await s.runs.setState(b, RunState.finished, endedAt: _at(1100));
      await s.subjective.save(
        a,
        RunSubjective(rpe: 5, complaints: _complaintMarker, note: _noteMarker),
        srpe: SrpeLoad.compute(duration: const Duration(minutes: 45), rpe: 5),
      );
      await s.subjective.save(b, RunSubjective(rpe: 3, note: 'bleibt'));
      await s.manualTrainings.add(
        ManualTraining(
          day: DateTime.utc(2030, 1, 1),
          kind: ManualTrainingKind.other,
          duration: const Duration(minutes: 20),
          rpe: 4,
        ),
      );
      return s;
    }

    test(
      'Lauf löschen entfernt Angaben und sRPE, Inhalt auch aus der Datei',
      () async {
        final s = await setup();
        addTearDown(s.close);
        final f = Files(path);
        expect(f.has(_noteMarker), isTrue, reason: 'Positivkontrolle');
        final ids = (await s.subjective.readAll()).keys.toList()..sort();
        await s.deleteRun(ids.first);
        expect(await s.subjective.read(ids.first), isNull);
        expect(await s.subjective.read(ids.last), isNotNull);
        expect(await count(s.database, 'manual_trainings'), 1);
        expect(f.has(_noteMarker), isFalse, reason: 'Notiz');
        expect(f.has(_complaintMarker), isFalse, reason: 'Beschwerde');
      },
    );

    test(
      'Lauf löschen ohne Kaskade (foreign_keys=OFF): ausdrücklich gelöscht',
      () async {
        final s = await setup();
        addTearDown(s.close);
        final ids = (await s.subjective.readAll()).keys.toList()..sort();
        await s.database.customStatement('PRAGMA foreign_keys = OFF');
        await s.deleteRun(ids.first);
        expect(await count(s.database, 'run_feedback'), 1);
        expect(await s.subjective.read(ids.first), isNull);
      },
    );

    test('Alles löschen leert beide Tabellen, auch ohne Kaskade', () async {
      final s = await setup();
      addTearDown(s.close);
      final f = Files(path);
      await s.database.customStatement('PRAGMA foreign_keys = OFF');
      await s.deleteAll();
      expect(await count(s.database, 'run_feedback'), 0);
      expect(await count(s.database, 'manual_trainings'), 0);
      expect(f.has(_noteMarker), isFalse);
      expect(f.has(_complaintMarker), isFalse);
    });

    test('ein nachgetragenes Training einzeln löschen', () async {
      final s = await setup();
      addTearDown(s.close);
      final t = (await s.manualTrainings.list()).single;
      await s.manualTrainings.delete(t.id);
      expect(await s.manualTrainings.list(), isEmpty);
      expect(await count(s.database, 'run_feedback'), 2);
    });
  });
}
