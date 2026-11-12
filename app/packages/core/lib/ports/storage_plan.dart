import 'dart:convert';

import '../src/goals/training_goal.dart';
import '../src/plan/plan_inputs.dart';
import '../src/plan/plan_replace.dart' show planReplaceKinds;
import '../src/plan/plan_unit.dart';
import '../src/plan/weekly_time.dart' show planDay;
import 'storage.dart' show StorageException, StorageFailure;

/// Auslöser einer Plan-Fassung (ADR-0010 Punkt 1).
enum PlanTrigger {
  create,
  goalChange,
  weekly,
  feedback,
  run,
  pause,
  manual,
  ruleVersion,
}

/// Schlüssel in den Einstellungen: Ortstag der letzten Prüfung, auch wenn
/// keine Fassung entstand (ADR-0010 Punkt 3). Kein technischer Merker, geht
/// ins Archiv.
const String planLastCheckDayKey = 'plan.last_check_day';

/// Schlüssel in den Einstellungen: Merker des Neustarts zur Pause (PAR-202),
/// Wert `JJJJ-MM-TT restart|none` (Tag des letzten Trainings). Nur Tag und
/// Code, geht ins Archiv.
const String planPauseRestartKey = 'plan.pause_restart';

/// Eine gespeicherte Fassung des Plans (Zeile von `plans`).
class PlanVersionRecord {
  PlanVersionRecord({
    required this.id,
    required this.goalId,
    required this.createdAt,
    required DateTime validFrom,
    required this.trigger,
    required this.reason,
    required this.version,
    required this.inputsJson,
    required this.summaryJson,
  }) : validFrom = planDay(validFrom);

  final int id;
  final int goalId;
  final DateTime createdAt;

  /// Ortstag, ab dem die Fassung rechnet.
  final DateTime validFrom;
  final PlanTrigger trigger;

  /// Grund-Code; der Satz entsteht in der Oberfläche aus Code und [summary].
  final String reason;
  final PlanVersion version;

  /// JSON-Text wie gespeichert.
  final String inputsJson;
  final String summaryJson;

  /// Die vollständigen Eingaben der Rechnung (ADR-0010 Punkt 2).
  PlanInputs get inputs =>
      PlanInputs.fromJson(jsonDecode(inputsJson) as Map<String, Object?>);

  /// Alt-Neu-Bild der Änderung (`PlanChangeSummary.toJson`).
  Map<String, Object?> get summary =>
      jsonDecode(summaryJson) as Map<String, Object?>;
}

/// Zu schreibende Fassung samt den neuen künftigen Einheiten.
class PlanVersionDraft {
  PlanVersionDraft({
    required this.createdAt,
    required DateTime validFrom,
    required this.trigger,
    required this.reason,
    required this.version,
    required this.inputs,
    required this.summary,
    required this.units,
    required this.readState,
  }) : validFrom = planDay(validFrom);

  final DateTime createdAt;
  final DateTime validFrom;
  final PlanTrigger trigger;
  final String reason;
  final PlanVersion version;
  final PlanInputs inputs;
  final Map<String, Object?> summary;

  /// Neue Einheiten (Tag ab [validFrom], ohne Lauf).
  final List<PlanUnit> units;

  /// Fingerabdruck ([planUnitsFingerprint]) der Einheiten ab
  /// `inputs.anchor`, auf denen die Rechnung beruht. Hat sich der Plan
  /// zwischen Lesen und Schreiben geändert (Lauf zugeordnet oder entfernt,
  /// Termin bestätigt, andere Fassung), lehnt [PlanRepository.writeVersion]
  /// mit `rejected` ab; der Aufrufer liest neu und rechnet noch einmal.
  final String readState;

  String get inputsJson => jsonEncode(inputs.toJson());
  String get summaryJson => jsonEncode(summary);
}

/// Der gespeicherte Plan (ADR-0010 Punkt 11). Gelesen wird frei; geschrieben
/// wird nur über [writeVersion] (aus dem Dienst `recalculatePlan`), über
/// [assignRun], [confirmMove], [replaceUnit], [setRestDay] und
/// [clearRestDay].
abstract interface class PlanRepository {
  /// Das Ziel, zu dem der Plan gehört (das einzige Ziel), oder `null`.
  Future<TrainingGoal?> currentGoal();

  /// Einheiten mit `from <= Tag <= to` (Ortstage), nach Tag und Kennung.
  Future<List<PlanUnit>> unitsBetween(DateTime from, DateTime to);

  /// Die Einheit an diesem Tag oder `null`.
  Future<PlanUnit?> unitOn(DateTime day);

  /// Alle Fassungen, älteste zuerst.
  Future<List<PlanVersionRecord>> history();

  /// Ordnet der Einheit einen Lauf zu, `null` hebt die Zuordnung auf.
  /// Einheit oder Lauf fehlt: `notFound`.
  Future<void> assignRun(int unitId, int? runId);

  /// Verschiebt die Einheit auf [newDay] und setzt `pinned` (OQ-0011);
  /// `fixed` aus `planMovedFixed` (`easyForHard` wird in einer anderen Woche
  /// zu `kind`). Fehlt
  /// die Einheit: `notFound`. Mit Lauf, auf einem belegten Tag oder auf einem
  /// Tag vor [today] (Ortstag „heute“, kein Uhr-Zugriff im Speicher):
  /// `rejected`.
  Future<void> confirmMove(
    int unitId,
    DateTime newDay, {
    required DateTime today,
  });

  /// Ersetzt die Art der Einheit nach Bestätigung des Nutzers (FR-0173,
  /// Schema 8): Art, Dauer und Abschnitte aus [replacement] (aus
  /// `checkPlanReplace`), `pinned` und `fixed` aus `planReplacedFixed` der
  /// gespeicherten Einheit (`easyForHard`, wenn eine harte Einheit locker
  /// wird, sonst `kind`) gesetzt, in einer Transaktion. Fehlt die Einheit: `notFound`. Mit Lauf, vor [today],
  /// Ruhetag oder Geh-Lauf, eine Art außerhalb von `planReplaceKinds` oder
  /// ein anderer Tag in [replacement]: `rejected`.
  Future<void> replaceUnit(
    int unitId,
    PlanUnit replacement, {
    required DateTime today,
  });

  /// Legt den Tag von [rest] (`kind = rest`) als Ruhetag fest (`pinned`,
  /// `fixed = day`, Fassung = die neueste), in einer Transaktion. Liegt dort
  /// eine offene Einheit, wird sie auf [moveUnitTo] verschoben (`pinned`,
  /// gleiche Woche, freier Tag ab [today]) oder ohne [moveUnitTo] gelöscht.
  /// [expectedUnitId] ist die Kennung der Einheit, die der Nutzer beim
  /// Bestätigen auf dem Tag gesehen hat (`null`: Tag frei); liegt jetzt eine
  /// andere oder keine Einheit dort, wird nichts geändert (FR-0176).
  /// Eine nicht festgelegte Ruhe-Einheit (`rest`, nicht `pinned`) auf dem
  /// Tag wird zum Ruhetag (ohne [moveUnitTo]).
  /// Ohne Fassung: `notFound`. Tag vor [today], Einheit mit Lauf, schon
  /// festgelegter Ruhetag, abweichende Einheit, ungültiger [moveUnitTo],
  /// [moveUnitTo] ohne Einheit oder bei einer Ruhe-Einheit: `rejected`.
  Future<void> setRestDay(
    PlanUnit rest, {
    required DateTime today,
    required int? expectedUnitId,
    DateTime? moveUnitTo,
  });

  /// Hebt den Ruhetag an [day] auf (löscht die Ruhetag-Einheit); die App
  /// plant dort erst bei der nächsten Neuberechnung wieder (OQ-0011). Kein
  /// Ruhetag an dem Tag: `notFound`; Tag vor [today]: `rejected`.
  Future<void> clearRestDay(DateTime day, {required DateTime today});

  /// In EINER Transaktion: legt die Fassung an, löscht alle offenen
  /// künftigen Einheiten (`Tag >= validFrom`, ohne Lauf) und fügt die neuen
  /// ein. Scheitert etwas, bleibt der alte Plan ganz bestehen. Ohne Ziel:
  /// `notFound`; ungültige Fassung oder geänderter Plan seit dem Lesen
  /// ([PlanVersionDraft.readState]): `rejected`.
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft draft);
}

/// Letzter möglicher Ortstag für „alle Einheiten ab Beginn“.
final DateTime planFarFuture = DateTime.utc(9999, 12, 31);

/// Fingerabdruck der gelesenen Einheiten (Kennung, Tag, Lauf, `pinned`, Art,
/// `fixed`), nach
/// Tag und Kennung wie `unitsBetween` sie liefert. Gleich nur, wenn kein
/// Schreiber (Fassung, Zuordnung, Bestätigung) dazwischen lag.
String planUnitsFingerprint(Iterable<PlanUnit> units) => [
  for (final u in units)
    '${u.id}|${planDay(u.day).toIso8601String()}|${u.runId}|${u.pinned}|'
        '${u.kind.name}|${u.fixed.name}',
].join(';');

/// Ein Speicher, der den Plan führt (wie [GoalStorage]).
abstract interface class PlanStorage {
  PlanRepository get plans;
}

/// Prüfung vor dem Schreiben, gleich für Fake und Datenbank.
void checkPlanDraftForStorage(PlanVersionDraft d) {
  if (d.reason.isEmpty ||
      d.version.method.isEmpty ||
      d.version.methodVersion < 1 ||
      d.version.parameterVersion < 1) {
    throw const StorageException(StorageFailure.rejected);
  }
  for (final u in d.units) {
    final day = planDay(u.day);
    if (u.runId != null ||
        u.minutes < 0 ||
        u.weekIndex < 0 ||
        day.isBefore(d.validFrom)) {
      throw const StorageException(StorageFailure.rejected);
    }
  }
}

/// Neue Wochennummer einer auf [newDay] verschobenen Einheit (die Nummer
/// zählt ab dem Anker; Wochen beginnen am Montag).
int movedWeekIndex(PlanUnit unit, DateTime newDay) {
  DateTime monday(DateTime d) {
    final x = planDay(d);
    return x.subtract(Duration(days: x.weekday - DateTime.monday));
  }

  final weeks = monday(newDay).difference(monday(unit.day)).inDays ~/ 7;
  return unit.weekIndex + weeks;
}

/// Prüfung vor [PlanRepository.replaceUnit], gleich für Fake und Datenbank:
/// `true`, wenn [stored] mit [replacement] ersetzt werden darf.
bool planReplaceAllowed(
  PlanUnit stored,
  PlanUnit replacement,
  DateTime today,
) =>
    stored.runId == null &&
    !planDay(stored.day).isBefore(planDay(today)) &&
    stored.kind != PlanUnitKind.rest &&
    stored.kind != PlanUnitKind.walkRun &&
    planReplaceKinds.contains(replacement.kind) &&
    planDay(replacement.day) == planDay(stored.day);

/// Prüfung vor [PlanRepository.setRestDay], gleich für Fake und Datenbank:
/// `true`, wenn der Ruhetag [rest] mit der Einheit [onDay] des Tags (oder
/// `null`) und dem Zieltag [moveUnitTo] gesetzt werden darf. [onDay] muss
/// die beim Bestätigen gesehene Einheit [expectedUnitId] sein. [taken]
/// sagt, ob auf einem Tag schon eine Einheit liegt.
bool planRestDayAllowed(
  PlanUnit rest,
  PlanUnit? onDay,
  DateTime today,
  DateTime? moveUnitTo,
  bool Function(DateTime day) taken, {
  required int? expectedUnitId,
}) {
  final d = planDay(rest.day);
  final t = planDay(today);
  if (rest.kind != PlanUnitKind.rest || d.isBefore(t)) return false;
  if (onDay?.id != expectedUnitId) return false;
  if (onDay != null && (onDay.runId != null || onDay.isRestDay)) {
    return false;
  }
  // Eine nicht festgelegte Ruhe-Einheit wird zum Ruhetag, sie wird nicht
  // verlegt.
  if (onDay?.kind == PlanUnitKind.rest && moveUnitTo != null) return false;
  if (moveUnitTo == null) return true;
  final m = planDay(moveUnitTo);
  DateTime monday(DateTime x) =>
      x.subtract(Duration(days: x.weekday - DateTime.monday));
  return onDay != null &&
      m != d &&
      !m.isBefore(t) &&
      monday(m) == monday(d) &&
      !taken(m);
}
