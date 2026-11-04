# WP04 – Algorithmen-Rahmen, Herzfrequenzzonen und TRIMP (`app/packages/core`)

**Zuordnung:** M1.

Bezug: NFR-0001, NFR-0002, NFR-0005, FR-0053, FR-0060, FR-0062, FR-0063, FR-0091, FR-0092, FR-0093; ADR-0004 Punkte 2 bis 5; PAR-018, PAR-019, PAR-036 bis PAR-043 (Stufenmodell); OQ-0012, OQ-0014, OQ-0040, OQ-0043, OQ-0051; Referenzwerte in `docs/quality/testing.md`.

## Inhalt
1. **Rahmen:** Interface je Algorithmenfamilie als reine Funktion, Registry für Familie und aktive Variante, Kennungen `method`, `methodVersion`, `parameterVersion`, Kategorie aus NFR-0002 an jeder Variante.
2. **Wertmodell:** Berechneter Wert mit den sieben Angaben aus FR-0053 (fortgeschrittene Werte) beziehungsweise Methode und Version (TRIMP, OQ-0040), den Qualitätsstufen und dem Grund bei „nicht bestimmbar“.
3. **Herzfrequenzreserve:** `r` nach FR-0060, Verhalten nach PAR-018 und PAR-019; fehlende Basiswerte ergeben „nicht verfügbar“ mit Grund, nie 0.
4. **Reservezonen:** Modell nach FR-0062 als Variante mit konfigurierbaren Grenzen (Eingabe als Parameter; die Oberfläche kommt mit WP05), Grenzregeln und Hinweis nach OQ-0014, Bereich unter Zone 1 gesondert (FR-0063).
5. **Edwards-TRIMP:** Nach FR-0092 und FR-0093 über Bewegungszeit aus WP03, Grenzregeln nach OQ-0014, Verhalten bei Pulslücken nach OQ-0051. Beim Ergebnis steht, ob es unvollständig oder der Lauf nicht bewertet ist.

## Umsetzung
- **Teile für die Coder-Aufträge:** Teil A: Punkte 1 und 2 / Teil B: Punkte 3 und 4 / Teil C: Punkt 5 mit Test zu NFR-0005, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Die Wahl des Belastungsmodells für den Nutzer ist Phase 2 (FR-0197). Hier nur die Austauschbarkeit.
- Dokumentation der Kategorie je Verfahren (NFR-0002): Tabelle in `docs/architecture/`, Datei benennt das Paket; spätere Pakete ergänzen.
- Nicht dazu: ATL und CTL, sRPE (Phase 2), Speicherung (WP09, WP10), Oberfläche.
- Parallel: läuft mit WP05. WP04 berührt nur `app/packages/core/lib/src/fitness/`; WP05 berührt `app/lib/features/profile`, `app/lib/features/settings`, `core` nur unter `src/profile/` und `src/consent/`. Der Teil Zoneneditor in WP05 wartet auf den Merge von WP04.

## Abnahmekriterien
- [ ] Referenzwerte aus `docs/quality/testing.md` für relative Auslastung und TRIMP als feste Tests je Variante.
- [ ] FR-0060: Fehlt Ruhepuls oder HFmax, ist `r` nicht verfügbar und nicht 0; HFmax ≤ HFRuhe nach PAR-018, kleine Reserve nach PAR-019.
- [ ] FR-0062: Testfälle der Spec einschließlich exakter Grenze und Werte oberhalb der obersten Zone mit Hinweis (OQ-0014). FR-0063: Zeit unter Zone 1 steht gesondert.
- [ ] FR-0092: Testfall der Spec; Gewicht 0 unter der Grenze, Grenzwert in der oberen Zone, Werte oberhalb in der obersten (OQ-0014); Bewegungszeit statt Gesamtzeit.
- [ ] OQ-0051: Lauf knapp über und knapp unter der Mindestabdeckung (unvollständig beziehungsweise nicht bewertet).
- [ ] FR-0093: Eine Änderung von Reservezonen oder Ruhepuls ändert den TRIMP nicht, außer nach PAR-018.
- [ ] FR-0091: Zu einem Lauf mit verwertbaren Daten liegt ein Belastungswert vor; ohne Puls gilt er als nicht bewertet und ist nicht 0.
- [ ] NFR-0005: Eine zusätzliche Fake-Variante läuft über die Registry, ohne Änderung an Aufzeichnung und Rohdatenschema; jeder Wert nennt seine Variante.
- [ ] NFR-0001, NFR-0002: Jede Variante trägt Methode, Version und Kategorie; ein Test schlägt fehl, wenn eine registrierte Variante das nicht tut.
- [ ] Mutationsbelege an Grenzregeln von Zonen und TRIMP.
- [ ] E2E: entfällt (reine Fachlogik); Anzeige prüfen WP06 und WP10.
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Modellgüte (NFR-0004, OQ-0020).
