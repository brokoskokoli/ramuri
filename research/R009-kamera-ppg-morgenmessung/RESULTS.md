# R009 – Ergebnis

## Kurzfassung
**Ruhepuls mit der Kamera (FR-0214) ist gut gedeckt.** In Ruhe stimmt der Fingerpuls aus der Kamera auf etwa ±2/min mit dem EKG überein [B7, B2, B8]. 60 s reichen dafür. Ruhepuls heißt hier: Ruhe vorher, immer dieselbe Haltung, kein Koffein vorher. Er ist nicht der Schlafpuls einer Uhr [A10].

**RMSSD aus 60 s Kamera mit rund 30 Bildern/s ist nicht belegt.** Das Messfenster an sich trägt: 60 s gegen 5 min ergibt lnRMSSD mit LoA ±0,22, gemessen liegend mit EKG [A5]. Für eine 60-s-Kameramessung gegen EKG fand ich keine Studie mit Übereinstimmungsgrenzen. Zwei Quellen sprechen dagegen: eine Kamerastudie mit 20–30 Bildern/s überschätzte RMSSD deutlich [B3], und eine Methodenempfehlung rät ausdrücklich von Kamera-Apps für HRV ab [A2]. Gut stimmte es nur mit 240 Bildern/s über 5 min [B2].

**Tageswerte nur als 7-Tage-Mittel bewerten.** Das stützt die Literatur, ebenso mindestens 3 Messungen pro Woche (bei Freizeitsportlern eher 5), eine Basis von 2–4 Wochen und die Grenze „Mittel ± 0,5 SD“ [C1–C5, C8, C13]. Die Rechnungen zeigen, was die Kamera kosten darf: Eine Messstreuung von der halben Tagesstreuung kostet wenige Prozentpunkte Erkennung, eine gleich große etwa 12 Punkte.

**Empfehlung:**
- WP27 übernimmt das Protokoll unten für FR-0214.
- FR-0215 wird **mit Auflage** freigegeben. Ruhepuls zählt sofort. RMSSD geht erst in die Readiness ein, wenn die Validierung gegen Polar H9 bestanden ist (2–4 Wochen täglich, n = 1, Kriterien unten).
- Für M3 eine neue Regelversion (Vorschlag „K-1“, Abschnitt 5). Dazu gehört eine Entscheidung des Maintainers zu OQ-0006: Darf es eine Zahl ohne Schlafdaten der Uhr geben, mit freiwilliger Selbstangabe der Schlafdauer?

## Lauf
- **Datum:** 2026-11-09. **Rechner:** Mac, Apple M3 Pro (arm64), macOS, Python 3.15.0, nur Standardbibliothek.
- **Kommando:** `./init.sh && ./run.sh --seed 1 --reps 4000`. Lauf `research/data/work/R009/20261109-205242/` auf Commit `171378a` (`dirty=0`). Laufzeit 19 s (A 10 s, B 8 s, C 1 s).
- **Literatur:** im Original geprüft, je Quelle vermerkt, ob Volltext oder nur Abstract (Quellenliste am Ende). Drei Teilrecherchen liefen parallel als Sub-Agenten. Kernstellen habe ich selbst nachgeprüft: Bánhalmi, Tabelle 1, und Esco und Flatt 2014, Ergebnisse.
- **Kontrollen im Code:**
  - t-Quantile gegen Tabellenwerte (Assertion).
  - Handrechnung KI bei n = 21.
  - Erwartete MAD = 0,6745·SD.
  - Aufschlag durch Zeitrauschen analytisch: RMSSD'² ≈ RMSSD² + 6·σ_t².
  - R8 nachgerechnet: SD von `z` bei AR 0 / 0,3 / 0,6 hier 1,06 / 1,30 / 1,69, in R8 1,05 / 1,31 / 1,70.

## 1. Messprotokoll (Literatur)

| Punkt | Befund | Quellen | Vorschlag |
| --- | --- | --- | --- |
| Zeitpunkt | Bewährt ist eine kurze Messung direkt nach dem Aufwachen: „best practice … upon awakening in the morning“. Die Studien messen im Liegen nach dem Aufwachen. | [A1, C3, C10] | Morgens nach dem Aufwachen, jeden Tag zur ähnlichen Zeit. |
| Toilette, Koffein | Laborempfehlung: vorher zur Toilette, 2 h kein Kaffee, kein Essen. Eine Feldstudie mit Messung zu Hause beim Aufwachen: „on an empty bladder“, ohne Koffein und Nikotin. Für die Reihenfolge Toilette dann Messung gibt es keine Sportstudie mit eigener Begründung. | [A2, A4] | Erst Toilette, dann messen, vor Kaffee und Frühstück. Gleiche Reihenfolge jeden Tag (eigene Wahl). |
| Haltung | Liegend ist am besten untersucht und streut am wenigsten: CV lnRMSSD liegend 8,2 %, stehend 16,1 %. Sitzend ist bequem und man schläft nicht wieder ein, dazu gibt es aber keine Zahlen. Die Abweichung der Kamera zum EKG wächst von liegend über sitzend zu stehend (60 s, externer Fingersensor). Stehend ist der Puls rund 25/min höher. | [A1, C13, B6, A4, B11] | Wählbar liegend oder sitzend, **Vorgabe liegend**, nie stehend. Wechselt die Haltung, beginnt eine neue Reihe (FR-0115). |
| Ruhephase | 1 min Stabilisierung liegend reichte für 1-min-Segmente (ICC 0,92–0,97, nur Abstract). Im Labor gelten „at least 5 min“ in der Haltung. | [A6, A2] | Morgenmessung: **1–2 min**, jeden Tag gleich. Profil tagsüber (FR-0214): **≥ 4–5 min**; die 4 min aus FR-0214 liegen knapp unter Labordes 5 min. |
| Atmung | Spontane Atmung ist Konsens für Ruhemessungen. RMSSD reagiert wenig auf das Atemmuster. Geführte und spontane Atmung unterschieden sich aber signifikant, korrelierten jedoch (r > 0,70). Langsame Atmung erhöht vagal vermittelte HRV während der Übung **und direkt danach** (Metaanalyse, nur Abstract). | [A2, A1, A7, A8] | Während der Messung **spontan atmen**. Die beruhigende Anleitung aus FR-0214 ohne vorgegebenes Atemtempo (keine 6/min), immer gleich lang. Für die Morgenreihe sonst Verzerrung nach oben, die je nach Tag unterschiedlich lang wirkt. |
| Dauer 60 s vs. 5 min | lnRMSSD aus 60 s gegen 5 min (liegend, EKG, morgens, Spontanatmung): ICC 0,98, Bias ± LoA 0,00 ± 0,22. Fingerpuls (Portapres) 30 s gegen 4–5 min: r = 0,93, LoA −0,34 bis +0,45. Einschränkung: Die kurzen Stücke stammen aus derselben Aufnahme; das gilt als methodisch schwach („a correlate does not make a surrogate“). Die Task Force bevorzugt 5 min, RMSSD sei aber kurz messbar. | [A5, A9, A11, A3] | **60 s** bleiben (FR-0214). Für den Puls unkritisch. Für RMSSD trägt die Fensterlänge, nicht aber die Kamera (siehe 3). |
| ln RMSSD | Log-Transformation wegen ungleicher Varianz: „natural logarithm of RMSSD“. Sie ist in allen Monitoring-Studien Standard. | [A2, C1–C4] | Auswertung auf `ln(RMSSD)`, wie PAR-161. |
| Wiederholen | In keiner Quelle geregelt. Wählt man die beste von mehreren Messungen, verzerrt das die Reihe (eigene Überlegung). | – | Es zählt **die erste Messung mit ausreichender Qualität**. Wiederholen nur, wenn die Qualität nicht reicht. |

Rechnung C dient als Plausibilitätsprüfung für die Fensterlänge. In einer stationären synthetischen Reihe streut ln RMSSD(60 s) gegenüber ln RMSSD(300 s) mit SD 0,069. Das ergibt LoA ±0,14 und ist eine Untergrenze. Die Literatur nennt ±0,22 [A5], also eine SD von etwa 0,11. Das passt: Echte Reihen sind nicht stationär.

## 2. Ruhepuls: Definition, morgens oder tagsüber, Haltung
- Eine verbindliche Definition aus erster Hand habe ich nicht gefunden. Das ESH-Konsenspapier von 2006 ist kostenpflichtig und nicht geprüft. Das ESH-Papier von 2016 (nur Abstract) verlangt anzugeben: Länge der Ruhe vorher, Methode, Dauer, Anzahl der Messungen und Körperhaltung [A12]. Daraus folgt nur: Diese Bedingungen festlegen und gleich halten.
- Der Tracker-Ruhepuls von Fitbit wird „primarily calculated during periods of sleep“ [A10]. Er ist also nicht derselbe Wert wie ein Ruhepuls im Wachzustand. FR-0115 gilt deshalb auch für den Ruhepuls: Kamera und Health Connect bilden getrennte Reihen.
- Die Haltung wirkt groß: liegend gegenüber stehend rund 25/min [A4]. Der Morgenwert liegend ist der niedrigste und am besten reproduzierbare Wert. Ein Ruhepuls tagsüber im Sitzen liegt höher (Richtung belegt, Größe für sitzend nicht).
- **Für das Profil (FR-0214):** Der Wert dient der Zonenberechnung, Haltung und Zeitpunkt werden mit gespeichert. Vorschlag: Liegen Morgenmessungen vor, schlägt die App den Median der letzten 7 gültigen Morgenwerte vor, statt eines Einzelwerts tagsüber (eigene Wahl; die Streuung von Tag zu Tag ist groß, CV 6,8 % liegend [C13], wöchentliche Schwankung im Median 3/min [A10]).

## 3. Smartphone-PPG gegen EKG in Ruhe, PRV ≠ HRV

| Studie | Aufbau | Puls | RMSSD / lnRMSSD | Zugriff |
| --- | --- | --- | --- | --- |
| Bánhalmi 2018 [B2] | n = 50, sitzend, 5 min, iPhone 6 mit **240 fps**, strenge Artefaktfilter (±20 % vom Median) | Bias 0,03, SD 0,11/min | RMSSD Bias +2,5 ms, SD 1,8 ms; ln Bias +0,10, SD 0,15 (LoA −0,20 bis +0,40) | Volltext, selbst nachgeprüft |
| Peng 2015 [B3] | n = 30, liegend, ≥ 5 min, **20–30 fps** schwankend, auf 800 Hz interpoliert | AVNN −0,05 ± 0,55 ms | RMSSD **+33 bis +68 ms** zu hoch (je nach Gipfelerkennung), „insufficient agreement“ | Volltext |
| Plews 2017 [B1] | n = 29, Ruhe, **5 min** (nicht 60 s), HRV4Training-Kamera | – | TEE 6,35 % (90 % KI 5,13–8,5), r = 1,00 | nur Abstract |
| Esco 2017 [B6] | n = 30, **60 s**, liegend/sitzend/stehend, App mit Pulssensor (laut [B2] externer Infrarot-Fingersensor, keine Kamera) | – | lnRMSSD×20: LoA −0,13 ± 2,83 / −0,94 ± 3,47 / −1,37 ± 3,56, umgerechnet ≈ ±0,14 / ±0,17 / ±0,18 ln | nur Abstract |
| Moya-Ramon 2022 [B5] | n = 26 Radprofis, 1 und 5 min, liegend/sitzend, Apps | – | r = 0,77–0,94, SEM < 6 %, keine LoA im Abstract | nur Abstract |
| Yan 2017 [B7] | n = 40, 20 s, Finger und Gesicht | LoA in Ruhe −1,98 bis +2,07/min | – | Volltext |
| Guede-Fernández 2015 [B4] | Android, 30 Hz | – | Fehler je Schlag bis 7,8 ± 3,8 ms, deutlicher Einfluss des Geräts | nur Abstract |

**PRV ≠ HRV:** In Ruhe ist PRV ein ausreichender Ersatz, „although … short-term variability is somewhat overestimated by PRV“. Bei Belastung und Stress wird die Übereinstimmung schlechter [B10, nur Abstract]. Haltungswechsel und Umgebungstemperatur verändern das Verhältnis, ebenso eine niedrige, ungleichmäßige Bildrate der Kamera [B11]. Bei gesunden, jungen Personen in Ruhe gilt PRV als Alternative [B11]. Die Abweichung zeigt durchgehend nach oben: [B2, B3, B9, B10].

**Zeitrauschen als Mechanismus (Rechnung C, analytisch und simuliert):** Unabhängiges Rauschen σ_t in den Schlagzeitpunkten erhöht RMSSD² um etwa 6·σ_t². Bei RMSSD 40 ms ergibt σ_t = 5 / 10 / 15 ms in ln +0,045 / +0,16 / +0,31. Der Aufschlag hängt vom Niveau ab und schwankt mit der Signalgüte des Tages. Er wirkt deshalb in der Reihe nicht als fester Bias, sondern als zusätzliche Streuung.

Die Grenze „Zeitrauschen > 25 ms → eingeschränkt“ aus `../puls` (ALGORITHMUS 5.5b) liegt weit über dem Bereich, in dem RMSSD noch brauchbar wäre. Unter der Annahme, dass das dort geschätzte Zeitrauschen dem σ_t hier entspricht, ergäbe sie bei RMSSD 40 ms einen Aufschlag von rund +0,6 ln. Für FR-0215 braucht RMSSD daher eine **eigene, strengere Qualitätsgrenze**. Die Validierung legt sie fest; diese Analyse schlägt keinen Wert vor und ändert den Algorithmus nicht.

**Folgerung:** Für den Ruhepuls ist die Kamera belegt. Für RMSSD aus 60 s mit 30 fps fehlt der Beleg, und es gibt Gegenbelege [A2, B3]. Eine eigene Vergleichsmessung des Maintainers mit `../puls` gegen Polar H9 verlief laut OQ-0078 gut. Es ist aber eine einzige Messung, sie ersetzt keine Validierung. Die Zahlen stehen absichtlich nicht hier.

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

**Größenordnung:** Altini und Plews fanden in 9 Mio. Kamera- und Sensormessungen am Tag nach Training −4,6 % HRV, nach viel Alkohol −12 %, bei Krankheit −10 % [C10]. Die Streuung von Tag zu Tag liegt im selben Bereich: lnRMSSD liegend CV 8–12 % [C13, C2, C5].

**Zweifel:** Manche Quellen berechnen den CV auf den ln-Werten (Plews), andere auf RMSSD. Die Tagesstreuung in ln-Einheiten ist deshalb nur grob bekannt. Die Validierung soll sie für die eigene Reihe schätzen.

### Rechnung B: 7-Tage-Mittel nach PAR-161/162 bei Lücken und Kamera-Streuung
Modell wie R8:
- Tageswerte AR(1) mit biologischer SD `sb`, dazu Kamerafehler `sm`.
- Fehlende Tage: zufällig mit Anteil `p` oder „nur Werktage“.
- Fehlmessungen, die die Qualitätsprüfung passieren: Anteil `q`, lnRMSSD +0,4, Ruhepuls +4.
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
| sb 1,5, sm 1, 20 % Lücken: MAD-Grenze 1 gegenüber 0,5 | 61 % gegenüber 79 % bei gleicher Trennschärfe (kal7 61 % gegenüber 59 %) | – |

**Was das heißt:**
1. **Kamerafehler bis zur halben Tagesstreuung kosten wenig:** 3–4 Punkte nach 7 Tagen (74 → 70 %). Ein gleich großer Fehler kostet ~12 Punkte (→ 62 %). Mit 20 % Lücken und 5 % Fehlmessungen liegt ein 1,5-facher Fehler 13 Punkte unter einem halben (47 gegenüber 60 %). Daraus folgt die Akzeptanzgrenze in Abschnitt 6.
2. **Lücken kosten vor allem Verfügbarkeit.** Da der heutige Wert Pflicht ist, fehlt die Zahl an jedem Tag ohne Messung. Die Trennschärfe sinkt nur mäßig. „Heute nicht Pflicht“ brächte 99 % Verfügbarkeit bei gleicher Trennschärfe; dann gäbe es aber eine Zahl ohne frische Messung.
3. **Fehlmessungen, die durch die Qualitätsprüfung rutschen,** verbreitern `z` und kosten etwa 6 Punkte. Die Qualitätsgrenze für RMSSD ist deshalb wichtig.
4. **Das 7-Tage-Mittel erkennt einen anhaltenden Abfall nach 3–7 Tagen besser, der Einzeltag am ersten Tag.** Das deckt sich mit [C1, C3] und mit PAR-161, das Mittel bleibt also. Die Varianten Referenz ohne Fenster und k ≥ 4 ändern bei gleicher Fehlalarmrate nichts und werden nicht empfohlen.
5. **Ruhepuls: Die Grenze „MAD < 1/min → kein z“ aus PAR-162 ist für die Kamera zu grob.** Bei sehr gleichmäßigem Ruhepuls (SD ≈ 1,5/min) sperrt sie bei Werten mit Nachkommastelle die Hälfte der Tage. Die Grenze war für ganzzahlige Werte aus Health Connect gedacht. Eine SD von 1,5/min liegt eher am unteren Rand (CV 6,8 % liegend [C13] entspricht bei 55/min ≈ 3,7/min). Das betrifft also nur sehr gleichmäßige Personen.
6. **Die Größe des Effekts relativieren:** Ein Abfall um 1 Tages-SD (≈ 10 %) wird auch nach 7 Tagen nur zu 60–74 % erkannt. Trainingsbedingte Änderungen von ~5 % [C10] sind also kaum sicher sichtbar. Das stützt die zurückhaltenden Texte (FR-0117, FR-0118).

## 5. Vorschlag: Regelversion „K-1“ (Kamera-Morgenmessung) für M3
Nur ein Vorschlag. Das Regelwerk `docs/phase-2-3-rules.md` bleibt unverändert, entscheiden muss der Maintainer. Nummern mit Suffix K bezeichnen die Kameravariante der jeweiligen Regel; die Health-Connect-Regeln bleiben daneben bestehen.

| ID (Vorschlag) | Regel | Art | Begründung |
| --- | --- | --- | --- |
| PAR-160K | **Gültiger Kamera-Morgenwert.** Eine Messung nach Protokoll: Haltung wie gespeichert, 1–2 min Ruhe, 60 s, spontane Atmung. Sie liegt im Morgenfenster des Nutzers (Vorgabe 4–11 Uhr, einstellbar). Es zählt die **erste** Messung des Tages mit ausreichender Qualität. Ruhepuls gilt bei Qualität „gut“ oder „eingeschränkt“, RMSSD nur bei „gut“ **und** unter der RMSSD-Qualitätsgrenze aus der Validierung. Wertebereiche: RMSSD 1–200 ms (wie PAR-160), Ruhepuls PAR-017. Eine eigene Reihe je Haltung und Gerät, nie gemischt mit Health Connect. | Heuristik, Evidenz niedrig | Abschnitte 1–3; FR-0115; Gerät beeinflusst [B4]; Zeitrauschen erhöht RMSSD (Rechnung C). Das Morgenfenster ist eigene Wahl, weil ohne Schlafdaten die Aufwachzeit fehlt. |
| PAR-161K | wie PAR-161: Mittel aus `k` ≥ 3 gültigen Werten der letzten 7 Tage, heute Pflicht, Referenz 28 Tage mit ≥ 14 gültigen Werten, Nenner `1,4826·MAD/√k`, MAD < 0,02 → kein `z`. **Neu:** Hat die Reihe in den letzten 7 Tagen weniger als 5 gültige Werte, sagt die Erklärung „wenige Messungen, weniger verlässlich“. | Heuristik | [C4, C5]; Rechnung B: Varianten bringen nichts, das Mittel schlägt den Einzeltag ab Tag 3. |
| PAR-162K | wie PAR-162, aber Ruhepuls mit einer Nachkommastelle und **MAD-Grenze 0,5/min** statt 1 | Heuristik | Rechnung B, Punkt 5. Die Grenze 1 bleibt für ganzzahlige Werte aus Health Connect. |
| PAR-163 | unverändert | – | [C12, C2] stützen, dass die Anzeige nur die Abweichung beschreibt. |
| PAR-164K/165K | **Schlafdauer ohne Uhr:** freiwillige Selbstangabe bei der Morgenmessung in Stufen (unter 5, 5–6, 6–7, 7–8, über 8 h). Sie geht mit der Stufenmitte in PAR-165 ein und ist als Selbstangabe markiert; die Effizienz (PAR-166) fehlt. | Heuristik, Evidenz keine | Mit dem Maintainer vereinbart („Messung + 1–2 Tipps“). Ohne Schlafwert erfüllt sonst niemand ohne Uhr OQ-0006. Grobe Stufen vermeiden Scheinpräzision (FR-0114). |
| PAR-169K | **Option „Schlafgefühl 1–5“** bei der Morgenmessung als Tagesangabe für das Befinden statt der Angabe beim letzten Lauf | Heuristik, Evidenz niedrig | Subjektive Maße reagieren empfindlich [N24 im Regelwerk]. **Konflikt:** PAR-169 hat eine Tagesangabe ausdrücklich abgelehnt. Nur auf Entscheidung des Maintainers. |
| PAR-170 | unverändert (Kappung 74 ohne Belastungsfaktor) | – | – |
| PAR-171K | Zahl nur nach der neuen Fassung von OQ-0006 (unten). Sonst „Eingeschränkte Einschätzung“, wenn **eine** frische Messung (Kamera oder Health Connect) oder Schlaf vorliegt, mit den Tatsachen („Ruhepuls heute 3/min über deinem Mittel“). Sonst „Unzureichende Daten“. | abgeleitet | erweitert PAR-171 um den Fall „Kamera ohne Schlaf“ |
| Validierungssperre | Bis die Validierung (Abschnitt 6) bestanden ist, geht nur der Kamera-Ruhepuls ein. RMSSD wird angezeigt, aber als „noch nicht geprüft“ markiert und nicht gewertet. Fällt die Validierung durch, bleibt das dauerhaft so. | Entscheidungsvorschlag | Abschnitt 3 |

**OQ-0006, neue Fassung (Vorschlag):** Eine Zahl erscheint nur mit
- einer aktuellen HRV, nächtlich aus Health Connect **oder** als gültiger Kamera-Morgenwert nach bestandener Validierung,
- einer Schlafdauer der letzten Nacht, aus Health Connect **oder** als Selbstangabe,
- einer persönlichen Referenz derselben Reihe aus mindestens 14 gültigen Werten in 28 Tagen.

Ohne jede Schlafangabe gibt es keine Zahl, sondern die eingeschränkte Einschätzung (PAR-171K). Begründung: Der Schlaf hat das größte Gewicht (30 %, FR-0110). Ein Wert ohne ihn würde nur durch Herausrechnen entstehen, und das soll fehlende Daten nicht verbessern (FR-0111).

**Option B für den Maintainer:** eine Zahl auch ohne Schlaf. Dann gilt die Kappung 74 wie bei fehlender Belastung (PAR-170), „Gut erholt“ ist nicht erreichbar und der Text nennt den fehlenden Faktor. Die Rechnungen sprechen weder für noch gegen eine der beiden Optionen; das ist eine Produktentscheidung.

**Mindestmengen für den Nutzer:**
- Die erste Zahl kommt nach 14 gültigen Morgenwerten, frühestens nach 2 Wochen.
- Empfohlen sind 5 oder mehr Messungen pro Woche, mindestens 3.
- Die Erinnerung bleibt freiwillig (FR-0215).

**Texte (FR-0118, FR-0149):**
- Kein Vergleich mit Bevölkerungswerten (FR-0112).
- Der Hinweis „Kamerawerte sind nicht mit Uhrwerten vergleichbar“ steht dabei.
- Verworfene unregelmäßige Schläge werden **nicht** als Herzrhythmus gedeutet. Die App sagt nur „Messung nicht auswertbar“.
- Ein hoher Wert erhöht nie die Belastung (PAR-173).

## 6. Validierungsplan gegen Polar H9 (n = 1, 2–4 Wochen)

**Aufbau:**
- **Wer und womit:** der Maintainer, sein Handy, 21–28 aufeinanderfolgende Morgen.
- **Ablauf am Morgen:** genau das Protokoll aus Abschnitt 1, Haltung fest und vorher gewählt. Der H9 läuft gleichzeitig und zeichnet RR-Intervalle auf (eine Logger-App mit RR-Export). Die Uhren beider Geräte werden abgeglichen.
- **Referenz:** RMSSD und Puls aus den H9-RR **im selben 60-s-Fenster**, ohne Interpolation. Ein offensichtlicher Artefakt wird nach fester Regel entfernt, die vorher festgelegt und für beide Seiten gleich ist.
- **Zusatz an 1–2 Tagen pro Woche:** gleich danach eine zweite Kameramessung (Wiederholbarkeit der Kamera allein).
- **Stresstests getrennt:** einzelne Messungen mit kalten Händen oder nach Bewegung, nicht in der Hauptauswertung.

**Auswertung:**
- Je Morgen die Differenz d = Kamera − H9 für Puls und lnRMSSD.
- Bland-Altman: Bias, LoA = Bias ± 1,96·SD, 95-%-KI der LoA ≈ ± t·√(3/n)·SD [B12, B15]. Dazu die Grafik Differenz gegen Mittel, um einen proportionalen Bias zu sehen.
- Lag-1-Autokorrelation der d prüfen.
- Die Tages-SD der H9-Reihe schätzen; sie ist der Bezug für die Akzeptanz von lnRMSSD.
- Qualitätsquote: Anteil gültiger Kameramessungen.
- Kalibrieren der RMSSD-Qualitätsgrenze (Zeitrauschen): die Grenze, unter der die Akzeptanz erfüllt ist. Wird sie an denselben Daten gesucht, an denen geprüft wird, ist das optimistisch. Deshalb Grenze nach den ersten 14 Tagen festlegen und an den restlichen Tagen prüfen.

**Akzeptanzgrenzen (vorab festgelegt):**

| Größe | Bestanden | Eingeschränkt | Nicht bestanden | Begründung |
| --- | --- | --- | --- | --- |
| Puls | LoA (Punktschätzung) innerhalb ±2/min | innerhalb ±3/min | darüber | Literatur Finger in Ruhe ±2/min [B7, B2]. Die übliche Norm (±5/min bzw. ±10 %) gilt für EKG-Geräte und schließt PPG aus [B18]. Für Änderungen von wenigen /min ist sie zu grob. |
| lnRMSSD | SD(d) ≤ 0,5 × Tages-SD der H9-Reihe | ≤ 1 × Tages-SD | darüber | Rechnung B: 0,5 kostet 3–4, 1,0 etwa 12 Punkte Erkennung. Der Bias zählt nicht, weil die Kamerareihe nie mit anderen gemischt wird (FR-0115), wird aber berichtet. Ein proportionaler Bias zählt. |
| Qualitätsquote | ≥ 80 % der Morgen mit gültigem Wert | 60–80 % | darunter | eigene Wahl. Rechnung B: Verfügbarkeit folgt direkt der Quote. |

**Fallzahl (Rechnung A, 4000 Läufe je Fall):**

| Tage n | Halbe KI-Breite Bias | Halbe KI-Breite LoA | Deckung des KI der LoA (AR 0) | (AR 0,5) |
| ---: | ---: | ---: | ---: | ---: |
| 14 | 0,57·SD | 0,98·SD | 93,5 % | 81,6 % |
| 21 | 0,45·SD | 0,78·SD | 94,5 % | 81,9 % |
| 28 | 0,38·SD | 0,67·SD | 95,1 % | 82,7 % |

Ein **formaler** Nachweis nach Lu et al. [B16] verlangt, dass das obere KI-Ende der LoA unter der Grenze Δ liegt. Bei 2–4 Wochen gelingt das nur, wenn die wahre SD(d) deutlich unter Δ liegt:
- SD = 0,25·Δ (Puls 0,5/min bei Δ 2): 99 % bei 21 Tagen.
- SD = 0,33·Δ (Puls 1/min bei Δ 3): 60 % bei 21 Tagen, 74 % bei 28 Tagen.
- SD = 0,5·Δ: ~0 %.
- Ein Bias von 0,5/min senkt das weiter (Tabelle A, Fälle mit `mu`).

**Folgerung für den Plan:**
- 28 Tage sind besser als 21.
- Die Entscheidung beruht auf der Punktschätzung, das KI wird berichtet.
- Ein Ergebnis „Punktschätzung erfüllt, KI überschreitet die Grenze“ heißt „vorläufig bestanden“, nicht „bewiesen“.
- Sind die Tagesdifferenzen autokorreliert (z. B. eine Woche mit kalten Händen), ist das KI zu schmal: Deckung 82 % statt 95 %. Bei Lag-1-Autokorrelation über 0,3 die KI-Breite deshalb um rund √((1+r)/(1−r)) erweitern (Näherung, eigene Wahl).

**Grenzen von n = 1:**
- Das Ergebnis gilt für eine Person, ein Handy, eine Haltung und die Jahreszeit der Messung.
- Andere Personen und Geräte sind nicht erfasst. Mühlen et al. empfehlen ≥ 45 Personen für eine Validierung [B17].
- Hauttemperatur, dunklere Haut und andere Geräte sind ungeprüft [B8, B4].
- Die App darf deshalb nicht behaupten, „validiert“ zu sein. Sie kann sagen: „mit einem Brustgurt verglichen“.

## Bewertung und Zweifel
- **Literatur:**
  - Volltext gelesen: Kernaussagen zu Puls, Ultrakurzzeit (liegend, EKG), Monitoring-Regeln [C1–C4 über die Dissertation von Plews, C5, C8, C10, C13], Bánhalmi, Peng, Laborde und Task Force.
  - Nur Abstract: unter anderem Plews 2017, Esco 2017, Schäfer und Vagedes 2013, Saboul 2013, Flatt und Esco 2016, Kiviniemi, Javaloyes, Moya-Ramon, Lu 2016 und die Metaanalyse zur langsamen Atmung. Alles ist in der Quellenliste vermerkt.
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
  - Die Ergebnisse hängen in B nur vom Verhältnis `sm/sb` ab. Das zeigen die identischen Zeilen für sb 0,10 und 0,15 ohne Kamerafehler.
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
  - eine EKG-Studie zu 60-s-Kamera-PPG mit LoA.

## Offene Punkte und Folgeanalysen
1. **Validierung durchführen** (Abschnitt 6). Folgeanalyse, z. B. R0xx, mit einer neuen Sammlung `research/input/kamera-h9-morgen-<datum>/` (privat, nur lokal, nie ins Repo).
2. **RMSSD-Qualitätsgrenze** (Zeitrauschen) aus der Validierung festlegen, mit Trennung zwischen Festlegen und Prüfen.
3. **Entscheidungen des Maintainers:**
   - OQ-0006 neue Fassung oder Option B;
   - Selbstangabe Schlafdauer;
   - Schlafgefühl statt Befinden beim letzten Lauf (Konflikt mit PAR-169);
   - Vorgabe der Haltung (liegend).
4. FR-0214: Ruhephase 4 min auf 5 min anheben? Anleitung ohne Atemtempo; Profilvorschlag aus dem Median der Morgenwerte.
5. Ob eine Korrektur des RMSSD um das Zeitrauschen (RMSSD² − 6·σ_t²) hilft, ist eine Frage an den Algorithmus in `../puls`, nicht Teil dieses Auftrags.

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
