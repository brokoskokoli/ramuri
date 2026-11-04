# R001 Nachbesserung: Modellparameter

Bezug: [R001-model-parameters.md](R001-model-parameters.md), Ziel: [model-parameters.md](../../model-parameters.md). Quellen geprüft am 2026-11-04.

**Ergebnis:** Von 25 Befunden sind 17 vom Typ `Beleg/Text`. 16 sind umgesetzt, davon 6 mit Abweichung vom Bericht, weil die Quelle etwas anderes sagt (M1, M2, M3, S2, S6, S10), und S14 über die Alternative des Berichts, weil die Streichung den `Startwert` berührt hätte. S15 ist teilweise umgesetzt. Die 8 Befunde vom Typ `Wert` sind auftragsgemäß nicht umgesetzt. Kein Befund war als Ganzes falsch; einzelne Aussagen in den genannten Befunden hielten der Prüfung nicht stand.

Die Spalten `Parameter`, `Startwert` und `Anforderung` sind per Skript gegen die Ausgangsfassung verglichen: unverändert in allen 48 Zeilen. Die Art ist nun 1 `belegt (Sekundärquellen)`, 6 `abgeleitet`, 41 `Heuristik`.

## Beleg/Text

| Befund | Ergebnis | Umsetzung und Prüfung |
|---|---|---|
| M1 | Umgesetzt, mit Abweichung | PAR-032 nennt 29,2, 32,2, 35,0, 40,4 und 44,7; alle nachgerechnet. Neue Zeile im Validierungsbedarf. FRIEND-Werte stimmen. **Abweichung:** Die 46,8 und 43,8 aus Dugas sind adjustierte Mittel. Das Dokument nennt das Rohmittel 47,4 und das Minimum 34,8, das zeigt zugleich, dass die Studie die Untergrenze nicht abdeckt. Die verlangte Bestätigung durch den Maintainer liegt inzwischen vor (OQ-0059) und ist in PAR-032 genannt. |
| M2 | Umgesetzt, mit Abweichung | Evidenzabschnitt und Validierungsbedarf neu gefasst; Dugas, Hall, Swain und Leutholtz, Parak und Helm ergänzt, Zahlen im Volltext oder Abstract bestätigt. Liste „nicht abrufbar“ bereinigt. **Abweichung:** Dugas extrapoliert per Regression über drei Stufen, nicht über `r`, und nutzt die Fox-Formel; das steht nun dabei, damit die Studie nicht als Prüfung genau dieses Schätzers gilt. Hall steht nicht als „Gegenrichtung“: Der Abstract nennt −20 kJ, erklärt das Vorzeichen aber nicht, belegt ist nur „nahe am Messwert“. |
| M3 | Umgesetzt, mit Abweichung | PAR-012 auf `Heuristik`, Wortlaute aufgenommen, Zeile im Validierungsbedarf. **Abweichung:** Runalyze sagt nicht ausdrücklich, dass die 3 m für Geländemodell oder Barometer gelten; das Dokument schreibt das so. Das Zitat „all devices had considerable errors“ steht nicht in Q25 (dort: „All devices presented considerable elevation gain measuring errors“), daher nur sinngemäß. Die Schlussfolgerung des Befunds bleibt richtig. |
| M5 | Umgesetzt | PAR-028 auf `Heuristik`, Modell und Wortlaut genannt. Bestätigt: Forerunner 570, Forerunner 945, Q2, Rechnung 0,43 und 0,63. Modell auch in PAR-020. |
| M6 | Umgesetzt | PAR-009, PAR-023, PAR-032, PAR-038 auf `Heuristik`. Mit M3 und M5 sinkt `abgeleitet` von 12 auf 6. |
| S1 | Umgesetzt | Q16 im Volltext bestätigt: ±0,25 m/s, Aufwärmen und Ruhe, Trend entfernt, Modell ohne Totzeit. 11 %, 3,7 bpm und 2,6 bpm nachgerechnet; die beiden letzten gelten für einen 5-min-Abschnitt, das steht nun dabei. |
| S2 | Umgesetzt, mit Abweichung | Nes, 2,3 SEE, 6,6 bpm und die 514 Personen ergänzt. **Abweichung:** Der Bericht schreibt, der Unterschied senke die Schätzung. Eine höhere HFmax senkt `r` und hebt die Schätzung (51,6 auf 54,1). Das Dokument sagt daher: Trifft Nes zu, liegt die Schätzung mit Tanaka rund 5 % zu niedrig. Der Abstract nennt die geprüften früheren Formeln nicht; Tanaka ist darin also nicht ausdrücklich genannt. |
| S3 | Umgesetzt | Coyle, Herkunft von 0,648 und die Spanne 7 bis 9 % ergänzt, nachgerechnet. Q7 nennt im Abstract keinen Zeitbezug für die 8 %; das Dokument schreibt das so. |
| S4 | Umgesetzt | Teil II und Coyle 1984 ergänzt, Abstracts bestätigt. „Gestützt auf [Q32]“ in PAR-041 ersetzt. |
| S5 | Umgesetzt | Q4, Q21 (7,90–8,02 km/h) und FR-0202 bestätigt. PAR-030, PAR-031 und PAR-044 ergänzt, Schrittfrequenz nur als Prüfgröße im Validierungsbedarf. OQ-0019 unberührt. Die Übereinstimmung des Übergangs mit 134 m/min steht als Einordnung im Dokument, nicht als Beleg. |
| S6 | Umgesetzt, mit Abweichung | Ranacher, Witte und Wilson, Android-Geschwindigkeit ergänzt, Tempovergleich im Validierungsbedarf. **Abweichung:** „Benson et al. 2016“ heißt richtig Gordon, Bruce und Benson 2016. Die Referenz ist dort ein Sport-GPS, kein wahrer Wert. Zusätzlich aufgenommen: Parak (Strecke −5 %) und Pobiruchin. |
| S7 | Umgesetzt | Q10-Tabelle bestätigt 7,42–12,99 m RMSE je Periode. Q11 bestätigt, 8,4 m gilt für das Referenzgerät S22. PAR-001, PAR-025, PAR-033 korrigiert. |
| S8 | Umgesetzt | Dugas-Wortlaut bestätigt, in PAR-023 und PAR-029 ergänzt. Q33 und Q34 bleiben als gekennzeichnete Zusatzquellen. |
| S9 | Umgesetzt | „Up to“ bestätigt, Tabelle nachgerechnet, in PAR-034 und im Validierungsbedarf ergänzt. |
| S10 | Umgesetzt, mit Abweichung | Zusatz gestrichen, Zweck genannt. **Abweichung:** „Keine Mindestdauer für eine Messung“ ist etwas zu stark, die Quelle spricht auch von „assessing aerobic durability“. Daher: „vor allem Einheiten der Grundlagenphase, keine untere Grenze für eine Messung“. |
| S14 | Umgesetzt, ohne Streichung | Die Bedingung steht im `Startwert` und bleibt deshalb. Umgesetzt ist die Alternative des Berichts: PAR-038 und PAR-039 nennen in der Begründung, dass sie nicht eigenständig wirkt. |
| S15 | Teilweise umgesetzt | Q19 und der Zusatz `belegt (Sekundärquellen)` umgesetzt; der Zusatz ist in der Lesehilfe erklärt. **Nicht umgesetzt:** „Q3 prüft nicht nur bei Herzpatienten“. Die 54 Gesunden dienen dem neuen Modell; die ACSM-Gehformel wird laut Volltext nur in der Patientengruppe berechnet. Die alte Aussage war richtig. Die Quellenangabe nennt nun beide Gruppen und ihren Zweck. |

## Wert

Nicht umgesetzt, weil der Auftrag den `Startwert` ausnimmt. OQ-0059 nennt für diese Vorschläge eine Teilentscheidung, die „noch einzutragen“ ist.

| Befund | Ergebnis | Grund |
|---|---|---|
| M4 | Nicht umgesetzt | Typ `Wert`. Evidenzteil zur Höhe steht unter M3. |
| M7 | Nicht umgesetzt | Typ `Wert`. |
| M8 | Nicht umgesetzt | Typ `Wert`. |
| M9 | Nicht umgesetzt | Typ `Wert`. |
| M10 | Nicht umgesetzt | Typ `Wert`. |
| S11 | Nicht umgesetzt | Typ `Wert`. |
| S12 | Nicht umgesetzt | Typ `Wert`. |
| S13 | Nicht umgesetzt | Typ `Wert`. |

## Für den Maintainer

Keine dieser Fragen ist im Dokument entschieden; alle Werte stehen unverändert.

- **S14:** Die Summenbedingung aus dem `Startwert` von PAR-038 und PAR-039 streichen? Ohne Wirkung auf das Ergebnis.
- **M2, PAR-082:** Die Bandbreite ±6 % ist enger als der in Dugas gefundene Fehler (rund 11 % MAPE). Die Zeile steht in `planning-rules.md` und liegt außerhalb dieses Auftrags.
- **S8, PAR-029:** `r` ≤ 0,85 ist weiter als die 70 % HRR der Protokolle. Als Heuristik zulässig.
- **S2, FR-0004:** Trifft Nes zu, liegt die Altersformel ab mittlerem Alter zu niedrig. Die Formel legt FR-0004 fest.
- **Version:** Es bleibt Version 1, weil sich kein Wert geändert hat. Der Statuskopf nennt den Stand der Belege und Einstufungen getrennt.

## Grenzen der Prüfung

- Abstract-Quellen sind in der Quellenliste gekennzeichnet. PubMed-Einträge wurden über Europe PMC gelesen. Q39, Q43, Q44 und Q52 sowie die übrigen Webseiten liefen über einen Webabruf mit Auszügen, nicht als Rohtext.
- Weiterhin nicht geprüft: ACSM-Leitlinie im Original, IAAF-Bericht hinter Q20. Für Ranacher [Q49] wurde nur der Abstract gelesen.
- Nur im Rahmen von R001 und nicht erneut abgerufen, weil ihr Text unverändert bleibt oder kein Befund sie betrifft: unter anderem Q6, Q12, Q13, Q20, Q22, Q26 bis Q29, Q31.
