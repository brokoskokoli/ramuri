import 'package:core/core.dart';

/// [FakeClock], deren Versatz der Zone des Testprozesses folgt (`TZ`), wie
/// die Systemuhr der App (`SystemClock.utcOffsetAt`). Damit liegen der
/// Ortstag über [Clock.utcOffsetAt] („Heute“, Laufstart) und der über
/// `toLocal()` (Plan, `calendarDay`) auf demselben Tag, in jeder Zone.
///
/// Setzt ein Test [utcOffset], gilt dieser feste Versatz wie bei [FakeClock].
class LocalFakeClock extends FakeClock {
  /// [start] ist ein Zeitpunkt, in Tests meist Ortszeit (`DateTime(…)`).
  LocalFakeClock(super.start);

  Duration? _fixed;

  @override
  Duration get utcOffset => _fixed ?? now().toLocal().timeZoneOffset;

  @override
  set utcOffset(Duration d) => _fixed = d;

  @override
  Duration utcOffsetAt(DateTime at) =>
      _fixed ?? at.toUtc().toLocal().timeZoneOffset;
}

/// Ortszeit [hour]:[minute] am Kalendertag [day] (Jahr, Monat, Tag von
/// [day], etwa einem Plantag als UTC-Mitternacht).
DateTime localAt(DateTime day, [int hour = 0, int minute = 0]) =>
    DateTime(day.year, day.month, day.day, hour, minute);
