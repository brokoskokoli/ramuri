import 'dart:async';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

const int _chunk = FramedArchiveCipher.chunkSize;
const int _sealed = _chunk + FramedArchiveCipher.tagLength;
const int _head = ArchiveHeader.length;
const String _password = 'synthetisches Testpasswort';

Uint8List _bytes(int n, [int seed = 1]) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 31 + seed) & 0xFF));

Uint8List _salt(int n) => Uint8List.fromList(List.generate(n, (i) => i + 1));

Future<Uint8List> _collect(Stream<Uint8List> s) async {
  final b = BytesBuilder(copy: false);
  await for (final c in s) {
    b.add(c);
  }
  return b.takeBytes();
}

/// Teilt [data] in Stücke fester, ungerader Größe (der Rahmen darf nicht von
/// der Zerlegung des Eingabestroms abhängen).
Stream<List<int>> _pieces(Uint8List data, int size) async* {
  for (var i = 0; i < data.length; i += size) {
    yield data.sublist(i, i + size > data.length ? data.length : i + size);
  }
}

class _Rig {
  _Rig({bool usesSalt = true})
    : kdf = FakeArchiveKdf(usesSalt: usesSalt),
      aead = FakeChunkAead() {
    cipher = FramedArchiveCipher(kdf: kdf, aead: aead, randomBytes: _salt);
  }

  final FakeArchiveKdf kdf;
  final FakeChunkAead aead;
  late final FramedArchiveCipher cipher;

  Future<Uint8List> seal(Uint8List plain, {int piece = 7777}) =>
      _collect(cipher.encrypt(_password, _pieces(plain, piece)));

  Future<Uint8List> open(Uint8List file, {String password = _password}) =>
      _collect(cipher.decrypt(password, _pieces(file, 5000)));

  /// Scheitert mit [ArchiveException] der Art [failure].
  Future<void> expectFails(
    Uint8List file,
    ArchiveFailure failure, {
    String? reason,
  }) async {
    try {
      await open(file);
    } on ArchiveException catch (e) {
      expect(e.failure, failure, reason: reason);
      return;
    }
    fail('Archiv wurde gelesen${reason == null ? '' : ' ($reason)'}');
  }
}

Uint8List _cat(List<List<int>> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

void main() {
  group('Rundgang', () {
    for (final n in [
      0,
      1,
      _chunk - 1,
      _chunk,
      _chunk + 1,
      2 * _chunk,
      2 * _chunk + 5,
      3 * _chunk,
    ]) {
      test('Klartext von $n Byte', () async {
        final r = _Rig();
        final plain = _bytes(n);
        final file = await r.seal(plain);
        final chunks = n == 0 ? 1 : (n + _chunk - 1) ~/ _chunk;
        final tail = n == 0 ? 0 : n - (chunks - 1) * _chunk;
        // Kein zusätzliches leeres Stück bei vollem letztem Stück.
        expect(
          file.length,
          _head + (chunks - 1) * _sealed + tail + 16,
          reason: 'Dateilänge',
        );
        expect(await r.open(file), plain);
        // Nonce: Zähler 0..n-1, Endbyte nur beim letzten Stück.
        expect(r.aead.sealedNonces.length, chunks);
        for (var i = 0; i < chunks; i++) {
          final nonce = r.aead.sealedNonces[i];
          expect(nonce.sublist(0, 11), [
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, i, //
          ]);
          expect(nonce[11], i == chunks - 1 ? 1 : 0);
        }
        // Der Kopf ist AAD jedes Stücks, beim Ver- und Entschlüsseln.
        final header = file.sublist(0, _head);
        for (final a in [...r.aead.sealedAads, ...r.aead.openedAads]) {
          expect(a, header);
        }
        expect(r.aead.openedAads.length, chunks);
      });
    }

    test('Zähler ist 11 Byte Big-Endian und wächst über ein Byte hinaus', () {
      expect(FramedArchiveCipher.nonceFor(0x0102, last: false), [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 0, //
      ]);
      expect(FramedArchiveCipher.nonceFor(5, last: true), [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 1, //
      ]);
    });

    test('Zerlegung des Eingabestroms ändert die Datei nicht', () async {
      final plain = _bytes(2 * _chunk + 123);
      final a = await _Rig().seal(plain, piece: 1000);
      final b = await _Rig().seal(plain, piece: 70000);
      expect(a, b);
    });

    test(
      'Kopf: Magic, Parameter der Formatversion 1 an die Ableitung',
      () async {
        final r = _Rig();
        final file = await r.seal(_bytes(10));
        expect(file.sublist(0, 8), 'RUNARCHV'.codeUnits);
        expect(file.sublist(20, 36), _salt(16));
        expect(r.kdf.calls, 1);
        final p = r.kdf.lastParams!;
        expect(
          [p.memoryKib, p.iterations, p.parallelism, p.keyLength],
          [65536, 3, 1, 32],
        );
      },
    );

    test('Falsches Passwort: wrongPasswordOrDamaged, ohne Klartext', () async {
      final r = _Rig();
      final file = await r.seal(_bytes(2 * _chunk));
      final got = <Uint8List>[];
      Object? error;
      try {
        await for (final c in r.cipher.decrypt('falsch', _pieces(file, 999))) {
          got.add(c);
        }
      } on ArchiveException catch (e) {
        error = e;
      }
      expect(
        (error as ArchiveException).failure,
        ArchiveFailure.wrongPasswordOrDamaged,
      );
      expect(got, isEmpty);
    });

    test('Passwort und Inhalt stehen nicht im Fehlertext', () async {
      final r = _Rig();
      final file = await r.seal(_bytes(100));
      try {
        await r.open(file, password: 'GEHEIMES-PASSWORT-123456');
      } on ArchiveException catch (e) {
        expect(e.toString(), isNot(contains('GEHEIM')));
        expect(e.toString(), 'ArchiveException(wrongPasswordOrDamaged)');
      }
    });
  });

  group('Rahmen: Negativfälle', () {
    late _Rig r;
    late Uint8List three; // drei Stücke: voll, voll, kurz
    late Uint8List good;

    setUp(() async {
      r = _Rig();
      good = await r.seal(_bytes(2 * _chunk + 1000));
      three = good;
    });

    Uint8List piece(Uint8List file, int i) {
      final start = _head + i * _sealed;
      final end = i < 2 ? start + _sealed : file.length;
      return file.sublist(start, end);
    }

    test('abgeschnitten mitten im letzten Stück', () async {
      await r.expectFails(
        three.sublist(0, three.length - 1),
        ArchiveFailure.damaged,
      );
    });

    test('abgeschnitten mitten in einem mittleren Stück', () async {
      await r.expectFails(
        three.sublist(0, _head + _sealed + 100),
        ArchiveFailure.damaged,
      );
    });

    test('Endstück fehlt (an Stückgrenze abgeschnitten)', () async {
      await r.expectFails(
        three.sublist(0, _head + 2 * _sealed),
        ArchiveFailure.damaged,
        reason: 'letztes Stück fehlt',
      );
      await r.expectFails(
        three.sublist(0, _head + _sealed),
        ArchiveFailure.wrongPasswordOrDamaged,
        reason: 'nur das erste, volle Stück bleibt (als letztes geprüft)',
      );
    });

    test('nur noch Kopf, Kopf und Teil des ersten Stücks', () async {
      await r.expectFails(
        three.sublist(0, _head),
        ArchiveFailure.wrongPasswordOrDamaged,
      );
      await r.expectFails(
        three.sublist(0, _head + 10),
        ArchiveFailure.wrongPasswordOrDamaged,
      );
    });

    test('Stücke vertauscht', () async {
      final swapped = _cat([
        three.sublist(0, _head),
        piece(three, 1),
        piece(three, 0),
        piece(three, 2),
      ]);
      await r.expectFails(swapped, ArchiveFailure.wrongPasswordOrDamaged);
      // Letztes Stück an andere Stelle: ebenfalls Fehler.
      final swappedLate = _cat([
        three.sublist(0, _head),
        piece(three, 0),
        piece(three, 2),
        piece(three, 1),
      ]);
      await r.expectFails(swappedLate, ArchiveFailure.damaged);
    });

    test('Stück doppelt', () async {
      final dup = _cat([
        three.sublist(0, _head),
        piece(three, 0),
        piece(three, 0),
        piece(three, 1),
        piece(three, 2),
      ]);
      await r.expectFails(dup, ArchiveFailure.damaged);
      final dupLast = _cat([three, piece(three, 2)]);
      await r.expectFails(dupLast, ArchiveFailure.damaged);
    });

    test('Byte im Kopf: jede Stelle scheitert', () async {
      for (var i = 0; i < _head; i++) {
        final b = Uint8List.fromList(three)..[i] ^= 0x01;
        try {
          await r.open(b);
          fail('Kopfbyte $i wurde akzeptiert');
        } on ArchiveException catch (e) {
          if (i >= 20) {
            expect(e.failure, ArchiveFailure.wrongPasswordOrDamaged);
          }
        }
      }
    });

    test(
      'Byte im Kopf wird auch ohne Salz im Schlüssel erkannt (AAD)',
      () async {
        // Ableitung ignoriert das Salz: Nur die Bindung des Kopfes als AAD kann
        // die Veränderung des Salzes noch auffallen lassen.
        final rig = _Rig(usesSalt: false);
        final file = await rig.seal(_bytes(1000));
        expect(await rig.open(file), _bytes(1000));
        for (var i = 20; i < _head; i++) {
          final b = Uint8List.fromList(file)..[i] ^= 0x01;
          await rig.expectFails(
            b,
            ArchiveFailure.wrongPasswordOrDamaged,
            reason: 'Salzbyte $i',
          );
        }
      },
    );

    test('Byte im Stück: erstes, mittleres, letztes, Tag', () async {
      final spots = {
        'erstes Stück': (_head + 5, ArchiveFailure.wrongPasswordOrDamaged),
        'erster Tag': (
          _head + _sealed - 1,
          ArchiveFailure.wrongPasswordOrDamaged,
        ),
        'mittleres Stück': (_head + _sealed + 9, ArchiveFailure.damaged),
        'letztes Stück': (_head + 2 * _sealed + 3, ArchiveFailure.damaged),
        'letzter Tag': (three.length - 1, ArchiveFailure.damaged),
      };
      for (final e in spots.entries) {
        final b = Uint8List.fromList(three)..[e.value.$1] ^= 0x80;
        await r.expectFails(b, e.value.$2, reason: e.key);
      }
    });

    test('Daten angehängt', () async {
      await r.expectFails(
        _cat([
          three,
          [0],
        ]),
        ArchiveFailure.damaged,
      );
      await r.expectFails(
        _cat([three, List.filled(16, 0)]),
        ArchiveFailure.damaged,
      );
      await r.expectFails(
        _cat([three, piece(three, 0)]),
        ArchiveFailure.damaged,
      );
      // Auch bei einem Archiv mit einem einzigen Stück.
      final one = await r.seal(_bytes(10));
      await r.expectFails(
        _cat([one, List.filled(40, 7)]),
        ArchiveFailure.wrongPasswordOrDamaged,
      );
      await r.expectFails(
        _cat([one, List.filled(_sealed, 7)]),
        ArchiveFailure.wrongPasswordOrDamaged,
      );
    });

    test('Anhängen an volles letztes Stück (Endmarke zählt)', () async {
      final exact = await r.seal(_bytes(_chunk));
      expect(await r.open(exact), _bytes(_chunk));
      await r.expectFails(
        _cat([
          exact,
          [1],
        ]),
        ArchiveFailure.wrongPasswordOrDamaged,
      );
    });

    test('leere Datei, fremde Datei', () async {
      await r.expectFails(Uint8List(0), ArchiveFailure.notAnArchive);
      await r.expectFails(
        Uint8List.fromList('Das ist kein Archiv, nur Text.'.codeUnits),
        ArchiveFailure.notAnArchive,
      );
      await r.expectFails(_bytes(5000, 9), ArchiveFailure.notAnArchive);
      expect(r.kdf.calls, 1, reason: 'nur der Aufbau in setUp hat abgeleitet');
    });

    test('unbekannte Formatversion und Parameter: vor der Ableitung', () async {
      final calls = r.kdf.calls;
      for (final (offset, failure) in [
        (9, ArchiveFailure.unsupportedVersion), // Version 0x0001 -> 0x0000
        (8, ArchiveFailure.unsupportedVersion), // 0x0101
        (11, ArchiveFailure.unsupportedParameters), // Speicher
        (17, ArchiveFailure.unsupportedParameters), // Durchläufe
        (18, ArchiveFailure.unsupportedParameters), // Parallelität
        (19, ArchiveFailure.unsupportedParameters), // Schlüssellänge
      ]) {
        final b = Uint8List.fromList(three)..[offset] ^= 0x01;
        await r.expectFails(b, failure, reason: 'Offset $offset');
      }
      // Riesiger Speicher im Kopf (4 GiB - 1 KiB): nie angefordert.
      final huge = Uint8List.fromList(three)
        ..setRange(10, 14, [255, 255, 255, 255]);
      await r.expectFails(huge, ArchiveFailure.unsupportedParameters);
      expect(r.kdf.calls, calls, reason: 'Ableitung darf nicht laufen');
    });

    test('Leeres letztes Stück nach einem vollen ist ungültig', () async {
      // Gültige Tags, aber gegen die Regel: ein leeres Stück, das nicht das
      // einzige ist (age: nur der leere Klartext hat ein leeres Stück).
      final header = three.sublist(0, _head);
      final key = await r.kdf.deriveKey(
        password: Uint8List.fromList(_password.codeUnits),
        salt: _salt(16),
        params: ArchiveHeader.params,
      );
      final forged = _cat([
        header,
        await r.aead.seal(
          key: key,
          nonce: FramedArchiveCipher.nonceFor(0, last: false),
          aad: header,
          plaintext: _bytes(_chunk),
        ),
        await r.aead.seal(
          key: key,
          nonce: FramedArchiveCipher.nonceFor(1, last: true),
          aad: header,
          plaintext: Uint8List(0),
        ),
      ]);
      await r.expectFails(forged, ArchiveFailure.damaged);
    });

    test(
      'Plaintext früherer Stücke ist nicht gültig, wenn der Strom scheitert',
      () async {
        final cut = three.sublist(0, three.length - 1);
        final got = <Uint8List>[];
        Object? error;
        try {
          await for (final c in r.cipher.decrypt(
            _password,
            _pieces(cut, 4000),
          )) {
            got.add(c);
          }
        } on ArchiveException catch (e) {
          error = e;
        }
        expect(error, isA<ArchiveException>());
        // Vertrag: Der Verbraucher muss das verwerfen; dieser Test hält fest,
        // dass der Fehler den Strom tatsächlich beendet.
        expect(got.length, lessThanOrEqualTo(2));
      },
    );
  });

  test('leerer Klartext: genau ein leeres letztes Stück', () async {
    final r = _Rig();
    final file = await r.seal(Uint8List(0));
    expect(file.length, _head + 16);
    expect(r.aead.sealedNonces.single[11], 1);
    expect(await r.open(file), isEmpty);
  });
}
