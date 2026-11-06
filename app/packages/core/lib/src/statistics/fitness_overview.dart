import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/vo2max_estimator.dart';
import '../recalculation/run_analysis.dart'
    show aerobicEfficiencyValueKey, vo2maxLongTermValueKey, vo2maxRunValueKey;
import '../recalculation/value_calculation_service.dart' show dayOfRun;
import 'period.dart';
import 'statistics_parameters.dart';

/// Die gespeicherte VO₂max-Schätzung eines Laufs (`current`, WP09). Der Wert
/// kann fehlen; dann steht der Grund in [value] (`unavailableReason`).
class RunEstimate {
  const RunEstimate({
    required this.runId,
    required this.endedAt,
    required this.day,
    required this.value,
  });

  final int runId;
  final DateTime endedAt;

  /// Lokaler Kalendertag des Laufendes (K21).
  final String day;
  final ComputedValue value;
}

/// Die gespeicherte langfristige VO₂max-Schätzung eines Tages (`current`).
class DayEstimate {
  const DayEstimate({required this.day, required this.value});

  /// Kalendertag `JJJJ-MM-TT`.
  final String day;
  final ComputedValue value;
}

/// Die gespeicherten Fitnesswerte für die Statistik (FR-0081, FR-0084). Nichts
/// davon wird hier gerechnet: Es sind die `current`-Werte aus WP09. Eine
/// Schätzung ist es immer (FR-0067); ohne gespeicherten Wert gibt es keinen.
class FitnessOverview {
  FitnessOverview({
    required List<RunEstimate> runEstimates,
    required this.longTerm,
    required this.efficiency,
    required this.pendingRuns,
    List<DayEstimate> longTermByDay = const [],
    this.day,
    this.readFailed = false,
  }) : runEstimates = List.unmodifiable(runEstimates),
       longTermByDay = List.unmodifiable(longTermByDay);

  /// Die Fitnesswerte ließen sich nicht lesen.
  FitnessOverview.failed()
    : runEstimates = const [],
      longTermByDay = const [],
      longTerm = null,
      efficiency = null,
      day = null,
      pendingRuns = 0,
      readFailed = true;

  /// Schätzungen aus einzelnen Läufen, nach Laufende aufsteigend (Sicht 1 und
  /// Grundlage des Verlaufs, Sicht 3). Enthält auch Läufe, deren Wert „nicht
  /// bestimmbar“ ist.
  final List<RunEstimate> runEstimates;

  /// Die langfristigen Schätzungen aller Tage mit gespeichertem Wert, nach Tag
  /// aufsteigend (Grundlage des Verlaufs, FR-0081 Sicht 3). Enthält auch Tage,
  /// deren Wert „nicht bestimmbar“ ist.
  final List<DayEstimate> longTermByDay;

  /// Verlauf über Wochen (FR-0081 Sicht 3): je Kalenderwoche (Beginn nach
  /// [firstDayOfWeek]) der zuletzt gespeicherte bestimmbare Tageswert, die
  /// neuesten [maxWeeks] Wochen mit Wert, älteste zuerst. Ein Lauf allein ist
  /// keine Fitnessänderung (FR-0078); die Tageswerte sind bereits die
  /// langfristigen.
  List<DayEstimate> weeklyLongTerm({
    int maxWeeks = 12,
    int firstDayOfWeek = DateTime.monday,
  }) {
    final byWeek = <String, DayEstimate>{};
    for (final e in longTermByDay) {
      if (e.value.value == null) continue;
      final week = StatisticsPeriod.weekOf(
        e.day,
        parameters: StatisticsParameters(firstDayOfWeek: firstDayOfWeek),
      ).firstDay!;
      byWeek[week] = e; // aufsteigend: der spätere Tag der Woche gewinnt
    }
    final weeks = byWeek.keys.toList()..sort();
    final last = weeks.length > maxWeeks
        ? weeks.sublist(weeks.length - maxWeeks)
        : weeks;
    return [for (final w in last) byWeek[w]!];
  }

  /// Tag (`JJJJ-MM-TT`) des neuesten Laufs, dem die Tageswerte gehören; `null`
  /// ohne beendete Läufe.
  final String? day;

  /// Langfristige Schätzung des Tages des neuesten Laufs (Sicht 2); `null`,
  /// wenn für diesen Tag keiner gespeichert ist.
  final ComputedValue? longTerm;

  /// Aerobe Effizienz (Veränderung) desselben Tages; `null`, wenn keine
  /// gespeichert ist.
  final ComputedValue? efficiency;

  /// Beendete Läufe ohne gespeicherten Laufwert: Die Berechnung nach dem Lauf
  /// steht aus oder ist gescheitert (sie wird beim Start nachgeholt).
  final int pendingRuns;

  final bool readFailed;
}

/// Liest die Fitnesswerte gebündelt: eine Abfrage für alle Laufwerte und eine
/// für die Tageswerte des neuesten Laufs (kein Zugriff je Lauf).
class FitnessOverviewService {
  FitnessOverviewService({required this.session});

  final StorageSession session;

  /// [finishedRuns]: alle beendeten Läufe (mit Laufende).
  Future<FitnessOverview> load(Iterable<StoredRun> finishedRuns) async {
    try {
      final runs = [
        for (final r in finishedRuns)
          if (r.endedAt != null) r,
      ]..sort((a, b) => a.endedAt!.compareTo(b.endedAt!));
      final stored = await session.values.readRunValues({vo2maxRunValueKey});
      final estimates = <RunEstimate>[];
      var pending = 0;
      for (final r in runs) {
        final v = stored[r.id]?[vo2maxRunValueKey];
        if (v == null) {
          pending++;
        } else {
          estimates.add(
            RunEstimate(
              runId: r.id,
              endedAt: r.endedAt!,
              day: dayOfRun(r),
              value: v,
            ),
          );
        }
      }
      ComputedValue? longTerm;
      ComputedValue? efficiency;
      String? day;
      // Eine Abfrage für alle Tage: Verlauf und die Werte des neuesten Tages.
      final days = await session.values.readDayValues({
        vo2maxLongTermValueKey,
        aerobicEfficiencyValueKey,
      });
      if (runs.isNotEmpty) {
        day = dayOfRun(runs.last);
        longTerm = days[day]?[vo2maxLongTermValueKey];
        efficiency = days[day]?[aerobicEfficiencyValueKey];
      }
      final trend = [
        for (final e in days.entries)
          if (e.value[vo2maxLongTermValueKey] != null)
            DayEstimate(day: e.key, value: e.value[vo2maxLongTermValueKey]!),
      ]..sort((a, b) => a.day.compareTo(b.day));
      return FitnessOverview(
        runEstimates: estimates,
        longTerm: longTerm,
        efficiency: efficiency,
        pendingRuns: pending,
        longTermByDay: trend,
        day: day,
      );
    } on StorageException {
      return FitnessOverview.failed();
    }
  }

  /// Der Laufwert mit den bewerteten Abschnitten (für Hinweise zu einer
  /// einzelnen Schätzung); `null`, wenn keiner gespeichert ist oder das Lesen
  /// scheitert.
  Future<ComputedValue?> runValueWithSections(int runId) async {
    try {
      for (final p in await session.values.read(ValueOwner.run(runId))) {
        if (p.current.key == vo2maxRunValueKey) return p.current;
      }
    } on StorageException {
      return null;
    }
    return null;
  }
}

/// Mindestens ein Abschnitt hatte Gewicht 0 und ging nicht in die Schätzung ein
/// ([EstimateDiscard.zeroWeight]).
bool hasZeroWeightSection(ComputedValue v) =>
    v.sections.any((s) => s.discard == EstimateDiscard.zeroWeight);
