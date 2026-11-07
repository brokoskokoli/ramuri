import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../ports/archive_cipher.dart';
import '../../ports/archive_source.dart';
import '../../ports/clock.dart';
import '../../ports/file_handoff.dart';
import 'archive_errors.dart';
import 'archive_lines.dart';
import 'archive_password.dart';

/// Baut den [ArchiveCipher] im Arbeits-Isolate. Muss eine Top-Level-Funktion
/// sein (Funktionswerte gehen nur so an einen anderen Isolate) und darf nichts
/// aus dem Haupt-Isolate brauchen; die Ableitung läuft dort selbst, ohne
/// weiteren Isolate.
typedef ArchiveCipherFactory = ArchiveCipher Function();

/// Abbruchmarke für einen laufenden Export.
class ArchiveCancel {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Dateiname eines Archivs: `running-archiv-JJJJMMTT.runarch` (Vorschlag).
String archiveFileName(DateTime utc) {
  String two(int v) => v.toString().padLeft(2, '0');
  final d = utc.toUtc();
  return exportFileName(
    'running-archiv-${d.year.toString().padLeft(4, '0')}${two(d.month)}${two(d.day)}',
    'runarch',
  );
}

/// Medientyp der Archivdatei (unspezifisch, verschlüsselte Bytes).
const String archiveMimeType = 'application/octet-stream';

/// Export des Gesamtarchivs (`docs/contracts/archive.md`, FR-0192, SEC-0011).
///
/// Ablauf: Datenbank seitenweise lesen und als JSON Lines ausgeben (dieser
/// Isolate; die Datenbank liegt ohnehin in ihrem eigenen) → ein Arbeits-Isolate
/// komprimiert (gzip), verschlüsselt (Strom über den [ArchiveCipher]) und
/// schreibt `<name>.part`. Erst nach Flush und Schließen wird zum Endnamen
/// umbenannt; bei jedem Fehler oder Abbruch wird die `.part`-Datei gelöscht.
/// Die Klartextzeilen verlassen den Speicher nie in eine Datei.
class ArchiveExporter {
  ArchiveExporter({
    required this._source,
    required this._handoff,
    required this._clock,
    required this._cipherFactory,
    this._pageSize = archivePageSize,
  });

  final ArchiveSource _source;
  final FileHandoff _handoff;
  final Clock _clock;
  final ArchiveCipherFactory _cipherFactory;
  final int _pageSize;

  /// Schreibt das Archiv nach `exportDirectory()/<fileName>` (`fileName` Vorgabe:
  /// [archiveFileName]) und liefert die Datei zur Übergabe. Wirft
  /// [ArchiveExportException]; danach liegt keine Datei mit dem Endnamen und
  /// keine `.part`-Datei dieses Laufs vor. Ein vorhandenes Ziel gleichen Namens
  /// wird erst beim Umbenennen ersetzt.
  Future<ExportFile> export({
    required String password,
    String? fileName,
    ArchiveCancel? cancel,
  }) async {
    if (checkArchivePassword(password, password) ==
        ArchivePasswordCheck.tooShort) {
      throw const ArchiveExportException(ArchiveExportFailure.passwordRejected);
    }
    final name = fileName ?? archiveFileName(_clock.now());
    final dir = await _handoff.exportDirectory();
    if (dir == null ||
        !isPlainAbsolutePath(dir) ||
        !isSafeExportFileName(name) ||
        !isSafeExportFileName('$name.part')) {
      throw const ArchiveExportException(
        ArchiveExportFailure.noExportDirectory,
      );
    }
    final target = '$dir/$name';
    final part = '$target.part';
    _deleteQuietly(part);

    final fromWorker = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final done = Completer<void>();
    Isolate? isolate;
    ArchiveExportException? sourceError;
    final lines = StreamIterator(
      archiveLines(
        source: _source,
        clock: _clock,
        pageSize: _pageSize,
        isCancelled: () => cancel?.isCancelled ?? false,
      ),
    );
    SendPort? toWorker;

    void fail(ArchiveExportFailure f) {
      if (!done.isCompleted) done.completeError(ArchiveExportException(f));
    }

    Future<void> answerRequest() async {
      try {
        if (cancel?.isCancelled ?? false) {
          throw const ArchiveExportException(ArchiveExportFailure.cancelled);
        }
        if (await lines.moveNext()) {
          toWorker!.send(<Object>[
            'batch',
            TransferableTypedData.fromList([lines.current]),
          ]);
        } else {
          toWorker!.send(<Object>['end']);
        }
      } on ArchiveExportException catch (e) {
        sourceError = e;
        toWorker!.send(<Object>['abort']);
      } catch (_) {
        sourceError = const ArchiveExportException(
          ArchiveExportFailure.readFailed,
        );
        toWorker!.send(<Object>['abort']);
      }
    }

    fromWorker.listen((Object? m) {
      if (m is SendPort) {
        toWorker = m;
      } else if (m == 'req') {
        unawaited(answerRequest());
      } else if (m is List && m.first == 'done') {
        if (!done.isCompleted) done.complete();
      } else if (m is List && m.first == 'error') {
        fail(
          sourceError?.failure ??
              ArchiveExportFailure.values.firstWhere(
                (f) => f.name == m[1],
                orElse: () => ArchiveExportFailure.writeFailed,
              ),
        );
      }
    });
    errors.listen((Object? _) => fail(ArchiveExportFailure.writeFailed));
    exits.listen((Object? _) {
      // Normalfall: 'done' oder 'error' kam schon. Sonst ist der Isolate
      // ohne Antwort gestorben; kurze Frist, falls die Nachricht noch läuft.
      Future<void>.delayed(const Duration(seconds: 1), () {
        fail(ArchiveExportFailure.writeFailed);
      });
    });

    try {
      isolate = await Isolate.spawn(
        _worker,
        _WorkerInit(
          reply: fromWorker.sendPort,
          partPath: part,
          password: password,
          cipherFactory: _cipherFactory,
        ),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
      );
      await done.future;
      isolate.kill();
      try {
        File(part).renameSync(target);
      } catch (_) {
        throw const ArchiveExportException(ArchiveExportFailure.writeFailed);
      }
      return ExportFile.inExportDirectory(
        fileName: name,
        mimeType: archiveMimeType,
        path: target,
      );
    } catch (e) {
      isolate?.kill(priority: Isolate.immediate);
      _deleteQuietly(part);
      if (e is ArchiveExportException) rethrow;
      throw const ArchiveExportException(ArchiveExportFailure.writeFailed);
    } finally {
      unawaited(lines.cancel());
      fromWorker.close();
      errors.close();
      exits.close();
    }
  }
}

void _deleteQuietly(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  } catch (_) {}
}

class _WorkerInit {
  const _WorkerInit({
    required this.reply,
    required this.partPath,
    required this.password,
    required this.cipherFactory,
  });

  final SendPort reply;
  final String partPath;
  final String password;
  final ArchiveCipherFactory cipherFactory;
}

class _Aborted implements Exception {
  const _Aborted();
}

/// Arbeits-Isolate: Stücke holen (Pull, ein Stück im Voraus), gzip,
/// verschlüsseln, schreiben, flush. Antwortet mit 'done' oder 'error'; bei
/// Fehler ist die `.part`-Datei dann gelöscht.
Future<void> _worker(_WorkerInit init) async {
  final inbox = ReceivePort();
  init.reply.send(inbox.sendPort);
  final it = StreamIterator<Object?>(inbox);
  RandomAccessFile? file;
  try {
    file = File(init.partPath).openSync(mode: FileMode.writeOnly);
    Stream<List<int>> plain() async* {
      while (true) {
        init.reply.send('req');
        if (!await it.moveNext()) throw const _Aborted();
        final m = it.current! as List<Object?>;
        if (m.first == 'batch') {
          yield (m[1]! as TransferableTypedData).materialize().asUint8List();
        } else if (m.first == 'end') {
          return;
        } else {
          throw const _Aborted();
        }
      }
    }

    final compressed = gzip.encoder.bind(plain());
    await for (final chunk in init.cipherFactory().encrypt(
      init.password,
      compressed,
    )) {
      file.writeFromSync(chunk);
    }
    file.flushSync();
    file.closeSync();
    file = null;
    init.reply.send(<Object>['done']);
  } catch (e) {
    try {
      file?.closeSync();
    } catch (_) {}
    _deleteQuietly(init.partPath);
    final kind = switch (e) {
      _Aborted() => ArchiveExportFailure.cancelled,
      ArchiveExportException(:final failure) => failure,
      FileSystemException() => ArchiveExportFailure.writeFailed,
      _ => ArchiveExportFailure.encryptFailed,
    };
    init.reply.send(<Object>['error', kind.name]);
  } finally {
    inbox.close();
  }
}
