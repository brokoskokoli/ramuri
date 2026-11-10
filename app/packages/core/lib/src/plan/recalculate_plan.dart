import '../../ports/storage.dart' show StorageException, StorageFailure;
import '../../ports/storage_plan.dart';
import '../../ports/storage_settings.dart';
import 'generate_plan.dart';
import 'plan_change.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'weekly_time.dart' show planDay;

/// Ergebnis von [recalculatePlan].
class PlanRecalculation {
  const PlanRecalculation._(this.version, this.generated, this.summary);

  /// Kein Ziel: nichts gerechnet, nichts geschrieben.
  const PlanRecalculation.noGoal() : this._(null, null, null);

  /// Gerechnet, aber unverändert: keine Fassung geschrieben.
  const PlanRecalculation.unchanged(GeneratedPlan g, PlanChangeSummary s)
    : this._(null, g, s);

  const PlanRecalculation.written(
    PlanVersionRecord v,
    GeneratedPlan g,
    PlanChangeSummary s,
  ) : this._(v, g, s);

  /// Die geschriebene Fassung; `null` ohne Ziel oder ohne Änderung.
  final PlanVersionRecord? version;

  /// Ergebnis der Rechnung; `null` ohne Ziel.
  final GeneratedPlan? generated;

  /// Alt-Neu-Bild der künftigen Einheiten; `null` ohne Ziel.
  final PlanChangeSummary? summary;

  bool get hasGoal => generated != null;
  bool get wasWritten => version != null;
}

/// Berechnet den Plan ab [today] neu und schreibt das Ergebnis atomar
/// (ADR-0010 Punkt 3, FR-0157, FR-0158, PAR-203).
///
/// Eingefroren sind Einheiten mit `Tag < heute` oder mit Lauf; offene
/// künftige `pinned`-Einheiten gehen als Termine in die Rechnung. Gleiche
/// künftige Einheiten ergeben keine neue Fassung (nur `plan.last_check_day`
/// wird gesetzt); die erste Fassung eines Ziels wird immer geschrieben.
/// Scheitert das Schreiben, bleibt der alte Plan ganz bestehen und
/// `plan.last_check_day` unverändert.
///
/// [inputs] fehlt: Bei [PlanTrigger.create] oder ohne frühere Fassung
/// beginnt die Zählung neu ([PlanInputs.forNewGoal]), sonst gelten die
/// Eingaben der letzten Fassung mit [today] als „heute“. [now] ist der
/// Zeitpunkt für `created_at` und `plan.last_check_day`; der Dienst liest
/// keine Uhr.
///
/// Lehnt [PlanRepository.writeVersion] mit `rejected` ab (der Plan hat sich
/// seit dem Lesen geändert, z. B. Lauf zugeordnet), liest der Dienst genau
/// einmal neu, rechnet neu und schreibt neu. Ein zweites `rejected` geht an
/// den Aufrufer.
Future<PlanRecalculation> recalculatePlan({
  required PlanRepository plans,
  required SettingsStore settings,
  required PlanTrigger trigger,
  required DateTime today,
  required DateTime now,
  String? reason,
  PlanInputs? inputs,
  PlanParameters parameters = const PlanParameters(),
}) async {
  Future<PlanRecalculation> once() => _recalculateOnce(
    plans: plans,
    settings: settings,
    trigger: trigger,
    today: today,
    now: now,
    reason: reason,
    inputs: inputs,
    parameters: parameters,
  );
  try {
    return await once();
  } on StorageException catch (e) {
    if (e.failure != StorageFailure.rejected) rethrow;
    return once();
  }
}

Future<PlanRecalculation> _recalculateOnce({
  required PlanRepository plans,
  required SettingsStore settings,
  required PlanTrigger trigger,
  required DateTime today,
  required DateTime now,
  String? reason,
  PlanInputs? inputs,
  PlanParameters parameters = const PlanParameters(),
}) async {
  final todayDay = planDay(today);
  final goal = await plans.currentGoal();
  if (goal == null) return const PlanRecalculation.noGoal();

  final history = await plans.history();
  final last = history.isEmpty ? null : history.last;
  final PlanInputs use =
      inputs ??
      ((trigger == PlanTrigger.create || last == null)
          ? PlanInputs.forNewGoal(goal, todayDay, parameters: parameters)
          : last.inputs.copyWith(today: todayDay));

  final all = await plans.unitsBetween(use.anchor, planFarFuture);
  final frozen = <PlanUnit>[];
  final pinned = <PlanUnit>[];
  final oldFuture = <PlanUnit>[];
  for (final u in all) {
    if (u.day.isBefore(todayDay) || u.runId != null) {
      frozen.add(u);
    } else {
      oldFuture.add(u);
      if (u.pinned) pinned.add(u);
    }
  }

  // Automatische Auslöser ändern im bereits geplanten Zeitraum weder Tage
  // noch Zahl der Läufe (ADR-0010 Punkt 8); neue Wochen am Ende sind frei.
  final automatic = _isAutomatic(trigger) && oldFuture.isNotEmpty;
  var generated = generatePlan(
    goal,
    use,
    frozen,
    todayDay,
    pinnedUnits: automatic ? oldFuture : pinned,
    parameters: parameters,
  );
  if (automatic) {
    generated = _keepSchedule(generated, oldFuture);
  }
  final summary = summarizeChange(
    oldFuture,
    generated.units,
    parameters: parameters,
  );

  if (last != null && summary.isEmpty) {
    await _markChecked(settings, todayDay, now);
    return PlanRecalculation.unchanged(generated, summary);
  }

  final record = await plans.writeVersion(
    PlanVersionDraft(
      createdAt: now,
      validFrom: todayDay,
      trigger: trigger,
      reason: reason ?? trigger.name,
      version: generated.version,
      inputs: use,
      summary: summary.toJson(),
      units: generated.units,
      readState: planUnitsFingerprint(all),
    ),
  );
  await _markChecked(settings, todayDay, now);
  return PlanRecalculation.written(record, generated, summary);
}

/// Alles außer Anlegen, Zieländerung und ausdrücklicher Neuberechnung.
bool _isAutomatic(PlanTrigger t) =>
    t != PlanTrigger.create &&
    t != PlanTrigger.goalChange &&
    t != PlanTrigger.manual;

DateTime _mondayOf(DateTime d) =>
    d.subtract(Duration(days: d.weekday - DateTime.monday));

/// Hält die Tage der bisherigen künftigen Einheiten bis zum Ende der Woche
/// der letzten fest: `generatePlan` hat sie als Termine bekommen (Inhalt neu,
/// Tag fest); hier bekommen die Einheiten ihr altes `pinned` zurück, Einheiten
/// auf anderen Tagen im alten Zeitraum entfallen (die Zahl der Läufe bleibt),
/// und nur Konflikte echter Termine bleiben gemeldet.
GeneratedPlan _keepSchedule(GeneratedPlan g, List<PlanUnit> oldFuture) {
  final oldByDay = {for (final u in oldFuture) planDay(u.day): u};
  final last = oldByDay.keys.reduce((a, b) => a.isAfter(b) ? a : b);
  final horizonEnd = _mondayOf(last).add(const Duration(days: 7));
  final units = <PlanUnit>[];
  for (final u in g.units) {
    final day = planDay(u.day);
    if (!day.isBefore(horizonEnd)) {
      units.add(u);
    } else if (oldByDay[day] case final old?) {
      units.add(u.copyWith(pinned: old.pinned));
    }
  }
  final realPinned = {
    for (final u in oldFuture)
      if (u.pinned) planDay(u.day),
  };
  return g.copyWith(
    units: units,
    pinnedConflicts: [
      for (final c in g.pinnedConflicts)
        if (realPinned.contains(c.day)) c,
    ],
  );
}

Future<void> _markChecked(
  SettingsStore settings,
  DateTime today,
  DateTime now,
) => settings.set(
  planLastCheckDayKey,
  '${today.year.toString().padLeft(4, '0')}-'
  '${today.month.toString().padLeft(2, '0')}-'
  '${today.day.toString().padLeft(2, '0')}',
  at: now,
);
