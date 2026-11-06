import '../recalculation/value_calculation_service.dart' show isoDay;
import 'statistics_parameters.dart';

/// Art des Auswertungszeitraums (FR-0044).
enum PeriodKind { run, week, month, custom }

/// Auswertungszeitraum nach FR-0044: einzelner Lauf, Kalenderwoche, Monat oder
/// frei gewählter Zeitraum. Tage sind lokale Kalendertage als `JJJJ-MM-TT`
/// (K21), beide Enden eingeschlossen; Rechnen mit Tagen kennt keine
/// Sommerzeit. Ein Jahr ist in der Spec nicht vorgesehen.
class StatisticsPeriod {
  const StatisticsPeriod._(
    this.kind,
    this.firstDay,
    this.lastDay,
    this.runId, [
    this.firstDayOfWeek = DateTime.monday,
  ]);

  /// Ein einzelner Lauf; er gehört zu keinem Tagesbereich.
  const StatisticsPeriod.singleRun(int runId)
    : this._(PeriodKind.run, null, null, runId);

  /// Die Kalenderwoche, die [day] enthält. Den Wochenbeginn legt allein
  /// [StatisticsParameters.firstDayOfWeek] fest; die Woche merkt ihn sich für
  /// [previous].
  factory StatisticsPeriod.weekOf(
    String day, {
    StatisticsParameters parameters = const StatisticsParameters(),
  }) {
    final firstDayOfWeek = parameters.firstDayOfWeek;
    final d = _parse(day);
    final back = (d.weekday - firstDayOfWeek) % DateTime.daysPerWeek;
    final first = d.subtract(Duration(days: back));
    return StatisticsPeriod._(
      PeriodKind.week,
      _format(first),
      _format(first.add(const Duration(days: DateTime.daysPerWeek - 1))),
      null,
      firstDayOfWeek,
    );
  }

  /// Der Kalendermonat, der [day] enthält.
  factory StatisticsPeriod.monthOf(String day) {
    final d = _parse(day);
    return StatisticsPeriod._(
      PeriodKind.month,
      _format(DateTime.utc(d.year, d.month)),
      // Tag 0 des Folgemonats ist der letzte Tag dieses Monats.
      _format(DateTime.utc(d.year, d.month + 1, 0)),
      null,
    );
  }

  /// Frei gewählter Zeitraum von [from] bis [to], beide eingeschlossen. Wirft
  /// [ArgumentError], wenn [to] vor [from] liegt; über den Jahreswechsel ist er
  /// erlaubt.
  factory StatisticsPeriod.custom({required String from, required String to}) {
    final a = _parse(from);
    final b = _parse(to);
    if (b.isBefore(a)) {
      throw ArgumentError.value(to, 'to', 'liegt vor dem Beginn');
    }
    return StatisticsPeriod._(PeriodKind.custom, from, to, null);
  }

  final PeriodKind kind;

  /// Erster und letzter Tag; `null` beim einzelnen Lauf.
  final String? firstDay;
  final String? lastDay;
  final int? runId;

  /// Wochenbeginn einer Woche (`DateTime.monday` bis `sunday`); sonst ohne Bedeutung.
  final int firstDayOfWeek;

  /// Ob ein Lauf mit Id [id] und Tag [day] in den Zeitraum fällt.
  bool contains({required int id, required String day}) => switch (kind) {
    PeriodKind.run => id == runId,
    _ => day.compareTo(firstDay!) >= 0 && day.compareTo(lastDay!) <= 0,
  };

  /// Der gleichartige Zeitraum davor (Woche bzw. Monat), für Vergleiche
  /// (FR-0043 „Entwicklung“). `null` für Lauf und freien Zeitraum.
  StatisticsPeriod? previous() {
    final first = firstDay;
    switch (kind) {
      case PeriodKind.week:
        return StatisticsPeriod.weekOf(
          _format(_parse(first!).subtract(const Duration(days: 1))),
          parameters: StatisticsParameters(firstDayOfWeek: firstDayOfWeek),
        );
      case PeriodKind.month:
        return StatisticsPeriod.monthOf(
          _format(_parse(first!).subtract(const Duration(days: 1))),
        );
      case PeriodKind.run:
      case PeriodKind.custom:
        return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is StatisticsPeriod &&
      other.kind == kind &&
      other.firstDay == firstDay &&
      other.lastDay == lastDay &&
      other.runId == runId;

  @override
  int get hashCode => Object.hash(kind, firstDay, lastDay, runId);

  @override
  String toString() => 'StatisticsPeriod($kind, $firstDay..$lastDay, $runId)';
}

final RegExp _isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');

DateTime _parse(String day) {
  if (_isoDay.hasMatch(day)) {
    final d = DateTime.tryParse('${day}T00:00:00Z');
    // Ungültige Tage (30. Februar) werden von DateTime verschoben.
    if (d != null && _format(d) == day) return d;
  }
  throw ArgumentError.value(day, 'day', 'kein Kalendertag JJJJ-MM-TT');
}

String _format(DateTime d) => isoDay(d);
