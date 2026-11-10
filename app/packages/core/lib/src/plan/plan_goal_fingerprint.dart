import 'dart:convert';

import '../goals/training_goal.dart';

/// Schlüssel des Ziel-Fingerabdrucks im `summary`-JSON einer Fassung
/// (WP22). Das Archiv beschreibt `summary` nur als JSON-Objekt.
const String planGoalFingerprintKey = 'goalFingerprint';

/// Version der Form von [planGoalFingerprint].
const int planGoalFingerprintVersion = 1;

String? _day(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

/// Fingerabdruck der planrelevanten Felder des Ziels: Art, Strecke und
/// Zielzeit, Zieldatum, Lauftage, maximale Zeit je Einheit, Regler, Stand
/// (Wochenzeit und „30 min am Stück“) und Schalter „harte Einheit“; nicht
/// der Zeitpunkt des Anlegens. Gleiche Felder ergeben denselben Text.
String planGoalFingerprint(TrainingGoal goal) => jsonEncode({
  'v': planGoalFingerprintVersion,
  'type': goal.type.name,
  'distance': goal.distance?.name,
  'targetSeconds': goal.targetSeconds,
  'targetDate': _day(goal.targetDate),
  'runDays': [...goal.runDays]..sort(),
  'maxSessionSeconds': goal.maxSessionSeconds,
  'weeklyCapSeconds': goal.weeklyCapSeconds,
  'currentWeeklySeconds': goal.currentWeeklySeconds,
  'canRun30': goal.canRun30.name,
  'hardSessionEnabled': goal.hardSessionEnabled,
});

/// Weicht [goal] vom Ziel ab, mit dem die Fassung mit diesem [summary]
/// gerechnet wurde? Nur wenn die Fassung einen lesbaren Fingerabdruck in
/// dieser Version trägt; ohne (ältere Fassung) wird keine Änderung
/// angenommen.
bool planGoalChangedSince(Map<String, Object?> summary, TrainingGoal goal) {
  final stored = summary[planGoalFingerprintKey];
  if (stored is! String) return false;
  try {
    final m = jsonDecode(stored);
    if (m is! Map || m['v'] != planGoalFingerprintVersion) return false;
  } on FormatException {
    return false;
  }
  return stored != planGoalFingerprint(goal);
}
