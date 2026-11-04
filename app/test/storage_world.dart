import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:running_app/features/storage/storage_start.dart';

Uint8List keyOf(int seed) =>
    Uint8List.fromList(List.generate(32, (i) => (i * 5 + seed) % 256));

bool sameBytes(Uint8List? a, Uint8List b) {
  if (a == null || a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Verbindet Datei-Fake und Speicher-Fake: Öffnen legt die "Datei" an,
/// Löschen der Dateien leert den Speicher. Jede verändernde Operation läuft
/// durch [step]: Dort wird ein Abbruch eingespielt und die Regel geprüft, dass
/// nie ein neuer Schlüssel neben der alten Datei liegt.
class World {
  World() {
    files = WorldFiles(this);
    keys = WorldKeys(this);
    storage = WorldStorage(this);
  }

  late final WorldFiles files;
  late final WorldKeys keys;
  late final WorldStorage storage;
  FakeStorage inner = FakeStorage();

  /// Fehler beim Öffnen der neuen Datei nach dem Löschen (Neubeginn).
  StorageFailure? openFailureAfterDelete;

  /// Schlüssel der alten Datei, solange sie liegt.
  Uint8List? oldFileKey;

  /// Soll beim n-ten verändernden Schritt (ab 1) abgebrochen werden.
  int? crashAt;
  int steps = 0;
  final List<String> log = [];
  final List<String> violations = [];

  Future<void> step(String name) async {
    steps++;
    if (crashAt == steps) {
      log.add('ABBRUCH vor $name');
      throw StateError('Abbruch vor $name');
    }
    log.add(name);
  }

  /// Regel: Liegt die alte Datei noch, darf der abgelegte Schlüssel nur der
  /// ursprüngliche oder keiner sein.
  void check() {
    final stored = keys.store;
    if (files.present && oldFileKey != null) {
      final k = stored[storageKeyName];
      final o = originalStoredKey;
      if (k != null && (o == null || !sameBytes(k, o))) {
        violations.add('neuer Schlüssel neben alter Datei: $log');
      }
    }
  }

  Uint8List? originalStoredKey;

  /// Datei mit Inhalt unter [fileKey]; abgelegt wird [storedKey] (oder keiner).
  Future<void> seed({required Uint8List fileKey, Uint8List? storedKey}) async {
    final s = await inner.open(fileKey);
    await s.runs.create(startedAt: DateTime.utc(2030));
    await s.settings.set('k', 'v', at: DateTime.utc(2030));
    files.present = true;
    oldFileKey = fileKey;
    if (storedKey != null) keys.put(storageKeyName, storedKey);
    originalStoredKey = storedKey;
    steps = 0;
    log.clear();
  }

  StorageStartController controller() {
    var n = 100;
    return StorageStartController(
      keyStore: keys,
      generateKey: () => keyOf(n++),
      wire: () async => StorageWiring(storage: storage, files: files),
    );
  }
}

class WorldFiles extends FakeDatabaseFiles {
  WorldFiles(this.w);
  final World w;

  /// Löschen tut nichts (Datei lässt sich nicht entfernen), ohne Fehler.
  bool stubborn = false;

  @override
  Future<void> deleteAll() async {
    await w.step('Dateien löschen');
    if (stubborn) return;
    await super.deleteAll();
    w.inner = FakeStorage(encryptionActive: w.inner.encryptionActive)
      ..openFailure = w.openFailureAfterDelete;
    w.oldFileKey = null;
    w.check();
  }
}

class WorldKeys implements KeyStore {
  WorldKeys(this.w);
  final World w;
  final Map<String, Uint8List> store = {};

  /// Wenn gesetzt, wirft jeder Zugriff [KeyStoreException].
  String? failWith;

  void put(String name, Uint8List v) => store[name] = Uint8List.fromList(v);

  void _check() {
    final m = failWith;
    if (m != null) throw KeyStoreException(m);
  }

  @override
  Future<Uint8List?> read(String name) async {
    _check();
    return store[name];
  }

  @override
  Future<void> write(String name, Uint8List value) async {
    _check();
    await w.step('Schlüssel schreiben');
    put(name, value);
    w.check();
  }

  @override
  Future<void> delete(String name) async {
    _check();
    await w.step('Schlüssel löschen');
    store.remove(name);
    w.check();
  }
}

class WorldStorage implements Storage {
  WorldStorage(this.w);
  final World w;

  @override
  Future<StorageSession> open(Uint8List key) async {
    if (!w.files.present && w.inner.encryptionActive) {
      await w.step('Datei anlegen');
    }
    final s = await w.inner.open(key);
    w.files.present = true;
    return s;
  }
}
