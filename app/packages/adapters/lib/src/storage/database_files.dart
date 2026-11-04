import 'dart:io';

import 'package:core/core.dart';

/// Dateien der Datenbank neben [path]: Haupt-, `-wal`-, `-shm`- und
/// `-journal`-Datei.
class FileDatabaseFiles implements DatabaseFiles {
  FileDatabaseFiles(this.path);

  final String path;

  /// Reihenfolge des Löschens: erst die Nebendateien, die Hauptdatei zuletzt.
  /// Ein Abbruch dazwischen lässt immer noch eine Datei stehen; die App
  /// behandelt das wie jede vorhandene Datei (kein neuer Schlüssel).
  static const List<String> suffixes = ['-wal', '-shm', '-journal', ''];

  @override
  Future<bool> exist() async {
    for (final suffix in suffixes) {
      if (await File('$path$suffix').exists()) return true;
    }
    return false;
  }

  @override
  Future<void> deleteAll() async {
    for (final suffix in suffixes) {
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
  }
}
