# R009 – Ergebnis

## Kurzfassung
**Ruhepuls mit der Kamera (FR-0214) ist gut gedeckt.** In Ruhe stimmt der Fingerpuls aus der Kamera auf etwa ±2/min mit dem EKG überein [B7, B2, B8]. 60 s reichen dafür. Ruhepuls heißt hier: Ruhe vorher, immer dieselbe Haltung, kein Koffein vorher. Er ist nicht der Schlafpuls einer Uhr [A10].

**RMSSD aus 60 s Kamera ist gemischt belegt, die direkteste Studie spricht eher dagegen.** Das Messfenster an sich trägt: 60 s gegen 5 min ergibt lnRMSSD mit LoA ±0,22, gemessen liegend mit EKG [A5]. Zur Kamera selbst:
- **Dafür:** Plews 2017 fand mit einer Kamera-App über **5 min** TEE 6,35 % und r = 1,00 [B1]. Van Dijk 2023 fand über 5 min mit langsamer, geführter Atmung ICC > 0,90 für lnRMSSD ohne proportionalen Bias [B20, nur Abstract]. Moya-Ramon 2022 fand mit Apps über 1 min r = 0,77–0,94 und SEM < 6 %, aber ohne LoA [B5]. Altini und Plews nutzten 1-min-Kameramessungen für eine große Feldstudie, ohne EKG-Vergleich [C10].
- **Dagegen:** Holmes 2020 maß genau diesen Aufbau, **60 s Finger auf Kamera und Blitz** gleichzeitig mit EKG (n = 31, sitzend). Die Kamera lag immer zu hoch, Bias ± LoA in Ruhe 0,19 ± 0,95 bis 0,34 ± 1,12 ln [B19]. Peng 2015 (20–30 Bilder/s, 5 min) überschätzte RMSSD deutlich [B3]. Laborde 2017 rät „for research purposes“ von Kamera-Apps ab, weil die Abtastrate zu niedrig sei; das ist eine Expertenmeinung ohne eigene Messung [A2].
- Bei Holmes zeigte die Teilmenge mit „optimaler“ Signalgüte kleinere mittlere Differenzen (0,32 / 0,16 / 0,10 / 0,09 ln). Das stützt eine strenge Qualitätsgrenze für RMSSD.

**Tageswerte nur als 7-Tage-Mittel bewerten.** Das stützt die Literatur, ebenso mindestens 3 Messungen pro Woche (bei Freizeitsportlern eher 5), eine Basis von 2–4 Wochen und die Grenze „Mittel ± 0,5 SD“ [C1–C5, C8, C13]. Die Tagesstreuung von lnRMSSD liegt bei einer SD von etwa **0,3–0,4 ln** [C13; Plews, Dissertation S. 98], das sind je SD rund +35 bis +49 % bzw. −26 bis −33 % RMSSD. Die Rechnungen zeigen, was die Kamera kosten darf: Eine Messstreuung von der halben Tagesstreuung kostet wenige Prozentpunkte Erkennung, eine gleich große etwa 12 Punkte. Bei einer Tages-SD von 0,33 ln heißt „halb so groß“: SD der Kamera-Abweichung je Messung höchstens **≈ 0,16 ln, also etwa +18 % / −15 % RMSSD** (LoA etwa +38 % / −28 %). Holmes fand zwischen Personen eine SD der Differenz von 0,42–0,57 ln [B19]. Das läge deutlich darüber; innerhalb einer Person ist die Streuung aber kleiner, wie viel, ist offen.

**Empfehlung:**
- WP27 übernimmt das Protokoll unten für FR-0214 (Vorgabe liegend, sitzend wählbar als eigene Reihe, E5).
- FR-0215 wird **mit Auflage** freigegeben. Der Kamera-Ruhepuls geht sofort in die eingeschränkte Einschätzung ein und erscheint dort als Tatsache. RMSSD geht erst in die Readiness ein, wenn die Validierung gegen Polar H9 bestanden ist (Abschnitt 6: 28 Morgen mit wochenweiser Kreuzvalidierung, n = 1) **und** der Nutzer es per Opt-in einschaltet (E2).
- **Folgen des Validierungsergebnisses (E7):** lnRMSSD „eingeschränkt“ zählt wie „nicht bestanden“: RMSSD bleibt gesperrt und erscheint nur als markierte Tatsache (E7a). Der Ruhepuls bleibt bei „bestanden“ und „eingeschränkt“ (LoA innerhalb ±3/min) in Gebrauch. Bei „nicht bestanden“ geht er in keine Zahl und keinen Faktor ein; er erscheint in der eingeschränkten Einschätzung nur noch als markierte Tatsache („ungenauer als erwartet“) und gilt weiter für das Profil (FR-0214) (E7b). Freigegeben wird das **Verfahren** (Algorithmus und Protokoll), nicht ein Gerät (E7c). Eine erneute Validierung nach „eingeschränkt“ oder „nicht bestanden“ ist nur nach einer dokumentierten Änderung des Verfahrens erlaubt; ein Gerätewechsel allein löst keinen neuen Lauf aus.
- **Folge für M3, ausdrücklich:** Nach OQ-0006 (heutige wie neue Fassung) braucht eine Zahl eine HRV. Solange Kamera-RMSSD gesperrt ist, gibt es **ohne Uhr keine Zahl**, nur die eingeschränkte Einschätzung. Bei „eingeschränkt“ oder „nicht bestanden“ bleibt das so, bis eine erneute Validierung nach einer dokumentierten Änderung des Verfahrens bestanden ist (E7a, E7c). Nach der Literatur (Holmes 2020) ist ein Nichtbestehen gut möglich, nach Rechnung D auch ein „eingeschränkt“. „Readiness ohne Uhr“ in M3 heißt dann: Morgenmessung, Ruhepuls-Trend (nach Puls „nicht bestanden“ nur als markierte Tatsache „ungenauer als erwartet“, E7b) und eingeschränkte Einschätzung, keine Zahl.
- Für M3 eine neue Regelversion (Vorschlag „K-1“, Abschnitt 5). **Der Maintainer hat am 2026-11-09 entschieden** (Abschnitt 5a):
  - E1: ohne Uhr nur die eingeschränkte Einschätzung, solange RMSSD gesperrt ist.
  - E2: nach bestandener Validierung Kamera-RMSSD nur per Opt-in als „experimentell“; eine Prüfung je Nutzer mit Gurt kann später dazukommen.
  - E3: die neue Fassung von OQ-0006, Schlafdauer aus Uhr oder freiwilliger Angabe in Stufen.
  - E4: PAR-169 bleibt, am Morgen nur Messung und Schlafdauer in Stufen (kein Schlafgefühl).
  - E5: Haltung liegend als Vorgabe, sitzend wählbar als eigene Reihe.
  - E6 (vorerst): Das Opt-in gilt nach einer liegend bestandenen Validierung auch sitzend, dort mit „liegend verglichen“; eine eigene Validierung im Sitzen ist empfohlen (Offene Punkte 4).
  - E7: Folgen von „eingeschränkt“ und „nicht bestanden“ für RMSSD (E7a) und Ruhepuls (E7b, bei „nicht bestanden“ nur markierte Tatsache); freigegeben wird das Verfahren, nicht ein Gerät, eine erneute Validierung nur nach dokumentierter Änderung des Verfahrens (E7c).
  - Das Konzept ändert der Project Supervisor.

## Lauf
- **Datum:** 2026-11-09. **Rechner:** Mac, Apple M3 Pro (arm64), macOS, Python 3.15.0, nur Standardbibliothek.
- **Kommando:** `./init.sh && ./run.sh --seed 1 --reps 4000`. Lauf `research/data/work/R009/20261109-212401/` auf Commit `052f564` (`dirty=0`). Laufzeit 61 s (A 5 s, B 8 s, C 1 s, D 47 s).
- **Nachbesserung 1 (2026-11-09):** Rechnung D neu (Trennschärfe der Akzeptanzkriterien), in B der Fall B4 (Tagesstreuung 0,33 ln). In A entfällt die lnRMSSD-Tabelle, weil ihr festes Δ keinem Kriterium entsprach. Alle übrigen Tabellen von A, B und C sind mit dem ersten Lauf (`20261109-205242`, Commit `171378a`) bitgleich.
- **Nachbesserung 2 (2026-11-09):** keine neue Rechnung. Entscheidung E7 des Maintainers eingearbeitet (Folgen von „eingeschränkt“ und „nicht bestanden“, erneute Validierung). Validierungsplan: Quote an den Mindestumfang gebunden (≥ 22 von 28 Referenzmorgen), Verlängerung nur für fehlende Referenzmorgen, keine Zwischenauswertung. Teil D unverändert, weil sein Design (22 Prüftage, Tages-SD aus 28 Tagen) genau dem Mindestumfang entspricht; zur Kontrolle `./run.sh --seed 1 --reps 4000 --part D` neu gelaufen (Lauf `20261109-220151`, Basis `e5abdd6`, `dirty=1` nur durch RESULTS.md, Code unverändert, 56 s): alle Werte von D1, D1b und D2 gleich wie in Abschnitt 6. In `D.txt` heißt die Zeile mit 22 von 28 Prüftagen noch „80 % gültig“; gemeint ist der Mindestumfang 22 von 28 (78,6 %). Van Dijk 2023 [B20] ergänzt, MAD-Begründung eingeschränkt.
- **Nachbesserung 3 (2026-11-09):** keine neue Rechnung, keine Zahl der Rechnungen geändert. Entscheidungen des Maintainers eingearbeitet: E7c (freigegeben wird das Verfahren, nicht ein Gerät; erneuter Lauf nur nach dokumentierter Änderung des Verfahrens) und die Auslegung von E7b (Puls „nicht bestanden“ als markierte Tatsache). Markierung für RMSSD nach einem Fehlschlag ergänzt, Regel zum nicht durchgeführten Lauf ergänzt. Nuuttila 2024 [C13], Tabelle 1, selbst am Volltext nachgeprüft: Puls-CV morgens liegend 6,8 ± 2,4 % (Bereich 4,1–12,8 %) bei 52,8 ± 8,2/min.
- **Literatur:** im Original geprüft, je Quelle vermerkt, ob Volltext oder nur Abstract (Quellenliste am Ende). Drei Teilrecherchen liefen parallel als Sub-Agenten. Kernstellen habe ich selbst nachgeprüft: Bánhalmi, Tabelle 1, Esco und Flatt 2014, Ergebnisse, und in Nachbesserung 1 Holmes 2020 (Methoden, Tabellen 1 und 2), Altini und Plews 2021, Buchheit 2014 und Laborde 2017 (Zitate) sowie das Abstract von Flatt und Esco 2016 (LoA).
- **Kontrollen im Code:**
  - t-Quantile gegen Tabellenwerte (Assertion).
  - Handrechnung KI bei n = 21.
  - Erwartete MAD = 0,6745·SD.
  - Aufschlag durch Zeitrauschen analytisch: RMSSD'² ≈ RMSSD² + 6·σ_t².
  - R8 nachgerechnet: SD von `z` bei AR 0 / 0,3 / 0,6 hier 1,06 / 1,30 / 1,69, in R8 1,05 / 1,31 / 1,70.
  - Teil D gegen die unabhängige Simulation aus Review-Runde 1: Verhältnis 0,7 besteht bei 28/14/10 Tagen zu 4/10/14 %, Verhältnis 0,5 bei 28 Tagen zu 47 %; D ergibt dieselben Werte.
  - Teil D: Scheinsteigung der Differenz gegen den Mittelwert bei fehlendem proportionalem Bias analytisch 0,118, simuliert 0,120–0,129.
  - B4: Mit Fehlmessung +4·sb ist der Fall sb 0,33 bitgleich mit sb 0,10 und +0,4. Das bestätigt, dass B nur von den Verhältnissen abhängt.

## 1. Messprotokoll (Literatur)

| Punkt | Befund | Quellen | Vorschlag |
| --- | --- | --- | --- |
| Zeitpunkt | Bewährt ist eine kurze Messung direkt nach dem Aufwachen: „the best practice for athletes tends to be short-term (5–10 min) measurements of HR(V) upon awakening in the morning“. Gemeint sind dort 5–10 min, nicht 60 s; für 60 s siehe Zeile „Dauer“ [A5]. Die Studien messen im Liegen nach dem Aufwachen. | [A1, C3, C10] | Morgens nach dem Aufwachen, jeden Tag zur ähnlichen Zeit. |
| Toilette, Koffein | Laborempfehlung: vorher zur Toilette, 2 h kein Kaffee, kein Essen. Eine Feldstudie mit Messung zu Hause beim Aufwachen: „on an empty bladder“, ohne Koffein und Nikotin. Für die Reihenfolge Toilette dann Messung gibt es keine Sportstudie mit eigener Begründung. | [A2, A4] | Erst Toilette, dann messen, vor Kaffee und Frühstück. Gleiche Reihenfolge jeden Tag (eigene Wahl). |
| Haltung | Liegend ist am besten untersucht und streut am wenigsten: CV lnRMSSD liegend 8,2 %, stehend 16,1 %. Sitzend ist bequem und man schläft nicht wieder ein, dazu gibt es aber keine Zahlen. Die Abweichung der Kamera zum EKG wächst von liegend über sitzend zu stehend (60 s, externer Fingersensor). Stehend ist der Puls rund 25/min höher. | [A1, C13, B6, A4, B11] | Wählbar liegend oder sitzend, **Vorgabe liegend**, nie stehend. Sitzend ist eine eigene Reihe; wechselt die Haltung, beginnt eine neue Reihe (FR-0115). Entschieden vom Maintainer 2026-11-09 (E5). |
| Ruhephase | Liegend, EKG: Die 1-min-Stücke aus den ersten 5 min stimmten mit dem lnRMSSD aus Minute 5–10 überein, ICC 0,92–0,97, aber LoA ±0,28 bis ±0,45 ln, also deutlich breiter als ±0,22 nach Ruhe [A5]. Die Autoren folgern, 1 min Stabilisierung reiche (nur Abstract). Im Labor gelten „at least 5 min“ in der Haltung. Holmes 2020 nutzte 5 min [B19]. Für den Puls nach dem Aufstehen zur Toilette fand ich keinen Beleg für 1–2 min. | [A6, A2, B19] | Morgenmessung: **Vorgabe 2 min**, jeden Tag gleich. Für lnRMSSD ist das schwach belegt, für den Puls nach dem Gang zur Toilette eine **Annahme**; die Validierung prüft es mit. Profil tagsüber (FR-0214): **≥ 4–5 min**; die 4 min aus FR-0214 liegen knapp unter Labordes 5 min. |
| Atmung | Spontane Atmung ist Konsens für Ruhemessungen. RMSSD reagiert wenig auf das Atemmuster. Geführte und spontane Atmung unterschieden sich aber signifikant, korrelierten jedoch (r > 0,70). Langsame Atmung erhöht vagal vermittelte HRV während der Übung **und direkt danach** (Metaanalyse, nur Abstract). | [A2, A1, A7, A8] | Während der Messung **spontan atmen**. Die beruhigende Anleitung aus FR-0214 ohne vorgegebenes Atemtempo (keine 6/min), immer gleich lang. Für die Morgenreihe sonst Verzerrung nach oben, die je nach Tag unterschiedlich lang wirkt. |
| Dauer 60 s vs. 5 min | lnRMSSD aus 60 s gegen 5 min (liegend, EKG, morgens, Spontanatmung): ICC 0,98, Bias ± LoA 0,00 ± 0,22. Fingerpuls (Portapres) 30 s gegen 4–5 min: r = 0,93, LoA −0,34 bis +0,45. Einschränkung: Die kurzen Stücke stammen aus derselben Aufnahme; das gilt als methodisch schwach („a correlate does not make a surrogate“). Die Task Force bevorzugt 5 min, RMSSD sei aber kurz messbar. | [A5, A9, A11, A3] | **60 s** bleiben (FR-0214). Für den Puls unkritisch. Für RMSSD trägt die Fensterlänge, nicht aber die Kamera (siehe 3). |
| ln RMSSD | Log-Transformation wegen ungleicher Varianz: „natural logarithm of RMSSD“. Sie ist in allen Monitoring-Studien Standard. | [A2, C1–C4] | Auswertung auf `ln(RMSSD)`, wie PAR-161. |
| Wiederholen | In keiner Quelle geregelt. Wählt man die beste von mehreren Messungen, verzerrt das die Reihe (eigene Überlegung). | – | Es zählt **die erste Messung mit ausreichender Qualität**. Wiederholen nur, wenn die Qualität nicht reicht. |

Rechnung C dient als Plausibilitätsprüfung für die Fensterlänge. In einer stationären synthetischen Reihe streut ln RMSSD(60 s) gegenüber ln RMSSD(300 s) mit SD 0,069. Das ergibt LoA ±0,14 und ist eine Untergrenze. Die Literatur nennt ±0,22 [A5], also eine SD von etwa 0,11. Das passt: Echte Reihen sind nicht stationär.

## 2. Ruhepuls: Definition, morgens oder tagsüber, Haltung
- Eine verbindliche Definition aus erster Hand habe ich nicht gefunden. Das ESH-Konsenspapier von 2006 ist kostenpflichtig und nicht geprüft. Das ESH-Papier von 2016 (nur Abstract) verlangt anzugeben: Länge der Ruhe vorher, Methode, Dauer, Anzahl der Messungen und Körperhaltung [A12]. Daraus folgt nur: Diese Bedingungen festlegen und gleich halten.
- Der Tracker-Ruhepuls von Fitbit wird „primarily calculated during periods of sleep“ [A10]. Er ist also nicht derselbe Wert wie ein Ruhepuls im Wachzustand. FR-0115 gilt deshalb auch für den Ruhepuls: Kamera und Health Connect bilden getrennte Reihen.
- Die Haltung wirkt groß: liegend gegenüber stehend rund 25/min [A4]. Der Morgenwert liegend ist der niedrigste und am besten reproduzierbare Wert. Ein Ruhepuls tagsüber im Sitzen liegt höher (Richtung belegt, Größe für sitzend nicht).
- **Für das Profil (FR-0214):** Der Wert dient der Zonenberechnung, Haltung und Zeitpunkt werden mit gespeichert. Vorschlag: Liegen Morgenmessungen vor, schlägt die App den Median der letzten 7 gültigen Morgenwerte vor, statt eines Einzelwerts tagsüber (eigene Wahl; die Streuung von Tag zu Tag ist groß, CV im Mittel 6,8 % liegend [C13], wöchentliche Schwankung im Median 3/min [A10]).

## 3. Smartphone-PPG gegen EKG in Ruhe, PRV ≠ HRV

| Studie | Aufbau | Puls | RMSSD / lnRMSSD | Zugriff |
| --- | --- | --- | --- | --- |
| Bánhalmi 2018 [B2] | n = 50, sitzend, 5 min, iPhone 6 mit **240 fps**, strenge Artefaktfilter (±20 % vom Median) | Bias 0,03, SD 0,11/min | RMSSD Bias +2,5 ms, SD 1,8 ms; ln Bias +0,10, SD 0,15 (LoA −0,20 bis +0,40) | Volltext, selbst nachgeprüft |
| Peng 2015 [B3] | n = 30, liegend, ≥ 5 min, **20–30 fps** schwankend, auf 800 Hz interpoliert | AVNN −0,05 ± 0,55 ms | RMSSD **+33 bis +68 ms** zu hoch (je nach Gipfelerkennung), „insufficient agreement“ | Volltext |
| **Holmes 2020 [B19]** | n = 31, **sitzend, 60 s** nach 5 min Ruhe, spontane Atmung, iPhone 6 mit HRV4Training, **Finger auf Kamera und Blitz**, gleichzeitig EKG; bis zu 3 Versuche für gute Signalgüte | – | lnRMSSD in Ruhe (4 Messungen): Bias ± 1,96 SD 0,34 ± 1,12 / 0,23 ± 1,03 / 0,19 ± 0,95 / 0,28 ± 0,83, r = 0,59–0,76, Kamera immer zu hoch („Significant, small–moderate differences“). Nur „optimale“ Signalgüte (n = 19–22): mittlere Differenz 0,32 / 0,16 / 0,10 / 0,09. Trend der Differenz zum Mittel r = −0,08 bis −0,13 (kaum proportionaler Bias). Nach Belastung 0,98 ± 0,96 | Volltext, selbst nachgeprüft |
| van Dijk 2023 [B20] | n = 57, Labor, Handykamera (Happitech-SDK) gegen EKG (NeXus), **5 × 5 min geführte Zwerchfellatmung** mit 6,5 bis 4,5 Atemzügen/min (Biofeedback) | – | ln-transformierte RMSSD: ICC „near perfect“ (> 0,90) bei allen Atemtempi, kein systematischer proportionaler Bias. Bland-Altman: gute Austauschbarkeit, über alle vier Indizes zusammen drei vereinzelte Ausnahmen (im Abstract keinem Index zugeordnet). Bias und LoA nicht im Abstract. Stützt die „Dafür“-Seite, aber 5 min und langsame geführte Atmung (große, regelmäßige RR-Schwankungen), nicht wie das Protokoll hier | nur Abstract (Repositorium VU Amsterdam) |
| Plews 2017 [B1] | n = 29, Ruhe, **5 min** (nicht 60 s), HRV4Training-Kamera | – | TEE 6,35 % (90 % KI 5,13–8,5), r = 1,00 | nur Abstract |
| Esco 2017 [B6] | n = 30, **60 s**, liegend/sitzend/stehend, App mit Pulssensor (laut [B2] externer Infrarot-Fingersensor, keine Kamera) | – | lnRMSSD×20: LoA −0,13 ± 2,83 / −0,94 ± 3,47 / −1,37 ± 3,56, umgerechnet ≈ ±0,14 / ±0,17 / ±0,18 ln | nur Abstract |
| Moya-Ramon 2022 [B5] | n = 26 Radprofis, 1 und 5 min, liegend/sitzend, Apps | – | r = 0,77–0,94, SEM < 6 %, keine LoA im Abstract | nur Abstract |
| Yan 2017 [B7] | n = 40, 20 s, Finger und Gesicht | LoA in Ruhe −1,98 bis +2,07/min | – | Volltext |
| Guede-Fernández 2015 [B4] | Android, 30 Hz | – | Fehler je Schlag bis 7,8 ± 3,8 ms, deutlicher Einfluss des Geräts | nur Abstract |

**PRV ≠ HRV:** In Ruhe ist PRV ein ausreichender Ersatz, „although … short-term variability is somewhat overestimated by PRV“. Bei Belastung und Stress wird die Übereinstimmung schlechter [B10, nur Abstract]. Haltungswechsel und Umgebungstemperatur verändern das Verhältnis, ebenso eine niedrige, ungleichmäßige Bildrate der Kamera [B11]. Bei gesunden, jungen Personen in Ruhe gilt PRV als Alternative [B11]. Die Abweichung zeigt durchgehend nach oben: [B2, B3, B9, B10, B19].

**Zeitrauschen als Mechanismus (Rechnung C, analytisch und simuliert):** Unabhängiges Rauschen σ_t in den Schlagzeitpunkten erhöht RMSSD² um etwa 6·σ_t². Bei RMSSD 40 ms ergibt σ_t = 5 / 10 / 15 ms in ln +0,045 / +0,16 / +0,31. Der Aufschlag hängt vom Niveau ab und schwankt mit der Signalgüte des Tages. Er wirkt deshalb in der Reihe nicht als fester Bias, sondern als zusätzliche Streuung.

Die Grenze „Zeitrauschen > 25 ms → eingeschränkt“ aus `../puls` (ALGORITHMUS 5.5b) liegt weit über dem Bereich, in dem RMSSD noch brauchbar wäre. Unter der Annahme, dass das dort geschätzte Zeitrauschen dem σ_t hier entspricht, ergäbe sie bei RMSSD 40 ms einen Aufschlag von rund +0,6 ln. Für FR-0215 braucht RMSSD daher eine **eigene, strengere Qualitätsgrenze**. Die Validierung legt sie fest; diese Analyse schlägt keinen Wert vor und ändert den Algorithmus nicht.

**Einordnung von Holmes 2020:** Die LoA beziehen sich auf Unterschiede **zwischen** Personen. Die SD der Differenz (0,42–0,57 ln) enthält deshalb auch den festen Bias jeder einzelnen Person. In einer persönlichen Reihe fällt ein fester Bias heraus (FR-0115); die Streuung von Tag zu Tag innerhalb einer Person ist kleiner, wie viel, sagt die Studie nicht. Die Autoren selbst werten die Übereinstimmung in Ruhe nach dem Bland-Altman-Verhältnis als „good“. Das Handy (iPhone 6) war schon damals mehrere Generationen alt.

**Einordnung von Laborde 2017 [A2]:** Die Warnung „We strongly recommend to avoid using smartphone apps based on the camera … because their sampling is simply too low“ steht im Kontext der Geräteauswahl „for research purposes“. Sie ist eine Expertenmeinung ohne eigene Messung. `../puls` begegnet genau diesem Punkt mit Interpolation der Pulskurve. Die Gegenbelege mit Daten sind Holmes 2020 und Peng 2015.

**Folgerung:** Für den Ruhepuls ist die Kamera belegt. Für RMSSD aus 60 s Kamera ist die Lage gemischt: positive Befunde mit 5 min [B1, B20] und ohne LoA [B5], dagegen die einzige Studie mit LoA genau zu 60 s Kamera [B19] und Peng [B3]. Ein Nichtbestehen der Validierung ist deshalb gut möglich. Eine eigene Vergleichsmessung des Maintainers mit `../puls` gegen Polar H9 verlief laut OQ-0078 gut. Es ist aber eine einzige Messung, sie ersetzt keine Validierung. Die Zahlen stehen absichtlich nicht hier.

## 4. Auswertung täglicher Werte

| Regel | Belegt durch | Stärke |
| --- | --- | --- |
| Mittel über mehrere Tage statt Einzeltag. Einzelwerte lagen bei einem Athleten in normalem Training zu 100 % außerhalb der SWC, das 7-Tage-Mittel zu 20 %. Wochenmittel gegen Leistung r = 0,72, Einzeltag r = −0,06. | [C1, C3], Abstract von [C4], N19 im Regelwerk | gut, aber kleine Studien (n = 2–10), liegend, Brustgurt/EKG |
| Mindestens 3 gültige Messungen pro Woche. Bei Freizeitsportlern eher ~5, weil sie stärker streuen (CV 10,1 % gegenüber 6,8 %). Buchheit: 3–4. | [C4, C5] | gut |
| Grenze (SWC, „normal range“): Mittel ± 0,5 SD über eine 4-Wochen-Basis [C8]. 0,5 × CV über 2 Wochen [C1, laut Dissertation]. 0,5 oder 1 × CV [C5]. 10-Tage-Mittel − 1 SD [C6]. Die Wahl nennt Buchheit „complex“. | [C1, C5, C6, C8, C13] | uneinheitlich, nicht validiert |
| Basis 2–4 Wochen | [C1, C8, C9, C13] | belegt verwendet. Eine Basis von 60 Tagen fand ich nicht als Primärbeleg; bei [C10] sind 60 Messungen nur Einschlusskriterium. |
| CV des lnRMSSD als eigener Marker | [C1] (n = 2), [C11] (n = 12) | schwach |
| Ruhepuls zusätzlich zu HRV: HRV „more sensitive but not specific“, Effektstärken beim Ruhepuls oft größer. Plews empfiehlt den Ruhepuls mitzulesen, um eine „Sättigung“ zu erkennen. | [C10, C2, C5] | mäßig |
| Abweichung nach oben ist nicht automatisch gut: lnRMSSD stieg bei funktioneller Überlastung. | [C12, C8, C2] | mäßig, stützt PAR-163 (Anzeige beschreibt nur die Abweichung) |

**Größenordnung der Effekte:** Altini und Plews fanden in 9 Mio. Messungen mit der Kamera (eine 1-min-Messung beim Aufwachen, „a simple, one minute measurement upon waking“) und mit Sensoren: RMSSD nach intensivem Training −3 %, nach lockerem +1,6 %, also 4,6 % Unterschied zwischen beiden; nach viel Alkohol −12 %, bei Krankheit −10 % [C10]. Das sind Mittelwerte über die Bevölkerung, nicht gegen EKG geprüft.

**Größenordnung der Tagesstreuung:** Die genannten CV beziehen sich auf die **ln-Werte**, nicht auf RMSSD.
- Nuuttila [C13]: lnRMSSD morgens liegend 4,03, Tages-CV 8,2 %, also SD ≈ 0,33 ln.
- Plews, Dissertation S. 98: Freizeitläufer lnRMSSD 3,4, CV 10,1 %, also SD ≈ 0,34 ln.
- Buchheit [C5]: „CV = 10–20% for Ln rMSSD“ bei wechselnder Trainingsbelastung, also eher mehr.
- Eine Tages-SD von 0,33 ln heißt: An einem gewöhnlichen Tag liegt RMSSD rund +39 % / −28 % neben dem persönlichen Mittel. Die Effekte oben (3–12 % ≈ 0,03–0,13 ln) liegen also deutlich **unter** einer Tages-SD, nicht im selben Bereich.

**Zweifel:** Die Tagesstreuung schwankt zwischen Personen (Nuuttila: CV 8,2 ± 3,9 %). Die Validierung schätzt sie für die eigene Reihe.

### Rechnung B: 7-Tage-Mittel nach PAR-161/162 bei Lücken und Kamera-Streuung
Modell wie R8:
- Tageswerte AR(1) mit biologischer SD `sb`, dazu Kamerafehler `sm`.
- Fehlende Tage: zufällig mit Anteil `p` oder „nur Werktage“.
- Fehlmessungen, die die Qualitätsprüfung passieren: Anteil `q`, lnRMSSD +0,4, Ruhepuls +4.
- Tagesstreuung lnRMSSD in B1–B3 `sb` 0,10 bzw. 0,15 ln. Das ist rund dreimal kleiner als die Literatur (0,33 ln, Abschnitt oben). Weil B nur von den Verhältnissen `sm/sb` und Fehlmessung/`sb` abhängt, gelten die Zeilen für jede Tagesstreuung, wenn man `sm` mitskaliert. Nur die feste Fehlmessung +0,4 ln ist bei sb 0,10 ein Ausreißer von 4 SD, bei sb 0,33 nur von 1,2 SD; das rechnet B4.
- Echter Abfall um 1·`sb` seit `d` Tagen.
- Je Fall 4000 Läufe.

`kal_d` ist der Anteil erkannter Abfälle bei einer Schwelle, die ohne Änderung genau 15,9 % der Tage auslöst. Die Spalte ist fair zwischen Fällen mit unterschiedlich breitem `z`. `fa1` ist P(z ≤ −1) ohne Änderung. Vollständige Tabellen: `B.txt` im Lauf.

| Fall (lnRMSSD, sb 0,10, AR 0,3) | Tage mit z | SD z | fa1 | kal1 | kal3 | kal7 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ohne Kamerafehler, keine Lücken | 100 % | 1,30 | 21,1 % | 26 % | 43 % | 74 % |
| sm = 0,5·sb | 100 % | 1,25 | 20,9 % | 25 % | 39 % | 70 % |
| sm = 1·sb | 100 % | 1,18 | 19,4 % | 23 % | 34 % | 62 % |
| sm 0,5·sb, 20 % Lücken | 80 % | 1,25 | 20,1 % | 27 % | 39 % | 66 % |
| sm 0,5·sb, 20 % Lücken, 5 % Fehlmessungen | 80 % | 1,41 | 17,0 % | 25 % | 36 % | 60 % |
| sm 0,5·sb, 40 % Lücken, 5 % Fehlmessungen | 52 % | 1,41 | 17,2 % | 27 % | 36 % | 57 % |
| sm 0,5·sb, nur Werktage, 5 % Fehlmessungen | 71 % | 1,43 | 18,5 % | 26 % | 36 % | 57 % |
| sm 1,5·sb, 20 % Lücken, 5 % Fehlmessungen | 80 % | 1,18 | 16,4 % | 22 % | 29 % | 47 % |

| Regelvariante (sm 0,5·sb, 20 % Lücken, 5 % Fehlmessungen) | Tage mit z | SD z | kal1 | kal3 | kal7 |
| --- | ---: | ---: | ---: | ---: | ---: |
| PAR-161 wie heute | 80 % | 1,41 | 25 % | 36 % | 60 % |
| Referenz ohne die 7 Fenstertage | 78 % | 1,86 | 22 % | 34 % | 62 % |
| heute nicht Pflicht | 99 % | 1,39 | 24 % | 35 % | 60 % |
| mindestens 4 statt 3 Werte | 79 % | 1,41 | 25 % | 36 % | 60 % |
| Einzeltag (Fenster 1) | 80 % | 1,44 | 41 % | 39 % | 33 % |

| Ruhepuls (AR 0,3, ohne Lücken) | Tage mit z, Wert mit 1 Nachkommastelle | gerundet auf ganze /min |
| --- | ---: | ---: |
| sb 1,5/min, ohne Kamerafehler | 43 % (57 % durch MAD < 1 gesperrt) | 93 % |
| sb 1,5, sm 1,0 | 73 % | 98 % |
| sb 2,0, ohne Kamerafehler | 84 % | 99 % |
| sb 3,0, ohne Kamerafehler | 99 % | 100 % |
| sb 1,5, sm 1, 20 % Lücken, 5 % Fehlmessungen (+4/min): MAD-Grenze 1 gegenüber 0,5 | 61 % gegenüber 79 % bei gleicher Trennschärfe (kal7 61 % gegenüber 59 %) | – |

| B4: lnRMSSD, sm 0,5·sb, AR 0,3, 20 % Lücken | SD z | kal1 | kal3 | kal7 |
| --- | ---: | ---: | ---: | ---: |
| sb 0,10, ohne Fehlmessungen | 1,25 | 27 % | 39 % | 66 % |
| sb 0,10, 5 % Fehlmessungen +0,4 ln (= 4 sb) | 1,41 | 25 % | 36 % | 60 % |
| sb 0,33, ohne Fehlmessungen | 1,25 | 27 % | 39 % | 66 % |
| sb 0,33, 5 % Fehlmessungen +0,4 ln (= 1,2 sb) | 1,25 | 26 % | 39 % | 66 % |
| sb 0,33, 5 % Fehlmessungen +1,32 ln (= 4 sb) | 1,41 | 25 % | 36 % | 60 % |

**Was das heißt:**
1. **Kamerafehler bis zur halben Tagesstreuung kosten wenig:** 3–4 Punkte nach 7 Tagen (74 → 70 %). Ein gleich großer Fehler kostet ~12 Punkte (→ 62 %). Mit 20 % Lücken und 5 % Fehlmessungen liegt ein 1,5-facher Fehler 13 Punkte unter einem halben (47 gegenüber 60 %). Daraus folgt die Akzeptanzgrenze in Abschnitt 6. Absolut heißt das bei einer Tages-SD von 0,33 ln: Kamerastreuung je Messung bis ≈ 0,16 ln (etwa +18 % / −15 % RMSSD) kostet wenig, bis ≈ 0,33 ln (etwa +39 % / −28 %) rund 12 Punkte.
2. **Lücken kosten vor allem Verfügbarkeit.** Da der heutige Wert Pflicht ist, fehlt die Zahl an jedem Tag ohne Messung. Die Trennschärfe sinkt nur mäßig. „Heute nicht Pflicht“ brächte 99 % Verfügbarkeit bei gleicher Trennschärfe; dann gäbe es aber eine Zahl ohne frische Messung.
3. **Fehlmessungen, die durch die Qualitätsprüfung rutschen,** kosten so viel, wie sie im Verhältnis zur Tagesstreuung groß sind. Ein Ausreißer von 4 Tages-SD bei 5 % der Messungen kostet etwa 6 Punkte; +0,4 ln bei einer Tages-SD von 0,33 ln (1,2 SD) kostet fast nichts (B4). Teuer sind also nur grobe Ausreißer, etwa ein Zeitrauschen von 15 ms und mehr (Rechnung C: +0,3 ln und mehr bei RMSSD 40 ms, bei kleinem RMSSD deutlich mehr). Die Qualitätsgrenze für RMSSD ist deshalb vor allem gegen solche Ausreißer wichtig.
4. **Das 7-Tage-Mittel erkennt einen anhaltenden Abfall nach 3–7 Tagen besser, der Einzeltag am ersten Tag.** Das deckt sich mit [C1, C3] und mit PAR-161, das Mittel bleibt also. Die Varianten Referenz ohne Fenster und k ≥ 4 ändern bei gleicher Fehlalarmrate nichts und werden nicht empfohlen.
5. **Ruhepuls: Die Grenze „MAD < 1/min → kein z“ aus PAR-162 ist für die Kamera zu grob.** Bei sehr gleichmäßigem Ruhepuls (SD ≈ 1,5/min) sperrt sie bei Werten mit Nachkommastelle die Hälfte der Tage. Die Grenze war für ganzzahlige Werte aus Health Connect gedacht. Eine SD von 1,5/min liegt am unteren Rand der Literatur oder darunter: Nuuttila fand morgens liegend eine Puls-CV von im Mittel 6,8 % (≈ 3,7/min bei 55/min), im Bereich 4,1–12,8 % zwischen den Personen; der untere Rand entspricht bei rund 53/min etwa 2/min [C13, Tabelle 1]. Das betrifft also nur sehr gleichmäßige Personen. **Warum 0,5:** Die erwartete MAD ist 0,6745·√(sb² + sm²). **Angenommen** sm ≈ 1/min (abgeleitet aus LoA ±2/min bei 20 s [B7]), ergibt schon der Messfehler allein eine MAD um 0,67/min; eine MAD unter 0,5/min wäre dann gleichmäßiger, als die Messung selbst sein kann. Diese Annahme ist unsicher: Bánhalmi fand mit 240 Bildern/s über 5 min eine SD von nur 0,11/min [B2]. Ist die Kamera über 60 s ähnlich genau, trägt die Begründung nur noch über die biologische Streuung: Bei sb = 1,5/min (unterer Rand oder darunter, siehe oben) ist die erwartete MAD ≈ 1,0/min, eine MAD unter 0,5 entspräche einer Tages-SD unter etwa 0,75/min, weit unter dem unteren Rand der Literatur (CV 4,1 % bei rund 53/min ≈ 2/min [C13]). Dazu kommt: Die MAD aus 14–28 Werten streut selbst deutlich, die Grenze ist also eher grob. Die Grenze dient FR-0114 (keine Scheinpräzision) bei zu wenigen oder auffällig gleichen Werten. Eine Grenze von 0,3 schützte davor kaum noch; ein anderer Wert als 1 und 0,5 ist nicht gerechnet. **Die Validierung misst sm und die Tages-SD des Pulses; danach ist die Grenze 0,5 zu prüfen** (Offene Punkte). Die Auflösung von 0,1/min ist kein Problem, solange sie unter dem Messfehler liegt; bei sm ≈ 0,1/min wäre sie gleich groß, aber weiter klein gegen die biologische Streuung.
6. **Die Größe des Effekts relativieren:** Ein Abfall um 1 Tages-SD (≈ 0,33 ln, also RMSSD rund −28 %) wird auch nach 7 Tagen nur zu 60–74 % erkannt. Die Effekte aus [C10] (3–12 %, also 0,1–0,4 Tages-SD) sind im Einzelfall kaum sicher sichtbar. Das stützt die zurückhaltenden Texte (FR-0117, FR-0118).

## 5. Vorschlag: Regelversion „K-1“ (Kamera-Morgenmessung) für M3
Nur ein Vorschlag. Das Regelwerk `docs/phase-2-3-rules.md` bleibt unverändert, entscheiden muss der Maintainer. Nummern mit Suffix K bezeichnen die Kameravariante der jeweiligen Regel; die Health-Connect-Regeln bleiben daneben bestehen.

| ID (Vorschlag) | Regel | Art | Begründung |
| --- | --- | --- | --- |
| PAR-160K | **Gültiger Kamera-Morgenwert.** Eine Messung nach Protokoll: Haltung wie gespeichert, 2 min Ruhe, 60 s, spontane Atmung. Sie liegt im Morgenfenster des Nutzers (Vorgabe 4–11 Uhr, einstellbar). Es zählt die **erste** Messung des Tages mit ausreichender Qualität. Ruhepuls gilt bei Qualität „gut“ oder „eingeschränkt“, RMSSD nur bei „gut“ **und** unter der RMSSD-Qualitätsgrenze aus der Validierung. Wertebereiche: RMSSD 1–200 ms (wie PAR-160), Ruhepuls PAR-017. Eine eigene Reihe je Haltung und Gerät, nie gemischt mit Health Connect. | Heuristik, Evidenz niedrig | Abschnitte 1–3; FR-0115; Gerät beeinflusst [B4]; Zeitrauschen erhöht RMSSD (Rechnung C). Das Morgenfenster ist eigene Wahl, weil ohne Schlafdaten die Aufwachzeit fehlt. |
| PAR-161K | wie PAR-161: Mittel aus `k` ≥ 3 gültigen Werten der letzten 7 Tage, heute Pflicht, Referenz 28 Tage mit ≥ 14 gültigen Werten, Nenner `1,4826·MAD/√k`, MAD < 0,02 → kein `z`. **Neu:** Hat die Reihe in den letzten 7 Tagen weniger als 5 gültige Werte, sagt die Erklärung „wenige Messungen, weniger verlässlich“. | Heuristik | [C4, C5]; Rechnung B: Varianten bringen nichts, das Mittel schlägt den Einzeltag ab Tag 3. |
| PAR-162K | wie PAR-162, aber Ruhepuls mit einer Nachkommastelle und **MAD-Grenze 0,5/min** statt 1 | Heuristik | Rechnung B, Punkt 5. Die Grenze 1 bleibt für ganzzahlige Werte aus Health Connect. |
| PAR-163 | unverändert | – | [C12, C2] stützen, dass die Anzeige nur die Abweichung beschreibt. |
| PAR-164K/165K | **Schlafdauer ohne Uhr:** freiwillige Selbstangabe bei der Morgenmessung in Stufen (unter 5, 5–6, 6–7, 7–8, über 8 h). Sie geht mit einem festen Wert je Stufe in PAR-165 ein: 4,5 / 5,5 / 6,5 / 7,5 / 8,5 h (offene Stufen eigene Wahl). Sie ist als Selbstangabe markiert; die Effizienz (PAR-166) fehlt. | Heuristik, Evidenz keine | Mit dem Maintainer vereinbart („Messung + 1–2 Tipps“). Ohne Schlafwert erfüllt sonst niemand ohne Uhr OQ-0006. Grobe Stufen vermeiden Scheinpräzision (FR-0114). |
| PAR-169 | **unverändert** (Befinden = Angabe beim letzten Lauf). Die zunächst vorgeschlagene Variante PAR-169K („Schlafgefühl 1–5“ am Morgen als Befinden) **entfällt**. Am Morgen erfasst die App nur die Messung und die Schlafdauer in Stufen. | Entscheidung des Maintainers 2026-11-09 (E4) | Die Variante widersprach PAR-169 und hätte den Schlaf doppelt gezählt (Schlafdauer 30 % plus Schlafgefühl als Befinden 10 %). Mit PAR-169 unverändert gibt es keine Doppelzählung. |
| PAR-170 | unverändert (Kappung 74 ohne Belastungsfaktor) | – | – |
| Vorrang (neu) | **Health Connect und Kamera am selben Tag:** Beide Reihen bleiben getrennt (FR-0115) und werden nie gemittelt. Für HRV **und** Ruhepuls gilt je Faktor: Hat die Health-Connect-Reihe heute ein gültiges `z`, zählt sie; sonst die Kamerareihe, wenn sie heute ein gültiges `z` hat und für diesen Faktor freigegeben ist (Validierungssperre unten: RMSSD nur nach Bestehen und Opt-in, Ruhepuls nicht nach „nicht bestanden“). Die andere Messung erscheint nur als Tatsache. Die Quelle steht in der Erklärung. | Heuristik, Evidenz keine | Das Regelwerk ist für nächtliche Werte geschrieben und dafür geprüft (R8); Kamera-RMSSD ist im besten Fall „mit einem Brustgurt verglichen“. Ein Wechsel der Quelle von Tag zu Tag ist möglich; er ändert nur, welche Reihe zählt, nie deren Referenz. |
| PAR-171K | Zahl nur nach der neuen Fassung von OQ-0006 (unten): HRV aus Uhr oder Kamera (Kamera nur nach bestandener Validierung **und** Opt-in), Schlafdauer aus Uhr oder Selbstangabe, Referenz ≥ 14 in 28 Tagen. Sonst „Eingeschränkte Einschätzung“, wenn **eine** frische Messung (Kamera oder Health Connect) oder Schlaf (auch Selbstangabe) vorliegt, mit den Tatsachen („Ruhepuls heute 3/min über deinem Mittel“, „Du hast rund 6 Stunden geschlafen“). Hat der Kamera-Ruhepuls die Validierung nicht bestanden, erscheint er dort nur als markierte Tatsache („ungenauer als erwartet“, E7b). Gesperrte oder nicht eingeschaltete Kamera-RMSSD erscheint dort höchstens als markierte Tatsache: „noch nicht geprüft“ vor der Validierung, „ungenauer als erwartet“ nach „eingeschränkt“ oder „nicht bestanden“ (E7a), „experimentell, nicht eingeschaltet“ nach Bestehen ohne Opt-in. Markierte Tatsachen gehen in keine Zahl und keinen Faktor ein. Der Wortlaut der Markierungen ist ein Vorschlag. Ohne Uhr ist das bis zur Freigabe der einzige Zustand mit Inhalt (E1). Sonst „Unzureichende Daten“. | abgeleitet | erweitert PAR-171 um den Fall „Kamera ohne Schlaf“; Entscheidungen E1–E3 |
| Validierungssperre | Bis die Validierung (Abschnitt 6) bestanden ist, geht nur der Kamera-Ruhepuls ein (in die eingeschränkte Einschätzung bzw. bei Uhr-Nutzern als Faktor). RMSSD wird angezeigt, aber als „noch nicht geprüft“ markiert und nicht gewertet. **Folgen je Ergebnis (E7):** lnRMSSD „eingeschränkt“ gilt wie „nicht bestanden“: RMSSD bleibt gesperrt und erscheint nur als markierte Tatsache „ungenauer als erwartet“ (E7a). Der Ruhepuls bleibt bei „bestanden“ und „eingeschränkt“ in Gebrauch; bei „nicht bestanden“ geht er in keine Zahl und keinen Faktor ein, erscheint in der eingeschränkten Einschätzung nur als markierte Tatsache „ungenauer als erwartet“ und gilt weiter für das Profil (FR-0214) (E7b). Die Sperre gilt bis zu einer **bestandenen** erneuten Validierung. Freigegeben bzw. gesperrt wird das Verfahren (Algorithmus und Protokoll), nicht ein Gerät; ein neuer Lauf ist nur nach einer dokumentierten Änderung des Verfahrens erlaubt, ein Gerätewechsel allein reicht nicht (E7c, Regeln in Abschnitt 6). **Nach Bestehen: Opt-in experimentell (E2).** Kamera-RMSSD zählt nur, wenn der Nutzer es ausdrücklich einschaltet; Zahl und Wert tragen „experimentell, mit einem Brustgurt verglichen (ein Handy)“, nie „validiert“. Die Validierung wird liegend gemessen; das Opt-in gilt **vorläufig auch für die sitzende Reihe**, dort mit dem Zusatz „liegend verglichen“ (E6). Ergibt eine spätere Validierung im Sitzen „eingeschränkt“ oder „nicht bestanden“, wird RMSSD sitzend gesperrt (E7a). Die RMSSD-Qualitätsgrenze schützt jede einzelne Messung. Eine Prüfung je Nutzer mit eigenem Gurt kann später dazukommen. | Entscheidung des Maintainers 2026-11-09 (E2, E6, E7a–c) | Abschnitt 3; Gerät beeinflusst die Güte [B4]; n = 1 (Abschnitt 6) |

**OQ-0006, neue Fassung (vom Maintainer am 2026-11-09 gewählt, E3; Konzept noch nicht geändert):** Eine Zahl erscheint nur mit
- einer aktuellen HRV, nächtlich aus Health Connect **oder** als gültiger Kamera-Morgenwert nach bestandener Validierung und eingeschaltetem Opt-in (E2),
- einer Schlafdauer der letzten Nacht, aus Health Connect **oder** als Selbstangabe,
- einer persönlichen Referenz derselben Reihe aus mindestens 14 gültigen Werten in 28 Tagen.

Ohne jede Schlafangabe gibt es keine Zahl, sondern die eingeschränkte Einschätzung (PAR-171K). Begründung: Der Schlaf hat das größte Gewicht (30 %, FR-0110). Ein Wert ohne ihn würde nur durch Herausrechnen entstehen, und das soll fehlende Daten nicht verbessern (FR-0111).

Verworfen (E3): Option B, eine Zahl auch ohne Schlaf mit Kappung 74.

**Wichtig:** Auch die neue Fassung verlangt eine HRV. Solange die Kamera-RMSSD gesperrt ist, gibt es ohne Uhr keine Zahl (E1).

**Anforderungen, deren Akzeptanzkriterien sich mit K-1 ändern müssten** (nur Hinweis, nicht geändert):
- FR-0109: „HRV der letzten Nacht“ → nächtliche HRV **oder** gültiger Kamera-Morgenwert; „Schlaf“ → auch Selbstangabe.
- FR-0113: „letzte 7 Nächte“ → „letzte 7 Tage“ für die Kamerareihe.
- FR-0115: „genau eine Quell-App“ → Kamera als eigene Quelle, eigene Reihe je Haltung (liegend als Vorgabe, sitzend getrennt, E5) und Gerät; Vorrangregel oben.
- FR-0214: Haltung liegend als Vorgabe, sitzend wählbar (E5); 2 min Ruhe vor der Morgenmessung.
- Nicht betroffen: PAR-169 und FR-0038 (Befinden beim letzten Lauf bleibt, E4).
- FR-0116 bzw. PAR-171: „wenn Schlaf der letzten Nacht vorliegt“ → auch eine frische Kamera-Messung (PAR-171K).
- PAR-147: „kein `z` für die HRV“ → auch kein gültiges Kamera-`z` bzw. Validierungssperre.
- PAR-148: „HRV-Referenz aus 14–17 Messungen“ gilt für die Kamerareihe entsprechend; dazu der Hinweis „wenige Messungen“ aus PAR-161K.
- FR-0215: Akzeptanzkriterien aus Protokoll, PAR-160K bis PAR-171K und der Validierungssperre.

## 5a. Entscheidungen des Maintainers (2026-11-09)
Die sieben Produktfragen E1–E7 hat der Maintainer am 2026-11-09 entschieden. Das Konzept ist noch nicht geändert; das übernimmt der Project Supervisor.

**E1: Was bekommen Nutzer ohne Uhr, solange Kamera-RMSSD gesperrt ist?**
- **Entscheidung des Maintainers (2026-11-09): „Nur eingeschränkte Einschätzung“ (Option a).** Ohne Uhr gibt es keine Zahl, solange Kamera-RMSSD gesperrt ist. Ergibt die Validierung „eingeschränkt“ oder „nicht bestanden“, bleibt das so, bis eine erneute Validierung nach einer dokumentierten Änderung des Verfahrens bestanden ist (E7a, E7c). Der Nutzer sieht die eingeschränkte Einschätzung nach PAR-171K mit den Tatsachen (z. B. „Ruhepuls heute 3/min über deinem Mittel“, nach Puls „nicht bestanden“ markiert als „ungenauer als erwartet“, E7b; Schlafangabe) und die Basis-Hinweise aus Trainingsdaten (FR-0106).
- Begründung: OQ-0006 verlangt eine HRV; eine Zahl ohne HRV würde das Herausrechnen fehlender Daten zur Hauptquelle machen (FR-0111) und hinge fast nur an Selbstangaben.
- Verworfen: (b) Zahl aus Ruhepuls und Schlaf ohne HRV mit Kappung (widerspricht OQ-0006 und PAR-147); (c) Zahl nur nach persönlicher Prüfung mit eigenem Brustgurt (als spätere Ergänzung über E2 möglich).

**E2: Was gibt ein Bestehen der Validierung mit n = 1 frei?**
- **Entscheidung des Maintainers (2026-11-09): „Opt-in experimentell“ (Option b).** Nach bestandener Validierung zählt Kamera-RMSSD nur für Nutzer, die es ausdrücklich einschalten. Die Zahl trägt die Kennzeichnung „experimentell, mit einem Brustgurt verglichen (ein Handy)“, nie „validiert“. Die RMSSD-Qualitätsgrenze schützt jede einzelne Messung. Freigegeben wird das Verfahren für alle Geräte, nicht ein einzelnes Gerät (E7c).
- Begründung: Bestanden heißt nur ein Handy, eine Person, eine Haltung, eine Jahreszeit; die Güte hängt am Gerät [B4, B19]. Das Risiko ist gering, weil ein hoher Wert die Belastung nie erhöht (PAR-173).
- Verworfen: (a) Freigabe für alle Nutzer und Geräte ohne Opt-in. (c) Prüfung je Nutzer mit eigenem Brustgurt ist **zurückgestellt**: Sie kann später dazukommen (nach Rechnung D mindestens 14, besser 22–28 gültige Morgen; braucht RR-Intervalle vom Gurt, WP26/FR-0213).

**E3: Zahl mit oder ohne Schlaf-Selbstangabe?**
- **Entscheidung des Maintainers (2026-11-09): „Selbstangabe Schlaf reicht“, also die neue Fassung von OQ-0006** (Abschnitt 5): HRV aus Uhr oder Kamera und Schlafdauer aus Uhr oder freiwilliger Angabe in Stufen (PAR-164K/165K).
- Verworfen: Option B (Zahl auch ohne jede Schlafangabe, mit Kappung 74).

**E4: Schlafgefühl am Morgen als Befinden (PAR-169K)?**
- **Entscheidung des Maintainers (2026-11-09): „Nein, PAR-169 bleibt“.** PAR-169K entfällt. Am Morgen nur Messung und Schlafdauer in Stufen; das Befinden bleibt die Angabe beim letzten Lauf. Damit entfällt auch die Doppelzählung des Schlafs.
- Verworfen: Schlafgefühl 1–5 als Tagesangabe für das Befinden.

**E5: Haltung bei der Morgenmessung?**
- **Entscheidung des Maintainers (2026-11-09): „Liegend, sitzend wählbar“.** Vorgabe liegend; wer sitzend wählt, bekommt eine eigene Reihe (eigene Referenz, nie gemischt, FR-0115). Stehend ist nicht vorgesehen.
- Folge für die Validierung: Sie wird liegend gemessen (Abschnitt 6). Für die sitzende Reihe ist Kamera-RMSSD damit nicht geprüft; dazu E6.

**E6: Gilt eine liegend bestandene Validierung auch für die sitzende Reihe?**
- **Entscheidung des Maintainers (2026-11-09): „gilt vorerst beides“ (Option b), also vorläufig.** Nach einer liegend bestandenen Validierung gilt das Opt-in „experimentell“ für beide Haltungen. Bei der sitzenden Reihe kommt der Zusatz „liegend verglichen“ dazu.
- **Gegenbeleg:** Die Abweichung der Kamera zum EKG wächst von liegend über sitzend zu stehend (Esco 2017, 60 s, externer Fingersensor, nur Abstract) [B6]. Holmes 2020 maß sitzend und fand breite LoA (rund ±1 ln zwischen Personen) [B19]. Die sitzende Reihe ist deshalb voraussichtlich schlechter als die geprüfte liegende.
- „Vorerst“: Eine eigene Validierung im Sitzen ist als Folgeanalyse empfohlen (Offene Punkte). Ergibt sie „eingeschränkt“ oder „nicht bestanden“, wird RMSSD sitzend gesperrt (E7a).
- Verworfen: (a) Sperre sitzend bis zur eigenen Validierung; (c) sitzend nur Ruhepuls.

**E7: Was folgt aus „eingeschränkt“ und „nicht bestanden“?** (Frage aus Review-Runde 2: Der Plan hat drei Stufen, die Sperre kannte nur „bestanden“ und „durchgefallen, dauerhaft“.)
- **E7a, lnRMSSD. Entscheidung des Maintainers (2026-11-09): „Gesperrt wie nicht bestanden“.** Bei „eingeschränkt“ geht RMSSD nicht in die Zahl ein und erscheint nur als markierte Tatsache, genau wie bei „nicht bestanden“ (Markierung „ungenauer als erwartet“, PAR-171K). Eine erneute Validierung ist nach einer dokumentierten Änderung des Verfahrens erlaubt (E7c); das gilt auch nach „nicht bestanden“. Das frühere „bleibt dauerhaft so“ heißt damit: gesperrt bis zu einer bestandenen erneuten Validierung nach einer solchen Änderung.
- **E7b, Ruhepuls. Entscheidung des Maintainers (2026-11-09): „Eingeschr. ok, sonst nur Profil“.** Ein Kamera-Ruhepuls mit Ergebnis „eingeschränkt“ (LoA innerhalb ±3/min) bleibt in Gebrauch, wie bei „bestanden“. Bei „nicht bestanden“ gilt er für das Profil (FR-0214), nicht für die Readiness. Eine erneute Validierung ist nach einer dokumentierten Änderung des Verfahrens erlaubt (E7c).
- **E7b, Auslegung. Entscheidung des Maintainers (2026-11-09): „Ja, als markierte Tatsache“.** „Nicht für die Readiness“ heißt: Ein Kamera-Ruhepuls mit „nicht bestanden“ geht in keine Zahl und keinen Faktor ein. In der eingeschränkten Einschätzung erscheint er weiter, aber nur als markierte Tatsache, etwa „ungenauer als erwartet“. Er wird damit behandelt wie eine gesperrte RMSSD (E7a); die frühere, strengere Auslegung („auch nicht in der eingeschränkten Einschätzung“) entfällt.
- **E7c, was freigegeben wird. Entscheidung des Maintainers (2026-11-09): „es wird nur das verfahren freigegeben, nicht jedes einzelne gerät“.** Das heißt:
  - Die Validierung prüft das **Verfahren**, also Algorithmus und Protokoll, und gibt es frei oder sperrt es. Sie prüft und gibt kein Gerät frei. Eine Freigabe je Gerätemodell gibt es nicht (Option „je Gerätemodell“ aus Review-Runde 3 verworfen).
  - Nach „eingeschränkt“ oder „nicht bestanden“ ist ein neuer Lauf nur nach einer **dokumentierten Änderung des Verfahrens** erlaubt. Ein Gerätewechsel allein löst keinen neuen Lauf aus. So kann ein Fehlschlag nicht durch einen zweiten Lauf auf einem anderen Handy mit unverändertem Verfahren ersetzt werden.
  - Der Einfluss des Geräts [B4] bleibt eine offene Grenze von n = 1 (Abschnitt 6, „Grenzen von n = 1“; Offene Punkte 4a). Die Kennzeichnung „(ein Handy)“ aus E2 macht sie für den Nutzer sichtbar.
- Begründung: Rechnung D zeigt, dass „eingeschränkt“ bei einem wahren Verhältnis von 0,5–1,0 das häufigste Ergebnis ist; ohne Regel wäre gerade dieser Fall offen gewesen. Für RMSSD ist die Belegung schwach (Abschnitt 3), für den Puls gut, daher die unterschiedliche Strenge bei „eingeschränkt“. Nach „nicht bestanden“ werden beide Größen gleich behandelt: markierte Tatsache, keine Zahl, kein Faktor.
- Regeln für eine erneute Validierung: Abschnitt 6.

**Was das für M3 heißt:** Für Nutzer ohne Uhr entsteht eine Zahl erst, wenn (1) die Validierung für lnRMSSD bestanden ist („eingeschränkt“ reicht nicht, E7a), (2) der Nutzer Kamera-RMSSD per Opt-in einschaltet, (3) eine Schlafdauer vorliegt (Selbstangabe genügt) und (4) die Kamerareihe 14 gültige Werte in 28 Tagen hat. Bis dahin: Morgenmessung, Ruhepuls-Trend und eingeschränkte Einschätzung. Hat der Puls die Validierung nicht bestanden, erscheint der Ruhepuls-Trend dort nur als markierte Tatsache („ungenauer als erwartet“, E7b).

## 6. Validierungsplan gegen Polar H9 (n = 1, 4–6 Wochen)

**Aufbau:**
- **Wer und womit:** der Maintainer, sein Handy, **28 Referenzmorgen**. Ein Referenzmorgen ist ein Morgen, an dem nach Protokoll mit dem H9 gemessen und eine Kameramessung versucht wurde und der H9-Wert gültig ist. Ob die Kameramessung gültig ist oder überhaupt einen Wert liefert, spielt dafür keine Rolle; ein Ausfall der Kamera zählt gegen die Quote. Fehlen Morgen (vergessen, H9-Ausfall), wird verlängert, bis 28 Referenzmorgen vorliegen, höchstens bis zum 42. Kalendermorgen (Regel unten).
- **Ablauf am Morgen:** genau das Protokoll aus Abschnitt 1, **liegend** (Vorgabe nach E5), an allen Morgen gleich. Der H9 läuft gleichzeitig und zeichnet RR-Intervalle auf (eine Logger-App mit RR-Export). Die Uhren beider Geräte werden abgeglichen.
- **Referenz:** RMSSD und Puls aus den H9-RR **im selben 60-s-Fenster**, ohne Interpolation. Ein offensichtlicher Artefakt wird nach fester Regel entfernt, die vorher festgelegt und für beide Seiten gleich ist. Weil beide Geräte dieselben Schläge messen, steckt das Rauschen des kurzen Fensters (Rechnung C, [A5]) nicht in der Differenz.
- **Zusatz an 1–2 Tagen pro Woche:** gleich danach eine zweite Kameramessung (Wiederholbarkeit der Kamera allein).
- **Stresstests getrennt:** einzelne Messungen mit kalten Händen oder nach Bewegung, nicht in der Hauptauswertung.

**Kalibrier- und Prüftage (wochenweise Kreuzvalidierung):** Die RMSSD-Qualitätsgrenze (Zeitrauschen) wird an den Daten bestimmt. Würde an denselben Tagen geprüft, wäre das optimistisch. Eine feste Aufteilung „14 Tage festlegen, Rest prüfen“ ließe bei 28 Morgen nur 14 Prüftage, abzüglich verworfener Messungen eher 10–12; dort trennt das Kriterium deutlich schlechter (Tabelle unten). Deshalb:
1. Vorab festlegen, nach welcher Regel die Grenze gewählt wird. Vorschlag: die größte Grenze, bei der an den zugelassenen Tagen SD(d) ≤ 0,5 × Tages-SD **und** ein Anteil gültiger Messungen ≥ 22/28 (78,6 %) gelten; gibt es keine, die strengste Grenze mit Anteil ≥ 17/28 (60,7 %). Das sind dieselben Schwellen wie bei der Qualitätsquote unten.
2. Die 28 Referenzmorgen bilden 4 Blöcke zu je 7 aufeinanderfolgenden Referenzmorgen („Wochen“). Für jeden Block die Grenze nur aus den **anderen 3 Blöcken** bestimmen und auf diesen Block anwenden.
3. Gewertet werden alle in ihrem Block zugelassenen Tage zusammen. Sie sind alle Prüftage, keiner hat seine eigene Grenze mitbestimmt.
4. **Mindestumfang und Quote hängen zusammen:** Die Prüftage sind genau die gültigen Kameramessungen unter den 28 Referenzmorgen. „Mindestens 22 Prüftage“ und „Qualitätsquote bestanden (≥ 22 von 28)“ sind also dieselbe Bedingung. Weniger als 22 Prüftage heißt Quote „eingeschränkt“ oder „nicht bestanden“, für lnRMSSD damit höchstens „eingeschränkt“ und nach E7a gesperrt.
5. **Verlängerung, vorab festgelegt:** Sie sichert nur die Zahl der **Referenzmorgen** (Ausfälle, die nicht an der Kamera liegen), nie die Quote. Wegen ungültiger Kameramessungen wird nicht verlängert. Quote, Prüftage und Tages-SD zählen immer über genau die 28 Referenzmorgen, auch wenn sie sich über bis zu 42 Kalendermorgen verteilen. Kommen bis zum 42. Kalendermorgen keine 28 Referenzmorgen zusammen, gilt die Validierung als nicht durchgeführt (kein Ergebnis). Die Kameradaten dieses Laufs werden dann **nie** ausgewertet, auch nicht später oder für einen anderen Zweck; der Lauf wird wie alle anderen berichtet (als „nicht durchgeführt“, mit Zahl der Referenzmorgen). Ein neuer Versuch beginnt mit neuen Morgen. Weil kein Ergebnis und kein Zwischenstand bekannt ist, braucht er keine Änderung des Verfahrens; die Regel „ohne Änderung kein neuer Lauf“ (unten) gilt für Läufe mit Ergebnis.
6. **Keine Zwischenauswertung:** Die Kameradaten werden erst nach dem 28. Referenzmorgen ausgewertet. Während der Messung wird nur geprüft, ob der H9-Wert gültig ist. So kann der Zwischenstand weder Verlängerung noch Abbruch beeinflussen.
7. Für die App gilt danach die Grenze, die die Regel aus allen Tagen ergibt. Ihr Ergebnis berichtet die Auswertung zusätzlich, entscheidend ist aber das Ergebnis der Kreuzvalidierung.

Gleichwertige, aber längere Alternative: 42 Referenzmorgen, Grenze aus den ersten 14, geprüft an den letzten 28; Quote dann über diese 28.

**Auswertung:**
- Je Morgen die Differenz d = Kamera − H9 für Puls und lnRMSSD.
- Bland-Altman: Bias, LoA = Bias ± 1,96·SD, 95-%-KI der LoA ≈ ± t·√(3/n)·SD [B12, B15].
- Proportionaler Bias: Steigung `b` der Regression **d gegen den H9-Wert** (nicht gegen den Mittelwert beider Geräte: Der enthält den Kamerafehler selbst und ergibt bei einem Verhältnis von 0,5 eine Scheinsteigung von etwa +0,12, Rechnung D2). Dazu die Grafik Differenz gegen H9-Wert.
- Lag-1-Autokorrelation der d prüfen.
- **Tages-SD der H9-Reihe über alle 28 Referenzmorgen** schätzen (unabhängig davon, ob die Kameramessung gültig war). Sie ist der Bezug für die Akzeptanz von lnRMSSD. Sie enthält auch das Rauschen des 60-s-Fensters; das ist richtig, weil auch die Reihe in der App 60-s-Werte hat.
- Qualitätsquote: Anteil gültiger Kameramessungen an den 28 Referenzmorgen, aus der Kreuzvalidierung (je Block mit der Grenze aus den anderen Blöcken).
- Puls: Bland-Altman über alle Referenzmorgen mit gültigem Kamera-Ruhepuls (Qualität „gut“ oder „eingeschränkt“, PAR-160K).

**Akzeptanzgrenzen (vorab festgelegt):**

| Größe | Bestanden | Eingeschränkt | Nicht bestanden | Begründung |
| --- | --- | --- | --- | --- |
| Puls | LoA (Punktschätzung) innerhalb ±2/min | innerhalb ±3/min | darüber | Literatur Finger in Ruhe ±2/min [B7, B2]. Die übliche Norm (±5/min bzw. ±10 %) gilt für EKG-Geräte und schließt PPG aus [B18]. Für Änderungen von wenigen /min ist sie zu grob. |
| lnRMSSD, Streuung | SD(d) ≤ 0,5 × Tages-SD der H9-Reihe | ≤ 1 × Tages-SD | darüber | Rechnung B: 0,5 kostet 3–4, 1,0 etwa 12 Punkte Erkennung. **Absolut** bei einer Tages-SD von 0,33 ln [C13]: bestanden heißt SD(d) ≤ 0,165 ln, also je Messung etwa **+18 % / −15 % RMSSD** (1 SD), LoA etwa +38 % / −28 %; eingeschränkt heißt bis 0,33 ln, etwa +39 % / −28 % je SD. Zum Vergleich: Bánhalmi mit 240 Bildern/s SD 0,153 [B2], Holmes zwischen Personen 0,42–0,57 [B19]. Bei einer Person mit kleinerer Tagesstreuung ist die Grenze absolut strenger. Der Bias zählt nicht, weil die Kamerareihe nie mit anderen gemischt wird (FR-0115), wird aber berichtet. |
| lnRMSSD, proportionaler Bias | \|b\| ≤ 0,2 (Punktschätzung) | 0,2 < \|b\| ≤ 0,35 | darüber | `b` = −0,2 heißt: Eine echte Änderung erscheint in der Kamerareihe nur zu 80 %. Für die Erkennung wirkt das wie ein Verhältnis von 0,5/0,8 ≈ 0,63 statt 0,5, kostet also nur wenige Punkte (Rechnung B, zwischen 70 und 62 %). Zeitrauschen erzeugt genau diesen Bias: `b` ≈ −0,2 entsteht bei RMSSD 25 ms schon ab σ_t ≈ 5 ms, bei 40 ms ab ≈ 8 ms (Rechnung D3). Holmes fand zwischen Personen nur einen schwachen Trend (r = −0,08 bis −0,13) [B19]. Die Grenzen sind eigene Wahl. |
| Qualitätsquote | ≥ 22 von 28 Referenzmorgen gültig (78,6 %) | 17–21 von 28 (60,7–75 %) | ≤ 16 von 28 | eigene Wahl. Rechnung B: Verfügbarkeit folgt direkt der Quote. Die Schwelle ist an den Mindestumfang von 22 Prüftagen gebunden (Schritt 4 oben); früher „≥ 80 %“, das hätte bei 22 von 28 nie „bestanden“ ergeben. |

Gesamturteil lnRMSSD: bestanden nur, wenn Streuung, proportionaler Bias und Qualitätsquote bestanden sind; sonst das schlechteste Teilurteil. Gesamturteil Puls: nach der Puls-Zeile allein.

**Folgen der Ergebnisse (E7, entschieden 2026-11-09):**

| Größe | Bestanden | Eingeschränkt | Nicht bestanden |
| --- | --- | --- | --- |
| lnRMSSD | Opt-in „experimentell“ (E2, E6) | gesperrt wie „nicht bestanden“ (E7a) | gesperrt: nur markierte Tatsache „ungenauer als erwartet“, nicht in der Zahl |
| Ruhepuls | in Gebrauch (Faktor bzw. eingeschränkte Einschätzung) | in Gebrauch wie „bestanden“ (E7b) | Profil (FR-0214); in der eingeschränkten Einschätzung nur markierte Tatsache „ungenauer als erwartet“, kein Faktor, nicht in der Zahl (E7b) |

Das Ergebnis gilt für das **Verfahren** (Algorithmus und Protokoll), nicht für ein Gerät (E7c).

**Erneute Validierung (E7c):** Nach „eingeschränkt“ oder „nicht bestanden“ ist ein neuer Lauf nur nach einer dokumentierten Änderung des Verfahrens erlaubt, für beide Größen. Ein Gerätewechsel allein löst keinen neuen Lauf aus. Damit sie kein „Weitermessen, bis es passt“ wird, gilt außerdem (Vorschlag, eigene Wahl):
- Die Änderung am Verfahren (Algorithmus-Version bzw. Protokoll) ist vor dem neuen Lauf festgelegt und dokumentiert. Ohne Änderung des Verfahrens gibt es keinen neuen Lauf, auch nicht mit einem anderen Handy. Ausnahme: ein nicht durchgeführter Lauf ohne Ergebnis (Schritt 5 oben).
- Der neue Lauf nutzt nur neue Morgen, denselben Plan und dieselben Schwellen. Daten früherer Läufe zählen nicht mit. Eine Änderung darf an alten Daten entwickelt sein (etwa eine Korrektur des Zeitrauschens, Offene Punkte 6); geprüft wird sie nur an neuen.
- Alle Läufe und ihre Ergebnisse werden berichtet, auch die nicht bestandenen und die nicht durchgeführten.
- Mit welchem Handy ein Lauf gemessen wird, ist kein Teil des Verfahrens; es wird berichtet. Sein Einfluss bleibt offen (Grenzen von n = 1 unten).

**Wie sicher trennt das Verhältniskriterium? (Rechnung D1, 4000 Läufe je Fall, H9-Reihe AR 0,3, d unabhängig)**

Anteil der Läufe mit Punktschätzung ≤ 0,5 („bestanden“) bei wahrem Verhältnis r; letzte Spalte: Anteil ≤ 1 („höchstens eingeschränkt“) bei r = 1,3.

| Design | Prüftage | Tage für Tages-SD | r = 0,4 | r = 0,5 | r = 0,7 | r = 0,85 | r = 1,0 | ≤ 1 bei r = 1,3 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 14 Morgen, 4 verworfen | 10 | 14 | 73 % | 47 % | 14 % | 5 % | 2 % | 20 % |
| 14 Morgen | 14 | 14 | 74 % | 45 % | 10 % | 3 % | 1 % | 15 % |
| 28 Morgen, 14 Kalibrier + 14 Prüf | 14 | 28 | 81 % | 50 % | 9 % | 2 % | 1 % | 15 % |
| **28 Morgen, Kreuzvalidierung, 22 von 28 gültig (Mindestumfang)** | 22 | 28 | 84 % | 47 % | 5 % | 1 % | 0 % | 10 % |
| 28 Morgen, Kreuzvalidierung, alle gültig | 28 | 28 | 85 % | 47 % | 4 % | 0 % | 0 % | 8 % |
| 42 Morgen, 14 Kalibrier + 28 Prüf | 28 | 42 | 88 % | 48 % | 4 % | 0 % | 0 % | 8 % |

- Mit autokorrelierten Differenzen (AR 0,3) ändern sich die Werte um 1–6 Punkte, bei r = 0,5 auf 51–55 % (Ausgabe `D.txt`).
- Streubereich (95 %) der Punktschätzung bei wahrem r = 0,5: 0,26–0,98 bei 10 Prüftagen, 0,30–0,79 bei 14, 0,33–0,76 bei 22, 0,35–0,72 bei 28 Prüf- und 42 Tagen.
- **Deutung:** Ab 22 Prüftagen besteht eine Kamera mit wahrem Verhältnis ≥ 0,85 praktisch nie (≤ 1 %), eine mit 0,7 selten (4–5 %), eine mit 0,4 meist (84–88 %). Mit 10–14 Prüftagen bestehen 0,7 zu 9–14 % und 0,85 zu 2–5 %. Nahe 0,5 entscheidet der Zufall; das liegt an jeder Grenze und ist hinnehmbar, weil 0,5 und 0,6 sich in der Erkennung kaum unterscheiden (Rechnung B). Die Tages-SD über 28 statt 14 Tage zu schätzen hilft vor allem guten Kameras (r = 0,4: 81 statt 74 %); entscheidend gegen schlechte ist die Zahl der Prüftage.

**Wie sicher trennt die Grenze für den proportionalen Bias? (Rechnung D2, Verhältnis 0,5)**

| Prüftage | halbe KI-Breite von b | P(\|b\| ≤ 0,2) bei wahrem β = 0 | β = −0,2 | β = −0,3 | β = −0,4 |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 14 | 0,33 | 82 % | 49 % | 25 % | 9 % |
| 22 | 0,24 | 90 % | 49 % | 19 % | 5 % |
| 28 | 0,21 | 94 % | 49 % | 15 % | 3 % |

Die Steigung ist bei n = 1 nur grob bestimmbar (KI ±0,2 bei 28 Tagen), weil die H9-Werte nur um eine Tages-SD streuen. Die Grenze fängt einen deutlichen proportionalen Bias (β ≤ −0,4) sicher, einen mäßigen (−0,3) nur zum Teil. Das KI wird berichtet.

**Fallzahl für den Puls (Rechnung A, 4000 Läufe je Fall, Einheiten der wahren SD(d)):**

| Tage n | Halbe KI-Breite Bias | Halbe KI-Breite LoA | Deckung des KI der LoA (AR 0) | (AR 0,5) |
| ---: | ---: | ---: | ---: | ---: |
| 14 | 0,57·SD | 0,98·SD | 93,5 % | 81,6 % |
| 21 | 0,45·SD | 0,78·SD | 94,5 % | 81,9 % |
| 28 | 0,38·SD | 0,67·SD | 95,1 % | 82,7 % |

Ein **formaler** Nachweis nach Lu et al. [B16] verlangt, dass das obere KI-Ende der LoA unter der Grenze Δ liegt. Bei 3–4 Wochen gelingt das nur, wenn die wahre SD(d) deutlich unter Δ liegt:
- SD = 0,25·Δ (Puls 0,5/min bei Δ 2): 99 % bei 21 Tagen.
- SD = 0,33·Δ (Puls 1/min bei Δ 3): 60 % bei 21 Tagen, 74 % bei 28 Tagen.
- SD = 0,5·Δ: ~0 %.
- Ein Bias von 0,5/min senkt das weiter (Tabelle A, Fälle mit `mu`).

Für lnRMSSD gibt es kein festes Δ; die frühere lnRMSSD-Tabelle in A mit Δ = 0,10/0,15 ln entsprach keinem Kriterium und ist entfallen.

**Folgerung für den Plan:**
- 28 Referenzmorgen mit Kreuzvalidierung, mindestens 22 gültige Prüftage (gleichbedeutend mit Quote „bestanden“). Verlängert wird nur bei fehlenden Referenzmorgen, nicht bei ungültigen Kameramessungen.
- Die Entscheidung beruht auf den Punktschätzungen, die KI werden berichtet.
- Ein Ergebnis „Punktschätzung erfüllt, KI überschreitet die Grenze“ heißt „vorläufig bestanden“, nicht „bewiesen“.
- Sind die Tagesdifferenzen autokorreliert (z. B. eine Woche mit kalten Händen), ist das KI der LoA zu schmal: Deckung 82 % statt 95 %. Bei Lag-1-Autokorrelation über 0,3 die KI-Breite deshalb um rund √((1+r)/(1−r)) erweitern (Näherung, eigene Wahl; Review-Runde 1 bestätigte 95–96 % Deckung damit).
- Nach der Literatur [B19, B3] ist ein Nichtbestehen bei lnRMSSD gut möglich. Die Folge für M3 steht in der Kurzfassung, in E1 und E7.

**Grenzen von n = 1:**
- Das Ergebnis gilt für eine Person, ein Handy, eine Haltung und die Jahreszeit der Messung.
- Andere Personen und Geräte sind nicht erfasst. Mühlen et al. empfehlen ≥ 45 Personen für eine Validierung [B17].
- Hauttemperatur, dunklere Haut und andere Geräte sind ungeprüft [B8, B4].
- Die App darf deshalb nicht behaupten, „validiert“ zu sein. Sie kann sagen: „mit einem Brustgurt verglichen“.
- Was ein Bestehen für andere Nutzer und Geräte freigibt, ist Entscheidung E2 (Abschnitt 5a).
- **Einfluss des Geräts:** Freigegeben wird das Verfahren für alle Geräte (E7c), geprüft ist es aber nur auf einem Handy. Die Güte hängt am Gerät [B4]; ob das Verfahren auf anderen Handys genauso gut misst, ist offen. Weder ein Bestehen noch ein Fehlschlag sagt etwas Sicheres über andere Geräte. Ein Gerätewechsel ist kein Anlass für einen neuen Lauf, ein Fehlschlag kann also nicht durch ein anderes Handy „repariert“ werden; umgekehrt kann ein Bestehen auf einem guten Handy für schwächere Geräte zu optimistisch sein. Die RMSSD-Qualitätsgrenze je Messung und die Kennzeichnung „(ein Handy)“ fangen das nur teilweise ab.

## Bewertung und Zweifel
- **Literatur:**
  - Volltext gelesen: Kernaussagen zu Puls, Ultrakurzzeit (liegend, EKG), Monitoring-Regeln [C1–C4 über die Dissertation von Plews, C5, C8, C10, C13], Bánhalmi, Peng, Holmes, Laborde und Task Force.
  - In der ersten Fassung fehlte Holmes 2020 [B19], die direkteste Studie zu 60 s Kamera gegen EKG; der Research Reviewer hat sie gefunden, in Runde 2 außerdem van Dijk 2023 [B20]. Die Suche war also nicht vollständig. Weitere Studien dieser Art sind möglich. Van Dijk ändert die Empfehlung nicht: Messdauer und Atmung weichen vom Protokoll ab, und die Validierung bleibt ohnehin Pflicht.
  - Nur Abstract: unter anderem Plews 2017, van Dijk 2023, Esco 2017, Schäfer und Vagedes 2013, Saboul 2013, Flatt und Esco 2016, Kiviniemi, Javaloyes, Moya-Ramon, Lu 2016 und die Metaanalyse zur langsamen Atmung. Alles ist in der Quellenliste vermerkt.
  - Drei Arbeiten von Plews habe ich über die Dissertation gelesen, nicht in der Verlagsfassung. Dort steht für die SWC 0,5 × CV, während Buchheit [C5] Plews 1 × CV zuschreibt; das ist nicht aufgelöst.
- **Korrekturen am Auftrag bzw. an `../puls/METHODIK`:**
  - Plews 2017 maß 5 min, nicht 60 s.
  - Esco 2017 nutzte wohl einen externen Fingersensor, keine Kamera (nur aus [B2] erschlossen).
  - Schäfer und Vagedes stützen „PRV in Ruhe brauchbar“, betonen aber eine Überschätzung der Kurzzeitvariabilität.
  - Esco und Flatt 2014 und Munoz 2015 stützen 60 s bzw. 30 s für RMSSD, beide aber nicht mit Kamera.
- **Bánhalmi, Tabelle 1:** Die ms-Zeile (SD 1,8 ms) und die ln-Zeile (SD 0,15) passen nur zusammen, wenn kleine RMSSD-Werte die ln-Differenzen dominieren. Die Studie nennt keine mittleren RMSSD-Werte. Ich übernehme beide Zeilen wie veröffentlicht.
- **Rechnungen:**
  - Die Verteilungen sind frei angenommen, die Rechnungen zeigen Empfindlichkeiten, keine Häufigkeiten.
  - Wie groß Kamerafehler (`sm`), Tagesstreuung (`sb`), Lückenquote und Fehlmessungen in Wirklichkeit sind, klärt erst die Validierung.
  - Die Ergebnisse hängen in B nur vom Verhältnis `sm/sb` ab. Das zeigen die identischen Zeilen für sb 0,10 und 0,15 ohne Kamerafehler und B4 (sb 0,33 mit +4·sb gleich sb 0,10 mit +0,4).
  - In der ersten Fassung war die Tagesstreuung als „CV 8–12 %“ mit Prozentänderungen von RMSSD vermischt und als ≈ 10 % gedeutet. Richtig ist eine SD von etwa 0,33 ln. Die Kerntabellen von B galten weiter, ihre Deutung (absolute Grenze, Wirkung der Fehlmessungen, Größe der Effekte) ist berichtigt.
  - Rechnung D nimmt an, dass d normalverteilt ist und nicht vom H9-Wert abhängt (außer über β), und dass verworfene Messungen zufällig fehlen. Verwirft die Qualitätsgrenze bevorzugt Tage mit kleinem RMSSD (dort ist das Zeitrauschen am stärksten), wird die Tages-SD der zugelassenen Tage kleiner als die aller Tage; deshalb wird sie über alle H9-Morgen geschätzt. Ausreißer in d machen die SD-Schätzung unruhiger als in D.
  - Der echte Abfall betrifft auch Tage, die in der Referenz liegen (Überlappung wie in PAR-161). Das senkt die Erkennung leicht und entspricht der Regel.
  - Die Fehlmessungen sind nur nach oben modelliert (PRV überschätzt).
- **Mögliche Fehler im eigenen Aufbau:**
  - Die KI-Näherung √(3/n) ist bei n = 10 leicht zu schmal (Deckung 92,6 %); ab n = 21 trifft sie.
  - Rechnung C ist stationär, also eine Untergrenze. Sie unterschätzt die Literatur (0,069 gegenüber ~0,11 SD), wie erwartet.
  - Bei den Ruhepuls-Rechnungen erhöht das Runden die Verfügbarkeit nur, weil es die MAD künstlich vergrößert. Das ist kein Vorteil des Rundens, sondern zeigt die Schwäche der festen MAD-Grenze.
- **Nicht gefunden:**
  - eine Primärquelle für einen „normal range“ über 60 Tage;
  - eine Sportstudie zur Reihenfolge Toilette und Messung;
  - Zahlen zur Übereinstimmung 60 s im Sitzen;
  - eine Studie zu 60 s Kamera gegen EKG **innerhalb einer Person über viele Tage** (Holmes 2020 vergleicht zwischen Personen).

## Offene Punkte und Folgeanalysen
1. **Validierung durchführen** (Abschnitt 6). Folgeanalyse, z. B. R0xx, mit einer neuen Sammlung `research/input/kamera-h9-morgen-<datum>/` (privat, nur lokal, nie ins Repo).
2. **RMSSD-Qualitätsgrenze** (Zeitrauschen) aus der Validierung festlegen, mit wochenweiser Kreuzvalidierung (Abschnitt 6).
3. **Entscheidungen des Maintainers:**
   - E1–E7 sind am 2026-11-09 entschieden (Abschnitt 5a); offen ist die Übernahme ins Konzept (Project Supervisor).
   - **Erledigt (2026-11-09):** Die Auslegung von E7b ist entschieden: Ein Kamera-Ruhepuls mit „nicht bestanden“ erscheint in der eingeschränkten Einschätzung als markierte Tatsache („ungenauer als erwartet“), nie in einer Zahl oder einem Faktor (Abschnitt 5a). Ebenso entschieden: E7c (freigegeben wird das Verfahren, nicht ein Gerät).
4. **Empfohlene Folgeanalyse: Validierung im Sitzen** (wegen E6, „vorerst“). Gleicher Plan wie Abschnitt 6, aber sitzend, eigene Sammlung. Grund: Die Abweichung wächst von liegend zu sitzend [B6], Holmes fand sitzend breite LoA [B19]. Bis dahin gilt das Opt-in sitzend nur vorläufig mit „liegend verglichen“; ergibt die Validierung „eingeschränkt“ oder „nicht bestanden“, wird RMSSD sitzend gesperrt (E7a).
4a. **Erneute Validierung** nach „eingeschränkt“ oder „nicht bestanden“ nur nach einer dokumentierten Änderung des Verfahrens (Algorithmus oder Protokoll), nicht nach einem Gerätewechsel allein (E7c), nach den Regeln in Abschnitt 6 (neue Morgen, gleicher Plan, alle Läufe berichtet). **Offen bleibt der Einfluss des Geräts:** Das Verfahren wird für alle Geräte freigegeben, geprüft ist es auf einem Handy (Grenzen von n = 1). Eine spätere Prüfung je Nutzer mit eigenem Gurt (E2, zurückgestellt) oder eine Validierung mit mehreren Handys würde das verkleinern.
4b. **MAD-Grenze 0,5/min für den Ruhepuls** nach der Validierung prüfen: Sie misst sm und die Tages-SD des Pulses; die Begründung hängt an sm ≈ 1/min (Rechnung B, Punkt 5).
5. FR-0214: Ruhephase 4 min auf 5 min anheben? Anleitung ohne Atemtempo; Profilvorschlag aus dem Median der Morgenwerte.
6. Ob eine Korrektur des RMSSD um das Zeitrauschen (RMSSD² − 6·σ_t²) hilft, ist eine Frage an den Algorithmus in `../puls`, nicht Teil dieses Auftrags.

## Quellen
Zugriff: **V** = Volltext geprüft, **A** = nur Abstract geprüft, **D** = über die Dissertation von Plews (AUT 2014, https://openrepository.aut.ac.nz/handle/10292/7122) statt der Verlagsfassung. Bekannte IDs aus `docs/phase-2-3-rules.md` in Klammern.

**Protokoll, Ruhepuls**
- [A1] Buchheit M 2014, Front Physiol 5:73, doi:10.3389/fphys.2014.00073, PMC3936188 (= Q27) – V
- [A2] Laborde S, Mosley E, Thayer JF 2017, Front Psychol 8:213, doi:10.3389/fpsyg.2017.00213, PMC5316555 – V
- [A3] Task Force ESC/NASPE 1996, Circulation 93:1043 bzw. Eur Heart J 17:354 – V (EHJ-Fassung)
- [A4] Besson C et al. 2025, Sci Rep 15:5611, doi:10.1038/s41598-025-89892-3, PMC11829968 – V
- [A5] Esco MR, Flatt AA 2014, J Sports Sci Med 13:535, PMC4126289 – V (Ergebnistext selbst nachgeprüft)
- [A6] Flatt AA, Esco MR 2016, Clin Physiol Funct Imaging 36:331, doi:10.1111/cpf.12233 – A
- [A7] Saboul D, Pialoux V, Hautier C 2013, Eur J Sport Sci 13:534, doi:10.1080/17461391.2013.767947 – A
- [A8] Laborde S et al. 2022, Neurosci Biobehav Rev 138:104711, doi:10.1016/j.neubiorev.2022.104711 – A
- [A9] Munoz ML et al. 2015, PLoS ONE 10:e0138921, PMC4586373 – V
- [A10] Quer G et al. 2020, PLoS ONE 15:e0227709, PMC7001906 – V
- [A11] Pecchia L et al. 2018, Healthc Technol Lett 5:94, PMC5998753 – V
- [A12] Palatini P et al. 2016, J Hypertens 34:813, PMID 26982382 – A (Palatini 2006, J Hypertens 24:603: nicht geprüft)
- Nussinovitch U et al. 2011, Ann Noninvasive Electrocardiol 16:117 – A (ergänzend)

**Smartphone-PPG, Validierung**
- [B1] Plews DJ et al. 2017, Int J Sports Physiol Perform 12:1324, doi:10.1123/ijspp.2016-0668 – A
- [B2] Bánhalmi A et al. 2018, J Healthc Eng 2018:4038034, PMC5832098 – V (Tabelle 1 selbst nachgeprüft)
- [B3] Peng RC et al. 2015, Comput Math Methods Med 2015:516826, PMC4309304 – V
- [B4] Guede-Fernández F et al. 2015, IEEE EMBC 2015:7332, doi:10.1109/EMBC.2015.7320085 – A
- [B5] Moya-Ramon M et al. 2022, Comput Methods Programs Biomed 217:106696 – A
- [B6] Esco MR, Flatt AA, Nakamura FY 2017, J Strength Cond Res 31:380, doi:10.1519/JSC.0000000000001519 – A
- [B7] Yan BP et al. 2017, JMIR Mhealth Uhealth 5:e33, PMC5368348 – V
- [B8] Mather JD et al. 2024, Front Digit Health 6:1326511, PMC10937558 – V
- [B9] Heathers JA 2013, Int J Psychophysiol 89:297 – A
- [B10] Schäfer A, Vagedes J 2013, Int J Cardiol 166:15, doi:10.1016/j.ijcard.2012.03.119 – A
- [B11] Mejía-Mejía E et al. 2020, Physiol Meas 41:07TR01 – V (akzeptiertes Manuskript)
- [B12] Bland JM, Altman DG 1986, Lancet 1:307 – V
- [B13] Bland JM, Altman DG 1999, Stat Methods Med Res 8:135 – A
- [B14] Bland JM, Altman DG 2007, J Biopharm Stat 17:571 – V (eingereichte Fassung)
- [B15] Bland JM, FAQ Fallzahl, www-users.york.ac.uk/~mb55/meas/sizemeth.htm – V
- [B16] Lu MJ et al. 2016, Int J Biostat 12(2), doi:10.1515/ijb-2015-0039 – A
- [B17] Mühlen JM et al. 2021, Br J Sports Med 55:767, PMC8273688 – V
- [B19] Holmes CJ, Fedewa MV, Winchester LJ, MacDonald HV, Wind SA, Esco MR 2020, Sensors 20:5738, doi:10.3390/s20205738, PMC7600564 – V (Tabellen 1 und 2 selbst nachgeprüft)
- [B20] van Dijk W, Huizink AC, Oosterman M, Lemmers-Jansen ILJ, de Vente W 2023, Psychosom Med 85(7):568–576, doi:10.1097/PSY.0000000000001236, https://research.vu.nl/en/publications/validation-of-photoplethysmography-using-a-mobile-phone-applicati/ – A
- [B18] ANSI/AAMI EC13 – nicht geprüft (kostenpflichtig); Sekundärbeleg Pstras et al. 2025, Front Physiol, PMC12505149 – V

**Auswertung täglicher Werte**
- [C1] Plews DJ et al. 2012, Eur J Appl Physiol 112:3729, doi:10.1007/s00421-012-2354-4 – A + D
- [C2] Plews DJ et al. 2013, Sports Med 43:773, doi:10.1007/s40279-013-0071-8 (= N18) – A + D
- [C3] Plews DJ et al. 2013, Int J Sports Physiol Perform 8:688, doi:10.1123/ijspp.8.6.688 – A + D
- [C4] Plews DJ et al. 2014, Int J Sports Physiol Perform 9:783, doi:10.1123/ijspp.2013-0455 (= N19) – A + D
- [C5] = [A1] Buchheit 2014 (= Q27) – V
- [C6] Kiviniemi AM et al. 2007, Eur J Appl Physiol 101:743 (= N22) – A
- [C7] Kiviniemi AM et al. 2010, Med Sci Sports Exerc 42:1355 – A
- [C8] Vesterinen V et al. 2016, Med Sci Sports Exerc 48:1347 (= N21) – V (akzeptiertes Manuskript, JYX 50625)
- [C9] Javaloyes A et al. 2019, Int J Sports Physiol Perform 14:23 – A
- [C10] Altini M, Plews D 2021, Sensors 21:7932, PMC8659706 – V
- [C11] Flatt AA, Esco MR 2016, J Strength Cond Res 30:378 – A
- [C12] Le Meur Y et al. 2013, Med Sci Sports Exerc 45:2061 – A
- [C13] Nuuttila OP et al. 2024, Sports Med Open 10:120, PMC11541970 (= N23) – V
