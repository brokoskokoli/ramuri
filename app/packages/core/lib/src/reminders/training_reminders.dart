import '../../ports/clock.dart';
import '../../ports/reminder_scheduler.dart';
import '../../ports/storage_goals.dart';
import '../../ports/storage_plan.dart';
import '../../ports/storage_settings.dart';
import '../plan/plan_unit.dart';
import '../prediction/reference_performance.dart' show calendarDay;
import '../settings/display_settings.dart';

/// Einstellungen der Erinnerungen (FR-0174, Vorschlag WP22 Teil F): aus, bis
/// der Nutzer sie einschaltet; eine einheitliche Trainingszeit für alle Tage
/// und ein Vorlauf. Gespeichert in `settings` (kein Schema); als
/// Nutzereinstellung kommen sie ins Archiv.
class ReminderSettings {
  const ReminderSettings({
    this.enabled = false,
    this.minuteOfDay = defaultMinuteOfDay,
    this.leadMinutes = defaultLeadMinutes,
  });

  /// Vorschlag: 18:00.
  static const int defaultMinuteOfDay = 18 * 60;

  /// Vorschlag: 30 Minuten.
  static const int defaultLeadMinutes = 30;

  /// Wählbare Vorläufe in Minuten.
  static const List<int> leadOptions = [15, 30, 60];

  final bool enabled;

  /// Trainingszeit in Minuten ab Mitternacht (Ortszeit).
  final int minuteOfDay;

  /// Vorlauf der Erinnerung vor der Trainingszeit.
  final int leadMinutes;

  int get hour => minuteOfDay ~/ 60;
  int get minute => minuteOfDay % 60;

  ReminderSettings copyWith({
    bool? enabled,
    int? minuteOfDay,
    int? leadMinutes,
  }) => ReminderSettings(
    enabled: enabled ?? this.enabled,
    minuteOfDay: minuteOfDay ?? this.minuteOfDay,
    leadMinutes: leadMinutes ?? this.leadMinutes,
  );

  /// Liest die Einstellungen; fehlende oder unlesbare Werte ergeben die
  /// Vorschläge.
  static Future<ReminderSettings> load(SettingsStore store) async {
    final enabled = await store.get(SettingKeys.reminderEnabled);
    final time = await store.get(SettingKeys.reminderTime);
    final lead = int.tryParse(
      await store.get(SettingKeys.reminderLeadMinutes) ?? '',
    );
    return ReminderSettings(
      enabled: enabled == '1',
      minuteOfDay: parseTime(time) ?? defaultMinuteOfDay,
      leadMinutes: leadOptions.contains(lead) ? lead! : defaultLeadMinutes,
    );
  }

  /// Schreibt alle drei Werte.
  Future<void> save(SettingsStore store, {required DateTime at}) async {
    await store.set(SettingKeys.reminderEnabled, enabled ? '1' : '0', at: at);
    await store.set(SettingKeys.reminderTime, formatTime(minuteOfDay), at: at);
    await store.set(SettingKeys.reminderLeadMinutes, '$leadMinutes', at: at);
  }

  /// `HH:MM` (00:00 bis 23:59) in Minuten ab Mitternacht, sonst `null`.
  static int? parseTime(String? v) {
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(v ?? '');
    if (m == null) return null;
    final h = int.parse(m[1]!), min = int.parse(m[2]!);
    if (h > 23 || min > 59) return null;
    return h * 60 + min;
  }

  static String formatTime(int minuteOfDay) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(minuteOfDay ~/ 60)}:${two(minuteOfDay % 60)}';
  }

  @override
  bool operator ==(Object other) =>
      other is ReminderSettings &&
      other.enabled == enabled &&
      other.minuteOfDay == minuteOfDay &&
      other.leadMinutes == leadMinutes;

  @override
  int get hashCode => Object.hash(enabled, minuteOfDay, leadMinutes);
}

/// Eine Erinnerung vor einer geplanten Einheit. Bewusst ohne Dauer, Pace oder
/// Puls: Der Text darf nur die Art nennen (SEC-0001).
class TrainingReminder {
  const TrainingReminder({
    required this.day,
    required this.kind,
    required this.trainingAt,
    required this.at,
  });

  /// Ortstag der Einheit (UTC-Mitternacht wie [PlanUnit.day]).
  final DateTime day;
  final PlanUnitKind kind;

  /// Trainingszeit an diesem Tag (Ortszeit).
  final DateTime trainingAt;

  /// Zeitpunkt der Erinnerung: Trainingszeit minus Vorlauf.
  final DateTime at;
}

/// Wie weit im Voraus geplant wird (Tage ab heute). Jede Synchronisierung
/// (Start, Rückkehr in die App, Änderung) schiebt das Fenster weiter.
const int reminderHorizonDays = 60;

/// Die nächsten Erinnerungen aus [units] (FR-0174): nur Lauf-Einheiten (keine
/// Ruhetage), ohne schon zugeordneten Lauf, nicht nach [planEnd] (Zieldatum)
/// und nur solche, deren Zeitpunkt nach [now] liegt. Zeitpunkt: Ortstag der
/// Einheit zur Trainingszeit minus Vorlauf. Ausgeschaltet: keine.
List<TrainingReminder> planTrainingReminders({
  required List<PlanUnit> units,
  required ReminderSettings settings,
  required DateTime now,
  DateTime? planEnd,
}) {
  if (!settings.enabled) return const [];
  final today = calendarDay(now);
  final last = today.add(const Duration(days: reminderHorizonDays));
  final end = planEnd == null ? null : calendarDay(planEnd);
  final out = <TrainingReminder>[];
  for (final u in units) {
    if (u.kind == PlanUnitKind.rest || u.runId != null) continue;
    if (end != null && u.day.isAfter(end)) continue;
    if (u.day.isAfter(last)) continue;
    final training = DateTime(
      u.day.year,
      u.day.month,
      u.day.day,
      settings.hour,
      settings.minute,
    );
    final at = training.subtract(Duration(minutes: settings.leadMinutes));
    if (!at.isAfter(now)) continue;
    out.add(
      TrainingReminder(day: u.day, kind: u.kind, trainingAt: training, at: at),
    );
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Texte der Benachrichtigung in der App-Sprache (die App liefert sie).
abstract interface class ReminderTexts {
  /// Name des Benachrichtigungskanals in den Systemeinstellungen.
  String get channelName;
  String title(TrainingReminder reminder);
  String body(TrainingReminder reminder);
}

/// Ergebnis von [syncTrainingReminders].
enum ReminderSyncResult {
  /// Ausgeschaltet: alles storniert.
  off,

  /// Eingeschaltet, aber Benachrichtigungen nicht erlaubt: alles storniert.
  notPermitted,

  /// Kein Ziel (gelöscht oder nie angelegt): alles storniert.
  noGoal,

  /// Neu geplant (auch mit null Erinnerungen).
  scheduled,
}

/// Plant die Erinnerungen aus dem gespeicherten Plan neu (nach Start,
/// Planänderung, Neuberechnung, Einstellungsänderung). Ersetzt immer alle
/// geplanten; ohne Einschalten, Berechtigung oder Ziel storniert es alle.
Future<ReminderSyncResult> syncTrainingReminders({
  required SettingsStore settings,
  required GoalStore goals,
  required PlanRepository plans,
  required ReminderScheduler scheduler,
  required Clock clock,
  required ReminderTexts texts,
}) async {
  final s = await ReminderSettings.load(settings);
  if (!s.enabled) {
    await scheduler.cancelAll();
    return ReminderSyncResult.off;
  }
  if (!await scheduler.permitted()) {
    await scheduler.cancelAll();
    return ReminderSyncResult.notPermitted;
  }
  final goal = await goals.goal();
  if (goal == null) {
    await scheduler.cancelAll();
    return ReminderSyncResult.noGoal;
  }
  final now = clock.now().toLocal();
  final today = calendarDay(now);
  final units = await plans.unitsBetween(
    today,
    today.add(const Duration(days: reminderHorizonDays)),
  );
  final reminders = planTrainingReminders(
    units: units,
    settings: s,
    now: now,
    planEnd: goal.targetDate,
  );
  await scheduler.replaceAll([
    for (final r in reminders)
      ScheduledReminder(at: r.at, title: texts.title(r), body: texts.body(r)),
  ], channelName: texts.channelName);
  return ReminderSyncResult.scheduled;
}
