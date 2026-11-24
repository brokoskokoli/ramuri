// Abgleich der PAR-Werte im Code mit den Parameter-Dokumenten.
//
// Der Test liest die PAR-Tabellen aus docs/model-parameters.md,
// docs/planning-rules.md und docs/phase-2-3-rules.md (Spalte „Startwert“)
// und zieht die Zahlen aus jeder Zelle. Für jede zugeordnete ID muss jede
// Zahl der Zelle genau einem Eintrag in [parCodeValues] entsprechen und
// umgekehrt (Vergleich als Multimenge): Ein Eintrag ist ein Wert aus dem Code
// oder eine Doku-Zahl ([DocOnly]) mit Grund in einer Zeile, etwa ein
// Rechenbeispiel. Steht ein Wert mehrfach in der Zelle, steht er ebenso oft
// in der Zuordnung; ändert sich ein Vorkommen, wird der Test rot. Jede
// PAR-ID der Dokumente steht entweder in [parCodeValues] oder in
// [parExceptions]; eine neue ID ohne Eintrag macht den Test rot. Annullierte
// IDs brauchen keinen Eintrag. Werte im App-Paket und im Android-Code prüft
// app/test/par_constants_app_test.dart; hier stehen sie als Ausnahme bzw.
// Doku-Zahl mit dem Grund [parCheckedInApp] (test/support/par_exceptions.dart).
// Parser und Abgleich liegen in test/support/par_docs.dart. Gegenprobe: Jede
// Zeile, die mit „| PAR-“ und einer Nummer beginnt, muss der Parser erfassen.
//
// Umrechnung: Die Werte stehen hier in der Einheit der Dokumente (Prozent,
// Minuten, Sekunden, Stunden), umgerechnet aus der Einheit des Codes.
import 'dart:io';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:test/test.dart';

import '../support/par_docs.dart';
import '../support/par_exceptions.dart';

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

/// Doku-Zahlen mit gemeinsamem Grund, zum Einfügen mit `...`.
List<DocOnly> _doc(List<num> values, String reason) => [
  for (final v in values) DocOnly(v, reason),
];

/// [a], wenn beide Code-Werte gleich sind (die Doku nennt sie einmal),
/// sonst NaN, das zu keiner Doku-Zahl passt.
num _both(num a, num b) => a == b ? a : double.nan;

/// Auf [digits] Nachkommastellen gerundet, wie in der Doku angegeben.
double _round(num v, int digits) {
  final f = math.pow(10, digits);
  return (v * f).round() / f;
}

double _kmh(num metersPerMinute) => _round(metersPerMinute * 60 / 1000, 2);
double _ms(num metersPerMinute) => _round(metersPerMinute / 60, 2);

/// Pace in Minuten je km, auf Sekunden gerundet („7:28“).
double _paceMinPerKm(num metersPerMinute) =>
    (1000 / metersPerMinute * 60).round() / 60;

bool _sameSession(List<WalkRunStep> a, List<WalkRunStep> b) =>
    a.length == b.length &&
    [
      for (var i = 0; i < a.length; i++)
        a[i].kind == b[i].kind && a[i].seconds == b[i].seconds,
    ].every((x) => x);

double _sessionTotal(List<WalkRunStep> s) =>
    (s.fold<int>(0, (a, st) => a + st.seconds) +
        walkRunProgram.warmUpSeconds +
        walkRunProgram.coolDownSeconds) /
    60;

/// Eine Programmwoche so, wie die Doku sie schreibt (PAR-133 bis PAR-139):
/// sind alle Einheiten gleich, einmal die Schritte in Minuten und die
/// Gesamtdauer mit Auf- und Abwärmen; sonst je Einheit „Lauf n:“ mit
/// Schritten und Gesamtdauer.
List<num> _walkRunWeek(int index) {
  final sessions = walkRunProgram.weeks[index].sessions;
  final same = sessions.every((s) => _sameSession(s, sessions.first));
  return [
    for (var i = 0; i < (same ? 1 : sessions.length); i++) ...[
      if (!same) i + 1,
      for (final step in sessions[i]) step.seconds / 60,
      _sessionTotal(sessions[i]),
    ],
  ];
}

/// Woche mit wiederholtem Paar „n × (laufen, gehen), dann laufen“ (PAR-132):
/// Zahl der Paare, Paar, letzter Lauf, Gesamtdauer. Wiederholen sich die
/// Paare nicht, ergibt das NaN.
List<num> _walkRunRepeatedWeek(int index) {
  final sessions = walkRunProgram.weeks[index].sessions;
  final s = sessions.first;
  final pairs = (s.length - 1) ~/ 2;
  final regular =
      s.length.isOdd &&
      sessions.every((x) => _sameSession(x, s)) &&
      [
        for (var i = 0; i < pairs; i++)
          s[2 * i].seconds == s[0].seconds &&
              s[2 * i + 1].seconds == s[1].seconds,
      ].every((x) => x);
  return [
    regular ? pairs : double.nan,
    s[0].seconds / 60,
    s[1].seconds / 60,
    s.last.seconds / 60,
    _sessionTotal(s),
  ];
}

/// PAR-ID → Einträge in der Einheit des Dokuments: Werte aus dem Code (num)
/// oder Doku-Zahlen mit Grund ([DocOnly]).
final Map<String, List<Object>> parCodeValues = {
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
    ..._doc([0, 1], 'Formel der fehlenden Zeit je Abstand, kein Parameter.'),
  ],
  'PAR-011': [
    _min(_pre.settlingDuration),
    _min(_pre.settlingPaceWindow),
    _pre.settlingPaceChange,
    _min(_pre.settlingPaceWindow),
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
  'PAR-019': [
    ..._doc([0], 'Untergrenze „0 < HFR“ der Fallunterscheidung.'),
    _fit.minHeartRateReserveBpm,
  ],
  'PAR-020': [
    _min(_sel.minDuration),
    _min(_sel.minDuration) + _min(_pre.settlingDuration),
  ],
  'PAR-021': [
    _min(_sel.splitLength),
    _min(_sel.splitLength) / 2,
    _min(_sel.splitLength),
  ],
  'PAR-022': [
    ..._doc([30], 'Takt der Tempowerte für den Variationskoeffizienten.'),
    _pct(_sel.paceMaxVariation),
    _pct(_sel.paceMaxHalfDifference),
  ],
  'PAR-023': [_sel.heartRateMaxHalfDifferenceBpm],
  'PAR-024': [_min(_sel.lateHalfWeightFrom), _min(_sel.lateExcludeFrom)],
  'PAR-025': [
    _sel.gpsMaxMedianAccuracyMeters,
    _pct(_sel.gpsMinShare),
    _sel.gpsShareAccuracyMeters,
  ],
  'PAR-026': [
    _pct(_sel.gradientMin),
    _pct(_sel.gradientMax),
    ..._doc([0], 'Steigung unter der Höhengrenze (PAR-027) gilt als 0.'),
  ],
  'PAR-027': [
    _pct(_sel.gradientUseFrom),
    ..._doc([0], 'Steigung sonst 0.'),
  ],
  'PAR-028': [_sel.intensityMin],
  'PAR-029': [_sel.intensityMax],
  'PAR-030': [
    _sel.fullSpeedMetersPerMinute,
    _kmh(_sel.fullSpeedMetersPerMinute),
    _ms(_sel.fullSpeedMetersPerMinute),
    _paceMinPerKm(_sel.fullSpeedMetersPerMinute),
  ],
  'PAR-031': [
    _sel.limitedSpeedMetersPerMinute,
    _sel.fullSpeedMetersPerMinute,
    _kmh(_sel.limitedSpeedMetersPerMinute),
    _kmh(_sel.fullSpeedMetersPerMinute),
    _sel.limitedSpeedMetersPerMinute,
  ],
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
    ..._doc([1, 1, 1], 'Zähler der Formel 1/n.'),
    ..._doc([0], 'α bei „nicht bestimmbar“: kein Beitrag.'),
  ],
  'PAR-035': [
    _weeks(_vo2.restartAfter),
    _vo2.restartRunNumber,
    math.max(_vo2.alphaGoodMin, 1 / _vo2.restartRunNumber),
    math.max(
      _vo2.alphaPreliminaryMin,
      1 / (_vo2.alphaPreliminaryDivisorFactor * _vo2.restartRunNumber),
    ),
  ],
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
    _vo2.longTermMinRecentRuns,
    _weeks(_vo2.longTermRecentWindow),
  ],
  'PAR-045': [
    _pct(_ae.gradientMaxAbs),
    ..._doc([0], 'Steigung unter der Höhengrenze (PAR-027) gilt als 0.'),
  ],
  'PAR-046': [_ae.minSections, _ae.minRuns, _min(_ae.minDuration)],
  'PAR-047': [
    _ae.sufficientMinSections,
    _ae.sufficientMinRuns,
    _ae.goodMinSections,
    _ae.goodMinRuns,
    _pct(_ae.maxGradientDifference),
  ],
  // docs/planning-rules.md
  'PAR-192': [_plan.continuousRunMinutes, _plan.continuousRunMinutes],
  'PAR-193': [
    _plan.midThresholdMinutes / 60,
    _pct(_plan.rateBelowMid),
    _plan.midThresholdMinutes / 60,
    _plan.highThresholdMinutes / 60,
    _pct(_plan.rateMid),
    _plan.highThresholdMinutes / 60,
    _pct(_plan.rateHigh),
  ],
  'PAR-194': [_plan.lighterWeekEvery, _pct(_plan.lighterWeekReduction)],
  'PAR-195': [
    _pct(_plan.longestRunShare(3)),
    ..._doc([2, 1], 'Zahl der Lauftage der Fallunterscheidung.'),
    _pct(_plan.longestRunShare(2)),
  ],
  'PAR-197': [
    const GoalParameters().minRunDays,
    ..._doc([2, 3, 4, 3], 'Aufzählung der Einheiten je Zahl der Lauftage.'),
    ..._doc([6], 'Ab 6 Tagen nur nach Festlegung des Nutzers.'),
    const GoalParameters().maxRunDays,
  ],
  'PAR-198': [
    _plan.hardMinRunDays,
    _plan.hardMinContinuousMinutes,
    ..._doc([
      1,
    ], 'Höchstens eine harte Einheit je Woche; Regel ohne Konstante.'),
    _plan.intervalsShort.reps,
    _plan.intervalsShort.workMinutes,
    _plan.intervalsShort.pauseMinutes,
    _plan.tempoShort.reps,
    _plan.tempoShort.workMinutes,
    _plan.tempoShort.pauseMinutes,
    _plan.progressiveBlockShort,
    _plan.hardLongFromWeeklyMinutes / 60,
    _plan.intervalsLong.reps,
    _plan.intervalsLong.workMinutes,
    _plan.tempoLong.reps,
    _plan.tempoLong.workMinutes,
    _plan.progressiveBlockLong,
  ],
  'PAR-199': [
    ..._doc([5, 10], 'Namen der Zielstrecken 5 km und 10 km.'),
    _plan.reductionWeeksShort,
    -_pct(_plan.reductionShareShort),
    _plan.reductionWeeksHalf,
    -_pct(_plan.reductionShareHalf),
    _plan.peakLeadWeeks,
  ],
  'PAR-200': [
    _plan.feedbackIntervalDays / 7,
    _pct(_plan.feedbackStep),
    -_pct(_plan.feedbackStep),
  ],
  'PAR-201': [
    _pct(_plan.holdBelowShare),
    _plan.fatigueRuns,
    _plan.fatigueWindowRuns,
    _plan.fatigueRpe,
    -_pct(_plan.fatigueReduction),
  ],
  'PAR-202': [
    _plan.pauseMinDays,
    _plan.pauseMinDays / 7,
    _plan.pauseLongDays / 7,
    _pct(_plan.pauseShortShare),
    _plan.pauseLongDays / 7,
    _plan.pauseNewStartDays / 7,
    _pct(_plan.pauseLongShare),
    _plan.pauseLongNoHardWeeks,
    _plan.pauseNewStartDays / 7,
  ],
  'PAR-204': [_pct(_plan.largeChangeShare)],
  'PAR-235': [_plan.deviationTimeFactor, _plan.deviationRpeSteps],
  'PAR-236': [
    _plan.underloadRuns,
    _plan.underloadWindowRuns,
    _plan.completedIntensiveMinHighHrMinutes,
    // Auslegung: „ab 80 % HFmax“ wie PAR-058.
    _fit.highHeartRateMinSharePercent,
  ],
  'PAR-205': [
    ..._doc([5, 10], 'Namen der Zielstrecken 5 km und 10 km.'),
    _plan.peakHalfMarathonKm,
    _plan.peakMaxMinutes / 60,
    _plan.peakMinEasyRuns,
    _plan.easyWindowWeeks,
    _plan.peakFallbackShort,
    _plan.peakFallbackTen,
    _plan.peakFallbackHalf,
  ],
  'PAR-058': [
    _plan.completedIntensiveMinHighHrMinutes,
    _fit.highHeartRateMinSharePercent,
    _plan.completedIntensiveMinRpe,
    // Auslegung: „Zeit bei mindestens 80 % HFmax“.
    _fit.highHeartRateMinSharePercent,
  ],
  'PAR-206': [
    _feas.fitsUpToPercentPerWeek,
    _feas.tightUpToPercentPerWeek,
    _feas.minRuns,
    _feas.runWindowDays / 7,
  ],
  'PAR-065': [
    walkRunProgram.weeks[0].sessions.first[0].seconds / 60,
    walkRunProgram.weeks[0].sessions.first[1].seconds / 60,
    walkRunProgram.weeks[0].sessions.first.length ~/ 2 + 1,
    walkRunProgram.weeks[0].sessions.first.length ~/ 2,
    _both(walkRunProgram.warmUpSeconds, walkRunProgram.coolDownSeconds) / 60,
    walkRunProgram.weeks.length,
    walkRunProgram.weeks.last.sessions.first.single.seconds / 60,
  ],
  'PAR-081': [_int.vo2maxLastRunMaxDays / 7],
  'PAR-082': [
    _pct(_int.vo2maxWidthSufficient),
    _pct(_int.vo2maxWidthGood),
    _int.referenceYoungDays / 7,
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
    // 183 Tage als „6 Monate“, auf ganze Monate gerundet.
    (_factor.priorValueDays * 12 / 365).round(),
  ],
  'PAR-073': [_load.tsbPercentMeanDays],
  'PAR-088': [_load.atlProvisionalDays],
  'PAR-089': [_load.ctlProvisionalDays],
  'PAR-090': [
    _load.fallbackWindowDays,
    _load.fallbackMissingPercent,
    _load.fallbackWindowDays,
    _load.fallbackMissingPercent,
  ],
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
    _int.referenceYoungDays / 7,
    _int.referenceMidDays / 7,
    _pct(_int.referenceWidthMid),
    _int.referenceMidDays / 7,
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
    ..._doc([5, 25], 'Rechenbeispiel: Referenz 5 km in 25:00.'),
    ..._doc([4.85, 5, 5.25, 5.45, 6], 'Rechenbeispiel: Ergebnis zur Referenz.'),
  ],
  'PAR-103': [
    _int.vo2maxRestMl,
    _int.vo2maxSlopeMl,
    _int.vo2maxShareEasy,
    _int.vo2maxShareTempo,
    _int.vo2maxMinSpeedMetersPerMinute,
  ],
  'PAR-108': [
    ..._doc([1, 1], 'Pulszone als Verweis (PAR-104).'),
    ..._doc([0.6], 'Grenze der Zone als Verweis (PAR-104).'),
    _int.rpeRecovery.min,
    _int.rpeRecovery.max,
  ],
  'PAR-109': [
    ..._doc([1, 2], 'Pulszone als Verweis (PAR-104).'),
    ..._doc([0.5, 0.7], 'Grenze der Zone als Verweis (PAR-104).'),
    _int.rpeEasy.min,
    _int.rpeEasy.max,
  ],
  'PAR-110': [
    ..._doc([1, 2], 'Pulszone als Verweis (PAR-104).'),
    _int.rpeLong.min,
    _int.rpeLong.max,
    _int.rpeLong.max + 1,
  ],
  'PAR-111': [
    ..._doc([0.7], 'Grenze der Zone als Verweis (PAR-104).'),
    _pct(_int.easyMaxShareOfMaxHr),
  ],
  'PAR-112': [
    ..._doc([2], 'Rang der Grundlage (PAR-100).'),
    _int.rpeInterval.min,
    _int.rpeInterval.max,
    ..._doc([4, 5], 'Pulszone als Verweis (PAR-104).'),
    ..._doc([0.85], 'Grenze der Zone als Verweis (PAR-104).'),
    ..._doc([4], 'Mindestlänge der Blöcke für die nachträgliche Auswertung.'),
    _int.rpeRecovery.max,
  ],
  'PAR-113': [
    ..._doc([3, 4], 'Pulszone als Verweis (PAR-104).'),
    ..._doc([0.75, 0.85], 'Grenze der Zone als Verweis (PAR-104).'),
    _int.rpeTempo.min,
    _int.rpeTempo.max,
  ],
  'PAR-114': [_int.rpeEndBlock.min, _int.rpeEndBlock.max],
  'PAR-115': [_int.rpeWalkRun.max, _int.rpeWalk.max],
  'PAR-119': [
    walkRunProgram.warmUpSeconds / 60,
    walkRunProgram.coolDownSeconds / 60,
  ],
  'PAR-132': _walkRunRepeatedWeek(1),
  for (var w = 2; w <= 8; w++) 'PAR-${131 + w}': _walkRunWeek(w),
  'PAR-140': [
    _plan.walkRunRepeatMinDone,
    walkRunProgram.maxSessionsPerWeek,
    _plan.walkRunRepeatMinDone,
    _plan.walkRunRepeatRpe,
    ..._doc([5, 3, 2], 'Woche 5, Lauf 3 und Lauf 2 der Abfolge (PAR-135).'),
    _plan.walkRunRepeatRpe,
  ],
  'PAR-141': [
    ..._doc([2, 1], 'Beispiele für die Zahl der Trainingstage.'),
    // Wochen je Programmwoche: höchstens maxSessionsPerWeek Einheiten je
    // Woche, also maxSessionsPerWeek / Trainingstage.
    walkRunProgram.maxSessionsPerWeek / 2,
    walkRunProgram.maxSessionsPerWeek / 1,
    walkRunProgram.shortenedWalkSeconds / 60,
  ],
  'PAR-175': [_hint.maxDaysInRow],
  'PAR-178': [
    _hint.increaseMinDaysOfData,
    ..._doc([7], 'Fenster der letzten Tage; im Code als Literal.'),
    _hint.increaseFactor,
    ..._doc([21], 'Vergleichsfenster davor; im Code als Literal.'),
  ],
  'PAR-180': [_hint.pauseMinDays, _hint.longPauseDays / 7],
  'PAR-181': [_hint.longPauseDays / 7],
  'PAR-182': [_hint.effortRpe, _hint.effortMinCount, _hint.effortLookback],
  'PAR-183': [
    ..._doc([1], 'Unterste Stufe des Befindens.'),
    _hint.wellbeingMax,
    _hint.wellbeingMaxAgeDays,
  ],
  'PAR-210': [
    treadmillInclineMinPercent,
    treadmillInclineMaxPercent,
    treadmillInclineStepPercent,
    ..._doc([0], 'Fehlende Angabe gilt nicht als 0.'),
  ],
  'PAR-117': [
    ..._doc([15, 3], 'Abschnittsnummer §15.3.'),
    ..._doc([8, 9], 'RPE-Vorgabe des Tests; nur Text.'),
    _plan.hardMinRunDays,
    _pred.testHintMinimumContinuousMinutes,
  ],
  'PAR-120': [
    _plan.warmUpMinutes,
    ..._doc([3, 20], 'Optionale Steigerungen; nur Text, keine Konstante.'),
  ],
  'PAR-121': [
    _plan.coolDownMinutes,
    ..._doc([10], 'Obere Grenze des Bereichs; der Plan nutzt den Startwert.'),
  ],
  'PAR-143': [
    _pred.maxReferenceAgeDays / 7,
    _pred.maxPauseDaysExclusive / 7,
    ..._doc([5], 'Name des 5-km-Tests.'),
  ],
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
    _pred.regularityRunsPerWeek,
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
  'PAR-162': [
    readinessRestingHrMadMinBpm,
    readinessMinWindowValues,
    readinessWindowDays,
  ],
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
    readinessWindowDays,
    readinessFewMeasurementsBelow,
  ],
  'PAR-162K': [readinessCameraRestingHrMadMinBpm, readinessRestingHrMadMinBpm],
  'PAR-163': [
    ..._doc([0, 0], 'Knick der Teilskala bei z = 0.'),
    readinessZBase,
    readinessZSlopeBelow,
    readinessScaleZ(-1000),
    readinessZBase,
    readinessZSlopeAbove,
    readinessZMax,
    ..._doc([-1, -2, 1], 'Beispielwerte für z.'),
    readinessScaleZ(-1),
    readinessScaleZ(-2),
    readinessScaleZ(1),
  ],
  'PAR-164': [_hours(_health.mainSleepMinDuration)],
  'PAR-164K/165K': [
    ..._doc([5, 5, 6, 6, 7, 7, 8, 8], 'Grenzen der Schlafstufen; nur Text.'),
    ...morningSleepBandHours,
  ],
  'PAR-165': [
    readinessSleepAnchorHours,
    readinessSleepAnchorScore,
    readinessSleepSlopeBelow,
    readinessSleepAnchorHours,
    readinessScaleSleepDuration(0),
    readinessSleepAnchorHours,
    readinessSleepCapHours,
    readinessSleepAnchorScore,
    readinessSleepSlopeAbove,
    readinessSleepAnchorHours,
    readinessSleepCapHours,
    readinessSleepCapScore,
    ..._doc([9], 'Aussage „keine Abwertung über 9 h“, keine Schwelle.'),
    ..._doc([6, 5, 7.5], 'Beispielwerte für h.'),
    readinessScaleSleepDuration(6),
    readinessScaleSleepDuration(5),
    readinessScaleSleepDuration(7.5),
  ],
  'PAR-166': [
    _pct(_health.sleepCoverageMinShare),
    _health.efficiencyLowerKnee,
    _health.efficiencyScoreAtLowerKnee,
    _health.efficiencySlopeBelow,
    _health.efficiencyLowerKnee,
    const HealthProcessing().efficiencyScore(0),
    _health.efficiencyLowerKnee,
    _health.efficiencyUpperKnee,
    _health.efficiencyScoreAtLowerKnee,
    _health.efficiencyLowerKnee,
    _health.efficiencyUpperKnee,
    _health.efficiencyScoreCap,
  ],
  'PAR-167': [readinessSleepDurationShare, readinessSleepEfficiencyShare],
  'PAR-168': [
    readinessLoadMaxScore,
    readinessLoadSlope,
    -readinessLoadNeutralTsbPercent,
    readinessLoadMaxScore,
    readinessScaleLoad(-1000),
    readinessLoadNeutralTsbPercent,
    readinessScaleLoad(readinessLoadNeutralTsbPercent),
    ..._doc([-20, -30, -40], 'Beispielwerte für TSB%.'),
    readinessScaleLoad(-20),
    readinessScaleLoad(-30),
    readinessScaleLoad(-40),
  ],
  'PAR-169': [
    ..._doc([1], 'Erste Stufe der Skala.'),
    readinessWellbeingScores.length,
    ...readinessWellbeingScores,
    readinessWellbeingMaxAgeDays,
  ],
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
    ..._doc([3.6], 'Umrechnung km/h in m/s.'),
    ..._doc([0], 'Geschwindigkeit 0 als Stillstand.'),
  ],
  'PAR-211': [ppgSearchMaxRecordSeconds],
  'PAR-212': [ppgSearchWindowSeconds],
  'PAR-213': [
    ppgSearchStepSeconds,
    ppgStandardWindow.start,
    // Letzter Fensterbeginn: Fenster und Filterrand passen in die Aufnahme.
    ppgStandardWindow.start +
        ((ppgSearchMaxRecordSeconds -
                        ppgSearchWindowSeconds -
                        ppgSearchFilterTailSeconds -
                        ppgStandardWindow.start) /
                    ppgSearchStepSeconds)
                .floor() *
            ppgSearchStepSeconds,
  ],
  'PAR-214': [ppgSearchFilterLeadSeconds],
  'PAR-215': [ppgSearchFilterTailSeconds],
  'PAR-216': [
    morningRawMaxFrames,
    ppgSearchMaxRecordSeconds,
    morningRawMaxFrames / ppgSearchMaxRecordSeconds,
  ],
  'PAR-218': [ppgMaxFrameGapSeconds, ppgMaxFrameGapSeconds],
  'PAR-219': [ppgMinRedGreenRatio],
  'PAR-220': [
    ppgGoodStretchDisplayMinSeconds,
    ..._doc([0], 'Anzeigewert darunter.'),
  ],
  'PAR-229': [morningBeltCompareAmbiguityRatio],
  'PAR-234': [
    // Fenster (restingLiveStageWindowSeconds) im App-Paket.
    ...parDocOnlyCheckedInApp['PAR-234']!,
    ppgLimitedQuality,
    _pct(ppgLimitedValidFraction),
  ],
  'PAR-230': [
    ppgInconsistentBeatMs,
    ppgInconsistentMedianRadius,
    ppgInconsistentMedianRadius,
    ..._doc([50], 'Name des Maßes pNN50.'),
    ppgMinHrvDiffs,
    ..._doc(
      [3],
      'Version, ab der PAR-230 gilt; die aktuelle Version (ppgMethodVersion) '
      'ist seit der Neusperre der Belichtung (PAR-245, PAR-246) 6.',
    ),
  ],
  'PAR-245': [
    ..._doc(
      [20, 0.5, 1.5],
      'Kotlin-Konstanten in PpgCameraLogic.kt, geprüft in PpgCameraLogicTest.',
    ),
    ppgMethodVersion,
  ],
  'PAR-246': [
    ..._doc([
      5,
    ], 'Kotlin-Konstante CALM_RELATIVE, geprüft in PpgCameraLogicTest.'),
    ppgExposureLockSeconds,
    // Fensterbeginn frühestens so lange nach der neuen Sperre wie beim ersten Mal.
    ppgSearchStartMin(relockedAt: 60) - 60,
    ppgSearchMaxRecordSeconds,
    ppgMethodVersion,
  ],
};

List<ParRow> _readDocs() => [
  for (final path in _docs)
    ...parseParTables(
      File(path).readAsStringSync(),
      path.replaceFirst('../../../', ''),
    ),
];

/// Zeilen der Dokumente, die mit „| PAR-“ beginnen, aber nicht erfasst sind.
List<String> _unparsedDocLines(List<ParRow> rows) => [
  for (final path in _docs)
    ...unparsedParLines(
      File(path).readAsStringSync(),
      path.replaceFirst('../../../', ''),
      rows,
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
      expect(extractNumbers('7 Tage (Entscheidung Maintainer 2026-11-18)'), [
        7,
      ]);
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

  group('Gegenprobe des Parsers', () {
    const doc = '''
| ID | Parameter | Startwert | Art |
|---|---|---|---|
| PAR-900 | A | 3 min | x |

| Nr | Parameter | Startwert |
|---|---|---|
| PAR-298 | B | 4 s |
''';

    test('PAR-Zeile in Tabelle mit anderem Kopf ist ein Fehler', () {
      final rows = parseParTables(doc, 'docs/planning-rules.md');
      expect(rows.map((r) => r.id), ['PAR-900']);
      expect(unparsedParLines(doc, 'docs/planning-rules.md', rows), [
        'PAR-298 (docs/planning-rules.md:7): Zeile einer PAR-Tabelle nicht '
            'erfasst',
      ]);
    });

    test('erfasste Zeilen und andere Tabellen sind kein Fehler', () {
      const ok = '''
| ID | Parameter | Startwert | Art |
|---|---|---|---|
| PAR-900 | A | 3 min | x |
| PAR-161K | B | 7 Tage | x |

| Werte | Warum |
|---|---|
| FR-0001 | B |
''';
      expect(unparsedParLines(ok, 'x.md', parseParTables(ok, 'x.md')), isEmpty);
    });

    test('Zeile aus einem anderen Dokument zählt nicht als erfasst', () {
      final rows = parseParTables(doc, 'a.md');
      expect(unparsedParLines(doc, 'b.md', rows), hasLength(2));
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
      expect(p, [
        'PAR-900: Code [11] nicht in der Doku, Doku [10] nicht zugeordnet '
            '(Zelle: [10, 42])',
      ]);
    });

    test('mehrfaches Vorkommen: jedes Vorkommen wird einzeln geprüft', () {
      List<String> check(String cell, List<Object> code) => compareParValues(
        [ParRow('PAR-900', cell, 'x.md')],
        {'PAR-900': code},
        {},
      );
      const cell = 'über 10 % in 42 Tagen, dann höchstens 10 %';
      expect(check(cell, [10, 42, 10]), isEmpty);
      expect(
        check('über 11 % in 42 Tagen, dann höchstens 10 %', [10, 42, 10]),
        [
          'PAR-900: Code [10] nicht in der Doku, Doku [11] nicht zugeordnet '
              '(Zelle: [11, 42, 10])',
        ],
      );
      expect(
        check('über 10 % in 42 Tagen, dann höchstens 11 %', [10, 42, 10]),
        [
          'PAR-900: Code [10] nicht in der Doku, Doku [11] nicht zugeordnet '
              '(Zelle: [10, 42, 11])',
        ],
      );
      // Ein Code-Wert verbraucht nur ein Vorkommen; das zweite bleibt übrig.
      expect(check(cell, [10, 42]), [
        'PAR-900: Code [] nicht in der Doku, Doku [10] nicht zugeordnet '
            '(Zelle: [10, 42, 10])',
      ]);
    });

    test(
      'Doku-Zahl braucht einen einzeiligen Grund und zählt wie ein Wert',
      () {
        List<String> check(List<Object> code) => compareParValues(
          [ParRow('PAR-900', 'Beispiel: 5 km in 25:00, Schwelle 10 %', 'x.md')],
          {'PAR-900': code},
          {},
        );
        expect(
          check([
            ..._doc([5, 25], 'Beispiel.'),
            10,
          ]),
          isEmpty,
        );
        expect(
          check([
            ..._doc([5, 26], 'Beispiel.'),
            10,
          ]),
          [
            'PAR-900: Code [26] nicht in der Doku, Doku [25] nicht zugeordnet '
                '(Zelle: [5, 25, 10])',
          ],
        );
        expect(
          check([
            ..._doc([5, 25], ' '),
            10,
          ]),
          [
            'PAR-900: Doku-Zahl 5 ohne einzeiligen Grund',
            'PAR-900: Doku-Zahl 25 ohne einzeiligen Grund',
          ],
        );
      },
    );

    test('zwei Code-Werte für eine Doku-Zahl müssen gleich sein', () {
      expect(_both(5, 5), 5);
      expect(
        compareParValues(
          [ParRow('PAR-900', 'davor und danach 5 min', 'x.md')],
          {
            'PAR-900': [_both(5, 6)],
          },
          {},
        ),
        [
          'PAR-900: Code [NaN] nicht in der Doku, Doku [5] nicht zugeordnet '
              '(Zelle: [5])',
        ],
      );
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
          'PAR-900': [10, 42],
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

  test('jede PAR-Zeile der Dokumente ist vom Parser erfasst', () {
    final problems = _unparsedDocLines(_readDocs());
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('Doku-Zahlen für den App-Test stehen in der Zuordnung', () {
    for (final e in parDocOnlyCheckedInApp.entries) {
      for (final d in e.value) {
        expect(parCodeValues[e.key], contains(same(d)), reason: e.key);
      }
    }
  });
}
