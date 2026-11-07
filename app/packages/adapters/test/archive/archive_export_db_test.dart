import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const String _password = 'synthetisches Testpasswort';
// Zur Laufzeit gebaut, damit das Testprogramm (dill) die Marke nicht selbst enthält.
final String _marker = ['ARCHIV', 'B1', 'MARKE', '8472'].join('-');
const String _consentMarker = 'EINWILLIGUNG-B1-MARKE-1357';

AppDatabase _open(String path) =>
    AppDatabase(NativeDatabase(File(path), setup: ConnectionSetup.configure));

Future<void> _x(AppDatabase db, String sql, [List<Object?> a = const []]) =>
    db.customStatement(sql, a);

/// Mindestens eine Zeile in jeder Tabelle des Schemas 4 (synthetisch).
Future<void> _fillAll(AppDatabase db) async {
  await _x(
    db,
    "INSERT INTO runs VALUES (1, 'finished', 1000, 2000000000, 3600)",
  );
  await _x(
    db,
    'INSERT INTO laps (run_id, lap_index, marked_at_us, lap_time_s) VALUES (1, 1, 10, 300.5)',
  );
  await _x(
    db,
    "INSERT INTO run_gaps (run_id, kind, start_us) VALUES (1, 'interruption', 5)",
  );
  await _x(
    db,
    'INSERT INTO raw_positions (run_id, time_us, source, state, latitude_deg, longitude_deg, accuracy_m, speed_mps, speed_accuracy_mps, vertical_accuracy_m) '
    "VALUES (1, 1, '$_marker', 'present', 52.5, 13.25, 4.5, 2.75, 0.5, 3.0)",
  );
  await _x(
    db,
    "INSERT INTO raw_heart_rates (run_id, time_us, source, state, bpm, contact) VALUES (1, 1, 'strap', 'present', 140, 'good')",
  );
  await _x(
    db,
    "INSERT INTO raw_altitudes (run_id, time_us, source, state, altitude_m, vertical_accuracy_m) VALUES (1, 1, 'gps', 'present', 35.5, 2.0)",
  );
  await _x(
    db,
    "INSERT INTO raw_steps (run_id, time_us, source, state, step_count) VALUES (1, 1, 'phone', 'present', 12)",
  );
  await _x(
    db,
    'INSERT INTO preprocessing_results (run_id, method, method_version, parameter_version, computed_at_us, total_time_s, moving_time_s, distance_m, bridged_distance_m, average_bpm, max_bpm, median_bpm, best_pace_s_per_km, lap_count, heart_rate_time_s) '
    "VALUES (1, 'preprocessing', 1, 2, 99, 600.0, 590.0, 2000.0, 0.0, 150.5, 170, 151.0, 300.0, 1, 580.0)",
  );
  await _x(
    db,
    "INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state, discard_reason) VALUES (1, 'position', 1, 1, 'discarded', 'hardJump')",
  );
  await _x(
    db,
    "INSERT INTO preprocessed_spans (run_id, kind, start_us, end_us) VALUES (1, 'moving', 1, 9)",
  );
  await _x(
    db,
    'INSERT INTO rated_sections (run_id, start_us, end_us, method, method_version, parameter_version, assessed_at_us, heart_rate_present, heart_rate_estimated, heart_rate_unavailable, heart_rate_discarded, position_present, position_estimated, position_unavailable, position_discarded, missing_heart_rate_share, longest_heart_rate_gap_s, meets_heart_rate_gap_rule, settling_overlap_s, settling_share, gps_gaps) '
    "VALUES (1, 1, 9, 'section-quality', 1, 2, 99, 1, 0, 0, 0, 1, 0, 0, 0, 0.0, 0.0, 1, 0.0, 0.0, '[]')",
  );
  // original (ohne Wert, mit Grund und Basis), dessen Abschnitt, dann current.
  const cv =
      'INSERT INTO computed_values (run_id, value_key, role, value_real, unit, computed_at_us, data_from_us, data_to_us, measurement_count, sources, method, method_version, parameter_version, quality, unavailable_reason, hr_max_bpm, hr_rest_bpm, hr_max_is_estimated) ';
  await _x(
    db,
    "$cv VALUES (1, 'zone_time.unbekannt', 'original', NULL, 's', 99, 1, 9, 3, '[\"strap\"]', 'm', 1, 2, 'undeterminable', 'insufficientData', 190, NULL, 1)",
  );
  await _x(
    db,
    'INSERT INTO value_sections (computed_value_id, position, start_us, end_us, gps_median_accuracy_m, weight, late_factor, status, discard, reasons, oxygen_demand, estimate) '
    "VALUES (1, 0, 1, 2, 3.5, 1.0, 0.5, 'rejected', 'incomplete', '[\"a\"]', 30.5, 45.25)",
  );
  await _x(
    db,
    "$cv VALUES (1, 'zone_time.unbekannt', 'current', 12.5, 's', 100, 1, 9, 3, '[\"strap\"]', 'm', 1, 3, 'good', NULL, 190, 50, 0)",
  );
  await _x(
    db,
    'INSERT INTO computed_values (day, value_key, role, value_real, unit, computed_at_us, measurement_count, sources, method, method_version, parameter_version, quality) '
    "VALUES ('2026-11-07', 'atl', 'original', 7.0, 'au', 100, 1, '[]', 'm', 1, 1, 'good')",
  );
  await _x(
    db,
    'INSERT INTO profile (id, birth_year, body_weight_kg, body_height_m, resting_heart_rate_bpm, max_heart_rate_bpm, weekly_run_minutes, training_days_mask, usual_training_minutes) VALUES (1, 1990, 70.5, 1.8, 50, 190, 120, 5, 45)',
  );
  await _x(db, "INSERT INTO settings VALUES ('unit.pace', 'min_km', 1)");
  await _x(
    db,
    "INSERT INTO settings VALUES ('values.calculationPending', '1,2', 1)",
  );
  await _x(db, "INSERT INTO settings VALUES ('values.refreshPending', '', 1)");
  await _x(db, "INSERT INTO settings VALUES ('recalculation.pending', 'x', 1)");
  await _x(
    db,
    "INSERT INTO known_devices (device_id, display_name, is_preferred, added_at_us) VALUES ('AA:BB', 'Gurt', 1, 5)",
  );
  await _x(db, "INSERT INTO consents VALUES ('$_consentMarker', 'granted', 5)");
  await _x(
    db,
    "INSERT INTO storage_meta VALUES ('technisch', '$_consentMarker')",
  );
}

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
        if (_hasBytes(data, utf8.encode(_marker))) bad.add('Marke: ${e.path}');
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

void main() {
  late Directory work;
  late Directory exportDir;
  late AppDatabase db;
  late FakeFileHandoff handoff;

  setUp(() async {
    work = Directory.systemTemp.createTempSync('wp12b1_db_');
    exportDir = Directory('${work.path}/exports')..createSync();
    handoff = FakeFileHandoff()..directory = exportDir.path;
    db = _open('${work.path}/plain.db');
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
    await _fillAll(db);
    final f = await exporter().export(password: _password);
    expect(exportDir.listSync(), hasLength(1));
    final lines = await _decode(File(f.path!));
    for (final s in archiveSections.where(
      (s) => !s.isReserved && s.name != 'settings',
    )) {
      expect(_rows(lines, s.name), isNotEmpty, reason: s.name);
    }
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
    expect([for (final r in _rows(lines, 'settings')) r['key']], ['unit.pace']);
    final all = jsonEncode(lines);
    expect(all, isNot(contains(_consentMarker)));
    expect(all, isNot(contains('consents')));
    expect(all, isNot(contains('technisch')));
    expect(lines.last['type'], 'end');
  });

  test(
    'keine Marke im Klartext und keine gzip-Datei in Export- und Temp-Ordner',
    () async {
      final started = DateTime.now().subtract(const Duration(seconds: 2));
      await _fillAll(db);
      await _x(db, "INSERT INTO settings VALUES ('marke', '$_marker', 1)");
      await _x(db, "UPDATE known_devices SET display_name = '$_marker'");
      final f = await exporter().export(password: _password);
      final head = File(f.path!).openSync();
      final magic = head.readSync(8);
      head.closeSync();
      expect(utf8.decode(magic), 'RUNARCHV');
      // Quelle (Test-Datenbank) ist ausgenommen: sie ist hier unverschlüsselt.
      expect(_leaks([exportDir, Directory.systemTemp], work, started), isEmpty);
      // Selbstprüfung: Die Suche findet die Marke im Klartext der Datenbank.
      expect(_leaks([work], Directory('/nonexistent'), started), isNotEmpty);
    },
  );

  test('Fehler mitten im Strom: keine Datei im Exportordner', () async {
    await _fillAll(db);
    await db.close();
    db = _open('${work.path}/plain.db');
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
    await _fillAll(db);
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
          await _x(
            db,
            "INSERT INTO runs (state, started_at_us, ended_at_us, ended_utc_offset_s) VALUES ('finished', ${r * 10000000000}, ${r * 10000000000 + 1800000000}, 3600)",
          );
          String cte(int n) =>
              'WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<$n) ';
          final base = r * 10000000000;
          await _x(
            db,
            '${cte(1800)}INSERT INTO raw_positions (run_id, time_us, source, state, latitude_deg, longitude_deg, accuracy_m, speed_mps, speed_accuracy_mps, vertical_accuracy_m) SELECT $r, $base + i*1000000, \'gps\', \'present\', 52.0 + abs(random()) % 100000 / 1e6, 13.0 + abs(random()) % 100000 / 1e6, 3.5 + abs(random()) % 100 / 10.0, 2.5 + abs(random()) % 100 / 100.0, 0.5, 2.0 FROM n',
          );
          await _x(
            db,
            '${cte(1800)}INSERT INTO raw_heart_rates (run_id, time_us, source, state, bpm, contact) SELECT $r, $base + i*1000000, \'strap\', \'present\', 120 + abs(random()) % 60, \'good\' FROM n',
          );
          await _x(
            db,
            '${cte(1800)}INSERT INTO raw_altitudes (run_id, time_us, source, state, altitude_m, vertical_accuracy_m) SELECT $r, $base + i*1000000, \'gps\', \'present\', 30.0 + abs(random()) % 5000 / 100.0, 3.0 FROM n',
          );
          await _x(
            db,
            '${cte(600)}INSERT INTO raw_steps (run_id, time_us, source, state, step_count) SELECT $r, $base + i*3000000, \'phone\', \'present\', i FROM n',
          );
          await _x(
            db,
            '${cte(1800)}INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state) SELECT $r, \'position\', i, $base + i*1000000, \'present\' FROM n',
          );
          await _x(
            db,
            '${cte(1800)}INSERT INTO preprocessed_samples (run_id, channel, raw_id, time_us, state) SELECT $r, \'heart_rate\', i, $base + i*1000000, \'present\' FROM n',
          );
          await _x(
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
    await _x(
      _db,
      'INSERT INTO laps (run_id, lap_index, marked_at_us, lap_time_s) VALUES (1, 2, 11, 301.0)',
    );
    await _x(_db, "INSERT INTO runs VALUES (2, 'active', 5000, NULL, NULL)");
    return s;
  }
}
