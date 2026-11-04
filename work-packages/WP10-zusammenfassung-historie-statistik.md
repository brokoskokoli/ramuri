# WP10 – Zusammenfassung, Historie, Statistik und Transparenz (`app/lib/features/summary`, `history`, `statistics`, `app/packages/core/lib/src/statistics`)

**Zuordnung:** M1.

Bezug: FR-0037, FR-0040 bis FR-0044, FR-0054, FR-0055, FR-0059, FR-0064, FR-0067, FR-0072, FR-0081, FR-0084, FR-0088, FR-0094, NFR-0003, NFR-0004, CON-0005, CON-0009, SEC-0005, ACC-04, ACC-05, ACC-06; PAR-012, PAR-013; OQ-0012, OQ-0037, OQ-0039, OQ-0040.

## Inhalt
1. **Zusammenfassung:** Alle Punkte aus FR-0037 nach dem Beenden, Bestpace und Einordnung nach OQ-0037, optionaler VO₂max-Wert aus WP09; Fehlendes als nicht verfügbar.
2. **Historie und Detail:** Liste nach FR-0040, Detail mit Route, Zeitverlauf und Diagrammen (FR-0041), Pace und Puls im Vergleich (FR-0042), Löschen aus WP02 eingehängt. Route und Diagramme als eigene Zeichnung mit Flutter-Mitteln, ohne Paket und ohne Netz.
3. **Statistik:** Kennzahlen aus FR-0043, die ihre Lieferfunktion in Phase 1 haben, Zeiträume nach FR-0044; Summen in `core` und getestet. Kennzahlen späterer Phasen erscheinen noch nicht.
4. **Fitnessanzeige:** Drei benannte Sichten auf die VO₂max (FR-0081), Kennzeichnung als Schätzung (FR-0067), Kennzahl der aeroben Effizienz in der Statistik (FR-0084) und Abgrenzung (FR-0088).
5. **Transparenz:** Erklärung zu jedem geschätzten Wert mit den sechs Fragen aus FR-0059 und dem Grund bei fehlendem Wert; Datenbasis und Bitte um Eingabe nach FR-0055; Quelle je Datensatz abrufbar (SEC-0005).
6. **Sprachregeln:** Keine Genauigkeits- oder Validierungsaussage (FR-0054, FR-0072, NFR-0003, NFR-0004), Zonen nicht als Schwellen (FR-0064), TRIMP nicht als Ermüdung (FR-0094), Schätzungen erkennbar (CON-0009). Gilt für alle Texte der ARB-Dateien, auch aus früheren Paketen.

## Umsetzung
- **Teile für die Coder-Aufträge:** Teil A: Punkt 3 in `core` und die Berechnungen zu Punkt 1 / Teil B: Punkte 1 und 2 / Teil C: Punkte 3 und 4 mit Oberfläche / Teil D: Punkte 5 und 6, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Karte: `M1-PLAN.md`, L2. Ohne Entscheidung des Maintainers gibt es nur die gezeichnete Route, kein Laden von Kartenkacheln (SEC-0008).
- Offen: L4 (persönliche Bestzeiten), L5 (Vergleichsgröße der Einordnung). Sie werden gemeldet und nicht im Code entschieden; die betroffenen Punkte erscheinen bis zur Antwort als nicht verfügbar.
- Nicht dazu: ATL und CTL, Prognosen, Readiness, subjektive Angaben, Energiereserve.
- Parallel: läuft mit WP07. Dateien siehe WP07.

## Abnahmekriterien
- [ ] FR-0037: Alle Punkte mit und ohne Daten; Bestpace mit Testfall und mit Lauf kürzer als die Bestpace-Strecke sowie mit Lücke darin; Einordnung mit weniger Vorläufen, als OQ-0037 vergleicht.
- [ ] FR-0028 (Oberfläche, aus WP06), FR-0040, ACC-04: Jeder Lauf mit Strecke, Dauer und Pace; fehlender Puls nicht als 0.
- [ ] FR-0041, FR-0042: Route und Diagramme werden angezeigt (Widget-Tests); ein Lauf mit Lücke zeigt die Lücke und verbindet sie nicht als gemessenen Verlauf.
- [ ] FR-0043, FR-0044: Alle vier Zeiträume wählbar; die Summe der Läufe einer Woche entspricht der Wochenstatistik; freier Zeitraum und Grenze über den Jahreswechsel; Kennzahlen berechnet oder als nicht verfügbar erkennbar.
- [ ] FR-0067, ACC-05: Jede Anzeige des Werts als Schätzung gekennzeichnet; ohne geeignete Daten kein Wert. FR-0081: Drei getrennte, eindeutig benannte Sichten. FR-0084: Sichtbar, sofern Daten vorliegen, sonst Grund.
- [ ] FR-0059, ACC-06, CON-0005: Alle sechs Fragen für einen berechneten Wert beantwortet; bei nicht berechnetem Wert der Grund sichtbar.
- [ ] FR-0055: Mit nur GPS funktioniert die Grundstatistik; fehlt ein Profilwert, zeigt die Funktion „nicht verfügbar“ mit Hinweis.
- [ ] SEC-0005: Zu einem gemessenen Datensatz ist die Quelle abrufbar.
- [ ] FR-0054, FR-0064, FR-0072, FR-0088, FR-0094, NFR-0003, NFR-0004, CON-0009: Durchsicht aller ARB-Texte durch den Reviewer, Ergebnis im Review festgehalten; es gibt keinen Validierungsnachweis, also keine Genauigkeitsangabe.
- [ ] E2E (separater Agent): Nach einem Lauf aus der Wiedergabe Zusammenfassung, Historie, Detail; vorbefüllte synthetische Historie für Woche, Monat und freien Zeitraum; Lauf ohne Puls; Erklärung eines Werts; Lauf löschen samt Hinweis; ACC-14 ohne Netz.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Lesbarkeit im Freien und Bedienung im Feld. NFR-0004: Die Validierung erfolgt im Feldtest und ist kein Release-Gate (OQ-0020).
