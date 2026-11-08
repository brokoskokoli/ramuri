import 'dart:io';

import 'package:core/core.dart';

/// Dateien der Datenbank neben [path]: Haupt-, `-wal`-, `-shm`- und
/// `-journal`-Datei.
class FileDatabaseFiles implements DatabaseFiles {
  FileDatabaseFiles(
    this.path, {
    String? importPath,
    this.beforeStep,
    this.alsoDelete,
  }) : importPath = importPath ?? '$path$importSuffix';

  final String path;

  /// Wird nach dem Löschen der Datenbank gerufen (nur [deleteAll], der Neubeginn nach Schlüsselverlust): Der
  /// Kartenspeicher (WP13) ist mit dem verlorenen Schlüssel verschlüsselt und darf nicht stehen bleiben. Er zählt
  /// nicht für [exist]: Er allein ist kein Grund für "Schlüssel fehlt".
  final Future<void> Function()? alsoDelete;

  /// Zwischendatenbank der Wiederherstellung (WP12): neben der aktiven, im
  /// selben Ordner, damit das Umbenennen atomar bleibt (gleiches Dateisystem).
  final String importPath;

  static const String importSuffix = '.import';

  /// Nur für Tests: wird vor jedem Schritt des Tauschs mit dessen Namen
  /// gerufen; eine Ausnahme dort simuliert das Ende des Prozesses an dieser
  /// Stelle.
  final void Function(String step)? beforeStep;

  /// Die Schritte von [replaceWithImport] in Reihenfolge.
  static const List<String> replaceSteps = [
    'start',
    'active-wal',
    'active-shm',
    'active-journal',
    'import-wal',
    'import-shm',
    'import-journal',
    'rename',
    'renamed',
  ];

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
    await alsoDelete?.call();
  }

  @override
  Future<bool> importExists() async {
    for (final suffix in suffixes) {
      if (await File('$importPath$suffix').exists()) return true;
    }
    return false;
  }

  @override
  Future<void> deleteImport() async {
    for (final suffix in suffixes) {
      final f = File('$importPath$suffix');
      if (await f.exists()) await f.delete();
    }
  }

  /// Reihenfolge ([replaceSteps]): erst Nebendateien der aktiven Datenbank
  /// (ein altes `-wal` neben der neuen Hauptdatei wäre falsch), dann die der
  /// Zwischendatenbank (sie ist geschlossen und per Checkpoint geleert), zuletzt
  /// **ein** atomares Umbenennen. Vor dem Umbenennen steht die alte Hauptdatei
  /// vollständig (die aktive Sitzung wurde mit Checkpoint geschlossen; ein
  /// aktives -wal mit Inhalt bricht den Tausch vorher ab), danach die neue. Das Verzeichnis wird nicht eigens synchronisiert (Dart hat dafür
  /// keinen Aufruf): Nach einem Stromausfall kann das Umbenennen fehlen, dann
  /// gilt der alte Stand.
  @override
  Future<void> replaceWithImport() async {
    void step(String name) => beforeStep?.call(name);
    step('start');
    if (!await File(importPath).exists()) {
      throw const FileSystemException('Zwischendatenbank fehlt');
    }
    // Fail-closed: Ein aktives -wal mit Inhalt kann Schreibvorgänge enthalten,
    // die nicht in der Hauptdatei stehen (Checkpoint fehlte oder scheiterte).
    // Es zu löschen, ginge ohne Spur verloren. Nach sauberem Schließen der
    // letzten Verbindung ist es leer oder weg.
    final activeWal = File('$path-wal');
    if (await activeWal.exists() && await activeWal.length() > 0) {
      throw const FileSystemException('Aktives -wal nicht eingecheckt');
    }
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      step('active$suffix');
      final f = File('$path$suffix');
      if (await f.exists()) await f.delete();
    }
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      step('import$suffix');
      final f = File('$importPath$suffix');
      if (await f.exists()) await f.delete();
    }
    step('rename');
    await File(importPath).rename(path);
    step('renamed');
  }
}
