# R001 Research-Review: Modellparameter (PAR-001 bis PAR-048)

**Urteil: NACHBESSERN**

Geprüft wurde `docs/model-parameters.md`, Version 1, am 2026-11-04. Kein Zitat ist erfunden, und keine geprüfte Zahl weicht so ab, dass ein Wert hinfällig wird. Nachzubessern sind vor allem eine übersehene direkte Studie, ein Beleg aus falschem Kontext, sechs zu hoch eingestufte Zeilen und Stufenregeln, die sich widersprechen oder kaum erreichbar sind.

Getroffene Entscheidungen (OQ-0001, OQ-0012, OQ-0019, OQ-0036, OQ-0037) sind nicht neu aufgerollt. Wo ein Befund sie berührt, geht es nur um Begründung und Offenlegung der Folgen.

## Geprüfter Umfang

| Gegenstand | Ergebnis |
|---|---|
| Zeilen | Alle 48: 1 `belegt`, 12 `abgeleitet`, 35 `Heuristik`. Bei Heuristiken wurden die genannten Zahlen und die Kennzeichnung geprüft, nicht der gewählte Wert an sich. |
| Quellen Q1 bis Q37 | 37 von 37 abgerufen; alle URLs existieren. |
| Rechnungen | Alle nachgerechnet, keine falsch (siehe Abschnitt `Nachgerechnet`). |
| Abruf | Q1 und Q9 als Originaltext gelesen, Q7, Q18, Q21, Q23, Q32 als Abstract über Europe PMC, weil PubMed das Abrufwerkzeug blockiert (gleicher Datensatz). Die Kernstellen von Q16 und der neuen Studie Dugas 2023 sind im Volltext-XML geprüft. Die übrigen Seiten liefen über einen Webabruf mit Zusammenfassung und wörtlichen Auszügen. |

**Nicht geprüft (nicht abrufbar oder nicht versucht), daher nicht als falsch bewertet:**
- ACSM's Guidelines als Primärquelle: kein Volltext. Der Gültigkeitsbereich von PAR-030 und PAR-031 bleibt sekundär belegt.
- IAAF-Biomechanikbericht Berlin 2009, die Primärquelle hinter Q20: nicht versucht.
- CSEM-Bericht (403), IDEA-Artikel (403, nur Suchauszug), Validierungsstudie von Marsh et al. 1999 in JSCR (402, nur Suchauszug und Zitat in Dugas 2023).
- Swain und Franklin 2021, Wynne 2023, Shushan 2023, Apunts-Studie: nicht versucht.

## Antworten zu den Schwerpunkten

- **ACSM-Gültigkeitsbereich (PAR-030, PAR-031):** Die Wortlaute stimmen. Q5 nennt „speeds greater than 5.0 mph (134 m·min-1)“, Q4 ergänzt „or 3.0 mph or greater if the subject is jogging“. `belegt` ist für 134 m/min haltbar, aber nur sekundär. Die Grenze von 120 m/min ist keine Gültigkeitsgrenze der Formel, sondern ein Ersatzkriterium für den Gang (S5).
- **Garmin (PAR-020, PAR-028):** Die Zahlen stehen im Handbuch der Forerunner-570-Reihe. Die 10 min tragen den Vergleich in PAR-020. Für PAR-028 reicht der Beleg nicht (M5).
- **Hunt 2015 (PAR-011):** Alle Zahlen stimmen. Die Übertragung auf Start und Pause deckt die Studie nicht ab (S1).
- **Tanaka, Quer (PAR-016, PAR-017):** Alle Zahlen stimmen. Eine Streuungsangabe lässt sich leicht ergänzen (S2).

---

## Befunde

### Blocker

Keine.

### Muss

**M1. PAR-032 (auch PAR-030, PAR-031, PAR-042, PAR-043): Die Schätzung hat eine feste Untergrenze, und die Dokumentation nennt nur die niedrigste.**
- **Problem:** Die Formel erzeugt in Kombination mit den Grenzen einen Mindestwert. PAR-032 nennt nur „kaum unter 29“. Nicht genannt ist: Mit 134 m/min und `r` ≤ 0,85 kann die Schätzung in der Ebene nicht unter 35,0 fallen, bei −2 % Gefälle nicht unter 32,2. „Ausreichend“ und „gut“ sind unterhalb davon also unerreichbar, und damit auch die Langzeitstufen aus PAR-042 und PAR-043 und die Pace-Vorgaben nach PAR-081. Wer nahe der Grenze liegt und einen Wert erhält, wird zudem eher überschätzt, denn niedrigere Ergebnisse können nicht entstehen. Lockere Läufe bei `r` = 0,65 erreichen die volle Bewertung erst ab einer geschätzten VO₂max von 44,7 und überhaupt einen Wert erst ab 40,4.
- **Beleg:** Rechnung nach FR-0069 und FR-0071. FRIEND-Median (US-Allgemeinbevölkerung, Laufband): Männer 40–49 Jahre 37,8, 50–59 Jahre 32,6; Frauen 20–29 Jahre 37,6, 30–39 Jahre 30,2, 40–49 Jahre 26,7 (https://pmc.ncbi.nlm.nih.gov/articles/PMC4919021). Bei Freizeitläufern lag der Messwert im Mittel bei 46,8, bei Frauen bei 43,8 (https://pmc.ncbi.nlm.nih.gov/articles/PMC10747607/). `docs/product.md` nennt ausdrücklich auch Einsteiger und Wiedereinsteiger. Als Registerdaten sind die FRIEND-Werte nur eine Einordnung, keine Schätzung des Nutzeranteils.
- **Korrektur:** In PAR-032 die Untergrenzen 29,2 (kein Wert), 35,0 und 32,2 (höchstens vorläufig) sowie die Folge für lockere Läufe nennen. Im Validierungsbedarf ergänzen: Anteil der Nutzer ohne Wert und ohne Stufe „ausreichend“ je Geschlecht und Alter, sowie Vergleich mit Referenz nahe der Untergrenze. Das Entscheidungsfeld von OQ-0019 bleibt unberührt. Ob diese Folge gewollt ist, sollte der Maintainer jedoch bewusst bestätigen, weil OQ-0019 nur die Tempofolge nennt.
- **Typ:** Beleg/Text

**M2. PAR-030, PAR-031: Die Evidenzaussage übersieht die direkteste Studie, und der Fehler „in beide Richtungen“ ist zu unscharf.**
- **Problem:** „Evidenz insgesamt“ sagt, die Studien nutzten „meist Laufband, kleine Gruppen junger Männer oder Athleten“. Es gibt jedoch eine Studie an 99 Freizeitläufern, die die ACSM-Laufformel submaximal mit Extrapolation auf die HFmax prüft: Mittel 39,9 Jahre, 19–66 Jahre, 41 Frauen, Stufen ab 8,0 km/h. Sie fand eine Überschätzung von 7,3 bis 8,1 % bei einem MAPE von 10,8 bis 11,3 %. Es ist Laufband mit Labormessung, kein Smartphone und keine freie Einheit. Die Aussage „keine Quelle prüft das an Freizeitläufern mit Smartphone-GPS“ bleibt also richtig, die Beschreibung der Studienlage aber nicht. Außerdem taugt Q5 (14,6 %) nicht als Beleg für die Überschätzung eines submaximalen Schätzers: Q5 setzt die Formel auf die letzte Stufe eines Bruce-Tests. Dugas zeigt den Unterschied: +20,9 % bei der letzten Stufe, +7 bis 8 % submaximal.
- **Beleg:**
  - Dugas et al. 2023, https://pmc.ncbi.nlm.nih.gov/articles/PMC10747607/: „significantly overestimated VO2max during a submaximal exercise test by 7.3% (ACSMsubmax,Fox) and 8.1% (ACSMsubmax,measured)“.
  - Gegenrichtung beim VO₂-Bedarf: Hall et al. 2004, n = 24, 2,82 m/s, ACSM unter den besten Vorhersagen, https://pubmed.ncbi.nlm.nih.gov/15570150/. Das Dokument führt Hall als nicht auffindbar.
  - Grundlage %HRR gleich %VO₂R: Swain und Leutholtz 1997, n = 63, Rad, stufenweise, https://pubmed.ncbi.nlm.nih.gov/9139182/. Auch dieser Abstract ist abrufbar.
  - Nächste Feldstudie: Parak et al. 2017, n = 24, **Smartphone-GPS**, optischer Puls, freier Lauf ab 20 min, MAPE 5,2 % mit gemessener und 5,9 % mit altersgeschätzter HFmax, Firstbeat-Algorithmus, Autoren bei PulseOn angestellt, https://pmc.ncbi.nlm.nih.gov/articles/PMC5548984.
  - Vergleich für PAR-020: Helm et al. 2021, n = 20, 10–15 min im Freien, MAPE 5,64 %, https://digitalcommons.wku.edu/ijesab/vol14/iss1/29.
- **Korrektur:** Evidenzabschnitt und Validierungsbedarf neu fassen: Die nächstliegende Laborprüfung an Freizeitläufern zeigt +7 bis 8 % und rund 11 % MAPE. Drift senkt die Schätzung, sie gleicht das aber nicht verlässlich aus. Q5 nur als Beleg für den Bereich und den Steady State führen, nicht für die Größe der Überschätzung. Quellenliste und „nicht auffindbar“ aktualisieren (Hall, Swain, Coyle, Witte, FRIEND und Pobiruchin sind über PubMed oder PMC erreichbar). Im Blick behalten: Die Bandbreite ±6 % in PAR-082 ist enger als dieser Fehler.
- **Typ:** Beleg/Text

**M3. PAR-012: Der Beleg stammt aus einem anderen Datenkontext und widerspricht der geplanten Nutzung.**
- **Problem:** Runalyze beschreibt die 3 m für Höhen aus Geländemodell oder Barometer und hält GPS-Höhen für unbrauchbar. Das Dokument zitiert nur „good results“ und die Grenze bei langsamem Anstieg. Die Einstufung `abgeleitet` ist deshalb nicht gedeckt: Kein Rechenschritt führt von dort zu Smartphone-GNSS-Höhen.
- **Beleg:** https://runalyze.com/help/article/2: „elevation data obtained via GPS is unusable and an elevation correction is used by default“ und „Elevation data from a device should only be used if the device has a barometric altimeter included“. Q25 ergänzt für 202 Einheiten: „all devices had considerable errors“; GPS-Geräte unterschätzten den Aufstieg.
- **Korrektur:** Art auf `Heuristik` setzen. Die Einschränkung von Q24 wörtlich aufnehmen und schreiben: „Für GNSS-Höhen nicht geprüft.“ Der Wert bleibt bis zum Feldtest. PAR-012, PAR-013, PAR-026 und PAR-027 fehlen im Validierungsbedarf und gehören dort hinein, weil sie jede VO₂max mitbestimmen.
- **Typ:** Beleg/Text

**M4. PAR-027 (auch PAR-026, PAR-045): Die Steigungskorrektur kann so viel Fehler zufügen, wie sie entfernt.**
- **Problem:** Die eigene Annahme von 10 m Höhenfehler ergibt 1,2 % Steigung auf 840 m, 1,5 % bei 134 m/min und 1,7 % bei 120 m/min. Das liegt schon über der Schwelle von 1 %, ab der `G` eingerechnet wird. Da 1 Prozentpunkt die Schätzung um rund 4 % ändert, kann reines Rauschen die Schätzung um rund 5 bis 7 % verschieben. An der Schwelle springt sie um rund 4 %. Dasselbe Rauschen entscheidet auch über die Zulassung nach PAR-026 und PAR-045. Langsame Läufer trifft es am stärksten.
- **Beleg:** Eigene Rechnung nach FR-0069 mit der Annahme aus PAR-027; Q24 und Q25 wie in M3. Für Smartphone-Barometer gegenüber GNSS habe ich keine belastbare Studie gefunden. Der Vorschlag beruht daher auf dem Rauschvergleich, nicht auf einer Messung.
- **Korrektur:** `G` nur einrechnen, wenn die Höhenänderung des Abschnitts mindestens das Doppelte der gemeldeten Vertikalgenauigkeit beträgt (Heuristik), sonst `G = 0`. Barometerhöhe vorziehen, wenn der Sensor vorhanden ist, und im Feldtest GNSS mit Barometer vergleichen. **Folgen:** Weniger Rauschkorrekturen und weniger zufällige Ausschlüsse, aber kleine reale Steigungen bleiben unkorrigiert (bis rund 1,5 Prozentpunkte, also rund 6 %). Abschnitte ohne Vertikalgenauigkeit gelten nach PAR-027 als ohne verwertbare Höhe. OQ-0019 bleibt gewahrt.
- **Typ:** Wert

**M5. PAR-028: Der wirkungsstarke Wert ist als `abgeleitet` geführt, die Quelle trägt das nicht.**
- **Problem:** Das Handbuch ist eine Bedienanleitung einzelner Modelle, keine Algorithmusangabe. „Reaching at least 70 %“ beschreibt das Erreichen im Lauf, nicht den Mittelwert eines Abschnitts. Das Handbuch der Forerunner 945 nennt gar keine Pulsbedingung. Q2 gibt die Regel anders wieder, nämlich „for the entire exercise“. Die Umrechnung gilt zudem nur für das Beispiel: 70 % HFmax ergibt `r` = 0,43 bei 170/80 und 0,63 bei 200/40. „Etwas mehr oder weniger“ untertreibt das.
- **Beleg:** Q14, Forerunner 570: „reaching at least 70% of your maximum heart rate“, https://www8.garmin.com/manuals/webhelp/GUID-25E3235D-44D2-4384-A591-DD1D71BEBCB1/EN-US/GUID-015C6746-435D-48E0-8ED8-CA2C81684E38.html. Forerunner 945: „Run for at least 10 minutes outdoors.“, https://www8.garmin.com/manuals/webhelp/forerunner945/EN-GB/GUID-015C6746-435D-48E0-8ED8-CA2C81684E38.html. Q2: https://pmc.ncbi.nlm.nih.gov/articles/PMC9213394/.
- **Korrektur:** Art auf `Heuristik` setzen. Der Text nennt Modell, Wortlaut und den Bereich 0,43 bis 0,63 und begründet die 0,55 vor allem mit der eigenen Sensitivitätsrechnung (6,8 % gegenüber 4,9 %, beide korrekt). Der Wert bleibt. Das Modell auch bei PAR-020 nennen.
- **Typ:** Beleg/Text

**M6. PAR-009, PAR-023, PAR-032, PAR-038: Die Art `abgeleitet` täuscht mehr Beleg vor als vorhanden.**
- **Problem:** Laut Lesehilfe folgt ein abgeleiteter Wert aus einer Quellenangabe durch Umrechnung oder einen benannten Rechenschritt. Das trifft hier nicht zu:
  - **PAR-009:** 25 bpm und 5 bpm/s folgen aus keiner Rechnung, sie „liegen darüber“. Zudem ist τ = 30 s nicht aus der Quelle.
  - **PAR-023:** Q33 vergleicht zwei Pulswerte eine Minute auseinander im Radtest, die App zwei Halbmittel über 5–10 min im Lauf. Das ist eine andere Kenngröße.
  - **PAR-032:** Die Untergrenze 25 ist laut Text eine eigene Absicherung. Q1 nennt rund 10, Q15 unterstützt 14–65, und Q35 berichtet bis 97,5.
  - **PAR-038:** Die Zeile bündelt sechs Obergrenzen, und ihre 10 min sind eigene Wahl.
- **Beleg:** Q33: „If minute 2 and minute 3 HR differ by <= 5 bpm“, https://open-exam-prep.com/study-guides/acsm-cpt/chapter-3-client-assessments/cardiorespiratory-fitness-assessments. Q1: „from about 10 ml/kg/min in cardiac patients to close to 90“, https://www.firstbeat.com/wp-content/uploads/2017/06/white_paper_VO2max_30.6.2017.pdf. Die übrigen Fundstellen sind die Zeilen selbst.
- **Korrektur:** Alle vier auf `Heuristik` setzen. Die Begründungen können bleiben. Mit M3 und M5 sinkt `abgeleitet` von 12 auf 6 Zeilen.
- **Typ:** Beleg/Text

**M7. PAR-036, PAR-040: `S` misst bei langen Läufen vor allem Herzdrift, und „gut“ ist dadurch kaum erreichbar.**
- **Problem:** `S` ist die Spannweite. Ein systematischer Pulsanstieg verbreitert sie auch ohne Messfehler, und längere Abschnitte verschlechtern das Ergebnis. Rechnung bei HFR 130, `r` 0,65, Beginn nach 3 min:

  | Drift | S bei 3 × 7 min | S bei 3 × 10 min |
  |---|---|---|
  | 0,2 bpm/min | 3,0 % | 4,3 % |
  | 0,3 bpm/min | 4,5 % | 6,4 % |
  | 0,4 bpm/min | 6,0 % | 8,5 % |
  | 0,6 bpm/min (Wert aus PAR-023) | 8,9 % | 12,4 % |

  Der Grenzwert 5 % ist damit schon vor jedem Rauschen ausgeschöpft. PAR-023 lässt diese Drift ausdrücklich passieren. Ein langer gleichmäßiger Lauf kann so schlechter abschneiden als ein kurzer, obwohl er mehr Daten hat. PAR-043 und PAR-082 hängen an dieser Stufe.
- **Beleg:** Rechnung nach FR-0071; Drift 18,5 bpm von Minute 20 bis 50 in Q30, allerdings „without fan or fluids“ und damit eher ein oberes Szenario, https://pmc.ncbi.nlm.nih.gov/articles/PMC3761905. Auch Q16 entfernt vor der Modellierung den linearen Trend, weil er eine eigene Komponente ist, https://pmc.ncbi.nlm.nih.gov/articles/PMC4687158/.
- **Korrektur:** Ab 3 Abschnitten `S` nach Entfernen eines linearen Zeittrends berechnen und die Drift weiter über PAR-024 begrenzen. Grenzwerte zunächst belassen. Vor dem Festschreiben mit Feldtestdaten die Stufenverteilung prüfen. **Folgen:** „Gut“ wird für lange Läufe erreichbar, FR-0077 bleibt erfüllt, weil die Streuung um den Trend zählt. Bei 2 Abschnitten ändert sich nichts.
- **Typ:** Wert

**M8. PAR-041, PAR-042, PAR-043: Die Stufen des Langzeitwerts widersprechen sich.**
- **Problem:** Laut Abschnitt 4 gilt eine Stufe, wenn alle ihre Bedingungen erfüllt sind. Fünf Läufe, davon drei „gut“, vor 6,5 bis 8 Wochen erfüllen PAR-043 („gut“) und zugleich PAR-041 („vorläufig“: weniger als 3 Läufe in den letzten 6 Wochen). Ein veralteter Wert kann so „gut“ heißen. PAR-042 und PAR-043 sagen zudem nicht, ob „in 6 Wochen“ die letzten Wochen meint. Die zweite Bedingung von PAR-041 („älter als 12 Wochen“) ist wirkungslos, weil dann schon 0 Läufe in den letzten 6 Wochen vorliegen.
- **Beleg:** Zeilen PAR-041 bis PAR-043 und Einleitung von Abschnitt 4 in `docs/model-parameters.md`. PAR-081 prüft die Aktualität für Pace-Vorgaben separat, die angezeigte Stufe bleibt aber falsch.
- **Korrektur:** Alle Fenster als „letzte N Wochen“ festlegen. PAR-041 hat Vorrang, also verlangen „ausreichend“ und „gut“ zusätzlich mindestens 3 Läufe in den letzten 6 Wochen. Die 12-Wochen-Bedingung streichen oder ihr eine eigene Wirkung geben, etwa einen Datenalter-Hinweis. **Folge:** Einzelne Werte fallen früher auf „vorläufig“; Pace-Vorgaben ändern sich nicht wesentlich.
- **Typ:** Wert

**M9. PAR-035: Der Neustart verletzt ein Abnahmekriterium von FR-0078.**
- **Problem:** Nach über 8 Wochen Pause ist `n` = 1, also ersetzt nach PAR-034 ein einziger Lauf den Langzeitwert vollständig. Das kann auch ein vorläufiger Lauf mit nur einem Abschnitt sein. FR-0078 verlangt: „Ein einzelner Ausreißerlauf ändert den Langzeitwert weniger als den Laufwert.“ Die Zeile PAR-034 begründet das `n` nur für den ersten Lauf überhaupt.
- **Beleg:** `docs/specs/vo2max.md`, FR-0078, sowie PAR-034 und PAR-035.
- **Korrektur:** Nach der Pause mit `n` = 2 weiterrechnen, also α = 0,5 bei „gut“ und „ausreichend“ und α = 0,25 bei „vorläufig“. **Folgen:** Ein Ausreißer nach der Pause wirkt nur noch halb oder zu einem Viertel. Nach zwei „guten“ Läufen sind rund zwei Drittel des Abstands aufgeholt, was bei den in S4 genannten Trainingsverlusten ausreicht.
- **Typ:** Wert

**M10. PAR-011, PAR-021: Zwei Regeln sind nicht eindeutig, und das Ergebnis hängt davon ab.**
- **Problem:**
  - PAR-011 löst die 3 min bei einem „Tempowechsel“ aus, nennt aber keine Grenze. Die Regel ist so nicht prüfbar und bestimmt doch den Anteil verwertbarer Zeit.
  - PAR-021 sagt nur „in Abschnitte von 5–10 min teilen“. Eine 20-min-Phase kann 2 × 10 (höchstens „ausreichend“), 3 × 6:40 oder 4 × 5 min („gut“ möglich) ergeben. Die Stufe hinge von der Umsetzung ab.
- **Beleg:** Zeilen PAR-011, PAR-021, PAR-039, PAR-040. Größenordnung für den Tempowechsel: Q16 nutzte ±0,25 m/s „to excite the heart rate dynamics“.
- **Korrektur:** Tempowechsel als Heuristik definieren: 2-min-Mittel weicht um mindestens 0,25 m/s vom vorherigen 2-min-Mittel ab. Teilung festlegen: `k = ⌈L/10 min⌉` gleich lange Abschnitte. **Folgen:** Reproduzierbare Stufen. Eine 20-min-Phase ergibt 2 Abschnitte, „gut“ braucht also mehr als 20 min nutzbare Phase; PAR-040 bleibt formal gleich.
- **Typ:** Wert

### Soll

**S1. PAR-011: Der Geltungsbereich von Hunt ist weiter dargestellt, als die Studie ihn abdeckt.**
- **Problem:** Die Zahlen stimmen (24 Männer, 2 Tests je Person, τ 57,6 ± 23,6 s). Gemessen wurden aber kleine Sprünge von ±0,25 m/s im laufenden Betrieb nach 10 min Aufwärmen und Pause, mit entferntem Trend. Das sagt wenig über Laufstart und Pausen. „Meldet keine Totzeit“ klingt wie ein Befund, das Modell enthält aber gar keine Totzeit. Bei τ + 1 SD (81 s) sind nach 3 min noch 11 % offen, nicht 5 %.
- **Beleg:** „preceded by a 10-min warm up and 10-min of rest“, https://pmc.ncbi.nlm.nih.gov/articles/PMC4687158/.
- **Korrektur:** So ergänzen. „Keine Totzeit“ durch „Modell erster Ordnung ohne Totzeit“ ersetzen. Die 3 min bleiben, für Start und Pause ausdrücklich als Übertragung kennzeichnen. Eine Rechnung zeigt, dass ein Sprung von 90 bpm bei τ = 81 s die Prüfung nach PAR-023 passiert (3,7 bpm Unterschied) und das Abschnittsmittel um rund 2,6 bpm senkt.
- **Typ:** Beleg/Text

**S2. PAR-016: Die fehlende Streuung ist leicht zu belegen.**
- **Problem:** Das Dokument hält die Streuung für nicht verfügbar. Der Grenzwert von 25 bpm lässt sich aber einordnen.
- **Beleg:** Nes et al. 2013, n = 3320: „211 - 0.64·age (SEE, 10.8)“, ältere Formeln unterschätzen ab 30 Jahren, https://pubmed.ncbi.nlm.nih.gov/22376273/.
- **Korrektur:** Einfügen: 25 bpm entsprechen rund 2,3 SEE. Bei 60 Jahren liegt Nes 6,6 bpm über Tanaka, was die Schätzung nach der Rechnung in PAR-038 um rund 5 % senkt. Die Formel selbst bleibt, weil FR-0004 in `specs/profile.md` sie festlegt. Die Lücke „laborbasierte Stichprobe 514“ aus dem Tanaka-Abstract ergänzen.
- **Typ:** Beleg/Text

**S3. PAR-024: Der Beginn der Drift ist belegbar früher, und die Rechnung nennt ihre Herkunft nicht.**
- **Problem:** Die Begründung setzt erst ab Minute 30 an. Coyle und González-Alonso beschreiben den Abfall des Schlagvolumens schon nach 10–20 min. Die Rechnung `r` 0,60 statt 0,648 stammt aus Q8 (4,8 Punkte bei 60 % HRR), steht dort aber direkt hinter Q7. Das „8 %“ von Q7 ist ein Unterschied zwischen zwei Prozentgrößen, und der Mittelwert umfasst die ganzen 40 min. Bei 80 % HRR und 8,6 Punkten ergibt sich rund 9 %.
- **Beleg:** „progressive decline in stroke volume after 10-20 min of exercise“, https://pubmed.ncbi.nlm.nih.gov/11337829/; Q7 https://pubmed.ncbi.nlm.nih.gov/22034854/; Q8 https://pmc.ncbi.nlm.nih.gov/articles/PMC9048681.
- **Korrektur:** Coyle ergänzen, die Herkunft von 0,648 nennen und die Spanne „rund 7 bis 9 %“ angeben. Der Wert bleibt als Heuristik; PAR-024 kann die frühe Drift aber nicht abfangen.
- **Typ:** Beleg/Text

**S4. PAR-035, PAR-041: Q32 behandelt nur Pausen unter 4 Wochen; bessere Quellen sind leicht zu finden.**
- **Problem:** PAR-041 nennt die 12 Wochen „gestützt auf [Q32]“. Q32 ist Teil I und gilt für „less than 4 weeks“.
- **Beleg:** Mujika und Padilla, Teil II: Bei Athleten fällt die VO₂max deutlich, „recently acquired VO2max gains are completely lost“, https://pubmed.ncbi.nlm.nih.gov/10999420/. Coyle et al. 1984, n = 7 Trainierte: −7 % nach 21 Tagen, stabil bei −16 % nach 56 Tagen, https://pubmed.ncbi.nlm.nih.gov/6511559/. Das stützt die Größenordnung von 8 Wochen in PAR-035.
- **Korrektur:** Quellen ergänzen. Bei PAR-041 „gestützt auf“ streichen oder durch die Teil-II-Angabe ersetzen. Die Werte bleiben Heuristik.
- **Typ:** Beleg/Text

**S5. PAR-031, PAR-009, PAR-044: Die Begründung übersieht die Schrittfrequenz und eine passende Zahl aus Q21.**
- **Problem:**
  - PAR-031 sagt, Joggen sei „aus GPS allein“ nicht erkennbar. FR-0202 liefert in Phase 1 die Schrittfrequenz, die Gehen und Laufen trennen könnte. Das gilt auch für PAR-044, das Gehabschnitte im Effizienztrend nicht ausschließt, und für Cadence-Lock in PAR-009 (Puls gleich Schrittfrequenz).
  - Q21 nennt außer dem bevorzugten Übergang auch den energetisch optimalen Übergang von 7,90–8,02 km/h. Das sind 132–134 m/min und passt auffällig zur Grenze in PAR-030. Die Quelle sagt auch, dass Laufen am bevorzugten Übergang mehr Energie kostet als Gehen.
- **Beleg:** `docs/specs/run-recording.md`, FR-0202; Q21 https://pubmed.ncbi.nlm.nih.gov/16286854/; Q4 https://pacompendium.com/unite-conversions/.
- **Korrektur:** In PAR-031 festhalten, dass 120 m/min ein Ersatz für die Gangerkennung ist und die Formel laut Q4 beim Joggen ab 3 mph zulässig wäre. Schrittfrequenz als Prüfgröße in den Validierungsbedarf aufnehmen, ohne die Entscheidung aus OQ-0019 zu ändern. EOTS in PAR-030 oder PAR-031 aufnehmen; für Cadence-Lock habe ich nur die Forenquelle Q36 geprüft.
- **Typ:** Beleg/Text

**S6. PAR-006, PAR-025: Die Rechnung zur GPS-Wirkung deckt nur den Endpunktfehler ab.**
- **Problem:** Das Abschnittstempo entsteht aus der Summe plausibler Distanzen (FR-0049), und das Tempo wirkt linear auf die Schätzung. Messfehler verlängern eine Summe systematisch, abhängig von der Autokorrelation. Es gibt zudem direkte Messungen mit Smartphone und die Android-Geschwindigkeit als mögliche Alternative. Das Dokument erwähnt das nicht.
- **Beleg:** Ranacher et al. 2016, https://pmc.ncbi.nlm.nih.gov/articles/PMC4786863/. Benson et al. 2016, iPhone, n = 38: Durchschnittsgeschwindigkeit −2 %, Distanz −1,9 %, https://pubmed.ncbi.nlm.nih.gov/26505223/. Witte und Wilson 2004: Genauigkeit der Geschwindigkeit bleibt bei schlechter Position erhalten, Fahrrad-GPS, https://pubmed.ncbi.nlm.nih.gov/15519597/. Q9 nennt `getSpeedAccuracyMetersPerSecond`.
- **Korrektur:** Diese Quellen ergänzen und als Fehlerposten nennen. Im Validierungsbedarf Abschnittstempo gegen bekannte Strecke um `Location.getSpeed()` als Vergleich erweitern. FR-0050 bleibt unberührt.
- **Typ:** Beleg/Text

**S7. PAR-001, PAR-025: Q10 und Q11 sind ungenau wiedergegeben.**
- **Problem:** Q10 nennt für 7–13 m RMSE je Messperiode an festen Punkten auf einem Campus, keine „mittleren Fehler“ im Lauf. Q11 berichtet „unter 5 m“ nur für Samsung; Pixel wurde im Außen-Gehdatensatz nicht gemessen, und nahe an Gebäuden lag der Samsung-Median bei 8,4 m. PAR-025 vergleicht zudem den gemeldeten 68-%-Radius mit einem wahren RMSE.
- **Beleg:** https://pmc.ncbi.nlm.nih.gov/articles/PMC6638960/; https://arxiv.org/html/2603.26706v1: „both P8 and P10 were not measured in the outdoor walking dataset“.
- **Korrektur:** Wortlaute korrigieren und den Vergleich beider Größen als grobe Orientierung kennzeichnen. Für PAR-033 festhalten, dass „≤ 5 m“ nur für offenes Gelände und Samsung belegt ist. Die Validierung gerätebezogen auslegen.
- **Typ:** Beleg/Text

**S8. PAR-023, PAR-029: Ein Lernportal lässt sich durch eine Fachquelle ersetzen.**
- **Problem:** Q33 und Q34 sind Lernportale. Eine Originalarbeit gibt dieselbe Regel als Protokoll nach einer ACSM-Stellungnahme wieder und liefert auch die Obergrenzen.
- **Beleg:** Dugas 2023, „steady HR attainment on each level (±5 bpm between the end of the 2nd and 3rd minute)“ und „≥70% reserve HR or ≥85% age-predicted HRmax“, https://pmc.ncbi.nlm.nih.gov/articles/PMC10747607/.
- **Korrektur:** Dugas ergänzen und PAR-029 um den Vergleich mit 70 % HRR erweitern: 0,85 ist deutlich weiter als diese Protokolle. Das ist zulässig, weil als Heuristik gekennzeichnet.
- **Typ:** Beleg/Text

**S9. PAR-034: Die Aussage zum Folgen des Anstiegs gilt nicht für alle Stufen.**
- **Problem:** Der Wert „soll“ dem Zuwachs bei drei Läufen pro Woche folgen können. Q1 sagt „by up to 10-20%“. Rechnung mit linearem Anstieg, Rückstand am Ende:

  | Anstieg | „gut“ | „ausreichend“ | „vorläufig“ |
  |---|---|---|---|
  | 20 % in 12 Läufen | 6,8 % | 8,1 % | 11,3 % |
  | 10 % in 30 Läufen | 1,8 % | 2,6 % | 4,5 % |

  Anfänger laufen oft „vorläufig“ (siehe M1), hier ist der Rückstand am größten.
- **Beleg:** Rechnung nach PAR-034; Q1 https://www.firstbeat.com/wp-content/uploads/2017/06/white_paper_VO2max_30.6.2017.pdf.
- **Korrektur:** „up to“ wiedergeben und die Rückstände nennen. Der Wert bleibt; im Validierungsbedarf gezielt Einsteiger prüfen.
- **Typ:** Beleg/Text

**S10. PAR-048: Die Angabe zu Friel ist für das Laufen nicht gedeckt.**
- **Problem:** „Ohne Auf- und Abwärmen“ steht im Artikel nur beim Radfahren. Die Quelle beschreibt zudem ein Trainingsziel für die Grundlagenphase und keine Mindestdauer für eine Messung. Die Einstufung `abgeleitet` ist haltbar, weil 60 min das untere Ende der Spanne ist.
- **Beleg:** „the practical range is typically one to two hours at aerobic threshold“, https://www.trainingpeaks.com/learn/articles/aerobic-endurance-and-decoupling/.
- **Korrektur:** Den Zusatz streichen, dafür den Zweck der Quelle nennen.
- **Typ:** Beleg/Text

**S11. PAR-003: Die Regel greift bei 1 Hz praktisch nie.**
- **Problem:** Mit zwei Punkten bei je 5 m Genauigkeit braucht die Regel über 30 m Distanz. Bei 8 bis 12,5 m/s setzt das mindestens 2,4 s Abstand voraus; in 1 s wären es über 30 m/s, die PAR-002 schon verwirft. Bei schlechterer Genauigkeit (10 m) sind es 4,8 s. Gerade verrauschte Punkte schützt das, und Sprünge von 8 bis 12,5 m in 1 s bleiben erhalten. Die Rechnung nimmt 1 Hz an, was das Dokument nicht festlegt.
- **Beleg:** Rechnung nach PAR-002 und PAR-003.
- **Korrektur:** Vorschlag: Faktor 1 statt 3. Bei je 5 m greift die Regel dann ab 10 m. **Folgen:** Kleine Sprünge fallen weg; echte Geschwindigkeiten über 8 m/s bei sehr guter Genauigkeit können verworfen werden, was für die Zielgruppe kaum vorkommt. Vor dem Festschreiben mit Rohdaten prüfen oder die Regel streichen.
- **Typ:** Wert

**S12. PAR-019: Die Begründung trägt die Folge für TRIMP und Eingabe nicht.**
- **Problem:** Die Begründung betrifft nur `r`. Durch „wie PAR-018“ ist aber auch TRIMP nicht verfügbar, obwohl OQ-0012 festhält „TRIMP braucht nur HFmax“, und eine neue Eingabe wird nicht gespeichert. OQ-0019 regelt dies nur für HFmax ≤ HFRuhe. Bei einem echten Wertepaar unter 50 bpm Reserve, etwa unter Medikamenten, auf die PAR-016 ausdrücklich Rücksicht nimmt, wird die Eingabe abgewiesen.
- **Beleg:** `docs/migration/open-questions.md`, OQ-0012 und OQ-0019; `docs/specs/training-load.md`, Abnahmekriterium zu PAR-018 und PAR-019.
- **Korrektur:** Bei 0 < HFR < 50 Eingabe speichern und `r`, Reservezonen, VO₂max und aerobe Effizienz als nicht verfügbar führen, TRIMP aber weiter berechnen. **Folge:** `training-load.md` ist anzupassen.
- **Typ:** Wert

**S13. PAR-044, PAR-046: Die Übernahme der VO₂max-Regeln passt nicht ganz zur Kennzahl.**
- **Problem:** PAR-044 übernimmt PAR-024 samt halbem Gewicht ab Minute 30, FR-0085 nutzt aber einen ungewichteten Median. Das Gewicht ist hier nicht definiert. Bei PAR-046 reichen 3 Abschnitte nur, wenn alle die Höchstlänge von 10 min haben, weil die Summe ≥ 30 min verlangt ist.
- **Beleg:** `docs/specs/aerobic-efficiency.md`, FR-0085; Zeilen PAR-021, PAR-024, PAR-044, PAR-046.
- **Korrektur:** Bei PAR-044 nur den Ausschluss ab Minute 60 übernehmen oder den Median ausdrücklich gewichten. Bei PAR-046 entweder 25 min Summe oder den Effekt ausdrücklich nennen. **Folge:** Etwas mehr Abdeckung beim Trend.
- **Typ:** Wert

**S14. PAR-038, PAR-039: Die Summenbedingung ist überflüssig.**
- **Problem:** Da jeder Abschnitt mindestens 5 min dauert (PAR-020), haben 2 Abschnitte immer mindestens 10 min. „Summe unter 10 min“ tritt nur bei einem Abschnitt auf, der ohnehin begrenzt ist.
- **Beleg:** Zeilen PAR-020, PAR-038, PAR-039.
- **Korrektur:** Bedingung streichen oder den Grund für eine höhere Summe nennen.
- **Typ:** Beleg/Text

**S15. PAR-017, PAR-030: Zwei Quellenbeschreibungen sind ungenau.**
- **Problem:** Q19 stammt laut Quelle aus den USA, nicht „vor allem USA“. Die 39,7–108,6 bpm sind Mittelwerte einer Tracker-Ruhepulsgröße und keine typische Selbsteingabe. Q3 prüft nicht „nur bei Herzpatienten“: 54 Gesunde dienten der Modellentwicklung, 47 Patienten der Validierung.
- **Beleg:** https://pmc.ncbi.nlm.nih.gov/articles/PMC7001906; https://pmc.ncbi.nlm.nih.gov/articles/PMC12419060/.
- **Korrektur:** Wortlaut anpassen. Bei PAR-030 `belegt (Sekundärquellen)` schreiben, damit die Einschränkung in der Art sichtbar bleibt.
- **Typ:** Beleg/Text

---

## Geprüft ohne Befund

| Quellen | Zeilen | Ergebnis |
|---|---|---|
| Q2 | PAR-020, PAR-039, PAR-040 | 10 min Fitbit und Garmin, ≥ 10 % als Grenze früherer Studien, 8–10,2 % MAPE stimmen. |
| Q1 | PAR-020, PAR-024, PAR-026, PAR-032, PAR-033, PAR-038 | 75 % nach 2 km, Drift und Gefälle, „close to 90“, 7–9 % bei 15 bpm, keine offengelegte Gewichtung stimmen. |
| Q4, Q5 | PAR-030, PAR-031 | Wortlaut stimmt. Zur Verwendung siehe M2 und S5. |
| Q6, Q7, Q8 | PAR-024, PAR-029 | Stichproben, Richtung, 0,7 und 4,8–8,6 Punkte, p-Wert der Wechselwirkung stimmen. |
| Q9, Q12, Q13, Q15, Q37 | PAR-001, PAR-005, PAR-013, PAR-014, PAR-015, PAR-032, PAR-041 | 68. Perzentil, keine Strava-Zahl offiziell, Forumszitat, Apple 14–65 und „several“ stimmen. |
| Q14 | PAR-020 | 10 min stimmen; Modell ergänzen (M5). |
| Q16, Q18, Q19 | PAR-011, PAR-016, PAR-017, PAR-022 | Alle Zahlen stimmen. |
| Q20 | PAR-002 | 44,72 km/h zwischen Meter 60 und 80 stimmt. Wikipedia gibt die IAAF-Studie an. |
| Q21, Q22, Q23, Q25, Q26 | PAR-012, PAR-014, PAR-026, PAR-031, PAR-040 | Zahlen stimmen, auch 17 Athleten und 2,0 bei 58,2. |
| Q27, Q28, Q29 | PAR-006, PAR-007, PAR-008, PAR-009, PAR-010 | 30–60 s, −13,7 bis 14,6 bpm, Statusbit, etwa 1 Sendung pro Sekunde stimmen. |
| Q30, Q31, Q33, Q34, Q35, Q36 | PAR-009, PAR-023, PAR-029, PAR-032, PAR-048 | Zahlen und Wortlaute stimmen, die Quellen sind wie im Dokument gekennzeichnet. |

Die Heuristiken sind als solche gekennzeichnet, was ausdrücklich zulässig ist. PAR-001 bis PAR-008, PAR-010, PAR-013 bis PAR-015, PAR-018, PAR-020, PAR-022, PAR-033, PAR-037 und PAR-042 sind außerhalb der genannten Befunde unauffällig.

## Nachgerechnet

| Zeile | Ergebnis |
|---|---|
| FR-0069, FR-0071 | 36,83 und 51,65 korrekt |
| PAR-002, PAR-003 | 12,42 m/s; 2:05 min/km; 30 m korrekt |
| PAR-004, PAR-005, PAR-014 | 30 m; 60 m; 0,89 m/s korrekt |
| PAR-009, PAR-011 | 1,72 und 3,33 bpm/s; 172,8 s und 95,0 % korrekt |
| PAR-019, PAR-022, PAR-023 | 10 Punkte; 8,3 %; 0,62 bpm/min und 3,1 bpm korrekt |
| PAR-024, PAR-025, PAR-026, PAR-027 | 7,0 %; 2,4 %; 4,1 %; 1,2 % korrekt |
| PAR-028, PAR-029 | `r` 0,56; 6,8 %; 4,9 %; `r` 0,78 korrekt |
| PAR-030, PAR-031 | 8,04 km/h; 2,23 m/s; 7:28; 7,2 km/h; 8:20; 103 m/min korrekt |
| PAR-032 | Untergrenze 29,2 korrekt, weitere Grenzen siehe M1 |
| PAR-034 | Halbwertszeiten 4,3, 6,6 und 13,5; 0,5–1,5 % korrekt |
| PAR-038, PAR-040, PAR-043, PAR-045 | ±7,2 %; 3,4 %; 55,6 %; 5,6 % korrekt |
