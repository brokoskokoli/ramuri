/// Grenzen der Angaben (FR-0038). Kein Klemmen und kein Runden: Ein Wert
/// außerhalb ist ein Fehler.
const int rpeMin = 0;
const int rpeMax = 10;
const int wellbeingMin = 1;
const int wellbeingMax = 5;

/// Ein Wert liegt außerhalb seines Bereichs. Nennt nur das Feld, nie den Wert
/// (Gesundheitsdaten gehören nicht in Fehlertexte, SEC).
class SubjectiveRangeError extends ArgumentError {
  SubjectiveRangeError(String field)
    : super('Wert außerhalb des Bereichs', field);
}

/// [value] oder `null`; wirft [SubjectiveRangeError] außerhalb von 0 bis 10.
int? checkRpe(int? value) {
  if (value != null && (value < rpeMin || value > rpeMax)) {
    throw SubjectiveRangeError('rpe');
  }
  return value;
}

/// [value] oder `null`; wirft [SubjectiveRangeError] außerhalb von 1 bis 5.
int? checkWellbeing(int? value) {
  if (value != null && (value < wellbeingMin || value > wellbeingMax)) {
    throw SubjectiveRangeError('wellbeing');
  }
  return value;
}
