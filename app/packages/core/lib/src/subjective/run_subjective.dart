import 'srpe.dart';
import 'subjective_limits.dart';

/// Antwort auf die Frage, ob Beschwerden als Warnsignal gelten (PAR-169). Nicht
/// beantwortet ist `null`. Die Antwort wird nur gespeichert und hat keine
/// Wirkung auf Plan oder Warnung (WP23).
enum WarningAnswer { yes, no }

/// Angaben zum Lauf (FR-0038): alles einzeln optional, höchstens ein Satz je
/// Lauf. Werte außerhalb des Bereichs werfen [SubjectiveRangeError].
///
/// Normalisierung: Leere oder nur aus Leerraum bestehende Texte werden `null`.
/// Ohne Beschwerden gibt es keine Warnsignal-Antwort (wird zurückgesetzt).
class RunSubjective {
  RunSubjective({
    int? rpe,
    int? wellbeing,
    String? complaints,
    WarningAnswer? warningAnswer,
    String? note,
  }) : rpe = checkRpe(rpe),
       wellbeing = checkWellbeing(wellbeing),
       complaints = _blankToNull(complaints),
       warningAnswer = _blankToNull(complaints) == null ? null : warningAnswer,
       note = _blankToNull(note);

  static const RunSubjective empty = _Empty();

  /// 0 bis 10.
  final int? rpe;

  /// 1 bis 5.
  final int? wellbeing;
  final String? complaints;
  final WarningAnswer? warningAnswer;

  /// Freitext ohne jede Auswertung.
  final String? note;

  bool get isEmpty =>
      rpe == null &&
      wellbeing == null &&
      complaints == null &&
      warningAnswer == null &&
      note == null;

  @override
  bool operator ==(Object other) =>
      other is RunSubjective &&
      other.rpe == rpe &&
      other.wellbeing == wellbeing &&
      other.complaints == complaints &&
      other.warningAnswer == warningAnswer &&
      other.note == note;

  @override
  int get hashCode =>
      Object.hash(rpe, wellbeing, complaints, warningAnswer, note);

  /// Ohne Inhalte (Gesundheitsdaten gehören nicht in Logs).
  @override
  String toString() => 'RunSubjective(…)';
}

class _Empty implements RunSubjective {
  const _Empty();
  @override
  int? get rpe => null;
  @override
  int? get wellbeing => null;
  @override
  String? get complaints => null;
  @override
  WarningAnswer? get warningAnswer => null;
  @override
  String? get note => null;
  @override
  bool get isEmpty => true;
}

String? _blankToNull(String? s) => s == null || s.trim().isEmpty ? null : s;

/// Angaben eines Laufs, wie sie gespeichert sind, samt sRPE (nur mit RPE und
/// bekannter Bewegungszeit).
class StoredRunSubjective {
  const StoredRunSubjective({required this.subjective, this.srpe});

  final RunSubjective subjective;
  final SrpeLoad? srpe;
}
