// Abgleich der PAR-Werte im Code mit den Parameter-Dokumenten.
//
// Der Test liest die PAR-Tabellen aus docs/model-parameters.md,
// docs/planning-rules.md und docs/phase-2-3-rules.md (Spalte „Startwert“),
// zieht die Zahlen aus jeder Zelle und prüft, dass jeder in [parCodeValues]
// zugeordnete Wert aus dem Code dort vorkommt. Jede PAR-ID der Dokumente
// steht entweder in [parCodeValues] oder in [parExceptions]; eine neue ID ohne
// Eintrag macht den Test rot. Annullierte IDs brauchen keinen Eintrag.
//
// Umrechnung: Die Werte stehen hier in der Einheit der Dokumente (Prozent,
// Minuten, Sekunden, Stunden), umgerechnet aus der Einheit des Codes.
import 'dart:io';

import 'package:core/core.dart';
import 'package:test/test.dart';

const _docs = [
  '../../../docs/model-parameters.md',
  '../../../docs/planning-rules.md',
  '../../../docs/phase-2-3-rules.md',
];

double _sec(Duration d) => d.inMicroseconds / Duration.microsecondsPerSecond;
double _min(Duration d) => _sec(d) / 60;
double _hours(Duration d) => _min(d) / 60;
double _days(Duration d) => _hours(d) / 24;
double _weeks(Duration d) => _days(d) / 7;
double _pct(num share) => share * 100;

const _pre = PreprocessingParameters.v4();
const _fit = FitnessParameters.v4();
const _sel = SectionSelectionParameters();
const _vo2 = Vo2maxParameters();
const _ae = AerobicEfficiencyParameters();
const _prof = ProfileParameters.v4();
const _plan = PlanParameters();
const _pred = PredictionParameters();
const _health = HealthParameters.v4();
const _load = trainingLoadParameters;
const _factor = personalLoadFactorParameters;

const _int = IntensityParameters();
const _hint = hintParameters;
const _feas = FeasibilityParameters();

/// Alle Schritte einer Programmwoche in Minuten, dazu die Gesamtdauer jeder
/// Einheit mit Auf- und Abwärmen (PAR-065, PAR-132 bis PAR-139).
List<num> _walkRunWeek(int index) {
  final p = walkRunProgram;
  return [
    for (final session in p.weeks[index].sessions) ...[
      for (final step in session) step.seconds / 60,
      (session.fold<int>(0, (a, st) => a + st.seconds) +
              p.warmUpSeconds +
              p.coolDownSeconds) /
          60,
    ],
  ];
}

/// PAR-ID → Werte aus dem Code, in der Einheit des Dokuments.
final Map<String, List<num>> parCodeValues = {
  // docs/model-parameters.md
  'PAR-001': [_pre.positionMaxAccuracyMeters],
  'PAR-002': [_pre.hardJumpMaxSpeed],
  'PAR-003': [_pre.softJumpSpeed],
  'PAR-004': [_sec(_pre.gapMaxDuration)],
  'PAR-005': [_sec(_pre.liveSmoothingWindow), _sec(_pre.liveMinData)],
  'PAR-006': [_sec(_pre.selectionMedianWindow)],
  'PAR-007': [_pre.heartRateMin, _pre.heartRateMax],
  'PAR-009': [
    _pre.heartRateOutlierDeviation,
    _sec(_pre.heartRateOutlierWindow),
    _pre.heartRateOutlierRate,
  ],
  'PAR-010': [
    _pct(_pre.heartRateMaxMissingShare),
    _sec(_pre.heartRateMaxSingleGap),
  ],
  'PAR-011': [
    _min(_pre.settlingDuration),
    _min(_pre.settlingPaceWindow),
    _pre.settlingPaceChange,
  ],
  'PAR-012': [_pre.ascentThresholdMeters],
  'PAR-013': [
    _sec(_pre.altitudeMedianWindow),
    _pre.altitudeMaxVerticalAccuracyMeters,
  ],
  'PAR-014': [_pre.standstillBelow, _pre.movementFrom],
  'PAR-015': [_sec(_pre.standstillMinDuration), _sec(_pre.resumeMinDuration)],
  'PAR-207': [_pre.reanchorCount],
  'PAR-016': [
    _prof.maxHrRejectBelowBpm,
    _prof.maxHrRejectAboveBpm,
    _prof.maxHrHintDeviationBpm,
    ProfileParameters.approxBaseTenths / 10,
    ProfileParameters.approxPerYearTenths / 10,
  ],
  'PAR-017': [
    _prof.restHrRejectBelowBpm,
    _prof.restHrRejectAboveBpm,
    _prof.restHrHintBelowBpm,
    _prof.restHrHintAboveBpm,
  ],
  'PAR-019': [_fit.minHeartRateReserveBpm],
  'PAR-020': [_min(_sel.minDuration)],
  'PAR-021': [_min(_sel.splitLength)],
  'PAR-022': [_pct(_sel.paceMaxVariation), _pct(_sel.paceMaxHalfDifference)],
  'PAR-023': [_sel.heartRateMaxHalfDifferenceBpm],
  'PAR-024': [_min(_sel.lateHalfWeightFrom), _min(_sel.lateExcludeFrom)],
  'PAR-025': [
    _sel.gpsMaxMedianAccuracyMeters,
    _pct(_sel.gpsMinShare),
    _sel.gpsShareAccuracyMeters,
  ],
  'PAR-026': [_pct(_sel.gradientMin), _pct(_sel.gradientMax)],
  'PAR-027': [_pct(_sel.gradientUseFrom)],
  'PAR-028': [_sel.intensityMin],
  'PAR-029': [_sel.intensityMax],
  'PAR-030': [_sel.fullSpeedMetersPerMinute],
  'PAR-031': [_sel.limitedSpeedMetersPerMinute, _sel.fullSpeedMetersPerMinute],
  'PAR-032': [_vo2.plausibleMin, _vo2.plausibleMax],
  'PAR-033': [
    _min(_vo2.weightMaxDuration),
    _vo2.gpsGoodFactor,
    _vo2.gpsGoodMedianMeters,
    _vo2.gpsOtherFactor,
  ],
  'PAR-034': [
    _vo2.alphaGoodMin,
    _vo2.alphaSufficientMin,
    _vo2.alphaPreliminaryMin,
    _vo2.alphaPreliminaryDivisorFactor,
  ],
  'PAR-035': [_weeks(_vo2.restartAfter), _vo2.restartRunNumber],
  'PAR-036': [
    _vo2.trendFromSections,
    _vo2.percentileFromSections,
    _pct(_vo2.percentileLow),
    _pct(_vo2.percentileHigh),
  ],
  'PAR-037': [_vo2.undeterminableAbovePercent],
  'PAR-038': [_vo2.undeterminableAbovePercent],
  'PAR-039': [_vo2.sufficientMinSections, _vo2.sufficientMaxPercent],
  'PAR-040': [
    _vo2.goodMinSections,
    _min(_vo2.goodMinDuration),
    _vo2.goodMaxPercent,
  ],
  'PAR-041': [_vo2.longTermMinRecentRuns, _weeks(_vo2.longTermRecentWindow)],
  'PAR-042': [
    _vo2.longTermMinRecentRuns,
    _weeks(_vo2.longTermRecentWindow),
    _vo2.longTermSufficientMinQualityRuns,
  ],
  'PAR-043': [
    _vo2.longTermGoodMinRuns,
    _weeks(_vo2.longTermGoodWindow),
    _vo2.longTermGoodMinGoodRuns,
  ],
  'PAR-045': [_pct(_ae.gradientMaxAbs)],
  'PAR-046': [_ae.minSections, _ae.minRuns, _min(_ae.minDuration)],
  'PAR-047': [
    _ae.sufficientMinSections,
    _ae.sufficientMinRuns,
    _ae.goodMinSections,
    _ae.goodMinRuns,
  ],
  // docs/planning-rules.md
  'PAR-192': [_plan.continuousRunMinutes],
  'PAR-193': [
    _pct(_plan.rateBelowMid),
    _plan.midThresholdMinutes / 60,
    _pct(_plan.rateMid),
    _plan.highThresholdMinutes / 60,
    _pct(_plan.rateHigh),
  ],
  'PAR-194': [_plan.lighterWeekEvery, _pct(_plan.lighterWeekReduction)],
  'PAR-195': [
    _pct(_plan.longestRunShareThreePlus),
    _pct(_plan.longestRunShareTwo),
  ],
  'PAR-198': [
    _plan.hardMinContinuousMinutes,
    _plan.hardLongFromWeeklyMinutes / 60,
    _plan.intervalsShort.reps,
    _plan.intervalsShort.workMinutes,
    _plan.intervalsShort.pauseMinutes,
    _plan.intervalsLong.reps,
    _plan.tempoShort.reps,
    _plan.tempoShort.workMinutes,
    _plan.tempoShort.pauseMinutes,
    _plan.tempoLong.workMinutes,
    _plan.progressiveBlockShort,
    _plan.progressiveBlockLong,
  ],
  'PAR-199': [
    _plan.reductionWeeksShort,
    -_pct(_plan.reductionShareShort),
    _plan.reductionWeeksHalf,
    -_pct(_plan.reductionShareHalf),
    _plan.peakLeadWeeks,
  ],
  'PAR-200': [_plan.feedbackIntervalDays / 7, _pct(_plan.feedbackStep)],
  'PAR-201': [
    _pct(_plan.holdBelowShare),
    _plan.fatigueRuns,
    _plan.fatigueWindowRuns,
    _plan.fatigueRpe,
    -_pct(_plan.fatigueReduction),
  ],
  'PAR-202': [
    _plan.pauseMinDays,
    _plan.pauseLongDays / 7,
    _pct(_plan.pauseShortShare),
    _plan.pauseNewStartDays / 7,
    _pct(_plan.pauseLongShare),
    _plan.pauseShortNoHardWeeks,
    _plan.pauseLongNoHardWeeks,
  ],
  'PAR-204': [_pct(_plan.largeChangeShare)],
  'PAR-205': [
    _plan.peakHalfMarathonKm,
    _plan.peakMaxMinutes / 60,
    _plan.peakMinEasyRuns,
    _plan.easyWindowWeeks,
    _plan.peakFallbackShort,
    _plan.peakFallbackTen,
    _plan.peakFallbackHalf,
  ],
  'PAR-058': [_plan.completedIntensiveMinRpe],
  'PAR-206': [
    _feas.fitsUpToPercentPerWeek,
    _feas.tightUpToPercentPerWeek,
    _feas.minRuns,
    _feas.runWindowDays / 7,
  ],
  'PAR-065': [
    ..._walkRunWeek(0).take(2),
    walkRunProgram.weeks[0].sessions.first.length ~/ 2 + 1,
    walkRunProgram.weeks[0].sessions.first.length ~/ 2,
    walkRunProgram.warmUpSeconds / 60,
    walkRunProgram.coolDownSeconds / 60,
  ],
  'PAR-081': [_int.vo2maxLastRunMaxDays / 7],
  'PAR-082': [
    _pct(_int.vo2maxWidthSufficient),
    _pct(_int.vo2maxWidthGood),
    _pct(_int.referenceWidthYoung),
  ],
  'PAR-086': [
    _factor.minRuns,
    _factor.windowDays,
    _factor.minHighRuns,
    _factor.highRpe,
    _factor.minLowRuns,
    _factor.lowRpe,
  ],
  'PAR-087': [
    _factor.medianRuns,
    _factor.securedRuns,
    _pct(_factor.adoptTolerance),
  ],
  'PAR-073': [_load.tsbPercentMeanDays],
  'PAR-088': [_load.atlProvisionalDays],
  'PAR-089': [_load.ctlProvisionalDays],
  'PAR-090': [_load.fallbackWindowDays, _load.fallbackMissingPercent],
  // docs/phase-2-3-rules.md
  'PAR-107': [
    _min(pulseAnnounceMinTimeInSegment),
    _min(pulseAnnounceMinSegmentLength),
    _min(pulseAnnounceMaxMovingTime),
    _sec(pulseAnnounceMinOverrun),
    walkBreakHintRunCount,
  ],
  'PAR-101': [
    _int.referenceYoungDays / 7,
    _pct(_int.referenceWidthYoung),
    _int.referenceMidDays / 7,
    _pct(_int.referenceWidthMid),
    _int.referenceMaxDays / 7,
    _pct(_int.referenceWidthOld),
    _int.pauseExcludesDays / 7,
  ],
  'PAR-102': [
    _int.intervalFastMeters / 1000,
    _int.intervalSlowMeters / 1000,
    _int.tempoFastMeters / 1000,
    _int.tempoFastMinutes,
    _pct(_int.easyLimitFactor - 1),
  ],
  'PAR-103': [
    _int.vo2maxRestMl,
    _int.vo2maxSlopeMl,
    _int.vo2maxShareEasy,
    _int.vo2maxShareTempo,
    _int.vo2maxMinSpeedMetersPerMinute,
  ],
  'PAR-108': [_int.rpeRecovery.min, _int.rpeRecovery.max],
  'PAR-109': [_int.rpeEasy.min, _int.rpeEasy.max],
  'PAR-110': [_int.rpeLong.min, _int.rpeLong.max],
  'PAR-111': [_pct(_int.easyMaxShareOfMaxHr)],
  'PAR-112': [_int.rpeInterval.min, _int.rpeInterval.max, _int.rpeRecovery.max],
  'PAR-113': [_int.rpeTempo.min, _int.rpeTempo.max],
  'PAR-114': [_int.rpeEndBlock.min, _int.rpeEndBlock.max],
  'PAR-115': [_int.rpeWalkRun.max, _int.rpeWalk.max],
  'PAR-119': [
    walkRunProgram.warmUpSeconds / 60,
    walkRunProgram.coolDownSeconds / 60,
  ],
  for (var w = 1; w <= 8; w++) 'PAR-${131 + w}': _walkRunWeek(w),
  'PAR-140': [_plan.walkRunRepeatRpe, _plan.walkRunRepeatMinDone],
  'PAR-175': [_hint.maxDaysInRow],
  'PAR-178': [_hint.increaseMinDaysOfData, _hint.increaseFactor],
  'PAR-180': [_hint.pauseMinDays, _hint.longPauseDays / 7],
  'PAR-181': [_hint.longPauseDays / 7],
  'PAR-182': [_hint.effortRpe, _hint.effortMinCount, _hint.effortLookback],
  'PAR-183': [_hint.wellbeingMax, _hint.wellbeingMaxAgeDays],
  'PAR-210': [
    treadmillInclineMinPercent,
    treadmillInclineMaxPercent,
    treadmillInclineStepPercent,
  ],
  'PAR-117': [_pred.testHintMinimumContinuousMinutes],
  'PAR-120': [_plan.warmUpMinutes],
  'PAR-121': [_plan.coolDownMinutes],
  'PAR-143': [_pred.maxReferenceAgeDays / 7, _pred.maxPauseDaysExclusive / 7],
  'PAR-144': [
    _pred.maxReferenceAgeDays / 7,
    _pred.provisionalCapAgeDays / 7,
    _pred.provisionalCapRatio,
  ],
  'PAR-145': [
    _pred.sufficientMaxAgeDays / 7,
    _pred.sufficientMaxRatio,
    _pred.sufficientRegularWeeks,
    _pred.regularityWeeks,
    _pred.regularityRunsPerWeek,
  ],
  'PAR-146': [
    _pred.goodMaxAgeDays / 7,
    _pred.goodMaxRatio,
    _pred.goodRegularWeeks,
    _pred.regularityWeeks,
    _pred.goodLongestRunDays / 7,
    _pct(_pred.goodLongestRunShare),
  ],
  'PAR-149': [readinessSufficientHrvReference],
  'PAR-150': [readinessGoodHrvReference, readinessGoodSourceDays],
  'PAR-160': [
    _health.rmssdMinMs,
    _health.rmssdMaxMs,
    _min(_health.hrvFallbackWindow),
  ],
  'PAR-161': [
    readinessWindowDays,
    readinessMinWindowValues,
    readinessReferenceDays,
    readinessMinReferenceValues,
    readinessMadScale,
    readinessHrvMadMinLn,
  ],
  'PAR-162': [readinessRestingHrMadMinBpm],
  'PAR-160K': [
    morningRestSeconds / 60,
    morningMeasureSeconds,
    morningWindowDefaultStartHour,
    morningWindowDefaultEndHour,
    morningRmssdMinMs,
    morningRmssdMaxMs,
  ],
  'PAR-161K': [
    readinessMinWindowValues,
    readinessWindowDays,
    readinessReferenceDays,
    readinessMinReferenceValues,
    readinessMadScale,
    readinessHrvMadMinLn,
  ],
  'PAR-162K': [readinessCameraRestingHrMadMinBpm, readinessRestingHrMadMinBpm],
  'PAR-163': [
    readinessZBase,
    readinessZSlopeBelow,
    readinessZSlopeAbove,
    readinessZMax,
  ],
  'PAR-164': [_hours(_health.mainSleepMinDuration)],
  'PAR-164K/165K': morningSleepBandHours,
  'PAR-165': [
    readinessSleepAnchorHours,
    readinessSleepAnchorScore,
    readinessSleepSlopeBelow,
    readinessSleepSlopeAbove,
    readinessSleepCapHours,
    readinessSleepCapScore,
  ],
  'PAR-166': [
    _pct(_health.sleepCoverageMinShare),
    _health.efficiencyLowerKnee,
    _health.efficiencyUpperKnee,
    _health.efficiencyScoreAtLowerKnee,
    _health.efficiencyScoreCap,
    _health.efficiencySlopeBelow,
  ],
  'PAR-167': [readinessSleepDurationShare, readinessSleepEfficiencyShare],
  'PAR-168': [
    readinessLoadMaxScore,
    readinessLoadSlope,
    -readinessLoadNeutralTsbPercent,
  ],
  'PAR-169': [...readinessWellbeingScores, readinessWellbeingMaxAgeDays],
  'PAR-170': [
    readinessWeightHrv,
    readinessWeightRestingHr,
    readinessWeightSleep,
    readinessWeightLoad,
    readinessWeightWellbeing,
    readinessCapWithoutLoad,
  ],
  'PAR-172': [
    readinessExplanationReference,
    readinessExplanationSleepReference,
  ],
  'PAR-185': [_pred.suggestionMinimumRpe, _pred.suggestionMinimumMeters / 1000],
  'PAR-208': [
    _pred.fastestReferencePaceSecondsPerKm / 60,
    _pred.slowestReferencePaceSecondsPerKm / 60,
  ],
  'PAR-209': [
    treadmillSpeedMinKmh,
    treadmillSpeedMaxKmh,
    treadmillSpeedStepKmh,
  ],
  'PAR-211': [ppgSearchMaxRecordSeconds],
  'PAR-212': [ppgSearchWindowSeconds],
  'PAR-213': [ppgSearchStepSeconds],
  'PAR-214': [ppgSearchFilterLeadSeconds],
  'PAR-215': [ppgSearchFilterTailSeconds],
  'PAR-216': [morningRawMaxFrames, ppgSearchMaxRecordSeconds],
  'PAR-218': [ppgMaxFrameGapSeconds],
  'PAR-219': [ppgMinRedGreenRatio],
  'PAR-220': [ppgGoodStretchDisplayMinSeconds],
  'PAR-229': [morningBeltCompareAmbiguityRatio],
  'PAR-230': [
    ppgInconsistentBeatMs,
    ppgInconsistentMedianRadius,
    ppgMinHrvDiffs,
  ],
};

/// PAR-IDs ohne Zuordnung, je mit Grund in einer Zeile.
const Map<String, String> parExceptions = {
  'PAR-008': 'Schalter ohne Zahl (heartRateDiscardPoorContact).',
  'PAR-018': 'Verhaltensregel bei HFmax ≤ HFRuhe, keine Zahl.',
  'PAR-044': 'Verweist nur auf andere PAR; deren Werte sind dort geprüft.',
  'PAR-048': 'Drift (Phase 4) ist nicht umgesetzt; keine Konstante im Code.',
  'PAR-196': 'Regler in Stunden je Woche ohne festen Startwert.',
  'PAR-197': 'Aufzählung der Einheiten je Lauftag, keine Schwelle.',
  'PAR-203': 'Regel ohne Zahl (alles änderbar).',
  'PAR-231': 'Zuordnungsregel ohne Zahl.',
  'PAR-049': 'Grundsatz zu Texten, keine Zahl.',
  'PAR-050': 'Verbot der 10-%-Regel als Sicherheitsregel; die Zahl ist kein Parameter.',
  'PAR-059': 'Abstand als „voller Kalendertag“ ohne Zahl; minGapDays = 2 ist der Tagesabstand dazu.',
  'PAR-060': 'Ablauf beim Verschieben, keine Zahl.',
  'PAR-072': 'Aussagegrenze, keine Zahl.',
  'PAR-076': 'Regel ohne Zahl.',
  'PAR-091': 'Grundlage des Modells, keine Zahl.',
  'PAR-092': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-093': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-094': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-095': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-096': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-097': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-098': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-099': 'Energiemodell (FR-0122) ist nicht umgesetzt.',
  'PAR-100': 'Rangfolge der Grundlagen, keine Schwelle.',
  'PAR-104': 'Zonen als Verweis, keine eigene Zahl.',
  'PAR-105': 'RPE-Skala und Wortlaut, keine Schwelle.',
  'PAR-106': 'Texte der Grundlage, keine Zahl.',
  'PAR-116': 'Eintrag ohne Zielintensität, keine Zahl.',
  'PAR-141': 'Streckung des Programms je Lauftage, keine benannte Konstante.',
  'PAR-142': 'Rechtlicher Hinweis zur Quelle, keine Zahl.',
  'PAR-147': 'Stufe als Verweis auf andere Bedingungen, keine eigene Zahl.',
  'PAR-148': 'Zahlen sind Beispiele aus PAR-149 und OQ-0006.',
  'PAR-151': 'Datenstufen der Energie (FR-0122), nicht umgesetzt.',
  'PAR-152': 'Datenstufen der Energie (FR-0122), nicht umgesetzt.',
  'PAR-153': 'Datenstufen der Energie (FR-0122), nicht umgesetzt.',
  'PAR-154': 'Datenstufen der Energie (FR-0122), nicht umgesetzt.',
  'PAR-155': 'Drift (Phase 4) ist nicht umgesetzt.',
  'PAR-156': 'Drift (Phase 4) ist nicht umgesetzt.',
  'PAR-157': 'Drift (Phase 4) ist nicht umgesetzt.',
  'PAR-158': 'Drift (Phase 4) ist nicht umgesetzt.',
  'PAR-159': 'Textregel; die Zahlen sind Beispiele.',
  'PAR-171': 'Anzeige ohne Zahl; die Zahl ist ein Verweis auf eine Stufe.',
  'PAR-171K': 'Bedingungen als Verweis auf OQ-0006, keine eigene Konstante.',
  'PAR-173': 'Regel ohne Zahl.',
  'PAR-174': 'Wortliste, keine Zahl.',
  'PAR-179': 'Auslöser ohne Zahl.',
  'PAR-184': 'Kein Text, keine Zahl.',
  'PAR-186':
      'Begriff „mehrere geeignete Einheiten“; im Code keine eigene Konstante.',
  'PAR-188': 'Die Planänderung bekommt die Ermüdung als Wahrheitswert, keine Schwelle.',
  'PAR-189': 'Quellenregel ohne Zahl.',
  'PAR-190': 'Beispielrechnung zur Bandbreite, keine eigenen Konstanten.',
  'PAR-217': 'Konstante im Android-Code (PpgFrameStats.kt), nicht aus Dart erreichbar.',
  'PAR-221': 'Konstante im App-Paket (resting_measure_controller.dart), nicht aus core erreichbar.',
  'PAR-222': 'Konstante im App-Paket (resting_measure_controller.dart), nicht aus core erreichbar.',
  'PAR-223': 'Konstante im App-Paket (resting_measure_controller.dart), nicht aus core erreichbar.',
  'PAR-224': 'Konstante im App-Paket (resting_measure_controller.dart), nicht aus core erreichbar.',
  'PAR-225': 'Konstante im App-Paket (resting_measure_controller.dart), nicht aus core erreichbar.',
  'PAR-226': 'Konstante im App-Paket (resting_measure_controller.dart), nicht aus core erreichbar.',
  'PAR-234': 'Konstante im App-Paket (resting_measure_controller.dart), nicht aus core erreichbar.',
};

/// Eine Zeile einer PAR-Tabelle.
class ParRow {
  ParRow(this.id, this.value, this.source);
  final String id;
  final String value;
  final String source;
  bool get annulled => value.toLowerCase().startsWith('annulliert');
}

final _idCell = RegExp(r'^PAR-\d{3}K?(?:/\d{3}K)?$');

/// Liest die PAR-Tabellen eines Dokuments: nur Tabellen mit Kopf „| ID |“,
/// Wert ist die Spalte „Startwert“ bzw. „Stand“.
List<ParRow> parseParTables(String text, String source) {
  final rows = <ParRow>[];
  List<String>? header;
  var inTable = false;
  for (final line in text.split('\n')) {
    if (!line.startsWith('|')) {
      inTable = false;
      header = null;
      continue;
    }
    final cells = line.split('|').map((c) => c.trim()).toList();
    if (!inTable) {
      inTable = true;
      header = cells;
      continue;
    }
    final h = header!;
    if (h.length < 3 || h[1] != 'ID' || cells.length < 4) continue;
    if (!_idCell.hasMatch(cells[1])) continue;
    var col = h.indexOf('Startwert');
    if (col < 0) col = h.indexOf('Stand');
    if (col < 0 || col >= cells.length) continue;
    rows.add(ParRow(cells[1], cells[col], source));
  }
  return rows;
}

final _references = RegExp(
  r'\b(?:PAR|FR|NFR|OQ|DEC|SEC|ADR|SRC)-\d+K?(?:/\d+K)?|\[[A-Z]+\d+\]|\bK-?\d+\b|\bR\d+\b',
);
final _number = RegExp(
  r'([−-]?)(\d+):(\d{2})(?!\d)|([−-]?)(\d{1,3}(?:[  ]\d{3})+(?!\d)|\d+(?:,\d+)?)',
);

/// Zahlen einer Zelle: Verweise (PAR-, FR-, Quellen) entfallen, Dezimalkomma
/// wird gelesen, „m:ss“ ergibt Minuten, ein Bereich „2–4“ ergibt beide
/// Grenzen, „−2“ (Minuszeichen) ist negativ.
List<double> extractNumbers(String cell) {
  final s = cell.replaceAll(_references, ' ');
  final out = <double>[];
  for (final m in _number.allMatches(s)) {
    final before = m.start == 0 ? ' ' : s[m.start - 1];
    final signed = before == ' ' || before == '(' || before == '`';
    if (m.group(2) != null) {
      final v = int.parse(m.group(2)!) + int.parse(m.group(3)!) / 60;
      out.add(m.group(1)!.isNotEmpty && signed ? -v : v);
    } else {
      final raw = m.group(5)!.replaceAll(RegExp('[  ]'), '');
      final v = double.parse(raw.replaceAll(',', '.'));
      out.add(m.group(4)!.isNotEmpty && signed ? -v : v);
    }
  }
  return out;
}

bool _contains(List<double> doc, num code) =>
    doc.any((d) => (d - code).abs() <= 1e-9 * (1 + code.abs()));

String _fmt(num v) {
  final d = v.toDouble();
  final r = (d * 1e9).roundToDouble() / 1e9;
  return r == r.roundToDouble() ? r.toInt().toString() : r.toString();
}

/// Abweichungen zwischen Zuordnung und Tabellen, je eine Zeile mit ID,
/// Doku-Werten und Code-Wert.
List<String> compareParValues(
  List<ParRow> rows,
  Map<String, List<num>> code,
  Map<String, String> exceptions,
) {
  final problems = <String>[];
  final byId = <String, List<ParRow>>{};
  for (final r in rows) {
    byId.putIfAbsent(r.id, () => []).add(r);
  }
  for (final e in byId.entries) {
    final id = e.key;
    final row = e.value.first;
    if (e.value.length > 1) {
      problems.add('$id: mehrfach in den Tabellen');
    }
    final mapped = code.containsKey(id);
    final excepted = exceptions.containsKey(id);
    if (row.annulled) {
      if (mapped || excepted) problems.add('$id: annulliert, aber zugeordnet');
      continue;
    }
    if (mapped && excepted) {
      problems.add('$id: zugleich zugeordnet und Ausnahme');
    } else if (!mapped && !excepted) {
      problems.add('$id (${row.source}): weder zugeordnet noch Ausnahme');
    }
    if (!mapped) continue;
    final doc = extractNumbers(row.value);
    for (final v in code[id]!) {
      if (!_contains(doc, v)) {
        problems.add(
          '$id: Code ${_fmt(v)}, Doku [${doc.map(_fmt).join(', ')}]',
        );
      }
    }
  }
  for (final id in {...code.keys, ...exceptions.keys}) {
    if (!byId.containsKey(id)) {
      problems.add('$id: zugeordnet, aber in keinem Dokument');
    }
  }
  for (final e in exceptions.entries) {
    if (e.value.trim().isEmpty || e.value.contains('\n')) {
      problems.add('${e.key}: Ausnahme ohne einzeiligen Grund');
    }
  }
  return problems;
}

List<ParRow> _readDocs() => [
  for (final path in _docs)
    ...parseParTables(
      File(path).readAsStringSync(),
      path.replaceFirst('../../../', ''),
    ),
];

void main() {
  group('Zahlen aus einer Zelle', () {
    test('Dezimalkomma, Einheit, Bereich und Minuszeichen', () {
      expect(extractNumbers('≤ 25 m'), [25]);
      expect(extractNumbers('> 12,5 m/s'), [12.5]);
      expect(extractNumbers('Werte außerhalb 30–240 bpm'), [30, 240]);
      expect(extractNumbers('zwischen −2 % und +3 %'), [-2, 3]);
      expect(extractNumbers('1:30 laufen, 2:00 gehen'), [1.5, 2]);
      expect(extractNumbers('14 400 Bilder'), [14400]);
    });

    test('Verweise zählen nicht als Wert', () {
      expect(
        extractNumbers('nach PAR-027 und FR-0062 [Q20], PAR-161K: 7 Tage'),
        [7],
      );
    });

    test('Tabellen: nur Kopf „ID“, Wert aus „Startwert“', () {
      const doc = '''
| ID | Parameter | Startwert | Art |
|---|---|---|---|
| PAR-900 | A | 3 min | x |

| Werte | Warum | Prüfung |
|---|---|---|
| PAR-901 | B | 4 |

| ID | Stand | Ersetzt durch |
|---|---|---|
| PAR-902 | annulliert | PAR-900 |
''';
      final rows = parseParTables(doc, 'x.md');
      expect(rows.map((r) => r.id), ['PAR-900', 'PAR-902']);
      expect(rows.first.value, '3 min');
      expect(rows.last.annulled, isTrue);
    });
  });

  group('Abgleich', () {
    final rows = [
      ParRow('PAR-900', 'Schwelle 10 % in 42 Tagen', 'x.md'),
      ParRow('PAR-901', 'Regel ohne Zahl', 'x.md'),
    ];

    test('abweichender Wert nennt ID, Doku-Wert und Code-Wert', () {
      final p = compareParValues(
        rows,
        {
          'PAR-900': [11, 42],
        },
        {'PAR-901': 'ohne Zahl'},
      );
      expect(p, ['PAR-900: Code 11, Doku [10, 42]']);
    });

    test('neue ID ohne Zuordnung und ohne Ausnahme ist ein Fehler', () {
      final p = compareParValues(rows, {
        'PAR-900': [10, 42],
      }, {});
      expect(p, ['PAR-901 (x.md): weder zugeordnet noch Ausnahme']);
    });

    test('verwaiste Zuordnung und doppelte Einträge sind Fehler', () {
      final p = compareParValues(
        rows,
        {
          'PAR-900': [10],
          'PAR-999': [1],
        },
        {'PAR-900': 'doppelt', 'PAR-901': 'ohne Zahl'},
      );
      expect(p, [
        'PAR-900: zugleich zugeordnet und Ausnahme',
        'PAR-999: zugeordnet, aber in keinem Dokument',
      ]);
    });
  });

  test('PAR-Werte im Code entsprechen den Parameter-Dokumenten', () {
    final rows = _readDocs();
    expect(
      rows.length,
      greaterThan(150),
      reason: 'PAR-Tabellen nicht gefunden',
    );
    final problems = compareParValues(rows, parCodeValues, parExceptions);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
