/// Eine geplante Erinnerung, wie sie an das System geht (FR-0174). Sie trägt
/// nur Zeitpunkt und Art der Einheit als Schlüssel ([PlanUnitKind.name]),
/// keine weiteren Plandaten: Der Adapter legt sie außerhalb der verschlüsselten
/// Datenbank ab, damit er nach einem Geräteneustart ohne Dart neu planen kann
/// (bewusste, minimierte Ausnahme zu SEC-0009, WP22 Teil F).
class ScheduledReminder {
  const ScheduledReminder({required this.at, required this.kind});

  /// Zeitpunkt der Benachrichtigung.
  final DateTime at;

  /// Art der Einheit als Schlüssel (etwa `easy`); der Text kommt aus
  /// [ReminderLabels.bodies].
  final String kind;

  @override
  bool operator ==(Object other) =>
      other is ScheduledReminder &&
      other.at.isAtSameMomentAs(at) &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(at.millisecondsSinceEpoch, kind);

  @override
  String toString() => 'ScheduledReminder($at, $kind)';
}

/// Texte der Benachrichtigungen in der App-Sprache: Kanalname, Titel und je
/// Art der Einheit der Text („Langer Lauf um 18:00“). Sie nennen nur Art und
/// Trainingszeit, keine Gesundheitswerte (SEC-0001), und hängen nicht vom Plan
/// ab (für jede Lauf-Art einer).
class ReminderLabels {
  const ReminderLabels({
    required this.channelName,
    required this.title,
    required this.bodies,
  });

  final String channelName;
  final String title;

  /// Text je Art-Schlüssel ([ScheduledReminder.kind]).
  final Map<String, String> bodies;

  @override
  bool operator ==(Object other) =>
      other is ReminderLabels &&
      other.channelName == channelName &&
      other.title == title &&
      other.bodies.length == bodies.length &&
      bodies.entries.every((e) => other.bodies[e.key] == e.value);

  @override
  int get hashCode => Object.hash(
    channelName,
    title,
    Object.hashAllUnordered(bodies.entries.map((e) => '${e.key}=${e.value}')),
  );
}

/// Texte der Morgen-Erinnerung (WP33 Teil D): eigener Kanal, Titel und Text
/// ohne Werte (SEC-0001).
class MorningReminderLabels {
  const MorningReminderLabels({
    required this.channelName,
    required this.title,
    required this.body,
  });

  final String channelName;
  final String title;
  final String body;

  @override
  bool operator ==(Object other) =>
      other is MorningReminderLabels &&
      other.channelName == channelName &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(channelName, title, body);
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

  /// Ersetzt alle geplanten Erinnerungen durch [reminders]; [labels] sind
  /// die Texte in der App-Sprache.
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required ReminderLabels labels,
  });

  /// Storniert alle geplanten und entfernt gezeigte Erinnerungen.
  Future<void> cancelAll();

  /// Plant die tägliche Morgen-Erinnerung (WP33 Teil D) ab [at] (nächstes
  /// Auftreten der Uhrzeit), ersetzt eine geplante. Eigener Wecker und Kanal,
  /// unabhängig von [replaceAll]/[cancelAll]. Der Adapter legt sie nicht in
  /// den eigenen Speicher und plant sie nach einem Neustart nicht neu (keine
  /// SEC-0009-Ausnahme); die App plant sie beim Öffnen neu.
  Future<void> scheduleMorning(
    DateTime at, {
    required MorningReminderLabels labels,
  });

  /// Streicht die Morgen-Erinnerung und entfernt eine gezeigte.
  Future<void> cancelMorning();

  /// Was das Tippen auf eine Benachrichtigung der App verlangt hat (etwa
  /// `morning`); wird mit dem Lesen gelöscht, `null` ohne Anliegen.
  Future<String?> takeLaunchTarget();
}
