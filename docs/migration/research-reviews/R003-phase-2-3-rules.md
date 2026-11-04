# R003 Research-Review: Regeln für Phase 2 und 3 (PAR-100 bis PAR-190)

**Urteil: NACHBESSERN**

Geprüft: `docs/phase-2-3-rules.md`, Version 1, Stand 2026-11-03. Review am 2026-11-04. Bewertet werden Methodik und Belege. Entscheidungen aus OQ und DEC werden nicht neu aufgerollt; wo ein Befund eine Folge daraus betrifft, ist das vermerkt.

**Kurzfassung:** Die Zitate sind überwiegend korrekt, alle NHS-Wochen stimmen, die meisten Rechnungen auch. Die Schwächen liegen in den Schlüssen. Eine automatische Planänderung hängt an einem verrauschten Tageswert und hat keinen Zeitbezug. Die Bandbreite weitet ältere Referenzen auch zur schnelleren Seite. Die Pace hängt nicht von der Blocklänge ab. Heuristiken sind mehrfach als `abgeleitet` eingestuft.

| Schwere | Gesamt | Typ `Wert` | Typ `Beleg/Text` |
|---|---:|---:|---:|
| Blocker | 3 | 3 | 0 |
| Muss | 12 | 4 | 8 |
| Soll | 11 | 3 | 8 |
| **Summe** | **26** | **10** | **16** |

## Geprüfter Umfang

**Zeilen:** alle 91 Zeilen PAR-100 bis PAR-190 gelesen (42 `abgeleitet`, 40 `Heuristik`, 9 `belegt`), dazu die Rechnungen R4 bis R8 und die 8 Rechenbeispiele aus Abschnitt 5.

**Quellen:** alle 44 Quellen der Liste abgerufen (L: 14, Q: 3, N: 27), zusätzlich 8 eigene Quellen zur Gegenprüfung.

| Prüftiefe | Quellen |
|---|---|
| Rohtext selbst gelesen | NHS-Plan und NHS-Bedingungen (HTML), NHS-PDF des Plans, alle PubMed-Abstracts über NCBI-E-Utilities, Norm [N16] (PDF), Android-Referenzen [L48, N26, N27, L43], Friel [Q17] |
| Über WebFetch, also durch ein Hilfsmodell zusammengefasst, Stellen nicht im Rohtext nachgelesen | [L9], [L25], [L38], [N5], [N12], [Q16], [Q27], Nuuttila-Volltext zu [N23], Relph 2023, c25k.com, Fitbit-Referenz |

**`nicht geprüft`**
- Vesterinen 2016 [N21], Volltext: Das Manuskript auf JYX lief zweimal in eine Zeitüberschreitung. Die Angaben zum 7-Tage-Mittel stammen aus einem Suchtreffer zu JYX-Dokumenten dieser Studie (Manuskript oder Masterarbeit Heikura 2015). Die Grenzen des SWC sind nicht geprüft.
- Daniels' Running Formula (Buch) und die Originaltabellen: nicht gelesen. Verglichen wurde nur mit der Daniels-Gilbert-Formel aus einer Sekundärquelle.
- ACSM Position Stand 2011 (Garber et al.), Tabelle: Die PMC-Tabellenseiten zeigten nur eine reCAPTCHA-Seite.
- Volltexte von Ohayon 2017 und Hirshkowitz 2015: nicht gelesen.
- Welche Apps RMSSD tatsächlich nach Health Connect schreiben: Die Suche ergab keine belastbare Liste.

**Nachrechnung R8:** eigene Simulation in Python mit den genannten Formeln und Verteilungen (200.000 Tage je Fall, Seed 42). Das Dokument nennt weder Skript noch Seed. Alle Simulationen hier zeigen die Empfindlichkeit unter frei gewählten Annahmen, nicht die Häufigkeit in der Praxis.

## Blocker

### B1. PAR-173 (mit PAR-163, PAR-165, PAR-170): Die Herabstufung hat keinen Zeitbezug, und ihre Folge wurde nie gerechnet. Typ: `Wert`

**Problem:** „Bei ‚Erhöhte Belastung‘ und ‚Erholung empfohlen‘ wird die nächste intensive Einheit automatisch locker.“ Offen bleibt, welcher Tageswert zählt. Gilt schon ein niedriger Wert drei Tage vor der Einheit, oder nur der am Tag selbst? Das Dokument wertet R8 unter „Empfindlichkeit“ aus und schreibt in `Validierungsbedarf` „die Ränder sind selten“. Die Entscheidung OQ-0058 kam erst danach und wurde nicht mit R8 verbunden.

**Beleg (eigene Simulation):** Die Tage ohne jede echte Veränderung sind reines Rauschen im Sinn von R8: `z` standardnormal, Korrelation 0,5. Für z, TSB und Schlaf gelten die Annahmen aus R8, zusätzlich AR(1) für z mit 0 bis 0,6 und für TSB mit 0,9.

| Lesart: Herabstufung, wenn der Wert unter 50 lag | Profil A (Schlaf 7,2 h, TSB% −12) | Profil B (Schlaf 6,5 h, TSB% −20) |
|---|---:|---:|
| nur am Tag der Einheit | 14 % | 32 % |
| an einem der letzten 3 Tage | 30–36 % | 59–67 % |
| an einem der letzten 7 Tage | 53–65 % | 84–92 % |

- **Kleine Anstöße reichen:** Bei 7 h und TSB% −25 kippt der Wert schon bei `z` = −0,8 auf beiden Herzfaktoren, bei 6,5 h und TSB% −25 bei `z` = −0,47.
- **Eine Nacht reicht:** Unter 5,2 h Schlaf bei sonst unauffälligen Werten fällt der Wert unter 50 (Beispiel im Dokument: 5 h ergibt 48). [N14] nennt die Wirkung von 1–3 Nächten Teilschlafentzug auf die Leistung ausdrücklich „remains unclear“ (https://pubmed.ncbi.nlm.nih.gov/33144349/).
- **Dauerhaft kurzer Schlaf:** Bei durchschnittlich 5,5 h und TSB% −5 liegen rund 42 % der Tage unter 50, bei 6 h und TSB% −20 rund 40 %. Das folgt aus dem entschiedenen Anker 7 h (OQ-0057) und wird nicht neu aufgerollt, ist aber nirgends benannt.
- **Einordnung am Tag der Einheit:** 14–32 % liegen in der Größenordnung von [N21], wo die HRV-Gruppe rund 25 % weniger harte Einheiten lief (13,2 gegen 17,7, https://pubmed.ncbi.nlm.nih.gov/26909534/). Dort gab es aber 2–3 solcher Einheiten je Woche. Im Aufbau gibt es höchstens eine (PAR-062).

**Korrektur** (OQ-0058 bleibt bestehen, die Regel wird nur präzisiert):
1. PAR-173 um den Zeitbezug ergänzen: „Maßgeblich ist nur der Wert des Tages, an dem die intensive Einheit geplant ist. Er gilt für diese Einheit und wird nicht vorgezogen oder übertragen.“
2. Festlegen, was in der Folgewoche passiert. Vorschlag: Eine herabgestufte Einheit zählt nicht als Stufe in PAR-124 und PAR-125, senkt die Stufe aber auch nicht.
3. In `Validierungsbedarf` „die Ränder sind selten“ streichen und den Anteil herabgestufter Einheiten je Nutzer als Hauptgröße aufnehmen, mit Grenzwert für eine Neubewertung.

**Folgen:** Implementierung wird eindeutig. Der Text in FR-0116 und OQ-0058 bleibt gültig.

### B2. PAR-161, PAR-162 (Wirkung über PAR-173): Tageswert von HRV und Ruhepuls steuert den Plan automatisch, obwohl die eigenen Quellen Mehrtagesmittel verlangen. Typ: `Wert`

**Problem:** PAR-161 vermerkt „Offen: Studien mitteln über mehrere Tage [N19], während FR-0113 einen Einzelwert erlaubt“, und verschiebt das in den Feldtest. Das Dokument erklärt außerdem „Alles ist entschieden“. Seit OQ-0058 entscheidet der Tageswert über eine Planänderung. Die Belege sprechen klar dagegen:

- **[N19], Abstract, im Dokument nicht genannt:** Standardisierte Änderung bei Mittelung über 1 Tag `0.20 ± 0.28`, über 3 Tage `0.49 ± 0.33`. Korrelation mit der Leistungsänderung über 1 Tag `-.02 ± .23`, über 4 Tage `-.25 ± .22`. Ein einzelner Tag zeigte in dieser Studie also keinen erkennbaren Zusammenhang. Schluss: „a minimum of 3 (randomly selected) valid data points per week“ (https://pubmed.ncbi.nlm.nih.gov/24334285/). Die Studie betrifft trainierte Triathleten. Das Dokument nutzt sie nur in PAR-148 für die Größenordnung der Messmenge.
- **[Q27]:** Ein Zusammenhang mit der Laufleistung „could only be observed using the average of at least 3–4 days of HR and HRV data“; Tag-zu-Tag-Streuung rund 10–20 % CV bei Ln rMSSD (https://www.frontiersin.org/articles/10.3389/fphys.2014.00073/full, Volltext zugänglich, abgelesen über WebFetch).
- **[N21]:** Laut Suchtreffer zu JYX-Dokumenten dieser Studie steuerte das 7-Tage-Mittel: „HRV group trained according to a 7-day rolling averaged morning RMSSD“ und „RMSSDrollavg provides a more reliable method … compared to RMSSDday“ (https://jyx.jyu.fi/handle/123456789/50625; Volltext `nicht geprüft`). PAR-163 zitiert genau diese Studie als Richtungsbeleg für den Tageswert.
- **[N22]:** Herabstufung nur bei Unterschreiten von „10-day mean-SD“ oder „decreasing trend for 2 days“, gemessen morgens und über HF-Oszillationen, nicht RMSSD (https://pubmed.ncbi.nlm.nih.gov/17849143/).
- **[L38]:** „a sustained rise in RHR over a few days“ (https://support.google.com/googlehealth/answer/14236710?hl=en). PAR-162 nennt das, rechnet aber den Tageswert. Zusätzlich ist der Ruhepuls ganzzahlig: Bei MAD 1 bpm ist `z` je bpm 0,67, also ergeben +3 bpm `S` ≈ 10.

**Korrektur, Variante A (empfohlen):** `x` wird das Mittel von `ln(RMSSD)` und Ruhepuls über die letzten 3 bis 7 Nächte, mindestens 3 Werte in 7 Tagen, dabei muss die letzte Nacht vorliegen (OQ-0006 „aktuelle HRV“ bleibt erfüllt).

**Korrektur, Variante B:** Tageswert bleibt für die Anzeige. PAR-173 greift erst, wenn der Wert an 2 Tagen in Folge unter 50 liegt (Muster aus [N22]).

| Simulation (Rauschen, unabhängige Nächte, Schlaf einzeln) | Erhöhte Belastung Profil A | Profil B |
|---|---:|---:|
| heute: Tageswert | 11 % | 30 % |
| Variante A, Mittel über 3 Nächte | 5 % | 25 % |
| Variante A, Mittel über 7 Nächte | 3 % | 23 % |
| Variante B, 2 Tage in Folge (AR 0,3, mit Korrelation 0,5) | 4 % | 13 % |

**Folgen:**
- Der Referenzwert aus Tageswerten überschätzt die Streuung eines Mittelwerts. Bei Variante A müsste die MAD aus der Reihe der Mittelwerte stammen, sonst wird `z` zu klein.
- Akute Reaktionen werden gedämpft, obwohl Nuuttila nächtliche Reaktionen nach einem harten Lauf zeigt [N23]. Warnsignale bleiben davon unberührt (FR-0203).
- Tage mit „Gut erholt“ werden noch seltener (Variante A: 0–0,3 %, siehe M11).
- Prüfplan in `Validierungsbedarf` wird zur Vergleichsgröße.

### B3. PAR-190 mit PAR-101: Die Bandbreite weitet ältere Referenzen auch zur schnelleren Seite. Typ: `Wert`

**Problem:** „Die Bandbreite aus PAR-101 weitet beide Enden der Spanne.“ Je älter die Referenz, desto schneller wird also das erlaubte Ende. Die Rechnung selbst stimmt (4:51–5:00 mit ±3 % ergibt 4:42–5:09). Die Folge widerspricht aber der eigenen Begründung in PAR-101: [L26] und [L27] stützen nur die Richtung, dass eine alte Referenz die aktuelle Form überschätzt.

**Beleg (Rechnung, 5 km in 25:00, also Tempo 3 km 4:51, 5 km 5:00, 10 km 5:13, Halbmarathon 5:27):**

| Bandbreite | Intervalle | Tempodauerlauf | Locker, falls geweitet |
|---|---|---|---|
| ±3 % | 4:42–5:09 | 5:04–5:37 | 5:49 |
| ±6 % (3–13 Wochen) | 4:34–5:18 | **4:54**–5:47, schneller als das 5-km-Wettkampftempo | 5:38 |
| ±10 % (13–26 Wochen) | **4:22**–5:30 | **4:42**–6:00 | **5:24**, schneller als das Halbmarathon-Tempo |

Das erlaubt einen Tempodauerlauf im Bereich einer 1,5-km-Leistung und hebt PAR-102 auf, wonach locker „mindestens 10 % langsamer“ sein soll. Ob die Grenze für locker mitgeweitet wird, sagt PAR-190 nicht. RPE wird zwar angezeigt (PAR-105), die Pace-Spanne spricht aber dagegen.

**Korrektur:** PAR-190: „Die Bandbreite weitet nur das langsame Ende. Das schnelle Ende bleibt der Wert aus PAR-102. Die Grenze für lockere Läufe wird nicht geweitet.“ Beispiel: Intervalle 4:51–5:09 (±3 %), 4:51–5:18 (±6 %), 4:51–5:30 (±10 %).

**Folgen:** Spannen werden einseitig; PAR-082 („stets ein Bereich“) bleibt erfüllt. Für die seltene Verbesserung seit der Referenz wird die Vorgabe konservativ, was dem Ziel von FR-0149 entspricht. Eine neue Referenz behebt das. PAR-103 und die dortige Bandbreite aus PAR-082 sind eine Schätzunsicherheit und nicht betroffen; das sollte der Text trennen.

## Muss

### M1. PAR-163: [N21] und [N22] werden falsch wiedergegeben; die Begründung der Asymmetrie trägt nicht. Typ: `Beleg/Text`

**Problem:**
- Text: „bei niedriger HRV [wurde] locker statt hart trainiert [N21, N22]“. [N21] plant hart nur, wenn die HRV innerhalb des SWC liegt: „The MOD/HIT session was programmed if HRV was within an individually determined smallest worthwhile change. Otherwise, low-intensity training was performed.“ (https://pubmed.ncbi.nlm.nih.gov/26909534/). Damit führt auch eine Abweichung nach oben zu locker. PAR-163 wertet eine hohe HRV dagegen bis `S` = 90 als günstig. Beleg für die exakten Grenzen: `nicht geprüft`.
- Beide Studien messen morgens, [N22] über HF statt RMSSD. PAR-160 nutzt nur nächtliche Werte. Das steht im Dokument nirgends, und [N23] zeigt gerade, dass sich beide nicht gleich verhalten.
- Die „Asymmetrie und Kappung“ sollen aus [N18] „folgen“. [N18] sagt für Eliteathleten, Anstieg und Abfall könnten mit negativer Anpassung einhergehen (https://pubmed.ncbi.nlm.nih.gov/23852425/). Das begründet weder 25 gegen 20 noch die Kappung bei 90, sondern spräche höchstens gegen jede Aufwertung. Nuuttila fand bei Freizeitläufern nach Überlastung einen Anstieg von LnRMSSD und einen Zusammenhang des nächtlichen Werts mit der Leistungsänderung ([N23], https://pubmed.ncbi.nlm.nih.gov/39503915/). Auch das stützt keine Regel „höher ist besser“.

**Korrektur:** Text ändern in: „In [N21] (morgens, siehe B2 zum Mittel) führte eine Abweichung außerhalb des SWC zu lockerem Training, in [N22] (morgens, HF) ein Abfall. Die Steigungen und die Kappung sind eigene Wahl. Eine Abweichung nach oben wird nur mangels Gegenbeleg leicht günstig gewertet; [N18] und [N21] sprechen dagegen, das als Erholung zu deuten.“

### M2. PAR-102 mit PAR-125 und PAR-128: Die Pace hängt nicht von Blocklänge und Gesamtdauer ab. Typ: `Wert`

**Problem:** Intervalle laufen stets „zwischen Tempo über 3 km und 5 km“, Tempodauerläufe stets „zwischen 10 km und Halbmarathon“. Das gilt auch für 4 × 8 min und 1 × 40 min. Damit passt die Vorgabe nicht zu RPE 6–7 aus PAR-113.

**Beleg:**
- [N4]: Die Intensität fällt mit der Blocklänge: „88 ± 2, 90 ± 2, and 94 ± 2% of HR(peak) … in 4 × 16, 4 × 8, and 4 × 4 min groups“ (https://pubmed.ncbi.nlm.nih.gov/21812820/). Das Dokument zitiert diese Zahlen in PAR-112 und PAR-113, zieht aber keinen Schluss für die Pace.
- [N5]: Intervallblöcke 3–5 min, Tempolauf rund 15–20 min (https://cdbaca.github.io/ssg/reading-daniels-running-formula-chapter-4.html).

| 5 km | 10-km-Zeit (Riegel) | 32 min harte Zeit gegen 5-km-Zeit | 1 × 40 min gegen 10-km-Zeit | Tempo PAR-102 | Riegel-Tempo für 60 min | Daniels T (88 % VDOT, Formel) |
|---|---:|---:|---:|---|---:|---:|
| 15:00 | 31 min | 2,1-fach | 1,3-fach | 3:08–3:16 | 3:15 | 3:15 |
| 20:00 | 42 min | 1,6-fach | 0,95-fach | 4:10–4:22 | 4:15 | 4:16 |
| 25:00 | 52 min | 1,3-fach | 0,77-fach | 5:13–5:27 | 5:15 | 5:16 |
| 35:00 | 73 min | 0,9-fach | 0,55-fach | 7:18–7:38 | 7:13 | 7:15 |

Formel: Daniels und Gilbert, wiedergegeben unter https://getfitcraft.com/tools/vdot-calculator (Sekundärquelle). Für schnellere Läufer verlangt das schnelle Ende also 40 min im Tempo ihres ganzen 10-km-Wettkampfs oder darüber hinaus.

**Korrektur:**
- PAR-102, Tempodauerlauf: schnelles Ende ist das langsamere aus 10-km-Tempo und Riegel-Tempo für 60 min. Beispiel 25:00: 5:15–5:27.
- PAR-102, Intervalle: Blöcke bis 5 min wie bisher. Blöcke ab 6 min zwischen 5-km- und 10-km-Tempo. Beispiel 25:00: 5:00–5:13.

**Folgen:** Beispiel in PAR-102 und PAR-190 ändert sich. Für langsamere Läufer ändert sich wenig. Keine neue Datenquelle nötig. Die 60 min sind eigene Wahl und trafen im Vergleich die Daniels-Formel bis auf wenige Sekunden.

### M3. PAR-118: Die 8 und 10 % aus [N5] sind dort Obergrenzen je Einheit, hier ein Start. Typ: `Beleg/Text`

**Problem:** „Die 8 und 10 % stehen in einer Lesenotiz zu Daniels … Sie gelten hier nur als vorsichtiger Start“. In [N5] sind es Höchstwerte je Einheit, die Intervalle zusätzlich mit „oder 10 km“ begrenzt (https://cdbaca.github.io/ssg/reading-daniels-running-formula-chapter-4.html). Die Regel lässt eine Einheit dann bis zum Wochenanteil von 15–20 % wachsen, also das 2- bis 2,5-Fache der einzigen genannten Grenze. 4 × 8 min bei 160 min Wochenumfang sind 20 %; nach [N5] wären 400 min nötig. Das Dokument verschweigt, dass die Quelle es als Grenze meint. Die Abweichung kann gewollt sein, ist aber so nicht erkennbar. Auch [L9] ist nur Wochen-, nicht zwingend Einheitsmenge (3 von 18,5 km, Wert stimmt).

**Korrektur:** Text: „[N5] nennt 8 und 10 % als Obergrenze je Einheit, bezogen auf Distanz. Diese Regel übernimmt sie nur als Start und überschreitet sie danach bewusst, weil [N4] und [L9] höhere Anteile zeigen. Ein Beleg für die Verträglichkeit bei Freizeitläufern fehlt.“ Art zu `Heuristik` (siehe M7).

### M4. PAR-128: Start ohne Rückfallregel, Obergrenze nicht wie begründet. Typ: `Wert`

**Problem:**
- Start 1 × 20 min verlangt nach PAR-118 (10 %) mindestens 200 min Wochenumfang, 3 × 8 min sogar 240 min. „Erfahren“ setzt nur 3 Läufe in 20 von 26 Wochen voraus (PAR-051), also oft weniger. PAR-124 und PAR-125 haben eine Rückfallregel, PAR-128 nicht.
- „Sie ergibt sich aus 20 % bei 200 min je Woche“ gilt für 1 × 40. 3 × 15 min sind 45 min und brauchen 225 min.

**Korrektur:** „Start 1 × 20 min oder 3 × 8 min, oder die letzte Stufe aus PAR-127, die nach PAR-118 passt.“ Begründung: „1 × 40 min entspricht 20 % bei 200 min, 3 × 15 min 20 % bei 225 min.“

**Folgen:** Keine Lücke mehr im Plangenerator, geringere Startlast für Erfahrene mit kleinem Umfang.

### M5. PAR-160: Die Regel mischt, was sie zu mischen verbietet. Typ: `Wert`

**Problem:** Begründung: „deshalb nur nächtlich und nicht gemischt“ [N23]. Der Startwert schließt aber „die 60 min danach“ ein, also die Wachphase, und nimmt den Median über alle Einträge. Nuuttila zeigt, dass schon die Nachtsegmente verschieden reagieren: „SleepEnd“ war „the only sleep segment that did not change significantly after the test run“, und Reaktionen von Nacht und Morgen waren „not similarly aligned“ (Volltext https://pmc.ncbi.nlm.nih.gov/articles/PMC11541970/, frei zugänglich; im Dokument als nicht lesbar geführt). Der Median ist außerdem nirgends begründet.

**Korrektur:** „Einträge innerhalb der Hauptschlafphase. Nur wenn es dort keinen Eintrag dieser Quelle gibt, zählt ein Eintrag aus den 60 min danach, und dieser Tag wird markiert. Median über die Einträge: eigene Wahl.“ Art zu `Heuristik`.

**Folgen:** Quellen mit Stempel am Sitzungsende behalten einen Wert, die Vermischung bei vielen Einträgen entfällt. Die Prüfung je Quelle bleibt nötig.

### M6. PAR-165: Evidenzgrad `mittel` ist zu hoch. Typ: `Beleg/Text`

**Problem:** Einzige Zeile mit `mittel`, und sie ist `Heuristik`. Der Konsens gilt für Dauer „on a regular basis to promote optimal health“ und Erwachsene von 18 bis 60 Jahren ([N12], https://pmc.ncbi.nlm.nih.gov/articles/PMC4434546/). Bewertet wird aber eine einzelne Nacht für den nächsten Lauf. Die Steigung ist eigene Wahl, [N14] nennt die Wirkung unklar und betrifft Eliteathleten (das steht im Dokument nicht). Die Begründung sagt das selbst, die Einstufung nicht. Die Definition von `mittel` nennt nur „nicht an Freizeitläufern geprüft“, nicht „anderer Zweck“. Die Zeile täuscht damit stärkere Stützung vor als die übrigen.

**Korrektur:** `Heuristik, Evidenz niedrig`. Text: „Nur der Anker hat formalen Konsens, und zwar für langfristige Gesundheit.“ In der Lesehilfe ergänzen: Der Grad gilt für den Wert in diesem Zweck, nicht für die Quelle als solche. Damit kommt `mittel` im Dokument nicht mehr vor, was der Evidenzlage entspricht.

### M7. Mehrere Zeilen: `abgeleitet`, obwohl der Wert eigene Wahl ist. Typ: `Beleg/Text`

**Problem:** Die Lesehilfe definiert `abgeleitet` als „folgt aus einer Quellenangabe, einer Entscheidung oder einem benannten Rechenschritt“ und `Heuristik` als „keine Quelle nennt diesen Wert“. Bei diesen Zeilen sagt die Begründung selbst, dass der wesentliche Wert gewählt ist:

| Zeile | Stelle in der Begründung | Soll |
|---|---|---|
| PAR-168 | Formel und Steigung ohne Quelle („lehnt sich an“, Abschnitt 5: „Keine Quelle nennt diese Formeln“) | Heuristik |
| PAR-109 | „passt … grob“, „keine prüft Reservezonen dafür“ | Heuristik |
| PAR-112 | „die 9 ist eigene Wahl“, Übersetzung „gilt nur für das Beispiel“ | Heuristik |
| PAR-113 | Quellen streuen, „RPE ist eigene Wahl“ | Heuristik |
| PAR-118 | „diese ist eigene Wahl“, 8 und 10 % umgedeutet (M3) | Heuristik |
| PAR-126 | „Der Rest ist eigene Wahl“ | Heuristik |
| PAR-140 | „Die Auslöser sind eigene Wahl“ | Heuristik |
| PAR-144, PAR-143 | 3 und 26 Wochen eigene Wahl | Heuristik mit abgeleitetem Teil |
| PAR-160 | 60 min und Median eigene Wahl | Heuristik |
| PAR-107 | „4 min und 30 s sind eigene Wahl“ | Heuristik mit abgeleitetem Teil |

**Korrektur:** Art ändern und eine dritte Lesart einführen, falls gewünscht: „Heuristik, Anker abgeleitet“. Das rund ein Viertel der `abgeleitet`-Zeilen betreffende Muster sollte vor der Version 2 systematisch durchgegangen werden. Die reinen Verweiszeilen (etwa PAR-131, PAR-147) sind korrekt eingestuft.

### M8. PAR-142: Wesentliche Prüfpunkte für OQ-0048 fehlen. Typ: `Beleg/Text`

**Stimmt:** „© Crown copyright“ auf der Plan-Seite. OGL, auch kommerziell, „adapting it“. Übersetzung als Abwandlung. „You must not attribute the content to the NHS website or cite the NHS specifically as the source“. Keine Andeutung von Billigung. Das Dokument bewertet das zu Recht nicht rechtlich. (https://www.nhs.uk/our-policies/terms-and-conditions/)

**Es fehlt:**
- **Herkunft:** „Couch to 5K“ stammt von Josh Clark, 1996 (https://en.wikipedia.org/wiki/Couch_to_5K). Die Wochen 3 bis 9 auf c25k.com haben dieselben Zahlen wie PAR-133 bis PAR-139 (https://c25k.com/c25k_plan/, Seite: „© Copyright 2023 – All Rights Reserved“). Der Name des Programms und die Abfolge könnten also nicht vom NHS stammen.
- **Ausnahmen in 3.5:** ausdrücklich „trademarks, trade names“ und „information owned by third parties which we are not authorised to licence on to you“. Das betrifft genau die Frage aus PAR-142, ob die Ausnahmen die Abfolge oder den Namen treffen. Eine Marke selbst habe ich nicht festgestellt; die Suche ergab dazu nichts.
- **Pflichtangabe bei Abwandlung:** „Contains public sector information licensed under the Open Government Licence v3.0.“
- **Klinische Freigabe und Haftung:** „Any adaptation … may invalidate its formal clinical approval; therefore if you use any such NHS Website Content you will bear any risk“. Das ist für PAR-141 (Abwandlung bei 1 und 2 Tagen) und den medizinischen Teil von OQ-0048 wichtig.
- **Widerspruch im eigenen Text:** Das Dokument und PAR-065 sprechen von „NHS-Struktur“. Bei Abwandlung wäre das in App-Texten verboten; Abschnitt 3 sagt das nur als offene Frage.

**Korrektur:** diese vier Punkte als Prüfpunkte aufnehmen und PAR-132 ff. ergänzen: „Programm und Zeiten gleichen dem Plan von Josh Clark (1996); ob und wie der NHS ihn lizenziert hat, ist nicht geklärt.“

### M9. PAR-132 bis PAR-139: „keine prüfende Studie gefunden“ übersieht eine leicht auffindbare Beobachtungsstudie. Typ: `Beleg/Text`

**Stimmt:** Alle Zeiten PAR-132 bis PAR-139 und PAR-065 stimmen mit Webseite und NHS-PDF überein (Abschnitt `Geprüft ohne Befund`).

**Problem:** Relph et al. 2023, „Couch-to-5k or Couch to Ouch to Couch!?“, https://pmc.ncbi.nlm.nih.gov/articles/PMC10487403/: 110 Erwachsene, Beobachtung, mit NHS-App und einem begleiteten Lauf je Woche. Nur 27,3 % schlossen laut Abstract ab (der Ergebnisteil nennt 64,5 % Abbrecher; die Zahlen passen nicht zusammen, vor Übernahme prüfen). 21 Verletzungen bei 20 Läufern (19 %). 11 von 15 befragten Abbrechern nannten eine Verletzung, und die Belastung sei für Anfänger zu schnell gestiegen. Die Autoren schreiben, das Programm „lacks an evidence base“. Die Studie ist klein, ungelost und abgewandelt, also kein Gegenbeweis. Sie ist aber der einzige direkte Datenpunkt und spricht gegen den Eindruck, das Programm sei einfach nur ungeprüft.

**Korrektur:** Begründung: „Behördenprogramm. Eine kleine Beobachtungsstudie zeigte hohe Abbruchraten und 19 % Verletzungen [neue Quelle]; ein Beleg für das Design fehlt.“ Quelle aufnehmen und PAR-140 sowie `Validierungsbedarf` darauf beziehen.

### M10. Abschnitt 5, PAR-163 bis PAR-170 und `Validierungsbedarf`: R8 ist nur näherungsweise wiederholbar und deckt den häufigen Fall nicht ab. Typ: `Beleg/Text`

**Nachrechnung:**

| Fall (alle fünf Faktoren) | Gut erholt | Normal | Erhöht | Erholung |
|---|---:|---:|---:|---:|
| Profil A, Korrelation 0 | 2,4 | 86,8 | 10,8 | 0,0 |
| Profil A, Korrelation 0,5 | 4,8 | 81,0 | 14,2 | 0,0 |
| Profil B, Korrelation 0 | 0,7 | 69,0 | 30,1 | 0,2 |
| Profil B, Korrelation 0,5 | 1,5 | 66,6 | 31,4 | 0,5 |
| **Dokument** | 0,5–5 | 64–86 | 12–34 | 0–1 |

Die Größenordnung ist bestätigt, ebenso „höchstens 1 %“. „64 %“ und „34 %“ erreiche ich nicht (66,6 und 31,4). Schlaf nur als Dauer gerechnet, weil R8 keine Effizienz nennt. Ohne Skript und Seed bleibt der Unterschied offen; er ändert den Schluss nicht.

**Problem:**
1. **Fehlende Faktoren:** R8 gilt nur mit allen Faktoren. In den ersten 126 Tagen fehlt die Belastung (PAR-168, PAR-073), das Befinden ist freiwillig. Korrelation 0,5:

| Vorhandene Faktoren | Gut erholt | Erhöht | Erholung |
|---|---:|---:|---:|
| HRV, Ruhepuls, Schlaf | 8–15 % | 16–29 % | bis 1,5 % |
| Nur HRV und Schlaf | 9–18 % | 13–30 % | bis 2,5 % |
| Mit allen Faktoren | 1,5–5 % | 14–31 % | bis 0,5 % |

   Der Wechsel an Tag 127 senkt „Gut erholt“ also stark, ohne dass sich etwas geändert hat. PAR-168 sagt nur „kann … steigen“.
2. **Verteilung von `z`:** R8 nimmt `z` als standardnormal. Mit geschätztem Median und MAD aus der Referenz ist es breiter: Bei 14 Werten SD 1,33 und P(z < −2) 5,9 % statt 2,3 %, bei 28 Werten SD 1,14 und 3,9 %. Die Bänder verschieben sich nur um 1–3 Punkte. Die Annahme sollte benannt sein, denn gerade die vorläufige Stufe (PAR-148) hat die breiteste Verteilung.
3. **Wortlaut:** „die Ränder sind selten“ passt zu „Erholung empfohlen“ und „Gut erholt“, nicht zu „Erhöhte Belastung“ mit 11–31 %.

**Korrektur:** R8 um die Fälle mit fehlenden Faktoren und die Annahme zu `z` ergänzen, Skript und Seed mitliefern, Wortlaut ändern. „0–1 %“ darf stehen bleiben, aber nur für alle Faktoren.

### M11. PAR-168, PAR-170: „Gut erholt“ ist kaum erreichbar, und ein Konflikt bleibt trotz „Alles ist entschieden“ offen. Typ: `Beleg/Text`

**Rechnung:** Der Höchstwert 82,5 stimmt, gilt aber nur mit allen Faktoren (ohne Belastung 86,5, nur HRV und Schlaf 84,5). Für 75 (gerundet ab 74,5) nötig, TSB% ≥ −10:

| Schlaf | Befinden 3 | Befinden 4 | Befinden 5 |
|---|---:|---:|---:|
| 8 h (`S` 80) | `z` ≥ +0,94 auf beiden | +0,78 | +0,61 |
| 7 h (`S` 70) | +1,28 | +1,11 | +0,94 |
| 6,5 h (`S` 57,5) | nicht erreichbar | nicht erreichbar | +1,36 |
| unter rund 6,33 h | nicht erreichbar, auch mit allen Höchstwerten | | |

Das Beispiel „Überall günstig“ liegt mit 76 knapp über der Grenze. Bei gewohnten 7 h und TSB% −5 sind rund 6 % der Tage „Gut erholt“, bei 8 h rund 12 %, bei 6 h unter 1 %.

**Urteil:** Das Band ist erreichbar, aber selten und bei kurzem Schlaf gar nicht. Dem Plan schadet das nicht, weil ein hoher Wert nichts erhöht (PAR-173). Der obere Teil 83–100 bleibt leer, und das Band umfasst effektiv nur 7,5 Punkte. Die Bänder sind entschieden (OQ-0029); ich empfehle keine Änderung der Kappungen, solange keine Felddaten vorliegen.

**Korrektur:**
- PAR-170: wirksamen Bereich und die Tabelle oben aufnehmen, Text: „Die Einordnung ‚Gut erholt‘ ist selten und bei kurzem Schlaf unerreichbar, das ist kein Fehler des Nutzers.“
- PAR-168 enthält einen **Konflikt** ohne **Entschieden**: „Gut erholt“ trotz PAR-072. Der Abschnitt `Entscheidungsbedarf` sagt „Alles ist entschieden“. Entweder als Entscheidung protokollieren oder dort aufführen, hier auch den offenen Punkt aus PAR-161.

### M12. PAR-109, PAR-111, PAR-107: Langsame Läufer können „locker“ im Lauf womöglich nicht einhalten. Typ: `Wert`

**Problem:** Locker heißt `r` < 0,70 und unter 80 % HFmax. Nach der App-Formel entspricht das dieser Geschwindigkeit (Formel unter 134 m/min nicht validiert, PAR-030; daher nur Größenordnung):

| VO₂max | `r` bei 134 m/min (7:28/km) | Tempo für `r` = 0,70 |
|---:|---:|---:|
| 30 | 1,01 | 10:47 min/km |
| 35 | 0,85 | 9:04 min/km |
| 40 | 0,73 | 7:50 min/km |
| 45 | 0,65 | 6:53 min/km |

Das Dokument behandelt den Fall nur für die Pace (PAR-103: keine Pace unter 134 m/min), nicht für die Pulsgrenze. Folge bei Aufbau-Nutzern mit Puls: Dauerhinweise nach PAR-107 ab Minute 3 oder ein Tempo auf Geh-Niveau. Läufe mit mindestens 10 min über 80 % HFmax zählen zudem als intensiv (PAR-058), auch wenn sie locker geplant waren. Die Regel überlastet nicht, kann aber zum Abbruch führen. [Relph] (M9) nennt zu schnell steigende Belastung und negative Gefühle als Abbruchgründe.

**Korrektur:** PAR-109 ergänzen: „Gehpausen sind in lockeren Einheiten immer erlaubt.“ PAR-107 ergänzen: „Wird die obere Pulsgrenze in den letzten 3 lockeren Einheiten überwiegend überschritten, keine Ansagen mehr, stattdessen ein Hinweis auf Gehpausen; Vorrang für RPE.“ Die Zahl 3 ist eigene Wahl.

**Folgen:** Keine Lockerung der Grenze. Die Zählung nach PAR-058 bleibt; ihr Anteil gehört in die Auswertung.

## Soll

### S1. PAR-105, PAR-112, PAR-113: Eine direkte CR-10-Studie an Läufern wurde übersehen. Typ: `Beleg/Text`

„Eine geprüfte Umrechnung auf die Skala 0–10 wurde nicht gefunden“ und die Suche „Validierung von RPE 0–10 am Lauf“ blieb erfolglos. Dantas et al. 2015, 95 moderat trainierte Läufer, Laufband, Borg CR-10: 2 mmol/L entspricht RPE 4,3 (95 % CI 3,9–4,7), 4 mmol/L entspricht 6,5 (6,0–7,1), https://pubmed.ncbi.nlm.nih.gov/25187249/. Das stützt die freigegebenen Eckwerte: locker bis RPE 4, Tempodauerlauf 6–7. Korrektur: als Quelle aufnehmen, Evidenz der Zeilen bleibt `niedrig`. Nicht verwechseln: Das Dokument nennt die Skala nur „0–10“; FR-0038 definiert keine Anker. Für CR-10 sollte die App dieselben Anker zeigen. Zu ACSM siehe `nicht geprüft`: Laut Suchtreffer ordnet eine Sekundärtabelle 77–95 % HFmax etwa 64–90 % HRR zu. Das wäre für Zone 2 oben schon „vigorous“ und sollte nach Prüfung der Tabelle erwähnt werden.

### S2. PAR-113 und R5: Rundungsfehler und zu enge Übersetzung. Typ: `Beleg/Text`

88 % HFmax bei HFmax 190 und HFRuhe 60 ergibt `r` = 0,8246, also **0,82**, nicht 0,83. Alle anderen Werte aus R5 und R4 stimmen. Zudem zeigt R5 nur einen Ruhepuls. Bei HFRuhe 45 und 75 reicht 85 % HFmax von 0,80 bis 0,75, 90 % von 0,87 bis 0,84, 70 % von 0,61 bis 0,50. Korrektur: Wert berichtigen und R5 um die Spanne erweitern; das macht „gilt nur für das Beispiel“ prüfbar.

### S3. PAR-102, PAR-109: Bessere Gegenprüfung als die Lesenotiz [N5]. Typ: `Beleg/Text`

Die Daniels-Gilbert-Formel erlaubt die Prüfung ohne das Buch. Sie bestätigt die Zuordnung weitgehend (Tabelle in M2). Lockere Grenze gegen Formel bei 74 % VDOT: 3:36 gegen 3:45 (15:00), 6:00 gegen 6:03 (25:00), 9:36 gegen 9:22 (40:00). Intervalle liegen bei 91–101 % VDOT, also für langsame Läufer etwas unter [N5] (95–100 %). Das ist ungefährlich. Außerdem sind die %VO₂max in [L9] aus VDOT-Tabellen geschätzt, nicht gemessen; das fehlt in PAR-109. Korrektur: Vergleich als `Sekundärquelle, Formel` aufnehmen, Originaltabellen bleiben `nicht geprüft`.

### S4. PAR-112: Obergrenze RPE 9 für „Aufbau“. Typ: `Wert`

Aufbau heißt nur 2 Läufe in 8 von 12 Wochen (PAR-051). Die Studien stützen RPE 9 nicht für diese Gruppe: [N3] nennt „moderately trained“, doch die Teilnehmer hatten VO₂max 55–60 ml/kg/min (https://pubmed.ncbi.nlm.nih.gov/17414804/), [N4] Radfahrer mit VO₂peak 52 bei „maximal tolerable“ Intensität. Vorschlag: Aufbau RPE 7–8, Erfahren RPE 7–9. Folge: etwas geringere Spitze, keine Wirkung auf die Struktur. Die Angabe „moderat trainiert“ in `Evidenz insgesamt` um die VO₂max ergänzen.

### S5. Abschnitt 5, PAR-172: „Wert 60 heißt in jeder Teilskala unauffällig“ stimmt für Schlaf nicht. Typ: `Wert`

Bei 7 h ist `S` = 70, `S` = 60 entspricht 6,6 h, bei der Effizienz 83 %. Die Rangfolge in PAR-172 nutzt `Gewicht · (S − 60)`. Schlaf erscheint damit bei 7 h immer mit +300 als günstiger Faktor. Vorschlag: In PAR-172 für Schlaf den Bezug 70 nehmen, Abschnittstext korrigieren: „60 für HRV, Ruhepuls, Belastung und Befinden, 70 für Schlaf“. Die Skalen bleiben, und 63 bleibt der Neutralwert.

### S6. PAR-160: Messfenster sind für Fitbit dokumentiert; Verfügbarkeit bleibt offen. Typ: `Beleg/Text`

Fitbit dokumentiert „main sleep“, `deepRmssd` und „stops collecting HRV data after it determines the user is awake“ und nennt das Ende der alten API am 30.10.2026 (https://dev.fitbit.com/build/reference/web-api/heartrate-variability/get-hrv-summary-by-date/). Das ersetzt nicht die Prüfung der Google Health API, gibt ihr aber einen Ausgangspunkt. Ob RMSSD von gängigen Geräten überhaupt nach Health Connect kommt, ließ sich nicht belegen. Das ist eine Voraussetzung für die Zahl aus OQ-0006 und gehört in `Validierungsbedarf`: je Quelle Vorhandensein, Anzahl der Einträge je Nacht, Zeitstempel. Die Android-Angaben in PAR-160 und PAR-162 selbst stimmen.

### S7. `Nicht abrufbar`: Einige Texte sind zugänglich. Typ: `Beleg/Text`

[Q27] heißt „nur Abstract zugänglich“, der Volltext liegt bei Frontiers. [N23] hat einen PMC-Volltext (PMC11541970), und der PubMed-Abstract ist nicht gekürzt. Für [N21] gibt es ein Manuskript auf JYX (bei mir nicht ladbar). Auch [N10], [N17], [N24], [N25] und [L28] haben PMC-Kennungen. Deshalb sind Schlüsse zum Mittelwert ohne nötige Not unterblieben. Korrektur: Liste bereinigen und mindestens [Q27], [N23], [N21] lesen.

### S8. PAR-173: Begründung und Benennung. Typ: `Beleg/Text`

„Folgt aus FR-0163, FR-0165, OQ-0026 und OQ-0055“ gilt nur für die Richtung nach oben und die Warnsignale. FR-0165 betrifft Erhöhungen; die Herabstufung folgt aus OQ-0058. „Erholung empfohlen“ ändert im Plan nichts gegenüber „Erhöhte Belastung“, ein lockerer Lauf bleibt stehen. Das Band „Erhöhte Belastung“ erscheint auch bei reinem Schlafmangel und niedriger Trainingsbelastung (Beispiel 5 h). Die Bänder sind entschieden, FR-0117 erklärt die Ursache. Korrektur: Quellenverweis berichtigen; PAR-172 sollte die Formulierung für diesen Fall vorgeben, z. B. „wegen kurzer Schlafdauer“.

### S9. PAR-115, PAR-140, R7: Stopp-Hinweis fehlt, R7 verdeckt den größten Sprung. Typ: `Wert`

- NHS schreibt „stop if something doesn’t feel right“ und „speak to a GP first if you’re worried about your health“. Beides fehlt im Einstieg. FR-0203 greift erst nach einer Meldung. Vorschlag: neutraler Satz vor dem Geh-Lauf-Plan, ohne Diagnose und vorbehaltlich OQ-0048.
- R7 stimmt (keine Einheit über 110 %, größter Schritt 108,6 %), rechnet aber mit Gehzeit. Am längsten Laufstück gemessen springt Woche 5 von 8 auf 20 min (×2,5). Vorschlag: R7 um diese Zeile ergänzen und in PAR-140 vor Woche 5, Lauf 3 die Wiederholung anbieten, wenn Lauf 2 RPE ≥ 6 hatte. Folge: mehr Wiederholungen, kein neuer Grenzwert für den Plan. Das bleibt eine Abwandlung (M8).

### S10. PAR-103, R6: Bereich unvollständig, Bezug fehlt. Typ: `Beleg/Text`

R6 stimmt. Es fehlt aber: Lockere Pace erst ab VO₂max 44,7, Tempodauerlauf-Pace ab 37,0. Zwischen beiden gibt es also Tempo-, aber keine lockere Pace. Außerdem gilt die Rechnung nur für den eigenen Schätzer aus FR-0071. Mit Daniels ist sie nicht vergleichbar (bei VO₂max 45 etwa 6:01 gegen T rund 4:38), weil die ACSM-Formel höhere Kosten ansetzt. Korrektur: beides in PAR-103 nennen.

### S11. PAR-163, PAR-166, PAR-173: Auslassungen bei der Wiedergabe. Typ: `Beleg/Text`

- [N20]: Das Dokument nennt nur die nicht signifikante Leistung. Das Abstract berichtet auch einen signifikanten Effekt auf submaximale Parameter (g = 0,296) und „fewer non-responders“ (https://pubmed.ncbi.nlm.nih.gov/34489178/). Beides ergänzen, sonst wirkt der Befund einseitig.
- [N17]: Macro-F1 0,26–0,69 gilt für alle 11 Tracker einschließlich Matten und Handy-Apps, nicht für Wearables. Das Dokument lässt es offen; Wearables waren laut Abstract im Tiefschlaf teils überlegen.
- [N14]: Eliteathleten nennen.

## Geprüft ohne Befund

**Zitate, inhaltlich korrekt:**
- NHS: alle Wochen 1 bis 9 einschließlich Gesamtzeiten, identisch auf Webseite und PDF. Dazu 5 min Gehen, Dehnen, „focus on time, not speed“, Wiederholbarkeit, Ruhetag.
- Terms: alle Aussagen in PAR-142, soweit sie gemacht werden.
- [L8], [L9], [L10], [L22], [L23], [L26], [L27], [L28], [L30], [L38], [L43], [L48], [N2], [N3], [N4] (Zahlen), [N5], [N6], [N7], [N8], [N9], [N10], [N11], [N12], [N13], [N15], [N16], [N17] (Zahlen), [N18] (Aussage), [N19] (Aussage), [N20] (Zahlen), [N22] (Zahlen), [N24], [N25], [N26], [N27], [Q16], [Q17], [L25].
- Friel: „no hard research-based rule“ steht im Radabschnitt, der Laufabschnitt sagt „the same framework applies“. Die Wiedergabe ist vertretbar.
- Norm [N16]: Effizienz „>85%“, Tabelle ausdrücklich „not intended to be a recommendation“, bezogen auf „time in bed“.

**Rechnungen, korrekt:**
- R4 einschließlich HFRuhe > HFmax / 3 und „ab 64“; R5 außer 88 % (S2); R6; R7.
- PAR-102 (Riegel, Beispiel 25:00); PAR-103; PAR-107 (3 τ = 173 s); PAR-118 (16 %); PAR-124, PAR-125 (Stufen halten PAR-054; 32 / 0,2 = 160); PAR-141.
- PAR-144 (Verhältnisse); PAR-148, PAR-149; PAR-161 (0,02 ≈ 1 ms bei 50 ms); PAR-163; PAR-165; PAR-166; PAR-167; PAR-168; PAR-169.
- PAR-170 mit 82,5 und alle 8 Rechenbeispiele. „Nur HRV fällt“ liegt bei 50,5 und ist nur bei Rundung auf 51 „normal“.
- PAR-190 (Arithmetik, Befund siehe B3).

**Sicherheit und Aussagegrenzen:**
- Die Texte PAR-176 bis PAR-183 sind mit FR-0107 vereinbar: keine festgestellte Erholung, kein Verletzungsrisiko, keine Aussage zur Fitness. Mit FR-0118 ebenfalls: keine Diagnose. PAR-174 und PAR-184 setzen das sauber um. Kein Hinweis fordert mehr Belastung.
- Einsteiger bleiben ohne intensive Einheit (PAR-123) und ohne 5-km-Test (PAR-117); PAR-173 erhöht nie etwas.

**Ehrlichkeit des Dokuments:** Der Hinweis „nicht validiert“, die Kennzeichnung der Sekundärquelle [N5] und die offenen Konflikte sind gut sichtbar. Die Evidenzgrade `keine` und `niedrig` sind sachgerecht, mit den Ausnahmen M6 und M7.
