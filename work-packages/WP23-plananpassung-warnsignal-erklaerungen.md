# WP23 – Plananpassung, Warnsignal, Erklärungen, Basis-Erholung (`core`, `app/lib/features/plan`, `home`)

**Zuordnung:** M2, Welle 4, nach WP19 und WP22. Parallel zu WP24.

Bezug: FR-0039, FR-0105 bis FR-0107, FR-0156 bis FR-0170, FR-0179 bis FR-0181, FR-0203; PAR-172 bis PAR-186, PAR-188, PAR-200 bis PAR-204; OQ-0011, OQ-0026, OQ-0029, OQ-0048, OQ-0058, OQ-0077. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md). Die in FR-0157 und FR-0158 genannte Erholung aus Phase 3 gehört nicht dazu.

## Inhalt
1. **Anpassung (Teil A, FR-0156 bis FR-0158, FR-0160 bis FR-0162, FR-0164 bis FR-0167, FR-0039):** Nach PAR-201 und PAR-202 von selbst nur nach unten; zusätzliche Läufe erhöhen nichts; Ausgefallenes wird nicht nachgeholt; Auslöser und mindestens wöchentliche Überprüfung. Das Ziel ändert nur der Nutzer, Termine nur nach Bestätigung (FR-0168, FR-0169).
2. **Nachfrage (Teil B, PAR-200):** Alle 2 Wochen „zu leicht, passt oder zu schwer?“, jederzeit auch von sich aus. Keine Antwort ändert nichts.
3. **Warnsignal (Teil C, FR-0163, FR-0203):** Melden und Aufheben im Plan und aus den Beschwerden von WP18. Solange es besteht, nur Ruhetage; Erinnerung nach 7 Tagen. Fester Wortlaut aus FR-0203, keine Diagnose.
4. **Begründungen und Erklärungen (Teil D, FR-0159, FR-0170, FR-0179 bis FR-0181):** Größere Änderung nach PAR-204 mit einem Satz Grund, wie „Plan angepasst“ im Design; Verlauf der Änderungen. Erklärungen nur aus tatsächlichen Daten.
5. **Basis-Erholung (Teil E, FR-0105 bis FR-0107):** Karte auf „Heute“ in der Optik von `Main.dc.html`, nur mit Texthinweis nach PAR-172 ff., ohne Zahl und ohne Zustand (OQ-0077).
6. **Aus WP21:** PAR-140 (Wiederholungsvorschlag Geh-Lauf), PAR-200/201 (Felder in `PlanInputs` nur vorbereitet) und der Neustart nach einer Pause (PAR-202) gehören hierher.
7. **Aus WP22:** Die Karten „Plan angepasst“ und „Erholung“ auf „Heute“ gehören hierher. Beobachtet im E2E: Nach „Neu berechnen“ wurde die heutige unbestätigte Einheit zum Ruhetag (vermutlich Abstandsregel PAR-059, ungeprüft). Ursache klären und, falls ungewollt, beheben (Test).

## Umsetzung
- Teile je ein Coder-Auftrag. Mutationsbelege für jede Regel aus PAR-200 bis PAR-204 und für den Vorrang des Warnsignals.
- **Eigenschaftstest:** Von selbst steigt die Wochenzeit nie stärker als PAR-193, und nie über den Regler; absolvierte Einheiten bleiben unverändert.
- Simulation mehrerer Wochen mit Ausfällen, Pause und hoher RPE als Testfall.
- **Parallel:** `home` nur hier, `run` nur WP24.

## Vorprüfung und Entscheidungen (2026-11-11)
Bericht: `../running-app-wt/handoff/vorpruefung-wp23.md`; Entscheidungen des Maintainers: K58. Wo der Bericht „Empfehlung“ sagt, ist sie entschieden.
- **Schema und Archiv:** Schema 10 mit Tabelle `active_warning`, Archivabschnitt 21 (reserviert). Läuft parallel zu WP25, das ebenfalls Schema 10 braucht: Wer später mergt, zieht auf 11 nach. Weiterer Zustand (letzte Nachfrage, Pausenantwort, Hinweissperre, „gesehen“) in `settings`, mit Archiv und Löschen.
- **Fehlende Verdrahtung aus Vorgängern:** Belastungsdienst übergibt weder erwartete Einheiten noch bestätigte Pausen (`training_load_service.dart`); die wöchentliche Prüfung läuft nur auf der Plan-Seite (auch beim Öffnen von „Heute“ auslösen); Vorschlag nach PAR-140 fehlt (`walk_run_units.dart`); Ruhetag nach „Neu berechnen“ bei Auslöser `manual` prüfen (`recalculate_plan.dart`). `planMethodVersion` 3 → 4.
- **Teile:** A Anpassung in `core` (PAR-200 bis -202, PAR-140, Eigenschaftstest, Ruhetag-Fehler); B Warnsignal-Daten (Schema 10, Abschnitt 21, Migration, Archiv, Löschen, Vektor, Port, Dienst, Vorrang in `core`); C Plan-Seite (melden, aufheben, Nachfrage, Pausenfrage, Verlauf); D Hinweise und „Heute“ (PAR-174 bis -184, Belastungsdienst, Karten „Erholung“ und „Plan angepasst“, Erklärungen FR-0179 bis -0181, Einstieg auf „Fortschritt“). A und B zuerst, dann C und D.
- **Einstiege:** siehe Abschnitt 7 des Berichts; die Antwort „ja“ in der Zusammenfassung (WP18) setzt das Warnsignal über den Dienst.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0039, FR-0105 bis FR-0107, FR-0156 bis FR-0170, FR-0179 bis FR-0181 und FR-0203.
- [ ] Die Karte „Erholung“ zeigt nie Zahl oder Zustand (Test), und kein Text formuliert einen festgestellten Erholungszustand.
- [ ] Jede Erklärung im Test wird aus den Eingangsdaten belegt; keine Erklärung ohne Daten.
- [ ] E2E auf API 36 und 31, hell und dunkel: ausgefallene Woche, Warnsignal setzen und aufheben, Nachfrage; Bildschirmfotos. Gate grün.
