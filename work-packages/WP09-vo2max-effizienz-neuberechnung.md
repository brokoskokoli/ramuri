# WP09 – VO₂max, aerobe Effizienz und Neuberechnung (`app/packages/core/lib/src/fitness`, `app/packages/core/lib/src/recalculation`, `app/packages/adapters`, `app/lib/features/settings`)

**Zuordnung:** M1.

Bezug: FR-0006, FR-0058, FR-0066, FR-0068 bis FR-0071, FR-0073 bis FR-0080, FR-0085 bis FR-0087, SEC-0006; PAR-006, PAR-010, PAR-011, PAR-018, PAR-019, PAR-020 bis PAR-047; ADR-0004 Punkte 3 bis 5; OQ-0001, OQ-0012, OQ-0019, OQ-0031, OQ-0036, OQ-0059; Referenzwerte in `docs/quality/testing.md`.

## Inhalt
1. **Abschnittsauswahl:** Eignungsregeln nach FR-0073 und PAR-020 bis PAR-031, Aufteilung nach PAR-021, Grenzen der Laufformel und Gehen (FR-0070, FR-0074).
2. **Schätzer:** Sauerstoffbedarf und Hochrechnung nach FR-0069 und FR-0071, Steigung nach PAR-026, PAR-027, Verwerfen nach PAR-032, Gewichtung und Gesamtwert nach PAR-033 (FR-0076), als austauschbare Variante aus WP04.
3. **Stufen und Langzeitwert:** Streuung und Laufstufe nach PAR-036 bis PAR-040 (FR-0077), Glättung nach PAR-034, PAR-035 (FR-0078, FR-0079), keine Aktualisierung bei „nicht bestimmbar“ (FR-0080), Langzeitstufe nach PAR-041 bis PAR-043.
4. **Aerobe Effizienz:** Abschnitte nach PAR-044, PAR-045 (FR-0085, FR-0086), Fenster und Formel nach FR-0087, Mengen und Stufe nach PAR-046, PAR-047.
5. **Speichern nach dem Lauf:** Ergebnisse als `original` und `current` mit allen Angaben aus FR-0053 und bewerteten Abschnitten.
6. **Neuberechnung:** Dienst nach ADR-0004 Punkt 5: Angebot nach einer Änderung (FR-0006), Start erst nach Bestätigung, Zwischenstand und Tausch in einer Transaktion, ursprüngliche Werte bleiben (FR-0058, OQ-0031). Dialog in den Einstellungen.

## Umsetzung
- Aus WP05: Wer Zonenzeiten speichert oder neu berechnet, nutzt `ReserveZoneSettings.loadParameters` statt `v3()` und hält die verwendeten Grenzen am Ergebnis fest; die Parameterversion bleibt 3. Sonst wirken angepasste Zonen still nicht (FR-0061) oder alte Läufe werden umgerechnet (gegen OQ-0065). Das Schema speichert noch keine Zonenzeiten. TRIMP-Verfügbarkeit nur über `EdwardsTrimp.basisUnavailableReason`.
- Aus WP02: Neuberechnung über `createOriginals` und `swapCurrent`. Die Verknüpfung von Wert und Abschnitt (FR-0073) fehlt im Schema; das braucht eventuell Schema-Version 2. Löschen eines Laufs entfernt überlappende Tageswerte und solche ohne Datenzeitraum, WP09 rechnet neu.
- Aus WP04 (K11): Die Verfahren aus WP03 tragen ihre Kategorie nur in `docs/architecture/algorithm-categories.md`. Dieses Paket zieht sie im Code nach (ADR-0004 Punkt 3). Die Stufenvergabe PAR-036 bis PAR-043 liegt hier, WP04 liefert nur das Modell.
- **Teile für die Coder-Aufträge:** Teil A: Punkt 1 / Teil B: Punkte 2 und 3 / Teil C: Punkt 4 / Teil D: Punkte 5 und 6, je ein Auftrag ohne Übergabe, in dieser Reihenfolge.
- Startwerte kommen aus dem Parametersatz mit Version (FR-0075); FR-0075 gilt als erfüllt, wenn kein Grenzwert außerhalb des Satzes steht.
- Berechnungen ohne Netzwerk (SEC-0006). Keine Zeitabhängigkeit außer über die Uhr-Schnittstelle.
- Anzeige und Kennzeichnung als Schätzung (FR-0067, FR-0072, FR-0081, FR-0084, FR-0088) liegen in WP10.
- Nicht dazu: Drift (Phase 4), Kalibrierung (FR-0082), Laufbandmodus (Phase 2).
- Parallel: läuft mit WP06. Dateien siehe WP06.

## Abnahmekriterien
- [ ] Referenzwerte aus `docs/quality/testing.md` für Sauerstoffbedarf, VO₂max und aerobe Effizienz als feste Tests.
- [ ] FR-0066: Aus einem geeigneten synthetischen Lauf entsteht ohne Maximaltest ein Wert. FR-0068: Fehlt ein benötigter Wert, kein Wert und sichtbarer Grund (OQ-0012, PAR-018, PAR-019).
- [ ] FR-0073: Für jede Regel ein Abschnitt, der genau sie verletzt und nicht bevorzugt wird. PAR-020 bis PAR-031: je Grenzwert knapp innerhalb und außerhalb; `vorläufig` bei PAR-031; kein Wert unterhalb.
- [ ] FR-0070, FR-0074: Starkes Gefälle, sehr langsames Laufen und reines Gehen liefern keine ungekennzeichnete Schätzung.
- [ ] FR-0076: Ein unplausibler Abschnitt verschiebt den Gesamtwert nicht ungefiltert; jeder Laufwert trägt eine Stufe. FR-0077: Testfall der Spec mit gleichem Mittel und Trend.
- [ ] PAR-036 bis PAR-043: Stufen mit Grenzfällen, einschließlich der Obergrenzen aus PAR-038 und des Vorrangs von PAR-041.
- [ ] FR-0078, FR-0079: Ein Ausreißerlauf ändert den Langzeitwert weniger als den Laufwert; α nach PAR-034; Neustart nach PAR-035. FR-0080: „nicht bestimmbar“ lässt ihn unverändert. Mutationsbelege.
- [ ] FR-0085 bis FR-0087: Abschnitte außerhalb des Bereichs fließen nicht ein, Median und Fenster nach OQ-0036, zu wenig Daten nach PAR-046 ergibt „nicht bestimmbar“.
- [ ] FR-0058, FR-0006: Nach der Neuberechnung sind ursprünglicher und aktueller Wert und ursprüngliche Qualität abrufbar; Rohdaten unverändert; ohne Bestätigung ändert sich nichts; Abbruch mitten in der Neuberechnung lässt den alten Stand einheitlich (Test mit Fehlerinjektion).
- [ ] Jeder Wert trägt die sieben Angaben aus FR-0053 (Test über alle erzeugten Werte).
- [ ] SEC-0006: Tests laufen ohne Netzwerkzugriff; `core` hat keine Netzwerkabhängigkeit.
- [ ] E2E (separater Agent): Basiswert ändern, Angebot ablehnen und annehmen, mit synthetisch vorbefüllter Datenbank (kein Bezug auf echte Daten).
- [ ] Doku/Spezifikation nachgezogen (Änderungsprotokoll-Eintrag durch den Orchestrator). Gate grün.

## Ungeprüft
Modellgüte und Startwerte gegen echte Läufe (NFR-0004, OQ-0020); Dauer einer Neuberechnung über viele echte Läufe auf einem schwachen Telefon (ADR-0004).
