import 'dart:typed_data';

import '../ports/archive_cipher.dart';

/// Schlüsselableitung für Tests: schnell, deterministisch, **nicht sicher**.
class FakeArchiveKdf implements ArchiveKdf {
  /// Mit `false` hängt der Schlüssel nur vom Passwort ab, nicht vom Salz
  /// (damit Tests die Kopfbindung des Rahmens unabhängig vom Salz prüfen).
  FakeArchiveKdf({this.usesSalt = true});

  final bool usesSalt;

  /// Aufrufe von [deriveKey].
  int calls = 0;

  /// Parameter des letzten Aufrufs.
  ArchiveKdfParams? lastParams;

  @override
  Future<Uint8List> deriveKey({
    required Uint8List password,
    required Uint8List salt,
    required ArchiveKdfParams params,
  }) async {
    calls++;
    lastParams = params;
    final h = _Mix()
      ..add(password)
      ..add(usesSalt ? salt : Uint8List(0));
    return h.bytes(params.keyLength);
  }
}

/// Stück-Verschlüsselung für Tests: Tag und Strom hängen von Schlüssel, Nonce,
/// AAD und Chiffretext ab, **nicht sicher**. Merkt sich Nonce und AAD.
class FakeChunkAead implements ChunkAead {
  /// Nonces und AAD aller [seal]-Aufrufe in Reihenfolge.
  final List<Uint8List> sealedNonces = [];
  final List<Uint8List> sealedAads = [];

  /// Nonces und AAD aller [open]-Aufrufe.
  final List<Uint8List> openedNonces = [];
  final List<Uint8List> openedAads = [];

  static Uint8List _stream(Uint8List key, Uint8List nonce, int length) {
    final h = _Mix()
      ..add(key)
      ..add(nonce);
    return h.bytes(length);
  }

  static Uint8List _tag(
    Uint8List key,
    Uint8List nonce,
    Uint8List aad,
    Uint8List cipher,
  ) {
    final h = _Mix(seed: 7)
      ..add(key)
      ..add(nonce)
      ..add(aad)
      ..add(cipher);
    return h.bytes(16);
  }

  @override
  Future<Uint8List> seal({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List plaintext,
  }) async {
    sealedNonces.add(Uint8List.fromList(nonce));
    sealedAads.add(Uint8List.fromList(aad));
    final ks = _stream(key, nonce, plaintext.length);
    final out = Uint8List(plaintext.length + 16);
    for (var i = 0; i < plaintext.length; i++) {
      out[i] = plaintext[i] ^ ks[i];
    }
    out.setRange(
      plaintext.length,
      out.length,
      _tag(key, nonce, aad, Uint8List.sublistView(out, 0, plaintext.length)),
    );
    return out;
  }

  @override
  Future<Uint8List?> open({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List aad,
    required Uint8List sealed,
  }) async {
    openedNonces.add(Uint8List.fromList(nonce));
    openedAads.add(Uint8List.fromList(aad));
    if (sealed.length < 16) return null;
    final n = sealed.length - 16;
    final cipher = Uint8List.sublistView(sealed, 0, n);
    final tag = _tag(key, nonce, aad, cipher);
    var diff = 0;
    for (var i = 0; i < 16; i++) {
      diff |= tag[i] ^ sealed[n + i];
    }
    if (diff != 0) return null;
    final ks = _stream(key, nonce, n);
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = cipher[i] ^ ks[i];
    }
    return out;
  }
}

/// Einfache 32-Bit-FNV-Mischung mit vier Bahnen (nur für die Fakes).
class _Mix {
  _Mix({int seed = 0})
    : _h = [
        0x811C9DC5 ^ seed,
        0x01000193 ^ seed,
        0xDEADBEEF ^ seed,
        0x12345678 ^ seed,
      ];

  final List<int> _h;
  int _n = 0;

  void add(Uint8List data) {
    for (final b in data) {
      final i = _n++ & 3;
      _h[i] = ((_h[i] ^ b) * 16777619) & 0xFFFFFFFF;
      _h[(i + 1) & 3] = (_h[(i + 1) & 3] + _h[i] + 0x9E3779B9) & 0xFFFFFFFF;
    }
    // Trennt die Eingaben, damit (a‖b) nicht gleich (a'‖b') mit anderer
    // Grenze wird.
    for (var i = 0; i < 4; i++) {
      _h[i] = ((_h[i] ^ data.length) * 16777619) & 0xFFFFFFFF;
    }
  }

  Uint8List bytes(int length) {
    final out = Uint8List(length);
    var state = List<int>.of(_h);
    for (var i = 0; i < length; i++) {
      final k = i & 3;
      state[k] =
          ((state[k] ^ (i + 1)) * 16777619 + state[(k + 1) & 3]) & 0xFFFFFFFF;
      out[i] = (state[k] >> ((i >> 2) & 3) * 8 ^ state[k] >> 13) & 0xFF;
    }
    return out;
  }
}
