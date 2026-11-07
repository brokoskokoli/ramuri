import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

void main() {
  final salt = Uint8List.fromList(List.generate(16, (i) => 0xA0 + i));

  test('Layout: Offsets, Big-Endian, feste Werte der Formatversion 1', () {
    final bytes = ArchiveHeader(salt).encode();
    expect(bytes, <int>[
      // 0: Magic RUNARCHV
      0x52, 0x55, 0x4E, 0x41, 0x52, 0x43, 0x48, 0x56,
      // 8: Formatversion 1
      0x00, 0x01,
      // 10: Speicher 65536 KiB
      0x00, 0x01, 0x00, 0x00,
      // 14: Durchläufe 3
      0x00, 0x00, 0x00, 0x03,
      // 18: Parallelität 1, 19: Schlüssellänge 32
      0x01, 0x20,
      // 20: Salz
      ...salt,
    ]);
    expect(bytes.length, ArchiveHeader.length);
  });

  test('Rundgang', () {
    final parsed = ArchiveHeader.parse(ArchiveHeader(salt).encode());
    expect(parsed.salt, salt);
  });

  test('Anhängsel nach dem Kopf stört das Lesen des Kopfes nicht', () {
    final withTail = Uint8List.fromList([
      ...ArchiveHeader(salt).encode(),
      1,
      2,
      3,
    ]);
    expect(ArchiveHeader.parse(withTail).salt, salt);
  });

  ArchiveFailure failureOf(Uint8List bytes) {
    try {
      ArchiveHeader.parse(bytes);
    } on ArchiveException catch (e) {
      return e.failure;
    }
    fail('kein Fehler');
  }

  test('Magic, Version, Parameter, Länge: Fehlerart je Offset', () {
    final good = ArchiveHeader(salt).encode();
    for (var i = 0; i < 8; i++) {
      final b = Uint8List.fromList(good)..[i] ^= 1;
      expect(failureOf(b), ArchiveFailure.notAnArchive, reason: 'Offset $i');
    }
    for (var i = 8; i < 10; i++) {
      final b = Uint8List.fromList(good)..[i] ^= 1;
      expect(
        failureOf(b),
        ArchiveFailure.unsupportedVersion,
        reason: 'Offset $i',
      );
    }
    for (var i = 10; i < 20; i++) {
      final b = Uint8List.fromList(good)..[i] ^= 1;
      expect(
        failureOf(b),
        ArchiveFailure.unsupportedParameters,
        reason: 'Offset $i',
      );
    }
    // Auch jede Länge unter 36 Byte scheitert, nach der Art der Lücke.
    expect(failureOf(Uint8List(0)), ArchiveFailure.notAnArchive);
    expect(failureOf(good.sublist(0, 7)), ArchiveFailure.notAnArchive);
    expect(failureOf(good.sublist(0, 9)), ArchiveFailure.unsupportedVersion);
    for (var n = 10; n < 36; n++) {
      expect(failureOf(good.sublist(0, n)), ArchiveFailure.damaged);
    }
  });

  test('Der Fehler nennt nur die Art', () {
    expect(
      const ArchiveException(ArchiveFailure.damaged).toString(),
      'ArchiveException(damaged)',
    );
  });
}
