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

## Vorprüfung und Entscheidungen (2026-11-11)
Bericht: `../running-app-wt/handoff/vorpruefung-wp25.md`; Entscheidungen des Maintainers: K57. Wo der Bericht „Empfehlung“ sagt, ist sie entschieden.
- **Schema und Archiv:** Schema 10 (`runs.mode`, Tabelle für Bandgeschwindigkeit und Steigung), Archivabschnitt 26. Läuft parallel zu WP23, das ebenfalls Schema 10 braucht: Wer später mergt, zieht auf 11 nach.
- **Dienst:** Nachtrag zu ADR-0005 (Typ `health` nur im Laufbandmodus) im Paket schreiben; Gate-Prüfung der Release-Rechte entsprechend erweitern, nicht abschwächen. E2E muss auf API 36 laufen (Diensttypen erst ab API 34 geprüft).
- **GPX:** Abweichend von Punkt 2 oben gilt FR-0196: kein GPX für Laufbandläufe, Grund im Exportfenster.
- **Eigener Port** für die Bandeinstellung; `LocationSource` setzt Breite und Länge voraus und trägt nicht.
- **Teile:** A Schema, Port, Aufzeichnung, Dienst (Diensttyp zuerst); B Oberfläche „Lauf vorbereiten“ und Live-Ansicht; C Export und Auswertung (GPX gesperrt, VO₂max-Schalter `treadmill`, Ausschlüsse); D Zusatzmetriken-CSV (eigener Auftrag, ohne Schema).
- **Einstiege:** Laufbandwahl, Startgeschwindigkeit, Steigung auf „Lauf vorbereiten“ (`run_flow_screen.dart`); Knöpfe in `live_run_view.dart`; Export über `RunExportAction`; CSV unter „Daten“.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0184 und FR-0196.
- [ ] Laufband ohne Standortberechtigung im Emulator; Wechsel der Geschwindigkeit wirkt nur ab dem Zeitpunkt der Änderung (Test).
- [ ] Wiederanlauf nach einem erzwungenen Beenden (E2E).
- [ ] Exporte in allen Formaten geprüft; Zusatzmetriken-Datei gegen die Beschreibung getestet.
- [ ] E2E auf API 36 und 31, hell und dunkel; Bildschirmfotos. Gate grün.
