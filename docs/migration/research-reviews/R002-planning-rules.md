# R002 Research-Review: Planungsregeln und Startwerte

**Urteil: NACHBESSERN**

Geprüftes Dokument: `docs/planning-rules.md`, Version 1, Stand 2026-11-03. Prüfdatum: 2026-11-04. Die Produktentscheidungen in `docs/migration/open-questions.md` und `docs/product.md` wurden nicht neu aufgerollt.

**Kurzfassung:** Die Zitate sind überwiegend korrekt, keines ist erfunden. Der Befund zu OQ-0047 trägt. Die Fehler liegen im Zusammenwirken der Regeln und in einzelnen Schlüssen:
- Die Definition der Wochengrenze widerlegt die eigene Begründung.
- Ein Einsteiger kann nach rund 9 Wochen intensive Einheiten erhalten. Die Vorlage dafür stammt aus einer Studie, die Einsteiger ausschloss.
- R3 ist für einwöchige Sprünge falsch.
- Bei Google fehlen die offiziell genannten Kosten der Sicherheitsprüfung.

## Geprüfter Umfang

| Bereich | Umfang |
|---|---|
| PAR-Zeilen | 51 von 51 gelesen. Alle 23 Zeilen mit Art `belegt` (4) oder `abgeleitet` (19) gegen die Quelle geprüft, bei den 28 Heuristiken die zitierten Zahlen |
| Teil D | Alle 7 Anbieterzeilen und der Befund für ADR-0001 |
| Quellen | 69 von 70 Kürzeln mindestens teilweise abgerufen |
| Prüftiefe Studien | Originaltext der Abstracts über die NCBI-E-Utilities, Volltext nur für L9, L25 und L36 sowie zur Prüfung der Schwellen bei Gabbett 2016 |
| Prüftiefe L41–L70 | Originaltext der Seiten, gezielt nach den behaupteten Aussagen durchsucht, nicht vollständig gelesen |
| Rechnungen | R1 bis R3, TSB%, Energiereserve, CV und Pace selbst nachgerechnet, dazu 12-Wochen-Beispiele |
| Zusätzlich gelesen | Damsted 2019, ProjectRun21 mit Studiendesign, Kluitenberg 2016, Relph 2023, Gabbett 2016, Oliveira 2024 (nur Zusammenfassung aus einer Websuche), Google `/health/app-verification`, `/health/setup` und Codelab, Garmin-PKCE-PDF, Suunto FAQ und How-to-start, Polar-Lizenzvertrag |

**Nicht geprüft (kein Urteil über die Richtigkeit):**
- L53 the5krunner: HTTP 403.
- L6, Volltext BJSM: HTTP 403, geprüft sind nur Abstract und Blogbeitrag der Autoren (L7).
- L39, zweite URL (Borbély 2022): nicht abgerufen.
- L57, zweite URL (Device compatibility): nicht abgerufen.
- Withings API Plans: Die Seite liefert ohne Skript keinen Inhalt, daher bleiben Preise und die Obergrenzen aus L70 ungeprüft.
- Garmin Personal API Swagger und Portal: hinter Skript oder Login.
- Offizielle Garmin-Seite zu Health Connect: Auch meine Suche fand nur Dritte.
- Android-Autorisierungsanleitung von Google: Sie wäre für den Befund M12 zu lesen, wurde aber nicht abgerufen.
- Oliveira 2024: Volltext nicht gelesen.

---

## Blocker

### B1. PAR-052: Die Wochengrenze erlaubt nach jeder Entlastung Sprünge von 37,5 bis 50 %
- **Typ:** `Wert`
- **Problem:** Die Begründung sagt: „30 % ist die einzige wiederkehrende Warnmarke […]; die Wochengrenzen bleiben darunter.“ Die Definition sagt aber: „‚Je Woche‘ bezieht sich auf die letzte Woche ohne Entlastung.“ Mit −20 % aus PAR-057 ergibt das von der Entlastungswoche zur Folgewoche:

| Stufe | Rechnung | Tatsächlicher Sprung |
|---|---|---|
| Einsteiger | 80 auf 110 | **+37,5 %** |
| Aufbau | 80 auf 115 | **+43,8 %** |
| Erfahren | 80 auf 120 | **+50 %** |

  Das tritt in jedem Zyklus auf. Ausgerechnet die Stufe „Einsteiger“ liegt damit über der Marke, unter der die Begründung sie verortet. Die Vorlage Run Clever, die PAR-052 nennt, springt in dieser Woche um 23 %.
- **Beleg:**
  - L9 (https://pmc.ncbi.nlm.nih.gov/articles/PMC4842282/): „a progression of 23 % in running […] the first week, a second and third adaptation week with 0 % progression and a fourth regression week with 10 % regression“.
  - L2 (https://vbn.aau.dk/da/publications/excessive-progression-in-weekly-running-distance-and-risk-of-runn): „may be well advised to progress their weekly distances by less than 30% per week over a 2-week period“.
  - Damsted 2019, nicht zitiert (https://pubmed.ncbi.nlm.nih.gov/30526231/): Halbmarathon-Vorbereitung, 261 Läufer, Steigerung 20–60 % gegen unter 20 %: „risk difference, 22.6%; 95% confidence interval: 0.9%, 44.3%; P = .041“ an Tag 21, nach 56 und 98 Tagen kein Unterschied.
- **Einordnung:** Ein Schaden ist nicht belegt. L6 findet für das Wochenverhältnis keinen Zusammenhang, und der Sprung bezieht sich teils nur auf eine abgesenkte Woche. Falsch ist die Aussage der Begründung, und diese Regel trifft jeden Nutzer alle 4 Wochen.
- **Korrektur:** Die erste Woche nach einer Entlastung erreicht höchstens die letzte Woche ohne Entlastung (+0 %). Die Wochengrenze gilt ab der zweiten Woche.
- **Folgen:**
  - Der größte Sprung sinkt bei −20 % Entlastung auf +25 %, also unter 30 %.
  - Die Spitze je Zyklus bleibt gleich, weil die Zyklusgrenze sie begrenzt. Beispiel Aufbau ab 120 min: Woche 5–7 bisher 165,6 / 172,8 / 172,8, künftig 144 / 165,6 / 172,8.
  - Die Planlänge ändert sich nicht.
  - Außerdem die Begründung um den tatsächlichen Sprung ergänzen und das Beispiel in PAR-084 mitprüfen.

### B2. PAR-051, PAR-054, PAR-062: Ein Einsteiger wird nach 8 Wochen automatisch „Aufbau“ und darf dann intensiv trainieren
- **Typ:** `Wert`
- **Problem:** „Aufbau“ verlangt nur mindestens 8 der letzten 12 Wochen mit mindestens 2 Läufen. Ein Mensch ohne Lauferfahrung erreicht das nach 8 Wochen. Ab dem 30-min-Dauerlauf entfällt auch die Selbstauskunft als Sperre. Dann gelten +15 % / +20 % (PAR-052), 1 intensive Einheit (PAR-062) und bis zu 15 % harte Zeit (PAR-061).
  - Die 8 Wochen in PAR-054 stammen aus Run Clever. Die Studie schloss aber nur Personen ein, die schon 6 Monate regelmäßig liefen. Die 8 Wochen waren dort eine zusätzliche Vorbereitung und kein Weg vom Einsteiger zur Intensität.
  - PAR-054 begrenzt nur das Wachstum des harten Anteils, nicht den Einstieg von 0 auf den ersten Wert.
  - PAR-051 begrenzt nur die Regelmäßigkeit, nicht den Umfang: 2 × 15 min genügen.
- **Beleg:**
  - L9 (https://pmc.ncbi.nlm.nih.gov/articles/PMC4842282/): „with an average of 1 – 3 weekly running sessions the past 6 months are eligible“.
  - Kluitenberg 2016, nicht zitiert (https://pubmed.ncbi.nlm.nih.gov/26452583/): 1.696 Laufanfänger, „running with a higher intensity in the previous week was associated with a higher injury risk“. Das ist beobachtend, und die Autoren warnen vor direkter Übernahme als Leitlinie.
  - Rechnung siehe Abschnitt „12-Wochen-Beispiele“.
- **Korrektur:** Bis zu einer neuen Freigabe:
  - „Aufbau“ verlangt zusätzlich mindestens 6 Monate regelmäßiges Laufen, wie der Einschluss in L9, oder eine entsprechende Selbstauskunft.
  - Intensive Einheiten beginnen frühestens 8 Wochen nach dem Ende des Einstiegs.
  - Die erste intensive Phase hat höchstens 5 % harte Zeit, die Woche zählt als Steigerung im Sinne von PAR-054.
  - Die Art bleibt `Heuristik`. Die Begründung nennt ausdrücklich, dass L9 keine Einsteiger untersucht.
- **Folgen:** Neue Läufer laufen länger nur locker, was FR-0151 ausdrücklich zulässt. Zeitziele werden für sie seltener „realistisch“ (PAR-083). PAR-051 braucht eine Zeile „Dauer seit Beginn“, die bei fehlenden Daten aus der Selbstauskunft kommt.

---

## Muss

### M1. PAR-074, PAR-073, Rechnung R3: Die einwöchigen Sprünge sind falsch berechnet, der Schluss kehrt sich um
- **Typ:** `Beleg/Text`
- **Problem:** R3 nennt „Tiefster TSB% (7-Tage-Mittel)“: 1 Woche ×1,5: −14; 1 Woche ×2: −27. Mit den Formeln aus FR-0098, FR-0099 und FR-0101 ergibt das rollende Mittel:

| Fall | Dokument | Rollendes 7-Tage-Mittel | Abhängig vom Muster |
|---|---|---|---|
| 1 Woche ×1,5 | −14 | **−19** | −18,5 bis −19,6 |
| 1 Woche ×2 | −27 | **−36** | −34,9 bis −36,9 |
| 3 Wochen ×1,5 | −25 | −26 | bestätigt |
| 2 Wochen ×2 | −46 | −47 | bestätigt |

  Die Werte −14 und −27 lassen sich etwa reproduzieren, wenn man nur über die Kalenderwoche des Sprungs mittelt (−13 bzw. −25 bei konstanter Tageslast). Dann ist das Tief aber noch nicht erreicht. Die Aussage in PAR-074 „Ein einzelner verdoppelter Wochenumfang erreicht −27 und löst nicht aus“ ist damit falsch: Er erreicht rund −36 und **löst aus**. Der Fehler wirkt in die sichere Richtung, die Begründung stimmt aber nicht.
- **Beleg:** Eigene Rechnung, Ansatz siehe „Rechnungen“. Die Lesehilfe definiert nur „das Mittel über 7 Tage“, ohne rollend oder Kalenderwoche festzulegen.
- **Korrektur:** R3 berichtigen und PAR-074 umformulieren: Eine verdoppelte Woche löst aus, das +1,5-Fache nicht. PAR-073 und die Lesehilfe legen „rollendes Mittel der letzten 7 Tage“ fest, das ändert Werte nahe der Schwelle um bis zu 10 Punkte. Der Wert −30 bleibt.

### M2. PAR-053: Die Regel „immer +5 min“ hebt die stärkste Quelle für alle Läufe unter 50 min auf
- **Typ:** `Wert`
- **Problem:** Die Begründung stützt sich auf L6 und dessen Grenze von 10 %, die Art lautet `abgeleitet`. Die Ausnahme gilt aber rechnerisch bis 50 min: 25 auf 30 min sind +20 %, 30 auf 35 min +16,7 %, 40 auf 45 min +12,5 %. Damit fällt fast jeder Einsteiger in die Klasse „small spike“ mit der HRR 1,64. Das steht als „eigene Wahl“ im Text, die Folge wird aber nicht genannt. Außerdem gibt es keine Grenze je Woche: Die längste Einheit kann über die Fortschreibung des 30-Tage-Bezugs je Woche um 10 % und mehr wachsen, also +46 % in 4 Wochen. L6 prüft nur die einzelne Einheit, nicht diese Folge.
- **Beleg:**
  - L6 (https://researchportal.lih.lu/en/publications/how-much-running-is-too-much-identifying-high-risk-running-sessio/): „small spikes (HRR=1.64 (95% CI: 1.31 to 2.05, p=0.01))“.
  - L7 (https://blogs.bmj.com/bjsm/?p=11751): „increases in the longest run may be vastly less than 10%“.
- **Korrektur:** Die Ausnahme auf +3 min senken und nur unter 30 min zulassen, dann gelten 110 %. Höchstens eine Erhöhung des Bezugs je Woche. In der Begründung die Folge für kurze Läufe nennen.
- **Folgen:** Kurze Einheiten wachsen etwas langsamer, Beispiel 25 auf 28 min statt 30 min. Die Abfolge aus PAR-065 passt weiterhin: Ihre Gesamtzeiten liegen in allen 9 Wochen innerhalb von 110 % des 30-Tage-Bezugs (nachgerechnet aus L15). Der Einfluss auf PAR-084 ist gering, weil dort PAR-063 und PAR-052 begrenzen (siehe M5).

### M3. PAR-055, PAR-056, PAR-078: Nach einer stark verkürzten Woche gibt es keine Rampe
- **Typ:** `Wert`
- **Problem:** Eine Pause gilt erst ab 7 Tagen (PAR-078). Eine ungeplant um mindestens 20 % kürzere Woche zählt als Entlastung (PAR-056), egal wie stark sie ausfällt. PAR-055 verhindert dann nur die Steigerung: „Sonst bleibt die Woche gleich oder sinkt.“ Eine Krankheitswoche mit 40 statt 120 min erlaubt somit in der Folgewoche wieder 120 min, also +200 %. Eine echte Entlastungswoche und eine fast ausgefallene Woche werden gleich behandelt. Der Wert −20 % aus der Begründung trifft nur Ersteres.
- **Beleg:** PAR-055, PAR-056, PAR-078 in `docs/planning-rules.md`. Größenordnung: L2 und Damsted 2019 (https://pubmed.ncbi.nlm.nih.gov/30526231/), beide wie in B1.
- **Korrektur:** War der Ist-Umfang der Vorwoche unter 50 % des Plans, gilt wie bei 7–13 Tagen Pause: 1 Woche mit 80 %, ohne intensive Einheit. Bei 50–80 % bleibt die Woche gleich ohne intensive Steigerung. FR-0163 behält Vorrang.
- **Folgen:** Etwas mehr Planänderungen nach kurzen Ausfällen, die über PAR-080 begründet werden müssen.

### M4. PAR-054: Der harte Anteil darf je Woche so schnell wachsen wie die Vorlage je Zyklus, und PAR-052 sieht die Belastung nicht
- **Typ:** `Wert`
- **Problem:** PAR-054 erlaubt je Woche eine Wiederholung oder +10 % harte Zeit. In Run Clever stieg der harte Anteil nur **je 4-Wochen-Zyklus** (3,0 auf 3,3 auf 3,5 auf 3,8 km, 6–9,5 % je Zyklus), und die Gesamtmenge blieb dabei fest. Dort stieg in einem **Zyklus** nur eines, nicht in einer Woche. Außerdem wirken sich PAR-052 (Minuten) und PAR-054 nicht gemeinsam aus: In Wochen ohne Umfangszuwachs darf der harte Anteil steigen, die Belastung wächst also fast jede Woche. Im Beispiel Aufbau wachsen die Minuten bis Woche 11 um 73 %, die TRIMP-Last aber um 94 %.
- **Beleg:** L9, Tabelle 2 und Abschnitt „Intervention“ (https://pmc.ncbi.nlm.nih.gov/articles/PMC4842282/): „The total running volume per week is fixed, and only kilometers at a hard running pace follow the progression“.
- **Korrektur:** „In einem Zyklus steigt nur eines: Umfang oder harter Anteil.“ Harte Zeit höchstens +10 % oder 1 Wiederholung je Zyklus.
- **Folgen:** Pläne mit Tempoanteil bauen sich langsamer auf. Erfahrene mit Zielzeiten sind stärker betroffen, die Einstufung nach PAR-083 ändert sich aber nicht unmittelbar. Liegt ein Zielkonflikt vor, greift PAR-084.

### M5. PAR-068, PAR-063, PAR-084: Die Regellängen sind nach den eigenen Grenzen nicht erreichbar
- **Typ:** `Wert`
- **Problem:** PAR-084 rechnet nur mit PAR-053 („60 min wachsen […] in 7 Wochen auf rund 117 min; PAR-053 schließt einen Halbmarathon also nicht von vornherein aus“). Bindend sind aber PAR-063 (lange Einheit höchstens 40 %) und die Zyklusgrenze aus PAR-052. Ab 3 × 30 min = 90 min je Woche:

| Stufe | 10 km, 12 Wochen, längste Einheit (Ziel 60) | Halbmarathon, 16 Wochen, längste Einheit (Ziel 90–120) | Nötige Länge HM mit 90 min |
|---|---|---|---|
| Einsteiger | 55 min, nein | 63 min, nein | rund 28–29 Wochen |
| Aufbau | 62 min, ja | 75 min, nein | rund 22–23 Wochen |
| Erfahren | 70 min, ja | 88 min, knapp nein | — |

  Auch 10 km in 10 Wochen werden in keiner Stufe erreicht (48 / 52 / 56 min). Die App würde also ihren eigenen Regelplan mit „eher unrealistisch“ bewerten.
- **Beleg:** Eigene Rechnung mit PAR-052, PAR-057, PAR-063, PAR-070. Die Rechnung nimmt nach B1 unverändert die Spitzen, die Zyklusgrenze bindet.
- **Korrektur:** PAR-068 anpassen: ab 30 min Dauerlauf 10 km 12–16 Wochen, Halbmarathon 22–28 Wochen. Alternative: Zielspitze Halbmarathon auf 75–90 min senken oder PAR-063 auf 50 % in der Spitzenphase heben, damit 90 min bei 180 min je Woche möglich sind. Das muss der Maintainer entscheiden. Das Beispiel in PAR-084 um PAR-063 und PAR-052 ergänzen.
- **Folgen:** Längere Pläne. Die Alternative „50 %“ erhöht den Anteil der langen Einheit, was die Begründung von PAR-063 nicht deckt.

### M6. PAR-050, PAR-052: Die Evidenz ist einseitig wiedergegeben, „Richtung belegt“ trägt nicht
- **Typ:** `Beleg/Text`
- **Problem:**
  - „Richtung belegt“ in PAR-052 steht im Widerspruch zu „Eine Übersicht […] fand widersprüchliche Ergebnisse“ und zu L1, L5, L6.
  - „Die einzige wiederkehrende Warnmarke“ ist 30 %: Damsted 2019 prüft 20–60 % gegen unter 20 %, mit einem signifikanten Unterschied an Tag 21.
  - L3 wird nur mit dem nicht signifikanten Teil genannt. Das signifikante Ergebnis fehlt: 86 % Steigerung in der Woche vor der Verletzung gegenüber anderen Wochen (p = 0,026).
  - L3 sagt „some individuals may tolerate“, der Text sagt allgemein „Anfänger vertragen“.
  - L4 wird nur mit „very limited evidence“ genannt. Dass 3 von 4 Arbeiten einen Zusammenhang fanden und eine nicht, fehlt.
  - L2 definiert die Exposition über einen 2-Wochen-Zeitraum, nicht je einzelner Woche.
  - In L1 lagen die Wochensteigerungen laut L9 bei 10,5 und 23,7 %. Diese direkt verwertbare Zahl fehlt in PAR-050 und PAR-052.
  - PAR-052 schreibt „Rechnung R2 zeigt“ für +33 % und das 4,2-Fache, R2 enthält das 4,2-Fache nicht. Der Wert stimmt, wenn schon die erste Woche steigt (1,1¹⁵ = 4,18).
- **Beleg:**
  - L3 (https://pubmed.ncbi.nlm.nih.gov/22990565/): „86% [95% confidence interval: 12.9-159.9], p = 0.026“.
  - L4 (https://pubmed.ncbi.nlm.nih.gov/30534459/): „Four articles fulfilled the eligibility criteria of which three found an association“.
  - L2: „over a 2-week period“.
  - L9: „a trial by Buist et al. comparing a weekly progression of 10.5 and 23.7 % found no difference“.
- **Korrektur:** „Richtung plausibel, nicht konsistent belegt“. Die fehlenden Ergebnisse in beiden Richtungen ergänzen, Damsted 2019 als Quelle aufnehmen und „die einzige“ streichen. Die Werte bleiben.

### M7. PAR-059: „rund 48 h von Start zu Start“ stimmt nicht und erreicht die Quelle nicht
- **Typ:** `Beleg/Text`
- **Problem:** Ein freier Kalendertag ergibt nicht rund 48 h: Montag 18 Uhr bis Mittwoch 7 Uhr sind 37 h, im Grenzfall etwa 25 h. L10 nennt für hohe Intensität „at least 48 h“ bis zur vollständigen autonomen Erholung, und zwar nach der Einheit. Die Regel unterschreitet die Untergrenze aus L10 also je nach Tageszeit deutlich. Der Text nennt sie eine Plausibilitätsgrenze, die Zahl legt aber eine Übereinstimmung nahe.
- **Beleg:** L10 (https://pubmed.ncbi.nlm.nih.gov/23912805/): „up to 24 h following low-intensity exercise, 24-48 h following threshold-intensity exercise and at least 48 h following high-intensity exercise“.
- **Korrektur:** „rund 48 h“ ersetzen durch „je nach Tageszeit etwa 25 bis über 60 h; für hohe Intensität also nicht immer die in L10 genannten mindestens 48 h“. Die Art ändert sich zu `Heuristik`, die Richtung stützt L10. Der Wert kann bleiben.

### M8. PAR-061: `abgeleitet` trifft nicht zu
- **Typ:** `Beleg/Text`
- **Problem:** Keine Quelle ergibt 85 % bei Aufbau und 80 % bei Erfahren, auch kein benannter Rechenschritt. Die Zeile sagt selbst: „die konservativere Wahl, nicht die bewiesen beste“. Das ist nach der Lesehilfe eine `Heuristik`. Zudem misst L11 nach Einheiten, die Regel nach Zeit. Die Zeile nennt das Merkmal, zieht aber keine Folge daraus.
- **Beleg:** L11 (https://pubmed.ncbi.nlm.nih.gov/20861519/): „about 80% of training sessions“. Lesehilfe in `docs/planning-rules.md`.
- **Korrektur:** Art auf `Heuristik` ändern. In der Begründung festhalten, dass 20 % harte Zeit nicht aus L11 folgt, sondern der Größenordnung von Zone 3 in L12 und L13 entspricht.

### M9. PAR-065, PAR-056: Es gibt eine prüfende Studie, und die Abfolge widerspricht dem Takt der Entlastungswochen
- **Typ:** `Beleg/Text`
- **Problem:**
  - „Eine prüfende Studie wurde nicht gefunden.“ Die PubMed-Suche nach „couch to 5k“ findet Relph et al. 2023: 110 Teilnehmer in einer abgewandelten 9-Wochen-Fassung, 19 % berichtete Verletzungen, nur 27,3 % schlossen ab, Abbruch verbunden mit Verletzungen und dem Aufbau des Programms. Das ist klein, abgewandelt, und 64 % hatten Lauferfahrung. Es relativiert die Vorlage aber.
  - Die Zeile nimmt nur PAR-052 aus. PAR-056 („Jede 4. Woche“) gilt weiter, die NHS-Abfolge hat aber keine Entlastung und reicht 9 Wochen. Das ist ungeklärt.
  - Die Zeile nennt +78 % Laufminuten, nicht aber die weiteren Sprünge: längster Dauerlauf von 8 auf 20 min innerhalb von Woche 5.
  - Die Art `belegt` trifft nur auf die Abfolge zu, nicht auf die Ausnahme von PAR-052.
- **Beleg:**
  - https://pubmed.ncbi.nlm.nih.gov/37681822/: „this programme lacks an evidence base“; „Only 27.3% completed the programme“; „Dropping out was linked to MSK injury and progressive design“.
  - L15 (https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/): Woche 5, Läufe 2 und 3.
- **Korrektur:** Relph 2023 als Quelle ergänzen. Festlegen, ob PAR-056 während der Abfolge entfällt, und das nennen. Das Wiederholen einer Woche in der App aktiv anbieten, was L15 ausdrücklich erlaubt. Die Abfolge kann bleiben.

### M10. PAR-087: Zitiert wird der falsche Korrelationswert, passend zum Edwards-TRIMP wäre r = 0,84
- **Typ:** `Beleg/Text`
- **Problem:** Die Zeile nennt r = 0,76, also 58 % gemeinsame Varianz. Dieser Wert gilt in L30 für den TRIMP. Die zweite Methode dort, die Summated-Heart-Rate-Zone (SHRZ), hat dieselben Zonen wie FR-0092 (50–60, 60–70, 80–90 % HFmax) und entspricht damit dem Verfahren der App. Dafür nennt L30 r = 0,84, also rund 71 % gemeinsame Varianz. Die Quelle stützt die App also etwas stärker als zitiert, und PAR-086 nennt „Edwards ist darin nicht gemessen“ nur für L31.
- **Beleg:** L30 (https://pubmed.ncbi.nlm.nih.gov/19193951/): „A correlation of r = .84 (.70 to .92) occurred between SHRZ and session-RPE training load“.
- **Korrektur:** r = 0,84 mit KI 0,70–0,92 als den näheren Wert nennen und 0,76 als Vergleich. Die Gleichsetzung von SHRZ und Edwards als eigene Einordnung kennzeichnen. Der Wert bleibt.

### M11. PAR-055, PAR-074, PAR-075, PAR-089, PAR-090: Die Bedingung aus den Schwellen ist in der riskantesten Phase leer, ohne dass die Begründung das sagt
- **Typ:** `Beleg/Text`
- **Problem:** Die 126 Tage sind entschieden und werden nicht neu aufgerollt (OQ-0046). Offen bleibt die Folge für die Begründungen:
  - PAR-055 nennt PAR-074 und PAR-075 als Bedingung für jede Steigerung. In den ersten 18 Wochen sind beide wirkungslos, im 12-Wochen-Beispiel also immer. Dann wirken nur Teilnahme und Selbstauskunft. PAR-089 nennt „4 Monate kein Signal“, aber nicht, dass genau dann auch die Bremse in PAR-055 entfällt.
  - R2 und R3 starten im Gleichgewicht. Beim tatsächlichen Start bei 0 liegt ein Aufbau-Plan an der Grenze an Tag 126 bei −30,0, die Schwelle löst also genau beim ersten Greifen aus. Die Aussage in PAR-074 „bleibt meist darüber“ gilt dann nicht.
  - PAR-090: Bei 3 Einheiten je Woche sind 18 in 42 Tagen erwartet, 2 unbewertete Läufe genügen also, um die Schwellen abzuschalten. Die Quelle L25 rät hier zu Vorsicht und zum Schätzen fehlender Werte, nicht zum Abschalten. Da die Schwellen nur entlasten dürfen, wirkt ein Abschalten gegen den Zweck. Wie man aus dem Rückfall wieder herauskommt, ist nicht festgelegt.
- **Beleg:** L25 (https://www.trainingpeaks.com/learn/articles/the-science-of-the-performance-manager/): „any error introduced […] as a result of poorly estimating the true TSS for one or two missing workouts is likely to be minimal“; „(e.g., >10% of all files for a particular block of time) […] should be interpreted with considerable caution“. Rechnung siehe unten.
- **Korrektur:** PAR-055 und PAR-089 nennen die Lücke offen. Die Rechnung für den Start bei 0 in R1 oder PAR-074 ergänzen. PAR-090 legt das Ende des Rückfalls fest, zum Beispiel bei wieder höchstens 10 % Lücke im 42-Tage-Fenster. Der Wert 126 bleibt.

### M12. Teil D, Google Health API (OQ-0047): Die Kosten sind offiziell genannt, und die Bedingung für die Sicherheitsprüfung ist auf der Produktseite strenger
- **Typ:** `Beleg/Text`
- **Problem:** Die Zeile sagt: „Keine Angabe; Kosten eines Assessments nicht genannt“ und stellt die Pflicht als unklar dar. Sie wird im Dokument nicht zitiert, nennt aber die Kosten, die Dauer und eine Pflicht ohne Bedingung zu Servern. Außerdem:
  - L61 ist die Anleitung für Desktop-Apps und verweist für Android auf eigene Anleitungen. Sie belegt also nicht „Android-Clients ohne Client-Secret“.
  - Unter „Nicht abrufbar“ steht `/health/authentication` (404). Die tatsächliche Anleitung `/health/setup` ist aber aus der Navigation erreichbar. Sie und das Codelab zeigen nur „Web Server“ bzw. „Web Application“ mit Client-Secret. „Wohl ja“ stützt sich also auf keine Aussage der Health-API-Doku.
  - Das Kürzel L60 belegt „Alle Scopes Restricted“ nicht: `/health/scopes` nennt das nicht. Es steht in `/health/about` („All Google Health API scopes are categorized as Restricted“) und abgeschwächt in `/health/app-verification` („Most scopes“).
  - Nicht genannt ist: Nutzer müssen sich vor der Einwilligung in der Google-Health-App anmelden.
- **Beleg:**
  - https://developers.google.com/health/app-verification: „apps using restricted scopes must also complete an annual security assessment“; „involves fees payable to the third-party assessor, ranging from $500 to $4,500 USD“; „2-3 weeks for tier-2 applications and 4-6 weeks for tier-3“.
  - https://developers.google.com/health/setup: „Select Web Server“.
  - Codelab: https://developers.google.com/health/codelabs/make-your-first-api-call.
  - L61 (https://developers.google.com/identity/protocols/oauth2/native-app): „For mobile apps, see the Android and iOS authorization guides“.
- **Korrektur:** Kosten und Dauer eintragen und die Pflicht als offizielle Aussage der Produktseite führen, im Widerspruch zur allgemeinen Seite L62. Für die Planung gilt: jährlich $500–4.500, bis Google anderes sagt. Quelle für Restricted korrigieren. Die Android-Anleitung lesen und zitieren. Die Entscheidung OQ-0047 bleibt, weil sie an die Prüfung gebunden ist. Der Maintainer sollte aber die Kosten kennen, die jährlich anfallen, bevor die Prüfung beginnt.

### M13. Teil D, Garmin Business (OQ-0047): Client-Secret und PKCE sind offiziell belegt, „offen“ ist überholt
- **Typ:** `Beleg/Text`
- **Problem:** Die Zeile nennt das Client-Secret nur aus Dritten und lässt Enterprise offen („Push or Ping/Pull, offen, Details hinter Login“). Garmins öffentliche PKCE-Spezifikation klärt das: PKCE ist vorgeschrieben, **und** der Token-Tausch verlangt das Secret. Damit entfällt auch Enterprise ohne ausgeliefertes Secret, unabhängig vom Pull-Modus. Der Befund für ADR-0001 nennt nur Starter.
- **Beleg:** https://developerportal.garmin.com/sites/default/files/OAuth2PKCE.pdf: „Garmin Connect Developer Program uses the OAuth2.0 PKCE version“; „client_secret=<client secret (consumer secret)>, required“. Einschränkung: Das Dokument trägt keine erkennbare Version und kann vor dem Neustart im Oktober 2026 entstanden sein. Die FAQ bestätigt nur OAuth 2.0.
- **Korrektur:** Als offizielle Quelle aufnehmen, Stand zum Abrufdatum vermerken, in der Zeile und im Befund schreiben: „Business insgesamt nur mit Secret, PKCE ändert daran nichts.“

### M14. Teil D, Suunto (OQ-0047): „Ungeklärt“ ist durch öffentliche Seiten von Suunto beantwortet
- **Typ:** `Beleg/Text`
- **Problem:** Die Zeile sagt „Ungeklärt, eher nein“ und stützt sich auf Dritte. Die FAQ und die How-to-start-Seite von Suunto sind öffentlich lesbar und zeigen den Token-Tausch mit Secret. Der Webhook muss öffentlich erreichbar sein und gilt laut FAQ nur für Workouts; L65 nennt inzwischen auch 24/7-Ereignisse, die FAQ kann also älter sein. Auch der Subscription-Key muss bei jedem API-Aufruf mit. PKCE beschreibt Suunto nicht.
- **Beleg:**
  - https://apizone.suunto.com/faq: „Authorization: Basic Base64(clientid:clientsecret)“; „Ocp-Apim-Subscription-Key parameter is required for Cloud API requests“; „There is no webhook / notification model in place for activity data“.
  - https://apizone.suunto.com/how-to-start: „--user <CLIENT_ID>:<CLIENT_SECRET>“.
- **Korrektur:** Zeile ändern in „Nur mit eingebettetem Secret und Subscription-Key (offiziell), PKCE nicht beschrieben“. Den Befund für ADR-0001 um Suunto ergänzen. Die Zulassung ohne Firma bleibt offen.

---

## Soll

### S1. PAR-074, PAR-075: „Keine Quelle nennt den Wert“ verschweigt eine bekannte Entsprechung
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** Nach `TSB% = 100·(1 − ATL/CTL)` entspricht −30 einem Verhältnis von 1,30 und −45 von 1,45. Das liegt fast genau an der Grenze „sweet spot“ von Gabbett 2016 (https://pmc.ncbi.nlm.nih.gov/articles/PMC4789704/): „within the range of 0.8–1.3 could be considered the training ‘sweet spot’, while […] ≥1.5 represent the ‘danger zone’“. Genau das kritisieren L22 und L23.
- **Korrektur:** Die Entsprechung nennen, ausdrücklich nicht als Beleg, und festhalten, dass Gabbett mit anderem Zeitfenster und anderen Sportarten rechnet.

### S2. PAR-068: Zum Halbmarathon gibt es eine leicht auffindbare Studie
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** „Für Pläne über 10 km oder Halbmarathon konnte keine Studie […] gelesen werden.“ ProjectRun21 begleitete 784 Läufer über einen 14-Wochen-Plan für den Halbmarathon (https://pubmed.ncbi.nlm.nih.gov/30190100/). Die Plandetails stehen im Studiendesign (https://pmc.ncbi.nlm.nih.gov/articles/PMC5673057/).
- **Korrektur:** Als Größenordnung aufnehmen, mit dem Hinweis, dass die Teilnehmer schon liefen. Das ändert nichts daran, dass die Studie keinen Plan als sicher belegt.

### S3. PAR-054, PAR-062, PAR-064: Eine große Studie an Laufanfängern fehlt
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** Kluitenberg 2016 misst wie die App in Minuten: 1.696 Laufanfänger, höhere Intensität mit mehr Verletzungen verbunden, geringerer Umfang ebenfalls, und ein Trend, dass 3 Läufe je Woche riskanter sind als 2 (https://pubmed.ncbi.nlm.nih.gov/26452583/): „should not be used plainly as a guideline for novices“.
- **Korrektur:** Mit dieser Einschränkung nennen. Sie ist Beobachtung und zeigt keine Ursache.

### S4. PAR-061: Eine neuere Metaanalyse ist auffindbar
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** Unter „Nicht abrufbar“ steht zu Oliveira 2024, die PubMed-Suche habe keinen Treffer ergeben. Die Arbeit ist laut Websuche in PMC verfügbar (PMID 38717713, https://pmc.ncbi.nlm.nih.gov/articles/PMC11329428/). Laut der Zusammenfassung aus der Websuche: 17 Studien, 437 Personen, kleiner Vorteil bei VO₂peak (SMD 0,24), keiner bei Zeitfahren und Zeit bis zur Erschöpfung. Das stützt den Schluss der Zeile besser als L14 allein. Den Volltext habe ich nicht gelesen.
- **Korrektur:** Volltext lesen und ergänzen. Die Aussage „zugunsten des polarisierten Modells“ entsprechend einschränken.

### S5. PAR-050, PAR-065, PAR-072, PAR-091, PAR-064, PAR-070: Art vermischt Beleg und Entscheidung
- **Typ:** `Beleg/Text`
- **Problem:** PAR-050, PAR-072 und PAR-091 sind Regeln oder Entwurfsentscheidungen, die auf Belegen beruhen. Die zitierten Zahlen stimmen, „Nicht als Sicherheitsregel verwenden“ steht aber in keiner Quelle. Nach der Lesehilfe wäre das `abgeleitet`. PAR-064 und PAR-070 nennen den Anteil eigener Wahl nur teilweise (Spanne 25–30 min, RPE ≤ 4, 3-Stunden-Regel). Ein Beleg wird hier nicht vorgetäuscht, die Texte sagen es überwiegend offen.
- **Beleg:** Lesehilfe in `docs/planning-rules.md`, Zeilen 10 und 11.
- **Korrektur:** Art auf `abgeleitet` setzen, bei PAR-065 in `belegt` (Abfolge) und `Heuristik` (Ausnahme) trennen, bei PAR-064 und PAR-070 die eigene Wahl vollständig nennen.

### S6. PAR-070: „stufenweise oder gleitend“ ist nur von einer der drei Quellen gedeckt
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** L16: „exponentially decreased by 41-60%“. L18: „Progressive nonlinear tapers are more beneficial to performance than step tapers“, außerdem Häufigkeit „slightly reducing […] no more than 20%“. Nur L17 stützt auch Stufen („a progressive or step taper“). Die Abweichung wird nicht genannt (https://pubmed.ncbi.nlm.nih.gov/17762369/, https://pubmed.ncbi.nlm.nih.gov/12840640/, https://pubmed.ncbi.nlm.nih.gov/37163550/).
- **Korrektur:** Den Widerspruch nennen. Der Wert kann bleiben, weil Stufen einfacher zu planen sind. Das als eigene Wahl kennzeichnen.

### S7. PAR-082: Der Bereich ±10 % deckt die eigene Rechnung nicht
- **Typ:** `Wert`
- **Problem:** Die Zeile rechnet richtig: 10 % VO₂max-Fehler verschieben die Pace um bis zu 13 %. PAR-081 nennt zugleich 8–10,2 % MAPE für Wearables [Q2]. Der Bereich „ausreichend“ von ±10 % deckt also nur rund 8 % Fehler. Nachrechnung mit FR-0069: −10 % ergeben v −11,5 %, also Pace +13 %.
- **Korrektur:** ±13 % für „ausreichend“, oder im Text sagen, dass ±10 % bewusst enger ist.
- **Folgen:** Breitere Vorgaben, die im Training weniger führen. Keine Änderung an den Stufen.

### S8. PAR-086: Die Genauigkeit gilt für das Mittel, PAR-087 verwendet den Median
- **Typ:** `Beleg/Text`
- **Problem:** ±28 / ±20 / ±14 % stimmen für das Mittel. Der Median streut bei Normalverteilung rund 1,25-mal stärker: ±35 / ±25 / ±18 %. Das Ziel ±20 % wäre erst bei rund 16 Läufen erreicht.
- **Beleg:** Rechnung, CV aus L31 (https://pubmed.ncbi.nlm.nih.gov/24662229/) bestätigt: 28,1 und 15,6 %.
- **Korrektur:** Die Abweichung nennen. Da „noch wenig gesichert“ bis 20 Läufe gilt, kann der Wert 10 bleiben.

### S9. PAR-083: Die Fortschrittsraten stammen von schnellen Läufern
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** L12 (https://pubmed.ncbi.nlm.nih.gov/23752040/) hat einen Ausgangswert von rund 39 min über 10 km („39min18s ± 4min54s“). Die Zeile nennt diese Gruppe nur „Freizeitläufer“, und die Fortschrittsrate wird für die Grenzen bei Einsteigern herangezogen.
- **Korrektur:** Das Leistungsniveau nennen, die Grenzen für Einsteiger entsprechend als eigene Annahme führen.

### S10. PAR-094, PAR-096: Das Modell behält eine harte Einheit kaum über die Nacht
- **Typ:** `Beleg/Text`
- **Problem:** Die Rechnungen stimmen (91 / 38, 78 / 28, 94 %). Nicht genannt ist: −36 aus 240 TRIMP schrumpfen bis zum nächsten Morgen auf etwa −2,2 Punkte (90,8 gegen 88,6), bei 360 TRIMP auf etwa −3,3. Der Morgenwert hängt damit fast nur von Schlafdauer und `f` ab (f = 0,5: 76; f = 1,25: 94). Mehrtägige Ermüdung kann das Modell so kaum abbilden, „plausibel“ gilt nur für den Tagesverlauf.
- **Korrektur:** Das als bekannte Eigenschaft nennen und unter PAR-099 mitprüfen. Die Funktion bleibt bis zur Kalibrierung ausgeblendet (OQ-0030), daher keine Dringlichkeit.

### S11. PAR-064: Die Ja-Antwort startet ohne Rampe
- **Typ:** `Wert`
- **Problem:** Wer „Kannst du 30 min am Stück laufen?“ bejaht und nur einen Wochenumfang nennt, beginnt mit bis zu 3 × 30 min. Das sind 90 Laufminuten in Woche 1 gegenüber 24 in der NHS-Abfolge, gestützt nur auf eine ungeprüfte Selbstauskunft.
- **Beleg:** L15, eigene Rechnung. Größenordnung zum Umfang: L20 (https://pubmed.ncbi.nlm.nih.gov/19346973/) mit 3 × 45 min, aber mit „jogging/walking“ nach Pulsvorgabe.
- **Korrektur:** In Woche 1 höchstens 3 × 25 min, danach die Einstiegsgrenzen.
- **Folgen:** Geringe Verzögerung für tatsächlich Trainierte. Das Datenpolster von 4 Wochen bleibt gleich.

### S12. Teil D, Polar: Der Lizenzvertrag ist abrufbar
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** „Der Link ließ sich aus der Seite nicht ermitteln.“ Er steht im HTML von L49: https://www.polar.com/en/legal/polar-api-agreement. Dort steht: „At the moment Polar offers the use and activation of Polar API's free of charge“, mit Vorbehalt künftiger Gebühren. Damit ist „Keine Angabe“ überholt. Der Vertrag erwähnt keine Regel zu Client-Secrets, ich habe ihn aber nur gezielt durchsucht.
- **Korrektur:** Kosten und Quelle eintragen, den Punkt aus „Nicht abrufbar“ streichen.

### S13. Teil D, Withings: „`client_secret` oder Signatur“ klingt wie eine Alternative
- **Typ:** `Beleg/Text`
- **Problem und Beleg:** Die Signatur entsteht laut L67 ebenfalls mit dem Secret (https://developer.withings.com/llms.md): „Sign the string with HMAC-SHA256 using your `client_secret`“. Die Aussage „Nur mit eingebettetem Secret“ stimmt.
- **Korrektur:** „mit `client_secret` oder einer daraus erzeugten Signatur“. PKCE findet sich weder in L67 noch in L69, das ergänzen.

### S14. Teil D, Health Connect und Befund: Wortlaut
- **Typ:** `Beleg/Text`
- **Problem und Beleg:**
  - L47 (https://support.google.com/googleplay/android-developer/answer/9888170): „User data may only be transferred to third parties with explicit user consent: for security purposes […], to comply with applicable laws or regulations, or as part of mergers/acquisitions“. Die Weitergabe ist also auch mit Einwilligung auf diese Zwecke begrenzt. Die Zeile nennt nur die Einwilligung.
  - „Ohne Einschränkung“ im Befund meint nur den Server. Die Zeile selbst nennt erhebliche Einschränkungen, etwa dass HRV nur fließt, wenn die Quell-App sie schreibt.
- **Korrektur:** Beide Formulierungen präzisieren, zum Beispiel „als einziger Weg ohne eigenen Server und ohne Secret“.

---

## Auftrag zu OQ-0047: Ergebnis

**Der Befund stimmt und ist eher zu vorsichtig formuliert.** Nur Health Connect kommt ohne Server und ohne Secret aus. Polar und Withings brauchen ein Client-Secret (offiziell bestätigt). Suunto und Garmin Business brauchen es ebenfalls, was das Dokument nicht als offiziell führt (M13, M14).

| Anbieter | Secret beim Token-Tausch | PKCE | Quelle |
|---|---|---|---|
| Health Connect | Kein OAuth | entfällt | L41, L45 |
| Garmin Personal | API-Schlüssel des Nutzers | entfällt | L50, L51 |
| Garmin Business | **Erforderlich** | **Ja, Pflicht, ersetzt das Secret aber nicht** | Garmin OAuth2PKCE.pdf |
| Google Health API | Für Android laut Dokument nicht; in der Health-Doku nicht bestätigt, Android-Anleitung von mir nicht gelesen. `/health/setup` zeigt nur Web Server mit Secret | Ja, für Desktop-Clients gefordert; Android nicht geprüft | L61, `/health/setup` |
| Polar | **Erforderlich** (Basic Auth) | Nicht beschrieben, 0 Treffer in L49 | L49 |
| Suunto | **Erforderlich** (Basic Auth) | Nicht beschrieben | FAQ, How-to-start |
| Withings | **Erforderlich** | Nicht beschrieben, 0 Treffer in L67 und L69 | L67, L69 |

„Nicht beschrieben“ heißt: in der öffentlichen Dokumentation nicht gefunden. Es ist kein Nachweis, dass ein Anbieter es nicht unterstützt.

**Fitbit Web API:** Die Daten stimmen. `/health/about` nennt den 2026-11-02 und HTTP 410, die Fitbit-Doku den 2026-10-30. Die Google-Seite vom 2026-10-23 kündigt dies aber nur an („will be turned off“). Eigener Test am 2026-11-04: `POST https://api.fitbit.com/oauth2/token` liefert HTTP 410. `GET /1/user/-/profile.json` liefert ohne Anmeldung 401, das ist für diesen Pfad nicht aussagekräftig. „Abgeschaltet“ ist für den OAuth-Endpunkt also bestätigt.

---

## 12-Wochen-Beispiele

**Annahmen:** PAR-052 wird wörtlich gelesen und ausgereizt, also als Obergrenze und nicht als jeder tatsächliche Plan. Reihenfolge wie in den Regeln. TRIMP-Gewichte sind meine Annahme: Gehen 1, lockeres Laufen 3 bzw. 2,5, hart 4,5. Alle Rechnungen vor der Korrektur aus B1. Die TSB-Schwellen sind in allen Beispielen wegen PAR-089 inaktiv.

### Einsteiger, Weg A: PAR-065 (kann nicht 30 min laufen), danach Stufe Aufbau

| Woche | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Minuten | 85,5 | 87 | 75 | 94,5 | 92 | 102 | 105 | 114 | 120 | 138 | 144 | 144 |
| Laufminuten | 24 | 27 | 27 | 48 | 51 | 63 | 75 | 84 | 90 | bis 138 | bis 144 | bis 144 |
| TRIMP | 134 | 141 | 129 | 190 | 194 | 228 | 255 | 282 | 300 | 414 | 454 | 464 |
| Harte Zeit | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 10 % | 15 % |

**Ergebnis nach 12 Wochen:**
- Die Zeit steigt um 68 %, die **Laufminuten bis auf das Sechsfache und der TRIMP auf das 3,5-Fache**. Das Maß für die Regel (Minuten einschließlich Gehen) zeigt also den kleinsten Wert.
- Größte TRIMP-Sprünge: +48 % von Woche 3 auf 4 und +38 % von Woche 9 auf 10. Keine Entlastung in 12 Wochen, wenn PAR-056 während der Abfolge nicht gilt (M9).
- Die erste intensive Einheit kommt in Woche 11. Grundlage dafür ist L9, die keine Einsteiger einschloss (B2).

Quelle der Abfolge: L15, Werte aus den Wochenseiten nachgezählt. Die Zeile PAR-065 ist in ihren eigenen Zahlen korrekt (27 auf 48, 75 auf 94,5).

### Einsteiger, Weg B: PAR-064 (bejaht 30 min), ab Woche 8 Stufe Aufbau

| Woche | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Minuten | 90 | 90 | 90 | 90 | 99 | 103,5 | 103,5 | 82,8 | 119 | 124,2 | 124,2 | 99,4 |
| Sprung | | 0 | 0 | 0 | +10 | +5 | 0 | −20 | **+44** | +4 | 0 | −20 |
| Längste Einheit | 30 | 30 | 30 | 30 | 35 | 40 | 41 | 33 | 46 | 50 | 50 | 40 |

**Ergebnis:** Spitze +38 %, längste Einheit +66 %. Der Stufenwechsel lässt den größten Sprung auf +44 % steigen, was die Stufe „Einsteiger“ gerade verhindern soll. Kleinster TSB% im Gleichgewicht −21.

### Aufbau: 3 × 40 min, also 120 min je Woche

| Woche | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Minuten | 138 | 144 | 144 | 115 | 166 | 173 | 173 | 138 | 199 | 207 | 207 | 166 |
| Sprung % | +15 | +4 | 0 | −20 | **+44** | +4 | 0 | −20 | **+44** | +4 | 0 | −20 |
| Längste Einheit | 53 | 58 | 58 | 46 | 63 | 69 | 69 | 55 | 76 | 83 | 83 | 66 |
| TRIMP (hart 0 auf 15 %) | 345 | 360 | 374 | 300 | 431 | 449 | 467 | 373 | 537 | 560 | 581 | 464 |

**Ergebnis:** Spitze +73 % nach 11 Wochen, TRIMP +94 %, längste Einheit von 48 auf 83 min. Zum Vergleich: Run Clever (L9, Schedule Volume) +19 % in 11 Wochen (18,5 auf 22 km). Der kleinste TSB% ist −23,5 (nur Minuten) bzw. −26,9 (mit Härte), löst also nicht aus. Die Schwelle würde selbst dann nicht greifen, wenn sie aktiv wäre: Diese Steigerung liegt innerhalb des Plans, den die Schwelle zulassen soll.

---

## Rechnungen

Ansatz: Tägliche Formeln aus FR-0098, FR-0099 und FR-0101, 3 gleiche Einheiten (Tage 0, 2, 4), Start im periodischen Gleichgewicht, TSB% rollend über 7 Tage. Für R1 Start bei 0 mit täglich gleicher Last.

| Rechnung | Dokument | Nachgerechnet | Urteil |
|---|---|---|---|
| R1 CTL 42 / 84 / 126 Tage | 64 / 87 / 95 % | 63,7 / 86,8 / 95,2 % | Stimmt |
| R1 ATL 21 Tage | 96 % | 96,1 % | Stimmt |
| R1 TSB% Tag 42 / 84 / 126 | −57 / −15 / −5 | −56,9 / −15,2 / −5,0 | Stimmt |
| R2 +15 / +20 / +25 / +33 / +50 % | −20 / −26 / −31 / −38 / −52 | −20,8 / −26,1 / −31,2 / −38,7 / −53,0 (bei anderer Verteilung bis −21,2 / −26,8 / −32,1 / −40,2 / −55,8) | Stimmt, abhängig von der Verteilung in der Woche |
| R2 Schwankung im Wochenmuster | ±13 | −12,2 bis +13,5 (bei 2 Einheiten ±19) | Stimmt |
| R3 1 Woche ×1,5 / ×2 | −14 / −27 | **−19 / −36** | **Falsch (M1)** |
| R3 3 Wochen ×1,5 / 2 Wochen ×2 | −25 / −46 | −26 / −47 | Stimmt |
| PAR-052 +33 %, 4,2-Faches | | 1,1³ = 1,331; 1,1¹⁵ = 4,18 | Stimmt |
| PAR-065 Laufminuten, Zeit | +78 %, 75 auf 94,5 | Stimmt, L15 nachgezählt | Stimmt |
| PAR-081 7:28 min/km | | 1000 / 134 = 7,46 min | Stimmt |
| PAR-082 5 % / 10 % | 6 % / 13 % | Pace +6,1 / +13,0 % (ungünstige Seite) | Stimmt |
| PAR-083 Raten | 0,36–0,5; rund 0,4; rund 0,6 | 5,0 und 3,6 % / 10; 3,0–3,5 % / 8; 16 % · 0,52 / 13 = 0,64 | Stimmt |
| PAR-084 | 117 min | 60 · 1,1⁷ = 116,9 | Stimmt, Schluss nicht (M5) |
| PAR-086 | 32 % CV, ±28 / ±20 / ±14 | 32,1 %; 28,1 / 19,9 / 14,1 | Stimmt, gilt fürs Mittel (S8) |
| PAR-087 r² | 58 % | 0,76² = 0,578 | Stimmt, falscher Wert (M10) |
| PAR-092 | 94 % | 1 − 0,416 · 0,148 = 93,9 % | Stimmt |
| PAR-094, PAR-095 τ | 4,2 / 18,2 h | 4,18 / 18,26 h | Stimmt |
| PAR-094 Tagesverlauf | 91 / 38; 78 / 28 | 90,8 / 37,8; 78,1 / 27,5 | Stimmt |
| PAR-096 | −9 / −16,5 / −36 | Gleich | Stimmt |
| PAR-089 Start bei 0, Aufbau | nicht genannt | Tag 126: −30,0 | Ergänzen (M11) |

## Geprüft ohne Befund

**Zitate, die wörtlich oder sinngemäß stimmen:**
- L1 Buist: 532, 20,8 / 20,3 %, P = 0,90.
- L2 Nielsen: 874, HR 1,59 (0,96–2,66), nur distanzbezogen.
- L3: 60, 13.
- L4: 4 Arbeiten, „very limited evidence“.
- L5: 36, 23.047, Vorsicht bei Empfehlungen.
- L6 und L7: 5.205, 588.071, alle drei HRR, ACWR negativ, Wochenverhältnis ohne Zusammenhang, Autoren zu +1–10 %.
- L8: 447, kein Unterschied.
- L9: 4-Wochen-Zyklen, 23 %, −10 %, 8,5–11,5 %, 2,7–3,8 km.
- L10: Zeitfenster und Grenzen.
- L11 bis L14: alle Zahlen.
- L16 bis L21: alle Zahlen, einschließlich 27 Studien, 14 Studien, Zeitfenster, 48 %, 16 %, 52 %.
- L22, L23: wörtlich, c-Statistik 0,574.
- L24, L26 bis L33: alle Zahlen.
- L25: −10 / +10, Warnung vor wörtlicher Anwendung, 5–7 TSS/d, >10 %, Startwerte.
- L34, L35: als nicht übertragbar eingeordnet.
- L36 bis L38: keine Formeln genannt, Patent und 28 Tage bestätigt.
- L40: 4,2 und 18,2 h.
- L41 bis L46: RMSSD 1–200 ms, 30 Tage, Hintergrundberechtigung, 15 min, 1 h im Beispiel, Datenarten.
- L48: Tom's Guide nennt „HRV status“ als nicht geteilt.
- L49: Basic Auth, Dauerpuls 5 min, ein Webhook, Tokens ohne Ablauf, Formel der Limits.
- L50 bis L52, L54: Garmin-Angaben, einschließlich Zitat zu kommerzieller Nutzung und 30 Tage bis 1 Jahr.
- L55: 2026-10-21, Starter und Enterprise.
- L56, L58 bis L60: bis auf M12.
- L63: RFC 8252 §8.5.
- L64 bis L66: „We do not charge“, wöchentliche Prüfung, höchstens 2 Wochen, RMSSD.
- L67 bis L70: `rmssd`, `sdnn_1`, 10 min, 1 Jahr und Rotation, 10 Nutzer und 1.000 Nutzer als Drittangabe.

**Methodik, die trägt:**
- Beobachtung wird in PAR-053, PAR-059, PAR-072 und PAR-086 als solche benannt. Die Abgrenzungen sind offen formuliert: „ohne Ursache“, „keine Sicherheitsgrenze“, „nicht übertragbar“. Ein Fall, in dem Beobachtung als Ursache verkauft wird, ist mir nicht aufgefallen.
- Die Heuristiken sind als solche gekennzeichnet und nennen die eigene Wahl.
- Die Einordnung von TSB% als ACWR-Variante ist richtig und die Identität `TSB% = 100·(1 − ATL/CTL)` stimmt.
- Dass die Schwellen nur entlasten dürfen, ist mit L6, L22 und L23 gut vereinbar.
- Keine erfundene Quelle gefunden.

## Grenzen dieses Reviews

Studien sind fast nur als Abstract geprüft, wie im Originaldokument. Teil D ist ein Stand vom 2026-11-04 und wird schnell veralten. Die 12-Wochen-Rechnungen zeigen die rechnerischen Grenzen der Regeln, nicht das Verhalten eines Planers, den es noch nicht gibt. Die vorgeschlagenen Werte sind selbst Heuristiken und nicht validiert.
