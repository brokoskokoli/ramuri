import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:sqlite3/sqlite3.dart' as raw;

import '../storage/connection_setup.dart';
import 'map_cache_core.dart';
import 'map_gate.dart';

/// Kartenspeicher (R008 "Speicher: Entscheidung", ADR-0009 Punkt 4): eine eigene verschlüsselte Datei
/// `map_cache.db` im Verzeichnis ohne Backup, mit dem Schlüssel aus ADR-0003, über eine eigene Verbindung in einem
/// Hintergrund-Isolate. Die Datei wird erst beim ersten Zugriff geöffnet.
///
/// Fehler des Speichers brechen nie die Karte und nie die Aufzeichnung: Lesefehler sind "kein Treffer", Schreibfehler
/// werden verschluckt. Ist die Verschlüsselung nicht belegt aktiv, bleibt der Speicher aus (fail-closed). Es wird
/// nichts geloggt.
class EncryptedMapTileStore implements MapThumbnailStore {
  EncryptedMapTileStore({
    required this.directory,
    required this.key,
    this.tileLimit = mapTileLimitBytes,
    this.thumbnailLimit = mapThumbnailLimitBytes,
    this.libraryProbe = defaultLibraryCipherProbe,
    this.fileProbe = defaultFileEncryptedProbe,
  });

  /// Verzeichnis ohne Backup (`getNoBackupFilesDir()`).
  final Future<String> Function() directory;

  /// Schlüssel aus ADR-0003 (`null`: noch keiner, dann bleibt der Speicher aus).
  final Future<Uint8List?> Function() key;
  final int tileLimit;
  final int thumbnailLimit;
  final LibraryCipherProbe libraryProbe;
  final FileEncryptedProbe fileProbe;

  Future<_Worker?>? _worker;
  bool _closed = false;

  /// Vorerst unbenutzbar (kein Schlüssel, Verschlüsselung nicht belegt, Datei nicht anlegbar): kein Treffer, kein
  /// Schreiben, kein neuer Versuch bis [delete] oder einem neuen Objekt.
  bool _off = false;

  Future<String> _path() async => '${await directory()}/$mapCacheFileName';

  /// Wie oft der Isolate nach einem Fehler neu starten darf, bevor der Speicher für diese Sitzung aus bleibt.
  static const int _maxRestarts = 3;
  int _restarts = 0;

  /// Wie [_ensure], aber ohne den Speicher anzulegen: gibt es keine Verbindung und keine Datei, ist da nichts.
  Future<_Worker?> _ensureExisting() async {
    if (_worker == null && !await File(await _path()).exists()) return null;
    return _ensure();
  }

  Future<_Worker?> _ensure() async {
    if (_off || _closed) return null;
    var pending = _worker;
    if (pending != null) {
      final w = await pending;
      if (w != null && !w.dead) return w;
      if (identical(_worker, pending)) {
        _worker = null;
        if (w != null && ++_restarts > _maxRestarts) _off = true;
      }
      if (_off) return null;
    }
    return await (_worker ??= _start());
  }

  Future<_Worker?> _start() async {
    try {
      final k = await key();
      if (k == null || k.length != storageKeyLength) {
        _off = true;
        return null;
      }
      final w = await _Worker.spawn(
        path: await _path(),
        hexKey: hexOfKey(k),
        tileLimit: tileLimit,
        thumbnailLimit: thumbnailLimit,
        libraryProbe: libraryProbe,
        fileProbe: fileProbe,
      );
      if (w == null) _off = true;
      return w;
    } catch (_) {
      _off = true;
      return null;
    }
  }

  @override
  Future<Uint8List?> read(String key) async {
    try {
      final w = await _ensure();
      if (w == null) return null;
      return await w.request(['read', key]) as Uint8List?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    try {
      final w = await _ensure();
      if (w == null) return;
      await w.request(['write', key, bytes]);
    } catch (_) {
      // Ein Schreibfehler kostet nur einen späteren Netzabruf.
    }
  }

  @override
  Future<void> deleteRun(int runId) async {
    try {
      final w = await _ensureExisting();
      if (w == null) return;
      await w.request(['deleteRun', runId]);
    } catch (_) {
      // Gibt es die Datei nicht oder ist sie nicht lesbar, gibt es auch keine Miniatur.
    }
  }

  /// Entfernt alle Miniaturen, die Kacheln bleiben (nach dem Tausch der Datenbank durch eine Wiederherstellung).
  /// Fehler sind kein Wurf; gibt es den Speicher nicht, tut es nichts.
  Future<void> deleteAllThumbnails() async {
    try {
      final w = await _ensureExisting();
      if (w == null) return;
      await w.request(['deleteThumbnails']);
    } catch (_) {}
  }

  /// Größe der Dateien auf der Platte (Datei und Nebendateien); 0, wenn es sie nicht gibt. Für die Anzeige (A3).
  Future<int> sizeBytes() async {
    try {
      final path = await _path();
      var sum = 0;
      for (final suffix in mapCacheSuffixes) {
        final f = File('$path$suffix');
        if (await f.exists()) sum += await f.length();
      }
      return sum;
    } catch (_) {
      return 0;
    }
  }

  /// Schließt die Verbindung und löscht Datei samt `-journal` ("Alles löschen", Widerruf, Schlüsselverlust). Wirft,
  /// wenn eine Datei nicht gelöscht werden konnte. Danach darf der Speicher wieder entstehen.
  Future<void> delete() async {
    final pending = _worker;
    _worker = null;
    _off = false;
    if (pending != null) {
      try {
        await (await pending)?.close();
      } catch (_) {}
    }
    deleteMapCacheFiles(await _path());
  }

  /// Schließt die Verbindung; die Datei bleibt.
  Future<void> close() async {
    _closed = true;
    final pending = _worker;
    _worker = null;
    if (pending != null) {
      try {
        await (await pending)?.close();
      } catch (_) {}
    }
  }
}

/// Der Hintergrund-Isolate mit der einen Verbindung. Nachrichten nur aus einfachen Werten; Fehler kommen ohne Text an.
class _Worker {
  _Worker._(this._isolate, this._send, this._port, this._exit);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _port;
  final ReceivePort _exit;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 0;

  /// Der Isolate ist beendet (Fehler oder Schließen).
  bool dead = false;

  /// `null`, wenn der Speicher nicht entstehen darf (Verschlüsselung nicht belegt, Datei nicht benutzbar).
  static Future<_Worker?> spawn({
    required String path,
    required String hexKey,
    required int tileLimit,
    required int thumbnailLimit,
    required LibraryCipherProbe libraryProbe,
    required FileEncryptedProbe fileProbe,
  }) async {
    final port = ReceivePort();
    final exit = ReceivePort();
    final ready = Completer<SendPort?>();
    final isolate = await Isolate.spawn(
      _run,
      _Init(
        port.sendPort,
        path,
        hexKey,
        tileLimit,
        thumbnailLimit,
        libraryProbe,
        fileProbe,
      ),
      onExit: exit.sendPort,
      errorsAreFatal: true,
    );
    _Worker? worker;
    port.listen((m) {
      if (!ready.isCompleted) {
        ready.complete(m is SendPort ? m : null);
        return;
      }
      final l = m as List<Object?>;
      worker?._pending.remove(l[0])?.complete(l[1] == true ? l[2] : null);
    });
    exit.listen((_) {
      if (!ready.isCompleted) ready.complete(null);
      worker?.dead = true;
      worker?._failAll();
    });
    final send = await ready.future;
    if (send == null) {
      port.close();
      exit.close();
      isolate.kill(priority: Isolate.immediate);
      return null;
    }
    return worker = _Worker._(isolate, send, port, exit);
  }

  void _failAll() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete(null);
    }
    _pending.clear();
  }

  /// Antwort ist `null` bei jedem Fehler (kein Treffer, nicht gespeichert).
  Future<Object?> request(List<Object?> msg) {
    if (dead) return Future.value(null);
    final id = _nextId++;
    final c = _pending[id] = Completer<Object?>();
    _send.send([id, ...msg]);
    return c.future;
  }

  Future<void> close() async {
    try {
      await request(['close']).timeout(const Duration(seconds: 5));
    } catch (_) {}
    dead = true;
    _isolate.kill(priority: Isolate.immediate);
    _failAll();
    _port.close();
    _exit.close();
  }
}

class _Init {
  _Init(
    this.reply,
    this.path,
    this.hexKey,
    this.tileLimit,
    this.thumbnailLimit,
    this.libraryProbe,
    this.fileProbe,
  );
  final SendPort reply;
  final String path;
  final String hexKey;
  final int tileLimit;
  final int thumbnailLimit;
  final LibraryCipherProbe libraryProbe;
  final FileEncryptedProbe fileProbe;
}

/// Einstieg des Isolate. Jeder Fehler wird zu "nichts", nie zu einem Text: Ausnahmen von SQLite tragen Statements.
void _run(_Init init) {
  final MapCacheCore core;
  try {
    core = MapCacheCore.open(
      path: init.path,
      hexKey: init.hexKey,
      tileLimit: init.tileLimit,
      thumbnailLimit: init.thumbnailLimit,
      libraryProbe: init.libraryProbe,
      fileProbe: init.fileProbe,
    );
  } catch (_) {
    init.reply.send('off');
    return;
  }
  final commands = ReceivePort();
  init.reply.send(commands.sendPort);
  var broken = false;
  var unreadable = false;
  commands.listen((m) {
    final l = m as List<Object?>;
    final id = l[0];
    Object? result;
    var ok = false;
    try {
      switch (l[1]) {
        case 'read':
          result = core.read(l[2] as String);
          ok = true;
        case 'write':
          core.write(l[2] as String, l[3] as Uint8List);
          ok = true;
        case 'deleteRun':
          core.deleteRunThumbnails(l[2] as int);
          ok = true;
        case 'deleteThumbnails':
          core.deleteAllThumbnails();
          ok = true;
        case 'close':
          core.close();
          ok = true;
          commands.close();
      }
    } on raw.SqliteException catch (e) {
      broken = true;
      final code = e.extendedResultCode & 0xff;
      unreadable = code == 26 || code == 11;
    } catch (_) {
      broken = true;
    }
    // Nach einem Fehler weiterzumachen wäre geraten; der nächste Start baut die Datei bei Bedarf neu auf. Erst
    // aufräumen, dann antworten: Wer die Antwort hat, sieht den Stand danach.
    if (broken) {
      try {
        core.close();
      } catch (_) {}
      // Beschädigt: löschen, der nächste Start baut neu auf (nur Abgeleitetes geht verloren).
      if (unreadable) {
        try {
          deleteMapCacheFiles(init.path);
        } catch (_) {}
      }
    }
    init.reply.send([id, ok, result]);
    if (broken) {
      commands.close();
    }
  });
}
