// Prüft den Archiv-Leser (core) mit dem echten Kryptografie-Adapter gegen die
// Vektoren der unabhängigen Umsetzung und im Rundgang mit dem Export. Alle
// Daten sind synthetisch. Der Leser läuft wie in der App im Arbeits-Isolate.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/archive/vectors';

const _failures = {
  'wrong_password_or_start_damaged':
      ArchiveImportFailure.wrongPasswordOrDamaged,
  'corrupt': ArchiveImportFailure.damaged,
  'unknown_version': ArchiveImportFailure.unsupportedVersion,
  'unsupported_parameters': ArchiveImportFailure.unsupportedParameters,
  'not_an_archive': ArchiveImportFailure.notAnArchive,
};

/// [today]: Ortstag des Vektors (`today`, sonst 2026-11-20), 12:00, Versatz 0.
Future<void> _import(
  FakeArchiveSink sink,
  String path,
  String password, [
  String today = '2026-11-20',
]) => ArchiveImporter(
  sink: sink,
  cipherFactory: createArchiveCipherInWorker,
  clock: FakeClock(DateTime.parse('${today}T12:00:00Z')),
).import(path: path, password: password);

void main() {
  final meta = jsonDecode(
    File('$_dir/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final vectors = (meta['vectors'] as List).cast<Map<String, dynamic>>();
  final positive = vectors.where((v) => v['expect'] == 'ok').toList();
  final negative = vectors.where((v) => v['expect'] != 'ok').toList();

  // Format 1 (archive_small) und Format 2 (archive_v2, Schema 5 mit
  // run_feedback und manual_trainings): alle Zeilen kommen an, commit am Ende.
  for (final v in positive.where((v) => v['jsonl_file'] != null)) {
    test(
      '${v['name']}: alle Zeilen des Vektors kommen an, commit am Ende',
      () async {
        final sink = FakeArchiveSink();
        await _import(
          sink,
          '$_dir/${v['file']}',
          v['password'] as String,
          (v['today'] as String?) ?? '2026-11-20',
        );

        final expected = <String, List<Map<String, Object?>>>{};
        String? section;
        for (final line in File('$_dir/${v['jsonl_file']}').readAsLinesSync()) {
          final m = jsonDecode(line) as Map<String, dynamic>;
          if (m['type'] == 'section') {
            section = m['name'] as String;
          } else if (m['type'] == 'row') {
            (expected[section!] ??= []).add(
              (m['data'] as Map<String, dynamic>).cast<String, Object?>(),
            );
          }
        }
        expect(sink.rows, expected);
        expect(sink.calls.first, 'begin');
        expect(sink.calls.last, 'commit');
        expect(sink.commits, 1);
        expect(sink.aborts, 0);
      },
    );
  }

  test(
    'archive_v2: ein Tag früher als das Datum des letzten Trainings lehnt ab',
    () async {
      // Grenzfall im Vektor: das zweite Training liegt genau auf "heute".
      final v = positive.firstWhere((v) => v['name'] == 'archive_v2');
      final sink = FakeArchiveSink();
      await expectLater(
        _import(
          sink,
          '$_dir/${v['file']}',
          v['password'] as String,
          '2026-11-19',
        ),
        throwsA(
          isA<ArchiveImportException>().having(
            (e) => e.failure,
            'failure',
            ArchiveImportFailure.damaged,
          ),
        ),
      );
      expect(sink.commits, 0);
      expect(sink.aborts, 1);
    },
  );

  group('Negativvektoren: abort, nie commit, richtige Fehlerart', () {
    for (final v in negative) {
      test('${v['name']} (${v['note']})', () async {
        final sink = FakeArchiveSink();
        await expectLater(
          _import(
            sink,
            '$_dir/${v['file']}',
            v['password'] as String,
            (v['today'] as String?) ?? '2026-11-20',
          ),
          throwsA(
            isA<ArchiveImportException>().having(
              (e) => e.failure,
              'failure',
              _failures[v['expect']],
            ),
          ),
        );
        expect(sink.commits, 0);
        expect(sink.aborts, 1);
        expect(sink.calls.last, 'abort');
        // Inhaltsfehler zeigt sich erst beim Lesen der Zeile: frühere Stapel
        // sind schon im Ziel, der Abbruch verwirft sie (Vertrag 3.2).
        if (v['layer'] != 'content') expect(sink.rows, isEmpty);
      });
    }
  });

  group('gültiger Rahmen, aber kein Archivinhalt: beschädigt', () {
    for (final v in positive.where((v) => v['jsonl_file'] == null)) {
      test('${v['name']}', () async {
        final sink = FakeArchiveSink();
        await expectLater(
          _import(sink, '$_dir/${v['file']}', v['password'] as String),
          throwsA(
            isA<ArchiveImportException>().having(
              (e) => e.failure,
              'failure',
              ArchiveImportFailure.damaged,
            ),
          ),
        );
        expect(sink.commits, 0);
        expect(sink.calls.last, 'abort');
      });
    }
  });

  test('archive_small mit falschem Passwort: eine Meldung', () async {
    final v = positive.firstWhere((v) => v['name'] == 'archive_small');
    final sink = FakeArchiveSink();
    await expectLater(
      _import(sink, '$_dir/${v['file']}', 'falsches Passwort 123456'),
      throwsA(
        isA<ArchiveImportException>().having(
          (e) => e.failure,
          'failure',
          ArchiveImportFailure.wrongPasswordOrDamaged,
        ),
      ),
    );
    expect(sink.calls, ['begin', 'abort']);
  });

  test(
    'Rundgang mit echter Kryptografie: Export -> Leser, alle Zeilen gleich',
    () async {
      final dir = Directory.systemTemp.createTempSync('wp12c1_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final db = <String, List<Map<String, Object?>>>{
        for (final s in archiveSections)
          if (!s.isReserved)
            s.name: [
              for (var i = 1; i <= 3; i++)
                {
                  for (final c in s.columns)
                    c.name: c.name == s.key && s.keyIsText
                        ? 'key$i'
                        : switch (c.type) {
                            ArchiveType.integer => i,
                            ArchiveType.real => i + 0.25,
                            // Plan: JSON-Texte und Ortstage prüft der Leser.
                            ArchiveType.text
                                when const {
                                  'inputs',
                                  'summary',
                                  'structure',
                                }.contains(c.name) =>
                              '{"t":"ä$i\u{1F3C3}"}',
                            ArchiveType.text
                                when const {
                                  'valid_from',
                                  'day',
                                }.contains(c.name) =>
                              '2026-11-0$i',
                            ArchiveType.text => 'ä$i\u{1F3C3}',
                            ArchiveType.boolean => i % 2,
                          },
                },
            ],
      };
      final handoff = FakeFileHandoff()..directory = dir.path;
      const password = 'synthetisches Testpasswort';
      final file = await ArchiveExporter(
        source: FakeArchiveSource(db),
        handoff: handoff,
        clock: FakeClock(DateTime.utc(2026, 11, 7, 12)),
        cipherFactory: createArchiveCipherInWorker,
      ).export(password: password);

      final sink = FakeArchiveSink();
      await _import(sink, file.path!, password);
      expect(sink.rows, db);
      expect(sink.commits, 1);
      expect(sink.calls.last, 'commit');

      // Ein verändertes Byte im Chiffretext: nichts wird übernommen.
      final bytes = Uint8List.fromList(File(file.path!).readAsBytesSync());
      bytes[bytes.length - 1] ^= 1;
      final broken = File('${dir.path}/kaputt.runarch')
        ..writeAsBytesSync(bytes);
      final sink2 = FakeArchiveSink();
      await expectLater(
        _import(sink2, broken.path, password),
        throwsA(isA<ArchiveImportException>()),
      );
      expect(sink2.commits, 0);
      expect(sink2.calls.last, 'abort');
    },
  );
}
