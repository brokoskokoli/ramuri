// Wiederherstellung aus dem Archiv mit echter verschlüsselter Datenbank
// (sqlite3mc), echter Kryptografie und echten Dateien (WP12 Teil C2): Rundgang,
// Ablehnung bei nicht leerer App, jeder Fehlerfall lässt die aktive Datenbank
// unverändert, Fehlerinjektion an jedem Schritt des Tauschs, kein Klartext.
// Alle Daten sind synthetisch.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

import '../storage/support.dart' show testKey;
import 'archive_fixture.dart';

const String _password = 'synthetisches Testpasswort';
const String _vectors = 'test/archive/vectors';
final String _smallPassword =
    ((jsonDecode(File('$_vectors/vectors.json').readAsStringSync())
                    as Map)['vectors']
                as List)
            .cast<Map>()
            .firstWhere((v) => v['name'] == 'archive_small')['password']
        as String;

typedef _Dump = Map<String, List<Map<String, Object?>>>;

/// Alle Tabellen außer `storage_meta`, `consents` und den technischen Merkern.
Future<_Dump> _dump(AppDatabase db) async {
  final names = [
    for (final r
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )
            .get())
      r.data['name']! as String,
  ];
  final out = <String, List<Map<String, Object?>>>{};
  for (final n in names) {
    if (n == 'storage_meta' || n == 'consents') continue;
    final rows = await db.customSelect('SELECT * FROM $n ORDER BY rowid').get();
    out[n] = [
      for (final r in rows)
        if (n != 'settings' ||
            !archiveExcludedSettingKeys.contains(r.data['key']))
          Map<String, Object?>.of(r.data),
    ];
  }
  return out;
}

AppDatabase _dbOf(StorageSession s) => (s as EncryptedStorageSession).database;

Future<void> _extra(AppDatabase db) async {
  // Zweiter Lauf: Original mit zwei Abschnitten, current mit einem.
  await sql(db, "INSERT INTO runs VALUES (2, 'finished', 5000, 9000, NULL)");
  const cv =
      'INSERT INTO computed_values (run_id, value_key, role, value_real, unit, computed_at_us, measurement_count, sources, method, method_version, parameter_version, quality) ';
  const vs =
      'INSERT INTO value_sections (computed_value_id, position, start_us, end_us, weight, late_factor, status, reasons) ';
  await sql(
    db,
    "$cv VALUES (2, 'vo2.neu', 'original', 41.5, 'x', 9, 3, '[]', 'm', 1, 1, 'good')",
  );
  final o =
      (await db
                  .customSelect('SELECT MAX(id) AS m FROM computed_values')
                  .getSingle())
              .data['m']!
          as int;
  await sql(db, "$vs VALUES ($o, 0, 1, 2, 1.0, 1.0, 'eligible', '[]')");
  await sql(db, "$vs VALUES ($o, 1, 2, 3, 0.5, 1.0, 'provisional', '[\"r\"]')");
  await sql(
    db,
    "$cv VALUES (2, 'vo2.neu', 'current', 42.5, 'x', 10, 3, '[]', 'm', 1, 1, 'good')",
  );
  final c = o + 1;
  await sql(db, "$vs VALUES ($c, 0, 1, 2, 1.0, 1.0, 'eligible', '[]')");
}

Future<Uint8List> _encrypt(List<Map<String, Object?>> lines) async {
  final text = '${lines.map(jsonEncode).join('\n')}\n';
  final b = BytesBuilder(copy: false);
  await for (final c in createArchiveCipher(
    offload: inlineOffloadAsync,
  ).encrypt(_password, Stream.value(gzip.encode(utf8.encode(text))))) {
    b.add(c);
  }
  return b.takeBytes();
}

Future<List<Map<String, Object?>>> _decode(File f) async {
  final b = BytesBuilder(copy: false);
  await for (final c in createArchiveCipher(
    offload: inlineOffloadAsync,
  ).decrypt(_password, Stream.value(f.readAsBytesSync()))) {
    b.add(c);
  }
  return [
    for (final l
        in utf8.decode(gzip.decode(b.takeBytes())).trimRight().split('\n'))
      jsonDecode(l) as Map<String, Object?>,
  ];
}

/// Ändert die Zeile [index] (nullbasiert) des Abschnitts [section].
List<Map<String, Object?>> _mutate(
  List<Map<String, Object?>> lines,
  String section,
  void Function(Map<String, Object?> data) change, {
  int index = 0,
}) {
  final out = [
    for (final l in lines)
      Map<String, Object?>.of(l)..addAll({
        if (l['data'] != null)
          'data': Map<String, Object?>.of((l['data']! as Map).cast()),
      }),
  ];
  String? cur;
  var n = 0;
  for (final l in out) {
    if (l['type'] == 'section') {
      cur = l['name'] as String;
      n = 0;
    }
    if (l['type'] == 'row' && cur == section && n++ == index) {
      change(l['data']! as Map<String, Object?>);
      return out;
    }
  }
  throw StateError('Zeile fehlt');
}

/// Reicht an den echten Sink durch und lässt an zwei Stellen eingreifen.
class _SpySink implements ArchiveSink {
  _SpySink(this.inner);
  final ArchiveSink inner;
  Future<void> Function()? beforeCommit;
  int? crashAtInsert; // Prozessende: Ausnahme, abort räumt NICHT auf.
  int _n = 0;
  bool crashed = false;

  @override
  Future<void> begin() => inner.begin();

  @override
  Future<void> insert(ArchiveSectionSpec s, List<Map<String, Object?>> r) {
    if (crashAtInsert != null && ++_n == crashAtInsert) {
      crashed = true;
      throw StateError('Prozess endet');
    }
    return inner.insert(s, r);
  }

  @override
  Future<void> commit() async {
    await beforeCommit?.call();
    await inner.commit();
  }

  @override
  Future<void> abort() async {
    if (crashed) return; // ein getöteter Prozess räumt nicht auf
    await inner.abort();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory work;
  late Directory src;
  late Directory appDir;
  late String activePath;
  late String archivePath;
  late _Dump sourceDump;
  late Uint8List key;
  late FileDatabaseFiles files;
  late StorageSession session;
  var serialized = 0;
  void Function(String)? hook;

  FileDatabaseFiles makeFiles() =>
      FileDatabaseFiles(activePath, beforeStep: (s) => hook?.call(s));

  Future<StorageSession> openActive() => EncryptedStorage(activePath).open(key);

  ArchiveRestoreService service({
    ArchiveSink? sink,
    FileDatabaseFiles? f,
    Future<T> Function<T>(Future<T> Function())? serialize,
  }) {
    final fl = f ?? files;
    return ArchiveRestoreService(
      session: session,
      sink:
          sink ??
          DriftArchiveSink(
            storage: EncryptedStorage(fl.importPath),
            key: () => key,
            files: fl,
          ),
      files: fl,
      cipherFactory: createArchiveCipherInWorker,
      clock: FakeClock(DateTime.utc(2026, 11, 20, 12)),
      reopen: () async => session = await openActive(),
      serialize:
          serialize ??
          <T>(Future<T> Function() a) {
            serialized++;
            return a();
          },
    );
  }

  Future<void> addOldData() async {
    await _dbOf(
      session,
    ).customStatement("INSERT INTO runs VALUES (77, 'finished', 1, 2, NULL)");
    await _dbOf(session)
        .customStatement("INSERT INTO settings VALUES ('alt', 'bleibt', 1)");
  }

  List<String> appFiles() =>
      [for (final e in appDir.listSync()) e.path.split('/').last]..sort();

  setUp(() async {
    serialized = 0;
    hook = null;
    key = testKey(3);
    work = Directory.systemTemp.createTempSync('wp12c2_');
    appDir = Directory('${work.path}/app')..createSync();
    activePath = '${appDir.path}/running_app.db';
    files = makeFiles();
    // Quelle: Klartext-Datenbank mit allem, exportiert mit echter Kryptografie.
    // Nicht unter systemTemp: Der Marken-Test des Exports durchsucht ihn, und
    // die Testdateien laufen gleichzeitig (Review 2, Befund 2). Die Klartext-
    // Quelle liegt im (nicht versionierten) .dart_tool des Pakets.
    Directory('.dart_tool').createSync();
    src = Directory('.dart_tool').createTempSync('wp12c2src_');
    final exportDir = Directory('${work.path}/exports')..createSync();
    final plain = openPlain('${src.path}/plain.db');
    await fillAllTables(plain);
    await _extra(plain);
    sourceDump = await _dump(plain);
    final handoff = FakeFileHandoff()..directory = exportDir.path;
    final f = await ArchiveExporter(
      source: DriftArchiveSource(plain),
      handoff: handoff,
      clock: FakeClock(DateTime.utc(2026, 11, 7, 12)),
      cipherFactory: createArchiveCipherInWorker,
      pageSize: 2,
    ).export(password: _password);
    archivePath = f.path!;
    await plain.close();
    src.deleteSync(recursive: true); // enthält die Marke im Klartext
    session = await openActive();
  });

  tearDown(() async {
    try {
      await session.close();
    } catch (_) {}
    work.deleteSync(recursive: true);
    if (src.existsSync()) src.deleteSync(recursive: true);
  });

  test(
    'Rundgang: Export -> Import auf leerer App, alle Tabellen zeilengleich',
    () async {
      // Einwilligung und Merker in der leeren App: kein Hindernis, danach weg.
      await session.consents.set(
        'quelle',
        ConsentState.granted,
        at: DateTime.utc(2026),
      );
      await session.settings.set(
        'values.refreshPending',
        '1',
        at: DateTime.utc(2026),
      );
      expect(await ArchiveRestoreService.isEmpty(session), isTrue);

      session = await service().restore(path: archivePath, password: _password);

      final got = await _dump(_dbOf(session));
      expect(got.keys, sourceDump.keys);
      for (final t in sourceDump.keys) {
        expect(got[t], sourceDump[t], reason: t);
        if (t != 'settings') expect(got[t], isNotEmpty, reason: t);
      }
      // computed_values original + current, unbekannter Schlüssel, Abschnitte.
      final cv = got['computed_values']!;
      expect(cv.map((r) => r['role']).toSet(), {'original', 'current'});
      expect(cv.map((r) => r['value_key']), contains('zone_time.unbekannt'));
      expect(got['value_sections'], hasLength(4));
      // Einwilligungen nicht erteilt, Merker weg.
      expect(await session.consents.all(), isEmpty);
      expect(await session.settings.get('values.refreshPending'), isNull);
      // Danach nur die aktive Datenbank, keine Zwischendatenbank.
      expect(await files.importExists(), isFalse);
      expect(appFiles().where((n) => n.contains('.import')), isEmpty);
      expect(serialized, 1);
      // Neu geöffnete Datenbank ist benutzbar (Schema 4, Schreiben geht).
      await _dbOf(session).customStatement(
        "INSERT INTO runs VALUES (99, 'active', 1, NULL, NULL)",
      );
    },
  );

  test(
    'Karteneinwilligung kommt mit dem Reimport nicht zurück (K30)',
    () async {
      await session.consents.set(
        mapProviderSourceKey,
        ConsentState.granted,
        at: DateTime.utc(2026),
      );
      expect(
        await session.consents.get(mapProviderSourceKey),
        ConsentState.granted,
      );
      session = await service().restore(path: archivePath, password: _password);
      // Nicht erteilt und nie gefragt: Die Oberfläche fragt beim nächsten Öffnen einer Karte neu.
      expect(await session.consents.get(mapProviderSourceKey), isNull);
    },
  );

  test('Einwilligung aus der Quellinstallation kommt nicht mit', () async {
    session = await service().restore(path: archivePath, password: _password);
    expect(await session.consents.get(fixtureConsentMarker), isNull);
    expect(await session.consents.all(), isEmpty);
  });

  group('nicht leere App', () {
    final cases = <String, Future<void> Function(StorageSession)>{
      'Lauf': (s) async => _dbOf(
        s,
      ).customStatement("INSERT INTO runs VALUES (77, 'finished', 1, 2, NULL)"),
      'Profil': (s) async =>
          s.profile.save(const ProfileRecord(birthYear: 1990)),
      'Einstellung': (s) =>
          s.settings.set('unit.pace', 'x', at: DateTime.utc(2026)),
      'Gerät': (s) => s.devices.upsert(
        'AA:BB',
        displayName: 'Gurt',
        at: DateTime.utc(2026),
      ),
    };
    for (final e in cases.entries) {
      test(
        '${e.key}: abgelehnt ohne Zurücksetzen, Datenbank unverändert',
        () async {
          await e.value(session);
          final before = await _dump(_dbOf(session));
          await expectLater(
            service().restore(path: archivePath, password: _password),
            throwsA(
              isA<ArchiveRestoreException>().having(
                (x) => x.failure,
                'failure',
                ArchiveRestoreFailure.notEmpty,
              ),
            ),
          );
          expect(await _dump(_dbOf(session)), before);
          expect(
            await files.importExists(),
            isFalse,
            reason: 'nichts angelegt',
          );
          expect(appFiles().any((n) => n.contains('.import')), isFalse);
        },
      );
    }

    test(
      'mit ausdrücklichem Zurücksetzen: alte Daten weg, Archiv da',
      () async {
        await addOldData();
        session = await service().restore(
          path: archivePath,
          password: _password,
          resetConfirmed: true,
        );
        final got = await _dump(_dbOf(session));
        expect(got, sourceDump);
        expect(got['runs']!.map((r) => r['id']), isNot(contains(77)));
      },
    );
  });

  test('archive_small (Vektor der unabhängigen Umsetzung) lässt sich importieren, Zeilen gleich', () async {
    session = await service().restore(
      path: '$_vectors/archive_small.runarchv',
      password: _smallPassword,
    );
    final lines = [
      for (final l in File('$_vectors/archive_small.jsonl').readAsLinesSync())
        jsonDecode(l) as Map<String, dynamic>,
    ];
    String? cur;
    final expected = <String, List<Map<String, Object?>>>{};
    for (final l in lines) {
      if (l['type'] == 'section') cur = l['name'] as String;
      if (l['type'] == 'row') {
        (expected[cur!] ??= []).add((l['data'] as Map).cast<String, Object?>());
      }
    }
    final got = await _dump(_dbOf(session));
    for (final e in expected.entries) {
      expect(got[e.key]!.length, e.value.length, reason: e.key);
      // Nur Ganzzahl-/Textspalten vergleichbar ohne Gleitkomma-Normalisierung.
      expect(
        [for (final r in got[e.key]!) r['id'] ?? r['key']],
        [for (final r in e.value) r['id'] ?? r['key']],
        reason: e.key,
      );
    }
    expect(await session.consents.all(), isEmpty);
    // Format 1 (Schema 4) kennt die Angaben und Trainings nicht: leer.
    expect(got['run_feedback'], isEmpty);
    expect(got['manual_trainings'], isEmpty);
    expect(await session.manualTrainings.list(), isEmpty);
    expect(await session.subjective.readAll(), isEmpty);
  });

  test(
    'Alles löschen, dann Reimport: Angaben, sRPE und Trainings sind wieder da',
    () async {
      final before = await _dump(_dbOf(session));
      expect(before['run_feedback'], isEmpty); // leere App
      session = await service().restore(path: archivePath, password: _password);
      final restored = await _dump(_dbOf(session));
      expect(restored['run_feedback'], sourceDump['run_feedback']);
      expect(restored['manual_trainings'], sourceDump['manual_trainings']);
      await session.deleteAll();
      final empty = await _dump(_dbOf(session));
      expect(empty['run_feedback'], isEmpty);
      expect(empty['manual_trainings'], isEmpty);
      expect(await ArchiveRestoreService.isEmpty(session), isTrue);
      session = await service().restore(path: archivePath, password: _password);
      final again = await _dump(_dbOf(session));
      expect(again['run_feedback'], sourceDump['run_feedback']);
      expect(again['manual_trainings'], sourceDump['manual_trainings']);
      final fb = (await session.subjective.read(1))!;
      expect(fb.subjective.rpe, 5);
      expect(fb.srpe!.points, 225.0);
      final trainings = await session.manualTrainings.list();
      expect(trainings, hasLength(2));
      // Datum in der Zukunft wurde angenommen.
      expect(trainings.map((t) => t.training.isoDay), contains('2026-11-20'));
    },
  );

  test('nachgetragene Trainings machen die App nicht leer', () async {
    expect(await ArchiveRestoreService.isEmpty(session), isTrue);
    await session.manualTrainings.add(
      ManualTraining(
        day: DateTime.utc(2026, 11, 1),
        kind: ManualTrainingKind.other,
        duration: const Duration(minutes: 45),
        rpe: 5,
      ),
    );
    expect(await ArchiveRestoreService.isEmpty(session), isFalse);
  });

  group('Fehler: aktive Datenbank unverändert, keine Zwischendatenbank', () {
    Future<void> expectUntouched(
      Future<Object?> Function() run,
      ArchiveImportFailure f,
    ) async {
      await addOldData();
      final before = await _dump(_dbOf(session));
      await expectLater(
        run(),
        throwsA(
          isA<ArchiveImportException>().having((e) => e.failure, 'failure', f),
        ),
      );
      expect(await _dump(_dbOf(session)), before);
      expect(await files.importExists(), isFalse);
      expect(appFiles().where((n) => n.contains('.import')), isEmpty);
    }

    final meta = jsonDecode(
      File('$_vectors/vectors.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    const failures = {
      'wrong_password_or_start_damaged':
          ArchiveImportFailure.wrongPasswordOrDamaged,
      'corrupt': ArchiveImportFailure.damaged,
      'unknown_version': ArchiveImportFailure.unsupportedVersion,
      'unsupported_parameters': ArchiveImportFailure.unsupportedParameters,
      'not_an_archive': ArchiveImportFailure.notAnArchive,
    };
    for (final v
        in (meta['vectors'] as List).cast<Map<String, dynamic>>().where(
          (v) => v['expect'] != 'ok',
        )) {
      test('Negativvektor ${v['name']}', () async {
        await expectUntouched(
          () => service().restore(
            path: '$_vectors/${v['file']}',
            password: v['password'] as String,
            resetConfirmed: true,
          ),
          failures[v['expect']]!,
        );
      });
    }

    final cases = <String, (String, void Function(Map<String, Object?>), int)>{
      'CHECK: runs.state unbekannt': ('runs', (d) => d['state'] = 'bogus', 0),
      'Fremdschlüssel: Rohposition ohne Lauf': (
        'raw_positions',
        (d) => d['run_id'] = 99,
        0,
      ),
      'Trigger: Wert ohne Grund': (
        'computed_values',
        (d) {
          d['value_real'] = null;
          d['unavailable_reason'] = null;
        },
        1,
      ),
      'Fremdschlüssel: Abschnitt ohne Wert': (
        'value_sections',
        (d) => d['computed_value_id'] = 999,
        0,
      ),
      'Eindeutigkeit: doppelter Wert je Lauf': (
        'computed_values',
        (d) {
          d['value_key'] = 'zone_time.unbekannt';
          d['run_id'] = 1;
        },
        3,
      ),
      // WP18 (Format 2): Angaben zum Lauf und nachgetragene Trainings.
      'Leser: RPE 11': ('run_feedback', (d) => d['rpe'] = 11, 0),
      'Leser: RPE 5.5': ('run_feedback', (d) => d['rpe'] = 5.5, 0),
      'Leser: Befinden 0': ('run_feedback', (d) => d['wellbeing'] = 0, 0),
      'Leser: sRPE-Wert passt nicht zu Dauer mal RPE': (
        'run_feedback',
        (d) => d['srpe_points'] = 226.0,
        0,
      ),
      'CHECK: sRPE-Spalten nicht alle gesetzt': (
        'run_feedback',
        (d) => d['srpe_method'] = null,
        0,
      ),
      'CHECK: Warnsignal-Antwort ohne Beschwerden': (
        'run_feedback',
        (d) => d['complaints'] = null,
        0,
      ),
      'CHECK: Warnsignal-Antwort unbekannt': (
        'run_feedback',
        (d) => d['warning_answer'] = 'vielleicht',
        0,
      ),
      'Fremdschlüssel: Angabe ohne Lauf': (
        'run_feedback',
        (d) => d['run_id'] = 99,
        0,
      ),
      'Leser: Training Dauer 0': (
        'manual_trainings',
        (d) => d['duration_s'] = 0,
        0,
      ),
      'Leser: Training RPE 11': ('manual_trainings', (d) => d['rpe'] = 11, 1),
      'CHECK: Training ungültiges Datum': (
        'manual_trainings',
        (d) => d['day'] = '2026-02-30',
        0,
      ),
      'CHECK: Training unbekannte Art': (
        'manual_trainings',
        (d) => d['kind'] = 'swim',
        0,
      ),
    };
    for (final c in cases.entries) {
      test(c.key, () async {
        final lines = _mutate(
          await _decode(File(archivePath)),
          c.value.$1,
          c.value.$2,
          index: c.value.$3,
        );
        final f = File('${work.path}/bad.runarchv')
          ..writeAsBytesSync(await _encrypt(lines));
        await expectUntouched(
          () => service().restore(
            path: f.path,
            password: _password,
            resetConfirmed: true,
          ),
          ArchiveImportFailure.damaged,
        );
      });

      // SEC-0009: Die Prüfung vor dem Löschen der alten Datei muss dieselben
      // Beschränkungen der Datenbank anwenden wie der Dienst.
      test('Vorprüfung (SEC-0009) lehnt ab: ${c.key}', () async {
        final lines = _mutate(
          await _decode(File(archivePath)),
          c.value.$1,
          c.value.$2,
          index: c.value.$3,
        );
        final f = File('${work.path}/bad.runarchv')
          ..writeAsBytesSync(await _encrypt(lines));
        await expectLater(
          verifyArchive(
            path: f.path,
            password: _password,
            files: files,
            cipherFactory: createArchiveCipherInWorker,
            clock: FakeClock(DateTime.utc(2026, 11, 20, 12)),
          ),
          throwsA(
            isA<ArchiveImportException>().having(
              (e) => e.failure,
              'failure',
              ArchiveImportFailure.damaged,
            ),
          ),
        );
        expect(appFiles().where((n) => n.contains('.import')), isEmpty);
      });
    }

    test(
      'Vorprüfung (SEC-0009): gültiges Archiv besteht, nichts bleibt',
      () async {
        await verifyArchive(
          path: archivePath,
          password: _password,
          files: files,
          cipherFactory: createArchiveCipherInWorker,
          clock: FakeClock(DateTime.utc(2026, 11, 20, 12)),
        );
        expect(appFiles().where((n) => n.contains('.import')), isEmpty);
      },
    );

    test('Fehler des Ziels (Zwischendatenbank nicht anlegbar): Zielfehler, unverändert', () async {
      final blocked = FileDatabaseFiles(
        activePath,
        importPath: (Directory(
          '${work.path}/verzeichnis.import',
        )..createSync()).path,
      );
      await expectUntouched(
        () => service(
          f: blocked,
        ).restore(path: archivePath, password: _password, resetConfirmed: true),
        ArchiveImportFailure.targetFailed,
      );
    });
  });

  group('Kein Klartext in der Zwischendatenbank', () {
    test(
      'Marke nirgends im Arbeitsverzeichnis, auch nicht kurz vor commit',
      () async {
        final spy = _SpySink(
          DriftArchiveSink(
            storage: EncryptedStorage(files.importPath),
            key: () => key,
            files: files,
          ),
        );
        var checked = false;
        spy.beforeCommit = () async {
          checked = true;
          // Die Zwischendatenbank existiert mit allen Zeilen, ist aber verschlüsselt.
          final imp = File(files.importPath);
          expect(imp.existsSync(), isTrue);
          expect(imp.lengthSync(), greaterThan(0));
          expect(defaultFileEncryptedProbe(files.importPath), isTrue);
          expect(_leaks(work), isEmpty);
        };
        session = await service(sink: spy)
            .restore(path: archivePath, password: _password);
        expect(checked, isTrue);
        expect(_leaks(work), isEmpty);
        // Positivkontrolle: Die Marke steht in den Daten (sonst wäre die Suche leer).
        final rows = await _dbOf(session)
            .customSelect('SELECT source FROM raw_positions')
            .get();
        expect(rows.single.data['source'], fixtureMarker);
      },
    );

    test('Positivkontrolle der Suche: Klartext-Datei wird gefunden', () {
      File('${work.path}/plain.txt').writeAsStringSync('x $fixtureMarker y');
      expect(_leaks(work), hasLength(1));
    });
  });

  group('Abbruch und Prozessende', () {
    test('Prozessende mitten im Einlesen: aktive unverändert, Rest wird beim Start gelöscht', () async {
      await addOldData();
      final before = await _dump(_dbOf(session));
      final spy = _SpySink(
        DriftArchiveSink(
          storage: EncryptedStorage(files.importPath),
          key: () => key,
          files: files,
        ),
      )..crashAtInsert = 3;
      await expectLater(
        service(
          sink: spy,
        ).restore(path: archivePath, password: _password, resetConfirmed: true),
        throwsA(isA<ArchiveImportException>()),
      );
      expect(await _dump(_dbOf(session)), before);
      expect(
        await files.importExists(),
        isTrue,
        reason: 'getöteter Prozess räumt nicht auf',
      );
      // Start-Ablauf: Rest löschen, Datenbank öffnen.
      await session.close();
      await makeFiles().deleteImport();
      expect(appFiles(), isNot(contains(contains('.import'))));
      session = await openActive();
      expect(await _dump(_dbOf(session)), before);
    });

    test('Prozessende vor commit (Zwischendatenbank voll, nicht festgeschrieben): nie getauscht', () async {
      await addOldData();
      final before = await _dump(_dbOf(session));
      final spy = _SpySink(
        DriftArchiveSink(
          storage: EncryptedStorage(files.importPath),
          key: () => key,
          files: files,
        ),
      );
      spy.beforeCommit = () async =>
          throw StateError('Prozess endet vor commit');
      await expectLater(
        service(
          sink: spy,
        ).restore(path: archivePath, password: _password, resetConfirmed: true),
        throwsA(isA<ArchiveImportException>()),
      );
      expect(await _dump(_dbOf(session)), before);
    });

    final steps = FileDatabaseFiles.replaceSteps;
    for (var n = 0; n < steps.length; n++) {
      test(
        'Prozessende vor/nach Tauschschritt ${steps[n]}: alter oder ganz neuer Stand',
        () async {
          await addOldData();
          final old = await _dump(_dbOf(session));
          hook = (s) {
            if (s == steps[n]) throw StateError('Prozess endet bei $s');
          };
          final f = makeFiles();
          await expectLater(
            service(f: f).restore(
              path: archivePath,
              password: _password,
              resetConfirmed: true,
            ),
            throwsA(isA<ArchiveRestoreException>()),
          );
          await session.close();
          // Neuer Start: Rest löschen, normal öffnen.
          hook = null;
          await makeFiles().deleteImport();
          session = await openActive();
          final now = await _dump(_dbOf(session));
          final expected = steps[n] == 'renamed' ? sourceDump : old;
          expect(now, expected, reason: 'Schritt ${steps[n]}');
          expect(now, anyOf(old, sourceDump));
          expect(appFiles().where((x) => x.contains('.import')), isEmpty);
          expect(now['runs'], isNotEmpty, reason: 'nie leer');
        },
      );
    }
  });

  test('swapFailed trägt die neu geöffnete Sitzung (alter Stand)', () async {
    await addOldData();
    hook = (s) {
      if (s == 'rename') throw StateError('Tausch scheitert');
    };
    final old = session;
    Object? error;
    try {
      await service().restore(
        path: archivePath,
        password: _password,
        resetConfirmed: true,
      );
    } catch (e) {
      error = e;
    }
    hook = null;
    expect(error, isA<ArchiveRestoreException>());
    final e = error! as ArchiveRestoreException;
    expect(e.failure, ArchiveRestoreFailure.swapFailed);
    expect(e.session, isNotNull);
    expect(e.session, isNot(same(old)));
    final rows = await _dbOf(e.session!)
        .customSelect('SELECT id FROM runs WHERE id = 77')
        .get();
    expect(rows, hasLength(1));
  });

  test('zweite Verbindung offen, kein Checkpoint beim close: swapFailed, alter Stand, Zwischendatei weg', () async {
    await addOldData();
    final other = await openActive();
    final gate = Completer<void>();
    final started = Completer<void>();
    final reading = _dbOf(other).transaction(() async {
      await _dbOf(other).customSelect('SELECT * FROM runs').get();
      started.complete();
      await gate.future;
    });
    await started.future;
    Object? error;
    try {
      await service().restore(
        path: archivePath,
        password: _password,
        resetConfirmed: true,
      );
    } catch (e) {
      error = e;
    }
    gate.complete();
    await reading;
    await other.close();
    expect(error, isA<ArchiveRestoreException>());
    expect(
      (error! as ArchiveRestoreException).failure,
      ArchiveRestoreFailure.swapFailed,
    );
    expect(await files.importExists(), isFalse);
  });

  group('FileDatabaseFiles', () {
    test(
      'replaceWithImport entfernt -wal/-shm/-journal beider Seiten',
      () async {
        await session.close();
        for (final s in ['', '-shm', '-journal']) {
          File('$activePath$s').writeAsBytesSync([1, 2, 3]);
        }
        File('$activePath-wal').writeAsBytesSync([]); // leer: eingecheckt
        for (final s in ['-wal', '-shm', '-journal']) {
          File('${files.importPath}$s').writeAsBytesSync([9]);
        }
        File(files.importPath).writeAsBytesSync([7, 7, 7, 7]);
        await files.replaceWithImport();
        expect(File(activePath).readAsBytesSync(), [7, 7, 7, 7]);
        expect(appFiles(), ['running_app.db']);
        session = await openActive().catchError((_) => session);
      },
    );

    test(
      'aktives -wal mit Inhalt (nicht eingecheckt): kein Tausch, Daten bleiben',
      () async {
        // Zustand nach einem Prozessende ohne Checkpoint: Hauptdatei alt, die
        // Läufe stehen nur im -wal (Review 2, Befund 1).
        await addOldData();
        final snap = Directory('${work.path}/snap')..createSync();
        File(activePath).copySync('${snap.path}/db');
        File('$activePath-wal').copySync('${snap.path}/wal');
        File('$activePath-shm').copySync('${snap.path}/shm');
        await session.close();
        File('${snap.path}/db').copySync(activePath);
        File('${snap.path}/wal').copySync('$activePath-wal');
        File('${snap.path}/shm').copySync('$activePath-shm');
        expect(File('$activePath-wal').lengthSync(), greaterThan(0));
        File(files.importPath).writeAsBytesSync([7, 7, 7, 7]);
        final walBefore = File('$activePath-wal').readAsBytesSync();
        hook = (s) {
          if (s == 'rename') throw StateError('Prozess endet bei $s');
        };
        await expectLater(
          files.replaceWithImport(),
          throwsA(isA<FileSystemException>()),
        );
        expect(File('$activePath-wal').readAsBytesSync(), walBefore);
        hook = null;
        await files.deleteImport();
        session = await openActive();
        final runs = await _dbOf(session)
            .customSelect('SELECT id FROM runs WHERE id = 77')
            .get();
        expect(runs, hasLength(1), reason: 'Lauf 77 darf nicht verloren sein');
      },
    );

    test('deleteImport löscht alle vier Dateien und nur diese', () async {
      for (final s in ['', '-wal', '-shm', '-journal']) {
        File('${files.importPath}$s').writeAsBytesSync([1]);
      }
      expect(await files.importExists(), isTrue);
      expect(await files.exist(), isTrue, reason: 'aktive Datenbank');
      await files.deleteImport();
      expect(await files.importExists(), isFalse);
      expect(File(activePath).existsSync(), isTrue);
    });

    test('exist zählt die Zwischendatenbank nicht (kein Schlüssel-Neubeginn durch Reste)', () async {
      await session.close();
      await files.deleteAll();
      File(files.importPath).writeAsBytesSync([1]);
      expect(await files.exist(), isFalse);
      expect(await files.importExists(), isTrue);
      await files.deleteImport();
      session = await openActive();
    });

    test(
      'replaceWithImport ohne Zwischendatenbank wirft und ändert nichts',
      () async {
        await session.close();
        final before = File(activePath).readAsBytesSync();
        await expectLater(
          files.replaceWithImport(),
          throwsA(isA<FileSystemException>()),
        );
        expect(File(activePath).readAsBytesSync(), before);
        session = await openActive();
      },
    );
  });
}

/// Dateien unter [dir] mit der Marke im Klartext oder mit dem Klartext-
/// SQLite-Kopf.
List<String> _leaks(Directory dir) {
  final bad = <String>[];
  final needle = utf8.encode(fixtureMarker);
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final data = e.readAsBytesSync();
    var found = false;
    outer:
    for (var i = 0; i + needle.length <= data.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (data[i + j] != needle[j]) continue outer;
      }
      found = true;
      break;
    }
    final plainHead =
        data.length >= 16 &&
        List.generate(15, (i) => data[i]).toString() ==
            plainSqliteHeader.sublist(0, 15).toString();
    if (found || plainHead) bad.add(e.path);
  }
  return bad;
}
