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
  randomBytes: (n) =>
      Uint8List.fromList(List.generate(n, (_) => Random.secure().nextInt(256))),
);

/// Verschlüsselt das dritte Stück nicht mehr: Fehler mitten im Strom.
class _FailingAead implements ChunkAead {
  final _inner = FakeChunkAead();
  int _n = 0;

  @override
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plaintext,
  }) {
    if (++_n == 3) {
      throw StateError('Verschlüsselung gescheitert (Test) $_marker');
    }
    return _inner.seal(key: key, nonce: nonce, aad: aad, plaintext: plaintext);
  }

  @override
  Future<Uint8List?> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  }) => _inner.open(key: key, nonce: nonce, aad: aad, sealed: sealed);
}

ArchiveCipher _failingCipher() => FramedArchiveCipher(
  kdf: FakeArchiveKdf(),
  aead: _FailingAead(),
  randomBytes: (n) => Uint8List(n),
);

Object _valueFor(ArchiveColumn c, int i) => switch (c.type) {
  ArchiveType.integer => i,
  ArchiveType.real => i + 0.25,
  ArchiveType.text => 's$i',
  ArchiveType.boolean => i % 2,
};

/// Eine Zeile mit Werten in allen Spalten (kein NULL).
Map<String, Object?> _row(ArchiveSectionSpec s, int i) => {
  for (final c in s.columns)
    c.name: c.name == s.key && s.keyIsText ? 'key$i' : _valueFor(c, i),
};

Map<String, List<Map<String, Object?>>> _fullDb({int rowsPer = 1}) => {
  for (final s in archiveSections)
    if (!s.isReserved) s.name: [for (var i = 1; i <= rowsPer; i++) _row(s, i)],
};

Future<List<Map<String, Object?>>> _readBack(
  File f, {
  String pw = _password,
}) async {
  final cipher = FramedArchiveCipher(
    kdf: FakeArchiveKdf(),
    aead: FakeChunkAead(),
    randomBytes: (n) => Uint8List(n),
  );
  final b = BytesBuilder(copy: false);
  await for (final c in cipher.decrypt(pw, Stream.value(f.readAsBytesSync()))) {
    b.add(c);
  }
  final text = utf8.decode(gzip.decode(b.takeBytes()));
  expect(text.endsWith('\n'), isTrue);
  return [
    for (final l in text.substring(0, text.length - 1).split('\n'))
      jsonDecode(l) as Map<String, Object?>,
  ];
}

void main() {
  late Directory dir;
  late FakeFileHandoff handoff;
  late FakeClock clock;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wp12b1_');
    handoff = FakeFileHandoff()..directory = dir.path;
    clock = FakeClock(DateTime.utc(2026, 11, 7, 12));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  ArchiveExporter exporter(
    FakeArchiveSource src, {
    ArchiveCipherFactory cipher = _fakeCipher,
    int pageSize = archivePageSize,
  }) => ArchiveExporter(
    source: src,
    handoff: handoff,
    clock: clock,
    cipherFactory: cipher,
    pageSize: pageSize,
  );

  List<String> files() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList();

  group('Rundgang über den Entschlüssler', () {
    test(
      'v6 vollständig: jeder Abschnitt, Reihenfolge, Zeilen, Endzeile',
      () async {
        final db = _fullDb(rowsPer: 2);
        final file = await exporter(FakeArchiveSource(db))
            .export(password: _password);
        expect(file.path, '${dir.path}/running-archiv-20261107.runarch');
        expect(file.fileName, 'running-archiv-20261107.runarch');
        expect(files(), ['running-archiv-20261107.runarch']);

        final lines = await _readBack(File(file.path!));
        expect(lines.first, {
          'type': 'manifest',
          'format': 2,
          'schema_version': 6,
          'created_at_us': DateTime.utc(2026, 11, 7, 12).microsecondsSinceEpoch,
        });
        final sections = [
          for (final l in lines)
            if (l['type'] == 'section') l['name'],
        ];
        expect(sections, [for (final s in archiveSections) s.name]);
        expect(sections, hasLength(23));
        // Jede Tabelle mit mindestens einer Zeile.
        for (final s in archiveSections.where((s) => !s.isReserved)) {
          final rows = _rowsOf(lines, s.name);
          expect(rows, hasLength(2), reason: s.name);
          expect(rows.first, db[s.name]!.first, reason: s.name);
          expect(rows.first.keys.toList(), [for (final c in s.columns) c.name]);
        }
        for (final n in ['goals', 'plans', 'active_warning']) {
          expect(_rowsOf(lines, n), isEmpty);
        }
        final end = lines.last;
        expect(end['type'], 'end');
        expect((end['rows']! as Map).keys.toList(), sections);
        expect((end['rows']! as Map)['runs'], 2);
        expect((end['rows']! as Map)['goals'], 0);
      },
    );

    test(
      'Laufwerte: original und current, Grund, Basis, unbekannter Schlüssel',
      () async {
        final spec = archiveSections.firstWhere(
          (s) => s.name == 'computed_values',
        );
        Map<String, Object?> v(
          int id,
          String role, {
          double? real,
          String? reason,
        }) => {
          ..._row(spec, id),
          'value_key': 'zukunft.unbekannt.v9',
          'role': role,
          'value_real': real,
          'unavailable_reason': reason,
          'hr_max_bpm': 190,
          'hr_rest_bpm': 50,
          'hr_max_is_estimated': 1,
        };
        final db = _fullDb()
          ..['computed_values'] = [
            v(1, 'original', reason: 'insufficientData'),
            v(2, 'current', real: 12.5),
          ];
        final f = await exporter(FakeArchiveSource(db))
            .export(password: _password);
        final rows = _rowsOf(await _readBack(File(f.path!)), 'computed_values');
        expect(rows, db['computed_values']);
        expect(rows.first['unavailable_reason'], 'insufficientData');
        expect(rows.last['hr_max_is_estimated'], 1);
      },
    );

    test(
      'Einwilligungen und storage_meta fehlen; technische Merker fehlen',
      () async {
        final db = _fullDb()
          ..['consents'] = [
            {'purpose': 'health', 'granted': 1},
          ]
          ..['storage_meta'] = [
            {'key': 'schema', 'value': _marker},
          ]
          ..['settings'] = [
            for (final k in [
              ValueCalculationService.calculationPendingKey,
              ValueCalculationService.refreshPendingKey,
              RecalculationService.pendingKey,
              SettingKeys.loadProfilePending,
              SettingKeys.loadCoefficientsPending,
              SettingKeys.loadFactorPending,
              SettingKeys.loadFactorDeclined,
              SettingKeys.loadFactor,
              'unit.pace',
              SettingKeys.loadProfile,
              SettingKeys.loadCoefficients,
              SettingKeys.loadAllRecorded,
              'zukunft.unbekannt',
            ])
              {'key': k, 'value': 'x', 'updated_at_us': 5},
          ];
        final f = await exporter(FakeArchiveSource(db))
            .export(password: _password);
        final lines = await _readBack(File(f.path!));
        final text = jsonEncode(lines);
        expect(text, isNot(contains('consents')));
        expect(text, isNot(contains('storage_meta')));
        expect(text, isNot(contains(_marker)));
        expect(
          [for (final r in _rowsOf(lines, 'settings')) r['key']],
          [
            SettingKeys.loadAllRecorded,
            SettingKeys.loadCoefficients,
            SettingKeys.loadFactor,
            SettingKeys.loadProfile,
            'unit.pace',
            'zukunft.unbekannt',
          ],
        );
        expect((lines.last['rows']! as Map)['settings'], 6);
      },
    );

    test(
      'Abschnitte sind in Seiten gelesen, Zeilenfolge nach Schlüssel',
      () async {
        final spec = archiveSections.firstWhere((s) => s.name == 'laps');
        final db = _fullDb()
          ..['laps'] = [
            for (final i in [7, 3, 5, 1, 2, 6, 4, 8]) _row(spec, i),
          ];
        final src = FakeArchiveSource(db);
        final f = await exporter(src, pageSize: 3).export(password: _password);
        expect(src.pageSizes.every((n) => n <= 3), isTrue);
        expect(src.pageSizes, contains(3));
        final ids = [
          for (final r in _rowsOf(await _readBack(File(f.path!)), 'laps'))
            r['id'],
        ];
        expect(ids, [1, 2, 3, 4, 5, 6, 7, 8]);
      },
    );

    test('falsches Passwort liest nichts', () async {
      final f = await exporter(FakeArchiveSource(_fullDb()))
          .export(password: _password);
      await expectLater(
        _readBack(File(f.path!), pw: 'falsches Passwort!!'),
        throwsA(isA<ArchiveException>()),
      );
    });

    test('Spalten stimmen mit der Tabelle im Vertrag überein', () {
      final doc = File('../../../docs/contracts/archive.md').readAsStringSync();
      final rows = RegExp(
        r'^\| (\d+) \| `(\w+)` \| (.+) \|$',
        multiLine: true,
      ).allMatches(doc).toList();
      expect(rows, hasLength(23));
      for (final m in rows) {
        final spec = archiveSections[int.parse(m.group(1)!) - 1];
        expect(spec.name, m.group(2));
        final cols = m.group(3)!.replaceAll(' (immer 1)', '');
        expect(
          [for (final c in spec.columns) '${c.name} ${_t(c)}'].join(', '),
          spec.isReserved ? isEmpty : cols,
          reason: spec.name,
        );
      }
    });
  });

  group('Fehler und Abbruch', () {
    // Unkomprimierbare Zeilen, damit mehrere Stücke entstehen (>128 KiB).
    Map<String, List<Map<String, Object?>>> bigDb() {
      final r = Random(1);
      final spec = archiveSections.firstWhere((s) => s.name == 'raw_steps');
      return _fullDb()
        ..['raw_steps'] = [
          for (var i = 1; i <= 5000; i++)
            {
              ..._row(spec, i),
              'source': List.generate(
                200,
                (_) => r.nextInt(16).toRadixString(16),
              ).join(),
            },
        ];
    }

    test(
      'Lesefehler mitten im Lauf: keine Datei, Fehler ohne Inhalt',
      () async {
        final src = FakeArchiveSource(bigDb())..failAtRead = 12;
        Object? err;
        try {
          await exporter(src, pageSize: 400).export(password: _password);
        } catch (e) {
          err = e;
        }
        expect(err, isA<ArchiveExportException>());
        expect(
          (err! as ArchiveExportException).failure,
          ArchiveExportFailure.readFailed,
        );
        expect(err.toString(), isNot(contains(_marker)));
        expect(files(), isEmpty);
      },
    );

    test(
      'Fehler beim Verschlüsseln nach geschriebenen Stücken: keine Datei',
      () async {
        Object? err;
        try {
          await exporter(
            FakeArchiveSource(bigDb()),
            cipher: _failingCipher,
          ).export(password: _password);
        } catch (e) {
          err = e;
        }
        expect(
          (err! as ArchiveExportException).failure,
          ArchiveExportFailure.encryptFailed,
        );
        expect(err.toString(), isNot(contains(_marker)));
        expect(files(), isEmpty);
      },
    );

    test('Abbruch mitten im Lauf: keine Datei', () async {
      final cancel = ArchiveCancel();
      final src = FakeArchiveSource(bigDb());
      final run = exporter(
        src,
        pageSize: 100,
      ).export(password: _password, cancel: cancel);
      // Nach einigen Seiten abbrechen.
      while (src.pageSizes.length < 30) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      cancel.cancel();
      await expectLater(
        run,
        throwsA(
          isA<ArchiveExportException>().having(
            (e) => e.failure,
            'failure',
            ArchiveExportFailure.cancelled,
          ),
        ),
      );
      expect(files(), isEmpty);
    });

    test('Wert passt nicht zum Schema: invalidData, keine Datei', () async {
      for (final bad in <Object?>[double.nan, double.infinity, 'x', null]) {
        final spec = archiveSections.firstWhere((s) => s.name == 'laps');
        final db = _fullDb()
          ..['laps'] = [
            {..._row(spec, 1), 'lap_time_s': bad},
          ];
        await expectLater(
          exporter(FakeArchiveSource(db)).export(password: _password),
          throwsA(
            isA<ArchiveExportException>().having(
              (e) => e.failure,
              'failure',
              ArchiveExportFailure.invalidData,
            ),
          ),
          reason: '$bad',
        );
        expect(files(), isEmpty);
      }
    });

    test('einzelnes Surrogat im Text wird abgelehnt', () async {
      final spec = archiveSections.firstWhere((s) => s.name == 'known_devices');
      final db = _fullDb()
        ..['known_devices'] = [
          {..._row(spec, 1), 'device_id': 'a\uD800b'},
        ];
      await expectLater(
        exporter(FakeArchiveSource(db)).export(password: _password),
        throwsA(isA<ArchiveExportException>()),
      );
      expect(files(), isEmpty);
    });

    test('zu kurzes Passwort, kein Exportordner, unsicherer Name', () async {
      final src = FakeArchiveSource(_fullDb());
      for (final (pw, f, ArchiveExportFailure want) in [
        ('kurz', null, ArchiveExportFailure.passwordRejected),
        (_password, '../x', ArchiveExportFailure.noExportDirectory),
      ]) {
        await expectLater(
          exporter(src).export(password: pw, fileName: f),
          throwsA(
            isA<ArchiveExportException>().having((e) => e.failure, 'f', want),
          ),
        );
      }
      handoff.directory = null;
      await expectLater(
        exporter(src).export(password: _password),
        throwsA(isA<ArchiveExportException>()),
      );
      expect(files(), isEmpty);
    });

    test('alte Datei gleichen Namens bleibt bei Fehler erhalten', () async {
      final target = File('${dir.path}/alt.runarch')..writeAsStringSync('alt');
      await expectLater(
        exporter(
          FakeArchiveSource(bigDb()),
          cipher: _failingCipher,
        ).export(password: _password, fileName: 'alt.runarch'),
        throwsA(isA<ArchiveExportException>()),
      );
      expect(target.readAsStringSync(), 'alt');
      expect(files(), ['alt.runarch']);
    });
  });

  group('Passwortregel', () {
    test('Länge in Zeichen, keine Klassenregeln, Wiederholung', () {
      expect(
        checkArchivePassword('a' * 14, 'a' * 14),
        ArchivePasswordCheck.tooShort,
      );
      expect(checkArchivePassword('a' * 15, 'a' * 15), ArchivePasswordCheck.ok);
      expect(
        checkArchivePassword('a' * 15, 'a' * 14 + 'b'),
        ArchivePasswordCheck.mismatch,
      );
      expect(checkArchivePassword('a' * 15, ''), ArchivePasswordCheck.mismatch);
      // Zeichen, nicht UTF-16-Einheiten: 15 Emoji sind 15 Zeichen, 14 nicht.
      expect(
        checkArchivePassword('😀' * 15, '😀' * 15),
        ArchivePasswordCheck.ok,
      );
      expect(
        checkArchivePassword('😀' * 14, '😀' * 14),
        ArchivePasswordCheck.tooShort,
      );
      // Nicht getrimmt: 14 Zeichen plus Leerzeichen zählen als 15.
      expect(
        checkArchivePassword('${'a' * 14} ', '${'a' * 14} '),
        ArchivePasswordCheck.ok,
      );
      expect(checkArchivePassword('', ''), ArchivePasswordCheck.tooShort);
    });
  });
}

String _t(ArchiveColumn c) =>
    '${switch (c.type) {
      ArchiveType.integer => 'I',
      ArchiveType.real => 'R',
      ArchiveType.text => 'T',
      ArchiveType.boolean => 'B',
    }}${c.nullable ? '?' : ''}';

List<Map<String, Object?>> _rowsOf(
  List<Map<String, Object?>> lines,
  String name,
) {
  final out = <Map<String, Object?>>[];
  String? cur;
  for (final l in lines) {
    if (l['type'] == 'section') cur = l['name'] as String;
    if (l['type'] == 'row' && cur == name) {
      out.add((l['data']! as Map).cast<String, Object?>());
    }
  }
  return out;
}
