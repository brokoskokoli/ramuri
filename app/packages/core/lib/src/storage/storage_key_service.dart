import 'dart:typed_data';

import '../../ports/key_store.dart';

/// Länge des Datenbankschlüssels in Byte (ADR-0003 Punkt 2).
const int storageKeyLength = 32;

/// Name des Datenbankschlüssels in der Schlüsselablage.
const String storageKeyName = 'database_key_v1';

/// Ergebnis der Startentscheidung (ADR-0003, OQ-0062).
sealed class StorageStart {
  const StorageStart();
}

/// Schlüssel und Datei sind da: die Datei mit [key] öffnen.
final class OpenExistingStorage extends StorageStart {
  const OpenExistingStorage(this.key);

  final Uint8List key;
}

/// Keine Datei vorhanden: mit [key] neu anlegen. Der Schlüssel liegt schon in
/// der Ablage.
final class CreateNewStorage extends StorageStart {
  const CreateNewStorage(this.key);

  final Uint8List key;
}

enum StorageNotOpenableReason {
  /// Eine Datei existiert, der Schlüssel fehlt in der Ablage.
  keyMissing,

  /// Eine Datei existiert, der abgelegte Schlüssel hat nicht 32 Byte.
  keyMalformed,
}

/// Es gibt eine Datei, aber keinen brauchbaren Schlüssel. Weder Schlüssel noch
/// Datei wurden verändert; nur der Nutzer darf das auflösen (Teil D).
final class StorageNotOpenable extends StorageStart {
  const StorageNotOpenable(this.reason);

  final StorageNotOpenableReason reason;
}

/// Entscheidet aus Schlüsselablage und Dateizustand, ob geöffnet, neu angelegt
/// oder nicht geöffnet wird. Rein und ohne Plattform: Ablage und Dateiprüfung
/// kommen von außen.
///
/// Regeln: Ein neuer Schlüssel entsteht nur, wenn keine Datei (weder `db`
/// noch `-wal` noch `-shm`) existiert. Ein vorhandener Schlüssel wird nie
/// überschrieben, wenn eine Datei da ist. Eine [KeyStoreException] führt nie
/// zum Neuanlegen, sie wird weitergereicht.
class StorageKeyService {
  StorageKeyService({
    required this.keyStore,
    required this.databaseFilesExist,
    required this.generateKey,
  });

  final KeyStore keyStore;

  /// `true`, wenn `db`, `-wal` oder `-shm` existiert.
  final Future<bool> Function() databaseFilesExist;

  /// Liefert [storageKeyLength] zufällige Byte aus einer sicheren Quelle.
  final Uint8List Function() generateKey;

  Future<StorageStart> decide() async {
    // Zuerst die Ablage lesen: Ein Fehler hier bricht ab, bevor irgendetwas
    // angelegt wird.
    final stored = await keyStore.read(storageKeyName);
    final filesExist = await databaseFilesExist();

    if (stored != null && stored.length == storageKeyLength) {
      return filesExist
          ? OpenExistingStorage(stored)
          : CreateNewStorage(stored);
    }
    if (filesExist) {
      return StorageNotOpenable(
        stored == null
            ? StorageNotOpenableReason.keyMissing
            : StorageNotOpenableReason.keyMalformed,
      );
    }

    // Keine Datei: Ein fehlender oder unbrauchbarer Schlüssel schützt nichts.
    final key = generateKey();
    if (key.length != storageKeyLength) {
      throw StateError(
        'Schlüsselerzeugung lieferte nicht $storageKeyLength Byte',
      );
    }
    await keyStore.write(storageKeyName, key);
    // Zurücklesen: Die Ablage muss den Schlüssel wirklich halten, bevor die
    // Datei entsteht.
    final back = await keyStore.read(storageKeyName);
    if (back == null || !_same(back, key)) {
      throw const KeyStoreException(
        'Schlüssel nach dem Schreiben nicht lesbar',
      );
    }
    return CreateNewStorage(key);
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
