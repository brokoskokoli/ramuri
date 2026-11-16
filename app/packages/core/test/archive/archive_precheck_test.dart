import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

/// Testvektoren des Archivvertrags (synthetisch, `tool/archive_vectors`).
const String _vectors = '../adapters/test/archive/vectors';

void main() {
  final meta = jsonDecode(
    File('$_vectors/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final vectors = (meta['vectors'] as List).cast<Map<String, dynamic>>();

  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('precheck'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ArchiveImportFailure?> failureOf(String path) async {
    try {
      await precheckArchiveFile(path);
    } on ArchiveImportException catch (e) {
      return e.failure;
    }
    return null;
  }

  String write(String name, List<int> bytes) {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(bytes);
    return f.path;
  }

  test(
    'jeder gültige Vektor (Format 1 und 2, alle Schemata) besteht',
    () async {
      final ok = vectors.where((v) => v['expect'] == 'ok').toList();
      expect(ok.map((v) => v['format']).toSet(), {1, 2});
      expect(ok, hasLength(greaterThanOrEqualTo(17)));
      for (final v in ok) {
        expect(
          await failureOf('$_vectors/${v['file']}'),
          isNull,
          reason: v['name'] as String,
        );
      }
    },
  );

  test('Negativvektoren des Kopfes ergeben den passenden Fehler', () async {
    const expected = {
      'neg_bad_magic': ArchiveImportFailure.notAnArchive,
      'neg_short_header': ArchiveImportFailure.damaged,
      'neg_version_3': ArchiveImportFailure.unsupportedVersion,
      'neg_memory_1024': ArchiveImportFailure.unsupportedParameters,
    };
    for (final e in expected.entries) {
      expect(
        await failureOf('$_vectors/${e.key}.runarchv'),
        e.value,
        reason: e.key,
      );
    }
  });

  test('Fehler hinter dem Kopf findet erst das Einlesen', () async {
    // Die Vorprüfung ersetzt die vollständige Prüfung nicht.
    for (final name in [
      'neg_header_only',
      'neg_flip_first_byte',
      'neg_truncate_at_boundary',
      'neg_append_byte',
    ]) {
      expect(await failureOf('$_vectors/$name.runarchv'), isNull, reason: name);
    }
  });

  test('Fremddatei, leere und zu kurze Datei: keine Archivdatei', () async {
    final text = write('notiz.txt', utf8.encode('Einkaufsliste: Brot\n' * 10));
    expect(await failureOf(text), ArchiveImportFailure.notAnArchive);
    final zip = write('a.zip', [0x50, 0x4B, 0x03, 0x04, ...List.filled(60, 0)]);
    expect(await failureOf(zip), ArchiveImportFailure.notAnArchive);
    expect(
      await failureOf(write('leer', [])),
      ArchiveImportFailure.notAnArchive,
    );
    // 7 Byte des Magic: zu kurz für die Kennung.
    final seven = write('sieben', ArchiveHeader.magic.sublist(0, 7));
    expect(await failureOf(seven), ArchiveImportFailure.notAnArchive);
  });

  test('Magic ohne vollständige Version: unbekannte Formatversion', () async {
    final nine = write('neun', [...ArchiveHeader.magic, 0x00]);
    expect(await failureOf(nine), ArchiveImportFailure.unsupportedVersion);
  });

  test(
    'nur die ersten 36 Byte zählen: gültiger Kopf ohne Stücke besteht',
    () async {
      final header = ArchiveHeader(Uint8List(16)).encode();
      expect(await failureOf(write('kopf', header)), isNull);
    },
  );

  test('nicht lesbare Datei: Lesefehler', () async {
    expect(
      await failureOf('${tmp.path}/fehlt.runarchv'),
      ArchiveImportFailure.readFailed,
    );
    expect(await failureOf(tmp.path), ArchiveImportFailure.readFailed);
  });

  test('Bytes direkt: gleiche Regeln wie der Leser', () {
    expect(
      () => precheckArchiveHeader(Uint8List.fromList(utf8.encode('RUNARCHX'))),
      throwsA(
        isA<ArchiveImportException>().having(
          (e) => e.failure,
          'failure',
          ArchiveImportFailure.notAnArchive,
        ),
      ),
    );
    precheckArchiveHeader(ArchiveHeader(Uint8List(16), format: 1).encode());
  });
}
