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
