import 'dart:io';

import 'package:adapters/adapters.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  test('exist erkennt jede der vier Dateien einzeln', () async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final dir = tempDir();
      addTearDown(() => dir.deleteSync(recursive: true));
      final files = FileDatabaseFiles('${dir.path}/x.db');
      expect(await files.exist(), isFalse);
      File('${dir.path}/x.db$suffix').writeAsBytesSync([1]);
      expect(await files.exist(), isTrue, reason: 'Suffix "$suffix"');
    }
  });

  test('deleteAll entfernt alle vier, fehlende sind kein Fehler', () async {
    final dir = tempDir();
    addTearDown(() => dir.deleteSync(recursive: true));
    final files = FileDatabaseFiles('${dir.path}/x.db');
    await files.deleteAll();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      File('${dir.path}/x.db$suffix').writeAsBytesSync([1]);
    }
    await files.deleteAll();
    expect(await files.exist(), isFalse);
    expect(dir.listSync(), isEmpty);
  });
}
