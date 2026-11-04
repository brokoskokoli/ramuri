import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

/// Ports, die erst nach dem Auflösen des Datenbankpfads zur Verfügung stehen.
class StorageWiring {
  const StorageWiring({required this.storage, required this.files});

  final Storage storage;
  final DatabaseFiles files;
}

/// Warum die Datenbank nicht geöffnet werden kann (OQ-0062).
enum StorageNotOpenableCause {
  /// Datei da, Schlüssel fehlt in der Ablage.
  keyMissing,

  /// Datei da, abgelegter Schlüssel unbrauchbar (nicht 32 Byte).
  keyMalformed,

  /// Die Schlüsselablage lässt sich nicht lesen oder beschreiben.
  keyStoreError,

  /// Falscher Schlüssel oder beschädigte Datei.
  unreadable,

  /// Die Datei hat eine neuere Schemaversion als diese App (Herabstufen). Die
  /// Datei ist gesund: nur "Erneut versuchen", kein Neubeginn.
  newerVersion,

  /// Die Migration auf die Version dieser App ist gescheitert (Fehler der App
  /// bei gesunder Datei): nur "Erneut versuchen", kein Neubeginn.
  migrationFailed,

  /// Die Prüfung, ob Dateien da sind, ist selbst gescheitert. Das sagt nichts
  /// über den Schlüsselspeicher oder die Datei: nur "Erneut versuchen".
  fileCheckError,

  /// Der Speicherort der Datei ließ sich nicht bestimmen. Es gibt nichts zu
  /// löschen; angeboten wird nur "Erneut versuchen".
  locationError,
}

/// Was beim Neubeginn schiefging (die Oberfläche zeigt es an).
enum StorageResetProblem {
  /// Die alte Datei ließ sich nicht (vollständig) löschen. Es wurde kein neuer
  /// Schlüssel angelegt.
  filesNotDeleted,

  /// Die alte Datei ist gelöscht, der Schlüssel ließ sich nicht erneuern.
  keyNotReplaced,
}

/// Zustand des App-Starts. Vor [StorageReady] gibt es keinen Zugriff auf
/// Inhalte: Nur dieser Zustand trägt die Sitzung.
sealed class StorageStartState {
  const StorageStartState();
}

final class StorageLoading extends StorageStartState {
  const StorageLoading();
}

final class StorageReady extends StorageStartState {
  const StorageReady(this.session);

  final StorageSession session;
}

final class StorageNotOpenableState extends StorageStartState {
  const StorageNotOpenableState(
    this.cause, {
    this.resetProblem,
    this.busy = false,
    this.retryFailed = false,
  });

  final StorageNotOpenableCause cause;

  /// Gesetzt, wenn der letzte Neubeginn fehlgeschlagen ist.
  final StorageResetProblem? resetProblem;

  /// Ein Neubeginn läuft.
  final bool busy;

  /// Bei [StorageNotOpenableCause.keyStoreError]: "Erneut versuchen" ist
  /// schon einmal gescheitert. Ein vorübergehender Fehler der Schlüsselablage
  /// (etwa gesperrtes Gerät) darf nicht sofort zum Neubeginn führen.
  final bool retryFailed;

  /// Neubeginn wird nur angeboten, wo es eine Datei zum Ersetzen gibt und die
  /// Datei als Ursache gilt oder der Schlüssel dauerhaft unbrauchbar scheint.
  /// Nie bei gesunder Datei (neuere Version, Migration) und nie, wenn die
  /// Dateiprüfung selbst scheiterte.
  bool get canReset => switch (cause) {
    StorageNotOpenableCause.keyMissing ||
    StorageNotOpenableCause.keyMalformed ||
    StorageNotOpenableCause.unreadable => true,
    StorageNotOpenableCause.keyStoreError => retryFailed,
    StorageNotOpenableCause.newerVersion ||
    StorageNotOpenableCause.migrationFailed ||
    StorageNotOpenableCause.fileCheckError ||
    StorageNotOpenableCause.locationError => false,
  };

  StorageNotOpenableState _with({
    StorageResetProblem? resetProblem,
    bool busy = false,
  }) => StorageNotOpenableState(
    cause,
    resetProblem: resetProblem,
    busy: busy,
    retryFailed: retryFailed,
  );
}

/// Die Verschlüsselung ist zur Laufzeit nicht aktiv. Die Datei ist nicht
/// schuld: kein Neubeginn, nichts wird verändert.
final class StorageEncryptionInactive extends StorageStartState {
  const StorageEncryptionInactive();
}

/// Zustandsautomat des App-Starts: laden, dann bereit, nicht zu öffnen oder
/// Verschlüsselung nicht aktiv. Rein testbar mit Fakes.
class StorageStartController extends ChangeNotifier {
  StorageStartController({
    required this.keyStore,
    required this.wire,
    required this.generateKey,
  });

  final KeyStore keyStore;
  final Future<StorageWiring> Function() wire;
  final Uint8List Function() generateKey;

  StorageStartState _state = const StorageLoading();
  StorageStartState get state => _state;

  bool _running = false;

  /// Der vorige Ladevorgang endete mit einem Fehler der Schlüsselablage.
  bool _keyStoreFailed = false;

  void _set(StorageStartState s) {
    _state = s;
    notifyListeners();
  }

  /// Lädt: Schlüssel und Dateien prüfen, dann öffnen. Auch für "Erneut
  /// versuchen". Läuft schon ein Vorgang oder ist der Speicher bereit, tut es
  /// nichts.
  Future<void> start() async {
    if (_running || _state is StorageReady) return;
    _running = true;
    try {
      _set(const StorageLoading());
      await _load();
    } finally {
      _running = false;
    }
  }

  Future<void> _load() async {
    final keyStoreFailedBefore = _keyStoreFailed;
    _keyStoreFailed = false;
    final StorageWiring wiring;
    try {
      wiring = await wire();
    } catch (_) {
      _set(
        const StorageNotOpenableState(StorageNotOpenableCause.locationError),
      );
      return;
    }
    final StorageStart decision;
    var fileCheckFailed = false;
    try {
      decision = await StorageKeyService(
        keyStore: keyStore,
        databaseFilesExist: () async {
          try {
            return await wiring.files.exist();
          } catch (_) {
            fileCheckFailed = true;
            rethrow;
          }
        },
        generateKey: generateKey,
      ).decide();
    } catch (_) {
      // Nichts wurde angelegt oder gelöscht, und es wird nie still neu angelegt.
      if (fileCheckFailed) {
        // Der Fehler gehört nicht dem Schlüsselspeicher.
        _set(
          const StorageNotOpenableState(StorageNotOpenableCause.fileCheckError),
        );
      } else {
        _keyStoreFailed = true;
        _set(
          StorageNotOpenableState(
            StorageNotOpenableCause.keyStoreError,
            retryFailed: keyStoreFailedBefore,
          ),
        );
      }
      return;
    }
    final Uint8List key;
    switch (decision) {
      case StorageNotOpenable(:final reason):
        _set(
          StorageNotOpenableState(switch (reason) {
            StorageNotOpenableReason.keyMissing =>
              StorageNotOpenableCause.keyMissing,
            StorageNotOpenableReason.keyMalformed =>
              StorageNotOpenableCause.keyMalformed,
          }),
        );
        return;
      case OpenExistingStorage(key: final k) || CreateNewStorage(key: final k):
        key = k;
    }
    try {
      _set(StorageReady(await wiring.storage.open(key)));
    } on StorageException catch (e) {
      _set(switch (e.failure) {
        StorageFailure.encryptionNotActive => const StorageEncryptionInactive(),
        StorageFailure.newerVersion => const StorageNotOpenableState(
          StorageNotOpenableCause.newerVersion,
        ),
        StorageFailure.migrationFailed => const StorageNotOpenableState(
          StorageNotOpenableCause.migrationFailed,
        ),
        _ => const StorageNotOpenableState(StorageNotOpenableCause.unreadable),
      });
    } catch (_) {
      _set(const StorageNotOpenableState(StorageNotOpenableCause.unreadable));
    }
  }

  /// Neubeginn mit leerer Datenbank. Nur aus "nicht zu öffnen" und nur, nachdem
  /// der Nutzer ausdrücklich bestätigt hat (das stellt die Oberfläche sicher).
  ///
  /// Reihenfolge, die einen Abbruch an jeder Stelle übersteht: (1) alle
  /// Dateien löschen und prüfen, dass keine mehr da ist; erst dann (2) den
  /// alten Schlüssel entfernen; (3) neuer Schlüssel und Öffnen über [start].
  /// Bis (1) fertig ist, wird der Schlüssel nie angefasst, es liegt also nie
  /// ein neuer Schlüssel neben der alten Datei. Schlägt (1) fehl, entsteht kein
  /// Schlüssel.
  Future<void> resetStorage() async {
    final current = _state;
    if (_running || current is! StorageNotOpenableState || !current.canReset) {
      return;
    }
    _running = true;
    try {
      _set(current._with(busy: true));
      final StorageWiring wiring;
      try {
        wiring = await wire();
        await wiring.files.deleteAll();
        if (await wiring.files.exist()) {
          throw StateError('Datei nach dem Löschen noch da');
        }
      } catch (_) {
        _set(current._with(resetProblem: StorageResetProblem.filesNotDeleted));
        return;
      }
      try {
        await keyStore.delete(storageKeyName);
      } catch (_) {
        _set(current._with(resetProblem: StorageResetProblem.keyNotReplaced));
        return;
      }
      _set(const StorageLoading());
      await _load();
    } finally {
      _running = false;
    }
  }
}
