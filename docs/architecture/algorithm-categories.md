# Verfahrenskategorien

Jedes Berechnungsverfahren der App ist genau einer Kategorie aus NFR-0002 zugeordnet (A etabliert, B Heuristik, C individuell kalibriert). Im Code steht die Kategorie an der Variante (`AlgorithmVariant.category`, [ADR-0004](adr/ADR-0004-algorithmen-rohdaten-versionierung.md)); die Registry der Standardbestückung liefert `AlgorithmRegistry.standard()`. Neue Verfahren tragen sich hier ein.

| Verfahren | Kennung | Kategorie | Begründung | Paket |
|---|---|---|---|---|
| Edwards-TRIMP | `edwards-trimp` v1 | A | Etabliertes Verfahren, in NFR-0002 als „TRIMP“ genannt (FR-0092). | WP04 |
| Herzfrequenzreserve | `heart-rate-reserve` v1 | A | In NFR-0002 ausdrücklich genannt (FR-0060). | WP04 |
| Reservezonen | `reserve-zones` v1 | B | Die Formel der Reserve ist etabliert, die Zonengrenzen sind aber frei wählbare Startwerte (FR-0062). NFR-0002 nennt die Zonen nicht eindeutig; **offener Punkt:** Bestätigung der Einordnung (die individuellen Trainingszonen in Kategorie C sind etwas anderes). | WP04 |
| Positionsfilter | `position-filter` v1 | B | Eigene Schwellen für Genauigkeit und Sprünge (PAR-001 bis PAR-004), Teil der Qualitätsbewertung. | WP03 |
| Tempo | `pace` v1 | B | Eigene Glättung (PAR-005). | WP03 |
| Bewegungszeit | `movement-time` v1 | B | Eigene Schwellen für Stillstand und Fortsetzen (PAR-014, PAR-015). | WP03 |
| Herzfrequenzfilter | `heart-rate-filter` v1 | B | Eigene Plausibilitäts-, Ausreißer- und Lückenregeln (PAR-007 bis PAR-010). | WP03 |
| Einschwingzeit | `settling` v1 | B | Eigene Regel ohne Quelle (PAR-011). | WP03 |
| Höhenfilter | `altitude-filter` v1 | B | Eigene Schwellen (PAR-012, PAR-013). | WP03 |
| Schrittreihe | `steps-series` v1 | B | Eigene Aufbereitung der Rohwerte. | WP03 |
| Abschnittsqualität | `section-quality` v1 | B | „Qualitätsbewertung“ ist in NFR-0002 Kategorie B (FR-0048). | WP03 |
