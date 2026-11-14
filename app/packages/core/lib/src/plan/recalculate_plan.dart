import '../../ports/storage.dart' show StorageException, StorageFailure;
import '../../ports/storage_plan.dart';
import '../../ports/storage_settings.dart';
import '../../ports/storage_warning.dart';
import '../goals/training_goal.dart';
import 'generate_plan.dart';
import 'plan_change.dart';
import 'plan_goal_fingerprint.dart';
import 'plan_hints.dart';
import 'plan_inputs.dart';
import 'plan_parameters.dart';
import 'plan_unit.dart';
import 'plan_warning.dart';
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
/// Das `summary` der Fassung trägt das Alt-Neu-Bild, die Hinweise der
/// Rechnung ([planHintsToJson], lesbar mit [planHintsFromSummary]) und den
/// Fingerabdruck des Ziels ([planGoalFingerprint]); weicht das Ziel von dem
/// der letzten Fassung ab ([planGoalChangedSince]), wird bei gleichen
/// Einheiten nur für die Auslöser `create`, `goalChange` und `manual`
/// geschrieben. Automatische Auslöser (z. B. `run`) rechnen eine
/// ausstehende Zieländerung nicht: Sie schreiben bei gleichen Einheiten
/// nichts und übernehmen sonst den Fingerabdruck der letzten Fassung, die
/// Änderung bleibt ausstehend.
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
///
/// [warning]: Besteht ein Warnsignal (FR-0203, K58), sind alle künftigen,
/// nicht absolvierten Einheiten Ruhetage ([applyWarningRest]); Art, `fixed`
/// und `pinned` bleiben im `summary` der Fassung gehalten ([planWarningKey])
/// und kehren zurück, sobald das Warnsignal fehlt (Ausnahme zu ADR-0010).
/// Aufrufer, die ein Warnsignal führen, müssen den Speicher übergeben.
///
/// [markChecked] `false`: `plan.last_check_day` bleibt unverändert (die
/// Wochenprüfung ist noch nicht gelaufen und bleibt fällig).
Future<PlanRecalculation> recalculatePlan({
  required PlanRepository plans,
  required SettingsStore settings,
  required PlanTrigger trigger,
  required DateTime today,
  required DateTime now,
  String? reason,
  PlanInputs? inputs,
  PlanParameters parameters = const PlanParameters(),
  WarningStore? warning,
  bool markChecked = true,
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
    warning: warning,
    markChecked: markChecked,
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
  WarningStore? warning,
  bool markChecked = true,
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
  final (:frozen, pinned: shownPinned, :oldFuture) = _split(all, todayDay);
  // Liegt der Anker nach heute (Antwort auf die Nachfrage, PAR-200: Wirkung
  // ab der nächsten Woche), bleiben die offenen Einheiten bis dahin
  // unverändert stehen. Die Rechnung beginnt erst am Anker, das Schreiben
  // ersetzt aber alles ab heute.
  final bridge = use.anchor.isAfter(todayDay)
      ? [
          for (final u in await plans.unitsBetween(todayDay, use.anchor))
            if (u.runId == null &&
                !u.day.isBefore(todayDay) &&
                u.day.isBefore(use.anchor))
              u,
        ]
      : const <PlanUnit>[];

  // Warnsignal (FR-0203, K58): Die letzte Fassung unter Warnsignal hat die
  // Festlegungen des Nutzers gehalten; die Rechnung geht von der Fassung
  // ohne Warnsignal aus (Art, `fixed`, `pinned` zurück) und legt es danach
  // wieder darüber. Der Vergleich (`summary`) gilt dem gezeigten Plan.
  final warned = warning != null && await warning.read() != null;
  final lastHeld = last == null ? null : warningHeldFromSummary(last.summary);
  final base = lastHeld == null
      ? oldFuture
      : restoreWarningHeld(oldFuture, lastHeld);
  final bridgeKept = lastHeld == null
      ? bridge
      : restoreWarningHeld(bridge, lastHeld);
  final pinned = lastHeld == null
      ? shownPinned
      : [
          for (final u in base)
            if (u.pinned) u,
        ];

  // Automatische Auslöser ändern im bereits geplanten Zeitraum weder Tage
  // noch Zahl der Läufe (ADR-0010 Punkt 8); neue Wochen am Ende sind frei.
  final automatic = _isAutomatic(trigger) && base.isNotEmpty;
  var generated = generatePlan(
    goal,
    use,
    frozen,
    todayDay,
    pinnedUnits: automatic ? base : pinned,
    heldDays: automatic ? {for (final u in base) planDay(u.day)} : null,
    heldUntil: automatic ? _heldUntil(base) : null,
    parameters: parameters,
  );
  if (automatic) {
    generated = _keepSchedule(generated, base);
  }
  if (bridge.isNotEmpty) {
    generated = generated.copyWith(
      units: [
        ...fillEmptyRestored(bridgeKept, generated.units),
        ...generated.units,
      ],
    );
  }
  final held = warned ? warningHeldOf(generated.units, todayDay) : null;
  if (warned) {
    generated = generated.copyWith(
      units: applyWarningRest(generated.units, todayDay),
    );
  }
  final summary = summarizeChange(
    [...bridge, ...oldFuture],
    generated.units,
    parameters: parameters,
  );

  // Gleiche Einheiten ergeben keine Fassung, außer bei einem Ziel- oder
  // Nutzerauslöser weicht das Ziel von dem der letzten Fassung ab: Dann hält
  // die neue Fassung fest, dass die Zieländerung gerechnet ist (sonst bliebe
  // sie über einen Neustart offen). Automatische Auslöser halten die Tage
  // ([_keepSchedule]) und rechnen eine ausstehende Zieländerung nicht: Sie
  // übernehmen den Fingerabdruck der letzten Fassung, die Änderung bleibt
  // ausstehend ([planGoalChangedSince]).
  //
  // Ausnahme: Stammt die letzte Fassung aus einer älteren Regelversion, gilt
  // die neue Fassung auch bei gleichen Einheiten (Auslöser `ruleVersion`):
  // Sie trägt die aktuelle Version, sonst bliebe der Plan dauerhaft auf der
  // alten und die Wochenbewertung fiele weg (NB6 1). Ohne Änderung der
  // Einheiten ist die Zusammenfassung leer, es gibt keine Karte.
  final keepsGoalPending = _isAutomatic(trigger) && last != null;
  //
  // Ebenso schreibt eine Anpassung der Eingaben (Wochenbewertung: Anker,
  // Beleg, Zählung, `noHardUntil`) eine Fassung ohne geänderte Einheiten,
  // z. B. unter einem Warnsignal, wo der gezeigte Plan unverändert ruht; sonst
  // ginge die Anpassung verloren. Gemessene Werte zählen nicht (keine Fassung
  // bei jedem Öffnen). Ohne Karte: die Zusammenfassung bleibt leer.
  if (last != null &&
      last.version.isCurrent &&
      summary.isEmpty &&
      !_planningInputsChanged(last.inputs, use) &&
      (keepsGoalPending || !planGoalChangedSince(last.summary, goal))) {
    if (markChecked) await _markChecked(settings, todayDay, now);
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
      summary: {
        ...summary.toJson(),
        if (held != null) planWarningKey: [for (final h in held) h.toJson()],
        planHintsKey: planHintsToJson(generated),
        if (keepsGoalPending
                ? last.summary[planGoalFingerprintKey]
                : planGoalFingerprint(goal)
            case final Object fingerprint)
          planGoalFingerprintKey: fingerprint,
      },
      units: generated.units,
      readState: planUnitsFingerprint(all),
    ),
  );
  if (markChecked) await _markChecked(settings, todayDay, now);
  return PlanRecalculation.written(record, generated, summary);
}

/// Eingefroren (Tag vor heute oder mit Lauf), künftige `pinned` und alle
/// offenen künftigen Einheiten.
({List<PlanUnit> frozen, List<PlanUnit> pinned, List<PlanUnit> oldFuture})
_split(List<PlanUnit> all, DateTime todayDay) {
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
  return (frozen: frozen, pinned: pinned, oldFuture: oldFuture);
}

/// Hinweise zum gespeicherten Plan ohne Schreiben (für die Anzeige): rechnet
/// wie eine ausdrückliche Neuberechnung ab [today] mit [inputs] (in der Regel
/// die Eingaben der letzten Fassung mit `today`) über die gespeicherten
/// Einheiten [units] ab `inputs.anchor`. Für Fassungen ohne gespeicherte
/// Hinweise ([planHintsFromSummary] `null`); die neuen Einheiten des
/// Ergebnisses sind nur eine Vorschau und nicht der gespeicherte Plan.
GeneratedPlan previewPlan({
  required TrainingGoal goal,
  required PlanInputs inputs,
  required List<PlanUnit> units,
  required DateTime today,
  PlanParameters parameters = const PlanParameters(),
}) {
  final todayDay = planDay(today);
  final (:frozen, :pinned, oldFuture: _) = _split(units, todayDay);
  return generatePlan(
    goal,
    inputs,
    frozen,
    todayDay,
    pinnedUnits: pinned,
    parameters: parameters,
  );
}

/// Alles außer Anlegen, Zieländerung und ausdrücklicher Neuberechnung.
bool _isAutomatic(PlanTrigger t) =>
    t != PlanTrigger.create &&
    t != PlanTrigger.goalChange &&
    t != PlanTrigger.manual;

DateTime _mondayOf(DateTime d) =>
    d.subtract(Duration(days: d.weekday - DateTime.monday));

/// Ende (exklusiv) des Zeitraums, dessen Tage ein automatischer Auslöser hält:
/// Montag nach der Woche der letzten Einheit in [oldFuture].
DateTime _heldUntil(List<PlanUnit> oldFuture) {
  final last = oldFuture
      .map((u) => planDay(u.day))
      .reduce((a, b) => a.isAfter(b) ? a : b);
  return _mondayOf(last).add(const Duration(days: 7));
}

/// Hält die Tage der bisherigen künftigen Einheiten bis zum Ende der Woche
/// der letzten fest: `generatePlan` hat sie als Termine bekommen (Inhalt neu,
/// Tag fest); hier bekommen die Einheiten ihr altes `pinned` und `fixed`
/// zurück, Einheiten
/// auf anderen Tagen im alten Zeitraum entfallen (die Zahl der Läufe bleibt),
/// und nur Konflikte echter Termine bleiben gemeldet.
GeneratedPlan _keepSchedule(GeneratedPlan g, List<PlanUnit> oldFuture) {
  final oldByDay = {for (final u in oldFuture) planDay(u.day): u};
  final horizonEnd = _heldUntil(oldFuture);
  final units = <PlanUnit>[];
  for (final u in g.units) {
    final day = planDay(u.day);
    if (!day.isBefore(horizonEnd)) {
      units.add(u);
    } else if (oldByDay[day] case final old?) {
      // Eine ersetzte Art, die die Rechnung nicht halten konnte (Geh-Lauf
      // hat Vorrang), ist nicht mehr vom Nutzer festgelegt.
      final lost = old.fixed.keepsKind && u.kind != old.kind;
      units.add(
        u.copyWith(
          pinned: old.pinned,
          fixed: lost ? PlanUnitFixed.none : old.fixed,
        ),
      );
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

/// Eingaben, die der Plan aus Anpassungen und Festlegungen trägt (nicht die
/// gemessenen Werte Pace, Zahl der lockeren Läufe, Intensität und „heute“).
bool _planningInputsChanged(PlanInputs a, PlanInputs b) =>
    a.anchor != b.anchor ||
    a.startWeeklyMinutes != b.startWeeklyMinutes ||
    a.walkRunWeeks != b.walkRunWeeks ||
    a.walkRunStart != b.walkRunStart ||
    a.walkRunFrom != b.walkRunFrom ||
    a.lastWeekMinutes != b.lastWeekMinutes ||
    a.achievedShare != b.achievedShare ||
    a.weekCountOffset != b.weekCountOffset ||
    a.noHardUntil != b.noHardUntil;
