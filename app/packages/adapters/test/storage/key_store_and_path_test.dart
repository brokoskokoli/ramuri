import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _MapStorage extends Fake implements FlutterSecureStorage {
  final map = <String, String>{};
  bool fail = false;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (fail) {
      throw PlatformException(code: 'x', message: 'Detail mit Schlüssel');
    }
    return map[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (fail) {
      throw PlatformException(code: 'x');
    }
    map[key] = value!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('resetOnError ist aus: Der Schlüssel wird nie still gelöscht', () {
    expect(SecureKeyStore.androidOptions.params['resetOnError'], 'false');
  });

  test('Schlüssel gehen als Byte hin und zurück', () async {
    final s = SecureKeyStore(_MapStorage());
    final key = generateStorageKey();
    expect(key.length, storageKeyLength);
    expect(await s.read('k'), isNull);
    await s.write('k', key);
    expect(await s.read('k'), key);
  });

  test('Plugin-Fehler werden KeyStoreException ohne Plugin-Text', () async {
    final m = _MapStorage()..fail = true;
    final s = SecureKeyStore(m);
    await expectLater(
      s.read('k'),
      throwsA(
        isA<KeyStoreException>().having(
          (e) => e.toString(),
          'text',
          isNot(contains('Detail')),
        ),
      ),
    );
    await expectLater(
      s.write('k', Uint8List(32)),
      throwsA(isA<KeyStoreException>()),
    );
  });

  test('kaputter Ablagewert ist KeyStoreException, nicht "fehlt"', () async {
    final m = _MapStorage()..map['k'] = '%%%kein base64';
    await expectLater(
      SecureKeyStore(m).read('k'),
      throwsA(isA<KeyStoreException>()),
    );
  });

  test('zwei erzeugte Schlüssel unterscheiden sich', () {
    expect(generateStorageKey(), isNot(generateStorageKey()));
  });

  test('Pfad kommt vom Plattformaufruf getNoBackupFilesDir', () async {
    const channel = MethodChannel('ramuri/storage');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return '/data/no_backup';
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(await databasePath(), '/data/no_backup/$databaseFileName');
    expect(calls, ['getNoBackupFilesDir']);
  });
}
