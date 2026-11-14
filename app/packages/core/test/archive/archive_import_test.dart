import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

const String _password = 'synthetisches Testpasswort';
const String _marker = 'SYNTHETISCHE-MARKE-4711';

ArchiveCipher _fakeCipher({int format = 2}) => FramedArchiveCipher(
  kdf: FakeArchiveKdf(),
  aead: FakeChunkAead(),
  randomBytes: (n) => Uint8List(n),
  headerFormat: format,
);

/// Die Datei ist schon der gzip-Strom (keine Kryptografie, schnell).
class _Identity implements ArchiveCipher {
  _Identity({this.failAtEnd = false});

  final bool failAtEnd;

  @override
  Stream<Uint8List> encrypt(String password, Stream<List<int>> plaintext) =>
      throw UnimplementedError();

  @override
  Stream<Uint8List> decrypt(String password, Stream<List<int>> archive) async* {
    await for (final c in archive) {
      yield Uint8List.fromList(c);
    }
    // Wie ein Rahmen, dessen letztes Stück nicht stimmt: alles davor kam an.
    if (failAtEnd) throw const ArchiveException(ArchiveFailure.damaged);
  }
}

ArchiveCipher _identity() => _Identity();
ArchiveCipher _identityFailAtEnd() => _Identity(failAtEnd: true);

Object _valueFor(ArchiveColumn c, int i) => switch (c.type) {
  ArchiveType.integer => i,
  ArchiveType.real => i + 0.25,
  ArchiveType.text => 's$i',
  ArchiveType.boolean => i % 2,
  ArchiveType.blob => Uint8List.fromList([i, 0, 255, 255]),
};

/// Eine Zeile für ein Archiv mit [schema]: Spalten, die erst ein späteres
/// Schema hat (`runs.mode` ab 10), fehlen davor.
Map<String, Object?> _row(ArchiveSectionSpec s, int i, {int schema = 4}) => {
  for (final c in s.columns)
    if ((c.sinceSchema ?? 0) <= schema)
      c.name: c.name == s.key && s.keyIsText ? 'key$i' : _valueFor(c, i),
};

const _fromSchema7 = {'goals', 'plans', 'plan_units', 'active_warning'};

Map<String, List<Map<String, Object?>>> _fullDb({
  int rowsPer = 1,
  int schema = 4,
}) => {
  // `goals`, `plans` und `plan_units` gibt es erst ab Schema 7, Zeilen in
  // `active_warning` ab Schema 11; die Hilfsfunktionen schreiben Schema 4.
  for (final s in archiveSections)
    if (!s.isReserved && !_fromSchema7.contains(s.name))
      s.name: [for (var i = 1; i <= rowsPer; i++) _row(s, i, schema: schema)],
};

String _manifest({int schema = 4}) =>
    '{"type":"manifest","format":1,"schema_version":$schema,'
    '"created_at_us":1793000000000000}';

String _section(String name) => '{"type":"section","name":"$name"}';

String _rowLine(Map<String, Object?> data) => jsonEncode({
  'type': 'row',
  // BLOB-Werte stehen in der Datei als Hex-Text (Vertrag 4.2).
  'data': {
    for (final e in data.entries)
      e.key: e.value is Uint8List
          ? encodeArchiveBlob(e.value! as Uint8List)
          : e.value,
  },
});

String _endLine(Map<String, int> counts) =>
    jsonEncode({'type': 'end', 'rows': counts});

/// Gültige Zeilen für [db] im Format des Vertrags.
List<String> _validLines(Map<String, List<Map<String, Object?>>> db) => [
  _manifest(),
  for (final s in archiveSectionsFor(4)) ...[
    _section(s.name),
    for (final r in db[s.name] ?? const <Map<String, Object?>>[]) _rowLine(r),
  ],
  _endLine({
    for (final s in archiveSectionsFor(4)) s.name: db[s.name]?.length ?? 0,
  }),
];

Uint8List _jsonl(List<String> lines) =>
    Uint8List.fromList(utf8.encode('${lines.join('\n')}\n'));

Uint8List _gzip(List<int> plain) => Uint8List.fromList(gzip.encode(plain));

/// Die Hilfen bauen Format 1 (Kopf und Manifest); Format 2 steht in der Gruppe
/// "Formatversion 2".
Future<Uint8List> _encrypt(
  List<int> plain, {
  String pw = _password,
  int format = 1,
}) async {
  final b = BytesBuilder(copy: false);
  await for (final c in _fakeCipher(
    format: format,
  ).encrypt(pw, Stream.value(plain))) {
    b.add(c);
  }
  return b.takeBytes();
}

Future<Uint8List> _archive(List<String> lines) async =>
    _encrypt(_gzip(_jsonl(lines)));

class _Case {
  _Case(this.dir) : sink = FakeArchiveSink();

  final Directory dir;
  FakeArchiveSink sink;
  int _n = 0;

  String write(List<int> bytes) {
    final f = File('${dir.path}/a${_n++}.runarch')..writeAsBytesSync(bytes);
    return f.path;
  }

  Future<void> run(
    List<int> bytes, {
    ArchiveCipherFactory cipher = _fakeCipher,
    String password = _password,
    int batchRows = 500,
    ArchiveCancel? cancel,
  }) => ArchiveImporter(
    sink: sink,
    cipherFactory: cipher,
    clock: _clock,
    batchRows: batchRows,
  ).import(path: write(bytes), password: password, cancel: cancel);

  /// Erwartet [failure]: abort genau einmal, nie commit, keine Inhalte im Text.
  Future<void> rejects(
    List<int> bytes,
    ArchiveImportFailure failure, {
    ArchiveCipherFactory cipher = _fakeCipher,
    String password = _password,
    int commits = 0,
  }) async {
    Object? error;
    try {
      await run(bytes, cipher: cipher, password: password);
    } catch (e) {
      error = e;
    }
    expect(error, isA<ArchiveImportException>(), reason: 'kein Fehler');
    expect((error! as ArchiveImportException).failure, failure);
    expect(error.toString(), isNot(contains(password)));
    expect(sink.commits, commits, reason: 'commit trotz Fehler');
    expect(sink.aborts, 1);
    expect(sink.calls.first, 'begin');
    expect(sink.calls.last, 'abort');
  }

  Future<void> rejectsLines(
    List<String> lines,
    ArchiveImportFailure failure,
  ) async => rejects(await _archive(lines), failure);

  Future<void> rejectsIdentity(
    List<String> lines,
    ArchiveImportFailure failure,
  ) => rejects(_gzip(_jsonl(lines)), failure, cipher: _identity);
}

/// Heute für die Tests: 2026-11-20 (Ortstag, Versatz 0).
final Clock _clock = FakeClock(DateTime.utc(2026, 11, 20, 12));

void main() {
  late Directory dir;
  late _Case c;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp12c1_');
    c = _Case(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> valid([int rowsPer = 1]) =>
      _validLines(_fullDb(rowsPer: rowsPer));

  group('Verwerfendes Ziel (nur prüfen)', () {
    test('gültiges Archiv: vollständig gelesen, kein Fehler', () async {
      final bytes = await _archive(valid(3));
      await ArchiveImporter(
        sink: DiscardArchiveSink(),
        cipherFactory: _fakeCipher,
        clock: _clock,
      ).import(path: c.write(bytes), password: _password);
    });

    test('falsches Passwort scheitert trotzdem', () async {
      final bytes = await _archive(valid());
      await expectLater(
        ArchiveImporter(
          sink: DiscardArchiveSink(),
          cipherFactory: _fakeCipher,
          clock: _clock,
        ).import(path: c.write(bytes), password: 'ganz anderes Passwort'),
        throwsA(
          isA<ArchiveImportException>().having(
            (e) => e.failure,
            'failure',
            ArchiveImportFailure.wrongPasswordOrDamaged,
          ),
        ),
      );
    });

    test('Beschädigung erst am Ende (falscher Zähler) scheitert', () async {
      final lines = valid()..removeLast();
      lines.add(_endLine({for (final s in archiveSectionsFor(4)) s.name: 99}));
      await expectLater(
        ArchiveImporter(
          sink: DiscardArchiveSink(),
          cipherFactory: _fakeCipher,
          clock: _clock,
        ).import(path: c.write(await _archive(lines)), password: _password),
        throwsA(isA<ArchiveImportException>()),
      );
    });
  });

  group('Rundgang Export -> Leser', () {
    test('alle Zeilen gleich, commit genau einmal am Ende', () async {
      // Der Schreiber erzeugt das neueste Schema (mit `runs.mode`).
      final db = _fullDb(rowsPer: 3, schema: archiveSchemaVersion);
      db['settings']!.add({
        'key': 'values.calculationPending',
        'value': 'x',
        'updated_at_us': 1,
      });
      final handoff = FakeFileHandoff()..directory = dir.path;
      final file = await ArchiveExporter(
        source: FakeArchiveSource(db),
        handoff: handoff,
        clock: FakeClock(DateTime.utc(2026, 11, 7, 12)),
        cipherFactory: _fakeCipher,
      ).export(password: _password);

      await c.run(File(file.path!).readAsBytesSync(), batchRows: 2);

      final expected = {
        for (final e in db.entries)
          e.key: [
            for (final r in e.value)
              if (r['key'] != 'values.calculationPending') r,
          ],
      };
      expect(c.sink.rows, expected);
      expect(c.sink.calls.first, 'begin');
      expect(c.sink.calls.last, 'commit');
      expect(c.sink.commits, 1);
      expect(c.sink.aborts, 0);
      expect(c.sink.batchSizes.every((n) => n >= 1 && n <= 2), isTrue);
      // Abschnitte kommen in Vertragsreihenfolge, nie vermischt.
      final order = [
        for (final call in c.sink.calls)
          if (call.startsWith('insert:')) call.substring(7),
      ];
      final names = [
        for (final s in archiveSections)
          if (!s.isReserved && !_fromSchema7.contains(s.name)) s.name,
      ];
      expect([
        ...{...order},
      ], names);
      expect([
        for (var i = 0; i < order.length; i++)
          if (i == 0 || order[i] != order[i - 1]) order[i],
      ], names);
    });

    test('leere Datenbank: nur Gerüst, commit', () async {
      await c.run(await _archive(valid(0)));
      expect(c.sink.rows, isEmpty);
      expect(c.sink.calls, ['begin', 'commit']);
    });

    test('mehrere Stücke, Werte unverändert (Texte, Zahlen, NULL, JSON als Text)', () async {
      final rnd = Random(7);
      String noise() =>
          base64.encode(List.generate(150, (_) => rnd.nextInt(256)));
      final db = _fullDb(rowsPer: 0)
        ..['runs'] = [
          {
            'id': 1,
            'state': 'finished',
            'started_at_us': 9223372036854775807,
            'ended_at_us': null,
            'ended_utc_offset_s': -64800,
          },
        ]
        ..['rated_sections'] = [
          {
            for (final col in archiveSectionsFor(4)[10].columns)
              col.name: col.name == 'gps_gaps'
                  ? '[{"start_us":1,"end_us":2}]'
                  : _valueFor(col, 1),
          },
        ]
        ..['settings'] = [
          for (var i = 0; i < 4000; i++)
            {
              'key': 'k${i.toString().padLeft(5, '0')}',
              'value': noise(),
              'updated_at_us': i,
            },
          {'key': 'z', 'value': 'ä\u{1F3C3}"\\\n', 'updated_at_us': 5},
        ];
      final bytes = await _archive(_validLines(db));
      expect(
        bytes.length,
        greaterThan(36 + 3 * 65552),
        reason: 'Mehrstück-Datei',
      );
      await c.run(bytes);
      // Schema 4 kennt `runs.mode` nicht: Der Leser setzt `gps` (Vertrag 4.3).
      expect(c.sink.rows, {
        for (final e in db.entries)
          if (e.value.isNotEmpty)
            e.key: e.key == 'runs'
                ? [
                    for (final r in e.value) {...r, 'mode': 'gps'},
                  ]
                : e.value,
      });
      expect(c.sink.commits, 1);
    });

    test('große Datei: Zeilen kommen vor dem Ende, bei Schaden in einem '
        'späteren Stück trotzdem abort ohne commit', () async {
      final rnd = Random(3);
      final db = _fullDb(rowsPer: 0)
        ..['settings'] = [
          for (var i = 0; i < 4000; i++)
            {
              'key': 'k${i.toString().padLeft(5, '0')}',
              'value': base64.encode(
                List.generate(150, (_) => rnd.nextInt(256)),
              ),
              'updated_at_us': i,
            },
        ];
      final bytes = await _archive(_validLines(db));
      final chunks = (bytes.length - 36 + 65551) ~/ 65552;
      expect(chunks, greaterThan(3));

      final flipped = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
      await c.rejects(flipped, ArchiveImportFailure.damaged);
      expect(
        c.sink.calls.any((x) => x.startsWith('insert:')),
        isTrue,
        reason: 'frühere Stücke lieferten schon Zeilen',
      );

      c = _Case(dir);
      await c.rejects(
        bytes.sublist(0, 36 + 2 * 65552),
        ArchiveImportFailure.damaged,
      );
      c = _Case(dir);
      final first = Uint8List.fromList(bytes)..[40] ^= 1;
      await c.rejects(first, ArchiveImportFailure.wrongPasswordOrDamaged);
      expect(c.sink.calls, ['begin', 'abort']);
    });
  });

  group('commit nur nach gültigem Endstück und gültiger Endzeile', () {
    test('Endzeile gelesen, aber das letzte Stück scheitert: abort', () async {
      final gz = _gzip(_jsonl(valid(2)));
      await c.rejects(
        gz,
        ArchiveImportFailure.damaged,
        cipher: _identityFailAtEnd,
      );
      // Alle Zeilen und die Endzeile waren schon gelesen und eingefügt.
      expect(c.sink.rows['runs'], hasLength(2));
    });

    test('Strom und Endzeile in Ordnung: commit', () async {
      await c.run(_gzip(_jsonl(valid(2))), cipher: _identity);
      expect(c.sink.commits, 1);
      expect(c.sink.calls.last, 'commit');
    });

    test(
      'gültiger Inhalt, aber gzip-Ende fehlt (abgeschnitten): kein commit',
      () async {
        final gz = _gzip(_jsonl(valid(1)));
        await c.rejects(
          gz.sublist(0, gz.length - 8),
          ArchiveImportFailure.damaged,
          cipher: _identity,
        );
      },
    );
  });

  group('Kopf, Passwort, Rahmen', () {
    test('falsches Passwort: eine Meldung, nichts eingefügt', () async {
      await c.rejects(
        await _archive(valid()),
        ArchiveImportFailure.wrongPasswordOrDamaged,
        password: 'ganz anderes Passwort $_marker',
      );
      expect(c.sink.calls, ['begin', 'abort']);
    });

    test('keine Archivdatei, leere Datei, fremde Datei', () async {
      await c.rejects(Uint8List(0), ArchiveImportFailure.notAnArchive);
      c = _Case(dir);
      await c.rejects(
        utf8.encode('PK\u0003\u0004 nur ein Zip'),
        ArchiveImportFailure.notAnArchive,
      );
    });

    test('unbekannte Formatversion und Parameter', () async {
      final bytes = await _archive(valid());
      await c.rejects(
        Uint8List.fromList(bytes)..[9] = 3,
        ArchiveImportFailure.unsupportedVersion,
      );
      c = _Case(dir);
      await c.rejects(
        Uint8List.fromList(bytes)..[12] = 0x04,
        ArchiveImportFailure.unsupportedParameters,
      );
    });

    test('Datei fehlt: readFailed', () async {
      Object? error;
      try {
        await ArchiveImporter(
          sink: c.sink,
          cipherFactory: _fakeCipher,
          clock: _clock,
        ).import(path: '${dir.path}/gibt-es-nicht', password: _password);
      } catch (e) {
        error = e;
      }
      expect(
        error,
        isA<ArchiveImportException>().having(
          (e) => e.failure,
          'failure',
          ArchiveImportFailure.readFailed,
        ),
      );
      expect(c.sink.calls, ['begin', 'abort']);
    });
  });

  group('Manifest und Schema', () {
    test(
      'Schema größer als 12: neueres Archiv, auch mit fremden Schlüsseln',
      () async {
        final lines = valid()..[0] = _manifest(schema: 13);
        await c.rejectsLines(lines, ArchiveImportFailure.newerSchema);
        c = _Case(dir);
        lines[0] = '{"type":"manifest","format":1,"schema_version":13,"created_at_us":1,"neu":true}';
        await c.rejectsLines(lines, ArchiveImportFailure.newerSchema);
      },
    );

    test(
      'Format 1 mit Schema 4 (19 Abschnitte) bleibt lesbar, neuere leer',
      () async {
        expect(archiveSectionsFor(4), hasLength(19));
        await c.run(await _archive(valid()));
        expect(c.sink.commits, 1);
        expect(c.sink.rows['runs'], isNotEmpty);
        for (final t in [
          'run_feedback',
          'manual_trainings',
          'reference_performances',
          'rejected_suggestions',
        ]) {
          expect(c.sink.rows[t] ?? const [], isEmpty, reason: t);
        }
      },
    );

    test('Schema kleiner als 4: nicht unterstützt (keine Migration)', () async {
      await c.rejectsLines(
        valid()..[0] = _manifest(schema: 3),
        ArchiveImportFailure.unsupportedSchema,
      );
    });

    for (final entry in {
      'format 2':
          '{"type":"manifest","format":2,"schema_version":4,"created_at_us":1}',
      'Schema als Text': '{"type":"manifest","format":1,"schema_version":"4","created_at_us":1}',
      'Schema fehlt': '{"type":"manifest","format":1,"created_at_us":1}',
      'Erstellzeit fehlt': '{"type":"manifest","format":1,"schema_version":4}',
      'Erstellzeit Text': '{"type":"manifest","format":1,"schema_version":4,"created_at_us":"1"}',
      'fremder Schlüssel': '{"type":"manifest","format":1,"schema_version":4,"created_at_us":1,"x":1}',
    }.entries) {
      test('Manifest ungültig: ${entry.key}', () async {
        await c.rejectsLines(
          valid()..[0] = entry.value,
          ArchiveImportFailure.damaged,
        );
      });
    }

    test('Manifest nicht als erste Zeile / fehlt / doppelt', () async {
      final l = valid();
      await c.rejectsLines([...l.skip(1)], ArchiveImportFailure.damaged);
      c = _Case(dir);
      await c.rejectsLines([
        l[0],
        l[0],
        ...l.skip(1),
      ], ArchiveImportFailure.damaged);
      c = _Case(dir);
      await c.rejectsLines([
        l[1],
        l[0],
        ...l.skip(2),
      ], ArchiveImportFailure.damaged);
    });
  });

  group('Abschnitte', () {
    test('Abschnitt doppelt', () async {
      final l = valid();
      final i = l.indexOf(_section('laps'));
      await c.rejectsLines([
        ...l.take(i + 2),
        _section('laps'),
        ...l.skip(i + 2),
      ], ArchiveImportFailure.damaged);
    });

    test('Abschnitt fehlt (mit passenden Zählern)', () async {
      final l = valid(0);
      final i = l.indexOf(_section('laps'));
      final counts = {
        for (final s in archiveSectionsFor(4))
          if (s.name != 'laps') s.name: 0,
      };
      await c.rejectsLines([
        ...l.take(i),
        ...l.skip(i + 1).take(l.length - i - 2),
        _endLine(counts),
      ], ArchiveImportFailure.damaged);
    });

    test('letzter Abschnitt fehlt', () async {
      final l = valid(0);
      final counts = {
        for (final s in archiveSectionsFor(4))
          if (s.name != 'active_warning') s.name: 0,
      };
      await c.rejectsLines([
        ...l.take(l.length - 2),
        _endLine(counts),
      ], ArchiveImportFailure.damaged);
    });

    test('falsche Reihenfolge', () async {
      final l = valid(0);
      final a = l.indexOf(_section('laps'));
      final swapped = [...l];
      swapped[a] = _section('run_gaps');
      swapped[a + 1] = _section('laps');
      await c.rejectsLines(swapped, ArchiveImportFailure.damaged);
    });

    test('unbekannter Abschnitt und fremder Schlüssel im Kopf', () async {
      final l = valid(0);
      final a = l.indexOf(_section('goals'));
      await c.rejectsLines([
        ...l.take(a),
        _section('ziele'),
        ...l.skip(a + 1),
      ], ArchiveImportFailure.damaged);
      c = _Case(dir);
      await c.rejectsLines([
        ...l.take(a),
        '{"type":"section","name":"goals","x":1}',
        ...l.skip(a + 1),
      ], ArchiveImportFailure.damaged);
    });

    test('reservierter Abschnitt mit Zeile', () async {
      final l = valid(0);
      final a = l.indexOf(_section('goals'));
      for (final name in ['goals', 'plans', 'active_warning']) {
        c = _Case(dir);
        final i = l.indexOf(_section(name));
        await c.rejectsLines([
          ...l.take(i + 1),
          _rowLine({'id': 1}),
          ...l.skip(i + 1),
        ], ArchiveImportFailure.damaged);
      }
      expect(a, greaterThan(0));
    });

    test('Zeile vor dem ersten Abschnitt', () async {
      final l = valid(0);
      await c.rejectsLines([
        l[0],
        _rowLine(_row(archiveSectionsFor(4)[0], 1)),
        ...l.skip(1),
      ], ArchiveImportFailure.damaged);
    });
  });

  group('Zeilen und Spalten', () {
    List<String> withRunRow(Map<String, Object?> data) {
      final l = valid(0);
      return [...l.take(2), _rowLine(data), ...l.skip(2)];
    }

    Map<String, Object?> run() => _row(archiveSectionsFor(4)[0], 1);

    Future<void> counted(
      Map<String, Object?> data,
      ArchiveImportFailure f,
    ) async {
      // Mit richtigem Zähler, damit nur die Zeile selbst falsch ist.
      final l = withRunRow(data);
      l[l.length - 1] = _endLine({
        for (final s in archiveSectionsFor(4)) s.name: s.name == 'runs' ? 1 : 0,
      });
      await c.rejectsLines(l, f);
    }

    test(
      'gültige Zeile mit diesem Aufbau wird angenommen (Gegenprobe)',
      () async {
        final l = withRunRow(run());
        l[l.length - 1] = _endLine({
          for (final s in archiveSectionsFor(4))
            s.name: s.name == 'runs' ? 1 : 0,
        });
        await c.run(await _archive(l));
        expect(c.sink.rows['runs'], [
          {...run(), 'mode': 'gps'},
        ]);
      },
    );

    test('unbekannte Spalte', () async {
      await counted({...run(), 'extra': 1}, ArchiveImportFailure.damaged);
    });

    test('fehlende Spalte', () async {
      await counted({...run()}..remove('state'), ArchiveImportFailure.damaged);
    });

    test('Spalte umbenannt (gleiche Anzahl)', () async {
      final r = run();
      final v = r.remove('state');
      await counted({...r, 'zustand': v}, ArchiveImportFailure.damaged);
    });

    test('Typfehler: Text statt Zahl, Zahl statt Text, Bruch/Exponent bei '
        'Ganzzahl, NULL in Pflichtspalte, Boolean 2', () async {
      final bad = <Map<String, Object?>>[
        {...run(), 'id': '1'},
        {...run(), 'state': 5},
        {...run(), 'started_at_us': 1.5},
        {...run(), 'started_at_us': null},
        {...run(), 'state': null},
        {...run(), 'started_at_us': true},
      ];
      for (final d in bad) {
        c = _Case(dir);
        await counted(d, ArchiveImportFailure.damaged);
      }
    });

    test('Ganzzahl in anderer Schreibweise und zu groß', () async {
      for (final text in ['1.0', '1e2', '9223372036854775808', '1E400']) {
        c = _Case(dir);
        final l = withRunRow({});
        final json = _rowLine(run())
            .replaceFirst('"started_at_us":1', '"started_at_us":$text');
        expect(json, contains(text), reason: 'Ersetzung hat gegriffen');
        l[2] = json;
        l[l.length - 1] = _endLine({
          for (final s in archiveSectionsFor(4))
            s.name: s.name == 'runs' ? 1 : 0,
        });
        await c.rejectsLines(l, ArchiveImportFailure.damaged);
      }
    });

    test(
      'REAL: nicht endlich abgelehnt, Ganzzahlschreibweise erlaubt',
      () async {
        final lap = _row(archiveSectionsFor(4)[1], 1);
        String lapsRow(String time) =>
            _rowLine(lap)
                .replaceFirst('"lap_time_s":1.25', '"lap_time_s":$time');
        expect(lapsRow('3'), contains(':3'));
        List<String> build(String time) {
          final l = valid(0);
          final i = l.indexOf(_section('laps'));
          return [
            ...l.take(i + 1),
            lapsRow(time),
            ...l.skip(i + 1).take(l.length - i - 2),
            _endLine({
              for (final s in archiveSectionsFor(4))
                s.name: s.name == 'laps' ? 1 : 0,
            }),
          ];
        }

        await c.rejectsLines(build('1E400'), ArchiveImportFailure.damaged);
        c = _Case(dir);
        await c.run(await _archive(build('3')));
        expect(c.sink.rows['laps']!.single['lap_time_s'], 3);
      },
    );

    test(
      'einzelnes Surrogat im Text; Surrogatpaar als Escape ist gültig',
      () async {
        final l = withRunRow(run());
        l[l.length - 1] = _endLine({
          for (final s in archiveSectionsFor(4))
            s.name: s.name == 'runs' ? 1 : 0,
        });
        final lone = [...l]
          ..[2] = _rowLine(run()).replaceFirst('"s1"', r'"\ud800"');
        expect(lone[2], contains('ud800'));
        await c.rejectsLines(lone, ArchiveImportFailure.damaged);
        c = _Case(dir);
        final pair = [...l]
          ..[2] = _rowLine(run()).replaceFirst('"s1"', r'"🏃"');
        await c.run(await _archive(pair));
        expect(c.sink.rows['runs']!.single['state'], '\u{1F3C3}');
      },
    );

    test('doppelter Schlüssel in der Zeile', () async {
      final l = withRunRow({});
      l[2] = _rowLine(run()).replaceFirst('"id":1,', '"id":1,"id":1,');
      await c.rejectsLines(
        l
          ..[l.length - 1] = _endLine({
            for (final s in archiveSectionsFor(4))
              s.name: s.name == 'runs' ? 1 : 0,
          }),
        ArchiveImportFailure.damaged,
      );
    });

    test(
      'Zeile mit fremdem Schlüssel neben data / ohne data / data kein Objekt',
      () async {
        final counts = {
          for (final s in archiveSectionsFor(4))
            s.name: s.name == 'runs' ? 1 : 0,
        };
        for (final line in [
          '${_rowLine(run()).substring(0, _rowLine(run()).length - 1)},"x":1}',
          '{"type":"row"}',
          '{"type":"row","data":[1]}',
        ]) {
          c = _Case(dir);
          final l = withRunRow({});
          l[2] = line;
          l[l.length - 1] = _endLine(counts);
          await c.rejectsLines(l, ArchiveImportFailure.damaged);
        }
      },
    );

    test('Schlüssel nicht aufsteigend oder doppelt', () async {
      final l = valid(0);
      final counts = {
        for (final s in archiveSectionsFor(4)) s.name: s.name == 'runs' ? 2 : 0,
      };
      for (final ids in [
        [2, 1],
        [1, 1],
      ]) {
        c = _Case(dir);
        final rows = [
          for (final id in ids)
            _rowLine({..._row(archiveSectionsFor(4)[0], 1), 'id': id}),
        ];
        await c.rejectsLines([
          ...l.take(2),
          ...rows,
          ...l.skip(2).take(l.length - 3),
          _endLine(counts),
        ], ArchiveImportFailure.damaged);
      }
    });
  });

  group('Endzeile und Zähler', () {
    test('Zähler zu hoch / zu niedrig', () async {
      for (final delta in [1, -1]) {
        c = _Case(dir);
        final db = _fullDb(rowsPer: 2);
        final counts = {
          for (final s in archiveSectionsFor(4))
            s.name: db[s.name]?.length ?? 0,
        };
        counts['laps'] = counts['laps']! + delta;
        final l = _validLines(db);
        l[l.length - 1] = _endLine(counts);
        await c.rejectsLines(l, ArchiveImportFailure.damaged);
      }
    });

    test('Zähler fehlt / überzählig / Text statt Zahl', () async {
      final base = {for (final s in archiveSectionsFor(4)) s.name: 0};
      for (final counts in <Map<String, Object?>>[
        {...base}..remove('plans'),
        {...base, 'extra': 0},
        {...base, 'runs': '0'},
        {...base, 'runs': 0.0},
      ]) {
        c = _Case(dir);
        final l = valid(0);
        l[l.length - 1] = jsonEncode({'type': 'end', 'rows': counts});
        await c.rejectsLines(l, ArchiveImportFailure.damaged);
      }
    });

    test('Endzeile fehlt', () async {
      await c.rejectsLines(
        valid().sublist(0, valid().length - 1),
        ArchiveImportFailure.damaged,
      );
    });

    test(
      'Zeile nach der Endzeile (Zeile, Abschnitt, zweite Endzeile)',
      () async {
        final l = valid();
        for (final extra in [
          _rowLine(_row(archiveSectionsFor(4)[0], 9)),
          _section('runs'),
          l.last,
          _manifest(),
        ]) {
          c = _Case(dir);
          await c.rejectsLines([...l, extra], ArchiveImportFailure.damaged);
        }
      },
    );

    test('unbekannter type, type fehlt, Zeile kein Objekt', () async {
      for (final line in [
        '{"type":"foo"}',
        '{"x":1}',
        '[1]',
        '"x"',
        '5',
        'null',
      ]) {
        c = _Case(dir);
        final l = valid(0);
        await c.rejectsLines([
          ...l.take(2),
          line,
          ...l.skip(2),
        ], ArchiveImportFailure.damaged);
      }
    });
  });

  group('Zeilengrenzen und Text', () {
    test('letzte Zeile ohne Zeilenende', () async {
      final bytes = _jsonl(valid());
      await c.rejects(
        await _encrypt(_gzip(bytes.sublist(0, bytes.length - 1))),
        ArchiveImportFailure.damaged,
      );
    });

    test('leere Zeile', () async {
      final l = valid(0);
      await c.rejectsLines([
        ...l.take(2),
        '',
        ...l.skip(2),
      ], ArchiveImportFailure.damaged);
    });

    test('Zeilentrenner \\r\\n gilt nicht als Zeilenende der Spezifikation, '
        'bleibt aber gültiges JSON-Leerzeichen', () async {
      final b = utf8.encode('${valid(0).join('\r\n')}\r\n');
      // Zeilengrenze ist nur \n; \r ist Leerraum des JSON: Datei wird gelesen.
      await c.run(await _encrypt(_gzip(b)));
      expect(c.sink.commits, 1);
    });

    test('ungültiges UTF-8 und Byte-Order-Mark', () async {
      final good = _jsonl(valid(0));
      final bad = Uint8List.fromList([...good])..[20] = 0xFF;
      await c.rejects(await _encrypt(_gzip(bad)), ArchiveImportFailure.damaged);
      c = _Case(dir);
      await c.rejects(
        await _encrypt(_gzip([0xEF, 0xBB, 0xBF, ...good])),
        ArchiveImportFailure.damaged,
      );
    });

    test('JSON kaputt in der Mitte', () async {
      final l = valid(1);
      l[3] = l[3].substring(0, l[3].length - 3);
      await c.rejectsLines(l, ArchiveImportFailure.damaged);
    });

    test('Zeile länger als 16 MiB wird abgelehnt', () async {
      final l = valid(0);
      final i = l.indexOf(_section('settings'));
      String settingsRow(int n) =>
          _rowLine({'key': 'k', 'value': 'a' * n, 'updated_at_us': 1});
      List<String> build(int n) {
        return [
          ...l.take(i + 1),
          settingsRow(n),
          ...l.skip(i + 1).take(l.length - i - 2),
          _endLine({
            for (final s in archiveSectionsFor(4))
              s.name: s.name == 'settings' ? 1 : 0,
          }),
        ];
      }

      // Knapp unter der Grenze geht, knapp darüber nicht.
      final overhead = utf8.encode(settingsRow(0)).length;
      await c.run(
        _gzip(_jsonl(build(archiveMaxLineBytes - overhead))),
        cipher: _identity,
      );
      expect(c.sink.commits, 1);
      c = _Case(dir);
      await c.rejects(
        _gzip(_jsonl(build(archiveMaxLineBytes - overhead + 1))),
        ArchiveImportFailure.damaged,
        cipher: _identity,
      );
    });
  });

  group('gzip', () {
    test('kein gzip', () async {
      await c.rejects(
        await _encrypt(_jsonl(valid())),
        ArchiveImportFailure.damaged,
      );
    });

    test('Klartext leer (gültiger Rahmen, nichts darin)', () async {
      await c.rejects(
        await _encrypt(Uint8List(0)),
        ArchiveImportFailure.damaged,
      );
    });

    test('gzip beschädigt (Byte im Inhalt)', () async {
      final gz = _gzip(_jsonl(valid(3)));
      final bad = Uint8List.fromList(gz)..[gz.length ~/ 2] ^= 0x55;
      await c.rejects(await _encrypt(bad), ArchiveImportFailure.damaged);
    });

    test('CRC32 und ISIZE falsch', () async {
      final gz = _gzip(_jsonl(valid(1)));
      await c.rejects(
        await _encrypt(Uint8List.fromList(gz)..[gz.length - 6] ^= 1),
        ArchiveImportFailure.damaged,
      );
      c = _Case(dir);
      await c.rejects(
        await _encrypt(Uint8List.fromList(gz)..[gz.length - 2] ^= 1),
        ArchiveImportFailure.damaged,
      );
    });

    test('Kopffelder FNAME und FCOMMENT werden geduldet (Vertrag 4)', () async {
      final gz = _gzip(_jsonl(valid(2)));
      expect(gz[3], 0, reason: 'der Schreiber setzt keine Felder');
      final withFields = Uint8List.fromList([
        ...gz.sublist(0, 3),
        0x08 | 0x10, // FNAME | FCOMMENT
        ...gz.sublist(4, 10),
        ...utf8.encode('name.jsonl'), 0,
        ...utf8.encode('Kommentar'), 0,
        ...gz.sublist(10),
      ]);
      await c.run(await _encrypt(withFields));
    });

    test('abgeschnitten', () async {
      final gz = _gzip(_jsonl(valid(1)));
      for (final cut in [1, 8, 9, gz.length - 12]) {
        c = _Case(dir);
        await c.rejects(
          await _encrypt(gz.sublist(0, gz.length - cut)),
          ArchiveImportFailure.damaged,
        );
      }
    });

    test('Bytes nach dem Element, zweites Element', () async {
      final gz = _gzip(_jsonl(valid(1)));
      await c.rejects(await _encrypt([...gz, 0]), ArchiveImportFailure.damaged);
      c = _Case(dir);
      await c.rejects(
        await _encrypt([...gz, ...gz]),
        ArchiveImportFailure.damaged,
      );
      c = _Case(dir);
      // Zweites Element enthält die Endzeile erst: Aufteilung des Inhalts.
      final l = valid(1);
      final part1 = _gzip(_jsonl(l.take(l.length - 1).toList()));
      final part2 = _gzip(_jsonl([l.last]));
      await c.rejects(
        await _encrypt([...part1, ...part2]),
        ArchiveImportFailure.damaged,
      );
    });
  });

  group('Ziel, Abbruch', () {
    test(
      'Ziel lehnt eine Zeile ab: abort, kein commit, targetFailed',
      () async {
        c.sink.failAtInsert = 2;
        await c.rejects(
          await _archive(valid(1)),
          ArchiveImportFailure.targetFailed,
        );
      },
    );

    test('Ziel meldet Verletzung als beschädigt: damaged', () async {
      c.sink
        ..failAtInsert = 1
        ..failWith = const ArchiveImportException(ArchiveImportFailure.damaged);
      await c.rejects(await _archive(valid(1)), ArchiveImportFailure.damaged);
    });

    test('commit scheitert: abort, targetFailed', () async {
      c.sink.failCommit = true;
      await c.rejects(
        await _archive(valid(1)),
        ArchiveImportFailure.targetFailed,
        commits: 1,
      );
    });

    test(
      'Abbruch nach dem letzten Stapel, vor dem commit: kein commit',
      () async {
        final cancel = ArchiveCancel();
        c.sink.onInsert = (section) {
          if (section == 'known_devices') cancel.cancel();
        };
        Object? e;
        try {
          await c.run(await _archive(valid(1)), cancel: cancel);
        } catch (x) {
          e = x;
        }
        expect(e, isA<ArchiveImportException>());
        expect(
          (e! as ArchiveImportException).failure,
          ArchiveImportFailure.cancelled,
        );
        expect(c.sink.commits, 0);
        expect(c.sink.aborts, 1);
        expect(c.sink.calls.last, 'abort');
      },
    );

    test('Abbruch vor dem Start', () async {
      Object? e;
      final cancel = ArchiveCancel()..cancel();
      try {
        await c.run(await _archive(valid(1)), cancel: cancel);
      } catch (x) {
        e = x;
      }
      expect(e, isA<ArchiveImportException>());
      expect(
        (e! as ArchiveImportException).failure,
        ArchiveImportFailure.cancelled,
      );
      expect(c.sink.commits, 0);
      expect(c.sink.aborts, 1);
    });
  });

  group('Formatversion 2 (WP18): run_feedback, manual_trainings', () {
    const secret = 'GEHEIME-NOTIZ-4711';

    Map<String, Object?> fb({
      int run = 1,
      Object? rpe = 5,
      Object? wellbeing = 3,
      Object? points = 225.0,
      Object? seconds = 2700.0,
      Object? method = 'srpe_duration_rpe',
      Object? version = 1,
    }) => {
      'run_id': run,
      'rpe': rpe,
      'wellbeing': wellbeing,
      'complaints': secret,
      'warning_answer': 'no',
      'note': secret,
      'srpe_points': points,
      'srpe_duration_s': seconds,
      'srpe_method': method,
      'srpe_method_version': version,
    };

    Map<String, Object?> mt({
      int id = 1,
      Object? day = '2026-11-20',
      Object? kind = 'other',
      Object? duration = 2700,
      Object? rpe = 5,
    }) => {
      'id': id,
      'day': day,
      'kind': kind,
      'duration_s': duration,
      'rpe': rpe,
    };

    List<String> v2({
      List<Map<String, Object?>>? feedback,
      List<Map<String, Object?>>? trainings,
      String? manifest,
      int schema = 5,
      Map<String, List<Map<String, Object?>>> extra = const {},
    }) {
      final db = <String, List<Map<String, Object?>>>{
        'runs': [
          _row(archiveSections[0], 1, schema: schema),
          _row(archiveSections[0], 2, schema: schema),
        ],
        'run_feedback': feedback ?? [fb()],
        'manual_trainings': trainings ?? [mt()],
        ...extra,
      };
      final sections = archiveSectionsFor(schema);
      return [
        manifest ??
            '{"type":"manifest","format":2,"schema_version":$schema,'
                '"created_at_us":1793000000000000}',
        for (final sec in sections) ...[
          _section(sec.name),
          for (final r in db[sec.name] ?? const <Map<String, Object?>>[])
            _rowLine(r),
        ],
        _endLine({
          for (final sec in sections) sec.name: db[sec.name]?.length ?? 0,
        }),
      ];
    }

    Future<List<int>> file(List<String> lines, {int header = 2}) =>
        _encrypt(_gzip(_jsonl(lines)), format: header);

    Future<void> rejectsV2(
      List<String> lines, [
      ArchiveImportFailure f = ArchiveImportFailure.damaged,
      int header = 2,
    ]) async {
      await c.rejects(await file(lines, header: header), f);
      expect(c.sink.rows['run_feedback'] ?? const [], isNotNull);
      c = _Case(dir);
    }

    test('gültig, auch heute', () async {
      final lines = v2(
        feedback: [
          fb(),
          fb(
            run: 2,
            rpe: null,
            wellbeing: null,
            points: null,
            seconds: null,
            method: null,
            version: null,
          ),
        ],
        trainings: [
          mt(day: '2026-11-20'),
          mt(id: 2, kind: 'run', rpe: 0),
        ],
      );
      await c.run(await file(lines));
      expect(c.sink.rows['run_feedback'], hasLength(2));
      expect(c.sink.rows['manual_trainings']![0]['day'], '2026-11-20');
      expect(c.sink.commits, 1);
    });

    test('Nachgetragenes Training morgen: abgelehnt, nichts bleibt', () async {
      final lines = v2(
        trainings: [
          mt(day: '2026-11-20'),
          mt(id: 2, day: '2026-11-21'),
        ],
      );
      await rejectsV2(lines);
    });

    test('Grenze ist der Ortstag, nicht der UTC-Tag', () async {
      // 23:30 UTC, Versatz +2 h: Ortstag ist schon der 21.
      final late = FakeClock(
        DateTime.utc(2026, 11, 20, 23, 30),
        utcOffset: const Duration(hours: 2),
      );
      await ArchiveImporter(
        sink: c.sink,
        cipherFactory: _fakeCipher,
        clock: late,
      ).import(
        path: c.write(await file(v2(trainings: [mt(day: '2026-11-21')]))),
        password: _password,
      );
      expect(c.sink.commits, 1);
      c = _Case(dir);
      await expectLater(
        ArchiveImporter(
          sink: c.sink,
          cipherFactory: _fakeCipher,
          clock: late,
        ).import(
          path: c.write(await file(v2(trainings: [mt(day: '2026-11-22')]))),
          password: _password,
        ),
        throwsA(isA<ArchiveImportException>()),
      );
      expect(c.sink.commits, 0);
      expect(c.sink.aborts, 1);
    });

    test('Format 1 mit den neuen Abschnitten wird abgelehnt', () async {
      final lines = v2();
      lines[0] = _manifest();
      await rejectsV2(lines, ArchiveImportFailure.damaged, 1);
    });

    test('Format 2 ohne die neuen Abschnitte wird abgelehnt', () async {
      await rejectsV2(valid());
      c = _Case(dir);
      // Manifest 2/5, aber Abschnittsfolge von Format 1.
      final l = valid()..[0] = v2()[0];
      await rejectsV2(l);
    });

    for (final entry in {
      'Format 2 mit Schema 4': (
        '{"type":"manifest","format":2,"schema_version":4,"created_at_us":1}',
        2,
      ),
      'Format 1 mit Schema 5': (
        '{"type":"manifest","format":1,"schema_version":5,"created_at_us":1}',
        1,
      ),
      'Format 1 mit Schema 6': (
        '{"type":"manifest","format":1,"schema_version":6,"created_at_us":1}',
        1,
      ),
      'Format 3': (
        '{"type":"manifest","format":3,"schema_version":5,"created_at_us":1}',
        2,
      ),
      'Format 0': (
        '{"type":"manifest","format":0,"schema_version":5,"created_at_us":1}',
        2,
      ),
      'Manifest 1, Kopf 2': (
        '{"type":"manifest","format":1,"schema_version":4,"created_at_us":1}',
        2,
      ),
      'Manifest 2, Kopf 1': (
        '{"type":"manifest","format":2,"schema_version":5,"created_at_us":1}',
        1,
      ),
    }.entries) {
      test('Manifest/Kopf widersprüchlich: ${entry.key}', () async {
        final lines =
            entry.key.contains('Format 1') || entry.key == 'Manifest 1, Kopf 2'
            ? valid()
            : v2();
        lines[0] = entry.value.$1;
        await rejectsV2(lines, ArchiveImportFailure.damaged, entry.value.$2);
      });
    }

    // Nur das Format/Schema-Paar ist falsch: Kopf und Manifest stimmen
    // überein und der Inhalt passt zum Schema. Ohne die Paarprüfung im Leser
    // würde das Archiv gelesen.
    test(
      'Paar Format 2 mit Schema 4, Inhalt von Schema 4: beschädigt',
      () async {
        final l = valid()
          ..[0] =
              '{"type":"manifest","format":2,"schema_version":4,'
              '"created_at_us":1}';
        await rejectsV2(l, ArchiveImportFailure.damaged, 2);
      },
    );

    test(
      'Paar Format 1 mit Schema 5, Inhalt von Schema 5: beschädigt',
      () async {
        final l = v2()
          ..[0] =
              '{"type":"manifest","format":1,"schema_version":5,'
              '"created_at_us":1}';
        await rejectsV2(l, ArchiveImportFailure.damaged, 1);
      },
    );

    test('archiveSectionsFor: Schema außerhalb von 4 bis 12 wirft', () {
      for (final bad in [-1, 0, 1, 2, 3, 13, 100]) {
        expect(() => archiveSectionsFor(bad), throwsRangeError, reason: '$bad');
      }
      expect(archiveSectionsFor(4), hasLength(19));
      expect(archiveSectionsFor(6), hasLength(23));
      expect(archiveSectionsFor(7), hasLength(24));
      expect(archiveSectionsFor(8), hasLength(24));
      expect(archiveSectionsFor(9), hasLength(25));
      expect(archiveSectionsFor(10), hasLength(26));
      expect(archiveSectionsFor(10).last.name, 'treadmill_settings');
      expect(
        archiveSectionsFor(9).map((s) => s.name),
        isNot(contains('treadmill_settings')),
      );
      // `mode` steht erst ab Schema 10 im Abschnitt 1.
      expect(
        archiveSectionsFor(9).first.columns.map((c) => c.name),
        isNot(contains('mode')),
      );
      expect(archiveSectionsFor(10).first.columns.last.name, 'mode');
      expect(archiveSectionsFor(11), hasLength(26));
      expect(archiveSectionsFor(11).last.name, 'treadmill_settings');
      // Morgenmessung (WP33): Abschnitte 27 und 28 erst ab Schema 12.
      expect(archiveSectionsFor(12), hasLength(28));
      expect(archiveSectionsFor(12).map((s) => s.name).skip(26), [
        'morning_measurements',
        'morning_rr_packets',
      ]);
      expect(
        archiveSectionsFor(11).map((s) => s.name),
        isNot(contains('morning_measurements')),
      );
      // `active_warning` (21) ist bis Schema 10 reserviert, ab 11 mit Spalten.
      expect(
        archiveSectionsFor(10)
            .firstWhere((s) => s.name == 'active_warning')
            .isReserved,
        isTrue,
      );
      expect(
        archiveSectionsFor(11)
            .firstWhere((s) => s.name == 'active_warning')
            .columns,
        hasLength(4),
      );
      expect(
        archiveSectionsFor(8).map((s) => s.name),
        isNot(contains('raw_rr_packets')),
      );
      // `fixed` steht erst ab Schema 8 im Abschnitt 24.
      expect(
        archiveSectionsFor(7).last.columns.map((c) => c.name),
        isNot(contains('fixed')),
      );
      expect(archiveSectionsFor(8).last.columns.last.name, 'fixed');
    });

    test(
      'Abschnitt 19 goals: bis Schema 6 reserviert, ab Schema 7 mit Spalten',
      () {
        for (final schema in [4, 5, 6]) {
          final g = archiveSectionsFor(schema)
              .firstWhere((s) => s.name == 'goals');
          expect(g.isReserved, isTrue, reason: '$schema');
          expect(g.columns, isEmpty, reason: '$schema');
        }
        final g = archiveSectionsFor(7).firstWhere((s) => s.name == 'goals');
        expect(g.isReserved, isFalse);
        expect(g.columns, hasLength(12));
        // Reihenfolge der Abschnitte bleibt über die Schemata gleich.
        expect(archiveSectionsFor(7)[18].name, 'goals');
        expect(archiveSectionsFor(6)[18].name, 'goals');
      },
    );

    test(
      'Format 2 mit Schema 5 (21 Abschnitte, ohne Prognose) bleibt lesbar',
      () async {
        expect(archiveSectionsFor(5), hasLength(21));
        await c.run(await file(v2()));
        expect(c.sink.commits, 1);
        expect(c.sink.rows['run_feedback'], hasLength(1));
        expect(c.sink.rows['manual_trainings'], hasLength(1));
        expect(c.sink.rows['reference_performances'] ?? const [], isEmpty);
      },
    );

    test('Format 2 mit Schema 6: Prognose-Abschnitte mit Inhalt', () async {
      expect(archiveSectionsFor(6), hasLength(23));
      final refs = [
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
      ];
      await c.run(
        await file(
          v2(
            schema: 6,
            extra: {
              'reference_performances': refs,
              'rejected_suggestions': [
                {'id': 1, 'run_id': 2},
              ],
            },
          ),
        ),
      );
      expect(c.sink.commits, 1);
      expect(c.sink.rows['reference_performances'], hasLength(2));
      expect(c.sink.rows['reference_performances']![0]['time_s'], 3012.5);
      expect(c.sink.rows['reference_performances']![0]['run_id'], isNull);
      expect(c.sink.rows['rejected_suggestions']![0]['run_id'], 2);
      expect(c.sink.rows['run_feedback'], hasLength(1));
    });

    Map<String, Object?> goal({Object? runDays = 21}) => {
      'id': 1,
      'type': 'time',
      'distance': 'tenKilometers',
      'target_s': 3000.0,
      'target_date': '2027-03-20',
      'run_days': runDays,
      'max_session_s': 3600.0,
      'weekly_cap_s': 14400.0,
      'current_weekly_s': null,
      'can_run_30': 'yes',
      'hard_session': 1,
      'created_at_us': 7,
    };

    Map<String, Object?> plan() => {
      'id': 1,
      'goal_id': 1,
      'created_at_us': 8,
      'valid_from': '2026-11-09',
      'trigger': 'create',
      'reason': 'goalCreated',
      'method': 'plan-rules',
      'method_version': 1,
      'parameter_version': 1,
      'inputs': jsonEncode(
        PlanInputs(
          anchor: DateTime.utc(2026, 11, 9),
          startWeeklyMinutes: 90,
          today: DateTime.utc(2026, 11, 9),
        ).toJson(),
      ),
      'summary': '{"weeks":12}',
    };

    Map<String, Object?> unit(int id, {int? runId}) => {
      'id': id,
      'plan_id': 1,
      'day': '2026-11-${(id + 8).toString().padLeft(2, '0')}',
      'week': 0,
      'phase': 'entry',
      'kind': 'walkRun',
      'minutes': 30,
      'structure': '[{"kind":"walk","minutes":5,"seconds":300}]',
      'run_id': runId,
      'pinned': 0,
    };

    test('Format 2 mit Schema 7: Ziel in Abschnitt 19', () async {
      await c.run(
        await file(
          v2(
            schema: 7,
            extra: {
              'goals': [goal()],
            },
          ),
        ),
      );
      expect(c.sink.commits, 1);
      expect(c.sink.rows['goals'], [goal()]);
      expect(c.sink.rows['run_feedback'], hasLength(1));
    });

    test('Format 2 mit Schema 7 ohne Ziel (0 Zeilen) ist gültig', () async {
      await c.run(await file(v2(schema: 7)));
      expect(c.sink.commits, 1);
      expect(c.sink.rows['goals'] ?? const [], isEmpty);
    });

    test('Ziel mit falschem Typ oder fehlender Spalte: beschädigt', () async {
      await rejectsV2(
        v2(
          schema: 7,
          extra: {
            'goals': [goal(runDays: '21')],
          },
        ),
      );
      await rejectsV2(
        v2(
          schema: 7,
          extra: {
            'goals': [goal()..remove('hard_session')],
          },
        ),
      );
      await rejectsV2(
        v2(
          schema: 7,
          extra: {
            'goals': [goal()..['can_run_30'] = null],
          },
        ),
      );
    });

    test(
      'Ziel in Schema 6 oder 5 (reservierter Abschnitt): beschädigt',
      () async {
        for (final schema in [5, 6]) {
          final l = v2(schema: schema);
          final at = l.indexOf(_section('goals'));
          l.insert(at + 1, _rowLine(goal()));
          // Zähler der Endzeile angepasst, damit nur die Zeile selbst stört.
          l[l.length - 1] = _endLine({
            for (final sec in archiveSectionsFor(schema))
              sec.name: switch (sec.name) {
                'runs' => 2,
                'run_feedback' || 'manual_trainings' || 'goals' => 1,
                _ => 0,
              },
          });
          await rejectsV2(l);
        }
      },
    );

    test(
      'Plan-Zeile in Schema 5 oder 6 (reservierter Abschnitt 20): beschädigt',
      () async {
        for (final schema in [5, 6]) {
          final l = v2(schema: schema);
          final at = l.indexOf(_section('plans'));
          l.insert(at + 1, _rowLine(plan()));
          // Zähler der Endzeile stimmt, damit nur die Reservierung stört.
          l[l.length - 1] = _endLine({
            for (final sec in archiveSectionsFor(schema))
              sec.name: switch (sec.name) {
                'runs' => 2,
                'run_feedback' || 'manual_trainings' || 'plans' => 1,
                _ => 0,
              },
          });
          await rejectsV2(l);
        }
      },
    );

    test('Schema 7: Plan und Einheiten (Abschnitte 20 und 24)', () async {
      await c.run(
        await file(
          v2(
            schema: 7,
            extra: {
              'goals': [goal()],
              'plans': [plan()],
              'plan_units': [unit(1), unit(2, runId: 1)],
            },
          ),
        ),
      );
      expect(c.sink.commits, 1);
      expect(c.sink.rows['plans'], [plan()]);
      // Schema 7 kennt `fixed` nicht: Der Leser setzt 'none' (Schema 8).
      expect(c.sink.rows['plan_units'], [
        unit(1)..['fixed'] = 'none',
        unit(2, runId: 1)..['fixed'] = 'none',
      ]);
    });

    test(
      'Schema 8: plan_units mit fixed (none, day, kind) unverändert',
      () async {
        final units = [
          unit(1)..['fixed'] = 'none',
          unit(2)
            ..['kind'] = 'rest'
            ..['pinned'] = 1
            ..['fixed'] = 'day',
          unit(3)
            ..['kind'] = 'tempo'
            ..['pinned'] = 1
            ..['fixed'] = 'kind',
        ];
        await c.run(
          await file(
            v2(
              schema: 8,
              extra: {
                'goals': [goal()],
                'plans': [plan()],
                'plan_units': units,
              },
            ),
          ),
        );
        expect(c.sink.commits, 1);
        expect(c.sink.rows['plan_units'], units);
      },
    );

    Map<String, Object?> rrRow(int id, Object? rr) => {
      'id': id,
      'run_id': 1,
      'time_us': id,
      'source': 'ble',
      'rr': rr,
    };

    Map<String, Object?> warn({
      Object? id = 1,
      Object? day = '2026-11-18',
      Object? source = 'run_feedback',
      Object? run = 7,
    }) => {'id': id, 'reported_on': day, 'source': source, 'run_id': run};

    test('Schema 11: active_warning trägt eine Zeile (Abschnitt 21)', () async {
      await c.run(
        await file(
          v2(
            schema: 11,
            extra: {
              'active_warning': [warn()],
            },
          ),
        ),
      );
      expect(c.sink.commits, 1);
      expect(c.sink.rows['active_warning'], [warn()]);
      // Ohne Lauf (leer) und ohne Zeile sind gültig.
      c = _Case(dir);
      await c.run(
        await file(
          v2(
            schema: 11,
            extra: {
              'active_warning': [warn(run: null)],
            },
          ),
        ),
      );
      expect(c.sink.rows['active_warning'], [warn(run: null)]);
      c = _Case(dir);
      await c.run(await file(v2(schema: 11)));
      expect(c.sink.commits, 1);
    });

    test(
      'active_warning: Zeile in Schema 10 (Abschnitt 21 reserviert), zweite '
      'Zeile, falsche id, kein Kalendertag, falscher Typ: beschädigt',
      () async {
        await rejectsV2(
          v2(
            schema: 10,
            extra: {
              'active_warning': [warn()],
            },
          ),
        );
        for (final bad in <List<Map<String, Object?>>>[
          [warn(), warn(id: 2)],
          [warn(), warn()],
          [warn(id: 2)],
          [warn(day: '2026-02-30')],
          [warn(day: '18.11.2026')],
          [warn(day: 20261118)],
          [warn(source: null)],
          [warn(run: '7')],
        ]) {
          await rejectsV2(v2(schema: 11, extra: {'active_warning': bad}));
        }
      },
    );

    test('Schema 9: raw_rr_packets, BLOB bitgleich (0, 65535)', () async {
      final bytes = Uint8List.fromList([0, 0, 255, 255, 0, 4]);
      await c.run(
        await file(
          v2(
            schema: 9,
            extra: {
              'raw_rr_packets': [rrRow(1, bytes), rrRow(2, Uint8List(2))],
            },
          ),
        ),
      );
      expect(c.sink.commits, 1);
      final rows = c.sink.rows['raw_rr_packets']!;
      expect(rows, hasLength(2));
      expect(rows[0]['rr'], isA<Uint8List>());
      expect(rows[0]['rr'], bytes);
      expect(rows[1]['rr'], [0, 0]);
    });

    test(
      'raw_rr_packets: kein Hex-Text, Großschreibung, ungerade Länge, '
      'NULL, Zahl, Liste: beschädigt; in Schema 8 gibt es den Abschnitt nicht',
      () async {
        for (final bad in <Object?>[
          '0g00',
          '00FF',
          '000',
          null,
          5,
          [0, 1],
        ]) {
          await rejectsV2(
            v2(
              schema: 9,
              extra: {
                'raw_rr_packets': [rrRow(1, bad)],
              },
            ),
          );
        }
        final l = v2(schema: 8);
        l.insert(l.length - 1, _section('raw_rr_packets'));
        await rejectsV2(l);
      },
    );

    Map<String, Object?> tmRow(
      int id, {
      Object? incline = 1.5,
      Object? speed = 2.5,
    }) => {
      'id': id,
      'run_id': 1,
      'offset_us': id * 1000000,
      'speed_mps': speed,
      'incline_percent': incline,
    };

    test(
      'Schema 10: mode und treadmill_settings, Steigung unbekannt (null)',
      () async {
        final runs = [
          _row(archiveSections[0], 1, schema: 10)..['mode'] = 'gps',
          _row(archiveSections[0], 2, schema: 10)..['mode'] = 'treadmill',
        ];
        await c.run(
          await file(
            v2(
              schema: 10,
              extra: {
                'runs': runs,
                'treadmill_settings': [
                  tmRow(1),
                  tmRow(2, incline: null),
                  tmRow(3, speed: 0),
                ],
              },
            ),
          ),
        );
        expect(c.sink.commits, 1);
        expect(
          [for (final r in c.sink.rows['runs']!) r['mode']],
          ['gps', 'treadmill'],
        );
        final t = c.sink.rows['treadmill_settings']!;
        expect(t, hasLength(3));
        expect(t[0]['incline_percent'], 1.5);
        expect(t[1]['incline_percent'], isNull);
        expect(t[2]['speed_mps'], 0);
      },
    );

    test(
      'Schema 9: runs ohne mode lesen sich mit gps, Abschnitt 26 gibt es nicht',
      () async {
        await c.run(await file(v2(schema: 9)));
        expect(c.sink.commits, 1);
        expect({for (final r in c.sink.rows['runs']!) r['mode']}, {'gps'});
        expect(c.sink.rows['treadmill_settings'] ?? const [], isEmpty);
        c = _Case(dir);
        final l = v2(schema: 9);
        l.insert(l.length - 1, _section('treadmill_settings'));
        await rejectsV2(l);
      },
    );

    test('Schema 12: Morgenmessungen (27) und Gurt-RR (28) kommen an; BLOB nur als Hex', () async {
      Map<String, Object?> mm(int id, {Object? ibi = '00608944'}) => {
        'id': id,
        'measured_at_us': 5000 + id,
        'utc_offset_s': -12600,
        'posture': 'lying',
        'device_manufacturer': 'Testhersteller',
        'device_model': 'Testmodell',
        'method': 'camera-ppg',
        'method_version': 1,
        'quality': 'good',
        'resting_hr_bpm': 52.3,
        'rmssd_ms': null,
        'timing_noise_ms': null,
        'sleep_band': null,
        'before_validation': 1,
        'outside_window': 0,
        'camera_ibi': ibi,
      };
      Map<String, Object?> rr(int id, {Object? hex = '0004ffff'}) => {
        'id': id,
        'measurement_id': 1,
        'time_us': 5000 + id,
        'source': 'ble',
        'rr': hex,
      };
      await c.run(
        await file(
          v2(
            schema: 12,
            extra: {
              'morning_measurements': [mm(1), mm(2, ibi: '')],
              'morning_rr_packets': [rr(1), rr(2)],
            },
          ),
        ),
      );
      expect(c.sink.commits, 1);
      final m = c.sink.rows['morning_measurements']!;
      expect(m, hasLength(2));
      expect(m[0]['camera_ibi'], [0x00, 0x60, 0x89, 0x44]);
      expect(m[1]['camera_ibi'], isEmpty);
      expect(c.sink.rows['morning_rr_packets'], hasLength(2));
      // Schema 11 hat die Abschnitte nicht (leer), ein Abschnitt darin ist beschädigt.
      c = _Case(dir);
      await c.run(await file(v2(schema: 11)));
      expect(c.sink.rows['morning_measurements'] ?? const [], isEmpty);
      expect(c.sink.rows['morning_rr_packets'] ?? const [], isEmpty);
      c = _Case(dir);
      final l = v2(schema: 11);
      l.insert(l.length - 1, _section('morning_measurements'));
      await rejectsV2(l);
      // BLOB: Großbuchstaben, ungerade Länge, Nicht-Text, null und falscher Typ der Spalten.
      for (final bad in <Map<String, Object?>>[
        mm(1, ibi: '0060894G'),
        mm(1, ibi: 'AB'),
        mm(1, ibi: '006'),
        mm(1, ibi: null),
        mm(1, ibi: [0, 96]),
        mm(1)..['resting_hr_bpm'] = 'schnell',
        mm(1)..['before_validation'] = 'ja',
        mm(1)..remove('device_model'),
        mm(1)..['extra'] = 1,
      ]) {
        await rejectsV2(
          v2(
            schema: 12,
            extra: {
              'morning_measurements': [bad],
            },
          ),
        );
      }
      for (final bad in <Map<String, Object?>>[
        rr(1, hex: 'ABCD'),
        rr(1, hex: '000'),
        rr(1, hex: null),
        rr(1)..['measurement_id'] = 'x',
      ]) {
        await rejectsV2(
          v2(
            schema: 12,
            extra: {
              'morning_rr_packets': [bad],
            },
          ),
        );
      }
    });

    test('mode: Schema 9 mit mode oder Schema 10 ohne mode sowie falscher Typ in treadmill_settings: beschädigt', () async {
      await rejectsV2(
        v2(
          schema: 9,
          extra: {
            'runs': [_row(archiveSections[0], 1, schema: 10)],
          },
        ),
      );
      await rejectsV2(
        v2(
          schema: 10,
          extra: {
            'runs': [_row(archiveSections[0], 1, schema: 9)],
          },
        ),
      );
      for (final bad in <Map<String, Object?>>[
        tmRow(1, speed: 'schnell'),
        tmRow(1, speed: null),
        tmRow(1, incline: 'steil'),
        tmRow(1)..remove('offset_us'),
        tmRow(1)..['extra'] = 1,
      ]) {
        await rejectsV2(
          v2(
            schema: 10,
            extra: {
              'treadmill_settings': [bad],
            },
          ),
        );
      }
    });

    test(
      'fixed fehlt in Schema 8 oder steht in Schema 7: beschädigt',
      () async {
        await rejectsV2(
          v2(
            schema: 8,
            extra: {
              'goals': [goal()],
              'plans': [plan()],
              'plan_units': [unit(1)],
            },
          ),
        );
        await rejectsV2(
          v2(
            schema: 7,
            extra: {
              'goals': [goal()],
              'plans': [plan()],
              'plan_units': [unit(1)..['fixed'] = 'none'],
            },
          ),
        );
        await rejectsV2(
          v2(
            schema: 8,
            extra: {
              'goals': [goal()],
              'plans': [plan()],
              'plan_units': [unit(1)..['fixed'] = 1],
            },
          ),
        );
      },
    );

    test(
      'Schema 7: vollständige und leere Zielintensität sind gültig',
      () async {
        final full =
            '[{"kind":"easy","minutes":5,"seconds":300,"intensity":{'
            '"rpeMin":3,"rpeMax":4,"paceFast":330,"paceSlow":360.5,"basis":"x",'
            '"hrMin":120,"hrMax":140,"estimated":true,"maxHrEstimated":false,'
            '"paceIsLimit":false}},'
            '{"kind":"walk","minutes":0,"intensity":{"rpeMin":null}}]';
        await c.run(
          await file(
            v2(
              schema: 7,
              extra: {
                'goals': [goal()],
                'plans': [plan()],
                'plan_units': [unit(1)..['structure'] = full],
              },
            ),
          ),
        );
        expect(c.sink.commits, 1);
      },
    );

    test('Schema 7 ohne Plan (0 Zeilen) ist gültig', () async {
      await c.run(await file(v2(schema: 7)));
      expect(c.sink.commits, 1);
      expect(c.sink.rows['plans'] ?? const [], isEmpty);
      expect(c.sink.rows['plan_units'] ?? const [], isEmpty);
    });

    test('Abschnitt plan_units gehört nur zu Schema 7', () async {
      expect(archiveSectionsFor(7).map((s) => s.name).last, 'plan_units');
      expect(archiveSectionsFor(7), hasLength(24));
      expect(archiveSectionsFor(6), hasLength(23));
      final l = v2(schema: 6);
      l.insert(l.length - 1, _section('plan_units'));
      await rejectsV2(l);
    });

    test(
      'Plan: JSON ungültig, Tag ungültig, falscher Typ: beschädigt',
      () async {
        Future<void> badPlan(Map<String, Object?> p) => rejectsV2(
          v2(
            schema: 7,
            extra: {
              'goals': [goal()],
              'plans': [p],
            },
          ),
        );
        await badPlan(plan()..['inputs'] = '{kaputt');
        await badPlan(plan()..['summary'] = '');
        // Gültiges JSON, aber nicht die Form von PlanInputs/Zusammenfassung:
        // sonst scheiterte jede spätere Neuberechnung dauerhaft.
        await badPlan(plan()..['inputs'] = '{}');
        await badPlan(plan()..['inputs'] = '[]');
        await badPlan(plan()..['inputs'] = '{"inputsVersion":2}');
        await badPlan(plan()..['summary'] = '[]');
        await badPlan(plan()..['valid_from'] = '2026-02-30');
        await badPlan(plan()..['valid_from'] = '9.11.2026');
        await badPlan(plan()..['method_version'] = '1');
        await badPlan(plan()..remove('reason'));
      },
    );

    test(
      'Plan-Einheit: JSON, Tag, Zahlen, run_id-Typ, id: beschädigt',
      () async {
        Future<void> bad(List<Map<String, Object?>> units) => rejectsV2(
          v2(
            schema: 7,
            extra: {
              'goals': [goal()],
              'plans': [plan()],
              'plan_units': units,
            },
          ),
        );
        await bad([unit(1)..['structure'] = '[{']);
        await bad([unit(1)..['structure'] = '{}']);
        await bad([unit(1)..['structure'] = '[1]']);
        await bad([unit(1)..['structure'] = '[{"kind":"x","minutes":5}]']);
        await bad([unit(1)..['structure'] = '[{"kind":"walk","minutes":"5"}]']);
        await bad([unit(1)..['structure'] = '[{"kind":"walk","minutes":-1}]']);
        await bad([
          unit(1)..['structure'] = '[{"kind":"walk","minutes":5,"seconds":-1}]',
        ]);
        for (final f in [
          '"rpeMin":"x"',
          '"rpeMax":1.5',
          '"paceFast":"5"',
          '"paceSlow":true',
          '"basis":3',
          '"hrMin":"1"',
          '"hrMax":2.5',
          '"estimated":"yes"',
          '"maxHrEstimated":1',
          '"paceIsLimit":"no"',
        ]) {
          await bad([
            unit(
              1,
            )..['structure'] = '[{"kind":"walk","minutes":5,"intensity":{$f}}]',
          ]);
        }
        await bad([unit(1)..['day'] = '2026-13-01']);
        await bad([unit(1)..['day'] = '2026-11-9']);
        await bad([unit(1)..['week'] = -1]);
        await bad([unit(1)..['minutes'] = -5]);
        await bad([unit(1)..['pinned'] = 2]);
        await bad([unit(1)..['run_id'] = '1']);
        await bad([unit(2), unit(1)]);
        await bad([unit(1), unit(1)]);
      },
    );

    test('Schema 6 ohne die Prognose-Abschnitte: beschädigt', () async {
      final l = v2();
      l[0] = v2(schema: 6)[0];
      await rejectsV2(l);
    });

    test('Schema 5 mit Prognose-Abschnitt: beschädigt', () async {
      final l = v2();
      final at = l.indexOf(_section('goals'));
      l.insert(at, _section('reference_performances'));
      await rejectsV2(l);
    });

    test('Schema 4 mit Abschnitt aus Schema 6: beschädigt', () async {
      final l = valid();
      final at = l.indexOf(_section('goals'));
      l.insert(at, _section('reference_performances'));
      await c.rejectsLines(l, ArchiveImportFailure.damaged);
    });

    test('Schema 13: neueres Archiv', () async {
      await rejectsV2(
        v2(schema: 8)..[0] = '{"type":"manifest","format":2,"schema_version":13,"created_at_us":1}',
        ArchiveImportFailure.newerSchema,
      );
    });

    test('Kopf Format 3 oder 0: unbekannte Formatversion', () async {
      final bytes = await file(v2());
      for (final v in [0, 3]) {
        await c.rejects(
          Uint8List.fromList(bytes)..[9] = v,
          ArchiveImportFailure.unsupportedVersion,
        );
        c = _Case(dir);
      }
    });

    final bad = <String, List<String>>{
      'RPE 11': v2(feedback: [fb(rpe: 11)]),
      'RPE -1': v2(feedback: [fb(rpe: -1)]),
      'RPE 5.5': v2(feedback: [fb(rpe: 5.5)]),
      'Befinden 0': v2(feedback: [fb(wellbeing: 0)]),
      'Befinden 6': v2(feedback: [fb(wellbeing: 6)]),
      'Befinden 4.5': v2(feedback: [fb(wellbeing: 4.5)]),
      'sRPE-Wert passt nicht zu Dauer mal RPE': v2(
        feedback: [fb(points: 226.0)],
      ),
      'sRPE ohne RPE': v2(feedback: [fb(rpe: null)]),
      'sRPE-Dauer ohne Punkte': v2(feedback: [fb(points: null)]),
      // Diese Fälle erreichen ohne die Spaltenregel keinen TypeError: nur die
      // Regel selbst erkennt sie (sonst bliebe der DB-CHECK als Umweg).
      'sRPE fremde Methode ohne RPE': v2(
        feedback: [fb(rpe: null, method: 'andere', version: 0)],
      ),
      'sRPE nur Punkte und Dauer, Methode fehlt': v2(
        feedback: [fb(method: null, version: null)],
      ),
      'sRPE nur Methode und Version, Werte fehlen': v2(
        feedback: [fb(points: null, seconds: null)],
      ),
      'sRPE Version fehlt': v2(feedback: [fb(version: null)]),
      'sRPE Methode fehlt, fremde Version': v2(
        feedback: [fb(method: null, version: 0)],
      ),
      'doppelte run_id': v2(feedback: [fb(), fb()]),
      'absteigende run_id': v2(feedback: [fb(run: 2), fb(run: 1)]),
      'Training RPE 11': v2(trainings: [mt(rpe: 11)]),
      'Training RPE fehlt': v2(trainings: [mt(rpe: null)]),
      'Training Dauer 0': v2(trainings: [mt(duration: 0)]),
      'Training Dauer -1': v2(trainings: [mt(duration: -1)]),
      'Training Dauer 1.5': v2(trainings: [mt(duration: 1.5)]),
      'doppelte Training-id': v2(trainings: [mt(), mt()]),
    };
    for (final e in bad.entries) {
      test('Leser lehnt ab: ${e.key}', () async {
        await rejectsV2(e.value);
      });
    }

    test('ältere sRPE-Methode wird nicht nachgerechnet', () async {
      await c.run(await file(v2(feedback: [fb(points: 1.0, version: 0)])));
      expect(c.sink.commits, 1);
    });

    test('Fehlertexte nennen keine Inhalte', () async {
      Object? error;
      try {
        await c.run(await file(v2(feedback: [fb(rpe: 11)])));
      } catch (e) {
        error = e;
      }
      expect(error.toString(), isNot(contains(secret)));
      expect(error.toString(), 'ArchiveImportException(damaged)');
    });

    test('Rundgang: Export schreibt Format 2 mit beiden Abschnitten', () async {
      final db = _fullDb(rowsPer: 2, schema: archiveSchemaVersion);
      db['run_feedback'] = [fb(), fb(run: 2)];
      db['manual_trainings'] = [mt(), mt(id: 2)];
      final handoff = FakeFileHandoff()..directory = dir.path;
      final out = await ArchiveExporter(
        source: FakeArchiveSource(db),
        handoff: handoff,
        clock: FakeClock(DateTime.utc(2026, 11, 7, 12)),
        cipherFactory: _fakeCipher,
      ).export(password: _password);
      final bytes = File(out.path!).readAsBytesSync();
      expect(bytes[9], 2);
      await c.run(bytes);
      expect(c.sink.rows['run_feedback'], db['run_feedback']);
      expect(c.sink.rows['manual_trainings'], db['manual_trainings']);
    });
  });
}
