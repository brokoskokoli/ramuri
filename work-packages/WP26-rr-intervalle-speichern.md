# WP26 – RR-Intervalle speichern (`core/sensors`, `core/recording`, Speicher, Archiv)

**Zuordnung:** M2, Welle 2b, nachgereicht am 2026-11-09 (DEC-0072). Nach WP20, vor WP24.

Bezug: FR-0213, FR-0021, FR-0019, FR-0020, SEC-0001 bis SEC-0010; ADR-0004, ADR-0005, ADR-0006 (Nachtrag); K44. Allgemeine Regeln: [M2-PLAN.md](M2-PLAN.md).

## Inhalt
1. **Parser (Teil A):** `heart_rate_parser.dart` liest die RR-Felder der Heart Rate Measurement (`0x2A37`, Flag-Bit 4, je 16 bit in 1/1024 s), auch mehrere je Paket und zusammen mit dem Feld „Energy Expended“. Ein kaputtes RR-Feld verwirft nie den Pulswert. Tests mit Paketen aus der Bluetooth-Spezifikation und Grenzfällen (0 Werte, ungerade Länge, 8-bit- und 16-bit-Puls).
2. **Aufzeichnung und Speicher (Teil B):** RR-Werte je Lauf als kompakte Reihe (etwa ein Block je Abschnitt), mit Quellgerät und Empfangszeitpunkt des Pakets. Bei Sensorwechsel bleibt die Herkunft getrennt (FR-0020). Absturz und Wiederanlauf verlieren höchstens den letzten Puffer, wie beim Puls (ADR-0005). Verschlüsselt, Migration mit Test.
3. **Archiv, Reimport, Löschen (Teil C):** Neuer Abschnitt im Archiv nach `docs/contracts/archive.md`, ältere Formate bleiben lesbar. Löschen eines Laufs und Gesamtlöschung entfernen die Reihe.

## Umsetzung
- Keine Auswertung und keine Anzeige von HRV, DFA α1 oder ähnlichem. Höchstens ein interner Zähler für Tests.
- Speicherbedarf messen und in der Fertigmeldung nennen (Ziel: 2 h Lauf bei 180 bpm deutlich unter 1 MB).
- Nie RR-Werte in Logs, Fehlermeldungen oder Testausgaben mit echten Daten (SEC); Testdaten synthetisch.
- Aufzeichnungsdienst nach ADR-0005: Die RR-Werte laufen auf demselben Weg wie der Puls; der Kern des Dienstes bleibt unverändert. Muss er geändert werden, vorher beim Orchestrator melden.
- Virtueller Sensor im Emulator (aus WP07/R006, falls vorhanden) sendet für den E2E auch RR-Werte; sonst Test auf Ebene der Adapter.
- Teile je ein Coder-Auftrag. Mutationsbelege für das Flag-Bit, die Längenprüfung, die Herkunft bei Sensorwechsel und das Löschen.
- **Parallel:** Schema und Archivabschnitt nach den zuvor gemergten Paketen (WP19, WP20, ggf. WP21); ich melde den Stand.

## Abnahmekriterien
- [ ] Akzeptanzkriterien von FR-0213.
- [ ] Ein Sensor ohne RR-Felder ändert weder Puls noch Aufzeichnung (Test gegen den alten Stand).
- [ ] RR-Reihe übersteht Archiv und Reimport bitgenau und verschwindet beim Löschen (Test).
- [ ] E2E auf API 36 und 31: Lauf mit virtuellem Sensor mit und ohne RR, Sensorwechsel, Wiederanlauf. Gate grün.

## Ungeprüft
Datenqualität des echten Polar H9 (Artefakte, Lücken) – erst mit Läufen des Maintainers.
