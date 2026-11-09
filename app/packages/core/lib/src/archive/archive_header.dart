import 'dart:typed_data';

import '../../ports/archive_cipher.dart';

/// Kopf des Archivs, Formatversion 1 oder 2 (`docs/contracts/archive.md`,
/// Abschnitt 2). Beide haben dieselben Parameter; der Schreiber erzeugt 2.
class ArchiveHeader {
  ArchiveHeader(this.salt, {this.format = formatVersion}) {
    if (!supportedFormats.contains(format)) {
      throw ArgumentError('Formatversion unbekannt');
    }
    if (salt.length != saltLength) {
      throw ArgumentError('Salz muss $saltLength Byte lang sein');
    }
  }

  static const int length = 36;
  static const int saltLength = 16;
  static const int formatVersion = 2;
  static const List<int> supportedFormats = [1, 2];
  static const List<int> magic = [
    0x52, 0x55, 0x4E, 0x41, 0x52, 0x43, 0x48, 0x56, // RUNARCHV
  ];

  /// Die einzigen Parameter der Formatversionen 1 und 2: 64 MiB, 3, 1, 32 Byte.
  static const ArchiveKdfParams params = ArchiveKdfParams(
    memoryKib: 65536,
    iterations: 3,
    parallelism: 1,
    keyLength: 32,
  );

  final Uint8List salt;

  /// Formatversion des Kopfes (1 oder 2).
  final int format;

  /// Die 36 Byte; zugleich die zusätzlich authentifizierten Daten jedes
  /// Stücks.
  Uint8List encode() {
    final out = Uint8List(length);
    final d = ByteData.sublistView(out);
    out.setRange(0, 8, magic);
    d.setUint16(8, format);
    d.setUint32(10, params.memoryKib);
    d.setUint32(14, params.iterations);
    d.setUint8(18, params.parallelism);
    d.setUint8(19, params.keyLength);
    out.setRange(20, length, salt);
    return out;
  }

  /// Liest [bytes] (die ersten bis zu 36 Byte der Datei) in der Reihenfolge der
  /// Leser-Regeln des Vertrags; wirft [ArchiveException]. Läuft vor jeder
  /// Schlüsselableitung.
  static ArchiveHeader parse(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const ArchiveException(ArchiveFailure.notAnArchive);
    }
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != magic[i]) {
        throw const ArchiveException(ArchiveFailure.notAnArchive);
      }
    }
    if (bytes.length < 10) {
      throw const ArchiveException(ArchiveFailure.unsupportedVersion);
    }
    final d = ByteData.sublistView(bytes);
    final format = d.getUint16(8);
    if (!supportedFormats.contains(format)) {
      throw const ArchiveException(ArchiveFailure.unsupportedVersion);
    }
    if (bytes.length < length) {
      throw const ArchiveException(ArchiveFailure.damaged);
    }
    if (d.getUint32(10) != params.memoryKib ||
        d.getUint32(14) != params.iterations ||
        d.getUint8(18) != params.parallelism ||
        d.getUint8(19) != params.keyLength) {
      throw const ArchiveException(ArchiveFailure.unsupportedParameters);
    }
    return ArchiveHeader(
      Uint8List.fromList(bytes.sublist(20, length)),
      format: format,
    );
  }
}
