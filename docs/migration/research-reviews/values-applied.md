# Eintrag der Wertänderungen (Version 2)

Bezug: [R001](R001-model-parameters.md), [R002](R002-planning-rules.md), [R003](R003-phase-2-3-rules.md), [OQ-0059](../open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung). Geändert wurden nur [model-parameters.md](../../model-parameters.md), [planning-rules.md](../../planning-rules.md), [phase-2-3-rules.md](../../phase-2-3-rules.md) und diese Datei. Stand 2026-11-04. `spec_tool.py check` meldet PASS, `build` wurde nicht ausgeführt.

**Ergebnis:** Alle zehn Entscheidungen und alle Wahlen aus Punkt 11 sind eingetragen. Nicht umgesetzt sind einzelne Teile von Befunden, weil sie einer Entscheidung widersprechen oder gegenstandslos wurden (Abschnitt 3). Sechs Festlegungen gehen über den Wortlaut der Entscheidungen hinaus und brauchen eine Bestätigung (Abschnitt 7).

## 1. Entscheidungen 1 bis 9

| Punkt | Stand | Umsetzung und Grund |
|---|---|---|
| 1 PAR-052 | Umgesetzt | Erste Woche nach einer Entlastung höchstens die letzte Woche ohne Entlastung, auch ohne die +5 min. Steigerung erst danach, gegenüber der Vorwoche. Größter Sprung +25 % bei −20 %, +43 % am Rand des Kalibrierbereichs (−30 %). Die Begründung, die Rechnung zum 4,2-Fachen (nun 2,9-Fach) und R1, R2 sind angepasst. |
| 2 PAR-051, PAR-054, PAR-062 | Umgesetzt, mit Auslegung | „6 Monate regelmäßig“ ist als „im Mittel mindestens 1 Lauf je Woche über 26 Wochen“ gefasst, nach dem Einschluss in [L9]. „Erfahren“ verlangt zusätzlich alle Bedingungen von „Aufbau“, sonst wäre die Stufe nach 20 Wochen ohne die 6 Monate erreichbar. „8 Wochen nach dem Einstieg“ ist nach R002 B2 als „nach dem Ende des Einstiegs“ gelesen, die vorsichtigere Lesart. „Zunächst 5 %“ gilt einen Zyklus lang, für „Aufbau“ und nach jedem Einstieg; „Erfahren“ ohne Einstieg beginnt nach PAR-125, weil 5 × 3 min sonst 300 min Umfang bräuchten. |
| 3 PAR-161, PAR-162, PAR-173 | Umgesetzt, mit Auslegung | Rollendes Mittel der letzten 7 Nächte, mindestens 3 gültige Werte. Die letzte Nacht muss vorliegen, weil OQ-0006 eine aktuelle HRV verlangt; beim Ruhepuls gilt das für den Eintrag von heute. Für die Bremsung zählt nur der Wert am Tag der Einheit. TSB% ist in PAR-073, Lesehilfe und R3 als rollendes Mittel festgelegt, das Mittel über die Kalenderwoche ist gestrichen. Nenner siehe Abschnitt 3. |
| 4 PAR-190, PAR-102 | Umgesetzt | Bandbreite nur am langsamen Ende, lockere Grenze nicht geweitet, schnelles Ende des Tempodauerlaufs das langsamere aus 10-km-Tempo und Riegel-Tempo für 60 min. PAR-082, PAR-101, PAR-103, R6 und die Beispiele angepasst. |
| 5 PAR-068 | Umgesetzt | 10 km 12–16, Halbmarathon 22–28 Wochen, Grenzen unverändert. PAR-084 neu gerechnet. Übrige Regellängen geprüft, Ergebnis in Abschnitt 5 und 7. |
| 6 PAR-032 | Umgesetzt | Stand schon im Dokument; Tempogrenzen unverändert, Untergrenzen und Folgen genannt, Anteil der Nutzer ohne Wert im Validierungsbedarf. |
| 7 Google Health API | Umgesetzt | Teil D, Befund für ADR-0001, Validierungsbedarf, PAR-093, PAR-098, PAR-160, PAR-189 und `Bereits entschieden` in phase-2-3-rules.md. Die Zeile in Teil D bleibt als Bestandsaufnahme mit dem Zusatz „zurückgestellt“. PAR-189 gilt für Quell-Apps in Health Connect. Die Polar-Angabe aus [L49] in PAR-093 und PAR-098 ist als nicht angebundener Weg gekennzeichnet oder entfernt. |
| 8 HFmax | Umgesetzt | FR-0004 unverändert, Nes 2013 als eigene Zeile im Validierungsbedarf von model-parameters.md. |
| 9 PAR-163 | Umgesetzt | Formel unverändert, die Anzeige beschreibt nur die Abweichung. |

## 2. Punkt 10: Befunde vom Typ `Wert`

| Befund | Stand | Umsetzung |
|---|---|---|
| R001 M4 | Umgesetzt | PAR-027, PAR-026, PAR-045. Die Grenze von 1 % bleibt zusätzlich bestehen, das ist die vorsichtigere Lesart. Folge in PAR-081 genannt. |
| R001 M7 | Umgesetzt | PAR-036, Trendabzug ab 3 Abschnitten. Kleinste Quadrate sind eigene Wahl. Nachgerechnet: rund 9 und 12 % bei 0,6 bpm/min, der Bericht nennt 8,9 und 12,4 %. |
| R001 M8 | Umgesetzt | PAR-041 bis PAR-043. Die 12-Wochen-Bedingung ist gestrichen, weil sie nicht wirkte; FR-0059 zeigt das Datenalter. |
| R001 M9 | Umgesetzt | PAR-035, Neustart mit `n` = 2. |
| R001 M10 | Umgesetzt | PAR-011, PAR-021. |
| R001 S11 | Umgesetzt | PAR-003, Faktor 1. Validierungsbedarf ergänzt. |
| R001 S12 | Umgesetzt | PAR-019. Passt zu OQ-0019, weil PAR-018 bei HFmax ≤ HFRuhe den TRIMP weiter ausschließt. |
| R001 S13 | Umgesetzt | PAR-044 nur Ausschluss ab Minute 60. PAR-046 behält 30 min und nennt die Folge; der Bericht lässt das zu, und es ist die vorsichtigere Variante. |
| R002 M2 | Umgesetzt | PAR-053. Die Bindung je Woche trifft die Abfolge nur in Woche 6, Lauf 3; PAR-065 nimmt das aus (R7). Der Bericht hatte das nicht gesehen. |
| R002 M3 | Umgesetzt | PAR-055, PAR-056. |
| R002 M4 | Umgesetzt | PAR-054, dazu PAR-124, PAR-125 und PAR-129 von „je Woche“ auf „je Zyklus“. |
| R002 S7 | Umgesetzt | PAR-082, „ausreichend“ bis 13 % langsamer. Nachgerechnet sind es 12,2 bis 12,5 %, der Bericht nennt 13 %. |
| R002 S11 | Umgesetzt | PAR-064. |
| R003 M4 | Teilweise | PAR-128 Rückfallregel und Rechnung. Obergrenze 1 × 40 min entfällt wegen Punkt 11. |
| R003 M5 | Umgesetzt | PAR-160. Zitat aus [N23] am Volltext geprüft. |
| R003 M12 | Umgesetzt | PAR-107, PAR-109. Tabelle nachgerechnet. |
| R003 S4 | Umgesetzt | PAR-112 und `Evidenz insgesamt`. [N3] am Abstract geprüft: 55,5 und 60,5 ml/kg/min zu Beginn. |
| R003 S5 | Umgesetzt | Einleitung von Abschnitt 5 und PAR-172. |
| R003 S9 | Umgesetzt, mit Abweichung | R7, PAR-115, PAR-140. „stop if something doesn’t feel right“ fand sich beim Abruf am 2026-11-04 auf beiden Plan-Seiten nicht, „speak to a GP first“ schon. Der erste Satz des Hinweises steht deshalb als eigene Wahl. |
| R003 B1, B2, B3 und R002 B1, B2, M5 | Siehe Punkte 1 bis 5 | R003 B1 auch mit den Teilen „zählt nicht als Stufe“ und Hauptgröße im Validierungsbedarf. Grenze dafür 40 %, eigene Wahl über den rund 36 % aus R8. |

## 3. Nicht umgesetzt, und warum

| Befund oder Teil | Grund |
|---|---|
| R003 M2, Intervalle: „Blöcke ab 6 min zwischen 5-km- und 10-km-Tempo“ | Gegenstandslos: Punkt 11 begrenzt Intervallblöcke auf 5 min. Nicht in der Liste von Punkt 10. |
| R003 M4, „1 × 40 min entspricht 20 % bei 200 min“ | Widerspricht der Wahl zu PAR-118 und zu den Blocklängen. |
| R003 B3, Satz „PAR-103 und die dortige Bandbreite aus PAR-082 sind nicht betroffen“ | Widerspricht Punkt 4 nach dessen Wortlaut. Einseitig gilt deshalb auch die Spanne aus der VO₂max; gestützt auf [Q38], das zu hoch schätzt. Siehe Abschnitt 7. |
| R003 B2, „MAD aus der Reihe der Mittelwerte“ | Nicht umsetzbar ohne neue Grenzen: Bei ganzzahligem Ruhepuls läge sie je nach Streuung zu 46 bis 100 % unter 1 bpm (PAR-162), und `z` wäre mit SD 1,36 bis 1,56 auch bei AR 0 zu breit. Stattdessen MAD der Tageswerte geteilt durch √k: SD 1,05 bei AR 0, 1,31 bei AR 0,3, Grenzen und OQ-0006 bleiben. Ohne Korrektur wäre die SD 0,39. |
| R003 B2, Variante B | Punkt 3 wählt das Mittel. |
| R002 M5, Alternativen (Zielspitze 75–90 min, PAR-063 mit 50 %) | Punkt 5: „die Grenzen bleiben“. |
| R002 M9, Wiederholung „aktiv anbieten“ für alle Wochen | PAR-140 bietet sie schon nach Auslösern an; R003 S9 ergänzt Woche 5. Kein weiterer Auslöser. |

## 4. Punkt 11: Wahlen

| Punkt | Wahl | Warum vorsichtiger |
|---|---|---|
| PAR-038, PAR-039, Summenbedingung | Gestrichen. Die Zeile PAR-040 behält ihre 20 min, die dort wirken. | Das Ergebnis ändert sich nicht, und keine Bedingung täuscht eine Wirkung vor. |
| PAR-059, „rund 48 h“ | Gestrichen, der volle Kalendertag ist maßgeblich. Die Begründung nennt 24 bis 72 h. | Nach Punkt 11 vorgegeben. |
| PAR-090, Ende des Rückfalls | Sobald im 42-Tage-Fenster wieder höchstens 10 % fehlen, ohne Wartezeit. | Im Rückfall fehlt die Bremse; eine Wartezeit verlängerte das. |
| PAR-118 | 8 und 10 % sind Obergrenzen je Einheit und nicht nur ein Start. Erste intensive Phase 5 %. | Die Einheit bleibt in der Grenze aus [N5]. „Aufbau“ bleibt damit bei 8–10 %. |
| Blocklängen aus [N5] | Intervallblock höchstens 5 min, zusammenhängender Tempoblock höchstens 20 min. Es entfallen 4 × 6, 5 × 6, 4 × 8 und 1 × 40 min. PAR-125 bis PAR-129 angepasst; Endblock „Erfahren“ 15–20 min. | Die Studie zu 4 × 8 ist eine Radstudie [N4]. Die Pause von 3 min bei 3 × 15 folgt 5:1 aus [N5]. |
| PAR-056 während der Abfolge | Gilt. Entlastung ist die letzte Programmwoche mit allen Phasen auf 80 %, danach dieselbe Woche unverändert (Punkt 1), dann weiter. Dasselbe im Einstiegsplan, Woche 4. Bei 1 oder 2 Tagen entfällt die Woche (PAR-141). | Mehr Erholung, und Punkt 1 gilt auch hier. Streckt die Abfolge von 9 auf 15 Trainingswochen. PAR-068 nennt deshalb 16 Wochen ab Einstieg. |
| PAR-105, Anker | Die App zeigt die Wortanker von Borg CR-10. Wortlaut nicht übernommen, weil nicht an der Originalquelle geprüft; Nutzungsrechte offen. | Nur so gilt [N29]. |
| PAR-172, reiner Schlafmangel | Liegt nur Schlaf unter seinem Bezug, nennt der Text „wegen kurzer Schlafdauer“. | Der Text unterstellt keine Trainingsbelastung. |
| PAR-100 | Test ist nur eine Eingabe für Riegel, keine Schwelle. | Keine Schwelle aus einem einzelnen Test. |
| PAR-116 | Ruhetag ist ein Planeintrag ohne Dauer. | Keine scheinbare Belastung. |
| PAR-123 | Verbot gilt, solange die Stufe gilt. | Strengere Lesart; PAR-054 ist entsprechend gefasst. |
| PAR-141 | Die 25–30 min aus PAR-064 gelten nur für den Dauerlauf-Einstieg. Die maximale Zeit bleibt die Grenze. | Die Vorlage bleibt unverändert, FR-0136 gilt. |
| PAR-168, PAR-170, Tag 127 | Fehlt der Belastungsfaktor, ist der Wert höchstens 74. PAR-072 ist gewahrt, weil TSB nur senkt und nie als Grund für einen hohen Wert erscheint. | Fehlende Daten verbessern die Einordnung nicht. Der Rest des Sprungs bleibt genannt: „Erhöhte Belastung“ 11–29 % gegen 12–34 %. |
| PAR-178, R3-Zitat | −20 im rollenden Mittel. | Folgt aus Punkt 3. |
| PAR-065, Relph und Bezeichnung | Zahlen wie in PAR-132: 21 Verletzungen bei 20 Läufern, 27,3 % gegen 64,5 %. Herkunft Josh Clark nach [N28], am Volltext geprüft. „NHS-Struktur“ in PAR-065, PAR-141 und PAR-142 ersetzt, Hinweis auf das Verbot der Quellenangabe. | Einheitlich mit R003 M8 und M9. |

## 5. Neu gerechnete Beispiele

Skripte unten. Keine Messergebnisse.

| Rechnung | Ergebnis |
|---|---|
| R1 | Unverändert −57, −15, −5. Plan an PAR-052: Tag 126 −23, −28, −33; danach −25, −30 (Tag 133), −35. Die Schwelle aus PAR-074 greift bei „Erfahren“ sofort, bei „Aufbau“ eine Woche später. |
| R2 | −21, −27, −32, −41, −57 (Mo, Mi, Fr). Etwas tiefer als zuvor, weil die Spitze spät im Zyklus kommt. |
| R3 | −20, −37, −26, −47, nur rollend. |
| R4, R5 | Nicht betroffen. |
| R6 | Siehe Dokument; einseitig mit bis 13 %. |
| R7 | Größter Schritt 108,6 %, Woche 6, Lauf 3 über der Bindung je Woche (35:00 gegen 34:39). |
| R8 | Tabelle im Dokument. Alle fünf Faktoren: gut 0,8–7,3, normal 61,8–85,8, erhöht 11,7–34,4, Erholung 0–1,3 %. Der Anteil am Tag der Einheit unter 50 liegt bei rund 12 bis 36 %. Das 7-Nächte-Mittel senkt ihn gegenüber R003 B1 kaum, weil die Spannen von Schlaf und TSB% bleiben und `z` bei Autokorrelation breit ist. |
| PAR-084 | 10 km: 15, 13, 12 Wochen. Halbmarathon 90 min: 27, 24, 20. 120 min: 35, 29, 24. Ab 3 × 50 min: Halbmarathon Aufbau 12, Erfahren 9. Je Zyklus mit steigendem harten Anteil +4 Wochen. |
| Regellängen | Ab 30 min: 5 km 8 Wochen erreichbar. 10 km 12: nur „Erfahren“. Halbmarathon 22: nur „Erfahren“ sicher, „Aufbau“ knapp nicht (89,6 min), „Einsteiger“ erst 27. Ab sicher 10 km: 10 km 8 und Halbmarathon 12 erreichbar, bei „Aufbau“ aber ohne Reserve; mit einem Zyklus für den harten Anteil wären es 16. |
| Pace 25:00 | Intervalle 4:51–5:00, Tempodauerlauf 5:15–5:27, locker ab 6:00. Mit 3, 6, 10 %: 5:09, 5:18, 5:30 und 5:37, 5:47, 6:00. |
| Daniels | Tempodauerlauf 81–88 % VDOT, also nicht mehr über T. |
| Rechenbeispiele Abschnitt 5, Erreichbarkeit | Nachgerechnet, unverändert. Sie setzen `z` als gegeben und enthalten alle den Belastungsfaktor oder bleiben unter 74. |
| 12-Wochen-Beispiele | Kurzfassung in planning-rules.md. Weg A: Spitze +23 %, Laufminuten ×3,1, keine Intensität, 30 min in Woche 15. Weg B: +32 % gegenüber Woche 3, Sprung höchstens +25 %, keine Intensität ohne Selbstauskunft. Aufbau: nur Umfang +73 % wie zuvor, mit erster intensiver Phase +44 %, TRIMP +49 %. |

**Folgen über Dokumentgrenzen:**
- **PAR-081:** Stufen hängen an PAR-036, PAR-041 bis PAR-043 und PAR-027. Ohne Vertikalgenauigkeit keine Pace. Einsteiger erhalten bis zu 26 Wochen keine Referenz über den vorgeschlagenen Test.
- **PAR-083:** Formel und Grenzen unverändert. [L20] setzt keine Intervalle voraus. Längere Regelpläne fallen meist unter die um ein Viertel gesenkten Grenzen.
- **PAR-055:** M3 eingetragen, Lücke aus PAR-073 und PAR-090 bleibt genannt. PAR-173 berührt die Bedingung nicht.
- **PAR-117, PAR-085:** Test auch erst nach der Frist aus PAR-054. PAR-143 verweist auf PAR-117 und bleibt.
- **PAR-094:** `f` nutzt weiter die Abweichung der einzelnen Nacht. Punkt 3 nennt nur PAR-161, PAR-162 und PAR-173; die Funktion ist ausgeblendet.
- **PAR-148 bis PAR-150:** Mengen zählen weiter die Referenzwerte (OQ-0006).
- **PAR-124, PAR-127, PAR-129:** Bei 5 % gibt es unter 160 min Umfang keine intensive Einheit, unter 200 min auch keinen Tempodauerlauf oder Endblock von 10 min.

## 6. Nötige Änderungen außerhalb der drei Dokumente

Der Wortlaut ist ein Vorschlag. `[ ]` steht für ein Akzeptanzkriterium.

| Stelle | Änderung, Wortlaut |
|---|---|
| [heart-rate-zones.md](../../specs/heart-rate-zones.md), FR-0060 | AK ersetzen: `[ ] Bei HFmax ≤ HFRuhe gilt PAR-018, bei 0 < HFR < 50 bpm PAR-019.` |
| [training-load.md](../../specs/training-load.md), FR-0093 | AK ersetzen: `[ ] Eine Änderung der Reservezonen oder des Ruhepulses ändert den Edwards-TRIMP nicht, außer er wird nach PAR-018 unverfügbar.` |
| [vo2max.md](../../specs/vo2max.md), FR-0069 | AK ergänzen: `[ ] Die Steigung geht nur nach PAR-027 ein.` |
| vo2max.md, FR-0077 | AK ersetzen, weil eine reine Drift nach PAR-036 nicht mehr als Streuung zählt: `[ ] Bei gleichem Mittelwert und gleichem Zeittrend erhält ein Lauf mit stark streuenden Abschnitten keine bessere Qualität als ein Lauf mit eng beieinanderliegenden.` |
| [readiness.md](../../specs/readiness.md), FR-0109 | AK ersetzen: `[ ] Eine Zahl erscheint nur mit HRV der letzten Nacht, einem rollenden Mittel aus mindestens 3 gültigen Werten in 7 Nächten (PAR-161) und Schlaf sowie einer Referenz aus mindestens 14 gültigen Messungen in 28 Tagen; sonst eine eingeschränkte Einschätzung ohne Zahl (OQ-0006).` |
| readiness.md, FR-0110 | AK ergänzen: `[ ] Für die Wirkung auf den Plan zählt nur der Wert am Tag der intensiven Einheit (PAR-173).` |
| readiness.md, FR-0111 | AK ersetzen: `[ ] Fehlende optionale Faktoren werden herausgerechnet und ausgewiesen (OQ-0029). Fehlt der Belastungsfaktor, ist der Wert höchstens 74 (PAR-170).` |
| readiness.md, FR-0113 | Text ergänzen: „Bei HRV und Ruhepuls ist `x` das rollende Mittel aus `k` gültigen Werten der letzten 7 Nächte und `X` die Reihe der Tageswerte. Im Nenner steht dann `1,4826 · MAD(X) / √k` (PAR-161, PAR-162).“ AK ergänzen: `[ ] Testfall (abgeleitet): X = {48, 50, 52}, k = 4, x = 51 ergibt z = 0,67.` |
| readiness.md, FR-0115 | AK ergänzen: `[ ] Jede Reihe stammt aus genau einer Quell-App; mehrere Quell-Apps werden nicht gemischt (PAR-160, PAR-189).` |
| readiness.md, FR-0117 | AK ergänzen: `[ ] Liegt nur der Schlaf unter seinem Bezug, nennt die Erklärung die kurze Schlafdauer als Grund (PAR-172).` |
| [run-recording.md](../../specs/run-recording.md), FR-0038 | AK ergänzen: `[ ] Die RPE-Skala zeigt die Wortanker der Borg-Skala CR-10 (PAR-105).` |
| [training-plan.md](../../specs/training-plan.md), FR-0139 | AK ergänzen: `[ ] Die Ausgangsanalyse nutzt die Dauer des regelmäßigen Laufens aus Daten oder Selbstauskunft (PAR-051).` |
| training-plan.md, FR-0140 | AK ergänzen: `[ ] Einstiegsplan und Geh-Lauf-Abfolge enthalten Entlastungswochen (PAR-056, PAR-065); ein Hinweis steht vor dem Geh-Lauf-Plan (PAR-115).` |
| training-plan.md, FR-0148 | AK ergänzen: `[ ] Die erste Woche nach einer Entlastung erreicht höchstens die letzte Woche ohne Entlastung (PAR-052).` und `[ ] In einem Zyklus steigt nur Umfang oder harter Anteil (PAR-054).` |
| training-plan.md, FR-0151 | AK ergänzen: `[ ] Intensive Einheiten erscheinen erst ab der Stufe Aufbau (PAR-051), frühestens 8 Wochen nach dem Ende des Einstiegs und zunächst mit höchstens 5 % harter Zeit (PAR-054); passt die erste Stufe nicht, ist die Einheit locker.` |
| training-plan.md, FR-0153 | AK ergänzen: `[ ] Die Bandbreite weitet nur das langsame Ende der Pace, die Grenze für lockere Läufe wird nicht geweitet (PAR-082, PAR-190).` |
| training-plan.md, FR-0154 | AK ergänzen: `[ ] Die Einschätzung bei Distanzzielen folgt PAR-084.` |
| [performance-prediction.md](../../specs/performance-prediction.md), FR-0129 | AK ersetzen: `[ ] Ohne Referenz gibt es keine Prognose, sondern einen Hinweis auf einen 5-km-Test, bei Einsteigern erst nach dieser Stufe und der Frist aus PAR-054 (OQ-0034, OQ-0057).` |
| [health-import.md](../../specs/health-import.md), FR-0200 | AK ergänzen: `[ ] Liefern mehrere Quell-Apps HRV oder Ruhepuls, gilt PAR-189.` |
| [index.md](../../index.md), Zeilen 41–43 | „Version 1“ durch „Version 2“ ersetzen. |
| [product.md](../../product.md), DEC-0029, DEC-0050, DEC-0055 | „als Version 1 freigegeben“ durch „als Version 2 freigegeben“ ersetzen oder einen neuen Vermerk zur Freigabe setzen. Neue DEC-IDs vergibt nur der Maintainer. |
| [open-questions.md](../open-questions.md), OQ-0059 | Status `Resolved`, „Noch einzutragen“ streichen. Solange sie offen ist, bleibt sie `blocking` für die Phasen 1 bis 3. OQ-0058 nennt „die nächste intensive Einheit“; PAR-173 liest das als die Einheit am Tag des Werts. OQ-0048 um die Wortanker der Borg-Skala ergänzen. |

Danach `spec_tool.py build` und `check` ausführen. Das Register und `Offene Fragen` der Specs sind generiert.

## 7. Für den Maintainer

Bitte bestätigen oder ändern, jeweils ist die eingetragene Variante die vorsichtigere oder einzig lauffähige:
1. **`z` mit MAD / √k (PAR-161, PAR-162, FR-0113).** Weicht von „MAD aus der Reihe der Mittelwerte“ ab, siehe Abschnitt 3.
2. **Einseitige Bandbreite auch für die Pace aus der VO₂max (PAR-082, PAR-103).** Eine zu tiefe Schätzung bleibt dadurch ungedeckt.
3. **Abfolge 15 Wochen statt 9 (PAR-065, PAR-068).** Ohne die Wiederholung nach der Entlastung wären es 11 Wochen, dann gälte Punkt 1 dort nicht. Ohne Entlastung 9 Wochen wie bei NHS.
4. **Wegfall von 4 × 6, 5 × 6, 4 × 8 und 1 × 40 min (PAR-125, PAR-128).** Folgt aus der Wahl zu [N5].
5. **Kappung auf 74 ohne Belastungsfaktor (PAR-170).** Berührt die Bänder aus OQ-0029 nicht, setzt aber eine Grenze, die OQ-0029 nicht nennt.
6. **5 % und „Aufbau“ (PAR-054).** Unter 160 min Umfang keine intensive Einheit, also bei 3 × 40 min erst ab Woche 6. Das Beispiel aus FR-0151 kommt dort später als zuvor.

Noch zu entscheiden:
7. **Untere Ränder von PAR-068.** Halbmarathon ab 22 Wochen ist für „Einsteiger“ und knapp für „Aufbau“ unerreichbar, 10 km ab 12 Wochen nur für „Erfahren“. Die App bewertet solche Pläne selbst als „eher unrealistisch“. Mit einem Zyklus für den harten Anteil braucht „Aufbau“ die vollen 28 Wochen, mit zwei reicht es nicht. Die obere Zielspitze 120 min ist in 28 Wochen nur für „Erfahren“ erreichbar.
8. **Umfangsspitze bei „Aufbau“.** +73 % in 11 Wochen bleiben möglich, weil Punkt 1 die Spitze nicht senkt.
9. **Wortanker der Borg-Skala:** Wortlaut und Nutzungsrechte.
10. **`z` bei Autokorrelation** ist zu breit (SD 1,31 bei AR 0,3). Ob das so bleibt, entscheidet erst der Feldtest. Die Grenze von 40 % im Validierungsbedarf ist eigene Wahl.

## Grenzen der Prüfung

Am 2026-11-04 erneut abgerufen: [N23] im Volltext, [N3] als Abstract, NHS-Seiten, Relph 2023 im Volltext. Alle anderen Zitate stammen unverändert aus den Dokumenten oder aus R001 bis R003 und wurden hier nicht neu geprüft. Neue Quellen sind nicht hinzugekommen. Die Skripte zeigen Obergrenzen und Empfindlichkeiten, nicht das Verhalten eines Planers, den es noch nicht gibt.

## Skripte

Python-Standardbibliothek, gelaufen mit Python 3.15.0.

R1 bis R3, Formeln aus FR-0098, FR-0099 und FR-0101, Einheiten Mo, Mi, Fr:

```python
"""R1-R3: ATL/CTL/TSB% nach FR-0098, FR-0099, FR-0101. Nur Standardbibliothek."""
def series(week_vols, pattern=(0,2,4), start=None, burn=None):
    """week_vols: Wochenlast. start: Gleichgewichtslast oder None(Start 0)"""
    days=[]
    for v in week_vols:
        d=[0.0]*7
        for i in pattern: d[i]=v/len(pattern)
        days+=d
    if burn is not None:
        pre=[]
        for _ in range(60):
            d=[0.0]*7
            for i in pattern: d[i]=burn/len(pattern)
            pre+=d
        days=pre+days; offset=len(pre)
    else: offset=0
    atl=ctl=0.0; tsbp=[]; 
    for t,l in enumerate(days):
        # TSB[t]=CTL[t-1]-ATL[t-1]; TSB%=100*TSB[t]/CTL[t-1]
        tsbp.append(100*(ctl-atl)/ctl if ctl>0 else None)
        atl+= (l-atl)/7; ctl+=(l-ctl)/42
    return tsbp, offset
def roll7(tsbp):
    out=[None]*len(tsbp)
    for t in range(6,len(tsbp)):
        w=tsbp[t-6:t+1]
        if all(x is not None for x in w): out[t]=sum(w)/7
    return out
def min_roll(week_vols,pattern=(0,2,4),burn=100.0,cool=8):
    s,off=series(list(week_vols)+[burn]*0,pattern,burn=burn)
    r=roll7(s)
    return min(x for x in r[off:] if x is not None)

def plan(n_cycles, wk, cy, base=100.0, deload=.2, new=True):
    """Obergrenze: PAR-052 ausgereizt. Rueckgabe Wochen."""
    v=[];peak=base;last=base
    for c in range(n_cycles):
        cap=peak*(1+cy)
        for i in range(3):
            if new and c>0 and i==0: x=min(last,cap)
            else: x=min(last*(1+wk),cap)
            v.append(x); last=x
        peak=last
        v.append(last*(1-deload))
    return v
```

PAR-084, PAR-068, Umfang und längste Einheit an den Obergrenzen. `ST` enthält die Grenzen aus PAR-052 je Stufe, `first_week` die erste Woche mit der Zielspitze:

```python
ST = {"Einsteiger": (.10, .15), "Aufbau": (.15, .20), "Erfahren": (.20, .25)}
def weeks(st, v0, n, long0=None, deload=.2, hold_cycles=(), first_is_after_deload=False, days=3, longshare=.40):
    """Obergrenzen: PAR-052 (Entscheidung: erste Woche nach Entlastung <= letzte Woche ohne Entlastung),
    PAR-053 (110 % der laengsten Einheit der letzten 30 Tage, bei <30 min +3 min, je Woche hoechstens eine Erhoehung),
    PAR-057 (-20 %), PAR-063 (40 %). hold_cycles: Zyklen ohne Umfangszuwachs (harter Anteil steigt, PAR-054)."""
    w,c=ST[st]
    V=[];L=[];peak=v0;last=v0
    long_hist=[long0 if long0 is not None else v0/days]*4   # letzte 4 Wochen ~30 Tage
    wk=0;cyc=0
    while wk<n:
        cap=peak*(1+c)
        hold=cyc in hold_cycles
        for i in range(3):
            if hold: x=last
            elif i==0 and cyc>0: x=last
            else:
                x=max(last*(1+w), last+5); x=min(x,max(cap,last))
            V.append(x); last=x
            ref=max(long_hist[-4:])
            lim=ref*1.10 if ref>=30 else max(ref*1.10,ref+3)
            l=min(longshare*x,lim); l=max(l,min(ref,longshare*x))
            L.append(l); long_hist.append(l); wk+=1
        peak=last
        V.append(last*(1-deload)); l=L[-1]*(1-deload)
        L.append(l); long_hist.append(l); wk+=1
        cyc+=1
    return V[:n],L[:n]
def first_week(st,v0,target,long0=None,hold=(),n=80):
    V,L=weeks(st,v0,n,long0,hold_cycles=hold)
    for i,l in enumerate(L):
        if l>=target-1e-9: return i+1,V[i],l
    return None
```

R8:

```python
"""R8: Sensitivitaetsrechnung Readiness mit rollendem 7-Naechte-Mittel. Nur Standardbibliothek. python3 -I r8.py"""
import math, random, statistics

def c(x, a=0, b=100): return max(a, min(b, x))
def P(z): return c(60 + 25 * z) if z < 0 else min(60 + 20 * z, 90)                # PAR-163
def D(h): return 80 if h >= 8 else (70 + 10 * (h - 7) if h >= 7 else c(70 - 25 * (7 - h)))  # PAR-165
def L(t): return min(60, c(60 + 2 * (t + 10)))                                    # PAR-168
MOOD = {1: 10, 2: 35, 3: 60, 4: 75, 5: 90}                                        # PAR-169
P_MOOD = [.03, .12, .5, .25, .1]
W = {"hrv": 25, "rhr": 20, "sleep": 30, "load": 15, "mood": 10}                   # FR-0110
SETS = {"alle": ("hrv", "rhr", "sleep", "load", "mood"), "ohne Belastung": ("hrv", "rhr", "sleep", "mood"),
        "HRV, Ruhepuls, Schlaf": ("hrv", "rhr", "sleep"), "HRV, Schlaf": ("hrv", "sleep")}
def value(sc, keys):                                                              # PAR-170
    v = sum(W[k] * sc[k] for k in keys) / sum(W[k] for k in keys)
    v = math.floor(v + .5)
    return min(v, 74) if "load" not in keys else v
def band(v): return 0 if v >= 75 else 1 if v >= 50 else 2 if v >= 25 else 3       # OQ-0029
DAYS = 29   # 28 Tage Referenz, heute

def path(rng, ar):
    e = rng.gauss(0, 1); out = []
    for _ in range(DAYS):
        e = ar * e + math.sqrt(1 - ar * ar) * rng.gauss(0, 1); out.append(e)
    return out

def z_mean(x, k=7):
    """PAR-161: Mittel der letzten k gueltigen Naechte gegen Median und MAD der 28 Tage davor, MAD / sqrt(k)."""
    ref = x[:-1]; med = statistics.median(ref); mad = statistics.median(abs(a - med) for a in ref)
    return (sum(x[-k:]) / k - med) / (1.4826 * mad / math.sqrt(k))

def z_single(x):
    ref = x[:-1]; med = statistics.median(ref); mad = statistics.median(abs(a - med) for a in ref)
    return (x[-1] - med) / (1.4826 * mad)

def draw(rng, rho, ar):
    g = path(rng, ar); a = path(rng, ar); b = path(rng, ar)
    s, t = math.sqrt(rho), math.sqrt(1 - rho)
    return [s * g[i] + t * a[i] for i in range(DAYS)], [s * g[i] + t * b[i] for i in range(DAYS)], g[-1]

def bands(n=50_000):
    for ar in (0, .3):
        for rho in (0, .5):
            for hm, hs, tm in ((7.2, .8, -12), (6.5, 1, -20)):
                rng = random.Random(1); cnt = {k: [0] * 4 for k in SETS}
                for _ in range(n):
                    xh, xr, g = draw(rng, rho, ar)
                    sc = {"hrv": P(z_mean(xh)), "rhr": P(z_mean(xr)), "sleep": D(rng.gauss(hm, hs) + .5 * rho * g),
                          "load": L(rng.gauss(tm, 10)), "mood": MOOD[rng.choices([1, 2, 3, 4, 5], P_MOOD)[0]]}
                    for k, keys in SETS.items():
                        cnt[k][band(value(sc, keys))] += 1
                for k, v in cnt.items():
                    print(ar, rho, hm, k, [round(100 * x / n, 1) for x in v])

def fixed_sleep(n=50_000, ar=.3, rho=.5):
    for h in (6, 7, 8):
        rng = random.Random(1); cnt = [0] * 4
        for _ in range(n):
            xh, xr, g = draw(rng, rho, ar)
            sc = {"hrv": P(z_mean(xh)), "rhr": P(z_mean(xr)), "sleep": D(h), "load": L(-5),
                  "mood": MOOD[rng.choices([1, 2, 3, 4, 5], P_MOOD)[0]]}
            cnt[band(value(sc, SETS["alle"]))] += 1
        print("Schlaf fest", h, [round(100 * x / n, 1) for x in cnt])

def width(n=30_000):
    for ar in (0, .3, .6):
        for name, f in (("Mittel 7", lambda x: z_mean(x, 7)), ("Mittel 3", lambda x: z_mean(x, 3)), ("Einzelwert", z_single)):
            rng = random.Random(1); z = [f(path(rng, ar)) for _ in range(n)]
            print("AR", ar, name, "SD", round(statistics.pstdev(z), 2), "P(z<-2)", round(100 * sum(a < -2 for a in z) / n, 1))

if __name__ == "__main__":
    bands(); fixed_sleep(); width()
```

Ausgabe in %, Reihenfolge gut, normal, erhöht, Erholung. Fall: AR, Korrelation, mittlere Schlafdauer, Faktoren.

```text
0 0 7.2 alle [2.5, 85.8, 11.7, 0.0]
0 0 7.2 ohne Belastung [0.0, 88.8, 11.1, 0.0]
0 0 7.2 HRV, Ruhepuls, Schlaf [0.0, 86.6, 13.3, 0.1]
0 0 7.2 HRV, Schlaf [0.0, 86.3, 13.4, 0.3]
0 0 6.5 alle [0.8, 68.6, 30.4, 0.2]
0 0 6.5 ohne Belastung [0.0, 75.3, 24.4, 0.4]
0 0 6.5 HRV, Ruhepuls, Schlaf [0.0, 71.4, 27.6, 1.0]
0 0 6.5 HRV, Schlaf [0.0, 67.8, 29.6, 2.6]
0 0.5 7.2 alle [5.0, 79.6, 15.4, 0.0]
0 0.5 7.2 ohne Belastung [0.0, 85.0, 14.8, 0.1]
0 0.5 7.2 HRV, Ruhepuls, Schlaf [0.0, 82.4, 17.2, 0.4]
0 0.5 7.2 HRV, Schlaf [0.0, 85.1, 14.5, 0.4]
0 0.5 6.5 alle [1.7, 65.6, 32.1, 0.7]
0 0.5 6.5 ohne Belastung [0.0, 72.5, 26.6, 0.9]
0 0.5 6.5 HRV, Ruhepuls, Schlaf [0.0, 68.8, 29.3, 1.9]
0 0.5 6.5 HRV, Schlaf [0.0, 67.0, 29.9, 3.1]
0.3 0 7.2 alle [3.9, 81.0, 15.1, 0.0]
0.3 0 7.2 ohne Belastung [0.0, 85.4, 14.6, 0.1]
0.3 0 7.2 HRV, Ruhepuls, Schlaf [0.0, 82.5, 17.3, 0.2]
0.3 0 7.2 HRV, Schlaf [0.0, 82.5, 17.1, 0.5]
0.3 0 6.5 alle [1.2, 65.3, 33.0, 0.5]
0.3 0 6.5 ohne Belastung [0.0, 72.0, 27.3, 0.7]
0.3 0 6.5 HRV, Ruhepuls, Schlaf [0.0, 68.2, 30.1, 1.7]
0.3 0 6.5 HRV, Schlaf [0.0, 65.5, 30.8, 3.7]
0.3 0.5 7.2 alle [7.3, 73.3, 19.3, 0.1]
0.3 0.5 7.2 ohne Belastung [0.0, 80.7, 19.0, 0.3]
0.3 0.5 7.2 HRV, Ruhepuls, Schlaf [0.0, 78.0, 21.1, 0.8]
0.3 0.5 7.2 HRV, Schlaf [0.0, 81.3, 18.0, 0.8]
0.3 0.5 6.5 alle [2.5, 61.8, 34.4, 1.3]
0.3 0.5 6.5 ohne Belastung [0.0, 69.1, 29.1, 1.8]
0.3 0.5 6.5 HRV, Ruhepuls, Schlaf [0.0, 65.8, 30.8, 3.4]
0.3 0.5 6.5 HRV, Schlaf [0.0, 64.6, 31.0, 4.4]
Schlaf fest 6 [0.0, 68.5, 31.5, 0.0]
Schlaf fest 7 [8.5, 78.5, 13.1, 0.0]
Schlaf fest 8 [17.6, 74.2, 8.2, 0.0]
AR 0 Mittel 7 SD 1.05 P(z<-2) 3.0
AR 0 Mittel 3 SD 1.09 P(z<-2) 3.3
AR 0 Einzelwert SD 1.14 P(z<-2) 4.0
AR 0.3 Mittel 7 SD 1.31 P(z<-2) 6.1
AR 0.3 Mittel 3 SD 1.31 P(z<-2) 6.0
AR 0.3 Einzelwert SD 1.16 P(z<-2) 4.1
AR 0.6 Mittel 7 SD 1.7 P(z<-2) 11.4
AR 0.6 Mittel 3 SD 1.59 P(z<-2) 9.6
AR 0.6 Einzelwert SD 1.2 P(z<-2) 4.7
```

## Nachtrag: Entscheidungen vom 2026-11-04

Die Abschnitte oben bleiben als Stand vor diesen Entscheidungen stehen. Maßgeblich sind OQ-0059 und die Regeldokumente. Überholt sind die Wahl zu PAR-056 während der Abfolge, die Zeile zu FR-0140 in Abschnitt 6, die Punkte 3 und 7 in Abschnitt 7 und in Abschnitt 5 Fall A, R7 ab „Mit Entlastung“ und die Spannen bei den Regellängen. Durch den Stand vom selben Tag ebenfalls überholt: die Borg-Anker und die Erweiterung von OQ-0048 in den Abschnitten 4 und 6, Punkt 9 in Abschnitt 7, die Längen unter PAR-084 und unten `Aufbau Regelfall` mit 24, 40 und 52 Wochen. Falsch war in Abschnitt 2 zu R003 S9, der NHS-Satz fehle: Er steht auf der Seite. Maßgeblich für Längen und Einstufung ist [R004-fixes.md](R004-fixes.md).

Rechnung zu PAR-084, mit `weeks` und `first_week` von oben:

```python
ST["Aufbau Regelfall"] = (.15, .10)              # Woche, Zyklus
first_week("Aufbau Regelfall", 90, 60)           # (22, 159.4, 63.8), + 2 = 24
first_week("Aufbau Regelfall", 90, 90)           # (38, 233.4, 93.4), + 2 = 40
first_week("Aufbau Regelfall", 90, 120)          # (50, 310.7, 124.3), + 2 = 52
first_week("Aufbau Regelfall", 150, 90, 60)      # (18, 241.6, 96.6), + 2 = 20
first_week("Einsteiger", 120, 60, 40)            # (6, 151.8, 60.7), + 1 = 7, + 9 = 16
first_week("Einsteiger", 120, 90, 40)            # (18, 230.9, 92.3), + 1 = 19, + 9 = 28
```
