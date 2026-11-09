import 'dart:typed_data';

import 'package:core/core.dart';

import '../storage/database_files.dart';
import '../storage/encrypted_storage.dart';
import '../storage/random_key.dart';
import 'drift_archive_sink.dart';

/// Prüft ein Archiv vollständig, ohne die aktive Datenbank zu berühren
/// (SEC-0009: erst prüfen, dann die alte Datei löschen). Anders als ein
/// reines Verwerfen schreibt die Prüfung in eine echte Zwischendatenbank
/// ([files], `importPath`), damit auch alle Beschränkungen der Datenbank
/// (CHECK, Fremdschlüssel, Trigger, Eindeutigkeit, `foreign_key_check`)
/// greifen, die der spätere Dienst anwendet. Der Schlüssel ist flüchtig
/// ([generateStorageKey] oder [key]), wird nie gespeichert; die Zwischendatei
/// wird auf jedem Weg gelöscht. Wirft [ArchiveImportException].
Future<void> verifyArchive({
  required String path,
  required String password,
  required FileDatabaseFiles files,
  required ArchiveCipherFactory cipherFactory,
  required Clock clock,
  ArchiveCancel? cancel,
  Uint8List Function()? key,
}) async {
  final throwaway = (key ?? (() => generateStorageKey()))();
  try {
    await ArchiveImporter(
      sink: DriftArchiveSink(
        storage: EncryptedStorage(files.importPath),
        key: () => throwaway,
        files: files,
      ),
      cipherFactory: cipherFactory,
      clock: clock,
    ).import(path: path, password: password, cancel: cancel);
  } finally {
    await files.deleteImport();
  }
}
