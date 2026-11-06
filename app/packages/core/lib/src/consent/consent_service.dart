import '../../ports/clock.dart';
import '../../ports/storage_consents.dart';

/// Ergebnis eines Widerrufs (SEC-0007).
class RevocationOutcome {
  const RevocationOutcome({required this.askDeleteImportedData});

  /// `true`: Die Oberfläche fragt, ob bereits importierte Daten dieser Quelle
  /// gelöscht werden sollen. Gelöscht wird nie ohne diese Entscheidung.
  final bool askDeleteImportedData;
}

/// Einwilligung je Quelle (SEC-0001, SEC-0002, SEC-0007). Jede Quelle hat einen
/// eigenen Zustand; die Freigabe einer Quelle gilt nie für eine andere.
///
/// Die Prüfung ist fail-closed: Nur ein gelesenes `granted` gibt frei. Fehlt
/// der Eintrag oder scheitert das Lesen, gilt die Quelle als nicht freigegeben.
class ConsentService {
  ConsentService(this._store, this._clock);

  final ConsentStore _store;
  final Clock _clock;

  /// Widerrufe dieser Sitzung wirken sofort, auch wenn das Schreiben scheitert
  /// und im Speicher noch `granted` steht.
  final Set<String> _revokedHere = {};

  Future<bool> isGranted(String sourceKey) async {
    if (_revokedHere.contains(sourceKey)) return false;
    try {
      return await _store.get(sourceKey) == ConsentState.granted;
    } catch (_) {
      return false;
    }
  }

  /// Erteilt die Einwilligung für genau diese Quelle. Scheitert das
  /// Schreiben, bleibt sie verweigert und der Fehler geht an den Aufrufer.
  Future<void> grant(String sourceKey) async {
    await _store.set(sourceKey, ConsentState.granted, at: _clock.now());
    _revokedHere.remove(sourceKey);
  }

  /// Widerruft die Einwilligung für genau diese Quelle. Sie wirkt ab diesem
  /// Aufruf, auch wenn das Speichern scheitert (dann wirft der Aufruf nach dem
  /// Sperren).
  Future<RevocationOutcome> revoke(String sourceKey) async {
    var wasGranted = true; // Unlesbarer Stand: vorsichtshalber fragen.
    try {
      wasGranted = await _store.get(sourceKey) == ConsentState.granted;
    } catch (_) {}
    _revokedHere.add(sourceKey);
    await _store.set(sourceKey, ConsentState.revoked, at: _clock.now());
    _revokedHere.remove(sourceKey);
    return RevocationOutcome(askDeleteImportedData: wasGranted);
  }
}
