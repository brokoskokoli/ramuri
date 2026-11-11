import 'package:core/core.dart';

import '../../l10n/app_localizations.dart';

/// Texte der Plan-Seite aus den Codes von `core` (WP22 Teil B). Nur
/// Zuordnung, keine Rechnung.

/// Kurzform der Phase für den Phasenbalken (OQ-0077).
String planPhaseShort(AppLocalizations l, PlanPhase p) => switch (p) {
  PlanPhase.entry => l.planPhaseEntry,
  PlanPhase.build => l.planPhaseBuild,
  PlanPhase.reduction => l.planPhaseReduction,
};

/// Voller Name der Phase für die Erklärung (FR-0141, OQ-0077).
String planPhaseFull(AppLocalizations l, PlanPhase p) => switch (p) {
  PlanPhase.entry => l.planPhaseEntryFull,
  PlanPhase.build => l.planPhaseBuildFull,
  PlanPhase.reduction => l.planPhaseReductionFull,
};

String planKindName(AppLocalizations l, PlanUnitKind k) => switch (k) {
  PlanUnitKind.easy => l.planKindEasy,
  PlanUnitKind.long => l.planKindLong,
  PlanUnitKind.intervals => l.planKindIntervals,
  PlanUnitKind.tempo => l.planKindTempo,
  PlanUnitKind.progressive => l.planKindProgressive,
  PlanUnitKind.walkRun => l.planKindWalkRun,
  PlanUnitKind.rest => l.planRestDay,
};

/// Trainingsziel der Einheit (FR-0142, FR-0143).
String planKindPurpose(AppLocalizations l, PlanUnitKind k) => switch (k) {
  PlanUnitKind.easy => l.planPurposeEasy,
  PlanUnitKind.long => l.planPurposeLong,
  PlanUnitKind.intervals => l.planPurposeIntervals,
  PlanUnitKind.tempo => l.planPurposeTempo,
  PlanUnitKind.progressive => l.planPurposeProgressive,
  PlanUnitKind.walkRun => l.planPurposeWalkRun,
  PlanUnitKind.rest => l.planPurposeRest,
};

String planSegmentName(AppLocalizations l, PlanSegmentKind k) => switch (k) {
  PlanSegmentKind.warmUp => l.planSegWarmUp,
  PlanSegmentKind.easy => l.planSegEasy,
  PlanSegmentKind.interval => l.planSegInterval,
  PlanSegmentKind.tempo => l.planSegTempo,
  PlanSegmentKind.recovery => l.planSegJogBreak,
  PlanSegmentKind.endBlock => l.planSegEndBlock,
  PlanSegmentKind.coolDown => l.planSegCoolDown,
  PlanSegmentKind.run => l.planSegRun,
  PlanSegmentKind.walk => l.planSegWalk,
};

/// Grundlage der Vorgabe nach PAR-106; unbekannter Code: `null`.
String? planBasisText(AppLocalizations l, String? code) =>
    switch (IntensityBasis.fromCode(code)) {
      IntensityBasis.reference => l.planBasisReference,
      IntensityBasis.vo2max => l.planBasisVo2max,
      IntensityBasis.heartRateZones => l.planBasisHeartRateZones,
      IntensityBasis.effort => l.planBasisEffort,
      null => null,
    };

String planDistanceName(AppLocalizations l, GoalDistance d) => switch (d) {
  GoalDistance.fiveKilometers => l.planDistance5k,
  GoalDistance.tenKilometers => l.planDistance10k,
  GoalDistance.halfMarathon => l.planDistanceHalf,
};

/// Dauer aus Minuten: unter einer Stunde „40 min“, sonst „1:05 h“.
String planDurationText(AppLocalizations l, int minutes) => minutes < 60
    ? l.planMinutes(minutes)
    : l.planHours(minutes ~/ 60, (minutes % 60).toString().padLeft(2, '0'));

/// Dauer eines Abschnitts aus Sekunden: volle Minuten „5 min“, sonst
/// „1:30 min“.
String planSegmentDuration(AppLocalizations l, int seconds) => seconds % 60 == 0
    ? planDurationText(l, seconds ~/ 60)
    : l.planDurationMinSec(
        seconds ~/ 60,
        (seconds % 60).toString().padLeft(2, '0'),
      );

/// Zielzeit eines Zeitziels: „55 min“, „52:30 min“ oder „1:58 h“ bzw.
/// „1:58:30 h“.
String planGoalTimeText(AppLocalizations l, double seconds) {
  final s = seconds.round();
  if (s < 3600) return planSegmentDuration(l, s);
  final h = s ~/ 3600;
  final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
  final rest = s % 60;
  return rest == 0
      ? l.planHours(h, m)
      : l.planHours(h, '$m:${rest.toString().padLeft(2, '0')}');
}

/// Text eines Konflikts eines bestätigten Termins (nur gemeldet).
String planConflictText(
  AppLocalizations l,
  PinnedConflict c,
  String Function(DateTime) day,
) => switch (c.kind) {
  PinnedConflictKind.spacing => l.planHintSpacing(
    day(c.day),
    c.otherDay == null ? '–' : day(c.otherDay!),
  ),
  PinnedConflictKind.dayTaken => l.planHintDayTaken(day(c.day)),
  PinnedConflictKind.noMatchingUnit => l.planHintNoMatchingUnit(day(c.day)),
  PinnedConflictKind.walkRunFirst => l.planHintWalkRunFirst(day(c.day)),
};

String planHardOmissionText(AppLocalizations l, HardOmission o) => switch (o) {
  HardOmission.tooFewRunDays => l.planHintHardTooFewRunDays,
  HardOmission.notContinuous30 => l.planHintHardNotContinuous30,
  HardOmission.exceedsMaxSession => l.planHintHardExceedsMax,
  HardOmission.noRecoveryDay => l.planHintHardNoRestDay,
  HardOmission.weekTooShort => l.planHintHardWeekTooShort,
  HardOmission.replacedByUser => l.planHintHardReplacedByUser,
};

/// Grund für eine fehlende oder seltene harte Einheit über den ganzen Plan;
/// `null`, wenn es nichts zu sagen gibt.
String? planHardFitText(AppLocalizations l, HardFitStatus s) => switch (s) {
  HardFitStatus.regulatorBelowFit => l.planHintHardRegulator,
  HardFitStatus.partialAtPeak => l.planHintHardPartial,
  HardFitStatus.neverFits => l.planHintHardNever,
  HardFitStatus.notApplicable ||
  HardFitStatus.raised ||
  HardFitStatus.atPeak => null,
};

/// Texte der Einschätzung (PAR-206): Hauptzeile, ggf. Zusatz und Grundlage
/// (PAR-106). `null` bei [FeasibilityReason.showRegularity]; die Regelmäßigkeit
/// zählt die Seite aus ihren Einheiten. [date] formatiert das Angebot.
({String main, String? extra, String basis})? planAssessmentTexts(
  AppLocalizations l,
  GoalAssessment a,
  String Function(DateTime) date,
) => switch (a.reason) {
  FeasibilityReason.peakReached => (
    main: l.planAssessFits,
    extra: null,
    basis: l.planAssessBasisCourse,
  ),
  FeasibilityReason.peakTooLate => (
    main: a.fitsFrom == null
        ? l.planAssessTight
        : l.planAssessTightFrom(date(a.fitsFrom!)),
    extra: null,
    basis: l.planAssessBasisCourse,
  ),
  FeasibilityReason.peakAboveRegulator => (
    main: l.planAssessTight,
    extra: null,
    basis: l.planAssessBasisCourse,
  ),
  FeasibilityReason.peakNotWithinHorizon => (
    main: l.planAssessTight,
    extra: l.planAssessNoDate,
    basis: l.planAssessBasisCourse,
  ),
  FeasibilityReason.improvementSmall => (
    main: l.planAssessFits,
    extra: null,
    basis: l.planAssessBasisTime,
  ),
  FeasibilityReason.improvementMedium => (
    main: l.planAssessTight,
    extra: null,
    basis: l.planAssessBasisTime,
  ),
  FeasibilityReason.improvementLarge => (
    main: l.planAssessLater,
    extra: null,
    basis: l.planAssessBasisTime,
  ),
  FeasibilityReason.noReference => (
    main: l.planAssessNoData,
    extra: null,
    basis: l.planAssessBasisTime,
  ),
  // Referenz oder Zeit vorhanden, aber zu wenige Läufe (PAR-206): sagen,
  // was fehlt (E2E API 36).
  FeasibilityReason.tooFewRuns => (
    main: l.planAssessNoData,
    extra: l.planAssessTooFewRuns(
      const FeasibilityParameters().minRuns,
      const FeasibilityParameters().runWindowDays ~/ 7,
    ),
    basis: l.planAssessBasisTime,
  ),
  FeasibilityReason.showRegularity => null,
};

/// Ungefähre Strecke in Metern für [minutes] mit dem lockeren Tempo aus
/// [inputs], nur wenn es bekannt ist (FR-0205, OQ-0077; „bekannt“ wie bei der
/// Zielspitze, PAR-205: aus mindestens `peakMinEasyRuns` Läufen). Sonst
/// `null`; Kilometer erscheinen dann nicht.
double? planApproxMeters(PlanInputs inputs, int minutes) {
  final pace = inputs.easyPaceSecondsPerKm;
  if (minutes <= 0 ||
      pace == null ||
      !pace.isFinite ||
      pace <= 0 ||
      inputs.easyRunCount < const PlanParameters().peakMinEasyRuns) {
    return null;
  }
  return minutes * 60 / pace * 1000;
}

/// Die Woche der Rechnung, die am Montag [monday] beginnt, oder `null`.
/// [GeneratedPlan.weeks] beginnt mit der Woche von „heute“, nicht mit dem
/// Anker; die Position in der Liste ist also nicht die Wochennummer.
PlanWeek? planWeekOf(List<PlanWeek> weeks, DateTime monday) {
  final m = planDay(monday);
  for (final w in weeks) {
    if (planDay(w.start) == m) return w;
  }
  return null;
}

/// Wochenzeit der Planwoche ab [monday] in Minuten, wie die Plan-Seite sie
/// zeigt: aus der Rechnung ([GeneratedPlan.weeks]), sonst die Summe der
/// Lauf-Einheiten in [units].
int planWeekMinutes({
  required GeneratedPlan? hints,
  required DateTime monday,
  required List<PlanUnit> units,
}) {
  final planned = planWeekOf(hints?.weeks ?? const [], monday)?.minutes;
  return planned ??
      units.fold<int>(
        0,
        (a, u) => u.kind == PlanUnitKind.rest ? a : a + u.minutes,
      );
}

/// Zeile einer Einheit: Art und Dauer, beim Ruhetag nur „Ruhetag“.
String planUnitText(AppLocalizations l, PlanUnit u) =>
    u.kind == PlanUnitKind.rest
    ? l.planRestDay
    : l.planUnitLine(planKindName(l, u.kind), planDurationText(l, u.minutes));
