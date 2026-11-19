/// Mindestlänge eines vergebenen Archivpassworts in Zeichen (ADR-0008
/// Antwort B).
const int archivePasswordMinLength = 15;

enum ArchivePasswordCheck { ok, tooShort, mismatch }

/// Prüft Passwort und Wiederholung (ADR-0008 Antwort B, SEC-0011): Das
/// Passwort ist freiwillig. Leer ist gültig (das Archiv wird dann mit dem
/// leeren Passwort verschlüsselt und ist nicht geschützt); sonst mindestens
/// [archivePasswordMinLength] Zeichen (Unicode-Zeichen, nicht UTF-16-Einheiten
/// und nicht Bytes), keine Klassenregeln, kein Trimmen. Beide Eingaben müssen
/// gleich sein. Die Länge wird zuerst geprüft. Gibt nie das Passwort zurück.
ArchivePasswordCheck checkArchivePassword(String password, String repeated) {
  if (password.isNotEmpty && password.runes.length < archivePasswordMinLength) {
    return ArchivePasswordCheck.tooShort;
  }
  if (password != repeated) return ArchivePasswordCheck.mismatch;
  return ArchivePasswordCheck.ok;
}
