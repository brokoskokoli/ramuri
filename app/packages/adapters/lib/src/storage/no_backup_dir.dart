import 'package:flutter/services.dart';

/// Name der Datenbankdatei im Verzeichnis ohne Backup.
const String databaseFileName = 'running_app.db';

/// Kanal zum kleinen Plattformaufruf in `MainActivity` (ADR-0003 Punkt 3).
const MethodChannel noBackupChannel = MethodChannel('ramuri/storage');

/// Liefert `Context.getNoBackupFilesDir()`, das immer vom Backup ausgenommen ist.
Future<String> noBackupFilesDir([
  MethodChannel channel = noBackupChannel,
]) async {
  final path = await channel.invokeMethod<String>('getNoBackupFilesDir');
  if (path == null || path.isEmpty) {
    throw PlatformException(code: 'no_backup_dir', message: 'Pfad fehlt');
  }
  return path;
}

Future<String> databasePath([MethodChannel channel = noBackupChannel]) async =>
    '${await noBackupFilesDir(channel)}/$databaseFileName';
