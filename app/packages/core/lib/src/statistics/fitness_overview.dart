import '../../ports/storage.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_values.dart';
import '../fitness/vo2max_estimator.dart';
import '../recalculation/run_analysis.dart'
    show aerobicEfficiencyValueKey, vo2maxLongTermValueKey, vo2maxRunValueKey;
import '../recalculation/value_calculation_service.dart' show dayOfRun;

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

/// Die gespeicherten Fitnesswerte für die Statistik (FR-0081, FR-0084). Nichts
/// davon wird hier gerechnet: Es sind die `current`-Werte aus WP09. Eine
/// Schätzung ist es immer (FR-0067); ohne gespeicherten Wert gibt es keinen.
class FitnessOverview {
  FitnessOverview({
    required List<RunEstimate> runEstimates,
    required this.longTerm,
    required this.efficiency,
    required this.pendingRuns,
    this.day,
    this.readFailed = false,
  }) : runEstimates = List.unmodifiable(runEstimates);

  /// Die Fitnesswerte ließen sich nicht lesen.
  FitnessOverview.failed()
    : runEstimates = const [],
      longTerm = null,
      efficiency = null,
      day = null,
      pendingRuns = 0,
      readFailed = true;

  /// Schätzungen aus einzelnen Läufen, nach Laufende aufsteigend (Sicht 1 und
  /// Grundlage des Verlaufs, Sicht 3). Enthält auch Läufe, deren Wert „nicht
  /// bestimmbar“ ist.
  final List<RunEstimate> runEstimates;

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
      if (runs.isNotEmpty) {
        day = dayOfRun(runs.last);
        for (final p in await session.values.read(ValueOwner.day(day))) {
          if (p.current.key == vo2maxLongTermValueKey) longTerm = p.current;
          if (p.current.key == aerobicEfficiencyValueKey) {
            efficiency = p.current;
          }
        }
      }
      return FitnessOverview(
        runEstimates: estimates,
        longTerm: longTerm,
        efficiency: efficiency,
        pendingRuns: pending,
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
