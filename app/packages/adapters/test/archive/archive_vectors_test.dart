// Prüft den Archiv-Adapter gegen Vektoren einer unabhängigen Umsetzung in
// Python (`tool/archive_vectors/make_vectors.py`, nur aus
// `docs/contracts/archive.md` geschrieben). Alle Daten sind synthetisch.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter_test/flutter_test.dart';

const _dir = 'test/archive/vectors';

Uint8List _hex(String h) => Uint8List.fromList([
  for (var i = 0; i < h.length; i += 2)
    int.parse(h.substring(i, i + 2), radix: 16),
]);

String _toHex(List<int> b) =>
    b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();

Future<Uint8List> _collect(Stream<Uint8List> s) async {
  final b = BytesBuilder(copy: false);
  await for (final c in s) {
    b.add(c);
  }
  return b.takeBytes();
}

Uint8List _read(String name) => File('$_dir/$name').readAsBytesSync();

/// Zerlegt Bytes in ungleich große Teile (Stückgrenzen liegen nie auf Teilgrenzen).
Stream<List<int>> _pieces(Uint8List b, [int size = 7919]) async* {
  for (var i = 0; i < b.length; i += size) {
    yield b.sublist(i, i + size > b.length ? b.length : i + size);
  }
}

Future<String> _sha(List<int> b) async =>
    _toHex((await Sha256().hash(b)).bytes);

const _failures = {
  'wrong_password_or_start_damaged': ArchiveFailure.wrongPasswordOrDamaged,
  'corrupt': ArchiveFailure.damaged,
  'unknown_version': ArchiveFailure.unsupportedVersion,
  'unsupported_parameters': ArchiveFailure.unsupportedParameters,
  'not_an_archive': ArchiveFailure.notAnArchive,
};

void main() {
  final meta = jsonDecode(
    File('$_dir/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final vectors = (meta['vectors'] as List).cast<Map<String, dynamic>>();
  final positive = vectors.where((v) => v['expect'] == 'ok').toList();
  // `layer: content`: Rahmen und Kryptografie gültig, der Inhalt wird vom Leser
  // abgelehnt (archive_import_vectors_test.dart), nicht von der Verschlüsselung.
  final negative = vectors
      .where((v) => v['expect'] != 'ok' && v['layer'] != 'content')
      .toList();

  test('Fixture ist vollständig (Mindestumfang)', () {
    expect(
      positive.map((v) => v['name']),
      containsAll([
        'empty',
        'short',
        'exact_65536',
        'exact_65537',
        'multi_150k',
        'archive_small',
      ]),
    );
    expect(negative.length, greaterThanOrEqualTo(10));
  });

  group('Schlüsselableitung gegen Python', () {
    for (final v in positive) {
      test('${v['name']}: Argon2id-Schlüssel', () async {
        final key = await CryptographyArchiveKdf().deriveKey(
          password: _hex(v['password_utf8_hex'] as String),
          salt: _hex(v['salt_hex'] as String),
          params: ArchiveHeader.params,
        );
        expect(_toHex(key), v['key_hex']);
      });
    }
  });

  group('Dart entschlüsselt die Vektoren', () {
    for (final v in positive) {
      test('${v['name']}', () async {
        final file = _read(v['file'] as String);
        expect(file.length, v['file_len']);
        final cipher = createArchiveCipher();
        final plain = await _collect(
          cipher.decrypt(v['password'] as String, _pieces(file)),
        );
        expect(plain.length, v['plaintext_len']);
        expect(await _sha(plain), v['plaintext_sha256']);
        expect(plain, _read(v['plaintext_file'] as String));
      });
    }

    test('archive_small: gzip, JSON Lines, 19 Abschnitte', () async {
      final v = positive.firstWhere((v) => v['name'] == 'archive_small');
      final plain = await _collect(
        createArchiveCipher().decrypt(
          v['password'] as String,
          Stream.value(_read(v['file'] as String)),
        ),
      );
      final text = utf8.decode(gzip.decode(plain));
      expect(await _sha(utf8.encode(text)), v['jsonl_sha256']);
      final lines = const LineSplitter().convert(text);
      expect(text.endsWith('\n'), isTrue);
      final first = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(first, {
        'type': 'manifest',
        'format': 1,
        'schema_version': 4,
        'created_at_us': 1793000000000000,
      });
      final sections = [
        for (final l in lines)
          if ((jsonDecode(l) as Map)['type'] == 'section')
            (jsonDecode(l) as Map)['name'],
      ];
      expect(sections.length, 19);
      final end = jsonDecode(lines.last) as Map<String, dynamic>;
      expect((end['rows'] as Map).keys.toList(), sections);
      expect(end['rows'], v['row_counts']);
      expect(text, contains('zukunft_kennzahl_'));
      expect(text, contains('"role":"original"'));
      expect(text, contains('"role":"current"'));
    });
  });

  test(
    'archive_v2: Format 2, Schema 5, 21 Abschnitte inkl. run_feedback',
    () async {
      final v = positive.firstWhere((v) => v['name'] == 'archive_v2');
      final plain = await _collect(
        createArchiveCipher().decrypt(
          v['password'] as String,
          Stream.value(_read(v['file'] as String)),
        ),
      );
      expect(_read(v['file'] as String)[9], 2);
      final text = utf8.decode(gzip.decode(plain));
      expect(await _sha(utf8.encode(text)), v['jsonl_sha256']);
      final lines = const LineSplitter().convert(text);
      expect(jsonDecode(lines.first), {
        'type': 'manifest',
        'format': 2,
        'schema_version': 5,
        'created_at_us': 1793000000000000,
      });
      final sections = [
        for (final l in lines)
          if ((jsonDecode(l) as Map)['type'] == 'section')
            (jsonDecode(l) as Map)['name'],
      ];
      expect(sections.length, 21);
      expect(sections.sublist(16, 18), ['run_feedback', 'manual_trainings']);
      final end = jsonDecode(lines.last) as Map<String, dynamic>;
      expect(end['rows'], v['row_counts']);
    },
  );

  test(
    'archive_v2_s6: Format 2, Schema 6, 23 Abschnitte inkl. Referenzleistungen',
    () async {
      final v = positive.firstWhere((v) => v['name'] == 'archive_v2_s6');
      final plain = await _collect(
        createArchiveCipher().decrypt(
          v['password'] as String,
          Stream.value(_read(v['file'] as String)),
        ),
      );
      expect(_read(v['file'] as String)[9], 2);
      final text = utf8.decode(gzip.decode(plain));
      expect(await _sha(utf8.encode(text)), v['jsonl_sha256']);
      final lines = const LineSplitter().convert(text);
      expect(jsonDecode(lines.first), {
        'type': 'manifest',
        'format': 2,
        'schema_version': 6,
        'created_at_us': 1793000000000000,
      });
      final sections = [
        for (final l in lines)
          if ((jsonDecode(l) as Map)['type'] == 'section')
            (jsonDecode(l) as Map)['name'],
      ];
      expect(sections.length, 23);
      expect(sections.sublist(21), [
        'reference_performances',
        'rejected_suggestions',
      ]);
      final end = jsonDecode(lines.last) as Map<String, dynamic>;
      expect(end['rows'], v['row_counts']);
      expect(end['rows']['reference_performances'], 3);
    },
  );

  test('archive_v2_s7: Format 2, Schema 7, 24 Abschnitte, Ziel, Plan und Einheiten', () async {
    final v = positive.firstWhere((v) => v['name'] == 'archive_v2_s7');
    final plain = await _collect(
      createArchiveCipher().decrypt(
        v['password'] as String,
        Stream.value(_read(v['file'] as String)),
      ),
    );
    expect(_read(v['file'] as String)[9], 2);
    final text = utf8.decode(gzip.decode(plain));
    expect(await _sha(utf8.encode(text)), v['jsonl_sha256']);
    final lines = const LineSplitter().convert(text);
    expect(jsonDecode(lines.first), {
      'type': 'manifest',
      'format': 2,
      'schema_version': 7,
      'created_at_us': 1793000000000000,
    });
    final sections = [
      for (final l in lines)
        if ((jsonDecode(l) as Map)['type'] == 'section')
          (jsonDecode(l) as Map)['name'],
    ];
    expect(sections.length, 24);
    expect(sections.sublist(18, 21), ['goals', 'plans', 'active_warning']);
    expect(sections.last, 'plan_units');
    final end = jsonDecode(lines.last) as Map<String, dynamic>;
    expect(end['rows'], v['row_counts']);
    expect(end['rows']['goals'], 1);
    expect(end['rows']['plans'], 1);
    expect(end['rows']['plan_units'], 2);
    expect(end['rows']['active_warning'], 0);
  });

  test('archive_v2_s8: Format 2, Schema 8, plan_units mit fixed', () async {
    final v = positive.firstWhere((v) => v['name'] == 'archive_v2_s8');
    final plain = await _collect(
      createArchiveCipher().decrypt(
        v['password'] as String,
        Stream.value(_read(v['file'] as String)),
      ),
    );
    expect(_read(v['file'] as String)[9], 2);
    final text = utf8.decode(gzip.decode(plain));
    expect(await _sha(utf8.encode(text)), v['jsonl_sha256']);
    final lines = [
      for (final l in const LineSplitter().convert(text))
        jsonDecode(l) as Map<String, dynamic>,
    ];
    expect(lines.first['schema_version'], 8);
    final units = [
      for (final l in lines)
        if (l['type'] == 'row' && (l['data'] as Map).containsKey('pinned'))
          l['data'] as Map,
    ];
    expect(
      [for (final u in units) u['fixed']],
      ['none', 'day', 'kind', 'easyForHard'],
    );
    expect(lines.last['rows'], v['row_counts']);
    expect(lines.last['rows']['plan_units'], 4);
  });

  group('Dart verschlüsselt byte-gleich mit festem Salz', () {
    // Hook: createArchiveCipher(randomBytes:) liefert das feste Salz; das
    // Salz ist der einzige Zufall des Formats.
    for (final v in positive) {
      test('${v['name']}', () async {
        final salt = _hex(v['salt_hex'] as String);
        var calls = 0;
        // Format 1 ist der Standard der Vektoren (Feld `format` fehlt oder 1);
        // `archive_v2` trägt Format 2.
        final cipher = FramedArchiveCipher(
          kdf: CryptographyArchiveKdf(),
          aead: CryptographyChunkAead(),
          randomBytes: (len) {
            calls++;
            expect(len, 16);
            return salt;
          },
          headerFormat: (v['format'] as int?) ?? 1,
        );
        final plain = _read(v['plaintext_file'] as String);
        final out = await _collect(
          cipher.encrypt(v['password'] as String, _pieces(plain, 10007)),
        );
        expect(calls, 1);
        expect(out.length, v['file_len']);
        expect(_toHex(out.sublist(0, 36)), v['header_hex']);
        expect(out, _read(v['file'] as String));
      });
    }
  });

  group('Fehlerklassen der Negativvektoren', () {
    for (final v in negative) {
      test('${v['name']} (${v['note']})', () async {
        final file = _read(v['file'] as String);
        await expectLater(
          _collect(
            createArchiveCipher().decrypt(
              v['password'] as String,
              _pieces(file),
            ),
          ),
          throwsA(
            isA<ArchiveException>().having(
              (e) => e.failure,
              'failure',
              _failures[v['expect']],
            ),
          ),
        );
      });
    }
  });
}
