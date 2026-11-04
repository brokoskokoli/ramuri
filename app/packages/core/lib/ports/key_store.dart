import 'dart:typed_data';

/// Zugriff auf die Schlüsselablage ist fehlgeschlagen (z. B. Keystore-Fehler).
class KeyStoreException implements Exception {
  const KeyStoreException(this.message);

  final String message;

  @override
  String toString() => 'KeyStoreException: $message';
}

/// Port: Schlüsselablage (ADR-0003 Punkt 2). Wirft [KeyStoreException].
abstract interface class KeyStore {
  /// `null`, wenn unter [name] nichts liegt.
  Future<Uint8List?> read(String name);

  Future<void> write(String name, Uint8List value);

  Future<void> delete(String name);
}
