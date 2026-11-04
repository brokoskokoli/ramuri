import 'dart:typed_data';

enum StorageFailure {
  /// Verschlüsselung ist nicht aktiv; die Datei wird nicht geöffnet (ADR-0003).
  encryptionNotActive,

  /// Schlüssel passt nicht oder Datei ist unlesbar (OQ-0062).
  unreadable,
}

class StorageException implements Exception {
  const StorageException(this.failure);

  final StorageFailure failure;

  @override
  String toString() => 'StorageException($failure)';
}

/// Offene Verbindung zum Speicher. Inhalte (Läufe, Werte) legt WP02 fest.
abstract interface class StorageSession {
  Future<void> close();
}

/// Port: Speicher. Bewusst dünn: kein SQL, keine Tabellen.
abstract interface class Storage {
  /// Öffnet den Speicher mit dem Schlüssel; wirft [StorageException].
  Future<StorageSession> open(Uint8List key);
}
