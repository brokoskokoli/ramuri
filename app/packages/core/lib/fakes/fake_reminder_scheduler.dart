import '../ports/reminder_scheduler.dart';

/// Fake: Berechtigung frei setzbar, merkt sich die geplanten Erinnerungen.
class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({
    this.granted = false,
    this.grantOnRequest = false,
    this.blockedBySystem = false,
  });

  /// Stand der Berechtigung.
  bool granted;

  /// Ergebnis der Anfrage: erteilt der Nutzer sie im Dialog?
  bool grantOnRequest;

  /// Benachrichtigungen im System ausgeschaltet (API 31/32: die Anfrage
  /// meldet trotzdem „erteilt“, [permitted] aber `false`).
  bool blockedBySystem;

  int requestCount = 0;
  int cancelCount = 0;
  int replaceCount = 0;

  /// Zuletzt geplant (leer nach [cancelAll]).
  List<ScheduledReminder> scheduled = const [];
  ReminderLabels? labels;

  String? get channelName => labels?.channelName;

  @override
  Future<bool> permitted() async => granted && !blockedBySystem;

  @override
  Future<bool> requestPermission() async {
    requestCount++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required ReminderLabels labels,
  }) async {
    replaceCount++;
    scheduled = List.unmodifiable(reminders);
    this.labels = labels;
  }

  @override
  Future<void> cancelAll() async {
    cancelCount++;
    scheduled = const [];
  }

  /// Morgen-Erinnerung: nächster Zeitpunkt, `null` = nicht geplant.
  DateTime? morningAt;
  MorningReminderLabels? morningLabels;
  int morningCancelCount = 0;
  int morningScheduleCount = 0;

  /// Was das Tippen auf die Benachrichtigung verlangt hat.
  String? launchTarget;

  @override
  Future<void> scheduleMorning(
    DateTime at, {
    required MorningReminderLabels labels,
  }) async {
    morningScheduleCount++;
    morningAt = at;
    morningLabels = labels;
  }

  @override
  Future<void> cancelMorning() async {
    morningCancelCount++;
    morningAt = null;
  }

  @override
  Future<String?> takeLaunchTarget() async {
    final t = launchTarget;
    launchTarget = null;
    return t;
  }
}
