import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:running_app/app.dart';
import 'package:running_app/app_dependencies.dart';
import 'package:running_app/features/storage/storage_start.dart';

import 'storage_world.dart';

const String marker = 'SYNTHETISCHE-MARKE-4711';

/// Bytes der Haupt- und der WAL-Datei (nicht der `-shm`: das ist ein
/// Arbeitsindex, kein Inhalt).
class Snapshot {
  Snapshot(String path)
    : main = File(path).readAsBytesSync(),
      wal = File('$path-wal').existsSync()
          ? File('$path-wal').readAsBytesSync()
          : null;

  final Uint8List main;
  final Uint8List? wal;

  void expectSameAs(String path) {
    expect(File(path).existsSync(), isTrue, reason: 'Hauptdatei');
    expect(File(path).readAsBytesSync(), main, reason: 'Hauptdatei geändert');
    expect(File('$path-wal').existsSync(), wal != null, reason: 'WAL da');
    if (wal != null) {
      expect(File('$path-wal').readAsBytesSync(), wal, reason: 'WAL geändert');
    }
  }
}

/// Log-Ausgabe des Hintergrund-Isolate von drift. `captureLogs` sieht sie nicht
/// (`debugPrint` und Zone gelten nur im Test-Isolate); `setup` ist als
/// `isolateSetup` zu übergeben und leitet sie auf einen Port um.
class IsolateLogs {
  IsolateLogs() {
    _port.listen((m) => _lines.add(m as String));
  }

  final _port = ReceivePort();
  final _lines = <String>[];

  FutureOr<void> Function() get setup => _redirect(_port.sendPort);

  Future<String> text() async {
    await pumpEventQueue();
    return _lines.join('\n');
  }

  void close() => _port.close();
}

FutureOr<void> Function() _redirect(SendPort port) =>
    () => driftRuntimeOptions.debugPrint = (String s) => port.send(s);

class Env {
  Env(this.dir, this.path, this.snapshot);
  final Directory dir;
  final String path;
  final Snapshot snapshot;
  final FakeKeyStore keys = FakeKeyStore();
  final IsolateLogs isolateLogs = IsolateLogs();

  StorageStartController controller({int seed = 100}) {
    var n = seed;
    return StorageStartController(
      keyStore: keys,
      generateKey: () => keyOf(n++),
      wire: () async => StorageWiring(
        storage: EncryptedStorage.forTest(
          path,
          isolateSetup: isolateLogs.setup,
        ),
        files: FileDatabaseFiles(path),
      ),
    );
  }
}

/// Legt eine echte verschlüsselte Datei mit Marke an, die wie nach einem
/// Absturz mit nicht geleertem WAL daliegt: Haupt- und WAL-Datei werden bei
/// offener Sitzung kopiert, danach wird das Original geschlossen und entfernt.
Future<Env> makeEnv({Uint8List? storedKey}) async {
  final dir = Directory.systemTemp.createTempSync('wp02d_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final src = '${dir.path}/src/$databaseFileName';
  Directory('${dir.path}/src').createSync();
  final session = await EncryptedStorage(src).open(keyOf(1));
  await session.settings.set('m', marker, at: DateTime.utc(2030));
  await session.runs.create(startedAt: DateTime.utc(2030));
  expect(File('$src-wal').lengthSync(), greaterThan(0), reason: 'WAL leer');
  final path = '${dir.path}/$databaseFileName';
  File(src).copySync(path);
  File('$src-wal').copySync('$path-wal');
  // Wie nach einem Absturz liegt auch die -shm-Datei daneben.
  expect(File('$src-shm').existsSync(), isTrue, reason: '-shm fehlt');
  File('$src-shm').copySync('$path-shm');
  await session.close();
  final env = Env(dir, path, Snapshot(path));
  addTearDown(env.isolateLogs.close);
  if (storedKey != null) await env.keys.write(storageKeyName, storedKey);
  return env;
}

/// Fängt alles ab, was der Start ausgibt.
Future<List<String>> captureLogs(Future<void> Function() body) async {
  final out = <String>[];
  final oldDebug = debugPrint;
  final oldOnError = FlutterError.onError;
  debugPrint = (String? m, {int? wrapWidth}) => out.add(m ?? '');
  FlutterError.onError = (d) => out.add(d.toString());
  try {
    await runZoned(
      body,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => out.add(line),
      ),
    );
  } finally {
    debugPrint = oldDebug;
    FlutterError.onError = oldOnError;
  }
  return out;
}

void main() {
  final k1 = keyOf(2);

  test('Vorbereitung ist echt: richtiger Schlüssel liest die Marke', () async {
    final env = await makeEnv();
    // Kopie öffnen, damit der Schnappschuss unberührt bleibt.
    final copy = '${env.dir.path}/copy.db';
    File(env.path).copySync(copy);
    File('${env.path}-wal').copySync('$copy-wal');
    final s = await EncryptedStorage(copy).open(keyOf(1));
    expect(await s.settings.get('m'), marker);
    expect(await s.runs.list(), hasLength(1));
    await s.close();
    expect(env.snapshot.wal, isNotNull);
    expect(env.snapshot.wal!.length, greaterThan(0));
  });

  test('Absturzbild hat Haupt-, WAL- und -shm-Datei', () async {
    final env = await makeEnv();
    expect(File(env.path).existsSync(), isTrue);
    expect(File('${env.path}-wal').lengthSync(), greaterThan(0));
    expect(File('${env.path}-shm').existsSync(), isTrue);
  });

  test('vorhandene Klartextdatei: öffnet nicht, Bytes unverändert', () async {
    final dir = Directory.systemTemp.createTempSync('wp02d_plain_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/$databaseFileName';
    final plain = sqlite3.open(path);
    plain.execute('PRAGMA journal_mode = DELETE');
    plain.execute('CREATE TABLE t (v TEXT)');
    plain.execute("INSERT INTO t VALUES ('$marker')");
    plain.close();
    final before = File(path).readAsBytesSync();
    expect(
      String.fromCharCodes(before.take(15)),
      'SQLite format 3',
      reason: 'Vorbereitung: wirklich Klartext',
    );
    await expectLater(
      EncryptedStorage(path).open(keyOf(1)),
      throwsA(
        isA<StorageException>().having(
          (e) => e.failure,
          'failure',
          StorageFailure.unreadable,
        ),
      ),
    );
    expect(File(path).readAsBytesSync(), before);
  });

  test(
    'falscher Schlüssel: Datei byteweise unverändert (Haupt und WAL)',
    () async {
      final env = await makeEnv(storedKey: k1);
      final c = env.controller();
      await c.start();
      expect(
        (c.state as StorageNotOpenableState).cause,
        StorageNotOpenableCause.unreadable,
      );
      env.snapshot.expectSameAs(env.path);
      expect(sameBytes(await env.keys.read(storageKeyName), k1), isTrue);
    },
  );

  test('ohne Schlüssel: Datei unverändert, kein Schlüssel angelegt', () async {
    final env = await makeEnv();
    final c = env.controller();
    await c.start();
    expect(
      (c.state as StorageNotOpenableState).cause,
      StorageNotOpenableCause.keyMissing,
    );
    env.snapshot.expectSameAs(env.path);
    expect(await env.keys.read(storageKeyName), isNull);
  });

  test(
    'Marken-Test: Start ohne Schlüssel gibt weder Marke noch Schlüssel aus',
    () async {
      final env = await makeEnv(storedKey: k1);
      final c = env.controller();
      final out = await captureLogs(() async {
        await c.start();
        // Ablauf ohne Schlüssel und mit falschem Schlüssel.
        await env.keys.delete(storageKeyName);
        await c.start();
        await env.keys.write(storageKeyName, k1);
        await c.start();
      });
      // Fehlertexte der Zugriffsschicht beim Öffnen mit falschem Schlüssel.
      final texts = <String>[...out, c.state.toString()];
      var isolateText = '';
      try {
        await EncryptedStorage.forTest(
          env.path,
          isolateSetup: env.isolateLogs.setup,
        ).open(k1);
      } on StorageException catch (e) {
        texts.add(e.toString());
      }
      // Positivkontrolle: Die Marke liegt wirklich in der Datei, und das
      // Abfangen sieht Ausgaben.
      final copy = '${env.dir.path}/copy.db';
      File(env.path).copySync(copy);
      File('${env.path}-wal').copySync('$copy-wal');
      final control = IsolateLogs();
      addTearDown(control.close);
      final s = await EncryptedStorage.forTest(
        copy,
        isolateSetup: control.setup,
        logStatements: true,
      ).open(keyOf(1));
      expect(await s.settings.get('m'), marker);
      await s.settings.set('m2', marker, at: DateTime.utc(2030));
      await s.close();
      // Positivkontrolle: Das Isolate-Log ist sichtbar und enthält bei
      // eingeschaltetem Loggen die Marke.
      expect(await control.text(), contains(marker), reason: 'Isolate blind');
      isolateText = await env.isolateLogs.text();
      texts.add(isolateText);
      final probe = await captureLogs(() async {
        // ignore: avoid_print
        print(marker);
      });
      expect(probe.join(), contains(marker), reason: 'Abfangen ist blind');
      final all = texts.join('\n');
      expect(all, isNot(contains(marker)));
      for (final k in [k1, keyOf(1)]) {
        expect(all, isNot(contains(base64Encode(k))));
        expect(
          all,
          isNot(
            contains(k.map((b) => b.toRadixString(16).padLeft(2, '0')).join()),
          ),
        );
        expect(all, isNot(contains(k.join(','))));
      }
    },
  );

  testWidgets(
    'Abbrechen lässt die echte Datei unverändert, Bestätigung ersetzt sie',
    (tester) async {
      final env = (await tester.runAsync(() => makeEnv(storedKey: k1)))!;
      final c = env.controller();
      await tester.runAsync(c.start);
      expect(c.state, isA<StorageNotOpenableState>());
      tester.platformDispatcher.localesTestValue = [const Locale('de')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(
        RunningApp(dependencies: AppDependencies(storageStart: c)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Neu beginnen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      env.snapshot.expectSameAs(env.path);

      await tester.tap(find.text('Neu beginnen'));
      await tester.pumpAndSettle();
      env.snapshot.expectSameAs(env.path); // der Dialog allein ändert nichts
      await tester.tap(find.text('Endgültig löschen und neu beginnen'));
      // Der Dialog muss erst zu sein (Animation), dann läuft der Neubeginn.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      // Echte Ein-/Ausgabe und Microtasks der Testzone abwechselnd laufen lassen.
      // Danach lädt die Startseite die Einstellungen aus der echten Datei und
      // zeigt die Ersteinrichtung (WP05).
      Future<void> untilShown(Finder f) async {
        for (var i = 0; i < 500 && f.evaluate().isEmpty; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
      }

      await untilShown(find.byKey(const Key('profile_save')));
      await tester.pumpAndSettle();
      expect(c.state, isA<StorageReady>());
      await tester.tap(find.byKey(const Key('setup_skip')));
      await untilShown(find.byKey(const Key('home_start_run')));
      await tester.pumpAndSettle();
      expect(find.text('Willkommen bei der Lauf-App'), findsOneWidget);
      final session = (c.state as StorageReady).session;
      expect(await tester.runAsync(() => session.runs.list()), isEmpty);
      expect(await tester.runAsync(() => session.settings.get('m')), isNull);
      expect(File(env.path).readAsBytesSync(), isNot(env.snapshot.main));
      final stored = await tester.runAsync(() => env.keys.read(storageKeyName));
      expect(sameBytes(stored, k1), isFalse);
      expect(sameBytes(stored, keyOf(1)), isFalse);
      await tester.runAsync(session.close);
    },
  );

  test('Neubeginn löscht Haupt-, WAL- und Journal-Datei', () async {
    final env = await makeEnv(storedKey: k1);
    File('${env.path}-shm').writeAsBytesSync([1, 2, 3]);
    File('${env.path}-journal').writeAsBytesSync([4, 5]);
    final c = env.controller();
    await c.start();
    expect(c.state, isA<StorageNotOpenableState>());
    await c.resetStorage();
    expect(c.state, isA<StorageReady>());
    expect(File('${env.path}-journal').existsSync(), isFalse);
    expect(await (c.state as StorageReady).session.runs.list(), isEmpty);
    await (c.state as StorageReady).session.close();
  });
}
