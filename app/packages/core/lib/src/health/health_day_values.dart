import 'health_processing.dart';
import 'health_types.dart';

/// Ein Tag als halboffener Zeitraum [start, end). Die Tagesgrenze legt der
/// Aufrufer fest (Ortszeit samt Sommerzeit), `core` kennt keine Zeitzone.
class DayRange {
  const DayRange(this.start, this.end);
  final DateTime start;
  final DateTime end;
}

/// [count] Ortstage ab dem Ortstag von [first]; die Grenzen sind lokale
/// Mitternächte (Sommerzeit-fest, weil sie aus Jahr, Monat und Tag gebildet
/// werden).
List<DayRange> localDayRanges(DateTime first, int count) {
  final f = first.toLocal();
  return [
    for (var i = 0; i < count; i++)
      DayRange(
        DateTime(f.year, f.month, f.day + i).toUtc(),
        DateTime(f.year, f.month, f.day + i + 1).toUtc(),
      ),
  ];
}

/// Tagesliste der Ruhepuls-Tageswerte je Quell-App als Eingabe für
/// [HealthProcessing.selectSource] (PAR-189). Tage ohne gültigen Wert fehlen.
List<Map<String, HealthDailyValue>> restingHeartRateDayList(
  HealthProcessing p,
  Iterable<HealthSample> samples,
  Iterable<DayRange> days,
) {
  final out = <Map<String, HealthDailyValue>>[];
  for (final d in days) {
    final m = p.restingHeartRateDaily(samples, d.start, d.end);
    if (m.isNotEmpty) out.add(m);
  }
  return out;
}

/// Tagesliste der HRV-Tageswerte je Quell-App. Je Tag zählt die Hauptschlafphase
/// (PAR-164) der Sitzungen, die an diesem Tag enden und in den ersten 16 h des
/// Tages (Höchstalter der Hauptschlafphase) liegen; die HRV-Werte des Tages
/// werden gegen sie geprüft (PAR-160). Tage ohne Hauptschlafphase oder ohne
/// gültigen Wert fehlen.
List<Map<String, HealthDailyValue>> hrvDayList(
  HealthProcessing p,
  Iterable<HealthSample> samples,
  Iterable<SleepSession> sessions,
  Iterable<DayRange> days,
) {
  final out = <Map<String, HealthDailyValue>>[];
  for (final d in days) {
    final ending = sessions
        .where((s) => !s.end.isBefore(d.start) && s.end.isBefore(d.end))
        .toList();
    final at = d.start.add(p.params.mainSleepMaxAge);
    final main = p.mainSleep(ending, at);
    final m = p.hrvDaily(samples, main);
    if (m.isNotEmpty) out.add(m);
  }
  return out;
}
