# WP22 – Plan-Seite, Ziele und Kalender (`app/lib/features/plan`, `home`, `app_shell`)

**Zuordnung:** M2, Welle 3, nach WP21. Parallel zu WP25.

Bezug: FR-0135 bis FR-0155 (Rest aus WP21), FR-0171 bis FR-0178, FR-0208, FR-0209; OQ-0011, OQ-0077. Vorlagen: `design/screens/Plan.dc.html`, `Main.dc.html`. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **Navigation und Plan-Seite (Teil A, FR-0208):** Bereich „Plan“ an zweiter Stelle. Seite nach `Plan.dc.html`: Ziel, Phasenbalken mit Kurzformen (OQ-0077), Einschätzung nach PAR-206, Woche mit Einheiten. Wochenziel als Zeit, Kilometer nur als „ca.“. Leerer Zustand ohne Plan.
2. **Ziel und Plan anlegen (Teil B):** Nur Ziel, Stand, Lauftage, Regler (PAR-192), im Stil des Designs. Alles später änderbar (PAR-203), Schalter „harte Einheit“. Vor dem Geh-Lauf-Plan der Hinweis aus PAR-115. Einheit mit Beschreibung nach FR-0143 und Grundlage der Vorgabe.
3. **Heute (Teil C, FR-0209):** Geplante Einheit mit „Einheit starten“ und „Frei laufen“, Wochenziel. Der Start führt vorerst in den normalen Lauf; die Führung kommt mit WP24. Die Karte „Erholung“ kommt mit WP23.
4. **Kalender (Teil D, FR-0171 bis FR-0173, FR-0175 bis FR-0178):** Geplante und absolvierte Einheiten, Ansichten, Verschieben und Ersetzen, Ruhetage, Terminvorschläge, Prüfung beim Verschieben, Alternativen bei Konflikten. Termine ändern sich nur nach Bestätigung. Ein Lauf wird der Einheit zugeordnet.
5. **Erinnerungen (Teil E, FR-0174):** Optionale Trainingszeiten und lokale Erinnerung; Berechtigung erst beim Einschalten erfragen. Keine Inhalte aus Gesundheitsdaten im Benachrichtigungstext. Neue Abhängigkeit vorher beim Orchestrator anmelden.
6. **Aus WP20 (K50):** Wird eine Referenz gelöscht, die aus einem bestätigten Lauf stammt, schlägt die App diesen Lauf nicht mehr vor (wie eine Ablehnung, auch über Archiv und Reimport). Test mit Mutationsbeleg.
7. **Aus WP21:** Lese-Adapter, der `buildPlanInputs` aus dem Speicher befüllt (fehlt noch). Die Oberfläche übergibt `today` an `GoalStore.save` und `confirmMove`, ruft `recalculatePlan`, prüft `version.isCurrent` für die Regelversion und übergibt `easyPlannedRunIds`, `otherPlannedRunIds`, `rpeByRunId`. Anzeigen: Konflikte (`pinnedConflicts`), wegfallende Tage (`droppedDaysByWeek`), fehlende harte Einheit mit Grund (`hardOmission`, `hardFit` inkl. `partialAtPeak`), Geh-Lauf-Zustände (`walkRunStaysAtWeek`, `walkRunNoWeekFits`), Grundlage nach PAR-106 in de und en (englische Texte fehlen in der Spec: vorschlagen). Einzelheiten: `../running-app-wt/handoff/hinweise/wp21/`.

## Umsetzung
- Teile je ein Coder-Auftrag. Mutationsbelege für die Bestätigung vor Terminänderungen, die Prüfung beim Verschieben und die Zuordnung eines Laufs.
- Zeitraum und Scrollposition bleiben beim Tab-Wechsel erhalten (Muster aus `app_shell`).
- **Parallel:** Navigation und `home` nur hier. `run_flow_screen.dart` bis auf den Einstieg nicht (WP25). Texte mit Präfix `plan`/`calendar`.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0171 bis FR-0178 sowie alle aus WP21 offen gemeldeten.
- [ ] FR-0208 und FR-0209: vier Bereiche, Heute mit Plan und ohne Plan.
- [ ] Ohne Bestätigung ändert sich kein Termin (Widget-Test mit Mutationsbeleg).
- [ ] Erinnerung auf dem Emulator ausgelöst; ohne Berechtigung läuft die App normal.
- [ ] E2E auf API 36 und 31, hell und dunkel: Ziel anlegen, Woche ansehen, verschieben, Einsteigerplan; Bildschirmfotos neben dem Design. Gate grün.
