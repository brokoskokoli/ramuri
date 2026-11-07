/// Mindestlänge des Archivpassworts in Zeichen (ADR-0008 Antwort B).
const int archivePasswordMinLength = 15;

enum ArchivePasswordCheck { ok, tooShort, mismatch }

/// Prüft Passwort und Wiederholung (ADR-0008 Antwort B, SEC-0011): mindestens
/// [archivePasswordMinLength] Zeichen (Unicode-Zeichen, nicht UTF-16-Einheiten
/// und nicht Bytes), keine Klassenregeln, kein Trimmen, beide gleich. Die
/// Länge wird zuerst geprüft. Gibt nie das Passwort zurück.
ArchivePasswordCheck checkArchivePassword(String password, String repeated) {
  if (password.runes.length < archivePasswordMinLength) {
    return ArchivePasswordCheck.tooShort;
  }
  if (password != repeated) return ArchivePasswordCheck.mismatch;
  return ArchivePasswordCheck.ok;
}
