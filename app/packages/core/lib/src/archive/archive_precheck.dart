import 'dart:io';
import 'dart:typed_data';

import '../../ports/archive_cipher.dart';
import 'archive_errors.dart';
import 'archive_header.dart';
import 'archive_reader.dart';

/// Vorprüfung des unverschlüsselten Kopfes (FR-0198): wendet die Leser-Regeln
/// 1 bis 4 aus `docs/contracts/archive.md`, Abschnitt 2, auf [start] an (die
/// ersten bis zu 36 Byte der Datei). Wirft [ArchiveImportException] mit
/// `notAnArchive`, `unsupportedVersion`, `damaged` (zu kurz) oder
/// `unsupportedParameters`. Ersetzt nicht die vollständige Prüfung beim
/// Einlesen; der Kopf enthält keine Geheimnisse (SEC-0011).
void precheckArchiveHeader(Uint8List start) {
  try {
    ArchiveHeader.parse(start);
  } on ArchiveException catch (e) {
    throw ArchiveImportException(archiveImportFailureOf(e.failure));
  }
}

/// Liest nur die ersten 36 Byte der Datei [path] und prüft sie mit
/// [precheckArchiveHeader], bevor nach dem Passwort gefragt wird. Ändert
/// nichts. Wirft [ArchiveImportException]; ist die Datei nicht lesbar,
/// `readFailed`.
Future<void> precheckArchiveFile(String path) async {
  final Uint8List start;
  RandomAccessFile? file;
  try {
    file = await File(path).open();
    start = await _readUpTo(file, ArchiveHeader.length);
  } on FileSystemException {
    throw const ArchiveImportException(ArchiveImportFailure.readFailed);
  } finally {
    try {
      await file?.close();
    } on FileSystemException {
      // Schließen nach dem Lesen: ohne Folgen für die Prüfung.
    }
  }
  precheckArchiveHeader(start);
}

/// Liest bis zu [length] Byte; `read` darf weniger liefern als verlangt.
Future<Uint8List> _readUpTo(RandomAccessFile file, int length) async {
  final out = BytesBuilder(copy: false);
  while (out.length < length) {
    final chunk = await file.read(length - out.length);
    if (chunk.isEmpty) break;
    out.add(chunk);
  }
  return out.takeBytes();
}
