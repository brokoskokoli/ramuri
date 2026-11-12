import '../../ports/clock.dart';
import '../../ports/storage.dart';
import '../../ports/storage_plan.dart';
import '../../ports/storage_runs.dart';
import '../../ports/storage_warning.dart';
import '../plan/plan_unit.dart';
import '../recalculation/value_calculation_service.dart' show dayOfRun;
import '../settings/load_settings.dart';
import 'hint_selection.dart';
import 'recovery_card.dart';

/// Schlüssel in den Einstellungen: zuletzt gezeigte Hinweise für die Sperre
/// nach PAR-175, `JJJJ-MM-TT=code`, durch Komma getrennt, höchstens
/// [HintService.historyDays] Tage. Enthält nie den Warntext und keine Inhalte.
const String hintShownKey = 'hints.shown';

/// Baut die Eingaben aus dem Speicher, wählt den Hinweis des Tages
/// ([selectHint]) und merkt sich ihn für die Sperre. Liest nur Läufe,
/// Nachträge, Plan, Warnsignal, Pausenantwort und die Zusage „alles erfasst“;
/// kein Ruhepuls, keine Gesundheitsdaten.
class HintService {
  HintService({required this.session, required this.clock});

  final StorageSession session;
  final Clock clock;

  /// So viele Tage der Auswahl bleiben gespeichert (mehr als die Sperre
  /// braucht).
  static const int historyDays = 7;

  /// Der Hinweis des Tages. Mehrfaches Abfragen am selben Tag ersetzt den
  /// gemerkten Hinweis dieses Tages (kein Zählen der Abfragen).
  Future<HintSelection> today() async {
    final now = clock.now();
    final local = now.add(clock.utcOffsetAt(now));
    final today = DateTime.utc(local.year, local.month, local.day);
    final input = await _inputs(today);
    final selection = selectHint(input);
    await _remember(today, selection, input.shown, now);
    return selection;
  }

  /// Die Karte „Erholung“ zum Hinweis des Tages; `null` ohne Auslöser.
  Future<RecoveryCard?> recoveryCard() async =>
      RecoveryCard.from(await today());

  /// Der Neustart, der wegen der Zusage „alles erfasst“ fällig ist
  /// (PAR-202); `null`, wenn keiner fällig ist.
  Future<PauseQuestion?> pauseRestartDue() async {
    final now = clock.now();
    final local = now.add(clock.utcOffsetAt(now));
    final today = DateTime.utc(local.year, local.month, local.day);
    return selectPauseRestart(await _inputs(today));
  }

  /// Die Pausenfrage von heute (PAR-202); `null`, wenn keine zu stellen ist.
  Future<PauseQuestion?> pauseQuestion() async {
    final now = clock.now();
    final local = now.add(clock.utcOffsetAt(now));
    final today = DateTime.utc(local.year, local.month, local.day);
    return selectPauseQuestion(await _inputs(today));
  }

  Future<HintInputs> _inputs(DateTime today) async {
    final s = session;
    final settings = s.settings;
    final trainings = <HintTraining>[];
    final byRunId = <int, HintTraining>{};
    final subjective = await s.subjective.readAll();
    for (final r in await s.runs.list()) {
      final end = r.endedAt;
      if (r.state != RunState.finished || end == null) continue;
      final sub = subjective[r.id]?.subjective;
      final t = HintTraining(
        day: DateTime.parse('${dayOfRun(r)}T00:00:00Z'),
        minutes: end.difference(r.startedAt).inMinutes,
        rpe: sub?.rpe,
        wellbeing: sub?.wellbeing,
        isRun: true,
      );
      trainings.add(t);
      byRunId[r.id] = t;
    }
    for (final m in await s.manualTrainings.list()) {
      trainings.add(
        HintTraining(
          day: m.training.day,
          minutes: m.training.duration.inMinutes,
          rpe: m.training.rpe,
          isRun: false,
        ),
      );
    }

    PlanUnit? plannedToday;
    final easy = <EasyPlanFeedback>[];
    if (s is PlanStorage) {
      plannedToday = await (s as PlanStorage).plans.unitOn(today);
      final from = today.subtract(const Duration(days: 90));
      for (final u in await (s as PlanStorage).plans.unitsBetween(
        from,
        today,
      )) {
        final id = u.runId;
        if (u.kind != PlanUnitKind.easy || id == null) continue;
        if (!u.day.isBefore(today)) continue;
        easy.add(EasyPlanFeedback(day: u.day, rpe: byRunId[id]?.rpe));
      }
    }
    WarningSignal? warning;
    if (s is WarningStorage) {
      warning = await (s as WarningStorage).warning.read();
    }

    return HintInputs(
      today: today,
      warningReportedOn: warning?.reportedOn,
      plannedToday: plannedToday,
      trainings: trainings,
      easyPlanned: easy,
      allRecorded: await LoadSettings.allRecorded(settings),
      pauseAnswer: await WarningState(settings).pauseAnswer(),
      pauseRestart: PauseRestartMark.parse(
        await settings.get(planPauseRestartKey),
      ),
      shown: _parse(await settings.get(hintShownKey)),
    );
  }

  Future<void> _remember(
    DateTime today,
    HintSelection selection,
    List<ShownHint> before,
    DateTime now,
  ) async {
    final code = selection.hint?.code;
    final keep = [
      for (final h in before)
        if (h.day.isBefore(today) &&
            today.difference(h.day).inDays <= historyDays)
          h,
      if (code != null && code != HintCode.warning) ShownHint(today, code),
    ];
    final text = [for (final h in keep) '${_day(h.day)}=${h.code.name}']
        .join(',');
    if (text == (await session.settings.get(hintShownKey) ?? '')) return;
    await session.settings.set(hintShownKey, text, at: now);
  }

  static List<ShownHint> _parse(String? v) {
    if (v == null || v.isEmpty) return const [];
    final out = <ShownHint>[];
    for (final part in v.split(',')) {
      final i = part.indexOf('=');
      if (i != 10) continue;
      final day = DateTime.tryParse('${part.substring(0, i)}T00:00:00Z');
      final code = HintCode.values.asNameMap()[part.substring(i + 1)];
      if (day == null || code == null || code == HintCode.warning) continue;
      out.add(ShownHint(day, code));
    }
    return out;
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
