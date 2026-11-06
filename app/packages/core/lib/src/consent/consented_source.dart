import 'consent_service.dart';

/// Eine Quelle, deren Daten nur mit Einwilligung gelesen werden dürfen.
abstract interface class ConsentedSource<T> {
  String get sourceKey;

  Future<List<T>> fetch();
}

/// Ergebnis eines geschützten Zugriffs.
sealed class ConsentedRead<T> {
  const ConsentedRead();
}

/// Keine Freigabe: Die Quelle wurde nicht berührt oder ihre Daten verworfen.
class ConsentDenied<T> extends ConsentedRead<T> {
  const ConsentDenied();
}

class ConsentedData<T> extends ConsentedRead<T> {
  const ConsentedData(this.items);
  final List<T> items;
}

/// Einziger Weg zu den Daten einer freigabepflichtigen Quelle: prüft vor dem
/// Zugriff und noch einmal danach (Widerruf während des Abrufs).
class ConsentGuard<T> {
  ConsentGuard(this._consents, this._source);

  final ConsentService _consents;
  final ConsentedSource<T> _source;

  Future<ConsentedRead<T>> read() async {
    if (!await _consents.isGranted(_source.sourceKey)) {
      return const ConsentDenied();
    }
    final items = await _source.fetch();
    if (!await _consents.isGranted(_source.sourceKey)) {
      return const ConsentDenied();
    }
    return ConsentedData(items);
  }
}
