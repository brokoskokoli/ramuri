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
