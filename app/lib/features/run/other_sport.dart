import 'package:core/core.dart';

/// Andere Sportart mit Puls (FR-0221): Merker der Wahl. Namen und Symbole
/// stehen in `ui/format/other_sport_format.dart`, die Regel des
/// Seilspring-Hinweises in `core` (`ropeHintBeforeStart`, `ropeHintForRun`).

/// Einstellung der zuletzt gewählten Sportart (Wert [OtherSport.wire]); gemerkt
/// wie die Laufart `recording.run_mode` (FR-0196).
const String otherSportSettingKey = 'recording.other_sport';

/// Vorgabe ohne gespeicherte Wahl.
const OtherSport defaultOtherSport = OtherSport.rope;

/// Gemerkte Sportart; Fehler oder unbekannter Wert: [defaultOtherSport].
Future<OtherSport> loadOtherSport(SettingsStore settings) async {
  try {
    return OtherSport.fromWire(await settings.get(otherSportSettingKey)) ??
        defaultOtherSport;
  } on Object {
    return defaultOtherSport;
  }
}
