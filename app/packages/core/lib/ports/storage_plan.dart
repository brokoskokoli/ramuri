import 'dart:convert';

import '../src/goals/training_goal.dart';
import '../src/plan/plan_inputs.dart';
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

  String get inputsJson => jsonEncode(inputs.toJson());
  String get summaryJson => jsonEncode(summary);
}

/// Der gespeicherte Plan (ADR-0010 Punkt 11). Gelesen wird frei; geschrieben
/// wird nur über [writeVersion] (aus dem Dienst `recalculatePlan`), über
/// [assignRun] und über [confirmMove].
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

  /// Verschiebt die Einheit auf [newDay] und setzt `pinned` (OQ-0011). Fehlt
  /// die Einheit: `notFound`. Mit Lauf, auf einem belegten Tag oder auf einem
  /// Tag vor [today] (Ortstag „heute“, kein Uhr-Zugriff im Speicher):
  /// `rejected`.
  Future<void> confirmMove(
    int unitId,
    DateTime newDay, {
    required DateTime today,
  });

  /// In EINER Transaktion: legt die Fassung an, löscht alle offenen
  /// künftigen Einheiten (`Tag >= validFrom`, ohne Lauf) und fügt die neuen
  /// ein. Scheitert etwas, bleibt der alte Plan ganz bestehen. Ohne Ziel:
  /// `notFound`; ungültige Fassung: `rejected`.
  Future<PlanVersionRecord> writeVersion(PlanVersionDraft draft);
}

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
