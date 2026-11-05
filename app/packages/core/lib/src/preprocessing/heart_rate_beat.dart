import 'heart_rate_processor.dart';
import 'measurement.dart';

/// Zeiten aller eingegangenen Pulswerte, auch verworfener, aber ohne
/// `nonMonotonicTime` (deren Zeit sagt nichts über den Takt). Aufsteigend
/// sortiert.
List<DateTime> receivedHeartRateTimes(HeartRateResult heartRate) => [
  for (final p in heartRate.processed)
    if (p.reason != DiscardReason.nonMonotonicTime) p.input.time,
]..sort();

/// Median-Takt in Mikrosekunden: Median der Abstände zwischen den
/// [received] eingegangenen Werten (PAR-010, Abschnittsqualität und
/// Pulsabdeckung rechnen damit gleich). `null` ohne mindestens zwei Werte:
/// dann ist kein Takt bekannt.
int? medianBeatMicros(List<DateTime> received) {
  if (received.length < 2) return null;
  final all = [...received]..sort();
  final inner = [
    for (var i = 1; i < all.length; i++)
      all[i].difference(all[i - 1]).inMicroseconds,
  ]..sort();
  final n = inner.length;
  return n.isOdd
      ? inner[n ~/ 2]
      : ((inner[n ~/ 2 - 1] + inner[n ~/ 2]) / 2).round();
}

/// Gemeinsame Regel für Abstände zwischen Werten (Pulsabdeckung, TRIMP,
/// Zonenzeit und `SectionQuality`): Ein Abstand von [delta] Mikrosekunden bei
/// Median-Takt [beat] gilt als lückenlos, wenn nach ganzen Takten nur ein
/// Wert zu erwarten war, `round(delta / beat) <= 1`. Zeitstempel-Jitter
/// macht daraus keine Lücke; fehlt mindestens ein Wert (ab 1,5 Takten),
/// gilt die Regel nicht. Ohne Takt (`beat <= 0`) deckt nichts.
bool beatCoversGap(int delta, int beat) =>
    beat > 0 && (delta / beat).round() <= 1;

/// Fehlende Zeit eines Abstands [delta]: 0 nach [beatCoversGap], sonst
/// `delta - beat` (nie negativ).
int missingMicrosInGap(int delta, int beat) {
  if (beatCoversGap(delta, beat)) return 0;
  return delta > beat ? delta - beat : 0;
}
