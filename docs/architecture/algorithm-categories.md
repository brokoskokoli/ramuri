# Verfahrenskategorien

Jedes Berechnungsverfahren der App ist genau einer Kategorie aus NFR-0002 zugeordnet (A etabliert, B Heuristik, C individuell kalibriert). Im Code steht die Kategorie an der Variante (`AlgorithmVariant.category`, [ADR-0004](adr/ADR-0004-algorithmen-rohdaten-versionierung.md)) nur für die Verfahren aus WP04; sie laufen über die Registry der Standardbestückung `AlgorithmRegistry.standard()`, ein Test gleicht sie mit dieser Tabelle ab. WP03-Verfahren und die Abschnittsauswahl tragen die Kategorie als Konstante `<x>Category`; `review_nb3_test` gleicht sie ab. Neue Verfahren tragen sich hier ein.

| Verfahren | Kennung | Kategorie | Begründung | Paket |
|---|---|---|---|---|
| Edwards-TRIMP | `edwards-trimp` v1 | A | Etabliertes Verfahren, in NFR-0002 als „TRIMP“ genannt (FR-0092). | WP04 |
| Banister-TRIMP männlich | `banister-trimp-male` v1 | A | Banister/Morton/Fitz-Clarke 1992 (K43), k nur sekundär belegt (Banister 1991); FR-0197. | WP19 |
| Banister-TRIMP weiblich | `banister-trimp-female` v1 | A | wie männlich mit k 0,86 und b 1,67 (K43); FR-0197. | WP19 |
| Herzfrequenzreserve | `heart-rate-reserve` v1 | A | In NFR-0002 ausdrücklich genannt (FR-0060). | WP04 |
| Reservezonen | `reserve-zones` v1 | B | Die Formel der Reserve ist etabliert, die Zonengrenzen sind aber frei wählbare Startwerte (FR-0062). NFR-0002 nennt die Zonen nicht eindeutig; Kategorie B bestätigt durch den Maintainer (2026-11-05); die individuellen Trainingszonen in Kategorie C sind etwas anderes. | WP04 |
| Positionsfilter | `position-filter` v2 | B | Eigene Schwellen für Genauigkeit und Sprünge (PAR-001 bis PAR-004), Teil der Qualitätsbewertung. | WP03 |
| Tempo | `pace` v1 | B | Eigene Glättung (PAR-005). | WP03 |
| Bewegungszeit | `movement-time` v1 | B | Eigene Schwellen für Stillstand und Fortsetzen (PAR-014, PAR-015). | WP03 |
| Herzfrequenzfilter | `heart-rate-filter` v1 | B | Eigene Plausibilitäts-, Ausreißer- und Lückenregeln (PAR-007 bis PAR-010). | WP03 |
| Einschwingzeit | `settling` v1 | B | Eigene Regel ohne Quelle (PAR-011). | WP03 |
| Höhenfilter | `altitude-filter` v1 | B | Eigene Schwellen (PAR-012, PAR-013). | WP03 |
| Schrittreihe | `steps-series` v1 | B | Eigene Aufbereitung der Rohwerte. | WP03 |
| Abschnittsqualität | `section-quality` v2 | B | „Qualitätsbewertung“ ist in NFR-0002 Kategorie B (FR-0048). | WP03 |
| VO₂max-Abschnittsauswahl | `vo2max-section-selection` v1 | B | Alle Grenzen (PAR-020 bis PAR-031) sind Heuristik ohne Quelle; die Auswahl ist eine Qualitätsbewertung (NFR-0002, FR-0048). | WP09 |
| VO₂max-Schätzer | `vo2max-acsm-hrr` v1 | B | ACSM-Laufformel und Hochrechnung über die Reserve sind etabliert (FR-0069, FR-0071), Plausibilität, Gewichtung, gewichteter Median und Stufen sind eigene Wahl (PAR-032, PAR-033, PAR-036 bis PAR-040). | WP09 |
| VO₂max-Langzeitwert | `vo2max-long-term-ema` v1 | B | Glättungsformel aus FR-0079 (Ursprungskonzept), α, Neustart und Stufen sind eigene Wahl ohne Quelle (PAR-034, PAR-035, PAR-041 bis PAR-043). | WP09 |
| Aerobe Effizienz | `aerobic-efficiency-median` v1 | B | Der Median ist etabliert, Belastungsbereich, Steigungsgrenze, Mindestmengen und Stufen sind eigene Wahl (OQ-0036, PAR-044 bis PAR-047). | WP09 |
| Kamera-PPG | `camera-ppg` v1 | B | Port der Heuristik `PpgAnalyzer.kt` (Tag `algo-v0.4-frozen`) mit eigenen Schwellen und Qualitätsbewertung (PAR-160K); am EKG-Gurt geprüft, nicht klinisch belegt (ADR-0011, R009). | WP27 |
| Leistungsprognose | `riegel-prediction` v1 | B | Das Riegel-Modell ist etabliert (FR-0130, OQ-0008), Stufen, Grenzen und Vorschlagsregel sind eigene Wahl (PAR-143 bis PAR-146, PAR-185). | WP20 |
| Wochenzeit und Einheiten des Plans | `weekly-time-course` v5 | B | Steigerung, leichtere Woche, Halten, Reduktion und gedämpfte Steigerung sind einfache, gesetzte Regeln ohne Beleg (PAR-193, PAR-194, PAR-196, PAR-199, ab v4 auch PAR-200 bis PAR-202; v5: automatische Auslöser geben die gehaltenen Tage an die Rechnung, die Wochenzeit bleibt nach bestätigter Verschiebung und absolviertem Lauf erhalten). Die Einheiten je Woche (langer Lauf, gleichmäßiger Rest, harte Einheit im Wechsel, Abstand) folgen im selben Verfahren (PAR-195, PAR-197, PAR-198, PAR-059). | WP21 |
| Zielintensität des Plans | `target-intensity` v2 | B | Rangfolge Referenz (Riegel), VO₂max, Herzfrequenzzonen, RPE und die Zuordnung je Trainingstyp sind gesetzte Regeln mit niedriger Evidenz (PAR-100 bis PAR-103, PAR-109 bis PAR-114, PAR-190). v2: RPE je Abschnitt der Geh-Lauf-Einheit (PAR-115, PAR-119, K63, WP24). | WP21 |
| Geh-Lauf-Abfolge | `walk-run-program` v1 | B | Zeiten je Programmwoche als austauschbarer Datensatz (PAR-065, PAR-132 bis PAR-139), Evidenz niedrig; Ausnahmen bei weniger Tagen oder kurzer Zeit sind eigene Wahl (PAR-140, PAR-141). | WP21 |
