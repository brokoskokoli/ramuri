import 'dart:async';

import 'package:adapters/adapters.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';

import 'map_consent_dialog.dart';
import 'map_services.dart';

/// Stand der Einwilligung zum Kartenanbieter.
enum MapConsentStatus {
  /// Nie gefragt (oder der Eintrag fehlt).
  neverAsked,

  /// Erteilt.
  granted,

  /// Widerrufen, oder der Stand war nicht lesbar (fail-closed).
  declined,
}

/// Ergebnis von [MapConsentController.revoke].
class MapRevokeResult {
  const MapRevokeResult({
    required this.askDeleteCache,
    required this.saveFailed,
  });

  /// Die Oberfläche fragt, ob der Kartenspeicher gelöscht wird (SEC-0007).
  final bool askDeleteCache;

  /// Der Widerruf wirkt in dieser Sitzung, wurde aber nicht gespeichert.
  final bool saveFailed;
}

/// Einstiegspunkt der Oberfläche für den Kartenanbieter (WP13, ADR-0009 Punkt 3): Stand der Einwilligung, die Frage
/// beim ersten Öffnen einer Karte, Erteilen und Widerrufen, Kartenspeicher und die Kachelquelle. Eine Instanz je
/// Sitzung. Die Kachelquelle entsteht nur bei erteilter Einwilligung; ein Lesefehler gilt als nicht erteilt.
class MapConsentController extends ChangeNotifier {
  MapConsentController({
    required ConsentStore store,
    required Clock clock,
    required this.services,
    void Function()? clearTileMemory,
  }) : _store = store,
       _clearTileMemory = clearTileMemory ?? clearMapTileMemory,
       _service = ConsentService(store, clock) {
    ready = _load();
  }

  final ConsentStore _store;
  final ConsentService _service;
  final MapServices services;
  final void Function() _clearTileMemory;

  /// Fertig, sobald der gespeicherte Stand gelesen ist (auch bei Lesefehler).
  late final Future<void> ready;

  MapConsentStatus _status = MapConsentStatus.declined; // bis zum Lesen: zu
  bool _granted = false;
  bool _deferred = false;
  bool _disposed = false;
  Future<bool>? _asking;

  MapConsentStatus get status => _status;

  /// Einwilligung für das Tor: wird bei jeder Anfrage gelesen und fällt mit dem Widerruf sofort.
  bool get granted => _granted;

  Future<void> _load() async {
    try {
      final state = await _store.get(mapProviderSourceKey);
      _granted = await _service.isGranted(mapProviderSourceKey);
      _status = _granted
          ? MapConsentStatus.granted
          : state == null
          ? MapConsentStatus.neverAsked
          : MapConsentStatus.declined;
    } catch (_) {
      _granted = false;
      _status = MapConsentStatus.declined;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Fragt beim ersten Öffnen einer Karte (nie beim App-Start). Gibt zurück, ob die Einwilligung erteilt ist. Nach
  /// "Nicht jetzt" fragt sie in dieser Sitzung nicht erneut; nach einem Widerruf fragt sie nie, dafür sind die
  /// Einstellungen da.
  ///
  /// Die Frage geht nur auf, solange die Seite oben liegt (kein Dialog, keine andere Route darüber) und [mayAsk]
  /// (falls gegeben) es erlaubt; beides wird erst nach dem Warten auf den Stand geprüft, denn bis dahin kann sich
  /// vieles geändert haben. Sonst bleibt es bei `false`, ohne "Nicht jetzt": gefragt wird beim nächsten Bedarf.
  Future<bool> ensureAsked(
    BuildContext context, {
    bool Function()? mayAsk,
  }) async {
    await ready;
    if (_granted) return true;
    if (_status != MapConsentStatus.neverAsked || _deferred) return false;
    if (!context.mounted) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    if (mayAsk != null && !mayAsk()) return false;
    return _asking ??= _ask(context).whenComplete(() => _asking = null);
  }

  Future<bool> _ask(BuildContext context) async {
    final yes = await showMapConsentDialog(context);
    if (yes != true) {
      _deferred = true;
      return false;
    }
    return grant();
  }

  /// Erteilt die Einwilligung. `false`, wenn das Speichern scheitert (dann bleibt sie verweigert).
  Future<bool> grant() async {
    await ready;
    try {
      await _service.grant(mapProviderSourceKey);
    } catch (_) {
      return false;
    }
    _granted = true;
    _status = MapConsentStatus.granted;
    _notify();
    return true;
  }

  /// Widerruft. Ab dem Aufruf geht keine Anfrage mehr ins Netz, auch wenn das Speichern scheitert.
  Future<MapRevokeResult> revoke() async {
    await ready;
    _granted = false;
    _status = MapConsentStatus.declined;
    _clearTileMemory(); // dekodierte Kacheln nicht im Arbeitsspeicher stehen lassen (SEC-0007)
    _notify();
    try {
      final out = await _service.revoke(mapProviderSourceKey);
      return MapRevokeResult(
        askDeleteCache: out.askDeleteImportedData,
        saveFailed: false,
      );
    } catch (_) {
      return const MapRevokeResult(askDeleteCache: true, saveFailed: true);
    }
  }

  /// "Alles löschen" ([deleteAll] löscht die Daten): Schon **vor** dem Löschen fällt die Einwilligung im Prozess
  /// (Tor zu, Warteschlange und Quellen der Miniaturen stoppen über die Hörer), damit nichts mehr aus dem
  /// Speicher gelöscht wird und eine laufende Miniatur nach dem Löschen nichts schreibt. Danach gilt der Stand des
  /// ersten Starts: nie gefragt, auch bei `deletedNotErased` (die Daten sind dann gelöscht). Scheitert das Löschen
  /// ganz, gilt wieder der gespeicherte Stand. Der Kartenspeicher wird nach dem Löschen noch einmal abgeräumt, falls
  /// eine Schreibung durchkam. Der Fehler von [deleteAll] wird weitergegeben.
  Future<void> deleteAllAround(Future<void> Function() deleteAll) async {
    await ready;
    _granted = false;
    _status = MapConsentStatus.declined;
    _clearTileMemory();
    _notify();
    var erased = false;
    try {
      await deleteAll();
      erased = true;
    } on StorageException catch (e) {
      erased = e.failure == StorageFailure.deletedNotErased;
      rethrow;
    } finally {
      if (erased) {
        _status = MapConsentStatus.neverAsked;
        _deferred = false;
        _clearTileMemory();
        try {
          await services.cache.delete();
        } catch (_) {}
        _notify();
      } else {
        await _load(); // nichts gelöscht: der gespeicherte Stand gilt
      }
    }
  }

  /// Größe des Kartenspeichers in Bytes; `null`, wenn nicht zu ermitteln.
  Future<int?> cacheSizeBytes() async {
    try {
      return await services.cache.sizeBytes();
    } catch (_) {
      return null;
    }
  }

  /// Löscht den Kartenspeicher. `false`, wenn es scheitert.
  Future<bool> deleteCache() async {
    try {
      await services.cache.delete();
    } catch (_) {
      return false;
    }
    _notify();
    return true;
  }

  /// Öffnet die Kachelquelle. Ohne Einwilligung `null`, und es gibt keine Anfrage (fail-closed). Wirft
  /// [MapSourceUnavailable], wenn der Anbieter nicht erreichbar ist. [maxParallel] begrenzt die gleichzeitigen
  /// Anfragen der Quelle (Miniaturen: höchstens 4, R008 Hinweis 6).
  Future<MapTileSource?> openSource({int? maxParallel}) async {
    await ready;
    if (!_granted) return null;
    final gate = services.gate(() => _granted)..maxParallel = maxParallel;
    return MapTileSource.open(gate);
  }

  final StreamController<int> _removedRuns = StreamController<int>.broadcast(
    sync: true,
  );

  /// Läufe, deren Miniatur entfernt wird (Löschen eines Laufs); laufende Erzeugungen für sie brechen ab.
  Stream<int> get removedRuns => _removedRuns.stream;

  /// Entfernt die Miniatur des gelöschten Laufs [runId] aus dem Kartenspeicher, auch ohne Einwilligung (rein
  /// lokal), und bricht ihre Erzeugung ab. Fehler sind kein Wurf: der Lauf ist dann schon gelöscht.
  Future<void> deleteRunThumbnails(int runId) async {
    if (!_removedRuns.isClosed) _removedRuns.add(runId);
    try {
      await services.thumbnails?.deleteRun(runId);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _granted = false; // Tore einer noch offenen Quelle sagen ab jetzt nein
    _status = MapConsentStatus.declined;
    _removedRuns.close();
    super.dispose();
  }
}
