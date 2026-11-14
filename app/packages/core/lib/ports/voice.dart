/// Port: Sprachausgabe des Telefons (WP24, Festlegung 9). Der Adapter nutzt
/// die Sprachausgabe des Systems; es geht nichts ins Netz und kein Text in Logs.
///
/// Aufrufer behandeln jeden Fehler und jedes Hängen als folgenlos: die
/// Sprachausgabe darf die Aufzeichnung nie stören.
abstract interface class VoicePort {
  /// Spricht [text] in der Sprache [languageTag] (BCP 47, etwa `de`); `null`
  /// lässt die Sprache des Systems. Mehrere Ansagen werden der Reihe nach
  /// gesprochen, keine geht verloren.
  Future<void> speak(String text, {String? languageTag});

  /// `false`, wenn die Sprachausgabe fehlt oder nicht läuft (Engine aus, keine
  /// Stimme oder Sprachdaten für [languageTag]); dann bleiben Ansagen still.
  /// Ein Fehler oder Hängen heißt „unbekannt“: Aufrufer weisen dann nicht hin.
  Future<bool> available({String? languageTag});

  /// Bricht eine laufende Ansage ab und gibt den Audio-Fokus frei.
  Future<void> stop();
}
