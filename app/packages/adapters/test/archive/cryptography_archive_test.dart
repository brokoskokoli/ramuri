import 'dart:typed_data';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _hex(String s) {
  final h = s.replaceAll(RegExp(r'\s'), '');
  return Uint8List.fromList([
    for (var i = 0; i < h.length; i += 2)
      int.parse(h.substring(i, i + 2), radix: 16),
  ]);
}

Future<Uint8List> _collect(Stream<Uint8List> s) async {
  final b = BytesBuilder(copy: false);
  await for (final c in s) {
    b.add(c);
  }
  return b.takeBytes();
}

Uint8List _salt(int n) => Uint8List.fromList(List.generate(n, (i) => 0x40 + i));

void main() {
  group('CryptographyChunkAead', () {
    // RFC 8439, Abschnitt 2.8.2: öffentlicher Vektor (Plausibilität des
    // Adapters; die Testvektoren des Archivs liefert ein anderes Paket).
    final key = _hex(
      '80 81 82 83 84 85 86 87 88 89 8a 8b 8c 8d 8e 8f'
      '90 91 92 93 94 95 96 97 98 99 9a 9b 9c 9d 9e 9f',
    );
    final nonce = _hex('07 00 00 00 40 41 42 43 44 45 46 47');
    final aad = _hex('50 51 52 53 c0 c1 c2 c3 c4 c5 c6 c7');
    final plain = Uint8List.fromList(
      "Ladies and Gentlemen of the class of '99: If I could offer you only "
              'one tip for the future, sunscreen would be it.'
          .codeUnits,
    );

    test('RFC 8439: Tag und Chiffretext-Anfang', () async {
      final sealed = await CryptographyChunkAead().seal(
        key: key,
        nonce: nonce,
        aad: aad,
        plaintext: plain,
      );
      expect(sealed.length, plain.length + 16);
      expect(
        sealed.sublist(sealed.length - 16),
        _hex('1a e1 0b 59 4f 09 e2 6a 7e 90 2e cb d0 60 06 91'),
      );
      expect(sealed.sublist(0, 8), _hex('d3 1a 8d 34 64 8e 60 db'));
    });

    test(
      'open: Rundgang, falscher Tag, falsche AAD, falsche Nonce, kurz',
      () async {
        final aead = CryptographyChunkAead();
        final sealed = await aead.seal(
          key: key,
          nonce: nonce,
          aad: aad,
          plaintext: plain,
        );
        expect(
          await aead.open(key: key, nonce: nonce, aad: aad, sealed: sealed),
          plain,
        );
        Future<Uint8List?> open({Uint8List? s, Uint8List? n, Uint8List? a}) =>
            aead.open(
              key: key,
              nonce: n ?? nonce,
              aad: a ?? aad,
              sealed: s ?? sealed,
            );
        expect(await open(s: Uint8List.fromList(sealed)..[0] ^= 1), isNull);
        expect(
          await open(s: Uint8List.fromList(sealed)..[sealed.length - 1] ^= 1),
          isNull,
        );
        expect(await open(a: Uint8List.fromList(aad)..[0] ^= 1), isNull);
        expect(await open(n: Uint8List.fromList(nonce)..[11] ^= 1), isNull);
        expect(await open(s: Uint8List(15)), isNull);
        // Leerer Klartext: nur der Tag.
        final empty = await aead.seal(
          key: key,
          nonce: nonce,
          aad: aad,
          plaintext: Uint8List(0),
        );
        expect(empty.length, 16);
        expect(
          await aead.open(key: key, nonce: nonce, aad: aad, sealed: empty),
          isEmpty,
        );
      },
    );
  });

  group('Archiv mit echter Kryptografie', () {
    test(
      'Argon2id: 32 Byte, deterministisch, abhängig von Salz und Passwort',
      () async {
        final kdf = CryptographyArchiveKdf();
        final pw = Uint8List.fromList('synthetisches Testpasswort'.codeUnits);
        final sw = Stopwatch()..start();
        final a = await kdf.deriveKey(
          password: pw,
          salt: _salt(16),
          params: ArchiveHeader.params,
        );
        final ms = sw.elapsedMilliseconds;
        final b = await kdf.deriveKey(
          password: pw,
          salt: _salt(16),
          params: ArchiveHeader.params,
        );
        final c = await kdf.deriveKey(
          password: pw,
          salt: Uint8List.fromList(_salt(16))..[0] ^= 1,
          params: ArchiveHeader.params,
        );
        final d = await kdf.deriveKey(
          password: Uint8List.fromList(pw)..[0] ^= 1,
          salt: _salt(16),
          params: ArchiveHeader.params,
        );
        expect(a.length, 32);
        expect(b, a);
        expect(c, isNot(a));
        expect(d, isNot(a));
        // ignore: avoid_print
        print('Argon2id 64 MiB, t=3, p=1 (Host, JIT): $ms ms');
      },
    );

    test('Rundgang, falsches Passwort, Fehlerfälle, kein Klartext', () async {
      var n = 0;
      final cipher = createArchiveCipher(
        randomBytes: (len) =>
            Uint8List.fromList(List.generate(len, (i) => (i + 3 * ++n) & 0xFF)),
      );
      final marker = 'SYNTHETISCHE-MARKE-4711'.codeUnits;
      final plain = Uint8List.fromList([
        for (var i = 0; i < 140000; i++) marker[i % marker.length],
      ]);
      const pw = 'ein langes synthetisches Passwort';
      final file = await _collect(cipher.encrypt(pw, Stream.value(plain)));
      expect(file.sublist(0, 8), 'RUNARCHV'.codeUnits);
      expect(
        String.fromCharCodes(file).contains('SYNTHETISCHE-MARKE'),
        isFalse,
        reason: 'Klartext im Archiv',
      );
      expect(await _collect(cipher.decrypt(pw, Stream.value(file))), plain);

      Future<void> fails(
        Uint8List f,
        String password,
        ArchiveFailure why,
      ) async {
        await expectLater(
          _collect(cipher.decrypt(password, Stream.value(f))),
          throwsA(
            isA<ArchiveException>().having((e) => e.failure, 'failure', why),
          ),
        );
      }

      await fails(
        file,
        'falsches Passwort',
        ArchiveFailure.wrongPasswordOrDamaged,
      );
      await fails(
        file.sublist(0, file.length - 70000),
        pw,
        ArchiveFailure.damaged,
      );
      await fails(
        Uint8List.fromList(file)..[file.length - 1] ^= 1,
        pw,
        ArchiveFailure.damaged,
      );
      await fails(Uint8List.fromList([...file, 0]), pw, ArchiveFailure.damaged);
      await fails(Uint8List(0), pw, ArchiveFailure.notAnArchive);
    });
  });
}
