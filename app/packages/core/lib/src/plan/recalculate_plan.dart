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

  final all = await plans.unitsBetween(use.anchor, _farFuture);
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

  final generated = generatePlan(
    goal,
    use,
    frozen,
    todayDay,
    pinnedUnits: pinned,
    parameters: parameters,
  );
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
    ),
  );
  await _markChecked(settings, todayDay, now);
  return PlanRecalculation.written(record, generated, summary);
}

final DateTime _farFuture = DateTime.utc(9999, 12, 31);

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
