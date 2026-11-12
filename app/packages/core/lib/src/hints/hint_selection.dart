import '../../ports/storage_warning.dart' show PauseAnswer, warningDay;
import '../plan/plan_adjust.dart' show pauseBaseWeek;
import '../plan/plan_unit.dart';

/// Hinweise der Basisstufe (PAR-174 bis PAR-184). Die Auswahl liefert nur
/// Codes und Datenbelege; die Texte setzt die App (PAR-174: beschreiben Daten,
/// keine Zustände, keine Diagnose).
enum HintCode {
  /// FR-0203: fester Warntext, Vorrang vor allem, ohne Sperre.
  warning,

  /// PAR-179: kurzer Abstand zur letzten intensiven Einheit.
  shortInterval,

  /// PAR-178: Anstieg der Bewegungszeit vor Tag 126.
  steepIncrease,

  /// PAR-180: Pause von 7 Tagen bis unter 8 Wochen.
  pause,

  /// PAR-181: Pause ab 8 Wochen.
  longPause,

  /// PAR-182: lockere Läufe fühlten sich anstrengender an als geplant.
  effortAbovePlan,

  /// PAR-183: Befinden beim letzten Lauf niedrig.
  lowWellbeing,
}

/// Knopf zum Hinweis. Es gibt keine automatische Änderung (K58, OQ-0011).
enum HintAction {
  /// Die heutige Einheit locker laufen (Ersetzen aus WP22, nach Bestätigung).
  easyRun,
}

/// Datenbeleg eines Hinweises oder einer Erklärung („Worauf beruht das?“).
enum EvidenceKey {
  plannedKind,
  plannedDay,
  lastIntensiveDaysAgo,
  lastIntensiveRpe,
  activeMinutes7d,
  weeklyAverageMinutes21d,
  daysOfData,
  daysSinceTraining,
  lastTrainingDay,
  allRecorded,
  pauseConfirmed,
  easyRunsConsidered,
  easyRunsAboveRpe,
  wellbeing,
  wellbeingDaysAgo,
  warningReportedOn,
  // Erklärungen (explanations.dart)
  fromDay,
  toDay,
  fromValue,
  toValue,
  runCount,
  shortTermLoad,
  longTermLoad,
  trigger,
  reason,
  validFrom,
  larger,
  changedUnitCount,
  valueKey,
  unavailableReason,
  quality,
  method,
  methodVersion,
  measurementCount,
}

/// Ein Beleg: Schlüssel und Wert (`num`, `bool`, `String` oder `DateTime`
/// als Ortstag).
class Evidence {
  const Evidence(this.key, this.value);
  final EvidenceKey key;
  final Object value;

  Map<String, Object?> toJson() => {
    'key': key.name,
    'value': value is DateTime ? _iso(value as DateTime) : value,
  };

  @override
  bool operator ==(Object other) =>
      other is Evidence && other.key == key && other.value == value;

  @override
  int get hashCode => Object.hash(key, value);

  @override
  String toString() => 'Evidence(${key.name})';
}

String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Ein ausgewählter Hinweis: Code, Knopf und Belege.
class Hint {
  const Hint({required this.code, this.action, this.evidence = const []});
  final HintCode code;
  final HintAction? action;
  final List<Evidence> evidence;

  Object? evidenceOf(EvidenceKey key) {
    for (final e in evidence) {
      if (e.key == key) return e.value;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'code': code.name,
    'action': action?.name,
    'evidence': [for (final e in evidence) e.toJson()],
  };
}

/// Ein erfasstes Training (Lauf oder Nachtrag) als Eingabe der Auswahl.
class HintTraining {
  HintTraining({
    required DateTime day,
    required this.minutes,
    this.rpe,
    this.wellbeing,
    required this.isRun,
  }) : day = warningDay(day);

  /// Ortstag.
  final DateTime day;

  /// Bewegungszeit (Dauer des Laufs bzw. des Nachtrags) in Minuten.
  final int minutes;
  final int? rpe;

  /// Befinden 1 bis 5, nur bei Läufen (PAR-169).
  final int? wellbeing;
  final bool isRun;
}

/// Eine abgeschlossene, locker geplante Einheit mit der RPE ihres Laufs.
class EasyPlanFeedback {
  EasyPlanFeedback({required DateTime day, this.rpe}) : day = warningDay(day);
  final DateTime day;
  final int? rpe;
}

/// Ein an einem Tag gezeigter Hinweis (für die Sperre nach PAR-175).
class ShownHint {
  ShownHint(DateTime day, this.code) : day = warningDay(day);
  final DateTime day;
  final HintCode code;
}

/// Eingaben der Auswahl. Bewusst ohne Ruhepuls und ohne Gesundheitsdaten
/// (K58). Alle Tage sind Ortstage.
class HintInputs {
  HintInputs({
    required DateTime today,
    this.warningReportedOn,
    this.plannedToday,
    this.trainings = const [],
    this.easyPlanned = const [],
    this.allRecorded = false,
    this.pauseAnswer,
    this.shown = const [],
  }) : today = warningDay(today);

  final DateTime today;

  /// Tag der Meldung, wenn ein Warnsignal besteht (FR-0203).
  final DateTime? warningReportedOn;

  /// Die geplante Einheit von heute (Ruhetag zählt wie keine).
  final PlanUnit? plannedToday;
  final List<HintTraining> trainings;

  /// Abgeschlossene, locker geplante Einheiten, neueste zuerst.
  final List<EasyPlanFeedback> easyPlanned;
  final bool allRecorded;
  final PauseAnswer? pauseAnswer;

  /// Früher gezeigte Hinweise (ohne [HintCode.warning]).
  final List<ShownHint> shown;
}

/// Ergebnis: der Hinweis des Tages oder keiner; [locked] nennt Hinweise,
/// deren Auslöser galt, die aber nach PAR-175 gesperrt waren.
class HintSelection {
  const HintSelection({this.hint, this.locked = const []});
  final Hint? hint;
  final List<HintCode> locked;
}

/// Parameter der Hinweise (PAR-175 bis PAR-183).
class HintParameters {
  const HintParameters();

  /// PAR-175: derselbe Hinweis höchstens an so vielen Tagen in Folge.
  final int maxDaysInRow = 3;

  /// PAR-179, bis OQ-0079 geklärt ist: absolviert intensiv = RPE ab hier.
  final int intensiveRpe = 7;

  /// PAR-178.
  final int increaseMinDaysOfData = 28;
  final int increaseBeforeDay = 126;
  final double increaseFactor = 1.5;

  /// PAR-180/PAR-181 (PAR-202): Tage bis zur langen Pause (8 Wochen).
  final int pauseMinDays = 7;
  final int longPauseDays = 56;

  /// PAR-182: RPE ab hier ist „anstrengender als geplant“, bei mindestens
  /// [effortMinCount] der letzten [effortLookback] locker geplanten Einheiten.
  final int effortRpe = 6;
  final int effortMinCount = 2;
  final int effortLookback = 3;

  /// PAR-183 (PAR-169): Befinden höchstens so niedrig, höchstens so alt.
  final int wellbeingMax = 2;
  final int wellbeingMaxAgeDays = 3;
}

const hintParameters = HintParameters();

/// Die Pausenfrage (PAR-202): Ab [HintParameters.pauseMinDays] Tagen ohne
/// erfasstes Training fragt die App, ob eine Pause war. [baseWeekMinutes] ist
/// die Summe der erfassten Minuten der Basiswoche ([pauseBaseWeek]: letzte
/// vollständige Kalenderwoche vor Beginn der Pause, Grundlage des Neustarts).
class PauseQuestion {
  const PauseQuestion({
    required this.daysSinceTraining,
    required this.lastTrainingDay,
    required this.baseWeekMinutes,
  });
  final int daysSinceTraining;
  final DateTime lastTrainingDay;
  final double baseWeekMinutes;
}

/// Fragt die App nach einer Pause? Nein bei Warnsignal, bei der Zusage „alles
/// erfasst“, ohne erfasstes Training, unter 7 Tagen und wenn seit dem letzten
/// Training schon geantwortet wurde (ja oder nein). Reine Funktion.
PauseQuestion? selectPauseQuestion(
  HintInputs input, {
  HintParameters parameters = hintParameters,
}) {
  if (input.warningReportedOn != null || input.allRecorded) return null;
  final last = _lastTrainingDay(input);
  if (last == null) return null;
  final days = _daysBetween(last, input.today);
  if (days < parameters.pauseMinDays) return null;
  final answer = input.pauseAnswer;
  if (answer != null && !answer.on.isBefore(last)) return null;
  final monday = pauseBaseWeek(last);
  final end = monday.add(const Duration(days: 7));
  var minutes = 0.0;
  for (final t in input.trainings) {
    if (!t.day.isBefore(monday) && t.day.isBefore(end)) minutes += t.minutes;
  }
  return PauseQuestion(
    daysSinceTraining: days,
    lastTrainingDay: last,
    baseWeekMinutes: minutes,
  );
}

/// Wählt den Hinweis des Tages (PAR-175): höchstens einer, Vorrang Warnsignal,
/// PAR-179, PAR-178, PAR-180, PAR-181, PAR-182, PAR-183. Derselbe Hinweis wird
/// nicht gezeigt, wenn er an den [HintParameters.maxDaysInRow] Tagen davor
/// gezeigt wurde; das Warnsignal ist ausgenommen und unterdrückt alle anderen.
/// Ohne Auslöser kein Hinweis (PAR-184), nie eine positive Meldung. Reine
/// Funktion, keine Texte.
HintSelection selectHint(
  HintInputs input, {
  HintParameters parameters = hintParameters,
}) {
  final w = input.warningReportedOn;
  if (w != null) {
    return HintSelection(
      hint: Hint(
        code: HintCode.warning,
        evidence: [Evidence(EvidenceKey.warningReportedOn, warningDay(w))],
      ),
    );
  }
  final candidates = <Hint?>[
    _shortInterval(input, parameters),
    _steepIncrease(input, parameters),
    _pause(input, parameters),
    _effort(input, parameters),
    _wellbeing(input, parameters),
  ];
  final locked = <HintCode>[];
  for (final c in candidates) {
    if (c == null) continue;
    if (_isLocked(c.code, input, parameters)) {
      locked.add(c.code);
      continue;
    }
    return HintSelection(hint: c, locked: locked);
  }
  return HintSelection(locked: locked);
}

bool _isLocked(HintCode code, HintInputs i, HintParameters p) {
  final days = {
    for (final s in i.shown)
      if (s.code == code) s.day,
  };
  for (var n = 1; n <= p.maxDaysInRow; n++) {
    if (!days.contains(i.today.subtract(Duration(days: n)))) return false;
  }
  return true;
}

int _daysBetween(DateTime from, DateTime to) => to.difference(from).inDays;

/// Heute geplant, noch nicht gelaufen, keine Ruhe.
PlanUnit? _openUnit(HintInputs i) {
  final u = i.plannedToday;
  if (u == null || u.kind == PlanUnitKind.rest || u.runId != null) return null;
  return u;
}

Hint? _shortInterval(HintInputs i, HintParameters p) {
  final u = _openUnit(i);
  if (u == null || !u.isIntensive) return null;
  DateTime? last;
  int? rpe;
  for (final t in i.trainings) {
    final r = t.rpe;
    if (r == null || r < p.intensiveRpe) continue;
    final ago = _daysBetween(t.day, i.today);
    if (ago != 0 && ago != 1) continue;
    if (last == null || t.day.isAfter(last)) {
      last = t.day;
      rpe = r;
    }
  }
  if (last == null) return null;
  return Hint(
    code: HintCode.shortInterval,
    action: HintAction.easyRun,
    evidence: [
      Evidence(EvidenceKey.plannedKind, u.kind.name),
      Evidence(EvidenceKey.lastIntensiveDaysAgo, _daysBetween(last, i.today)),
      Evidence(EvidenceKey.lastIntensiveRpe, rpe!),
    ],
  );
}

DateTime? _lastTrainingDay(HintInputs i) {
  DateTime? last;
  for (final t in i.trainings) {
    if (t.day.isAfter(i.today)) continue;
    if (last == null || t.day.isAfter(last)) last = t.day;
  }
  return last;
}

DateTime? _firstTrainingDay(HintInputs i) {
  DateTime? first;
  for (final t in i.trainings) {
    if (t.day.isAfter(i.today)) continue;
    if (first == null || t.day.isBefore(first)) first = t.day;
  }
  return first;
}

Hint? _steepIncrease(HintInputs i, HintParameters p) {
  final first = _firstTrainingDay(i);
  if (first == null) return null;
  final daysOfData = _daysBetween(first, i.today);
  // PAR-178: nur solange PAR-073 sperrt, mit mindestens 28 Tagen Daten.
  if (daysOfData < p.increaseMinDaysOfData ||
      daysOfData >= p.increaseBeforeDay) {
    return null;
  }
  final answer = i.pauseAnswer;
  final pauseConfirmed =
      answer != null &&
      answer.paused &&
      !answer.on.isBefore(i.today.subtract(const Duration(days: 27)));
  if (!i.allRecorded && !pauseConfirmed) return null;
  var last7 = 0;
  var before21 = 0;
  for (final t in i.trainings) {
    final ago = _daysBetween(t.day, i.today);
    if (ago < 0) continue;
    if (ago <= 6) {
      last7 += t.minutes;
    } else if (ago <= 27) {
      before21 += t.minutes;
    }
  }
  final weekly = before21 / 3;
  if (weekly <= 0 || last7 < weekly * p.increaseFactor) return null;
  return Hint(
    code: HintCode.steepIncrease,
    evidence: [
      Evidence(EvidenceKey.activeMinutes7d, last7),
      Evidence(EvidenceKey.weeklyAverageMinutes21d, weekly),
      Evidence(EvidenceKey.daysOfData, daysOfData),
      Evidence(EvidenceKey.allRecorded, i.allRecorded),
      Evidence(EvidenceKey.pauseConfirmed, pauseConfirmed),
    ],
  );
}

Hint? _pause(HintInputs i, HintParameters p) {
  final last = _lastTrainingDay(i);
  if (last == null) return null;
  final days = _daysBetween(last, i.today);
  if (days < p.pauseMinDays) return null;
  final answer = i.pauseAnswer;
  final pauseConfirmed =
      answer != null && answer.paused && !answer.on.isBefore(last);
  if (!i.allRecorded && !pauseConfirmed) return null;
  return Hint(
    code: days >= p.longPauseDays ? HintCode.longPause : HintCode.pause,
    evidence: [
      Evidence(EvidenceKey.daysSinceTraining, days),
      Evidence(EvidenceKey.lastTrainingDay, last),
      Evidence(EvidenceKey.allRecorded, i.allRecorded),
      Evidence(EvidenceKey.pauseConfirmed, pauseConfirmed),
    ],
  );
}

Hint? _effort(HintInputs i, HintParameters p) {
  final u = _openUnit(i);
  if (u == null) return null;
  final recent = i.easyPlanned.where((e) => e.day.isBefore(i.today)).toList()
    ..sort((a, b) => b.day.compareTo(a.day));
  final considered = recent.take(p.effortLookback).toList();
  final above = considered
      .where((e) => e.rpe != null && e.rpe! >= p.effortRpe)
      .length;
  if (above < p.effortMinCount) return null;
  return Hint(
    code: HintCode.effortAbovePlan,
    action: HintAction.easyRun,
    evidence: [
      Evidence(EvidenceKey.plannedKind, u.kind.name),
      Evidence(EvidenceKey.easyRunsConsidered, considered.length),
      Evidence(EvidenceKey.easyRunsAboveRpe, above),
    ],
  );
}

Hint? _wellbeing(HintInputs i, HintParameters p) {
  HintTraining? last;
  for (final t in i.trainings) {
    if (!t.isRun || t.day.isAfter(i.today)) continue;
    if (last == null || t.day.isAfter(last.day)) last = t;
  }
  final w = last?.wellbeing;
  if (last == null || w == null) return null;
  final age = _daysBetween(last.day, i.today);
  if (w > p.wellbeingMax || age > p.wellbeingMaxAgeDays) return null;
  return Hint(
    code: HintCode.lowWellbeing,
    action: HintAction.easyRun,
    evidence: [
      Evidence(EvidenceKey.wellbeing, w),
      Evidence(EvidenceKey.wellbeingDaysAgo, age),
    ],
  );
}
