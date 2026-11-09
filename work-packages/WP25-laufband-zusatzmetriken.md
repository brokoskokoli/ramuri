# WP25 – Laufband und Zusatzmetriken (`core`, `app/lib/features/run`, `export`)

**Zuordnung:** M2, Welle 3. Parallel zu WP22.

Bezug: FR-0184, FR-0195, FR-0196; ADR-0005; OQ-0032, OQ-0042. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **Laufbandmodus (Teil A und B, FR-0196):** Auswahl beim Lauf vorbereiten. Bandgeschwindigkeit im Lauf einstellbar, Steigung optional. Strecke aus Geschwindigkeit mal Zeit, keine Standortberechtigung. VO₂max höchstens „vorläufig“, Belastung und Statistik zählen normal. Karte, Route und Höhe entfallen in Zusammenfassung, Detail und Verlauf sauber.
2. **Export bei Laufband (Teil B):** GPX, TCX und FIT ohne Positionsdaten nach Möglichkeit der Formate; was ein Format nicht hergibt, klar melden. Archiv und Reimport enthalten die Einstellungen.
3. **Zusatzmetriken (Teil C, FR-0184):** Selbst berechnete Werte wie VO₂max als dokumentierte CSV-Datei mit Formatversion, beschrieben in `docs/contracts/` (Vorschlag für den letzten offenen Punkt von OQ-0032). Über denselben Weg teilbar wie die anderen Exporte.

## Umsetzung
- Teile je ein Coder-Auftrag. Mutationsbelege für die Streckenrechnung, die VO₂max-Stufe und das Fehlen der Standortabfrage.
- Aufzeichnungsdienst nach ADR-0005: Neue Quelle hinter dem vorhandenen Port, der Weg für GPS bleibt unverändert. Wiederanlauf nach einem Absturz gilt auch hier.
- **Parallel:** `run_flow_screen.dart` nur hier, bis auf den Einstieg aus WP22. Texte mit Präfix `treadmill`/`metrics`.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0184 und FR-0196.
- [ ] Laufband ohne Standortberechtigung im Emulator; Wechsel der Geschwindigkeit wirkt nur ab dem Zeitpunkt der Änderung (Test).
- [ ] Wiederanlauf nach einem erzwungenen Beenden (E2E).
- [ ] Exporte in allen Formaten geprüft; Zusatzmetriken-Datei gegen die Beschreibung getestet.
- [ ] E2E auf API 36 und 31, hell und dunkel; Bildschirmfotos. Gate grün.
