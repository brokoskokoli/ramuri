import 'dart:typed_data';

/// Warum ein Archiv nicht gelesen werden konnte. Die Fehler tragen nie
/// Inhalte, Zeilenzahlen oder das Passwort (SEC-0011, SEC-0010).
enum ArchiveFailure {
  /// Keine Archivdatei (Magic fehlt oder die Datei ist zu kurz dafür).
  notAnArchive,

  /// Formatversion unbekannt (auch neuere): nichts wird geändert (ADR-0008 C).
  unsupportedVersion,

  /// Die Parameter im Kopf weichen von denen der Formatversion ab.
  unsupportedParameters,

  /// Das erste Stück ist nicht lesbar: falsches Passwort oder beschädigter
  /// Anfang; beides ist technisch nicht unterscheidbar (ADR-0008 Punkt 5).
  wrongPasswordOrDamaged,

  /// Die Datei ist ab dem zweiten Stück beschädigt, abgeschnitten, hat
  /// Stücke vertauscht, doppelt oder Bytes angehängt.
  damaged,
}

/// Ausnahme des Archivs. Der Text nennt nur die Art, nie Inhalte.
class ArchiveException implements Exception {
  const ArchiveException(this.failure);

  final ArchiveFailure failure;

  @override
  String toString() => 'ArchiveException(${failure.name})';
}

/// Port: Archiv als Strom ver- und entschlüsseln (`docs/contracts/archive.md`).
///
/// [decrypt] liefert Klartext schon, bevor das letzte Stück geprüft ist. Wer
/// den Strom verbraucht, muss sein Ergebnis verwerfen, wenn der Strom mit
/// einem Fehler endet (Tausch erst nach dem gültigen letzten Stück).
abstract interface class ArchiveCipher {
  /// Verschlüsselt [plaintext] mit [password]; der erste Wert des Stroms ist
  /// der Kopf. Fehler: Ausnahmen des Adapters, nie mit dem Passwort im Text.
  Stream<Uint8List> encrypt(String password, Stream<List<int>> plaintext);

  /// Entschlüsselt [archive]. Wirft [ArchiveException] als Stromfehler.
  Stream<Uint8List> decrypt(String password, Stream<List<int>> archive);
}

/// Argon2id-Parameter einer Formatversion (Speicher in KiB).
class ArchiveKdfParams {
  const ArchiveKdfParams({
    required this.memoryKib,
    required this.iterations,
    required this.parallelism,
    required this.keyLength,
  });

  final int memoryKib;
  final int iterations;
  final int parallelism;
  final int keyLength;
}

/// Port: Schlüsselableitung (Argon2id). Rechnet schwer; Adapter laufen in
/// einem eigenen Isolate.
abstract interface class ArchiveKdf {
  /// Leitet aus den UTF-8-Bytes des Passworts und dem [salt] einen Schlüssel
  /// von `params.keyLength` Byte ab.
  Future<Uint8List> deriveKey({
    required Uint8List password,
    required Uint8List salt,
    required ArchiveKdfParams params,
  });
}

/// Port: ChaCha20-Poly1305 (RFC 8439) für ein Stück.
abstract interface class ChunkAead {
  /// Liefert `Chiffretext ‖ Tag (16 Byte)`.
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plaintext,
  });

  /// Liefert den Klartext oder `null`, wenn der Tag nicht stimmt (oder
  /// [sealed] kürzer als 16 Byte ist).
  Future<Uint8List?> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  });
}
