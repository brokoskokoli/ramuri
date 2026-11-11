import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'archive_fixture.dart';

const String _password = 'synthetisches Testpasswort';
Future<List<Map<String, Object?>>> _decode(File f) async {
  final b = BytesBuilder(copy: false);
  await for (final c in createArchiveCipher(
    offload: inlineOffloadAsync,
  ).decrypt(_password, Stream.value(f.readAsBytesSync()))) {
    b.add(c);
  }
  final text = utf8.decode(gzip.decode(b.takeBytes()));
  return [
    for (final l in text.trimRight().split('\n'))
      jsonDecode(l) as Map<String, Object?>,
  ];
}

List<Map<String, Object?>> _rows(List<Map<String, Object?>> lines, String n) {
  final out = <Map<String, Object?>>[];
  String? cur;
  for (final l in lines) {
    if (l['type'] == 'section') cur = l['name'] as String;
    if (l['type'] == 'row' && cur == n) {
      out.add((l['data']! as Map).cast<String, Object?>());
    }
  }
  return out;
}

bool _hasBytes(Uint8List data, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= data.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (data[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Alle Dateien unter [dir], die nach [since] geändert wurden; nicht lesbare
/// Ordner (fremde Systemordner im Temp-Verzeichnis) werden übergangen.
Iterable<File> _filesSince(Directory dir, DateTime since) sync* {
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(followLinks: false);
  } on FileSystemException {
    return;
  }
  for (final e in entries) {
    if (e is Directory) {
      yield* _filesSince(e, since);
    } else if (e is File) {
      try {
        if (e.lastModifiedSync().isAfter(since)) yield e;
      } on FileSystemException {
        continue;
      }
    }
  }
}

/// Findet seit [since] geänderte Dateien unter [roots] (außer unter [skip])
/// mit der Marke im Klartext oder mit gzip-Magie `1f 8b 08` am Dateianfang.
List<String> _leaks(List<Directory> roots, Directory skip, DateTime since) {
  final bad = <String>[];
  for (final root in roots) {
    if (!root.existsSync()) continue;
    for (final e in _filesSince(root, since)) {
      if (e.path.startsWith(skip.path)) continue;
      try {
        if (e.lengthSync() > 200 * 1024 * 1024) continue;
        final data = e.readAsBytesSync();
        if (_hasBytes(data, utf8.encode(fixtureMarker))) {
          bad.add('Marke: ${e.path}');
        }
        if (data.length >= 3 &&
            data[0] == 0x1f &&
            data[1] == 0x8b &&
            data[2] == 8) {
          bad.add('gzip: ${e.path}');
        }
      } on FileSystemException {
        continue;
      }
    }
  }
  return bad;
}

/// Test-Chiffre: beendet den Arbeits-Isolate hart nach dem Kopf, ohne dass
/// dessen catch/finally läuft.
class _DyingCipher implements ArchiveCipher {
  @override
  Stream<Uint8List> encrypt(
    String password,
    Stream<List<int>> plaintext,
  ) async* {
    var n = 0;
    await for (final c in createArchiveCipherInWorker().encrypt(
      password,
      plaintext,
    )) {
      if (n++ >= 1) Isolate.exit();
      yield c;
    }
  }

  @override
  Stream<Uint8List> decrypt(String password, Stream<List<int>> archive) =>
      throw UnimplementedError();
}

ArchiveCipher _dyingCipher() => _DyingCipher();

void main() {
  late Directory work;
  late Directory exportDir;
  late AppDatabase db;
  late FakeFileHandoff handoff;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('wp12b1_db_');
    exportDir = Directory('${work.path}/exports')..createSync();
    handoff = FakeFileHandoff()..directory = exportDir.path;
    db = openPlain('${work.path}/plain.db');
  });
  tearDown(() async {
    await db.close();
    work.deleteSync(recursive: true);
  });

  ArchiveExporter exporter({
    ArchiveCipherFactory cipher = createArchiveCipherInWorker,
  }) => ArchiveExporter(
    source: DriftArchiveSource(db),
    handoff: handoff,
    clock: FakeClock(DateTime.utc(2026, 11, 7, 12)),
    cipherFactory: cipher,
    pageSize: 2,
  );

  test('Abschnitte entsprechen den Tabellen der Datenbank (Spalten, Reihenfolge, NOT NULL)', () async {
    final tables =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
                )
                .get())
            .map((r) => r.data['name']! as String)
            .toSet();
    final specTables = {
      for (final s in archiveSections)
        if (!s.isReserved) s.name,
    };
    // Nicht im Archiv: technische Tabelle und Einwilligungen (SEC-0011).
    expect(tables.difference(specTables), {'storage_meta', 'consents'});
    expect(specTables.difference(tables), isEmpty);
    for (final s in archiveSections.where((s) => !s.isReserved)) {
      final info = await db.customSelect('PRAGMA table_info(${s.name})').get();
      expect(
        [for (final r in info) r.data['name']],
        [for (final c in s.columns) c.name],
        reason: s.name,
      );
      for (var i = 0; i < info.length; i++) {
        final notNull = info[i].data['notnull'] == 1 || info[i].data['pk'] == 1;
        expect(
          s.columns[i].nullable,
          !notNull,
          reason: '${s.name}.${s.columns[i].name}',
        );
      }
    }
  });

  test('Rundgang mit echter Kryptografie: alle Tabellen, Einwilligung und Merker fehlen', () async {
    await fillAllTables(db);
    final f = await exporter().export(password: _password);
    expect(exportDir.listSync(), hasLength(1));
    final lines = await _decode(File(f.path!));
    for (final s in archiveSections.where(
      (s) => !s.isReserved && s.name != 'settings',
    )) {
      expect(_rows(lines, s.name), isNotEmpty, reason: s.name);
    }
    expect(_rows(lines, 'reference_performances'), [
      {
        'id': 1,
        'kind': 'race',
        'distance_m': 10000.0,
        'time_s': 3012.5,
        'performed_on': '2026-10-01',
        'created_at_us': 7,
        'run_id': null,
      },
      {
        'id': 2,
        'kind': 'confirmedRun',
        'distance_m': 5000.0,
        'time_s': 1490.0,
        'performed_on': '2026-11-02',
        'created_at_us': 8,
        'run_id': 1,
      },
    ]);
    expect(_rows(lines, 'rejected_suggestions'), [
      {'id': 1, 'run_id': 1},
    ]);
    expect(_rows(lines, 'goals'), [
      {
        'id': 1,
        'type': 'time',
        'distance': 'tenKilometers',
        'target_s': 3000.0,
        'target_date': '2027-03-20',
        'run_days': 21,
        'max_session_s': 3600.0,
        'weekly_cap_s': 14400.0,
        'current_weekly_s': 7200.0,
        'can_run_30': 'yes',
        'hard_session': 1,
        'created_at_us': 9,
      },
    ]);
    expect(_rows(lines, 'plans'), [
      {
        'id': 1,
        'goal_id': 1,
        'created_at_us': 10,
        'valid_from': '2026-11-02',
        'trigger': 'create',
        'reason': 'goalCreated',
        'method': 'plan-rules',
        'method_version': 1,
        'parameter_version': 1,
        'inputs': '{"inputsVersion":1,"anchor":"2026-11-02","startWeeklyMinutes":120,"walkRunWeeks":0,"easyPaceSecondsPerKm":null,"easyRunCount":0,"lastWeekMinutes":null,"achievedShare":null,"walkRunStart":null,"walkRunFrom":null,"intensity":null,"today":"2026-11-02"}',
        'summary': '{"weeks":12,"estimated":true}',
      },
    ]);
    final units = _rows(lines, 'plan_units');
    expect(units, hasLength(3));
    expect(units[0]['run_id'], 1);
    expect(units[0]['pinned'], 1);
    expect(units[0]['kind'], 'walkRun');
    expect(units[1]['run_id'], isNull);
    expect(units[1]['structure'], '[]');
    // Schema 8: Festlegung des Nutzers (Ruhetag) geht mit ins Archiv.
    expect(units[0]['fixed'], 'none');
    expect(units[1]['fixed'], 'day');
    expect(units[1]['pinned'], 1);
    expect(units[2]['kind'], 'easy');
    expect(units[2]['fixed'], 'easyForHard');
    // Platzhalter ohne Tabelle bleiben leer.
    expect(_rows(lines, 'active_warning'), isEmpty);
    // Werte bleiben exakt (Typen, NULL, Kennungen).
    expect(_rows(lines, 'runs').single, {
      'id': 1,
      'state': 'finished',
      'started_at_us': 1000,
      'ended_at_us': 2000000000,
      'ended_utc_offset_s': 3600,
    });
    final cv = _rows(lines, 'computed_values');
    expect(cv.map((r) => r['role']), ['original', 'current', 'original']);
    expect(cv[0]['value_real'], isNull);
    expect(cv[0]['unavailable_reason'], 'insufficientData');
    expect(cv[0]['hr_rest_bpm'], isNull);
    expect(cv[0]['hr_max_bpm'], 190);
    expect(cv[1]['hr_max_is_estimated'], 0);
    expect(cv[0]['value_key'], 'zone_time.unbekannt');
    expect(cv[2]['day'], '2026-11-07');
    expect(cv[2]['run_id'], isNull);
    expect(_rows(lines, 'value_sections').single['computed_value_id'], 1);
    expect(
      _rows(lines, 'rated_sections').single['meets_heart_rate_gap_rule'],
      1,
    );
    expect(_rows(lines, 'rated_sections').single['gps_gaps'], '[]');
    // Archiviert: die vier load.*-Einstellungen; die technischen Merker
    // (unbestätigte Wahl, Faktor-Angebot, abgelehnter Faktor) fehlen.
    expect(
      [for (final r in _rows(lines, 'settings')) r['key']],
      [
        'load.all_recorded',
        'load.coefficients',
        'load.factor',
        'load.profile',
        // Ruhepuls-Herkunft (FR-0214): Haltung, Zeitpunkt, Quelle.
        'resting_hr.measured_at',
        'resting_hr.posture',
        'resting_hr.source',
        'unit.pace',
      ],
    );
    for (final merker in const [
      'load.profile_pending',
      'load.coefficients_pending',
      'load.factor_pending',
      'load.factor_declined',
    ]) {
      expect(jsonEncode(lines), isNot(contains(merker)));
    }
    final all = jsonEncode(lines);
    expect(all, isNot(contains(fixtureConsentMarker)));
    expect(all, isNot(contains('consents')));
    expect(all, isNot(contains('technisch')));
    expect(lines.last['type'], 'end');
  });

  test(
    'keine Marke im Klartext und keine gzip-Datei in Export- und Temp-Ordner',
    () async {
      final started = DateTime.now().subtract(const Duration(seconds: 2));
      await fillAllTables(db);
      await sql(
        db,
        "INSERT INTO settings VALUES ('marke', '$fixtureMarker', 1)",
      );
      await sql(db, "UPDATE known_devices SET display_name = '$fixtureMarker'");
      final f = await exporter().export(password: _password);
      final head = File(f.path!).openSync();
      final magic = head.readSync(8);
      head.closeSync();
      expect(utf8.decode(magic), 'RUNARCHV');
      // Nur die Test-Datenbank ist ausgenommen (unverschlüsselt; der Präfix
      // deckt -wal/-shm/-journal). Exportordner und .part werden mitgeprüft.
      expect(
        _leaks(
          [exportDir, Directory.systemTemp],
          Directory('${work.path}/plain.db'),
          started,
        ),
        isEmpty,
      );
      // Selbstprüfung: Die Suche findet die Marke im Klartext der Datenbank.
      expect(_leaks([work], Directory('/nonexistent'), started), isNotEmpty);
    },
  );

  test('Arbeits-Isolate stirbt: keine .part, Fehler ohne Inhalte', () async {
    await fillAllTables(db);
    await sql(db, "UPDATE known_devices SET display_name = '$fixtureMarker'");
    Object? error;
    try {
      await exporter(cipher: _dyingCipher).export(password: _password);
    } catch (e) {
      error = e;
    }
    expect(error, isA<ArchiveExportException>());
    expect(
      (error! as ArchiveExportException).failure,
      ArchiveExportFailure.writeFailed,
    );
    expect(error.toString(), isNot(contains(fixtureMarker)));
    expect(error.toString(), isNot(contains(_password)));
    expect(exportDir.listSync(), isEmpty);
  });

  test('Fehler mitten im Strom: keine Datei im Exportordner', () async {
    await fillAllTables(db);
    await db.close();
    db = openPlain('${work.path}/plain.db');
    final src = _FailingSource(DriftArchiveSource(db), failAt: 6);
    await expectLater(
      ArchiveExporter(
        source: src,
        handoff: handoff,
        clock: FakeClock(DateTime.utc(2026, 11, 7)),
        cipherFactory: createArchiveCipherInWorker,
        pageSize: 2,
      ).export(password: _password),
      throwsA(isA<ArchiveExportException>()),
    );
    expect(exportDir.listSync(), isEmpty);
  });

  test('Kennungen und Grenze: später hinzugekommene Zeilen fehlen', () async {
    await fillAllTables(db);
    final src = _LateInsertSource(DriftArchiveSource(db), db);
    final f = await ArchiveExporter(
      source: src,
      handoff: handoff,
      clock: FakeClock(DateTime.utc(2026, 11, 7)),
      cipherFactory: createArchiveCipherInWorker,
      pageSize: 2,
    ).export(password: _password);
    final lines = await _decode(File(f.path!));
    expect(_rows(lines, 'laps'), hasLength(1));
    expect(_rows(lines, 'runs'), hasLength(1));
  });

  test(
    'Messung: 50 synthetische Läufe (nur mit WP12_MEASURE=1)',
    () async {
      final sw = Stopwatch()..start();
      await db.transaction(() async {
        for (var r = 1; r <= 50; r++) {
          await sql(
            db,
            "INSERT INTO runs (state, started_at_us, ended_at_us, ended_utc_offset_s) VALUES ('finished', ${r * 10000000000}, ${r * 10000000000 + 1800000000}, 3600)",
          );
          String cte(int n) =>
              'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<$n) ';
          final base = r * 10000000000;
          await sql(
            db,
            '${cte(1800)}INSERT INTO raw_positions (run_id, time_us, source, state, latitude_deg, longitude_deg, accuracy_m, speed_mps, speed_accuracy_mps, vertical_accuracy_m) SELECT $r, $base + i*1000000, \'gps\', \'present\', 52.0 + abs(random()) % 100000 / 1e6, 13.0 + abs(random()) % 100000 / 1e6, 3.5 + abs(random()) % 100 / 10.0, 2.5 + abs(random()) % 100 / 100.0, 0.5, 2.0 FROM n',
          );
          await sql(
            db,
            '${cte(1800)}INSERT INTO raw_heart_rates (run_id, time_us, source, state, bpm, contact) SELECT $r, $base + i*1000000, \'strap\', \'present\', 120 + abs(random()) % 60, \'good\' FROM n',
          );
          await sql(
            db,
            '${cte(1800)}INSERT INTO raw_altitudes (run_id, time_us, source, state, altitude_m, vertical_accuracy_m) SELECT $r, $base + i*1000000, \'gps\', \'present\', 30.0 + abs(random()) % 5000 / 100.0, 3.0 FROM n',
          );
          await sql(
            db,
            '${cte(600)}INSERT INTO raw_steps (run_id, time_us, source, state, step_count) SELECT $r, $base + i*3000000, \'phone\', \'present\', i FROM n',
          );
          await sql(
            db,
            '${cte(1800)}INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state) SELECT $r, \'position\', i, $base + i*1000000, \'present\' FROM n',
          );
          await sql(
            db,
            '${cte(1800)}INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state) SELECT $r, \'heart_rate\', i, $base + i*1000000, \'present\' FROM n',
          );
          await sql(
            db,
            '${cte(6)}INSERT INTO laps (run_id, lap_index, marked_at_us, lap_time_s) SELECT $r, i, $base + i*300000000, 300.0 + i FROM n',
          );
        }
      });
      final built = sw.elapsed;
      final rowsN =
          (await db
                  .customSelect(
                    'SELECT (SELECT count(*) FROM raw_positions) + (SELECT count(*) FROM raw_heart_rates) + (SELECT count(*) FROM raw_altitudes) + (SELECT count(*) FROM raw_steps) + (SELECT count(*) FROM preprocessed_samples) AS c',
                  )
                  .get())
              .single
              .data['c'];
      sw.reset();
      final f = await exporter().export(password: _password);
      final took = sw.elapsed;
      // ignore: avoid_print
      print(
        'MESSUNG 50 Läufe: Aufbau ${built.inMilliseconds} ms, $rowsN Zeilen, '
        'Export ${took.inMilliseconds} ms, Datei ${File(f.path!).lengthSync()} Byte',
      );
      final end = (await _decode(File(f.path!))).last['rows']! as Map;
      expect(end['runs'], 50);
      expect(end['raw_positions'], 90000);
      expect(end['preprocessed_samples'], 180000);
    },
    skip: Platform.environment['WP12_MEASURE'] == null
        ? 'nur auf Anforderung'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _FailingSource implements ArchiveSource {
  _FailingSource(this._inner, {required this.failAt});
  final ArchiveSource _inner;
  final int failAt;

  @override
  Future<ArchiveSnapshot> open() async =>
      _FailingSnapshot(await _inner.open(), failAt);
}

class _FailingSnapshot implements ArchiveSnapshot {
  _FailingSnapshot(this._inner, this.failAt);
  final ArchiveSnapshot _inner;
  final int failAt;
  int _n = 0;

  @override
  Future<List<Map<String, Object?>>> readPage(
    ArchiveSectionSpec section, {
    Object? after,
    required int limit,
  }) {
    if (++_n == failAt) throw StateError('Lesefehler (Test)');
    return _inner.readPage(section, after: after, limit: limit);
  }
}

/// Fügt nach dem Öffnen des Stands eine Runde hinzu (Aufnahme läuft weiter).
class _LateInsertSource implements ArchiveSource {
  _LateInsertSource(this._inner, this._db);
  final ArchiveSource _inner;
  final AppDatabase _db;

  @override
  Future<ArchiveSnapshot> open() async {
    final s = await _inner.open();
    await sql(
      _db,
      'INSERT INTO laps (run_id, lap_index, marked_at_us, lap_time_s) VALUES (1, 2, 11, 301.0)',
    );
    await sql(_db, "INSERT INTO runs VALUES (2, 'active', 5000, NULL, NULL)");
    return s;
  }
}
