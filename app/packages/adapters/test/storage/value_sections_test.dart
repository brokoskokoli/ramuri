import 'dart:io';

import 'package:adapters/adapters.dart' hide RawSteps, ComputedValue;
import 'package:core/core.dart';
import 'package:core/testing/contract_samples.dart' as cs;
import 'package:drift/drift.dart'
    show MigrationStrategy, Migrator, QueryExecutor;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Bewertete Abschnitte je Wert (WP09 D1, Schema Version 3, FR-0073).
final _t0 = DateTime.utc(2030, 1, 1, 12);
DateTime _at(int s) => _t0.add(Duration(seconds: s));

ComputedValue _dayValue(String key, int from, int to) => ComputedValue(
  key: key,
  value: 1,
  unit: 'au',
  computedAt: _at(300),
  dataFrom: _at(from),
  dataTo: _at(to),
  measurementCount: 1,
  sources: const ['s'],
  method: 'm',
  methodVersion: 1,
  parameterVersion: 1,
  quality: ValueQuality.good,
  sections: cs.sampleValueSections(),
);

/// Datenbank im Stand Version 1 oder 2 (WP06 ergänzt in Version 2 die Spalten
/// der Rohpositionen): Tabelle und Trigger von `value_sections` und die Spalte
/// `unavailable_reason` samt Triggern fehlen, `user_version` ist [version]. Der
/// Store der aktuellen App schreibt in diese Datei nicht; die Zeilen kommen per
/// SQL ([_seedV1]).
class _V1 extends AppDatabase {
  _V1(super.e, this.version);
  final int version;

  @override
  int get schemaVersion => version;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await customStatement('DROP TABLE value_sections');
      await customStatement('DROP TRIGGER computed_values_reason_insert');
      await customStatement('DROP TRIGGER computed_values_reason_update');
      for (final t in [
        'computed_values_basis_insert',
        'computed_values_basis_update',
        'runs_offset_insert',
        'runs_offset_update',
      ]) {
        await customStatement('DROP TRIGGER $t');
      }
      for (final c in [
        'unavailable_reason',
        'hr_max_bpm',
        'hr_rest_bpm',
        'hr_max_is_estimated',
      ]) {
        await customStatement('ALTER TABLE computed_values DROP COLUMN $c');
      }
      await customStatement('ALTER TABLE runs DROP COLUMN ended_utc_offset_s');
      // Tabellen aus Schema 5 (WP18).
      await customStatement('DROP TABLE run_feedback');
      await customStatement('DROP TABLE manual_trainings');
      // Spalten der Kurzfassung (Schema 4, WP10).
      for (final c in [
        'best_pace_s_per_km',
        'lap_count',
        'heart_rate_time_s',
      ]) {
        await customStatement(
          'ALTER TABLE preprocessing_results DROP COLUMN $c',
        );
      }
      // Tabellen der Leistungsprognose (Schema 6, WP20).
      await customStatement('DROP TABLE reference_performances');
      await customStatement('DROP TABLE rejected_suggestions');
      // Trainingsziel (Schema 7, WP21).
      await customStatement('DROP TABLE plan_units');
      await customStatement('DROP TABLE plans');
      await customStatement('DROP TABLE goals');
      // RR-Pakete (Schema 9, WP26), samt Index und Triggern.
      await customStatement('DROP TABLE raw_rr_packets');
      if (version < 2) {
        for (final c in [
          'speed_mps',
          'speed_accuracy_mps',
          'vertical_accuracy_m',
        ]) {
          await customStatement('ALTER TABLE raw_positions DROP COLUMN $c');
        }
      }
    },
  );
}

/// Legt einen Wert (original und current) im Stand v1 per SQL an.
Future<void> _seedV1(
  AppDatabase db, {
  int? runId,
  String? day,
  required ComputedValue v,
}) async {
  for (final role in ['original', 'current']) {
    await db.customStatement(
      'INSERT INTO computed_values (run_id, day, value_key, role, value_real, '
      'unit, computed_at_us, data_from_us, data_to_us, measurement_count, '
      'sources, method, method_version, parameter_version, quality) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        runId,
        day,
        v.key,
        role,
        v.value,
        v.unit,
        v.computedAt.microsecondsSinceEpoch,
        v.dataFrom?.microsecondsSinceEpoch,
        v.dataTo?.microsecondsSinceEpoch,
        v.measurementCount,
        '["strap","gps"]',
        v.method,
        v.methodVersion,
        v.parameterVersion,
        v.quality.name,
      ],
    );
  }
}

void main() {
  late Directory dir;
  late String path;
  setUp(() {
    dir = tempDir();
    path = '${dir.path}/test.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<EncryptedStorageSession> open([
    AppDatabase Function(QueryExecutor) builder = AppDatabase.new,
  ]) async =>
      await EncryptedStorage(path, databaseBuilder: builder).open(testKey())
          as EncryptedStorageSession;

  Future<int> count(EncryptedStorageSession s, String table) async =>
      (await s.database
                  .customSelect('SELECT count(*) c FROM $table')
                  .getSingle())
              .data['c']
          as int;

  Future<Object?> failure(Future<void> f) async {
    try {
      await f;
    } catch (e) {
      return e;
    }
    return null;
  }

  group('Speichern und Lesen', () {
    test(
      'Roundtrip: Wert samt Abschnitten, original und current getrennt',
      () async {
        final s = await open();
        addTearDown(s.close);
        final r = (await s.runs.create(startedAt: _at(0))).id;
        final o = ValueOwner.run(r);
        final first = cs.sampleValue(
          'vo2max',
          48.5,
          sections: cs.sampleValueSections(),
        );
        await s.values.createOriginals(o, [first]);
        final second = cs.sampleValue(
          'vo2max',
          50,
          method: 2,
          sections: cs.sampleValueSections(7).sublist(0, 2),
        );
        await s.values.swapCurrent(o, [second]);
        final p = (await s.values.read(o)).single;
        expect(cs.describeValue(p.original), cs.describeValue(first));
        expect(cs.describeValue(p.current), cs.describeValue(second));
        final x = p.original.sections;
        expect(x, hasLength(3));
        expect(x[0].duration, const Duration(seconds: 300, microseconds: 5));
        expect(x[0].estimate, 47.75);
        expect(x[1].reasons, ['paceVariation', 'gpsGap']);
        expect(x[2].discard, EstimateDiscard.implausible);
        expect(p.current.sections, hasLength(2));
        // Zeilen: 3 (original) + 2 (current), nichts übrig vom alten current.
        expect(await count(s, 'value_sections'), 5);
      },
    );

    test(
      'Fehlerinjektion: ungültiger Abschnitt im zweiten Wert, nichts bleibt',
      () async {
        final s = await open();
        addTearDown(s.close);
        final r = (await s.runs.create(startedAt: _at(0))).id;
        final bad = ValueSection(
          start: _at(50),
          end: _at(10),
          weight: 1,
          lateFactor: 1,
          status: SectionStatus.eligible,
        );
        final e = await failure(
          s.values.createOriginals(ValueOwner.run(r), [
            cs.sampleValue('a', 1, sections: cs.sampleValueSections()),
            cs.sampleValue('b', 2, sections: [bad]),
          ]),
        );
        expect(e, isA<StorageException>());
        expect((e! as StorageException).failure, StorageFailure.rejected);
        expect(await count(s, 'computed_values'), 0);
        expect(await count(s, 'value_sections'), 0);
      },
    );

    test(
      'Fehlerinjektion beim Tausch: current und seine Abschnitte unverändert',
      () async {
        final s = await open();
        addTearDown(s.close);
        final r = (await s.runs.create(startedAt: _at(0))).id;
        final o = ValueOwner.run(r);
        await s.values.createOriginals(o, [
          cs.sampleValue('a', 1, sections: cs.sampleValueSections()),
          cs.sampleValue('b', 2, sections: cs.sampleValueSections(1)),
        ]);
        final before = (await s.values.read(o)).map(cs.describePair).join(';');
        final bad = ValueSection(
          start: _at(1),
          end: _at(2),
          weight: -1,
          lateFactor: 1,
          status: SectionStatus.eligible,
        );
        final e = await failure(
          s.values.swapCurrent(o, [
            cs.sampleValue('a', 5, sections: cs.sampleValueSections(3)),
            cs.sampleValue('b', 6, sections: [bad]),
          ]),
        );
        expect((e! as StorageException).failure, StorageFailure.rejected);
        expect((await s.values.read(o)).map(cs.describePair).join(';'), before);
        expect(await count(s, 'value_sections'), 12);
      },
    );
  });

  group('original-Abschnitte sind unveränderlich', () {
    Future<(EncryptedStorageSession, int, int)> filled() async {
      final s = await open();
      addTearDown(s.close);
      final r = (await s.runs.create(startedAt: _at(0))).id;
      await s.values.createOriginals(ValueOwner.run(r), [
        cs.sampleValue('a', 1, sections: cs.sampleValueSections()),
      ]);
      final ids = await s.database
          .customSelect('SELECT id, role FROM computed_values ORDER BY id')
          .get();
      return (s, ids[0].data['id'] as int, ids[1].data['id'] as int);
    }

    test('UPDATE eines Original-Abschnitts bricht ab', () async {
      final (s, orig, _) = await filled();
      final e = await failure(
        s.database.customStatement(
          'UPDATE value_sections SET weight = 99 WHERE computed_value_id = ?',
          [orig],
        ),
      );
      expect(e.toString(), contains('immutable'));
    });

    test(
      'Umhängen eines current-Abschnitts an das original bricht ab',
      () async {
        final (s, orig, cur) = await filled();
        final e = await failure(
          s.database.customStatement(
            'UPDATE value_sections SET computed_value_id = ?, position = 9 '
            'WHERE computed_value_id = ?',
            [orig, cur],
          ),
        );
        expect(e.toString(), contains('immutable'));
      },
    );

    test('nachträgliches Einfügen beim Original bricht ab', () async {
      final (s, orig, _) = await filled();
      expect(
        (await failure(
          s.database.customStatement(
            "UPDATE computed_values SET unit = 'x' WHERE role = 'original'",
          ),
        )).toString(),
        contains('immutable'),
        reason: 'Original-Trigger nach der Migration wieder da',
      );
      final e = await failure(
        s.database.customStatement(
          'INSERT INTO value_sections (computed_value_id, position, start_us, '
          "end_us, weight, late_factor, status, reasons) VALUES (?, 9, 1, 2, 1, 1, 'eligible', '[]')",
          [orig],
        ),
      );
      expect(e.toString(), contains('immutable'));
      expect(await count(s, 'value_sections'), 6);
    });

    test('swapCurrent lässt die Original-Abschnitte unberührt, current ist änderbar', () async {
      final (s, _, cur) = await filled();
      final o =
          (await s.database
                      .customSelect(
                        'SELECT run_id FROM computed_values LIMIT 1',
                      )
                      .getSingle())
                  .data['run_id']
              as int;
      await s.values.swapCurrent(ValueOwner.run(o), [
        cs.sampleValue(
          'a',
          2,
          sections: cs.sampleValueSections(4).sublist(0, 1),
        ),
      ]);
      final p = (await s.values.read(ValueOwner.run(o))).single;
      expect(
        p.original.sections.map(cs.describeSection),
        cs.sampleValueSections().map(cs.describeSection),
      );
      expect(p.current.sections, hasLength(1));
      await s.database.customStatement(
        'UPDATE value_sections SET weight = 3 WHERE computed_value_id = ?',
        [cur],
      );
    });
  });

  group('Löschen erfasst value_sections ausdrücklich', () {
    // Mit foreign_keys=OFF wirkt die Kaskade nicht: Was weg ist, hat der Code
    // ausdrücklich gelöscht.
    Future<(EncryptedStorageSession, int, int)> setup() async {
      final s = await open();
      addTearDown(s.close);
      final a = (await s.runs.create(startedAt: _at(0))).id;
      await s.runs.setState(a, RunState.finished, endedAt: _at(100));
      final b = (await s.runs.create(startedAt: _at(1000))).id;
      await s.runs.setState(b, RunState.finished, endedAt: _at(1100));
      for (final r in [a, b]) {
        await s.values.createOriginals(ValueOwner.run(r), [
          cs.sampleValue('v', 1, sections: cs.sampleValueSections()),
        ]);
      }
      await s.values.createOriginals(const ValueOwner.day('2030-01-01'), [
        _dayValue('atl', 10, 20),
      ]);
      await s.values.createOriginals(const ValueOwner.day('2030-01-02'), [
        _dayValue('atl', 5000, 6000),
      ]);
      return (s, a, b);
    }

    Future<int> sectionsOf(EncryptedStorageSession s, String where) async =>
        (await s.database
                    .customSelect(
                      'SELECT count(*) c FROM value_sections WHERE computed_value_id IN '
                      '(SELECT id FROM computed_values WHERE $where)',
                    )
                    .getSingle())
                .data['c']
            as int;

    test(
      'Normalbetrieb: Lauf A samt überlappendem Tageswert weg, Rest bleibt',
      () async {
        final (s, a, _) = await setup();
        expect(await count(s, 'value_sections'), 24);
        await s.deleteRun(a);
        // übrig: Lauf B (6), Tag 2 (6)
        expect(await count(s, 'value_sections'), 12);
        expect(await count(s, 'computed_values'), 4);
      },
    );

    test('deleteRun ohne Kaskade (foreign_keys=OFF)', () async {
      final (s, a, b) = await setup();
      await s.database.customStatement('PRAGMA foreign_keys = OFF');
      await s.deleteRun(a);
      expect(await sectionsOf(s, 'run_id = $a'), 0);
      expect(await count(s, 'computed_values'), 4);
      expect(await sectionsOf(s, "day = '2030-01-01'"), 0);
      // fremde Werte behalten ihre Abschnitte
      expect(await sectionsOf(s, 'run_id = $b'), 6);
      expect(await sectionsOf(s, "day = '2030-01-02'"), 6);
      expect(await count(s, 'value_sections'), 12);
    });

    test('deleteAll ohne Kaskade (foreign_keys=OFF)', () async {
      final (s, _, _) = await setup();
      await s.database.customStatement('PRAGMA foreign_keys = OFF');
      await s.deleteAll();
      expect(await count(s, 'value_sections'), 0);
      expect(await count(s, 'computed_values'), 0);
    });

    test('deleteAll setzt auch den Zähler von value_sections zurück', () async {
      final (s, _, _) = await setup();
      await s.deleteAll();
      expect(await count(s, 'sqlite_sequence'), 0);
    });
  });

  group('fehlender Wert nennt den Grund (FR-0068)', () {
    test('Trigger: Wert genau dann NULL, wenn ein Grund gesetzt ist', () async {
      final s = await open();
      addTearDown(s.close);
      final r = (await s.runs.create(startedAt: _at(0))).id;
      Future<Object?> insert(String key, String? value, String? reason) =>
          failure(
            s.database.customStatement(
              'INSERT INTO computed_values (run_id, value_key, role, '
              'value_real, unavailable_reason, unit, computed_at_us, '
              'measurement_count, sources, method, method_version, '
              "parameter_version, quality) VALUES ($r, '$key', 'current', "
              "$value, $reason, 'u', 1, 0, '[]', 'm', 1, 1, 'good')",
            ),
          );
      expect(
        (await insert('a', 'NULL', 'NULL')).toString(),
        contains('exclusive'),
      );
      expect(
        (await insert('b', '1.5', "'noValidSection'")).toString(),
        contains('exclusive'),
      );
      expect(await insert('c', 'NULL', "'noValidSection'"), isNull);
      expect(await insert('d', '1.5', 'NULL'), isNull);
      // Auch beim Ändern der current-Zeile.
      Future<Object?> update(String key, String set) => failure(
        s.database.customStatement(
          "UPDATE computed_values SET $set WHERE value_key = '$key'",
        ),
      );
      expect(
        (await update('d', 'value_real = NULL')).toString(),
        contains('exclusive'),
      );
      expect(
        (await update('c', 'unavailable_reason = NULL')).toString(),
        contains('exclusive'),
      );
      expect(
        (await update(
          'c',
          "value_real = 2, unavailable_reason = 'x'",
        )).toString(),
        contains('exclusive'),
      );
      expect(
        await update('c', 'value_real = 2, unavailable_reason = NULL'),
        isNull,
      );
    });

    test(
      'Adapter: Grund wird gespeichert, gelesen und beim Tausch ersetzt',
      () async {
        final s = await open();
        addTearDown(s.close);
        final r = (await s.runs.create(startedAt: _at(0))).id;
        final o = ValueOwner.run(r);
        await s.values.createOriginals(o, [
          cs.sampleValue(
            'v',
            null,
            quality: ValueQuality.undeterminable,
            reason: UnavailableReason.spreadTooHigh,
          ),
        ]);
        var p = (await s.values.read(o)).single;
        expect(p.original.unavailableReason, UnavailableReason.spreadTooHigh);
        await s.values.swapCurrent(o, [cs.sampleValue('v', 3)]);
        p = (await s.values.read(o)).single;
        expect(p.current.unavailableReason, isNull);
        expect(p.current.value, 3);
        expect(p.original.unavailableReason, UnavailableReason.spreadTooHigh);
        await s.values.swapCurrent(o, [
          cs.sampleValue('v', null, reason: UnavailableReason.noHeartRate),
        ]);
        p = (await s.values.read(o)).single;
        expect(p.current.unavailableReason, UnavailableReason.noHeartRate);
        expect(p.current.value, isNull);
      },
    );

    test(
      'unbekannter gespeicherter Code ist ein Datenfehler, kein Raten',
      () async {
        final s = await open();
        addTearDown(s.close);
        final r = (await s.runs.create(startedAt: _at(0))).id;
        await s.values.createOriginals(ValueOwner.run(r), [
          cs.sampleValue('v', null, quality: ValueQuality.undeterminable),
        ]);
        await s.database.customStatement(
          "UPDATE computed_values SET unavailable_reason = 'neuerCode' "
          "WHERE role = 'current'",
        );
        await expectLater(
          s.values.read(ValueOwner.run(r)),
          throwsA(isA<StorageException>()),
        );
      },
    );
  });

  group('Basis-Schnappschuss und UTC-Versatz (D2a)', () {
    test('Trigger und Prüfungen auf SQL-Ebene', () async {
      final s = await open();
      addTearDown(s.close);
      final r = (await s.runs.create(startedAt: _at(0))).id;
      Future<Object?> insert(String key, String cols, String vals) => failure(
        s.database.customStatement(
          'INSERT INTO computed_values (run_id, value_key, role, value_real, '
          'unit, computed_at_us, measurement_count, sources, method, '
          'method_version, parameter_version, quality$cols) VALUES ($r, '
          "'$key', 'current', 1, 'u', 1, 0, '[]', 'm', 1, 1, 'good'$vals)",
        ),
      );
      const flagCols = ', hr_max_bpm, hr_rest_bpm, hr_max_is_estimated';
      // Werte ohne Anzeiger: Trigger.
      expect(
        (await insert('a', ', hr_max_bpm', ', 190')).toString(),
        contains('snapshot flag'),
      );
      expect(
        (await insert('b', ', hr_rest_bpm', ', 50')).toString(),
        contains('snapshot flag'),
      );
      // Ungültige Werte: CHECK.
      expect((await insert('c', flagCols, ', 0, 50, 0')), isNotNull);
      expect((await insert('d', flagCols, ', 190, -1, 0')), isNotNull);
      expect((await insert('e', flagCols, ', 190, 50, 2')), isNotNull);
      // Gültig: voller Schnappschuss, nur Anzeiger, kein Schnappschuss.
      expect(await insert('f', flagCols, ', 190, 50, 1'), isNull);
      expect(await insert('g', ', hr_max_is_estimated', ', 0'), isNull);
      expect(await insert('h', '', ''), isNull);
    });

    test('UTC-Versatz: Bereich und nur mit Ende', () async {
      final s = await open();
      addTearDown(s.close);
      final r = (await s.runs.create(startedAt: _at(0))).id;
      expect(
        (await failure(
          s.database.customStatement(
            'UPDATE runs SET ended_utc_offset_s = 3600 WHERE id = $r',
          ),
        )).toString(),
        contains('offset without end'),
      );
      await s.runs.setState(r, RunState.finished, endedAt: _at(5));
      expect(
        await failure(
          s.database.customStatement(
            'UPDATE runs SET ended_utc_offset_s = 64801 WHERE id = $r',
          ),
        ),
        isNotNull,
      );
      expect(
        await failure(
          s.database.customStatement(
            'UPDATE runs SET ended_utc_offset_s = -64800 WHERE id = $r',
          ),
        ),
        isNull,
      );
      // Wiederaufnahme über den Store löscht Versatz und Ende zusammen.
      await s.runs.setState(r, RunState.active);
      expect((await s.runs.get(r))!.endedUtcOffset, isNull);
    });
  });

  for (final from in [1, 2]) {
    group('Migration $from -> 9 auf befüllter v$from-Datenbank', () {
      test('Daten bleiben, Tabelle und Trigger kommen dazu', () async {
        final v1 = await open((e) => _V1(e, from));
        Future<List<Object?>> master(String type) async => [
          for (final r
              in await v1.database
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = '$type'",
                  )
                  .get())
            r.data['name'],
        ];
        expect(await master('table'), isNot(contains('value_sections')));
        expect(
          await master('trigger'),
          isNot(contains('value_sections_original_immutable')),
        );
        final r = (await v1.runs.create(startedAt: _at(0))).id;
        // Der Store der aktuellen App kennt die v1-Spalten nicht: per SQL beenden.
        await v1.database.customStatement(
          "UPDATE runs SET state = 'finished', ended_at_us = ? WHERE id = ?",
          [_at(100).microsecondsSinceEpoch, r],
        );
        final o = ValueOwner.run(r);
        await _seedV1(v1.database, runId: r, v: cs.sampleValue('vo2max', 48.5));
        // Ein alter Wert ohne Zahl (v1 verlangte dafür keinen Grund).
        await _seedV1(
          v1.database,
          runId: r,
          v: cs.sampleValue(
            'efficiency',
            null,
            quality: ValueQuality.undeterminable,
          ),
        );
        await _seedV1(
          v1.database,
          day: '2030-01-01',
          v: _dayValue('atl', 1, 2).copyWithoutSections(),
        );
        await v1.settings.set('units', 'km', at: _at(0));
        expect(
          (await v1.database.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          from,
        );
        final expected = cs.describeValue(cs.sampleValue('vo2max', 48.5));
        await v1.close();

        final s = await open();
        addTearDown(s.close);
        expect(
          (await s.database.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          9,
        );
        await s.database.validateDatabaseSchema();
        expect(await count(s, 'computed_values'), 6);
        expect(await count(s, 'value_sections'), 0);
        expect(await s.settings.all(), {'units': 'km'});
        final both = await s.values.read(o);
        final p = both.last;
        expect(cs.describeValue(p.original), expected);
        expect(p.original.sections, isEmpty);
        // Alter Wert ohne Zahl: bekommt den allgemeinen Grund, original und
        // current, trotz unveränderlichem original.
        expect(both.first.original.key, 'efficiency');
        expect(
          both.first.original.unavailableReason,
          UnavailableReason.insufficientData,
        );
        expect(
          both.first.current.unavailableReason,
          UnavailableReason.insufficientData,
        );
        expect(p.original.unavailableReason, isNull);
        // D2a: alte Zeilen haben keinen Basis-Schnappschuss, alte Läufe keinen
        // UTC-Versatz (beides unbekannt, nicht 0).
        for (final x in [...both.map((b) => b.original), p.current]) {
          expect(x.heartRateBasis, isNull);
        }
        expect((await s.runs.get(r))!.endedUtcOffset, isNull);
        expect((await s.runs.get(r))!.endedAt, _at(100));
        // Die Regel gilt auf der migrierten Datei (Trigger vorhanden).
        expect(
          (await failure(
            s.database.customStatement(
              "UPDATE computed_values SET value_real = NULL WHERE role = 'current' "
              "AND value_key = 'vo2max'",
            ),
          )).toString(),
          contains('exclusive'),
        );

        // Neue Funktion auf der migrierten Datei, samt Triggern.
        await s.values.swapCurrent(o, [
          cs.sampleValue(
            'vo2max',
            50,
            sections: cs.sampleValueSections(),
            basis: const HeartRateBasis(maxBpm: 188, restingBpm: 50),
          ),
        ]);
        expect(
          (await s.values.read(o)).last.current.heartRateBasis?.maxBpm,
          188,
        );
        expect((await s.values.read(o)).last.original.heartRateBasis, isNull);
        await s.runs.setState(
          r,
          RunState.finished,
          endedAt: _at(101),
          endedUtcOffset: const Duration(hours: 1),
        );
        expect((await s.runs.get(r))!.endedUtcOffset, const Duration(hours: 1));
        expect(
          (await failure(
            s.database.customStatement(
              'UPDATE computed_values SET hr_max_is_estimated = NULL '
              "WHERE role = 'current' AND value_key = 'vo2max'",
            ),
          )).toString(),
          contains('snapshot flag'),
        );
        expect(
          (await failure(
            s.database.customStatement(
              'UPDATE runs SET ended_at_us = NULL WHERE id = $r',
            ),
          )).toString(),
          contains('offset without end'),
        );
        expect((await s.values.read(o)).last.current.sections, hasLength(3));
        expect((await s.values.read(o)).last.original.sections, isEmpty);
        final orig =
            (await s.database
                        .customSelect(
                          "SELECT id FROM computed_values WHERE role = 'original' AND value_key = 'vo2max' AND run_id = $r",
                        )
                        .getSingle())
                    .data['id']
                as int;
        final e = await failure(
          s.database.customStatement(
            'INSERT INTO value_sections (computed_value_id, position, start_us, '
            "end_us, weight, late_factor, status, reasons) VALUES (?, 0, 1, 2, 1, 1, 'eligible', '[]')",
            [orig],
          ),
        );
        expect(e.toString(), contains('immutable'));
        await s.deleteRun(r);
        expect(await count(s, 'value_sections'), 0);
      });
    });
  }
}

extension on ComputedValue {
  ComputedValue copyWithoutSections() => ComputedValue(
    key: key,
    value: value,
    unit: unit,
    computedAt: computedAt,
    measurementCount: measurementCount,
    sources: sources,
    method: method,
    methodVersion: methodVersion,
    parameterVersion: parameterVersion,
    quality: quality,
    dataFrom: dataFrom,
    dataTo: dataTo,
  );
}
