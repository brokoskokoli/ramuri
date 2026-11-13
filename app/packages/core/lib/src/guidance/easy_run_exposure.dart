import 'guidance_parameters.dart';

/// Pulsverhalten eines lockeren Laufs für den Gehpausen-Hinweis (PAR-107).
///
/// Quelle der Werte: die gespeicherten Zonenzeiten je Lauf
/// (`StoredRunLoad.zoneTimes`, Zone 1 bis 5, und `belowZone1Time`, aus
/// `recalculation/run_load_values.dart`). Locker ist Zone 1 bis 2 (PAR-109);
/// „über der oberen Grenze“ ist also Zone 3 bis 5.
class EasyRunExposure {
  const EasyRunExposure({required this.aboveUpper, required this.known});

  /// Aus Zonenzeiten (Index 0 = Zone 1, mindestens 3 Einträge) und der Zeit
  /// unter Zone 1.
  factory EasyRunExposure.fromZoneTimes(
    List<Duration> zoneTimes, {
    Duration belowZone1 = Duration.zero,
  }) {
    var above = Duration.zero;
    var known = belowZone1;
    for (var i = 0; i < zoneTimes.length; i++) {
      known += zoneTimes[i];
      if (i >= 2) above += zoneTimes[i];
    }
    return EasyRunExposure(aboveUpper: above, known: known);
  }

  /// Zeit über der oberen Grenze.
  final Duration aboveUpper;

  /// Zeit mit bekanntem Puls.
  final Duration known;

  /// Mehr als [mostlyAboveShare] der bekannten Zeit über der Grenze.
  bool get mostlyAbove =>
      known > Duration.zero &&
      aboveUpper.inMicroseconds > known.inMicroseconds * mostlyAboveShare;
}

/// PAR-107: Wurde die obere Pulsgrenze in den letzten 3 lockeren Einheiten
/// überwiegend überschritten? [lastEasyRuns] sind die lockeren Läufe,
/// neueste zuerst; es zählen die ersten [walkBreakHintRunCount]. Weniger Läufe: `false`. Läufe ohne bekannten Puls
/// zählen als „nicht darüber“ (kein Beleg, kein Hinweis). Auslegung: mindestens
/// [walkBreakHintMinRuns] dieser Läufe sind je „überwiegend darüber“.
bool easyRunsMostlyAboveUpper(List<EasyRunExposure> lastEasyRuns) {
  if (lastEasyRuns.length < walkBreakHintRunCount) return false;
  final n = lastEasyRuns
      .take(walkBreakHintRunCount)
      .where((r) => r.mostlyAbove)
      .length;
  return n >= walkBreakHintMinRuns;
}
