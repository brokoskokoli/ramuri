import 'dart:io';

import 'package:core/core.dart';

/// Hilfen für Tests der Tageszuordnung, die in jeder Zeitzone laufen. Das Gate
/// führt sie zusätzlich unter mehreren Zeitzonen aus (Umgebung `TZ`).

/// Versatz zur UTC Mitte Januar und Mitte Juli [year] in der Zeitzone des
/// Prozesses. Unterscheiden sie sich, hat die Zone Sommerzeit.
(Duration, Duration) winterSummerOffset(int year) => (
  DateTime.utc(year, 1, 15, 12).toLocal().timeZoneOffset,
  DateTime.utc(year, 7, 15, 12).toLocal().timeZoneOffset,
);

bool zoneHasDst(int year) {
  final (w, s) = winterSummerOffset(year);
  return w != s;
}

/// Erwartete Versätze (Januar, Juli) der Zeitzonen, unter denen das Gate die
/// Tests ausführt. So fällt auf, wenn `TZ` nicht wirkt (fehlende Zonendaten
/// führen sonst still zu UTC).
const Map<String, (Duration, Duration)> knownZones = {
  'UTC': (Duration.zero, Duration.zero),
  'America/Los_Angeles': (Duration(hours: -8), Duration(hours: -7)),
  'Pacific/Auckland': (Duration(hours: 13), Duration(hours: 12)),
  'Europe/Berlin': (Duration(hours: 1), Duration(hours: 2)),
};

/// Wert der Umgebung `TZ` (null, wenn nicht gesetzt).
String? get processTz => Platform.environment['TZ'];

/// Alle Ortstage des Jahres [year] in der Zeitzone des Prozesses.
List<DayRange> localDaysOfYear(int year) {
  final first = DateTime(year);
  final n = DateTime(year + 1).difference(first).inDays + 1;
  return [
    for (final d in localDayRanges(first, n + 1))
      if (d.start.toLocal().year == year) d,
  ];
}

/// Ortstage von [year], die nicht 24 h lang sind (Sommerzeitwechsel).
List<DayRange> dstDays(int year) => [
  for (final d in localDaysOfYear(year))
    if (d.end.difference(d.start) != const Duration(hours: 24)) d,
];

/// Ein Ortstag samt Vortag und Folgetag in der Zeitzone des Prozesses.
class LocalDayCase {
  LocalDayCase(this.label, this.prev, this.day, this.next);

  /// Ortstag, der [at] (Ortszeit) enthält.
  factory LocalDayCase.around(String label, DateTime at) {
    final r = localDayRanges(DateTime(at.year, at.month, at.day - 1), 3);
    return LocalDayCase(label, r[0], r[1], r[2]);
  }

  final String label;
  final DayRange prev;
  final DayRange day;
  final DayRange next;

  Duration get length => day.end.difference(day.start);

  /// Kalendertag des Ortstags als Schlüssel (wie die Readiness-Reihen).
  DateTime get key {
    final l = day.start.toLocal();
    return DateTime.utc(l.year, l.month, l.day);
  }
}

/// Die zu prüfenden Ortstage der aktuellen Zone: ein gewöhnlicher Tag im
/// Januar und im Juli und, wenn die Zone Sommerzeit hat, der kurze (23 h) und
/// der lange (25 h) Tag des Jahres [year].
List<LocalDayCase> localDayCases(int year) {
  final out = [
    LocalDayCase.around('15.01. (Ortszeit)', DateTime(year, 1, 15)),
    LocalDayCase.around('15.07. (Ortszeit)', DateTime(year, 7, 15)),
  ];
  for (final d in dstDays(year)) {
    final l = d.start.toLocal();
    final h = d.end.difference(d.start).inHours;
    out.add(
      LocalDayCase.around(
        'Zeitumstellung ${l.day}.${l.month}. ($h h)',
        DateTime(l.year, l.month, l.day),
      ),
    );
  }
  return out;
}

/// Ortstage mit Zeitumstellung unabhängig von der Zone des Prozesses, als
/// UTC-Zeitpunkte gebildet (Mitteleuropa 2026: 29.03. mit 23 h, 25.10. mit
/// 25 h). Damit laufen die Grenzfälle auch unter UTC.
final List<LocalDayCase> fixedDstCases = [
  LocalDayCase(
    'fest: 29.03.2026 Mitteleuropa (23 h)',
    DayRange(DateTime.utc(2026, 3, 27, 23), DateTime.utc(2026, 3, 28, 23)),
    DayRange(DateTime.utc(2026, 3, 28, 23), DateTime.utc(2026, 3, 29, 22)),
    DayRange(DateTime.utc(2026, 3, 29, 22), DateTime.utc(2026, 3, 30, 22)),
  ),
  LocalDayCase(
    'fest: 25.10.2026 Mitteleuropa (25 h)',
    DayRange(DateTime.utc(2026, 10, 23, 22), DateTime.utc(2026, 10, 24, 22)),
    DayRange(DateTime.utc(2026, 10, 24, 22), DateTime.utc(2026, 10, 25, 23)),
    DayRange(DateTime.utc(2026, 10, 25, 23), DateTime.utc(2026, 10, 26, 23)),
  ),
];
