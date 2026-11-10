import '../ports/reminder_scheduler.dart';

/// Fake: Berechtigung frei setzbar, merkt sich die geplanten Erinnerungen.
class FakeReminderScheduler implements ReminderScheduler {
  FakeReminderScheduler({this.granted = false, this.grantOnRequest = false});

  /// Stand der Berechtigung.
  bool granted;

  /// Ergebnis der Anfrage: erteilt der Nutzer sie im Dialog?
  bool grantOnRequest;

  int requestCount = 0;
  int cancelCount = 0;
  int replaceCount = 0;

  /// Zuletzt geplant (leer nach [cancelAll]).
  List<ScheduledReminder> scheduled = const [];
  String? channelName;

  @override
  Future<bool> permitted() async => granted;

  @override
  Future<bool> requestPermission() async {
    requestCount++;
    if (grantOnRequest) granted = true;
    return granted;
  }

  @override
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required String channelName,
  }) async {
    replaceCount++;
    scheduled = List.unmodifiable(reminders);
    this.channelName = channelName;
  }

  @override
  Future<void> cancelAll() async {
    cancelCount++;
    scheduled = const [];
  }
}
