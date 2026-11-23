import '../../ports/health_import.dart';
import 'consent_service.dart';
import 'consent_sources.dart';

/// Einziger Leseweg zu Health Connect (SEC-0001, SEC-0002, SEC-0007): prüft die eigene Einwilligung der Art vor jeder
/// Seite und noch einmal danach. Ohne Einwilligung wird der Leser nicht berührt; wird sie während des Lesens
/// widerrufen, wird die Seite verworfen. In beiden Fällen liefert [readPage] `null`, also keine Daten.
///
/// Der Import-Dienst bekommt [HealthConnectReader] nur in dieser Hülle; den rohen Leser hält nur die Verdrahtung.
final class ConsentedHealthReader {
  ConsentedHealthReader(this._reader, this.consents);

  final HealthConnectReader _reader;

  /// Die Einwilligungen, gegen die geprüft wird; der Import und die Seite nutzen dieselbe Instanz, damit ein Widerruf
  /// der Sitzung sofort gilt.
  final ConsentService consents;

  /// Eine Seite wie [HealthConnectReader.readPage], oder `null`, wenn die Einwilligung für [kind] fehlt bzw. während
  /// des Lesens widerrufen wurde. Fehler des Lesers gehen unverändert an den Aufrufer.
  Future<HealthPage?> readPage({
    required HealthDataKind kind,
    required DateTime from,
    required DateTime to,
    String? pageToken,
    int? pageSize,
  }) async {
    final key = healthSourceKey(kind);
    if (!await consents.isGranted(key)) return null;
    final page = await _reader.readPage(
      kind: kind,
      from: from,
      to: to,
      pageToken: pageToken,
      pageSize: pageSize,
    );
    if (!await consents.isGranted(key)) return null;
    return page;
  }
}
