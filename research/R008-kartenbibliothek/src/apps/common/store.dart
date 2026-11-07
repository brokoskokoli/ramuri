// R008: verschluesselter Kachel- und Miniaturspeicher (Stellvertreter fuer WP13).
// Jeder Eintrag ist eine Datei: 12 Byte Nonce + AES-256-GCM(Inhalt) + 16 Byte Tag.
// Dateiname = SHA-256 des Schluessels (keine Kachelkoordinaten im Dateisystem).
// Der Schluessel kaeme in der App aus ADR-0003; hier zufaellig je Installation (nur Research).
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class EncStore {
  EncStore(this.dir, this._key, {this.maxBytes = 50 * 1024 * 1024});

  final Directory dir;
  final SecretKey _key;
  final int maxBytes;
  final _aes = AesGcm.with256bits();
  int writes = 0, reads = 0, hits = 0;

  static Future<EncStore> open(Directory dir, {int maxBytes = 50 * 1024 * 1024}) async {
    await dir.create(recursive: true);
    final kf = File('${dir.path}/../r008-research.key'); // nur Research, in der App: ADR-0003
    List<int> k;
    if (await kf.exists()) {
      k = await kf.readAsBytes();
    } else {
      final r = Random.secure();
      k = List<int>.generate(32, (_) => r.nextInt(256));
      await kf.writeAsBytes(k, flush: true);
    }
    return EncStore(dir, SecretKey(k), maxBytes: maxBytes);
  }

  Future<String> _name(String key) async {
    final h = await Sha256().hash(key.codeUnits);
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<File> _file(String key) async => File('${dir.path}/${await _name(key)}.bin');

  Future<Uint8List?> read(String key) async {
    reads++;
    final f = await _file(key);
    if (!await f.exists()) return null;
    final b = await f.readAsBytes();
    final box = SecretBox(b.sublist(12, b.length - 16), nonce: b.sublist(0, 12), mac: Mac(b.sublist(b.length - 16)));
    final clear = await _aes.decrypt(box, secretKey: _key, aad: key.codeUnits);
    hits++;
    await f.setLastAccessed(DateTime.now()).catchError((_) {});
    return Uint8List.fromList(clear);
  }

  Future<void> write(String key, Uint8List bytes) async {
    writes++;
    final box = await _aes.encrypt(bytes, secretKey: _key, aad: key.codeUnits);
    final out = BytesBuilder(copy: false)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    final f = await _file(key);
    await f.writeAsBytes(out.takeBytes(), flush: false);
    if (writes % 20 == 0) await evict();
  }

  Future<bool> exists(String key) async => (await _file(key)).exists();
  Future<void> delete(String key) async {
    final f = await _file(key);
    if (await f.exists()) await f.delete();
  }

  Future<int> size() async {
    var s = 0;
    await for (final e in dir.list()) {
      if (e is File) s += await e.length();
    }
    return s;
  }

  /// Groessengrenze: aelteste (nach letztem Zugriff bzw. Aenderung) zuerst verdraengen.
  Future<void> evict() async {
    final files = <File, FileStat>{};
    await for (final e in dir.list()) {
      if (e is File) files[e] = await e.stat();
    }
    var total = files.values.fold<int>(0, (a, s) => a + s.size);
    if (total <= maxBytes) return;
    final order = files.keys.toList()
      ..sort((a, b) => files[a]!.accessed.compareTo(files[b]!.accessed));
    for (final f in order) {
      if (total <= maxBytes) break;
      total -= files[f]!.size;
      await f.delete();
    }
  }
}
