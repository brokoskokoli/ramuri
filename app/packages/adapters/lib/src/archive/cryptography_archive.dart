import 'dart:math';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Argon2id (`DartArgon2id` aus `cryptography` 2.9.0, ADR-0008) in einem
/// eigenen Isolate, damit die Oberfläche nicht stockt. Rechnet nur mit den
/// Parametern, die der Aufrufer nennt; die Formatversion legt fest, welche das
/// sind (Kopfprüfung in `ArchiveHeader`).
class CryptographyArchiveKdf implements ArchiveKdf {
  CryptographyArchiveKdf({this.offload = isolateOffloadAsync});

  /// Wo gerechnet wird; Tests dürfen [inlineOffloadAsync] nehmen.
  final OffloadAsync offload;

  @override
  Future<Uint8List> deriveKey({
    required Uint8List password,
    required Uint8List salt,
    required ArchiveKdfParams params,
  }) => offload<_KdfJob, Uint8List>(
    _deriveInIsolate,
    _KdfJob(password, salt, params),
  );
}

class _KdfJob {
  const _KdfJob(this.password, this.salt, this.params);

  final Uint8List password;
  final Uint8List salt;
  final ArchiveKdfParams params;
}

/// Läuft im Isolate (Top-Level-Funktion, rein, ohne Zugriff auf Speicher).
Future<Uint8List> _deriveInIsolate(_KdfJob job) async {
  final argon = DartArgon2id(
    memory: job.params.memoryKib,
    iterations: job.params.iterations,
    parallelism: job.params.parallelism,
    hashLength: job.params.keyLength,
    // Genau eine Bahn (Parallelität 1): keine weiteren Isolates.
    maxIsolates: 1,
  );
  final key = await argon.deriveKey(
    secretKey: SecretKey(job.password),
    nonce: job.salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// ChaCha20-Poly1305 (`DartChacha20.poly1305Aead` aus `cryptography` 2.9.0)
/// für ein Stück. Nonce, AAD und Schlüssel bestimmt der Rahmen in `core`.
class CryptographyChunkAead implements ChunkAead {
  CryptographyChunkAead();

  static const DartChacha20 _cipher = DartChacha20.poly1305Aead();

  @override
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plaintext,
  }) async {
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final out = Uint8List(box.cipherText.length + box.mac.bytes.length);
    out.setRange(0, box.cipherText.length, box.cipherText);
    out.setRange(box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  @override
  Future<Uint8List?> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  }) async {
    const tag = 16;
    if (sealed.length < tag) return null;
    final split = sealed.length - tag;
    try {
      final clear = await _cipher.decrypt(
        SecretBox(
          Uint8List.sublistView(sealed, 0, split),
          nonce: nonce,
          mac: Mac(Uint8List.sublistView(sealed, split)),
        ),
        secretKey: SecretKey(key),
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      return null;
    }
  }
}

/// Zufallsbytes aus der sicheren Quelle des Systems (für das Salz).
Uint8List secureRandomBytes(int length) {
  final r = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => r.nextInt(256)));
}

/// Fertig verdrahteter [ArchiveCipher]: Rahmen aus `core`, Kryptografie aus
/// `cryptography`, Ableitung im eigenen Isolate.
ArchiveCipher createArchiveCipher({
  OffloadAsync offload = isolateOffloadAsync,
  Uint8List Function(int length) randomBytes = secureRandomBytes,
}) => FramedArchiveCipher(
  kdf: CryptographyArchiveKdf(offload: offload),
  aead: CryptographyChunkAead(),
  randomBytes: randomBytes,
);

/// Cipher für das Arbeits-Isolate des Exports: Top-Level-Funktion (als
/// `ArchiveCipherFactory` sendbar), Ableitung im selben Isolate.
ArchiveCipher createArchiveCipherInWorker() =>
    createArchiveCipher(offload: inlineOffloadAsync);
