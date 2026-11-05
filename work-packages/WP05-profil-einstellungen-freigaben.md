# WP05 – Profil, Einstellungen und Freigaben (`app/lib/features/profile`, `app/lib/features/settings`, `app/packages/core/lib/src/profile`, `app/packages/core/lib/src/consent`)

**Zuordnung:** M1.

Bezug: FR-0001 bis FR-0005, FR-0061, NFR-0006, SEC-0001, SEC-0002, SEC-0007, SEC-0008, CON-0007; PAR-016 bis PAR-019; OQ-0010, OQ-0012, OQ-0013, OQ-0025, OQ-0035, OQ-0038, OQ-0067; ADR-0002, ADR-0004.

## Inhalt
1. **Ersteinrichtung:** Beim ersten Start angeboten und überspringbar; danach ist ein Lauf möglich (FR-0001, OQ-0010).
2. **Profil:** Felder aus FR-0002 außer den Banister-Koeffizienten (ab Phase 2), alle leer lassbar; Plausibilität und Verhalten nach PAR-016 bis PAR-019.
3. **HFmax:** Eingabe hat Vorrang (FR-0003), sonst Näherung nach FR-0004, gekennzeichnet als Schätzung und jederzeit änderbar (FR-0005). Ohne Alter und HFmax Bitte um Eingabe.
4. **Zoneneditor:** Der Nutzer passt die fünf Zonen an (FR-0061); neue Berechnungen verwenden die Einteilung. Nutzt das Zonenmodell aus WP04.
5. **Sprachen und Einheiten:** Alle Texte Deutsch und Englisch, Wahl Kilometer oder Meilen als reine Anzeige (NFR-0006); ein gemeinsamer Formatierer für alle Pakete. Bei jeder anderen Gerätesprache gilt Englisch (OQ-0067); bisher fällt die App auf Deutsch zurück, siehe `app/lib/app.dart`.
6. **Freigaben:** Einwilligung je Quelle mit Zustand in `core`, Prüfung vor jedem Zugriff auf eine freigabepflichtige Quelle, getrennter Widerruf (SEC-0001, SEC-0002, SEC-0007). Phase 1 hat keine solche Quelle (siehe `M1-PLAN.md`, L7), deshalb nur die Logik mit Fake-Quelle und keine Oberfläche dafür.
7. **Android-Berechtigungen:** Einstellungsseite mit dem Stand von Standort, Bluetooth und Schritterkennung und dem Weg in die Systemeinstellungen zum Widerruf (SEC-0007). Einträge erscheinen mit den jeweiligen Paketen.
8. **Keine Übertragung (SEC-0008):** Das Release-Manifest fordert kein `INTERNET`. Fügt ein Plugin die Berechtigung hinzu, ist das zu melden und nicht still zu akzeptieren.

## Umsetzung
- Aus WP04: Der Zoneneditor baut auf `ReserveZones`, `zoneFor` und `validateBounds`.
- **Teile für die Coder-Aufträge:** Teil A: Punkte 2 und 3 in `core` und Speicherzugriff / Teil B: Punkte 1 und 5 mit Oberfläche / Teil C: Punkte 6 bis 8 / Teil D: Punkt 4 nach dem Merge von WP04, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Keine Pakete außerhalb des Flutter-SDKs; Berechtigungsstand über eigenen Plattformaufruf hinter einem Port.
- Offene Punkte aus L3 und L11 (`M1-PLAN.md`) werden gemeldet und nicht im Code entschieden: Felder ohne Werteliste bleiben bis zur Antwort des Maintainers offen; das Paket ist in diesem Punkt nicht fertig.
- Neuberechnung nach Änderung der Basiswerte: WP09 hängt sich ein. Texte zu Zonen als Näherung: WP10 prüft alle Anzeigen, die Regel FR-0064 gilt aber schon hier.
- Nicht dazu: Trainingsplan-Abfrage aus FR-0002 (Phase 2). Die Felder werden gespeichert und noch nicht ausgewertet.
- Parallel: läuft mit WP04. Dateien siehe WP04; gemeinsam nur `app/packages/core/lib/core.dart` und, wenn überhaupt, die ARB-Dateien.

## Abnahmekriterien
- [ ] FR-0001: Einrichtung beim ersten Start, überspringen, Lauf-Start ist erreichbar; beim zweiten Start keine erneute Pflicht.
- [ ] FR-0002: Alle optionalen Felder leer und Grundfunktionen nicht gesperrt.
- [ ] FR-0003, FR-0004: Testfall aus der Spec; mit Messwert und Alter gilt der Messwert; Näherung ist gekennzeichnet (CON-0009) und nicht als individuell genau dargestellt.
- [ ] PAR-016, PAR-017: Eingaben knapp außerhalb abgelehnt, im Hinweisbereich gespeichert mit Hinweis. PAR-018: Konflikt-Eingabe nicht gespeichert. PAR-019: gespeichert, abhängige Werte nicht verfügbar.
- [ ] FR-0061: Angepasste Zonen wirken auf neue Berechnungen (Test mit Zonenmodell aus WP04).
- [ ] NFR-0006: Gerätesprache Französisch zeigt Englisch (Widget-Test und E2E). Der Test aus WP01 schlägt bei fehlendem Schlüssel fehl; Meilen ändern gespeicherte Rohdaten nicht (Test vor und nach der Umstellung).
- [ ] SEC-0001, SEC-0002: Ohne Einwilligung liefert die Fake-Quelle keine Daten; Freigabe von Quelle A gibt B nicht frei. SEC-0007: Nach dem Widerruf keine neuen Daten, und es wird nach dem Löschen importierter Daten gefragt. Mutationsbeleg an der Prüfung (fail-closed).
- [ ] CON-0007: Ohne jede Freigabe bleiben Profil und Grundfunktionen nutzbar.
- [ ] SEC-0008: Die Berechtigungsliste des Release-APK enthält kein `INTERNET` (Prüfung mit `aapt`/`apkanalyzer` belegt).
- [ ] E2E (separater Agent): Erster Start überspringen und ausfüllen; ungültige Werte; Sprachwechsel über das System; Umstellen auf Meilen; Berechtigung im System entzogen und Stand in der App sichtbar.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Rechtliche Einordnung der Einwilligung (OQ-0048). Ein Netzwerkmitschnitt ist auf Phase-1-Funktionen beschränkt; am Ende von M1 wird die Berechtigungsliste erneut geprüft (`M1-PLAN.md`).
