import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:test/test.dart';

Uint8List _key(int fill) =>
    Uint8List.fromList(List.filled(storageKeyLength, fill));

void main() {
  late FakeKeyStore store;
  late bool files;
  var generated = 0;

  StorageKeyService service() => StorageKeyService(
    keyStore: store,
    databaseFilesExist: () async => files,
    generateKey: () {
      generated++;
      return _key(generated);
    },
  );

  setUp(() {
    store = FakeKeyStore();
    files = false;
    generated = 0;
  });

  test('Schlüssel und Datei da: öffnen', () async {
    await store.write(storageKeyName, _key(9));
    files = true;
    final r = await service().decide();
    expect(r, isA<OpenExistingStorage>());
    expect((r as OpenExistingStorage).key, _key(9));
    expect(generated, 0);
  });

  test(
    'Schlüssel da, keine Datei: neu anlegen mit vorhandenem Schlüssel',
    () async {
      await store.write(storageKeyName, _key(9));
      final r = await service().decide();
      expect(r, isA<CreateNewStorage>());
      expect((r as CreateNewStorage).key, _key(9));
      expect(generated, 0);
    },
  );

  test(
    'weder Schlüssel noch Datei: neuer Schlüssel, vor dem Anlegen abgelegt',
    () async {
      final r = await service().decide();
      expect(r, isA<CreateNewStorage>());
      expect((r as CreateNewStorage).key, _key(1));
      expect(await store.read(storageKeyName), _key(1));
    },
  );

  test(
    'Schlüssel fehlt, Datei da: nicht zu öffnen, nichts geschrieben',
    () async {
      files = true;
      final r = await service().decide();
      expect(r, isA<StorageNotOpenable>());
      expect(
        (r as StorageNotOpenable).reason,
        StorageNotOpenableReason.keyMissing,
      );
      expect(await store.read(storageKeyName), isNull);
      expect(generated, 0);
    },
  );

  test(
    'Schlüssel falsch lang, Datei da: nicht zu öffnen, Schlüssel bleibt',
    () async {
      final bad = Uint8List.fromList([1, 2, 3]);
      await store.write(storageKeyName, bad);
      files = true;
      final r = await service().decide();
      expect(
        (r as StorageNotOpenable).reason,
        StorageNotOpenableReason.keyMalformed,
      );
      expect(await store.read(storageKeyName), bad);
    },
  );

  test('Schlüssel falsch lang, keine Datei: neuer Schlüssel', () async {
    await store.write(storageKeyName, Uint8List.fromList([1, 2, 3]));
    final r = await service().decide();
    expect((r as CreateNewStorage).key, _key(1));
  });

  test('KeyStoreException führt nie zum Neuanlegen, auch ohne Datei', () async {
    store.failWith = 'defekt';
    await expectLater(service().decide(), throwsA(isA<KeyStoreException>()));
    expect(generated, 0);
    files = true;
    await expectLater(service().decide(), throwsA(isA<KeyStoreException>()));
    expect(generated, 0);
  });

  test(
    'Ablage hält den geschriebenen Schlüssel nicht: Fehler statt Neuanlegen',
    () async {
      final lossy = _LossyKeyStore();
      final s = StorageKeyService(
        keyStore: lossy,
        databaseFilesExist: () async => false,
        generateKey: () => _key(5),
      );
      await expectLater(s.decide(), throwsA(isA<KeyStoreException>()));
    },
  );

  test('Generator liefert falsche Länge: Abbruch, nichts abgelegt', () async {
    final s = StorageKeyService(
      keyStore: store,
      databaseFilesExist: () async => false,
      generateKey: () => Uint8List(16),
    );
    await expectLater(s.decide(), throwsStateError);
    expect(await store.read(storageKeyName), isNull);
  });
}

class _LossyKeyStore implements KeyStore {
  @override
  Future<Uint8List?> read(String name) async => null;
  @override
  Future<void> write(String name, Uint8List value) async {}
  @override
  Future<void> delete(String name) async {}
}
