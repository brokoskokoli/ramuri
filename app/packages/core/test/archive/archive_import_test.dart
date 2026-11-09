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
  for (final s in archiveSectionsFor(1)) ...[
    _section(s.name),
    for (final r in db[s.name] ?? const <Map<String, Object?>>[]) _rowLine(r),
  ],
  _endLine({
    for (final s in archiveSectionsFor(1)) s.name: db[s.name]?.length ?? 0,
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
      lines.add(_endLine({for (final s in archiveSectionsFor(1)) s.name: 99}));
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
              for (final col in archiveSectionsFor(1)[10].columns)
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
      'Schema größer als 5: neueres Archiv, auch mit fremden Schlüsseln',
      () async {
        final lines = valid()..[0] = _manifest(schema: 6);
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
        for (final s in archiveSectionsFor(1))
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
        for (final s in archiveSectionsFor(1))
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
        _rowLine(_row(archiveSectionsFor(1)[0], 1)),
        ...l.skip(1),
      ], ArchiveImportFailure.damaged);
    });
  });

  group('Zeilen und Spalten', () {
    List<String> withRunRow(Map<String, Object?> data) {
      final l = valid(0);
      return [...l.take(2), _rowLine(data), ...l.skip(2)];
    }

    Map<String, Object?> run() => _row(archiveSectionsFor(1)[0], 1);

    Future<void> counted(
      Map<String, Object?> data,
      ArchiveImportFailure f,
    ) async {
      // Mit richtigem Zähler, damit nur die Zeile selbst falsch ist.
      final l = withRunRow(data);
      l[l.length - 1] = _endLine({
        for (final s in archiveSectionsFor(1)) s.name: s.name == 'runs' ? 1 : 0,
      });
      await c.rejectsLines(l, f);
    }

    test(
      'gültige Zeile mit diesem Aufbau wird angenommen (Gegenprobe)',
      () async {
        final l = withRunRow(run());
        l[l.length - 1] = _endLine({
          for (final s in archiveSectionsFor(1))
            s.name: s.name == 'runs' ? 1 : 0,
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
          for (final s in archiveSectionsFor(1))
            s.name: s.name == 'runs' ? 1 : 0,
        });
        await c.rejectsLines(l, ArchiveImportFailure.damaged);
      }
    });

    test(
      'REAL: nicht endlich abgelehnt, Ganzzahlschreibweise erlaubt',
      () async {
        final lap = _row(archiveSectionsFor(1)[1], 1);
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
              for (final s in archiveSectionsFor(1))
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
          for (final s in archiveSectionsFor(1))
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
            for (final s in archiveSectionsFor(1))
              s.name: s.name == 'runs' ? 1 : 0,
          }),
        ArchiveImportFailure.damaged,
      );
    });

    test(
      'Zeile mit fremdem Schlüssel neben data / ohne data / data kein Objekt',
      () async {
        final counts = {
          for (final s in archiveSectionsFor(1))
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
        for (final s in archiveSectionsFor(1)) s.name: s.name == 'runs' ? 2 : 0,
      };
      for (final ids in [
        [2, 1],
        [1, 1],
      ]) {
        c = _Case(dir);
        final rows = [
          for (final id in ids)
            _rowLine({..._row(archiveSectionsFor(1)[0], 1), 'id': id}),
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
          for (final s in archiveSectionsFor(1))
            s.name: db[s.name]?.length ?? 0,
        };
        counts['laps'] = counts['laps']! + delta;
        final l = _validLines(db);
        l[l.length - 1] = _endLine(counts);
        await c.rejectsLines(l, ArchiveImportFailure.damaged);
      }
    });

    test('Zähler fehlt / überzählig / Text statt Zahl', () async {
      final base = {for (final s in archiveSectionsFor(1)) s.name: 0};
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
          _rowLine(_row(archiveSectionsFor(1)[0], 9)),
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
            for (final s in archiveSectionsFor(1))
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
    }) {
      final db = <String, List<Map<String, Object?>>>{
        'runs': [_row(archiveSections[0], 1), _row(archiveSections[0], 2)],
        'run_feedback': feedback ?? [fb()],
        'manual_trainings': trainings ?? [mt()],
      };
      return [
        manifest ??
            '{"type":"manifest","format":2,"schema_version":5,'
                '"created_at_us":1793000000000000}',
        for (final sec in archiveSections) ...[
          _section(sec.name),
          for (final r in db[sec.name] ?? const <Map<String, Object?>>[])
            _rowLine(r),
        ],
        _endLine({
          for (final sec in archiveSections)
            sec.name: db[sec.name]?.length ?? 0,
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
      final db = _fullDb(rowsPer: 2);
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
