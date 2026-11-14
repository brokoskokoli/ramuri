import '../../ports/clock.dart';
import '../../ports/reminder_scheduler.dart';
import '../../ports/storage_settings.dart';
import '../ppg/validation_status.dart';
import '../settings/developer_mode.dart';
import '../settings/display_settings.dart';
import 'training_reminders.dart' show ReminderSettings;

/// Einstellungen der Morgen-Erinnerung (WP33 Teil D, K62): freiwillig, aus bis
/// zum Einschalten; eine Uhrzeit für alle Tage. Nur in `settings` der
/// verschlüsselten Datenbank.
class MorningReminderSettings {
  const MorningReminderSettings({
    this.enabled = false,
    this.minuteOfDay = defaultMinuteOfDay,
  });

  /// Vorschlag: 6:30 (Design „Täglich um 6:30“).
  static const int defaultMinuteOfDay = 6 * 60 + 30;

  final bool enabled;
  final int minuteOfDay;

  MorningReminderSettings copyWith({bool? enabled, int? minuteOfDay}) =>
      MorningReminderSettings(
        enabled: enabled ?? this.enabled,
        minuteOfDay: minuteOfDay ?? this.minuteOfDay,
      );

  static Future<MorningReminderSettings> load(SettingsStore store) async {
    final enabled = await store.get(SettingKeys.morningReminderEnabled);
    final time = await store.get(SettingKeys.morningReminderTime);
    return MorningReminderSettings(
      enabled: enabled == '1',
      minuteOfDay: ReminderSettings.parseTime(time) ?? defaultMinuteOfDay,
    );
  }

  Future<void> save(SettingsStore store, {required DateTime at}) async {
    await store.set(
      SettingKeys.morningReminderEnabled,
      enabled ? '1' : '0',
      at: at,
    );
    await store.set(
      SettingKeys.morningReminderTime,
      ReminderSettings.formatTime(minuteOfDay),
      at: at,
    );
  }
}

/// Texte der Morgen-Erinnerung in der App-Sprache (ohne Werte, SEC-0001).
abstract interface class MorningReminderTexts {
  MorningReminderLabels get morningLabels;
}

/// Nächster Zeitpunkt der Uhrzeit [minuteOfDay] (Ortszeit) nach [now].
DateTime nextMorningReminderAt(DateTime now, int minuteOfDay) {
  final local = now.toLocal();
  final today = DateTime(
    local.year,
    local.month,
    local.day,
    minuteOfDay ~/ 60,
    minuteOfDay % 60,
  );
  return today.isAfter(local)
      ? today
      : DateTime(
          local.year,
          local.month,
          local.day + 1,
          minuteOfDay ~/ 60,
          minuteOfDay % 60,
        );
}

/// Ergebnis von [syncMorningReminder].
enum MorningReminderSyncResult {
  /// Ausgeschaltet: gestrichen.
  off,

  /// Morgenmessung nicht erreichbar (Entwicklermodus aus, nicht validiert):
  /// gestrichen.
  unreachable,

  /// Benachrichtigungen nicht erlaubt: gestrichen.
  notPermitted,

  /// Geplant.
  scheduled,
}

/// Plant die Morgen-Erinnerung neu (beim Öffnen der App, nach Änderung,
/// nach Ausschalten des Entwicklermodus): nur eingeschaltet, erreichbar
/// ([morningMeasurementReachable]) und mit Berechtigung; sonst gestrichen.
Future<MorningReminderSyncResult> syncMorningReminder({
  required SettingsStore settings,
  required Clock clock,
  required ReminderScheduler scheduler,
  required MorningReminderTexts texts,
  Map<ValidationQuantity, ValidationState> validationState = ppgValidationState,
}) async {
  final s = await MorningReminderSettings.load(settings);
  if (!s.enabled) {
    await scheduler.cancelMorning();
    return MorningReminderSyncResult.off;
  }
  final dev = await SettingsDeveloperModeStore(settings, clock).read();
  if (!morningMeasurementReachable(
    developerMode: dev,
    state: validationState,
  )) {
    await scheduler.cancelMorning();
    return MorningReminderSyncResult.unreachable;
  }
  if (!await scheduler.permitted()) {
    await scheduler.cancelMorning();
    return MorningReminderSyncResult.notPermitted;
  }
  await scheduler.scheduleMorning(
    nextMorningReminderAt(clock.now(), s.minuteOfDay),
    labels: texts.morningLabels,
  );
  return MorningReminderSyncResult.scheduled;
}
