/// Eine geplante Erinnerung, wie sie an das System geht (FR-0174). Sie trägt
/// nur Zeitpunkt und fertigen Text; der Text nennt nur die Art der Einheit
/// und die Trainingszeit, keine Gesundheitswerte (SEC-0001).
class ScheduledReminder {
  const ScheduledReminder({
    required this.at,
    required this.title,
    required this.body,
  });

  /// Zeitpunkt der Benachrichtigung.
  final DateTime at;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.at.isAtSameMomentAs(at) &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(at.millisecondsSinceEpoch, title, body);

  @override
  String toString() => 'ScheduledReminder($at, $title, $body)';
}

/// Lokale Erinnerungen des Systems (FR-0174, WP22 Teil F). Kein Netz; der
/// Adapter plant über den Wecker des Systems (inexakt) und plant nach einem
/// Neustart des Geräts selbst neu.
abstract interface class ReminderScheduler {
  /// Darf die App Benachrichtigungen zeigen? Fragt nicht.
  Future<bool> permitted();

  /// Fragt die Berechtigung für Benachrichtigungen an (Systemdialog, nur wenn
  /// nötig); `true`, wenn sie danach erteilt ist.
  Future<bool> requestPermission();

  /// Ersetzt alle geplanten Erinnerungen durch [reminders]. [channelName]
  /// ist der Name des Benachrichtigungskanals in der App-Sprache.
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required String channelName,
  });

  /// Storniert alle geplanten und entfernt gezeigte Erinnerungen.
  Future<void> cancelAll();
}
