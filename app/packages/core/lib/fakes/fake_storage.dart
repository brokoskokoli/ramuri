import 'dart:typed_data';

import '../ports/storage.dart';

/// Speicher im Arbeitsspeicher. Der erste Schlüssel legt die "Datei" an.
class FakeStorage implements Storage {
  FakeStorage({this.encryptionActive = true});

  /// `false` simuliert eine Laufzeit ohne aktive Verschlüsselung.
  bool encryptionActive;

  /// Simuliert eine beschädigte Datei.
  bool corrupted = false;

  Uint8List? _fileKey;
  int openSessions = 0;

  @override
  Future<StorageSession> open(Uint8List key) async {
    if (!encryptionActive) {
      throw const StorageException(StorageFailure.encryptionNotActive);
    }
    final fileKey = _fileKey;
    if (corrupted || (fileKey != null && !_same(fileKey, key))) {
      throw const StorageException(StorageFailure.unreadable);
    }
    _fileKey ??= Uint8List.fromList(key);
    openSessions++;
    return _FakeSession(this);
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _FakeSession implements StorageSession {
  _FakeSession(this._owner);

  final FakeStorage _owner;
  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _owner.openSessions--;
  }
}
