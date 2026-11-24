import 'package:core/core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Andere Sportart mit Puls (FR-0221): Namen, Symbole, Merker der Wahl und
/// die Regeln der Hinweise. Der Zähler der Seilspring-Einheiten kommt aus den
/// gespeicherten Einheiten, ohne eigenes Feld.

/// Einstellung der zuletzt gewählten Sportart (Wert [OtherSport.wire]); gemerkt
/// wie die Laufart `recording.run_mode` (FR-0196).
const String otherSportSettingKey = 'recording.other_sport';

/// Vorgabe ohne gespeicherte Wahl.
const OtherSport defaultOtherSport = OtherSport.rope;

/// Hinweis Wade/Achillessehne: in den ersten so vielen Seilspring-Einheiten.
const int ropeHintRuns = 3;

String otherSportName(AppLocalizations l10n, OtherSport sport) =>
    switch (sport) {
      OtherSport.rope => l10n.otherSportRope,
      OtherSport.cycling => l10n.otherSportCycling,
      OtherSport.rowing => l10n.otherSportRowing,
      OtherSport.other => l10n.otherSportOther,
    };

IconData otherSportIcon(OtherSport sport) => switch (sport) {
  OtherSport.rope => Icons.sports_gymnastics,
  OtherSport.cycling => Icons.directions_bike,
  OtherSport.rowing => Icons.rowing,
  OtherSport.other => Icons.sports,
};

/// Rad und Rudern: Die Belastung aus dem Pulsbereich vom Laufen ist eher
/// unterschätzt (Hinweis in Zusammenfassung und Detail).
bool otherSportUnderestimated(OtherSport? sport) =>
    sport == OtherSport.cycling || sport == OtherSport.rowing;

/// Gemerkte Sportart; Fehler oder unbekannter Wert: [defaultOtherSport].
Future<OtherSport> loadOtherSport(SettingsStore settings) async {
  try {
    return OtherSport.fromWire(await settings.get(otherSportSettingKey)) ??
        defaultOtherSport;
  } on Object {
    return defaultOtherSport;
  }
}

bool _isRope(StoredRun r) =>
    r.mode == RunMode.sport && r.sport == OtherSport.rope;

/// Start: Hinweis, solange weniger als [ropeHintRuns] Seilspring-Einheiten
/// beendet gespeichert sind (die neue wäre die 1. bis 3.). Lesefehler: zeigen.
Future<bool> ropeHintBeforeStart(RunStore runs) async {
  try {
    final done = (await runs.list())
        .where((r) => r.state == RunState.finished && _isRope(r))
        .length;
    return done < ropeHintRuns;
  } on Object {
    return true;
  }
}

/// Zusammenfassung: Hinweis, wenn [runId] unter den ersten [ropeHintRuns]
/// beendeten Seilspring-Einheiten ist (nach Start, dann Nummer).
/// Lesefehler: zeigen.
Future<bool> ropeHintForRun(RunStore runs, int runId) async {
  try {
    final rope =
        (await runs.list())
            .where(
              (r) =>
                  _isRope(r) && (r.state == RunState.finished || r.id == runId),
            )
            .toList()
          ..sort((a, b) {
            final c = a.startedAt.compareTo(b.startedAt);
            return c != 0 ? c : a.id.compareTo(b.id);
          });
    final rank = rope.indexWhere((r) => r.id == runId);
    return rank >= 0 && rank < ropeHintRuns;
  } on Object {
    return true;
  }
}
