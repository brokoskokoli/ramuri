# WP08 – Hintergrundbetrieb und Wiederanlauf (`app/android`, `app/packages/adapters`, `app/packages/core/lib/src/recording`, `app/lib/features/run`)

**Zuordnung:** M1. **Wartet auf R005.**

Bezug: FR-0034, FR-0193, FR-0202; ADR-0005, ADR-0003 Punkt 5; OQ-0021, OQ-0052, OQ-0061.

Ergebnis von R005 (`research/R005-aufzeichnung-durchstich/RESULTS.md`): Host eigener Dienst mit einer Engine, Partial Wake Lock für die Laufdauer (Entscheidung des Maintainers), eine Zeile je Transaktion mit `synchronous = FULL`, WAL verschlüsselt, keine Änderung an WP02 nötig. Der Schrittsensor unter Typ `location` bleibt offen, er fehlt auf beiden Images.

## Inhalt
1. **Dienst:** Foreground Service aus der sichtbaren App, Diensttypen nach ADR-0005 Punkt 2, Benachrichtigung, Engine und dünner Kotlin-Code nach dem Ergebnis von R005. Die Sitzung aus WP06 läuft unverändert darin.
2. **Durchhalten:** Wake Lock und Transaktionsgröße nach R005; ändert R005 WAL oder Synchronisationsstufe, wird das an der Stelle aus WP02 nachgezogen.
3. **Sensor im Dienst:** Typ `connectedDevice` nur mit `BLUETOOTH_CONNECT`, Verbindung aus WP07 läuft mit gesperrtem Bildschirm weiter (ADR-0006 Punkt 4).
4. **Wiederaufnahme (FR-0193, OQ-0061):** Aktiver Lauf ohne laufenden Dienst beim Start erkannt; der Nutzer wählt Fortsetzen oder als beendet speichern, ohne Frist. Beim Fortsetzen ist die Lücke markiert und die Strecke nicht geschätzt. Kein automatischer Neustart (ADR-0005 Punkt 6).
5. **Schrittfrequenz (FR-0202):** Schrittsensor des Telefons in Kotlin hinter dem Port, eigene Berechtigung, ohne sie „nicht verfügbar“ und normale Aufzeichnung. Füllt die Anzeige aus WP06.

## Umsetzung
- Aus WP06: Ohne monotone Zeit erzeugen Uhrsprünge falsche Lücken und verlängern Zeiten. Ein Lauf, der nach Prozessende `active` bleibt, muss aufgeräumt werden (E2E: Entzug der Standortberechtigung beendet den Prozess). Rohpunkte in manueller Pause liegen gespeichert in deren Lücke.
- Aus WP02: `runs.unfinished()` enthält auch pausierte Läufe. WAL und `synchronous = FULL` stehen als Konstante in `connection_setup.dart`.
- Testhinweise aus R005: `emulator_wake_lock` hält den Emulator wach, ein Vergleich mit und ohne Lock braucht den Eingriff per root; `geo fix` weckt nicht aus dem Suspend; Kill auf API 31 per root; Abstände bis 2 s auf API 36 bei Anfrage 1 s zählen nicht als Lücke.
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1 und 2 / Teil B: Punkt 4 / Teil C: Punkte 3 und 5, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Offen und nicht im Code zu entscheiden (`M1-PLAN.md`, L6): wie die Zeit der Lücke nach einem Abbruch in Gesamt- und Bewegungszeit eingeht. Fortsetzen ohne Standortberechtigung: FR-0195 gilt, der Nutzer kann speichern.
- Kein `BOOT_COMPLETED`, keine Hintergrund-Standortberechtigung.
- Nicht dazu: Akkuoptimierung, Herstellerausnahmen.
- Parallel: läuft mit WP11. WP11 berührt `core/lib/src/export`, `adapters/.../export`, `app/lib/features/export` und das Manifest (FileProvider). Gemeinsam: `AndroidManifest.xml`, ARB-Dateien. Wer später mergt, gleicht ab.

## Abnahmekriterien
- [ ] FR-0193, Logik: Aktiver Lauf ohne Dienst wird beim Start erkannt, ohne aktiven Lauf kein Angebot; Fortsetzen und Speichern ergeben jeweils den erwarteten Lauf; die Lücke erhöht die Strecke nicht; Mutationsbeleg.
- [ ] Nach beendetem Lauf oder gewählter Option kommt das Angebot nicht wieder. Keine Frist: Ein Test mit weit vorgestellter Uhr bietet die Wiederaufnahme weiter an.
- [ ] FR-0202: Mit Berechtigung liefert der Fake-Sensor Werte in die Anzeige; ohne Berechtigung „nicht verfügbar“ und normaler Lauf; im Emulator soweit ein Sensor vorhanden, sonst als ungeprüft gemeldet.
- [ ] Dienst startet ohne `POST_NOTIFICATIONS`; ohne `BLUETOOTH_CONNECT` kein `connectedDevice` und keine `SecurityException`.
- [ ] Manifest: keine Hintergrund-Standortberechtigung, kein `BOOT_COMPLETED`.
- [ ] E2E (separater Agent), API 31 und 36, GPS-Wiedergabe: Lauf bei gesperrtem Bildschirm und `dumpsys deviceidle force-idle` mit Auswertung der Lücken; Prozess-Kill und Wischen aus den letzten Apps, danach beide Optionen; `adb emu kill` als Näherung an einen Stromausfall; Berechtigung im Lauf entzogen; Test-Sensor bei gesperrtem Bildschirm mit Abbruch.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
FR-0034 unter Feldbedingungen („durchgehende Daten“), Kill durch Energiesparmodi der Hersteller, Akkuverbrauch, echter Stromausfall, ACC-02 im Hintergrund. Die E2E-Szenarien sind nur Näherungen; FR-0034 bleibt in `STATUS.md` offen und wird nicht als erfüllt gemeldet.
