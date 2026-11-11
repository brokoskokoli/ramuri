import 'hint_selection.dart';

/// Modell der Karte „Erholung“ auf „Heute“ in der Basisstufe (FR-0106,
/// FR-0107, OQ-0077, PAR-184): nur der Code des Texthinweises und die Belege
/// für „Worauf beruht das?“. Bewusst ohne Zahl, ohne Zustand und ohne
/// Ruhepuls: Es gibt keine Bewertung, kein Band und keine positive Meldung.
class RecoveryCard {
  const RecoveryCard._(this.hint);

  /// Der Hinweis hinter der Karte (Code, Knopf, Belege).
  final Hint hint;

  HintCode get code => hint.code;
  HintAction? get action => hint.action;

  /// „Worauf beruht das?“: die Datenbelege des Hinweises.
  List<Evidence> get basis => hint.evidence;

  Map<String, Object?> toJson() => {
    'hint': hint.code.name,
    'action': hint.action?.name,
    'basis': [for (final e in hint.evidence) e.toJson()],
  };

  /// Die Karte zum Hinweis, `null` ohne Hinweis: Ohne Auslöser gibt es kein
  /// Modell, die Karte ist ausgeblendet (K58, PAR-184).
  static RecoveryCard? from(HintSelection selection) {
    final h = selection.hint;
    return h == null ? null : RecoveryCard._(h);
  }
}
