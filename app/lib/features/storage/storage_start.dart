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

  /// Falscher Schlüssel oder beschädigte Datei (SQLite NOTADB oder CORRUPT).
  unreadable,

  /// Sonstiger Fehler beim Öffnen (E/A, Rechte, Sperre, voller Speicher). Die
  /// Datei kann gesund sein: Neubeginn erst nach einem Fehlversuch.
  openFailed,

  /// Die Datei hat eine neuere Schemaversion als diese App (Herabstufen).
  newerVersion,

  /// Die Migration auf die Version dieser App ist gescheitert.
  migrationFailed,

  /// Die Einrichtung der Verbindung (PRAGMAs wie WAL) hat nicht den verlangten
  /// Wert geliefert.
  configurationFailed,

  /// Die Prüfung, ob Dateien da sind, ist selbst gescheitert. Das sagt nichts
  /// über den Schlüsselspeicher oder die Datei.
  fileCheckError,

  /// Der Speicherort der Datei ließ sich nicht bestimmen. Es gibt nichts zu
  /// löschen, also nie Neubeginn.
  locationError,
}

/// Die zentrale Regel für den Neubeginn (OQ-0062, Entscheidung des
/// Maintainers): Neubeginn nur, wo es eine Datei zum Ersetzen gibt.
/// - Schlüssel fehlt oder unbrauchbar, Datei unlesbar: sofort.
/// - Alle anderen Fälle, in denen sich die Datei nicht öffnen lässt: erst nach
///   einem gescheiterten "Erneut versuchen" ([retryFailed], gezählt wie bei
///   der Schlüsselablage; nach einem App-Neustart wieder 0). Der Neubeginn
///   braucht stets die ausdrückliche Bestätigung mit Hinweis auf den
///   Datenverlust, bis dahin bleiben die Dateien unberührt.
/// - Speicherort unbekannt: nie (nichts zu löschen).
bool canResetFor(StorageNotOpenableCause cause, {required bool retryFailed}) =>
    switch (cause) {
      StorageNotOpenableCause.keyMissing ||
      StorageNotOpenableCause.keyMalformed ||
      StorageNotOpenableCause.unreadable => true,
      StorageNotOpenableCause.keyStoreError ||
      StorageNotOpenableCause.newerVersion ||
      StorageNotOpenableCause.migrationFailed ||
      StorageNotOpenableCause.configurationFailed ||
      StorageNotOpenableCause.openFailed ||
      StorageNotOpenableCause.fileCheckError => retryFailed,
      StorageNotOpenableCause.locationError => false,
    };

/// Was ein Neubeginn schon an den alten Daten verändert hat. Ab dem Aufruf von
/// `deleteAll` stimmt "die Daten wurden nicht verändert" nicht mehr.
enum StorageDataLoss {
  /// Es wurde nichts gelöscht.
  none,

  /// Das Löschen lief, die Prüfung danach hat noch Dateien gefunden.
  partial,

  /// Alle Dateien sind weg; der Schlüssel oder das Öffnen der neuen
  /// Datenbank ist danach gescheitert.
  deleted,
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
    this.dataLoss = StorageDataLoss.none,
  });

  final StorageNotOpenableCause cause;

  /// Gesetzt, wenn der letzte Neubeginn fehlgeschlagen ist.
  final StorageResetProblem? resetProblem;

  /// Ein Neubeginn läuft.
  final bool busy;

  /// "Erneut versuchen" ist mit derselben Fehlerart schon einmal gescheitert.
  /// Ein vorübergehender Fehler (etwa gesperrtes Gerät) darf nicht sofort zum
  /// Neubeginn führen.
  final bool retryFailed;

  /// Was der Neubeginn schon gelöscht hat. Ist es nicht `none`, zeigt die
  /// Oberfläche statt der Ursache den wahren Zustand (nicht "unverändert").
  final StorageDataLoss dataLoss;

  /// Siehe [canResetFor].
  bool get canReset => canResetFor(cause, retryFailed: retryFailed);

  StorageNotOpenableState _with({
    StorageResetProblem? resetProblem,
    bool busy = false,
  }) => StorageNotOpenableState(
    cause,
    resetProblem: resetProblem,
    busy: busy,
    retryFailed: retryFailed,
    dataLoss: dataLoss,
  );
}

/// Die Verschlüsselung ist zur Laufzeit nicht aktiv. Die Datei ist nicht
/// schuld: kein Neubeginn, nichts wird verändert.
final class StorageEncryptionInactive extends StorageStartState {
  const StorageEncryptionInactive({this.dataLoss = StorageDataLoss.none});

  /// Was ein bestätigter Neubeginn davor schon gelöscht hat.
  final StorageDataLoss dataLoss;
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

  /// Fehlerart des vorigen Ladevorgangs (null: er war erfolgreich oder es gab
  /// ihn nicht). Gleiche Art zweimal hintereinander ergibt `retryFailed`.
  StorageNotOpenableCause? _lastCause;

  /// Ab dem Löschen im Neubeginn bis zum erfolgreichen Öffnen.
  StorageDataLoss _dataLoss = StorageDataLoss.none;

  void _set(StorageStartState s) {
    _state = s;
    notifyListeners();
  }

  /// Lädt: Schlüssel und Dateien prüfen, dann öffnen. Auch für "Erneut
  /// versuchen". Läuft schon ein Vorgang oder ist der Speicher bereit, tut es
  /// nichts.
  ///
  /// Hat ein Neubeginn schon Daten verändert ([StorageDataLoss] nicht `none`),
  /// setzt es den Neubeginn fort, statt Reste der alten Daten zu öffnen: Ein
  /// bestätigter Neubeginn wird im laufenden Prozess nicht vergessen. Nach
  /// einem App-Neustart gilt wieder die normale Entscheidung.
  Future<void> start() async {
    if (_running || _state is StorageReady) return;
    final current = _state;
    _running = true;
    try {
      if (current is StorageNotOpenableState &&
          _dataLoss != StorageDataLoss.none) {
        await _reset(current);
        return;
      }
      _set(const StorageLoading());
      await _load();
    } finally {
      _running = false;
    }
  }

  Future<void> _load() async {
    final before = _lastCause;
    _lastCause = null;
    void fail(StorageNotOpenableCause cause) {
      _lastCause = cause;
      _set(
        StorageNotOpenableState(
          cause,
          retryFailed: cause == before,
          dataLoss: _dataLoss,
        ),
      );
    }

    final StorageWiring wiring;
    try {
      wiring = await wire();
    } catch (_) {
      fail(StorageNotOpenableCause.locationError);
      return;
    }
    // Reste einer abgebrochenen Wiederherstellung (WP12): eine Zwischen-
    // datenbank wird nie weiterverwendet, nur gelöscht. Scheitert das, bleibt
    // sie liegen (verschlüsselt, ungenutzt); der Start geht trotzdem weiter.
    try {
      await wiring.files.deleteImport();
    } catch (_) {}
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
        fail(StorageNotOpenableCause.fileCheckError);
      } else {
        fail(StorageNotOpenableCause.keyStoreError);
      }
      return;
    }
    final Uint8List key;
    switch (decision) {
      case StorageNotOpenable(:final reason):
        fail(switch (reason) {
          StorageNotOpenableReason.keyMissing =>
            StorageNotOpenableCause.keyMissing,
          StorageNotOpenableReason.keyMalformed =>
            StorageNotOpenableCause.keyMalformed,
        });
        return;
      case OpenExistingStorage(key: final k) || CreateNewStorage(key: final k):
        key = k;
    }
    try {
      final session = await wiring.storage.open(key);
      _dataLoss = StorageDataLoss.none;
      _set(StorageReady(session));
    } on StorageException catch (e) {
      switch (e.failure) {
        case StorageFailure.encryptionNotActive:
          _set(StorageEncryptionInactive(dataLoss: _dataLoss));
        case StorageFailure.newerVersion:
          fail(StorageNotOpenableCause.newerVersion);
        case StorageFailure.migrationFailed:
          fail(StorageNotOpenableCause.migrationFailed);
        case StorageFailure.configurationFailed:
          fail(StorageNotOpenableCause.configurationFailed);
        case StorageFailure.unreadable:
          fail(StorageNotOpenableCause.unreadable);
        default:
          // Alles andere kann eine gesunde Datei sein: kein sofortiger Neubeginn.
          fail(StorageNotOpenableCause.openFailed);
      }
    } catch (_) {
      fail(StorageNotOpenableCause.openFailed);
    }
  }

  StorageNotOpenableState _stateWith(
    StorageNotOpenableState s, {
    required StorageResetProblem resetProblem,
  }) => StorageNotOpenableState(
    s.cause,
    resetProblem: resetProblem,
    retryFailed: s.retryFailed,
    dataLoss: _dataLoss,
  );

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
      await _reset(current);
    } finally {
      _running = false;
    }
  }

  Future<void> _reset(StorageNotOpenableState current) async {
    _set(current._with(busy: true));
    final StorageWiring wiring;
    try {
      wiring = await wire();
    } catch (_) {
      _set(current._with(resetProblem: StorageResetProblem.filesNotDeleted));
      return;
    }
    // Ab hier können Daten verloren sein, auch wenn das Löschen scheitert.
    // Der Merker steigt nur: nach `deleted` fällt er nicht auf `partial`.
    if (_dataLoss == StorageDataLoss.none) {
      _dataLoss = StorageDataLoss.partial;
    }
    try {
      await wiring.files.deleteAll();
      if (await wiring.files.exist()) {
        throw StateError('Datei nach dem Löschen noch da');
      }
    } catch (_) {
      _set(
        _stateWith(current, resetProblem: StorageResetProblem.filesNotDeleted),
      );
      return;
    }
    _dataLoss = StorageDataLoss.deleted;
    try {
      await keyStore.delete(storageKeyName);
    } catch (_) {
      _set(
        _stateWith(current, resetProblem: StorageResetProblem.keyNotReplaced),
      );
      return;
    }
    _lastCause = null;
    _set(const StorageLoading());
    await _load();
  }
}
