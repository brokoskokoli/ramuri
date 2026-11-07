import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import '../../ports/archive_sink.dart';
import 'archive_errors.dart';
import 'archive_export.dart';
import 'archive_reader.dart';
import 'archive_schema.dart';

/// Einlesen eines Archivs (`docs/contracts/archive.md`, FR-0198, SEC-0011) in
/// einen [ArchiveSink]. Dieser Teil kennt weder Zwischendatenbank noch Tausch.
///
/// Ablauf: ein Arbeits-Isolate liest die Datei, prüft den Kopf, entschlüsselt
/// (Argon2 inline), entpackt als Strom, prüft jede Zeile und schickt geprüfte
/// Zeilenstapel zurück (Pull: ein Stapel, dann Quittung). Der Haupt-Isolate
/// schreibt sie in den Sink. **Nur wenn der Strom des Arbeits-Isolates ohne
/// Fehler endet** (letztes Stück geprüft, gzip-Rahmen, Endzeile, nichts danach),
/// kommt `commit`; bei jedem anderen Ausgang `abort`. Es entsteht keine Datei.
class ArchiveImporter {
  ArchiveImporter({
    required this._sink,
    required this._cipherFactory,
    this._batchRows = 500,
  });

  final ArchiveSink _sink;
  final ArchiveCipherFactory _cipherFactory;
  final int _batchRows;

  /// Liest die Archivdatei [path] mit [password]. Wirft
  /// [ArchiveImportException]; danach wurde `abort` aufgerufen und nie
  /// `commit`. Die Datei wird nur gelesen.
  Future<void> import({
    required String path,
    required String password,
    ArchiveCancel? cancel,
  }) async {
    final fromWorker = ReceivePort();
    final errors = ReceivePort();
    final exits = ReceivePort();
    final done = Completer<void>();
    SendPort? toWorker;
    Isolate? isolate;
    Timer? poll;
    ArchiveImportFailure? targetFailure;

    void fail(ArchiveImportFailure f) {
      if (!done.isCompleted) done.completeError(ArchiveImportException(f));
    }

    Future<void> handleRows(String name, List<Object?> rows) async {
      try {
        if (cancel?.isCancelled ?? false) {
          fail(ArchiveImportFailure.cancelled);
          toWorker!.send('abort');
          return;
        }
        final section = archiveSections.firstWhere((s) => s.name == name);
        await _sink.insert(section, [
          for (final r in rows) (r! as Map).cast<String, Object?>(),
        ]);
        toWorker!.send('ack');
      } catch (e) {
        targetFailure = e is ArchiveImportException
            ? e.failure
            : ArchiveImportFailure.targetFailed;
        fail(targetFailure!);
        toWorker?.send('abort');
      }
    }

    fromWorker.listen((Object? m) {
      if (m is SendPort) {
        toWorker = m;
      } else if (m is List && m.first == 'rows') {
        unawaited(handleRows(m[1]! as String, m[2]! as List<Object?>));
      } else if (m is List && m.first == 'done') {
        if (!done.isCompleted) done.complete();
      } else if (m is List && m.first == 'error') {
        fail(
          targetFailure ??
              ArchiveImportFailure.values.firstWhere(
                (f) => f.name == m[1],
                orElse: () => ArchiveImportFailure.readFailed,
              ),
        );
      }
    });
    errors.listen((Object? _) => fail(ArchiveImportFailure.readFailed));
    exits.listen((Object? _) {
      // Normalfall: 'done' oder 'error' kam schon. Sonst ist der Isolate ohne
      // Antwort gestorben; kurze Frist, falls die Nachricht noch läuft.
      Future<void>.delayed(const Duration(seconds: 1), () {
        fail(ArchiveImportFailure.readFailed);
      });
    });

    try {
      try {
        await _sink.begin();
      } catch (e) {
        throw ArchiveImportException(
          e is ArchiveImportException
              ? e.failure
              : ArchiveImportFailure.targetFailed,
        );
      }
      if (cancel != null) {
        poll = Timer.periodic(const Duration(milliseconds: 100), (_) {
          if (cancel.isCancelled) fail(ArchiveImportFailure.cancelled);
        });
      }
      isolate = await Isolate.spawn(
        _worker,
        _ImportInit(
          reply: fromWorker.sendPort,
          path: path,
          password: password,
          cipherFactory: _cipherFactory,
          batchRows: _batchRows,
        ),
        onError: errors.sendPort,
        onExit: exits.sendPort,
        errorsAreFatal: true,
      );
      await done.future;
      if (cancel?.isCancelled ?? false) {
        throw const ArchiveImportException(ArchiveImportFailure.cancelled);
      }
      try {
        await _sink.commit();
      } catch (e) {
        throw ArchiveImportException(
          e is ArchiveImportException
              ? e.failure
              : ArchiveImportFailure.targetFailed,
        );
      }
    } catch (e) {
      isolate?.kill(priority: Isolate.immediate);
      try {
        await _sink.abort();
      } catch (_) {}
      if (e is ArchiveImportException) rethrow;
      throw const ArchiveImportException(ArchiveImportFailure.readFailed);
    } finally {
      poll?.cancel();
      isolate?.kill();
      fromWorker.close();
      errors.close();
      exits.close();
    }
  }
}

class _ImportInit {
  const _ImportInit({
    required this.reply,
    required this.path,
    required this.password,
    required this.cipherFactory,
    required this.batchRows,
  });

  final SendPort reply;
  final String path;
  final String password;
  final ArchiveCipherFactory cipherFactory;
  final int batchRows;
}

class _Aborted implements Exception {
  const _Aborted();
}

/// Arbeits-Isolate: Datei lesen, entschlüsseln, entpacken, Zeilen prüfen,
/// Stapel schicken und auf die Quittung warten. Antwortet mit 'done' oder
/// 'error' (Name der [ArchiveImportFailure]). Schreibt nichts auf den
/// Datenträger.
Future<void> _worker(_ImportInit init) async {
  final inbox = ReceivePort();
  init.reply.send(inbox.sendPort);
  final it = StreamIterator<Object?>(inbox);
  try {
    await for (final batch in readArchive(
      file: File(init.path).openRead(),
      cipher: init.cipherFactory(),
      password: init.password,
      batchRows: init.batchRows,
    )) {
      init.reply.send(<Object>['rows', batch.section.name, batch.rows]);
      if (!await it.moveNext() || it.current != 'ack') throw const _Aborted();
    }
    init.reply.send(<Object>['done']);
  } catch (e) {
    final kind = switch (e) {
      _Aborted() => ArchiveImportFailure.cancelled,
      ArchiveImportException(:final failure) => failure,
      FileSystemException() => ArchiveImportFailure.readFailed,
      _ => ArchiveImportFailure.damaged,
    };
    init.reply.send(<Object>['error', kind.name]);
  } finally {
    inbox.close();
  }
}
