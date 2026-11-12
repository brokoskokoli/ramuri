import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_plan.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_warning.dart';
import '../fitness/load_profile.dart';
import '../fitness/personal_load_factor.dart';
import '../recalculation/recalculation_service.dart';
import '../recalculation/run_load_values.dart';
import '../recalculation/value_calculation_service.dart';
import '../plan/plan_unit.dart';
import '../settings/load_settings.dart';
import 'pause_days.dart';
import 'training_load.dart';

/// Stand des persönlichen Faktors TRIMP/sRPE für das aktive Profil
/// (FR-0097, PAR-086, PAR-087).
class LoadFactorState {
  const LoadFactorState({
    required this.profile,
    required this.value,
    required this.runCount,
    required this.eligibleRuns,
    required this.unavailable,
    required this.adoptedDay,
    required this.offered,
  });

  /// Das Profil, zu dem der Faktor gehört.
  final LoadProfile profile;

  /// Der angewandte Faktor; `null`: keiner (Umrechnung unmöglich, die
  /// betroffenen Einheiten sind unbewertet).
  final double? value;

  /// Läufe im Median des angewandten Faktors (bei der Übernahme).
  final int runCount;

  /// Geeignete Läufe (TRIMP des Profils und sRPE) im Moment der Abfrage.
  final int eligibleRuns;

  /// Warum der berechnete Faktor fehlt; `null`, wenn er berechenbar ist.
  final FactorUnavailableReason? unavailable;

  /// Tag der Übernahme des angewandten Faktors.
  final DateTime? adoptedDay;

  /// Ein neuer Faktor wartet auf die Bestätigung (Neuberechnung angeboten).
  final LoadFactorRecord? offered;

  /// Der angewandte Faktor gilt weiter, obwohl die Mindestanzahl PAR-086 im
  /// 180-Tage-Fenster aktuell nicht erfüllt ist (Festlegung WP19: einmal
  /// angewandt, bleibt er; „Vorher“ in PAR-086 heißt vor dem ersten Erreichen).
  bool get unsupported => value != null && unavailable != null;

  /// PAR-087: Faktor da, aber unter 20 Läufen „noch wenig gesichert“.
  bool get tentative =>
      value != null && runCount < personalLoadFactorParameters.securedRuns;
}

/// Belastungsstand für die Seite Fortschritt: Verlauf, Grundlage und Stand.
class TrainingLoadReport {
  const TrainingLoadReport({
    required this.series,
    required this.profile,
    required this.profileIssues,
    required this.factor,
    required this.today,
    required this.seriesEnd,
    required this.todayEmpty,
    required this.calculatedAt,
  });

  /// Verlauf mit Methode und Version; leer ohne Einheiten.
  final TrainingLoadSeries series;

  /// Das aktive Profil. Ist es nicht anwendbar ([profileIssues]), gibt es
  /// keine TRIMP-Last (Läufe sind unbewertet bzw. nur über sRPE), nie eine
  /// stille andere Skala.
  final LoadProfile profile;
  final List<LoadProfileIssue> profileIssues;

  final LoadFactorState factor;

  /// Lokaler Kalendertag (UTC-Mitternacht des Datums).
  final DateTime today;

  /// Letzter Tag des Verlaufs: heute, bei leerem heutigen Tag gestern
  /// (ein leerer Tag geht nicht als Last 0 ein, FR-0103).
  final DateTime seriesEnd;
  final bool todayEmpty;

  final DateTime calculatedAt;

  bool get profileApplicable => profileIssues.isEmpty;
}

/// Baut den Belastungsstand aus der Datenbank (WP19, FR-0097 bis FR-0104,
/// FR-0199): sammelt je lokalem Kalendertag die Einheiten und ruft
/// [computeTrainingLoad].
///
/// Einheiten:
/// * Lauf mit TRIMP des aktiven Profils (gültiger Puls): TRIMP.
/// * Lauf, dessen TRIMP „nicht verfügbar“ ist (kein gültiger Puls): sRPE mit
///   Faktor, gekennzeichnet; ohne RPE unbewertet.
/// * Lauf ohne TRIMP-Wert, oder mit TRIMP einer anderen Skala (Methode passt
///   nicht zum aktiven Profil): unbewertet, nie 0 und nie gemischt.
/// * Nachgetragenes Training (Lauf oder Sonstiges): sRPE mit Faktor.
///
/// [load] hat Nebenwirkungen auf Einstellungen: es übernimmt einen neuen
/// Faktor innerhalb der Toleranz still oder bietet ihn über
/// [RecalculationService] an (`personalFactor`).
class TrainingLoadService {
  TrainingLoadService({
    required this.session,
    required this.clock,
    required ValueCalculationService calculation,
    required RecalculationService recalculation,
  }) : _calc = calculation,
       _recalc = recalculation;

  final StorageSession session;
  final Clock clock;
  final ValueCalculationService _calc;
  final RecalculationService _recalc;

  Future<TrainingLoadReport> load() async {
    final now = clock.now();
    final local = now.add(clock.utcOffsetAt(now));
    final today = DateTime.utc(local.year, local.month, local.day);
    final settings = session.settings;

    final profile = await LoadSettings.activeProfile(settings);
    final resolution = await _calc.loadResolution(await _calc.profileBasis());
    final model = resolution.model;
    final allRecorded = await LoadSettings.allRecorded(settings);

    final runs = [
      for (final r in await session.runs.list())
        if (r.state == RunState.finished && r.endedAt != null) r,
    ];
    final trimps = await session.values.readRunValues({trimpRunValueKey});
    final subjective = await session.subjective.readAll();

    final units = <LoadUnit>[];
    final factorRuns = <FactorRun>[];
    for (final run in runs) {
      final day = DateTime.parse('${dayOfRun(run)}T00:00:00Z');
      final trimp = trimps[run.id]?[trimpRunValueKey];
      final srpe = subjective[run.id]?.srpe;
      final rpe = subjective[run.id]?.subjective.rpe;
      if (trimp == null) {
        // Kein TRIMP-Wert (alter Lauf, nie gerechnet): ohne Aussage.
        units.add(LoadUnit.run(day: day));
      } else if (trimp.value == null) {
        // Kein gültiger Puls (oder Profil nicht anwendbar): sRPE.
        units.add(LoadUnit.run(day: day, srpePoints: srpe?.points));
      } else if (model != null &&
          trimp.method == model.method &&
          trimp.methodVersion == model.methodVersion) {
        units.add(LoadUnit.run(day: day, trimp: trimp.value));
        if (srpe != null && rpe != null) {
          factorRuns.add(
            FactorRun(
              time: run.endedAt!,
              trimp: trimp.value!,
              srpePoints: srpe.points,
              rpe: rpe,
            ),
          );
        }
      } else {
        // TRIMP einer anderen Skala: weder verwenden noch als 0 zählen.
        units.add(LoadUnit.run(day: day));
      }
    }
    for (final t in await session.manualTrainings.list()) {
      units.add(
        LoadUnit.manual(
          day: t.training.day,
          srpePoints: t.training.srpe.points,
        ),
      );
    }

    final factor = await _syncFactor(
      profile: profile,
      applicable: model != null,
      factorRuns: factorRuns,
      now: now,
      today: today,
    );

    // Ein leerer heutiger Tag geht nicht als Last 0 ein: der Verlauf endet
    // gestern, außer heute gibt es Einheiten (auch unbewertete).
    final todayEmpty = !units.any((u) => _sameDay(u.day, today));
    final end = todayEmpty ? today.subtract(const Duration(days: 1)) : today;
    final expected = await _expectedUnitsPerDay(units, today);
    final pauseAnswer = await WarningState(settings).pauseAnswer();
    final series = computeTrainingLoad(
      profile: profile,
      units: units,
      factor: factor.value,
      confirmsAllRecorded: allRecorded,
      today: end,
      expectedUnitsPerDay: expected,
      confirmedPauseDays: confirmedPauseDays(
        answer: pauseAnswer,
        unitDays: [for (final u in units) u.day],
      ),
    );
    return TrainingLoadReport(
      series: series,
      profile: profile,
      profileIssues: resolution.issues,
      factor: factor,
      today: today,
      seriesEnd: end,
      todayEmpty: todayEmpty,
      calculatedAt: now,
    );
  }

  /// Erwartete Einheiten je Tag aus dem aktuellen Plan (FR-0103, PAR-090):
  /// geplante Läufe (ohne Ruhetage) der Tage vor heute, heute nur mit
  /// zugeordnetem Lauf (der Tag ist nicht vorbei). `null` ohne Plan oder ohne
  /// Einheiten: dann gelten alle erfassten Einheiten als erwartet.
  Future<Map<DateTime, int>?> _expectedUnitsPerDay(
    List<LoadUnit> units,
    DateTime today,
  ) async {
    final s = session;
    if (s is! PlanStorage || units.isEmpty) return null;
    var first = units.first.day;
    for (final u in units) {
      if (u.day.isBefore(first)) first = u.day;
    }
    final planned = await (s as PlanStorage).plans.unitsBetween(first, today);
    final expected = <DateTime, int>{};
    for (final u in planned) {
      if (u.kind == PlanUnitKind.rest) continue;
      if (_sameDay(u.day, today) && u.runId == null) continue;
      expected[u.day] = (expected[u.day] ?? 0) + 1;
    }
    return expected.isEmpty ? null : expected;
  }

  static int? _ageDays(DateTime today, DateTime? day) =>
      day == null ? null : today.difference(day).inDays;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Berechnet den Faktor, übernimmt ihn still, bietet ihn an oder lässt den
  /// alten (PAR-087). Ein gespeicherter Faktor eines anderen Profils gilt
  /// nicht: nach einem Profilwechsel zählt der Faktor des neuen Profils. Ist
  /// das Profil nicht anwendbar, bleibt alles Gespeicherte unangetastet.
  Future<LoadFactorState> _syncFactor({
    required LoadProfile profile,
    required bool applicable,
    required List<FactorRun> factorRuns,
    required DateTime now,
    required DateTime today,
  }) async {
    final settings = session.settings;
    final stored = await LoadSettings.factor(settings);
    final storedHere = stored != null && stored.profile == profile
        ? stored
        : null;
    var pending = await LoadSettings.pendingFactor(settings);
    if (!applicable) {
      return LoadFactorState(
        profile: profile,
        value: null,
        runCount: 0,
        eligibleRuns: 0,
        unavailable: null,
        adoptedDay: null,
        offered: pending?.profile == profile ? pending : null,
      );
    }
    if (pending != null && pending.profile != profile) {
      await _recalc.withdrawPersonalFactor();
      pending = null;
    }
    final fresh = computePersonalLoadFactor(factorRuns, now: now);
    final eligible = fresh.runCount;

    if (!fresh.available) {
      // PAR-086 („Vorher“ = vor dem ersten Erreichen der Mindestanzahl): ein
      // einmal angewandter Faktor bleibt, auch wenn das 180-Tage-Fenster die
      // Mindestanzahl später nicht mehr hält (Festlegung WP19). Kein
      // rückwirkendes Unbewertet-Werden; der Zustand trägt den Grund
      // ([LoadFactorState.unsupported]) und bleibt gekennzeichnet.
      if (pending != null) await _recalc.withdrawPersonalFactor();
      return LoadFactorState(
        profile: profile,
        value: storedHere?.value,
        runCount: storedHere?.runs ?? 0,
        eligibleRuns: eligible,
        unavailable: fresh.unavailable,
        adoptedDay: storedHere?.day,
        offered: null,
      );
    }

    final candidate = LoadFactorRecord(
      profile: profile,
      value: fresh.value!,
      runs: fresh.runCount,
      day: today,
    );
    final decision = decideFactorAdoption(
      stored: storedHere?.value,
      storedAgeDays: _ageDays(today, storedHere?.day),
      fresh: candidate.value,
    );
    if (decision == FactorDecision.adopt) {
      if (pending != null) await _recalc.withdrawPersonalFactor();
      final same =
          storedHere != null &&
          storedHere.value == candidate.value &&
          storedHere.runs == candidate.runs;
      if (!same) await LoadSettings.writeFactor(settings, candidate, at: now);
      final record = same ? storedHere : candidate;
      return LoadFactorState(
        profile: profile,
        value: record.value,
        runCount: record.runs,
        eligibleRuns: eligible,
        unavailable: null,
        adoptedDay: record.day,
        offered: null,
      );
    }

    // Abweichung über der Toleranz: Angebot, es sei denn, ein ähnlicher
    // Faktor wurde schon abgelehnt.
    final declined = await LoadSettings.declinedFactor(settings);
    // Eine Ablehnung gilt nur bis [priorValueDays] (PAR-087, wie der Vorwert);
    // danach vergleicht der Faktor normal. Das Alter bleibt deshalb aus dem
    // Vergleich heraus (sonst gäbe eine alte Ablehnung „adopt“ für jeden Wert).
    final declinedAge = declined == null ? null : _ageDays(today, declined.day);
    final suppressed =
        declined != null &&
        declined.profile == profile &&
        declinedAge! <= personalLoadFactorParameters.priorValueDays &&
        decideFactorAdoption(stored: declined.value, fresh: candidate.value) ==
            FactorDecision.adopt;
    LoadFactorRecord? offered;
    if (!suppressed) {
      if (pending == null) {
        offered = (await _recalc.requestPersonalFactor(candidate))
            .personalFactor;
      } else {
        if (pending != candidate) {
          await LoadSettings.writePendingFactor(settings, candidate, at: now);
        }
        offered = candidate;
      }
    } else if (pending != null) {
      await _recalc.withdrawPersonalFactor();
    }
    return LoadFactorState(
      profile: profile,
      value: storedHere!.value,
      runCount: storedHere.runs,
      eligibleRuns: eligible,
      unavailable: null,
      adoptedDay: storedHere.day,
      offered: offered,
    );
  }
}
