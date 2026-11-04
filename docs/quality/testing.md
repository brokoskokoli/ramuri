# Tests und Abnahme

**Status:** Draft. Die Abnahmekriterien und Testfälle stammen aus der Quelle. Die Teststrategie ist eine Empfehlung, weil die Quelle dazu nichts festlegt. Es wurden noch keine Tests ausgeführt.

## Funktionale Abnahmekriterien

Aus SRC-001 §25. Das Konzept gilt in seinen jeweiligen Entwicklungsphasen als erfüllt, wenn mindestens diese Anforderungen nachweisbar sind. Die Phase ergibt sich aus den Anforderungen; die Quelle ordnet sie nicht direkt zu.

| ID | Kriterium | Quelle | Anforderungen |
|---|---|---|---|
| ACC-01 | Ein Nutzer kann einen Lauf vollständig ohne Pulssensor aufzeichnen. | Z. 1396 | FR-0035, CON-0004 |
| ACC-02 | Ein kompatibler Bluetooth-Pulssensor kann verbunden und während eines Laufs live ausgelesen werden. | Z. 1397 | FR-0007, FR-0012, FR-0015 |
| ACC-03 | Ein Verbindungsabbruch führt nicht zum Verlust des übrigen Laufs. | Z. 1398 | FR-0036, FR-0017 |
| ACC-04 | Die Trainingshistorie zeigt aufgezeichnete Läufe mit Strecke, Dauer, Pace und vorhandenen Herzfrequenzdaten. | Z. 1399 | FR-0040 |
| ACC-05 | Eine VO₂max-Schätzung wird nur aus dafür geeigneten Daten berechnet und als Schätzung gekennzeichnet. | Z. 1400 | FR-0067, FR-0073 |
| ACC-06 | Der Nutzer kann nachvollziehen, warum ein Fitnesswert berechnet oder nicht berechnet wurde. | Z. 1401 | FR-0059 |
| ACC-07 | Trainingsbelastung und langfristige Belastungstrends verwenden eine konsistente Berechnungsskala. | Z. 1402 | FR-0097 |
| ACC-08 | Ein Trainingsplan kann anhand eines Ziels und verfügbarer Trainingstage erstellt werden. | Z. 1403 | FR-0138 |
| ACC-09 | Der Plan reagiert auf zusätzliche oder ausgefallene Trainingseinheiten. | Z. 1404 | FR-0157, FR-0162 |
| ACC-10 | Größere Planänderungen werden begründet. | Z. 1405 | FR-0170 |
| ACC-11 | Eine Training-Readiness-Bewertung berücksichtigt fehlende Daten und persönliche Referenzwerte. | Z. 1406 | FR-0111, FR-0112 |
| ACC-12 | Eine Energiereserve wird nicht ohne geeignete kontinuierliche Daten als zuverlässiger aktueller Wert dargestellt (ab Phase 4, DEC-0060). | Z. 1407 | FR-0120, FR-0121 |
| ACC-13 | Ein Lauf kann unabhängig von Strava exportiert werden. | Z. 1408 | FR-0182 |
| ACC-14 | Die App bleibt ohne externe Fitnessplattform nutzbar. | Z. 1409 | CON-0010 |
| ACC-15 | Persönliche Daten können vom Nutzer exportiert und gelöscht werden. | Z. 1410 | SEC-0004, FR-0192 |

## Testfälle aus den Rechenbeispielen der Quelle

Die Migration hat diese Beispiele nachgerechnet; sie stimmen mit der Quelle überein. Sie eignen sich als Referenzwerte für künftige Tests.

| Berechnung | Eingabe | Erwartung | Anforderung |
|---|---|---|---|
| Relative Auslastung | HFmax 190, HFRuhe 60, HF 151 | r = 0,70 | FR-0060 |
| Sauerstoffbedarf | 10 km/h, eben | 36,83 ml/kg/min | FR-0069 |
| VO₂max | 10 km/h, HF 150, HFmax 190, HFRuhe 60 | r = 0,6923; ≈ 51,6 ml/kg/min | FR-0071 |
| Aerobe Effizienz | 9,0 auf 9,5 km/h | 5,56 % | FR-0087 |
| TRIMP | 10 min Z1, 30 min Z2, 10 min Z4 | 110 | FR-0092 |
| sRPE | 45 min, RPE 5 | 225 | FR-0095 |
| Riegel | 5 km in 25 min auf 10 km | ≈ 52 min 7 s | FR-0130 |

## Teststrategie (Empfehlung, nicht bindend)

- **Rechenmodelle:** Unit-Tests mit den Referenzwerten oben und Randfällen.
- **Vorverarbeitung und Modelle:** Wiedergabe aufgezeichneter oder synthetischer Läufe mit GPS-Sprüngen, Sensorlücken und Pausen.
- **Gerätefunktionen:** Tests auf echten Android-Geräten mit Sensor, ausgeschaltetem Bildschirm und Verbindungsabbruch.
- **Strava:** Tests gegen eine simulierte Gegenstelle einschließlich Fehlern und Duplikaten.
- **Datenschutz:** Negativtests ohne Einwilligung und nach einem Widerruf.
- **Modellqualität:** Validierung gegen Referenzdaten getrennt von Softwaretests (OQ-0020).

## CI-Gates

TBD: Es gibt noch keinen Code und keine Pipeline. Aktuell existiert nur die Dokumentationsprüfung aus [AGENTS.md](../../AGENTS.md).
