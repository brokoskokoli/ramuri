import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

const String _password = 'synthetisches Testpasswort';
const String _marker = 'SYNTHETISCHE-MARKE-4711';

ArchiveCipher _fakeCipher() => FramedArchiveCipher(
  kdf: FakeArchiveKdf(),
  aead: FakeChunkAead(),
  randomBytes: (n) => Uint8List(n),
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
};

Map<String, Object?> _row(ArchiveSectionSpec s, int i) => {
  for (final c in s.columns)
    c.name: c.name == s.key && s.keyIsText ? 'key$i' : _valueFor(c, i),
};

Map<String, List<Map<String, Object?>>> _fullDb({int rowsPer = 1}) => {
  for (final s in archiveSections)
    if (!s.isReserved) s.name: [for (var i = 1; i <= rowsPer; i++) _row(s, i)],
};

String _manifest({int schema = 4}) =>
    '{"type":"manifest","format":1,"schema_version":$schema,'
    '"created_at_us":1793000000000000}';

String _section(String name) => '{"type":"section","name":"$name"}';

String _rowLine(Map<String, Object?> data) =>
    jsonEncode({'type': 'row', 'data': data});

String _endLine(Map<String, int> counts) =>
    jsonEncode({'type': 'end', 'rows': counts});

/// Gültige Zeilen für [db] im Format des Vertrags.
List<String> _validLines(Map<String, List<Map<String, Object?>>> db) => [
  _manifest(),
  for (final s in archiveSections) ...[
    _section(s.name),
    for (final r in db[s.name] ?? const <Map<String, Object?>>[]) _rowLine(r),
  ],
  _endLine({for (final s in archiveSections) s.name: db[s.name]?.length ?? 0}),
];

Uint8List _jsonl(List<String> lines) =>
    Uint8List.fromList(utf8.encode('${lines.join('\n')}\n'));

Uint8List _gzip(List<int> plain) => Uint8List.fromList(gzip.encode(plain));

Future<Uint8List> _encrypt(List<int> plain, {String pw = _password}) async {
  final b = BytesBuilder(copy: false);
  await for (final c in _fakeCipher().encrypt(pw, Stream.value(plain))) {
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

  group('Rundgang Export -> Leser', () {
    test('alle Zeilen gleich, commit genau einmal am Ende', () async {
      final db = _fullDb(rowsPer: 3);
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
          if (!s.isReserved) s.name,
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

    test(
      'mehrere Stücke, Werte unverändert (Texte, Zahlen, NULL, JSON als Text)',
      () async {
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
              for (final col in archiveSections[10].columns)
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
        expect(c.sink.rows, {
          for (final e in db.entries)
            if (e.value.isNotEmpty) e.key: e.value,
        });
        expect(c.sink.commits, 1);
      },
    );

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
        Uint8List.fromList(bytes)..[9] = 2,
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
      'Schema größer als 4: neueres Archiv, auch mit fremden Schlüsseln',
      () async {
        final lines = valid()..[0] = _manifest(schema: 5);
        await c.rejectsLines(lines, ArchiveImportFailure.newerSchema);
        c = _Case(dir);
        lines[0] = '{"type":"manifest","format":1,"schema_version":9,"created_at_us":1,"neu":true}';
        await c.rejectsLines(lines, ArchiveImportFailure.newerSchema);
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
        for (final s in archiveSections)
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
        for (final s in archiveSections)
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
        _rowLine(_row(archiveSections[0], 1)),
        ...l.skip(1),
      ], ArchiveImportFailure.damaged);
    });
  });

  group('Zeilen und Spalten', () {
    List<String> withRunRow(Map<String, Object?> data) {
      final l = valid(0);
      return [...l.take(2), _rowLine(data), ...l.skip(2)];
    }

    Map<String, Object?> run() => _row(archiveSections[0], 1);

    Future<void> counted(
      Map<String, Object?> data,
      ArchiveImportFailure f,
    ) async {
      // Mit richtigem Zähler, damit nur die Zeile selbst falsch ist.
      final l = withRunRow(data);
      l[l.length - 1] = _endLine({
        for (final s in archiveSections) s.name: s.name == 'runs' ? 1 : 0,
      });
      await c.rejectsLines(l, f);
    }

    test(
      'gültige Zeile mit diesem Aufbau wird angenommen (Gegenprobe)',
      () async {
        final l = withRunRow(run());
        l[l.length - 1] = _endLine({
          for (final s in archiveSections) s.name: s.name == 'runs' ? 1 : 0,
        });
        await c.run(await _archive(l));
        expect(c.sink.rows['runs'], [run()]);
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
          for (final s in archiveSections) s.name: s.name == 'runs' ? 1 : 0,
        });
        await c.rejectsLines(l, ArchiveImportFailure.damaged);
      }
    });

    test(
      'REAL: nicht endlich abgelehnt, Ganzzahlschreibweise erlaubt',
      () async {
        final lap = _row(archiveSections[1], 1);
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
              for (final s in archiveSections) s.name: s.name == 'laps' ? 1 : 0,
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
          for (final s in archiveSections) s.name: s.name == 'runs' ? 1 : 0,
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
            for (final s in archiveSections) s.name: s.name == 'runs' ? 1 : 0,
          }),
        ArchiveImportFailure.damaged,
      );
    });

    test(
      'Zeile mit fremdem Schlüssel neben data / ohne data / data kein Objekt',
      () async {
        final counts = {
          for (final s in archiveSections) s.name: s.name == 'runs' ? 1 : 0,
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
        for (final s in archiveSections) s.name: s.name == 'runs' ? 2 : 0,
      };
      for (final ids in [
        [2, 1],
        [1, 1],
      ]) {
        c = _Case(dir);
        final rows = [
          for (final id in ids)
            _rowLine({..._row(archiveSections[0], 1), 'id': id}),
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
          for (final s in archiveSections) s.name: db[s.name]?.length ?? 0,
        };
        counts['laps'] = counts['laps']! + delta;
        final l = _validLines(db);
        l[l.length - 1] = _endLine(counts);
        await c.rejectsLines(l, ArchiveImportFailure.damaged);
      }
    });

    test('Zähler fehlt / überzählig / Text statt Zahl', () async {
      final base = {for (final s in archiveSections) s.name: 0};
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
          _rowLine(_row(archiveSections[0], 9)),
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
            for (final s in archiveSections)
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
}
