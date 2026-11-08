# ADR-0003 — Speicherung und Verschlüsselung auf dem Gerät

- **Status:** Accepted (Maintainer, 2026-11-04)
- **Datum:** 2026-11-04
- **Quellen:** SRC-003 (OQ-0024, OQ-0056)
- **Betroffene Anforderungen:** SEC-0004, SEC-0009, SEC-0010, FR-0193, OQ-0024, OQ-0056, ADR-0001

## Kontext
Die Datenbankdatei muss ohne Schlüssel unlesbar sein (SEC-0009), ein System-Backup darf keine App-Daten enthalten (SEC-0010), und gelöschte Daten müssen wirklich entfernt sein (SEC-0004). Die Aufzeichnung schreibt bei ausgeschaltetem und gesperrtem Bildschirm weiter (FR-0034).

## Entscheidung
**1. Datenbank:** `drift` 2.35.3 (MIT, Stand 2026-10-23) auf `sqlite3` 3.8.0 (MIT, Stand 2026-10-23) mit `hooks: user_defines: sqlite3: source: sqlite3mc` [1][2]. Das baut SQLite3MultipleCiphers (MIT) ein, Standardverfahren ChaCha20-Poly1305 mit Authentifizierung je Seite [3][4]. SQLite selbst ist Public Domain [5]. Die Binärdateien kommen aus den Releases von `sqlite3` und werden per SHA-256 geprüft [2]. Beim Öffnen prüft die App zur Laufzeit, dass die Verschlüsselung aktiv ist, wie drift es empfiehlt [1]; ohne sie öffnet sie die Datei nicht.

**2. Schlüssel:** Ein zufälliger Datenbankschlüssel je Installation, abgelegt mit `flutter_secure_storage` 11.2.0 (BSD-3-Clause, Stand 2026-09-16). Das Plugin schützt ihn über einen Schlüssel im Android Keystore und nutzt Tink (Apache-2.0) [6][7][8]. Kein Passwort des Nutzers und keine Bindung an Biometrie oder entsperrtes Gerät, weil die Aufzeichnung sonst bei gesperrtem Bildschirm an den Schlüssel gebunden wäre. Der Schlüssel wird zum Laufstart gelesen und bleibt im Prozess.

**3. Backups aus, dreifach:**
- `android:allowBackup="false"`. Das allein reicht nicht: Ab Android 12 schaltet es auf manchen Geräten die Übertragung von Gerät zu Gerät nicht ab [9].
- `dataExtractionRules` mit `<cloud-backup>` und `<device-transfer>`, die alle Domains ausschließen. Fehlt ein Abschnitt, ist diese Art der Übertragung voll aktiv [9].
- Datenbank in `getNoBackupFilesDir()`, das immer ausgenommen ist [9]. Der Pfad braucht voraussichtlich einen kleinen eigenen Plattformaufruf.

**4. Löschen:** `PRAGMA secure_delete = ON`, damit gelöschte Inhalte überschrieben werden [10]; nach dem Löschen ein WAL-Checkpoint.

**5. Haltbarkeit:** Für die Lauf-Datenbank WAL mit `synchronous = FULL` (der Kartenspeicher nach ADR-0009 Punkt 4 ist abgeleitet und nutzt kein WAL), denn nur so überstehen bestätigte Transaktionen einen Stromausfall [10]. Die Kosten sind klein (R005: Commit p50 unter 7 ms bei 1 Punkt je Sekunde, nur relativ gültig).

## Erwogene Alternativen
- **`sqlcipher_flutter_libs`:** Eingestellt (0.7.0+eol), drift verweist auf den Weg über `sqlite3` 3.x [1][11]. SQLCipher bindet auf Android zudem OpenSSL ein [2].
- **`encrypted_drift`:** Läuft über ein Java-Plugin; drift rät neuen Apps davon ab [1].
- **Nur die Geräteverschlüsselung von Android:** Erfüllt das Akzeptanzkriterium von SEC-0009 nicht, weil die Datei für das entsperrte System lesbar bleibt.
- **Eigener Keystore-Code statt Plugin:** Weniger Abhängigkeiten, aber selbst gepflegte Kryptografie. Bleibt Rückfallweg hinter dem Port.
- **Schlüssel per Biometrie schützen:** Weder verlangt noch mit der Aufzeichnung bei gesperrtem Gerät vereinbar. App-Sperre bleibt ein Vorschlag in [security.md](../../quality/security.md).

**Nachtrag nach R005 (K9):**
- **WAL:** Im Stand sqlite3mc 2.6.1 und SQLite 3.54.0 nachweislich verschlüsselt (Rechner, API 31, API 36); Frame-Köpfe bleiben Klartext.
- **Punkt 5:** `FULL` verlor im Emulator keine bestätigte Zeile (41 harte Kills vor dem ersten Checkpoint, je 14 `sigkill` bei wiederverwendetem WAL und mit Zeilen nur in der Hauptdatei), die Kontrolle `NORMAL` verlor. `adb emu kill` und `sigkill` nähern sich dem Stromausfall nur an. Kill mitten im Checkpoint und Checkpoints von 1000 Frames sind nicht gemessen.
- **Warnung:** Seitengrößenwechsel nur außerhalb von WAL; die FAQ-Prozedur hinterlässt sonst eine Klartextdatei. Die Laufzeitprüfung aus Punkt 1 ist daher auch nach Wartungsschritten nötig.
- **Offen:** Das WAL kann bei Manipulation still abgeschnitten werden; die Authentifizierung je Seite fängt verworfene WAL-Enden nicht ab. Die Bewertung steht aus.

## Konsequenzen
- Geht der Schlüssel verloren (Keystore-Fehler, Gerätewechsel), sind lokale Daten unwiederbringlich; es bleibt nur das Archiv (ADR-0001). Das Verhalten dabei legt die Spec nicht fest.
- Laut Plugin kann Android-Backup zu `InvalidKeyException` führen [6]; Punkt 3 schließt das aus.
- Solange der Prozess läuft, liegt der Schlüssel im Speicher. Das schützt nicht gegen ein kompromittiertes, entsperrtes Gerät.
- Der Schutz des Gesamtexports (SEC-0011) ist hier nicht entschieden; Verfahren und Schlüsselableitung brauchen vor FR-0192 eine eigene Festlegung.

## Im Emulator nicht belegbar
Hardwaregebundener Keystore, echter Stromausfall (`adb emu kill` ist nur eine Näherung), Übertragungswerkzeuge der Hersteller und physische Reste gelöschter Daten im Flash. Prüfbar sind System-Backup und -Restore mit den Testwerkzeugen von Android [9], die unlesbare Datei und das Öffnen ohne Schlüssel.

## Offene Punkte
Für Verschlüsselung im WAL-Modus nennt SQLite3MultipleCiphers eigene Implementierungen und Korrekturen im Changelog [12], eine geschlossene Aussage dazu fand ich nicht; R005 belegt es durch Messung, siehe Nachtrag. Auch `<cross-platform-transfer>` (ab Android 16 QPR2) verlangt iOS-Kennungen [9]; dass ohne diesen Abschnitt nichts übertragen wird, ist unbelegt.

## Belege (Abruf 2026-11-04)
[1] https://drift.simonbinder.eu/platforms/encryption/ ·
[2] https://github.com/simolus3/sqlite3.dart/blob/main/sqlite3/doc/hook.md ·
[3] https://github.com/utelle/SQLite3MultipleCiphers/blob/main/LICENSE ·
[4] https://utelle.github.io/SQLite3MultipleCiphers/docs/ciphers/cipher_chacha20/ ·
[5] https://www.sqlite.org/copyright.html ·
[6] https://pub.dev/packages/flutter_secure_storage ·
[7] https://developer.android.com/privacy-and-security/keystore ·
[8] https://github.com/tink-crypto/tink-java/blob/main/LICENSE ·
[9] https://developer.android.com/guide/topics/data/autobackup ·
[10] https://www.sqlite.org/pragma.html ·
[11] https://pub.dev/packages/sqlcipher_flutter_libs ·
[12] https://github.com/utelle/SQLite3MultipleCiphers/blob/main/CHANGELOG.md

Lizenzen von `drift`, `sqlite3` und `flutter_secure_storage` an der Lizenzdatei des jeweils aktuellen pub.dev-Archivs geprüft.
