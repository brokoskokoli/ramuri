import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show MigrationStrategy, Migrator;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';
import '../generated_migrations/schema.dart';

/// Pro lauf-abhängiger Tabelle eine gültige Zeile für Lauf `:run`.
/// Neue Tabelle mit Fremdschlüssel auf `runs` ohne Eintrag hier macht
/// 'jede lauf-abhängige Tabelle ist abgedeckt' rot.
const _rowFor = <String, String>{
  'laps':
      'INSERT INTO laps (run_id, lap_index, marked_at_us, lap_time_s) '
      'VALUES (?, 1, 10, 300.0)',
  'run_gaps': "INSERT INTO run_gaps (run_id, kind, start_us) VALUES (?, 'interruption', 5)",
  'raw_positions':
      "INSERT INTO raw_positions (run_id, time_us, source, state, latitude_deg, longitude_deg) "
      "VALUES (?, 1, 'gps', 'present', 52.0, 13.0)",
  'raw_heart_rates':
      "INSERT INTO raw_heart_rates (run_id, time_us, source, state, bpm, contact) "
      "VALUES (?, 1, 'strap', 'present', 140, 'good')",
  'raw_altitudes':
      "INSERT INTO raw_altitudes (run_id, time_us, source, state, altitude_m) "
      "VALUES (?, 1, 'gps', 'present', 35.5)",
  'raw_steps':
      "INSERT INTO raw_steps (run_id, time_us, source, state, step_count) "
      "VALUES (?, 1, 'phone', 'present', 12)",
  'preprocessing_results':
      "INSERT INTO preprocessing_results (run_id, method, method_version, parameter_version, computed_at_us) "
      "VALUES (?, 'preprocessing', 1, 2, 99)",
  'preprocessed_samples':
      "INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state) "
      "VALUES (?, 'position', 1, 1, 'present')",
  'preprocessed_spans':
      "INSERT INTO preprocessed_spans (run_id, kind, start_us, end_us) "
      "VALUES (?, 'moving', 1, 9)",
  'rated_sections':
      'INSERT INTO rated_sections (run_id, start_us, end_us, method, method_version, '
      'parameter_version, assessed_at_us, heart_rate_present, heart_rate_estimated, '
      'heart_rate_unavailable, heart_rate_discarded, position_present, position_estimated, '
      'position_unavailable, position_discarded, missing_heart_rate_share, '
      'longest_heart_rate_gap_s, meets_heart_rate_gap_rule, settling_overlap_s, settling_share, gps_gaps) '
      "VALUES (?, 1, 9, 'section-quality', 1, 2, 99, 1, 0, 0, 0, 1, 0, 0, 0, 0.0, 0.0, 1, 0.0, 0.0, '[]')",
  'computed_values':
      "INSERT INTO computed_values (run_id, value_key, role, value_real, unit, computed_at_us, "
      "measurement_count, sources, method, method_version, parameter_version, quality) "
      "VALUES (?, 'vo2max', 'original', 48.0, 'ml/(kg*min)', 99, 3, '[\"strap\"]', 'acsm', 1, 2, 'good')",
};

const _rawTables = [
  'raw_positions',
  'raw_heart_rates',
  'raw_altitudes',
  'raw_steps',
];

Future<void> _exec(
  AppDatabase db,
  String sql, [
  List<Object?> args = const [],
]) => db.customStatement(sql, args);

Future<int> _count(AppDatabase db, String table, [int? run]) async {
  final rows = await db
      .customSelect(
        'SELECT count(*) c FROM $table'
        '${run == null ? '' : ' WHERE run_id = $run'}',
      )
      .get();
  return rows.single.data['c'] as int;
}

Future<void> _expectAborted(Future<void> f, String reason) async {
  Object? caught;
  try {
    await f;
  } catch (e) {
    caught = e;
  }
  expect(caught, isNotNull, reason: reason);
  expect(caught.toString(), contains(reason));
}

Future<void> _insertRun(AppDatabase db, int id) => _exec(
  db,
  "INSERT INTO runs (id, state, started_at_us) VALUES (?, 'active', 1)",
  [id],
);

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

  group('Schema und Dump', () {
    test(
      'erzeugtes Schema der verschlüsselten Datenbank = Dump Version 4',
      () async {
        final db = await openDb();
        addTearDown(db.close);
        await SchemaVerifier(GeneratedHelper()).migrateAndValidate(db, 4);
      },
    );

    test('erzeugtes Schema = aktueller Code (createAll)', () async {
      final db = await openDb();
      addTearDown(db.close);
      await db.validateDatabaseSchema();
    });

    test('Mutation des Schemas ist für den Dump-Test sichtbar', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _exec(db, 'DROP TRIGGER raw_steps_no_update');
      await expectLater(
        SchemaVerifier(GeneratedHelper()).migrateAndValidate(db, 4),
        throwsA(isA<SchemaMismatch>()),
      );
    });

    test('Meta-Tabelle aus Teil A ist Teil von Version 4', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _exec(db, "INSERT INTO storage_meta VALUES ('k', 'v')");
      expect(await _count(db, 'storage_meta'), 1);
      expect(db.schemaVersion, 4);
      final v = await db.customSelect('PRAGMA user_version').get();
      expect(v.single.data.values.single, 4);
    });
  });

  group('Fremdschlüssel und Kaskade', () {
    test('jede lauf-abhängige Tabelle ist abgedeckt', () async {
      final db = await openDb();
      addTearDown(db.close);
      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='table' "
                    "AND name NOT LIKE 'sqlite_%'",
                  )
                  .get())
              .map((r) => r.data['name'] as String);
      final dependent = <String>{};
      for (final t in tables) {
        final fks = await db
            .customSelect("SELECT * FROM pragma_foreign_key_list('$t')")
            .get();
        for (final fk in fks) {
          if (fk.data['table'] == 'runs') {
            dependent.add(t);
            expect(
              fk.data['on_delete'],
              'CASCADE',
              reason: '$t muss mit dem Lauf kaskadieren',
            );
          }
        }
      }
      expect(dependent, _rowFor.keys.toSet());
    });

    test(
      'Löschen eines Laufs entfernt alle seine Zeilen, der andere Lauf bleibt',
      () async {
        final db = await openDb();
        addTearDown(db.close);
        await _insertRun(db, 1);
        await _insertRun(db, 2);
        for (final sql in _rowFor.values) {
          await _exec(db, sql, [1]);
          await _exec(db, sql, [2]);
        }
        for (final t in _rowFor.keys) {
          expect(await _count(db, t, 1), 1, reason: '$t vorher');
        }
        await _exec(db, 'DELETE FROM runs WHERE id = 1');
        for (final t in _rowFor.keys) {
          expect(await _count(db, t, 1), 0, reason: '$t Lauf 1 nach Löschen');
          expect(await _count(db, t, 2), 1, reason: '$t Lauf 2 bleibt');
        }
      },
    );

    test(
      'alle Läufe löschen hinterlässt leere lauf-abhängige Tabellen',
      () async {
        final db = await openDb();
        addTearDown(db.close);
        await _insertRun(db, 1);
        await _insertRun(db, 2);
        for (final sql in _rowFor.values) {
          await _exec(db, sql, [1]);
          await _exec(db, sql, [2]);
        }
        await _exec(db, 'DELETE FROM runs');
        for (final t in _rowFor.keys) {
          expect(await _count(db, t), 0, reason: t);
        }
      },
    );

    test('Zeile ohne Lauf wird abgelehnt', () async {
      final db = await openDb();
      addTearDown(db.close);
      for (final entry in _rowFor.entries) {
        await expectLater(
          _exec(db, entry.value, [99]),
          throwsA(anything),
          reason: entry.key,
        );
      }
    });
  });

  group('Rohdaten nur anhängen', () {
    for (final table in _rawTables) {
      test(
        '$table: UPDATE bricht ab, DELETE einzeln bricht ab, Kaskade geht',
        () async {
          final db = await openDb();
          addTearDown(db.close);
          await _insertRun(db, 1);
          await _exec(db, _rowFor[table]!, [1]);
          await _expectAborted(
            _exec(db, 'UPDATE $table SET source = \'x\''),
            'append-only',
          );
          await _expectAborted(
            _exec(db, 'UPDATE $table SET run_id = run_id'),
            'append-only',
          );
          await _expectAborted(
            _exec(db, 'DELETE FROM $table'),
            'only with its run',
          );
          expect(await _count(db, table), 1);
          await _exec(db, 'DELETE FROM runs WHERE id = 1');
          expect(await _count(db, table), 0);
        },
      );
    }

    test('Rohdaten lassen sich anhängen, auch viele', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      for (var i = 0; i < 50; i++) {
        await _exec(db, _rowFor['raw_heart_rates']!, [1]);
      }
      expect(await _count(db, 'raw_heart_rates', 1), 50);
    });

    test('Fehlertext trägt keine Daten (Trigger-Fehler über translateStorageError)', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      await _exec(
        db,
        "INSERT INTO raw_heart_rates (run_id, time_us, source, state, bpm, contact) "
        "VALUES (1, 1, '$marker', 'present', 140, 'good')",
      );
      Object? caught;
      try {
        await _exec(db, "UPDATE raw_heart_rates SET source = '$marker-neu'");
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      // Positivkontrolle: Die rohe drift-Ausnahme trägt das Statement.
      expect(caught.toString(), contains(marker));
      final translated = translateStorageError(caught!);
      expect(translated.toString(), isNot(contains(marker)));
      expect(translated.toString(), isNot(contains('raw_heart_rates')));
    });
  });

  group('Rohdaten: Zustand unavailable ohne Wert (FR-0057)', () {
    // Je Tabelle: Spalten bis einschließlich Zustand, Wertspalten, Beispielwerte.
    const tables = <String, (String, String, String)>{
      'raw_positions': (
        'latitude_deg, longitude_deg',
        '52.0, 13.0',
        'NULL, NULL',
      ),
      'raw_heart_rates': ('bpm, contact', "140, 'good'", "NULL, 'unsupported'"),
      'raw_altitudes': ('altitude_m', '35.5', 'NULL'),
      'raw_steps': ('step_count', '12', 'NULL'),
    };
    for (final e in tables.entries) {
      Future<void> insert(AppDatabase db, String state, String values) => _exec(
        db,
        'INSERT INTO ${e.key} (run_id, time_us, source, state, ${e.value.$1}) '
        "VALUES (1, 1, 'q', '$state', $values)",
      );
      test(
        '${e.key}: unavailable ohne Wert geht, present ohne Wert scheitert',
        () async {
          final db = await openDb();
          addTearDown(db.close);
          await _insertRun(db, 1);
          await insert(db, 'present', e.value.$2);
          await insert(db, 'unavailable', e.value.$3);
          expect(await _count(db, e.key, 1), 2);
          for (final state in ['present', 'estimated', 'discarded']) {
            await _expectAborted(
              insert(db, state, e.value.$3),
              'CHECK constraint failed',
            );
          }
          expect(await _count(db, e.key, 1), 2);
        },
      );
    }
  });

  group('Berechnete Werte: original und current', () {
    Future<void> insertValue(
      AppDatabase db, {
      int? run = 1,
      String? day,
      String key = 'vo2max',
      String role = 'original',
      double value = 48.0,
    }) => _exec(
      db,
      'INSERT INTO computed_values (run_id, day, value_key, role, value_real, unit, '
      'computed_at_us, measurement_count, sources, method, method_version, '
      'parameter_version, quality) '
      "VALUES (?, ?, ?, ?, ?, 'ml/(kg*min)', 99, 3, '[]', 'acsm', 1, 2, 'good')",
      [run, day, key, role, value],
    );

    test('UPDATE einer Zeile original bricht ab, auch Umbenennen zu original', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      await insertValue(db);
      await insertValue(db, role: 'current', value: 50.0);
      await _expectAborted(
        _exec(
          db,
          "UPDATE computed_values SET value_real = 1 WHERE role = 'original'",
        ),
        'immutable',
      );
      await _expectAborted(
        _exec(
          db,
          "UPDATE computed_values SET quality = 'good' WHERE role = 'original'",
        ),
        'immutable',
      );
      await _expectAborted(
        _exec(
          db,
          "UPDATE computed_values SET role = 'original' WHERE role = 'current'",
        ),
        'immutable',
      );
      final o = await db
          .customSelect(
            "SELECT value_real v FROM computed_values WHERE role='original'",
          )
          .get();
      expect(o.single.data['v'], 48.0);
    });

    test('current darf geändert werden (Neuberechnung)', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      await insertValue(db, role: 'current', value: 50.0);
      await _exec(
        db,
        "UPDATE computed_values SET value_real = 51.0 WHERE role = 'current'",
      );
      final r = await db
          .customSelect(
            "SELECT value_real v FROM computed_values WHERE role='current'",
          )
          .get();
      expect(r.single.data['v'], 51.0);
    });

    test('höchstens eine Zeile original und eine current je Wert', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      await _insertRun(db, 2);
      await insertValue(db);
      await insertValue(db, role: 'current');
      await expectLater(insertValue(db), throwsA(anything));
      await expectLater(insertValue(db, role: 'current'), throwsA(anything));
      // Anderer Wert und anderer Lauf bleiben möglich.
      await insertValue(db, key: 'aerobic_efficiency');
      await insertValue(db, run: 2);
      expect(await _count(db, 'computed_values'), 4);
    });

    test('Tageswerte: Eindeutigkeit je Tag, entweder Lauf oder Tag', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      await insertValue(db, run: null, day: '2026-11-04', key: 'ctl');
      await insertValue(
        db,
        run: null,
        day: '2026-11-04',
        key: 'ctl',
        role: 'current',
      );
      await expectLater(
        insertValue(db, run: null, day: '2026-11-04', key: 'ctl'),
        throwsA(anything),
      );
      await insertValue(db, run: null, day: '2026-11-05', key: 'ctl');
      await expectLater(insertValue(db, run: null), throwsA(anything));
      await expectLater(
        insertValue(db, run: 1, day: '2026-11-04'),
        throwsA(anything),
      );
    });

    test('Löschen des Laufs löscht auch original (Kaskade)', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      await insertValue(db);
      await _exec(db, 'DELETE FROM runs WHERE id = 1');
      expect(await _count(db, 'computed_values'), 0);
    });
  });

  group('Indizes und Zustände', () {
    test('Zugriff je Lauf und Zeit ist indiziert', () async {
      final db = await openDb();
      addTearDown(db.close);
      const timeColumn = {
        'raw_positions': 'time_us',
        'raw_heart_rates': 'time_us',
        'raw_altitudes': 'time_us',
        'raw_steps': 'time_us',
        'preprocessed_samples': 'time_us',
        'preprocessed_spans': 'start_us',
        'rated_sections': 'start_us',
        'run_gaps': 'start_us',
        'laps': 'marked_at_us',
      };
      for (final e in timeColumn.entries) {
        final indexes = await db
            .customSelect("SELECT name FROM pragma_index_list('${e.key}')")
            .get();
        var found = false;
        for (final i in indexes) {
          final cols =
              (await db
                      .customSelect(
                        "SELECT name FROM pragma_index_info('${i.data['name']}') ORDER BY seqno",
                      )
                      .get())
                  .map((r) => r.data['name'] as String)
                  .toList();
          if (cols.first == 'run_id' && cols.contains(e.value)) found = true;
        }
        expect(found, isTrue, reason: '${e.key}: Index (run_id, ${e.value})');
      }
    });

    test('Zustände entsprechen den Enums in core', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _insertRun(db, 1);
      for (final s in MeasurementState.values) {
        await _exec(
          db,
          "INSERT INTO raw_steps (run_id, time_us, source, state, step_count) VALUES (1, 1, 'p', ?, 1)",
          [s.name],
        );
      }
      await expectLater(
        _exec(
          db,
          "INSERT INTO raw_steps (run_id, time_us, source, state, step_count) VALUES (1, 1, 'p', 'bogus', 1)",
        ),
        throwsA(anything),
      );
      for (final r in DiscardReason.values) {
        await _exec(
          db,
          "INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state, discard_reason) "
          "VALUES (1, 'position', 1, 1, 'discarded', ?)",
          [r.name],
        );
      }
      for (final c in SensorContact.values) {
        await _exec(
          db,
          "INSERT INTO raw_heart_rates (run_id, time_us, source, state, bpm, contact) "
          "VALUES (1, 1, 's', 'present', 100, ?)",
          [c.name],
        );
      }
    });

    test('Profil: eine Zeile, alles optional, nur positive Zahlen für Alter, Gewicht, Größe', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _exec(db, 'INSERT INTO profile (id) VALUES (1)');
      await expectLater(
        _exec(db, 'INSERT INTO profile (id) VALUES (2)'),
        throwsA(anything),
      );
      await expectLater(
        _exec(db, 'UPDATE profile SET body_weight_kg = 0'),
        throwsA(anything),
      );
      await expectLater(
        _exec(db, 'UPDATE profile SET body_height_m = -1'),
        throwsA(anything),
      );
      await expectLater(
        _exec(db, 'UPDATE profile SET birth_year = 0'),
        throwsA(anything),
      );
      await _exec(
        db,
        'UPDATE profile SET max_heart_rate_bpm = 185, resting_heart_rate_bpm = 52',
      );
    });

    test('bekannte Geräte: mehrere, höchstens eins bevorzugt', () async {
      final db = await openDb();
      addTearDown(db.close);
      const ins =
          'INSERT INTO known_devices (device_id, display_name, is_preferred, added_at_us) VALUES (?, ?, ?, 1)';
      await _exec(db, ins, ['A', 'Gurt A', 1]);
      await _exec(db, ins, ['B', 'Gurt B', 0]);
      await _exec(db, ins, ['C', null, 0]);
      await expectLater(_exec(db, ins, ['D', 'x', 1]), throwsA(anything));
      await expectLater(_exec(db, ins, ['A', 'doppelt', 0]), throwsA(anything));
      await _exec(
        db,
        "UPDATE known_devices SET is_preferred = 0 WHERE device_id = 'A'",
      );
      await _exec(
        db,
        "UPDATE known_devices SET is_preferred = 1 WHERE device_id = 'B'",
      );
      expect(await _count(db, 'known_devices'), 3);
    });

    test('Einwilligungen und Einstellungen', () async {
      final db = await openDb();
      addTearDown(db.close);
      await _exec(db, "INSERT INTO consents VALUES ('strava', 'granted', 1)");
      await _exec(
        db,
        "INSERT INTO consents VALUES ('health_connect', 'revoked', 2)",
      );
      await expectLater(
        _exec(db, "INSERT INTO consents VALUES ('x', 'maybe', 3)"),
        throwsA(anything),
      );
      await expectLater(
        _exec(db, "INSERT INTO consents VALUES ('strava', 'revoked', 3)"),
        throwsA(anything),
      );
      await _exec(db, "INSERT INTO settings VALUES ('units', 'km', 1)");
      expect(await _count(db, 'consents'), 2);
      expect(await _count(db, 'settings'), 1);
    });

    test('Lauf-Zustand nur aus der Liste', () async {
      final db = await openDb();
      addTearDown(db.close);
      await expectLater(
        _exec(
          db,
          "INSERT INTO runs (state, started_at_us) VALUES ('weird', 1)",
        ),
        throwsA(anything),
      );
    });
  });

  group('Migrationen', () {
    test('echte Migration v1 -> v4 auf befüllter v1-Datenbank (alle Schritte): Daten bleiben, '
        'neue Spalten NULL (nie 0), Schema = Dump v4', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final v1 = await verifier.schemaAt(1);
      v1.rawDatabase
        ..execute(
          "INSERT INTO runs (id, state, started_at_us, ended_at_us) "
          "VALUES (7, 'finished', 1, 9)",
        )
        ..execute(
          "INSERT INTO raw_positions (run_id, time_us, source, state, "
          "latitude_deg, longitude_deg, accuracy_m) "
          "VALUES (7, 5, 'gps', 'present', 52.5, 13.25, 4.5)",
        )
        ..execute(
          "INSERT INTO raw_positions (run_id, time_us, source, state) "
          "VALUES (7, 6, 'gps', 'unavailable')",
        );
      _fillComputedV2(v1.rawDatabase);
      final db = AppDatabase(v1.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 4);
      final rows = await db
          .customSelect(
            'SELECT latitude_deg, accuracy_m, speed_mps, speed_accuracy_mps, '
            'vertical_accuracy_m FROM raw_positions ORDER BY time_us',
          )
          .get();
      expect(rows, hasLength(2));
      expect(rows[0].data['latitude_deg'], 52.5);
      expect(rows[0].data['accuracy_m'], 4.5);
      for (final r in rows) {
        expect(r.data['speed_mps'], isNull);
        expect(r.data['speed_accuracy_mps'], isNull);
        expect(r.data['vertical_accuracy_m'], isNull);
      }
      // Die migrierte Datei nimmt neue Werte an und bleibt append-only.
      await _exec(
        db,
        "INSERT INTO raw_positions (run_id, time_us, source, state, "
        "latitude_deg, longitude_deg, speed_mps) "
        "VALUES (7, 7, 'gps', 'present', 1, 2, 0.0)",
      );
      await _expectAborted(
        _exec(db, "UPDATE raw_positions SET speed_mps = 1"),
        'append-only',
      );
      // Aus WP09: Werte, Läufe, Abschnitte und Trigger über alle Schritte.
      await _expectV3Upgrade(db);
    });

    test(
      'echte Migration v2 -> v4 auf befüllter v2-Datenbank: Daten bleiben, '
      'Grund für Zeilen ohne Wert, neue Spalten NULL, Schema = Dump v4',
      () async {
        final verifier = SchemaVerifier(GeneratedHelper());
        final v2 = await verifier.schemaAt(2);
        v2.rawDatabase.execute(
          "INSERT INTO runs (id, state, started_at_us, ended_at_us) "
          "VALUES (7, 'finished', 1, 9)",
        );
        _fillComputedV2(v2.rawDatabase);
        v2.rawDatabase.execute(
          "INSERT INTO raw_positions (run_id, time_us, source, state, "
          "latitude_deg, longitude_deg, speed_mps) "
          "VALUES (7, 5, 'gps', 'present', 52.5, 13.25, 3.5)",
        );
        final db = AppDatabase(v2.newConnection());
        addTearDown(db.close);
        await verifier.migrateAndValidate(db, 4);
        final speed = await db
            .customSelect('SELECT speed_mps FROM raw_positions')
            .getSingle();
        expect(speed.data['speed_mps'], 3.5);
        await _expectV3Upgrade(db);
      },
    );

    test('echte Migration v3 -> v4 auf befüllter v3-Datenbank: Kurzfassung bleibt, '
        'neue Spalten NULL (nie 0), Schema = Dump v4', () async {
      final verifier = SchemaVerifier(GeneratedHelper());
      final v3 = await verifier.schemaAt(3);
      v3.rawDatabase
        ..execute(
          "INSERT INTO runs (id, state, started_at_us, ended_at_us) "
          "VALUES (7, 'finished', 1, 9)",
        )
        ..execute(
          "INSERT INTO preprocessing_results (run_id, method, method_version, "
          "parameter_version, computed_at_us, total_time_s, moving_time_s, "
          "distance_m, average_bpm) "
          "VALUES (7, 'run-overview', 1, 4, 5, 61.5, 60.0, 1000.5, 150.0)",
        );
      final db = AppDatabase(v3.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 4);
      final row = await db
          .customSelect('SELECT * FROM preprocessing_results')
          .getSingle();
      expect(row.data['method_version'], 1);
      expect(row.data['distance_m'], 1000.5);
      expect(row.data['average_bpm'], 150.0);
      expect(row.data['best_pace_s_per_km'], isNull);
      expect(row.data['lap_count'], isNull);
      expect(row.data['heart_rate_time_s'], isNull);
    });

    test(
      'Dump Version 4 liegt vor, genau drei Schritte (1 -> 2, 2 -> 3, 3 -> 4)',
      () async {
        final db = await openDb();
        addTearDown(db.close);
        expect(db.migrationSteps.keys, [1, 2, 3]);
      },
    );

    test(
      'synthetischer Schritt v4 -> v5 auf verschlüsselter Datei erhält Daten',
      () async {
        final v1 = await openDb();
        await _insertRun(v1, 7);
        await _exec(v1, _rowFor['raw_positions']!, [7]);
        await _exec(v1, "INSERT INTO settings VALUES ('units', 'km', 1)");
        await v1.close();

        var ran = 0;
        final storage = EncryptedStorage(
          path,
          databaseBuilder: (e) => _SyntheticV2(e, onStep: () => ran++),
        );
        final v2 =
            (await storage.open(testKey()) as EncryptedStorageSession).database;
        addTearDown(v2.close);
        expect(ran, 1);
        expect(
          (await v2.customSelect('PRAGMA user_version').get())
              .single
              .data
              .values
              .single,
          5,
        );
        // Schritt wirkte, alte Daten, Trigger und Kaskade bleiben.
        await _exec(v2, "UPDATE settings SET note = 'neu'");
        expect(await _count(v2, 'raw_positions', 7), 1);
        await _expectAborted(
          _exec(v2, "UPDATE raw_positions SET source = 'x'"),
          'append-only',
        );
        await _exec(v2, 'DELETE FROM runs WHERE id = 7');
        expect(await _count(v2, 'raw_positions'), 0);
      },
    );

    test(
      'fehlender Schritt: Datenbank öffnet nicht und bleibt Version 4',
      () async {
        await (await openDb()).close();
        final storage = EncryptedStorage(
          path,
          databaseBuilder: (e) => _NoStepV2(e),
        );
        await expectLater(
          storage.open(testKey()),
          throwsA(
            isA<StorageException>().having(
              (e) => e.failure,
              'failure',
              StorageFailure.migrationFailed,
            ),
          ),
        );
        final v1 = await openDb();
        addTearDown(v1.close);
        expect(
          (await v1.customSelect('PRAGMA user_version').get())
              .single
              .data
              .values
              .single,
          4,
        );
      },
    );

    test('Herabstufen wird abgelehnt', () async {
      final storage = EncryptedStorage(
        path,
        databaseBuilder: (e) => _SyntheticV2(e, onStep: () {}),
      );
      await (await storage.open(testKey())).close();
      // Datei ist jetzt Version 5, die App kennt nur 4.
      await expectLater(
        EncryptedStorage(path).open(testKey()),
        throwsA(
          isA<StorageException>().having(
            (e) => e.failure,
            'failure',
            StorageFailure.newerVersion,
          ),
        ),
      );
    });

    test(
      'Schritt wirft mit Inhalt im Text: migrationFailed, Text ohne Inhalt',
      () async {
        await (await openDb()).close();
        final storage = EncryptedStorage(
          path,
          databaseBuilder: (e) => _FailingStepV2(e),
        );
        try {
          await storage.open(testKey());
          fail('hätte scheitern müssen');
        } on StorageException catch (e) {
          expect(e.failure, StorageFailure.migrationFailed);
          expect(e.toString(), isNot(contains(marker)));
        }
      },
    );

    test('Schritt 2 von 2 scheitert: Schritt 4 ist zurückgerollt, Version 4, '
        'Erneut versuchen läuft sauber', () async {
      await (await openDb()).close();
      final failing = EncryptedStorage(
        path,
        databaseBuilder: (e) => _TwoStepsSecondFails(e),
      );
      await expectLater(
        failing.open(testKey()),
        throwsA(
          isA<StorageException>().having(
            (e) => e.failure,
            'failure',
            StorageFailure.migrationFailed,
          ),
        ),
      );
      final v1 = await openDb();
      final columns = await v1
          .customSelect("SELECT name FROM pragma_table_info('settings')")
          .get();
      expect(
        columns.map((r) => r.data['name']),
        isNot(contains('note')),
        reason: 'Schritt 4 muss mit zurückgerollt sein',
      );
      expect(
        (await v1.customSelect('PRAGMA user_version').get())
            .single
            .data
            .values
            .single,
        4,
      );
      await v1.close();
      // Erneut versuchen mit einem funktionierenden Schritt 4.
      final retry = EncryptedStorage(
        path,
        databaseBuilder: (e) => _SyntheticV2(e, onStep: () {}),
      );
      final v2 =
          (await retry.open(testKey()) as EncryptedStorageSession).database;
      addTearDown(v2.close);
      expect(
        (await v2.customSelect('PRAGMA user_version').get())
            .single
            .data
            .values
            .single,
        5,
      );
    });

    test(
      'Version steht in beforeOpen schon auf 5, also vor drifts eigenem '
      'Versionsschreiben (Reihenfolge PRAGMA/COMMIT: siehe nächster Test)',
      () async {
        await (await openDb()).close();
        final observed = <Object?>[];
        final storage = EncryptedStorage(
          path,
          databaseBuilder: (e) =>
              _SyntheticV2(e, onStep: () {}, onBeforeOpenVersion: observed.add),
        );
        await (await storage.open(testKey())).close();
        expect(observed, [5]);
      },
    );

    test('PRAGMA user_version steht vor dem COMMIT der Migration', () async {
      await (await openDb()).close();
      final logs = IsolateLogs();
      addTearDown(logs.close);
      final storage = EncryptedStorage.forTest(
        path,
        isolateSetup: logs.setup,
        logStatements: true,
        databaseBuilder: (e) => _SyntheticV2(e, onStep: () {}),
      );
      await (await storage.open(testKey())).close();
      final lines = (await logs.text()).split('\n');
      final step = lines.indexWhere((l) => l.contains('ADD COLUMN note'));
      final pragma = lines.indexWhere(
        (l) => l.contains('PRAGMA user_version = 5'),
      );
      final commit = lines.indexWhere((l) => l.contains('COMMIT'), step);
      expect(step, isNonNegative, reason: '$lines');
      expect(pragma, greaterThan(step), reason: '$lines');
      expect(commit, greaterThan(pragma), reason: '$lines');
    });
  });
}

/// Test-Datenbank "Version 5" mit einem Schritt, der nur im Test existiert.
class _SyntheticV2 extends AppDatabase {
  _SyntheticV2(super.e, {required this.onStep, this.onBeforeOpenVersion});
  final void Function() onStep;

  /// Meldet `user_version`, wie sie in `beforeOpen` steht: nach der Migration,
  /// aber bevor drift die Version selbst schreibt.
  final void Function(Object?)? onBeforeOpenVersion;

  @override
  MigrationStrategy get migration {
    final base = super.migration;
    return MigrationStrategy(
      onCreate: base.onCreate,
      onUpgrade: base.onUpgrade,
      beforeOpen: (details) async {
        final rows = await customSelect('PRAGMA user_version').get();
        onBeforeOpenVersion?.call(rows.single.data.values.single);
      },
    );
  }

  @override
  int get schemaVersion => 5;

  @override
  Map<int, MigrationStep> get migrationSteps => {
    ...super.migrationSteps,
    4: (Migrator m) async {
      onStep();
      await m.database.customStatement(
        'ALTER TABLE settings ADD COLUMN note TEXT',
      );
    },
  };
}

class _NoStepV2 extends AppDatabase {
  _NoStepV2(super.e);

  @override
  int get schemaVersion => 5;
}

class _FailingStepV2 extends AppDatabase {
  _FailingStepV2(super.e);

  @override
  int get schemaVersion => 5;

  @override
  Map<int, MigrationStep> get migrationSteps => {
    ...super.migrationSteps,
    4: (Migrator m) async {
      await m.database.customStatement(
        "INSERT INTO no_such_table VALUES ('$marker')",
      );
    },
  };
}

/// Version 5 mit zwei Schritten: Schritt 4 gelingt, Schritt 5 wirft.
class _TwoStepsSecondFails extends AppDatabase {
  _TwoStepsSecondFails(super.e);

  @override
  int get schemaVersion => 6;

  @override
  Map<int, MigrationStep> get migrationSteps => {
    ...super.migrationSteps,
    4: (Migrator m) async {
      await m.database.customStatement(
        'ALTER TABLE settings ADD COLUMN note TEXT',
      );
    },
    5: (Migrator m) async {
      await m.database.customStatement(
        "INSERT INTO no_such_table VALUES ('x')",
      );
    },
  };
}

/// Füllt eine Datenbank der Version 1 oder 2 (Lauf 7 muss vorhanden sein) mit
/// zwei Werten: Original ohne Wert, current mit Wert.
void _fillComputedV2(dynamic raw) {
  raw.execute(
    "INSERT INTO computed_values (id, run_id, value_key, role, value_real, "
    "unit, computed_at_us, measurement_count, sources, method, "
    "method_version, parameter_version, quality) VALUES "
    "(1, 7, 'vo2max', 'original', NULL, 'ml', 1, 0, '[]', 'm', 1, 1, "
    "'undeterminable'), "
    "(2, 7, 'vo2max', 'current', 41.5, 'ml', 1, 3, '[]', 'm', 1, 1, 'good')",
  );
}

/// Prüft nach der Migration auf Version 3: alte Zeilen, Grund-Regel, Basis,
/// Versatz und neue Tabelle samt Triggern.
Future<void> _expectV3Upgrade(AppDatabase db) async {
  // Die Kaskade gilt nur bei eingeschalteten Fremdschlüsseln.
  await _exec(db, 'PRAGMA foreign_keys = ON');
  final rows = await db
      .customSelect(
        'SELECT id, value_real, unavailable_reason, hr_max_bpm, hr_rest_bpm, '
        'hr_max_is_estimated FROM computed_values ORDER BY id',
      )
      .get();
  expect(rows, hasLength(2));
  expect(rows[0].data['value_real'], isNull);
  expect(rows[0].data['unavailable_reason'], 'insufficientData');
  expect(rows[1].data['value_real'], 41.5);
  expect(rows[1].data['unavailable_reason'], isNull);
  for (final r in rows) {
    expect(r.data['hr_max_bpm'], isNull);
    expect(r.data['hr_rest_bpm'], isNull);
    expect(r.data['hr_max_is_estimated'], isNull);
  }
  final run = await db
      .customSelect('SELECT ended_utc_offset_s FROM runs WHERE id = 7')
      .getSingle();
  expect(run.data['ended_utc_offset_s'], isNull);
  expect(await _count(db, 'value_sections'), 0);
  // Der Originalwert blieb unveränderlich, die neuen Regeln gelten.
  await _expectAborted(
    _exec(db, 'UPDATE computed_values SET unit = \'x\' WHERE id = 1'),
    'original value is immutable',
  );
  await _expectAborted(
    _exec(db, 'UPDATE computed_values SET value_real = NULL WHERE id = 2'),
    'exclusive',
  );
  await _expectAborted(
    _exec(db, 'UPDATE computed_values SET hr_max_bpm = 180 WHERE id = 2'),
    'snapshot flag',
  );
  await _exec(db, 'UPDATE runs SET ended_utc_offset_s = 3600 WHERE id = 7');
  await _exec(
    db,
    "INSERT INTO value_sections (computed_value_id, position, start_us, "
    "end_us, weight, late_factor, status, reasons) "
    "VALUES (2, 0, 1, 2, 1, 1, 'eligible', '[]')",
  );
  expect(await _count(db, 'value_sections'), 1);
  await _exec(db, 'DELETE FROM runs WHERE id = 7');
  expect(await _count(db, 'value_sections'), 0);
}
