import '../preprocessing/measurement.dart';

/// Ein zusammenhängender Abschnitt eines Laufs mit demselben Quellgerät der
/// Pulswerte (FR-0020). [start] und [end] sind Zeit des ersten und letzten
/// Werts des Abschnitts.
class HeartRateSourceSection {
  const HeartRateSourceSection({
    required this.deviceId,
    required this.start,
    required this.end,
    required this.count,
  });

  final String deviceId;
  final DateTime start;
  final DateTime end;
  final int count;
}

/// Quellgeräte der gespeicherten Pulswerte in zeitlicher Reihenfolge: ein
/// Abschnitt endet, wenn der nächste Wert (nach Zeit sortiert) von einem
/// anderen Gerät stammt. Grundlage ist `raw_heart_rates.source`; es braucht
/// kein eigenes Schema. Zeilen ohne Wert (`unavailable`) zählen nicht.
List<HeartRateSourceSection> heartRateSourceSections(
  Iterable<RawHeartRate> rows,
) {
  final sorted = [
    for (final r in rows)
      if (r.state != MeasurementState.unavailable) r,
  ]..sort((a, b) => a.time.compareTo(b.time));
  final out = <HeartRateSourceSection>[];
  for (final r in sorted) {
    if (out.isNotEmpty && out.last.deviceId == r.source) {
      final l = out.removeLast();
      out.add(
        HeartRateSourceSection(
          deviceId: l.deviceId,
          start: l.start,
          end: r.time,
          count: l.count + 1,
        ),
      );
    } else {
      out.add(
        HeartRateSourceSection(
          deviceId: r.source,
          start: r.time,
          end: r.time,
          count: 1,
        ),
      );
    }
  }
  return out;
}

/// Die verschiedenen Quellgeräte in der Reihenfolge ihres ersten Werts.
List<String> heartRateSourceDevices(Iterable<RawHeartRate> rows) {
  final seen = <String>[];
  for (final s in heartRateSourceSections(rows)) {
    if (!seen.contains(s.deviceId)) seen.add(s.deviceId);
  }
  return seen;
}
