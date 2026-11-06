import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// [KeyStore] auf `flutter_secure_storage` (ADR-0003 Punkt 2).
///
/// `resetOnError` ist ausdrücklich aus: Der Standard des Plugins (true) würde
/// bei einem Lese- oder Schlüsselfehler den abgelegten Schlüssel still löschen
/// und so die Datenbank unlesbar machen, ohne dass der Nutzer gefragt wird.
class SecureKeyStore implements KeyStore {
  SecureKeyStore([FlutterSecureStorage? storage])
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: androidOptions);

  /// Eingestellt wie beschrieben; ein Test hält das fest.
  static const AndroidOptions androidOptions = AndroidOptions(
    resetOnError: false,
  );

  final FlutterSecureStorage _storage;

  @override
  Future<Uint8List?> read(String name) async {
    final String? v;
    try {
      v = await _storage.read(key: name);
    } catch (_) {
      throw const KeyStoreException(
        'Lesen aus der Schlüsselablage fehlgeschlagen',
      );
    }
    if (v == null) return null;
    try {
      return base64Decode(v);
    } on FormatException {
      throw const KeyStoreException('Abgelegter Schlüssel nicht lesbar');
    }
  }

  @override
  Future<void> write(String name, Uint8List value) async {
    try {
      await _storage.write(key: name, value: base64Encode(value));
    } catch (_) {
      throw const KeyStoreException(
        'Schreiben in die Schlüsselablage fehlgeschlagen',
      );
    }
  }

  @override
  Future<void> delete(String name) async {
    try {
      await _storage.delete(key: name);
    } catch (_) {
      throw const KeyStoreException(
        'Löschen in der Schlüsselablage fehlgeschlagen',
      );
    }
  }
}
