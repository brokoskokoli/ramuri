# WP02 – Verschlüsselte Speicherung und Löschen (`app/packages/core`, `app/packages/adapters`, `app/android`, `app/lib/features/storage`)

**Zuordnung:** M1.

Bezug: SEC-0004, SEC-0009, SEC-0010; ADR-0003, ADR-0004 Punkte 1, 4 und 6, ADR-0001; OQ-0025, OQ-0031, OQ-0056, OQ-0062; Begriffe in `docs/architecture/data-model.md`.

Startet ohne R005: WAL und Synchronisationsstufe folgen ADR-0003 und stehen an genau einer Stelle. Ändert das Ergebnis von R005 etwas daran, setzt WP08 das um.

## Inhalt
1. **Datenbank:** drift auf `sqlite3` mit `sqlite3mc` nach ADR-0003 Punkt 1, mit Laufzeitprüfung der aktiven Verschlüsselung; ohne sie öffnet die App die Datei nicht. Pfad in `getNoBackupFilesDir()`.
2. **Schlüssel:** Zufälliger Schlüssel je Installation über den Port Schlüsselablage, `flutter_secure_storage` nach ADR-0003 Punkt 2.
3. **Schema Phase 1 als erste Version:** Alle Tabellen, die Phase 1 braucht, damit spätere Pakete nur noch Zugriffe ergänzen: Lauf mit Zustand, Rohdaten-Messreihen (nur anhängen; Zeitstempel, Quellgerät, Zustand nach FR-0057), Runden, Lücken, Vorverarbeitung, Abschnitte mit Bewertung, berechnete Werte (`original`/`current`, Methode, Version, Parameterstand, übrige Angaben aus FR-0053), Profil und Einstellungen, bekannte Geräte, Einwilligungen. Phase-2-Objekte kommen später per Migration.
4. **Migrationen:** Versionierter Ablauf mit Test je Schritt und Prüfung, dass das Schema dem Stand entspricht (ADR-0004 Punkt 6).
5. **Backups aus:** Alle drei Maßnahmen aus ADR-0003 Punkt 3, ohne Schalter (OQ-0056).
6. **Löschen:** Je Lauf und komplett, einschließlich aller abgeleiteten Werte; `secure_delete` und WAL-Checkpoint nach ADR-0003 Punkt 4. Der Dialog weist darauf hin, dass bereits weitergegebene Dateien, etwa bei Strava, dort bleiben (OQ-0025).
7. **Datenbank nicht zu öffnen (OQ-0062):** Die App erklärt das Problem und bietet den Neubeginn mit leerer Datenbank an; die alte Datei bleibt bis zur ausdrücklichen Bestätigung. Der Eintrag „Reimport aus dem Archiv“ kommt mit WP12.

## Umsetzung
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1, 2 und 5 / Teil B: Punkte 3 und 4 / Teil C: Punkt 6 als Dienst und Dialog / Teil D: Punkt 7 mit Oberfläche, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- SEC-0009 „Zugangsdaten externer Dienste“ hat in Phase 1 keinen Anwendungsfall (OQ-0049). Es wird nichts dafür gebaut.
- Nicht dazu: Fachlogik, Export, Archiv, Oberfläche für den Listeneintrag eines Laufs (WP10 hängt das Löschen dort ein).
- Parallel: läuft mit WP03. WP03 berührt nur `app/packages/core/lib/src/preprocessing/` und seine Tests; gemeinsam nur der Export in `app/packages/core/lib/core.dart`.

## Abnahmekriterien
- [ ] Die Datenbankdatei ist ohne Schlüssel nicht lesbar: Öffnen ohne und mit falschem Schlüssel scheitert; eingefügte synthetische Marken sind weder in Haupt- noch in WAL-Datei im Klartext zu finden.
- [ ] Ist die Verschlüsselung zur Laufzeit nicht aktiv, öffnet die App die Datei nicht (Test mit Fake; Mutationsbeleg).
- [ ] Fehlender Schlüssel: Die alte Datei bleibt unverändert, bis der Nutzer bestätigt; Abbrechen lässt sie stehen; erst nach der Bestätigung ist sie weg (SEC-0009, OQ-0062).
- [ ] Rohdaten lassen sich über die Zugriffsschicht nicht ändern, nur anhängen und mit dem Lauf löschen.
- [ ] Löschen eines Laufs entfernt Rohdaten, Abschnitte und Werte, andere Läufe bleiben. „Alles löschen“ hinterlässt eine leere Datenbank; eine Marke ist danach samt Checkpoint in der Datei nicht zu finden. Negativfall: Abbruch im Dialog löscht nichts. Mutationsbeleg an Fremdschlüssel oder Löschlogik.
- [ ] Je Migrationsschritt ein Test; das erzeugte Schema entspricht dem Stand.
- [ ] Logs enthalten keine Messwerte, Profilwerte oder Schlüssel (Test mit synthetischer Marke).
- [ ] E2E (separater Agent), API 31 und 36: System-Backup und -Restore mit den Android-Testwerkzeugen enthalten keine App-Daten (SEC-0010); App-Daten nach Neustart lesbar; gelöschter Schlüssel führt zum Dialog; Löschen im Dialog bestätigt und abgebrochen.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Hardwaregebundener Keystore, echter Stromausfall, Übertragungswerkzeuge der Hersteller, physische Reste im Flash, `<cross-platform-transfer>` (ADR-0003).
