# WP21 – Planmodell und Planerzeugung (`core`, Speicher)

**Zuordnung:** M2, Welle 2, nach WP18 und WP20. Parallel zu WP19. Ohne Oberfläche, die kommt mit WP22.

Bezug: FR-0135 bis FR-0155; `docs/planning-rules.md` (PAR-192 bis PAR-206, PAR-058, PAR-059, PAR-065, PAR-081, PAR-082), `docs/phase-2-3-rules.md` (PAR-100 bis PAR-117, PAR-119 bis PAR-121, PAR-132 bis PAR-141); DEC-0002, DEC-0034, DEC-0061; OQ-0048, OQ-0077. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **ADR-0010 (Teil A):** Vorschlag, wie der Plan gespeichert und neu berechnet wird: was festgeschrieben ist (absolvierte Einheiten, Regelversion, Eingaben), was abgeleitet wird, wie Änderungen nachvollziehbar bleiben (NFR-0001, FR-0156, PAR-203). Dem Orchestrator vorlegen, bevor Teil C beginnt.
2. **Ziele (Teil B, FR-0135 bis FR-0137):** Zeit-, Strecken- und offene Fitnessziele bis Halbmarathon, mit Lauftagen, maximaler Zeit und Regler. Keine feste Zielzeit nötig. Speichern, Archiv, Reimport, Löschen.
3. **Planerzeugung (Teil C, FR-0138 bis FR-0143, FR-0147 bis FR-0152):** Wochenzeit nach PAR-192 bis PAR-199, Einheiten nach PAR-197 und PAR-198, Abstand der intensiven Einheiten (FR-0152), Einheit nach FR-0143, Phasen nach FR-0141. Rein regelbasiert und deterministisch.
4. **Zielintensität (Teil D, FR-0144 bis FR-0146, FR-0153):** Rangfolge nach PAR-100 bis PAR-107, Grundlage als Text (PAR-106), RPE immer dabei, Pace immer als Bereich.
5. **Einstieg (Teil E, FR-0140, FR-0155):** Geh-Lauf-Abfolge nach PAR-065 und PAR-132 bis PAR-141 als austauschbarer Datensatz an einer Stelle, ohne Nennung des NHS (OQ-0077, PAR-142). Der Plan kommt nur mit dem Smartphone aus.
6. **Machbarkeit (Teil F, FR-0154):** PAR-205 und PAR-206, Anschluss an die Zielprognose aus WP20 (`predictGoal` in `core`).
7. **Aus WP20:** Der Testhinweis PAR-117 nutzt ohne Plan eine Annahme (≥ 12 Läufe in 28 Tagen und ein Lauf ≥ 30 min, K49). Mit dem Plan entscheidet die Planlage nach PAR-117 (3 Läufe je Woche, 30 min am Stück), die Annahme entfällt (Test).

## Umsetzung
- Teile je ein Coder-Auftrag. Reine Funktionen, keine Uhrzeit und kein Zufall im Kern; „heute“ wird übergeben.
- Mutationsbelege für Steigerung, leichtere Woche, Zieltermin, längsten Lauf, Schalter „harte Einheit“, Abstandsregel und Rangfolge.
- **Eigenschaftstests über viele Eingaben:** Wochenzeit nie über dem Regler, keine Einheit über der maximalen Zeit, nie zwei intensive Einheiten ohne Erholung, höchstens eine harte Einheit je Woche, nur gewählte Lauftage.
- Die Rechenbeispiele aus den Regeldokumenten sind Testfälle (etwa 3 × 30 min, Halbmarathon in 12 Monaten).
- Keine neuen Abhängigkeiten.
- **Schema und Archiv:** main hat Schema 6 und Archivformat 2 mit den Abschnitten bis 23 (WP20). WP21 setzt Schema 7 auf; ob dafür ein neues Archivformat nötig ist, entscheidet ADR-0010 nach `docs/contracts/archive.md`. Ältere Archive bleiben lesbar.

## Abnahmekriterien
- [ ] ADR-0010 vorgelegt und entschieden.
- [ ] Akzeptanzkriterien von FR-0135 bis FR-0155, soweit ohne Oberfläche prüfbar; der Rest steht in der Fertigmeldung für WP22.
- [ ] Gleiche Eingaben ergeben denselben Plan (Test); die Regelversion ist mitgespeichert.
- [ ] Die Geh-Lauf-Abfolge lässt sich durch Austausch einer Stelle ersetzen (Test oder Beleg); der NHS wird nirgends in der App genannt.
- [ ] Ziele und Pläne überstehen Archiv und Reimport und verschwinden beim Löschen (Test).
- [ ] Gate grün. E2E entfällt mangels Oberfläche, die Migration wird auf dem Emulator geprüft.
