import 'package:core/core.dart';

import 'plan_controller.dart';

/// Zuordnung eines beendeten Laufs zu einer Plan-Einheit (WP22 Teil D).
///
/// „Einheit starten“ merkt die Einheit in `settings`
/// ([SettingKeys.planStartedUnit]), bevor der Lauf beginnt. Zugeordnet wird,
/// sobald der Lauf beendet ist: nach dem Schließen des Lauf-Bildschirms, nach
/// einer Wiederaufnahme oder dem Speichern eines unterbrochenen Laufs
/// (FR-0193) und beim nächsten Start, falls die App dazwischen endete. Danach
/// wird der Merker gelöscht. Termine ändern sich dabei nie (nur
/// [PlanRepository.assignRun]).
class PlanStartedUnit {
  const PlanStartedUnit({
    required this.unitId,
    required this.day,
    required this.since,
  });

  /// Kennung der Einheit beim Start.
  final int unitId;

  /// Ortstag des Starts (`JJJJ-MM-TT`); löst die Einheit neu auf, wenn eine
  /// Neuberechnung sie inzwischen ersetzt hat (neue Kennung).
  final String day;

  /// Startzeit, auf ganze Sekunden abgerundet: Nur ein Lauf, der nicht
  /// früher begann, gehört zu dieser Einheit.
  final DateTime since;

  String encode() =>
      '$unitId;$day;${since.toUtc().millisecondsSinceEpoch ~/ 1000}';

  /// `null` bei leerem oder unlesbarem Wert.
  static PlanStartedUnit? decode(String? value) {
    final parts = value?.split(';');
    if (parts == null || parts.length != 3) return null;
    final unitId = int.tryParse(parts[0]);
    final seconds = int.tryParse(parts[2]);
    if (unitId == null || seconds == null) return null;
    if (DateTime.tryParse(parts[1]) == null) return null;
    return PlanStartedUnit(
      unitId: unitId,
      day: parts[1],
      since: DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    );
  }
}

/// Liest, schreibt und erledigt den Merker der gestarteten Einheit.
class PlanStartedUnitStore {
  PlanStartedUnitStore({required this.session, required this.clock});

  final StorageSession session;
  final Clock clock;

  Future<PlanStartedUnit?> read() async =>
      PlanStartedUnit.decode(await session.settings.get(_key));

  /// Merkt [unitId] für einen Lauf, der jetzt am Ortstag [day] beginnt.
  Future<void> remember(int unitId, String day) {
    final now = clock.now().toUtc();
    final since = DateTime.fromMillisecondsSinceEpoch(
      now.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    );
    return session.settings.set(
      _key,
      PlanStartedUnit(unitId: unitId, day: day, since: since).encode(),
      at: now,
    );
  }

  Future<void> forget() =>
      session.settings.set(_key, '', at: clock.now().toUtc());

  /// Ordnet den Lauf der gemerkten Einheit zu, sobald er beendet ist, und
  /// löscht den Merker. [runId] ist der eben beendete Lauf, falls bekannt;
  /// sonst gilt der erste seit dem Start begonnene Lauf. Gibt es keinen
  /// solchen Lauf, löscht nur [forgetWithoutRun] den Merker (der Aufrufer
  /// weiß, dass kein Lauf mehr beginnt: Lauf-Bildschirm geschlossen). Ist der Lauf
  /// noch offen (Wiederaufnahme steht an), bleibt er stehen. [serialize]
  /// reiht die Zuordnung hinter die Wertberechnung des Laufs
  /// (`RecalculationController.exclusive`). Ergebnis `null`: nichts
  /// zuzuordnen.
  Future<PlanActionResult?> settle({
    required Future<void> Function(Future<void> Function() action) serialize,
    int? runId,
    bool forgetWithoutRun = false,
  }) async {
    final started = await read();
    if (started == null) return null;
    final runs = await session.runs.list();
    final own = [
      for (final r in runs)
        if (!r.startedAt.isBefore(started.since)) r,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    if (own.isEmpty) {
      if (forgetWithoutRun) await forget();
      return null;
    }
    final run = runId == null
        ? own.first
        : own.where((r) => r.id == runId).firstOrNull;
    if (run == null || run.state != RunState.finished) return null;
    PlanActionResult? result;
    await serialize(() async {
      result = await assignRunToUnit(
        session: session,
        clock: clock,
        unitId: started.unitId,
        day: started.day,
        runId: run.id,
      );
    });
    if (result != PlanActionResult.failed) await forget();
    return result;
  }

  static const _key = SettingKeys.planStartedUnit;
}

/// Ordnet den beendeten Lauf [runId] der Einheit [unitId] zu und rechnet den
/// Plan neu (Auslöser `run`). Hat eine Neuberechnung die Einheit ersetzt
/// (`notFound`), gilt die offene Einheit desselben Ortstags [day]. Ein nicht
/// beendeter Lauf zählt nicht (`rejected`).
Future<PlanActionResult> assignRunToUnit({
  required StorageSession session,
  required Clock clock,
  required int unitId,
  required String day,
  required int runId,
}) async {
  final stored = await session.runs.get(runId);
  if (stored == null) return PlanActionResult.notFound;
  if (stored.state != RunState.finished) return PlanActionResult.rejected;
  final plan = PlanController(session: session, clock: clock);
  try {
    var result = await plan.assignRun(unitId, runId);
    if (result == PlanActionResult.notFound && session is PlanStorage) {
      final unit = await (session as PlanStorage).plans.unitOn(
        DateTime.parse('${day}T00:00:00Z'),
      );
      final id = unit?.id;
      if (unit != null &&
          id != null &&
          id != unitId &&
          unit.kind != PlanUnitKind.rest &&
          unit.runId == null) {
        result = await plan.assignRun(id, runId);
      }
    }
    return result;
  } finally {
    plan.dispose();
  }
}

/// Die offene Einheit am Ortstag [day] (nicht Ruhetag, ohne Lauf), sonst
/// `null` (auch ohne Plan).
Future<PlanUnit?> openPlanUnitOn(StorageSession session, String day) async {
  if (session is! PlanStorage) return null;
  final unit = await (session as PlanStorage).plans.unitOn(
    DateTime.parse('${day}T00:00:00Z'),
  );
  if (unit == null ||
      unit.id == null ||
      unit.kind == PlanUnitKind.rest ||
      unit.runId != null) {
    return null;
  }
  return unit;
}
