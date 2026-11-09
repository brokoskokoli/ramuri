import 'dart:convert';
import 'dart:typed_data';

import '../../ports/archive_cipher.dart';
import 'archive_header.dart';

/// Rahmen des Archivs: Kopf plus STREAM-Stücke wie age v1 (ChaCha20-Poly1305,
/// 64-KiB-Klartextstücke, Nonce = 11-Byte-Zähler + Endbyte, Kopf als AAD),
/// siehe `docs/contracts/archive.md`, Abschnitt 3. Die Kryptografie liegt
/// hinter [ArchiveKdf] und [ChunkAead], der Rahmen ist reiner Dart-Code.
class FramedArchiveCipher implements ArchiveCipher {
  FramedArchiveCipher({
    required this._kdf,
    required this._aead,
    required Uint8List Function(int length) randomBytes,
    int headerFormat = ArchiveHeader.formatVersion,
  }) : _random = randomBytes,
       _format = headerFormat;

  /// Klartext je Stück.
  static const int chunkSize = 65536;

  /// Länge des Authentifizierungs-Tags.
  static const int tagLength = 16;

  static const int _sealedChunk = chunkSize + tagLength;

  final ArchiveKdf _kdf;
  final ChunkAead _aead;
  final Uint8List Function(int length) _random;

  /// Formatversion, die [encrypt] in den Kopf schreibt (Tests für Format 1).
  final int _format;

  /// Nonce des Stücks [index]: 11 Byte Zähler (Big-Endian), dann `0x01` nur
  /// beim letzten Stück.
  static Uint8List nonceFor(int index, {required bool last}) {
    final nonce = Uint8List(12);
    ByteData.sublistView(nonce).setUint64(3, index);
    nonce[11] = last ? 1 : 0;
    return nonce;
  }

  static Uint8List _concat(Uint8List a, List<int> b) {
    if (a.isEmpty && b is Uint8List) return b;
    final out = Uint8List(a.length + b.length);
    out.setRange(0, a.length, a);
    out.setRange(a.length, out.length, b);
    return out;
  }

  @override
  Stream<Uint8List> encrypt(
    String password,
    Stream<List<int>> plaintext,
  ) async* {
    final salt = _random(ArchiveHeader.saltLength);
    final header = ArchiveHeader(Uint8List.fromList(salt), format: _format);
    final aad = header.encode();
    final key = await _kdf.deriveKey(
      password: Uint8List.fromList(utf8.encode(password)),
      salt: header.salt,
      params: ArchiveHeader.params,
    );
    try {
      yield aad;
      var index = 0;
      var pending = Uint8List(0);
      await for (final data in plaintext) {
        pending = _concat(pending, data);
        var offset = 0;
        // Ein Stück wird erst geschrieben, wenn danach noch Daten da sind:
        // Das letzte Stück ist nie leer (außer beim leeren Klartext).
        while (pending.length - offset > chunkSize) {
          yield await _aead.seal(
            key: key,
            nonce: nonceFor(index++, last: false),
            aad: aad,
            plaintext: Uint8List.sublistView(
              pending,
              offset,
              offset + chunkSize,
            ),
          );
          offset += chunkSize;
        }
        pending = pending.sublist(offset);
      }
      yield await _aead.seal(
        key: key,
        nonce: nonceFor(index, last: true),
        aad: aad,
        plaintext: pending,
      );
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  @override
  Stream<Uint8List> decrypt(String password, Stream<List<int>> archive) async* {
    var pending = Uint8List(0);
    Uint8List? aad;
    Uint8List? key;
    var index = 0;
    try {
      await for (final data in archive) {
        pending = _concat(pending, data);
        if (aad == null) {
          if (pending.length < ArchiveHeader.length) continue;
          final header = ArchiveHeader.parse(pending);
          aad = pending.sublist(0, ArchiveHeader.length);
          pending = pending.sublist(ArchiveHeader.length);
          key = await _kdf.deriveKey(
            password: Uint8List.fromList(utf8.encode(password)),
            salt: header.salt,
            params: ArchiveHeader.params,
          );
        }
        var offset = 0;
        // Folgen nach einem vollen Stück noch Byte, ist es nicht das letzte.
        while (pending.length - offset > _sealedChunk) {
          final plain = await _open(
            key!,
            aad,
            index++,
            false,
            Uint8List.sublistView(pending, offset, offset + _sealedChunk),
          );
          offset += _sealedChunk;
          yield plain;
        }
        if (offset > 0) pending = pending.sublist(offset);
      }
      if (aad == null) {
        // Strom endete vor einem vollständigen Kopf.
        ArchiveHeader.parse(pending);
        throw const ArchiveException(ArchiveFailure.damaged);
      }
      final last = await _open(key!, aad, index, true, pending);
      if (index > 0 && last.isEmpty) {
        throw const ArchiveException(ArchiveFailure.damaged);
      }
      yield last;
    } finally {
      key?.fillRange(0, key.length, 0);
    }
  }

  Future<Uint8List> _open(
    Uint8List key,
    Uint8List aad,
    int index,
    bool last,
    Uint8List sealed,
  ) async {
    final plain = sealed.length < tagLength
        ? null
        : await _aead.open(
            key: key,
            nonce: nonceFor(index, last: last),
            aad: aad,
            sealed: sealed,
          );
    if (plain == null) {
      throw ArchiveException(
        index == 0
            ? ArchiveFailure.wrongPasswordOrDamaged
            : ArchiveFailure.damaged,
      );
    }
    return plain;
  }
}
