import 'dart:typed_data';

import '../ports/key_store.dart';

class FakeKeyStore implements KeyStore {
  final _data = <String, Uint8List>{};

  /// Wenn gesetzt, wirft jeder Zugriff [KeyStoreException].
  String? failWith;

  void _check() {
    final m = failWith;
    if (m != null) throw KeyStoreException(m);
  }

  @override
  Future<Uint8List?> read(String name) async {
    _check();
    final v = _data[name];
    return v == null ? null : Uint8List.fromList(v);
  }

  @override
  Future<void> write(String name, Uint8List value) async {
    _check();
    _data[name] = Uint8List.fromList(value);
  }

  @override
  Future<void> delete(String name) async {
    _check();
    _data.remove(name);
  }
}
