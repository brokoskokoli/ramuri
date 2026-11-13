/// Port: Sprachausgabe des Telefons (WP24, Festlegung 9). Der Adapter nutzt
/// die Sprachausgabe des Systems; es geht nichts ins Netz und kein Text in Logs.
///
/// Aufrufer behandeln jeden Fehler und jedes Hängen als folgenlos: die
/// Sprachausgabe darf die Aufzeichnung nie stören.
abstract interface class VoicePort {
  /// Spricht [text] in der Sprache [languageTag] (BCP 47, etwa `de`); `null`
  /// lässt die Sprache des Systems. Eine laufende Ansage wird abgelöst.
  Future<void> speak(String text, {String? languageTag});

  /// Bricht eine laufende Ansage ab und gibt den Audio-Fokus frei.
  Future<void> stop();
}
