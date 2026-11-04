# R004 Review Runde 1 (Re-Review von R001 bis R003) – NACHBESSERN

Commit: keiner (kein Worktree, kein Commit, Stand der Dateien 2026-11-04)

**Webtools:** WebFetch und WebSearch waren verfügbar und funktionierten (je ein echter Abruf). Tragende Zahlen wurden zusätzlich am Rohtext geprüft (`curl` auf NCBI E-Utilities, BioC-Volltext, Originalseiten).

**Urteil in einem Satz:** Die Rechnungen und die neuen Quellen tragen fast vollständig. Eine Übergabe ist aber noch nicht möglich, weil zwei Regeln den Nutzer stärker belasten als beabsichtigt und mehrere Einstufungen nicht eindeutig umsetzbar sind. Keine Entscheidung des Maintainers muss zurückgenommen werden; einige brauchen eine Präzisierung.

| Schwere | Gesamt | Typ `Wert` | Typ `Beleg/Text` |
|---|---:|---:|---:|
| Blocker | 2 | 2 | 0 |
| Muss | 10 | 7 | 3 |
| Soll | 9 | 3 | 6 |
| **Summe** | **21** | **12** | **9** |

**Alte Blocker:** 5 geprüft, 4 behoben, 1 teilweise (R002 B2, siehe B2 unten). **Alte Muss-Befunde:** 36 geprüft, 33 behoben, 3 teilweise oder mit Rest (R001 M4, R002 M5, R003 M7); R003 M2 ist behoben, sein zweiter Teil gegenstandslos.

**Geprüfter Umfang:**
- Vollständig: alle alten Blocker und Muss-Befunde, Längentabelle, R1 bis R8, 12-Wochen-Beispiele, Pace-Beispiele, Rechenbeispiele der Readiness, Entscheidungen OQ-0047, OQ-0057 bis OQ-0059, DEC-0057.
- Volltext oder Rohtext: Dugas 2023, Relph 2023, ProjectRun21-Design, Gabbett 2016 (gezielt), Pobiruchin 2017 (gezielt), NHS-Plan, Google `/health/app-verification`, [N5], [N33].
- Abstract im Rohtext: Nes 2013, Damsted 2019, ProjectRun21, Kluitenberg 2016, Silva Oliveira 2024, Hall 2004, Swain und Leutholtz 1997, Gordon 2016, Dantas 2015, Witte und Wilson 2004.
- Über WebFetch: Android-Autorisierung [L79].
- Abgleich Specs: training-plan, plan-adaptation, readiness, goals, performance-prediction vollständig; heart-rate-zones, vo2max, training-load, run-recording, health-import an den betroffenen FR.
- Stichprobe: übrige PAR-Zeilen, sofern kein alter Befund und keine neue Rechnung sie berührt.
- `spec_tool.py check`: PASS. `build` nicht ausgeführt.

## Befunde

### Blocker

**B1. PAR-052, PAR-071, FR-0148: Das Regelziel hat kein Ende. Typ `Wert`. Neu durch die Korrektur.**
- **Problem:** Das Regelziel gilt nun in allen Stufen, offene Ziele und 5 km mit +10 % je Zyklus. FR-0148 verlangt: „bleibt die Steigerung je Zyklus beim Regelziel“. Keine Regel sagt, wann der Umfang aufhört zu steigen. Pflicht bei der Planerstellung sind nur die Trainingstage (OQ-0010), die maximale Zeit je Einheit ist optional.
- **Rechnung:** Offenes Ziel ab 90 min: nach 1 Jahr ×3,45 (311 min, langer Lauf 124 min), nach 2 Jahren ×11,9 (1.073 min, langer Lauf 429 min). Ziel 5 km, Aufbau ab 3 × 30: längste Einheit nach 8 Wochen 44, nach 24 Wochen 64 min, bei einer Zielspitze von 30 min.
- **Warum es trägt:** Das trifft ausgerechnet Ziele wie „Regelmäßig dreimal pro Woche laufen“ (FR-0135). PAR-071 setzt mit „gleichbleibender Belastung“ ein Plateau voraus, das nach den Regeln nie entsteht. Die zitierte Quelle [L20] beruht auf konstant 3 × 45 min. Ein Implementierungsagent müsste das Ende erfinden; AGENTS.md verbietet das.
- **Korrektur, vorsichtigste Lösung:** Regelziel als Obergrenze lesen, nicht als Pflichtzuwachs. Ist die Zielspitze erreicht, bleibt der Umfang gleich. Für offene Ziele endet die Steigerung nach einer festen Zahl von Zyklen (Vorschlag: 3, rund +33 %, eigene Wahl) oder beim Wochenumfang, den der Nutzer bestätigt; danach greift der Vorschlag aus PAR-071. Dabei auch festlegen, ob der Plan beim Halbmarathon auf 90 oder 120 min zielt; bisher ist nur „geprüft wird die Untergrenze“ geregelt. Die Längen ändern sich nicht.
- **Beleg:** `planning-rules.md:57`, `:101`, `:141`; `specs/training-plan.md:146`; `specs/goals.md` FR-0135; OQ-0010.

**B2. PAR-051: Die Formel für „6 Monate“ lässt Einsteiger nach 9 Wochen aufsteigen. Typ `Wert`. Rest von R002 B2.**
- **Problem:** „im Mittel mindestens 1 Lauf je Woche über die letzten 26 Wochen“ ist kein Maß für die Dauer. Wer vor 9 Wochen mit 3 Läufen je Woche begann, hat 27 Läufe in 26 Wochen, also 1,04 je Woche, und erfüllt auch „8 von 12 Wochen mit mindestens 2 Läufen“. Bei 4 Läufen je Woche reichen 7 Wochen. Genau das schließt die Abfolge aus PAR-065 ab.
- **Warum es trägt:** Dieselbe Zeile und PAR-081, PAR-085, PAR-117 behaupten „mindestens 26 Wochen“. OQ-0059 verlangt „6 Monate regelmäßiges Laufen“, [L9] schloss nur solche Läufer ein. Wörtlich umgesetzt gelten ab Woche 10 die Grenzen von „Aufbau“, in Woche 17 endet die Frist aus PAR-054. Die Hürde von 160 min bremst die Intensität, den Rest nicht.
- **Korrektur:** Bedingung ergänzen: „Der erste erfasste Lauf oder die Selbstauskunft liegt mindestens 26 Wochen zurück, und in mindestens 20 dieser Wochen liegt mindestens 1 Lauf.“ Die 20 sind eigene Wahl und lassen Urlaub zu. Die Absicht des Dokuments ändert sich nicht.
- **Beleg:** `planning-rules.md:56`; Rechnung 3 · 9 / 26 = 1,04.

### Muss

**M1. PAR-084, FR-0154: Gleichstand und Reihenfolge der Einstufung. Typ `Wert`. Punkte a) und b).**
- **Problem:** Einsteiger, Halbmarathon 27 und 35 Wochen sowie 5 km erfüllen „realistisch“ und „ambitioniert“ zugleich. Mit Regelziel gelten Einsteiger früher als Aufbau (10 km ab 19 gegen 20, Halbmarathon ab 27 gegen 28), allein wegen der kürzeren Reduktion; ihre Zielspitze kommt in derselben Woche (18, 26, 34).
- **Korrektur, vorsichtigste Lösung:** Eine Regel löst beides: **„Realistisch“ verlangt bei „Einsteiger“ eine Woche Reserve, die Spitzenwoche wird dann einmal gehalten.** Damit gilt für alle Stufen dieselbe Spalte: 10 km ab 20, Halbmarathon ab 28 und 36, ab Einstieg 29, 37 und 45. Die entschiedenen kürzesten Längen 15 und 27 bleiben und heißen „ambitioniert“. PAR-070 bleibt unverändert, weil die Reduktion selbst weiter 1 Woche dauert. Der Vorrang der schlechteren Stufe steht bei Zeitzielen schon in PAR-084. 5 km siehe M2.
- **Beleg:** `planning-rules.md:141`, Tabelle `:146–158`, Abschnitt `Entscheidungsbedarf`; `specs/training-plan.md:224`; eigene Rechnung unten.

**M2. PAR-068: Längen ohne Rechnung ergeben eine nicht monotone Einstufung. Typ `Wert`. Punkt c).**
- **Problem:** Nach PAR-084 ist ein 5-km-Plan ab 3 × 30 bei jeder Länge ab 1 Woche mit Regelziel erreichbar. Daraus folgt: 7 Wochen „realistisch“, 8 Wochen „ambitioniert“ (FR-0154), 9 Wochen „realistisch“. Der Text „Kürzere Pläne erreichen die Zielspitze nicht“ ist hier falsch. Bei „Erfahren“ und Halbmarathon ab 3 × 50: nach Rechnung 9 Wochen, genannt 12, mit Regelziel 13; 9 bis 11 Wochen fallen in keine Stufe.
- **Einschätzung:** OQ-0059 zählt nur die Längen für 10 km und Halbmarathon ab 30 min auf und setzt „Regellängen heißen kürzeste Längen“. Die 8, 8 und 12 Wochen sind also alte Regellängen ohne Rechengrundlage.
- **Korrektur, vorsichtigste Lösung:** Sie als **Konvention für die Vorbereitung** kennzeichnen, nicht als rechnerische Grenze, und die Einstufung monoton festlegen: Zielspitze im Start und Länge bis einschließlich 8 Wochen „ambitioniert“, darüber „realistisch“, nie „eher unrealistisch“ allein wegen der Länge. Halbmarathon ab sicher 10 km: 12 Wochen für beide Stufen behalten, darunter „eher unrealistisch“; die 9 Wochen stehen nur als Rechnung. „Sicher 10 km“ als „3 × 50 min, längste Einheit 60 min“ definieren, bisher steht das nur in der Rechnung. Ab Einstieg: unter 10 Wochen „eher unrealistisch“, weil die Abfolge nicht fertig wird.
- **Beleg:** `planning-rules.md:98`, `:141`, `:148–149`, `Entscheidungsbedarf`.

**M3. PAR-054, PAR-069, PAR-084, PAR-130: Die Längen enthalten keine Intensität, und die Phasen laufen leer. Typ `Wert`.**
- **Problem:** Die Hürde von 160 min ist entschieden und wird nicht aufgerollt. Ihre Folge ist aber nur für 3 × 40 genannt. Bei „Aufbau“ ab 3 × 30:

  | Ziel | 160 min mit Regelziel in Woche | Erste intensive Phase ab Woche | Plan mit Regelziel |
  |---|---:|---:|---|
  | 5 km | 26 | 29 | 8 bis 28 Wochen: keine intensive Einheit |
  | 10 km | 18 | 21 | 20 Wochen: keine intensive Einheit |
  | Halbmarathon | 18 | 21 | 28 Wochen: keine; mit einem Zyklus 32 Wochen |

- **Warum es trägt:** PAR-130 verlangt in der Phase „Spezifisch“ für 5 km „vor allem Intervalle“; PAR-083 stuft Zeitziele nach Fortschrittsraten ein, die zum Teil aus Studien mit harter Arbeit stammen [L12, L13]. Ein Nutzer mit dem Ziel „5 km unter 25 min“ kann „realistisch“ lesen und nur lockere Läufe erhalten. Keine Regel sagt, ob bei knappem Datum der Umfang oder die Intensität Vorrang hat.
- **Korrektur:** Rangfolge festlegen (vorsichtig: Umfang vor Intensität, also die Tabelle wörtlich) und die Folge in PAR-054, PAR-083, PAR-130 nennen. PAR-069 und PAR-130 ergänzen: Passt die Einheit nicht ins Budget, bleibt die Phase locker und die App sagt das. Bei Zeitzielen, die im Plan keine Intensität enthalten, höchstens „ambitioniert“. Die Hürde selbst bleibt.
- **Beleg:** `planning-rules.md:59`, `:99`, `:140`; `phase-2-3-rules.md:112`, `:118`; eigene Rechnung.

**M4. PAR-054, PAR-118, PAR-125: Entscheidung und Regeln sagen zur Hürde Verschiedenes. Typ `Wert`. Neu.**
- **Problem:** OQ-0059: „unter 160 min Umfang gibt es keine intensive Einheit“, ohne Einschränkung, und so auch in PAR-054. PAR-118 und PAR-125 erlauben aber „Erfahren“ ohne Einstieg den Rückgriff auf 4 × 2 min ab 100 min, und „Aufbau“ nach der ersten Phase ebenfalls. Unklar bleibt auch eine Entlastungswoche unter 160 min während einer laufenden intensiven Phase (C2: 138 min).
- **Korrektur:** Der Maintainer klärt den Geltungsbereich. Vorsichtigste Lesart: Die Hürde gilt für den Beginn einer intensiven Phase in allen Stufen; eine Entlastungswoche unterbricht eine laufende Phase nicht (PAR-131). Fällt der Umfang sonst unter 160 min, bleibt die Einheit locker.
- **Beleg:** OQ-0059; `planning-rules.md:59`; `phase-2-3-rules.md:106`, `:113`.

**M5. `Umfang`, PAR-053, PAR-066, PAR-077: Die zwei Zählweisen treffen sich in Ist-Werten. Typ `Wert`. Punkt d).**
- **Einschätzung:** Die Rechnung ab 90 min ist in sich schlüssig; der Maintainer hat sie entschieden. Beim Übergang sinkt die Gesamtzeit von 120 auf 99 min, die Laufminuten steigen von 90 auf 99. Das Problem liegt in den Regeln, die Ist-Werte lesen:
  - **PAR-053:** Die längste Einheit der letzten 30 Tage ist 40 min (PAR-139), erlaubt wären 44. PAR-066 setzt 30.
  - **PAR-077, PAR-078:** Pause direkt nach der Abfolge: Mittel der Wochen 6 bis 9 sind 110 min Gesamtzeit, 80 % davon 88 min. Das sind 13 % mehr als die mittleren 78 Laufminuten vor der Pause, obwohl die Regel eine Senkung auf 80 % meint.
- **Korrektur, vorsichtigste Lösung:** Die Wochen der Abfolge zählen für alle Vergleichswerte nur mit Laufzeit. Ab dem Start nach der Abfolge zählt die ganze Einheit einschließlich Auf- und Abwärmen und Gehpausen (PAR-109, PAR-119), kein Gehen läuft mehr außerhalb des Umfangs. Damit gibt es ab dann nur eine Definition, und 3 × 30 bleibt.
- **Beleg:** `planning-rules.md:21`, `:58`, `:91`, `:119`, `:120`.

**M6. PAR-105, PAR-110: RPE 5 ist nach der eigenen Skala nicht locker. Typ `Wert`. Punkt e).**
- **Problem:** Ein längerer Lauf bleibt im letzten Viertel bei RPE 5 („Gespräch schwer“) locker. Bei 90 min sind das rund 22 min, also rund 9 % von 240 min Umfang außerhalb jedes Budgets. Ein Endblock von 10 min mit RPE 5 zählt dagegen als intensiv (PAR-114, PAR-129). Für „Einsteiger“ widerspricht die Zeile PAR-061 („100 % locker“), PAR-064 (RPE höchstens 4) und dem Verbot von Endblöcken in PAR-123.
- **Korrektur, vorsichtigste Lösung:** Skala behalten, weil sie entschieden ist, und PAR-110 ändern: **Vorgabe RPE 3–4 bis zum Ende, ohne Anstieg als Ziel. Meldet der Nutzer am Ende RPE 5, gilt das nicht als Abweichung** (PAR-182 greift ohnehin erst ab 6). Wer gezielt steigern will, nutzt PAR-114. Das hält die Einheit tatsächlich locker und lässt natürlichen Anstieg zu.
- **Beleg:** `phase-2-3-rules.md:80`, `:93`, `:97`, `:111`, `:117`; `planning-rules.md:81`, `:89`.

**M7. PAR-084: Die Zielspitze in Minuten deckt langsame Läufer nicht. Typ `Wert`. Neu entdeckt.**
- **Problem:** FR-0135 nennt „Erstmals 5 km durchlaufen“. 30 min sind bei 8:00 min/km nur 3,75 km; die 5 km dauern 40 min, 10 km 80 min statt 60, der Halbmarathon rund 169 min gegen eine geprüfte Spitze von 90. PAR-031 und PAR-081 sagen selbst, dass gerade Einsteiger so langsam laufen. Dennoch lautet die Einstufung nach der Abfolge „realistisch“, ohne dass der Nutzer je die Zeit des Ziels gelaufen ist.
- **Einordnung:** Der lange Lauf muss beim Halbmarathon nicht die Wettkampfdauer erreichen. Bei einem ersten 5-km-Lauf ist die Lücke aber der Kern des Ziels.
- **Korrektur:** Liegt ein Tempo aus den Läufen vor, ist die Zielspitze für 5 km die erwartete Dauer der Strecke, für 10 km mindestens 75 % davon (eigene Wahl). Liegt keins vor, gelten die Minuten, und der Text sagt „30 min Laufen“, nicht „5 km“. Dafür verlängern sich Pläne langsamer Läufer.
- **Beleg:** `planning-rules.md:141`, `:133`; `model-parameters.md:70`; `specs/goals.md` FR-0135.

**M8. PAR-063: „Keine Quelle gefunden“ stimmt nicht. Typ `Beleg/Text`.**
- **Problem:** Die Lesenotiz [N5], die PAR-118 als Obergrenze „vorsichtig“ übernimmt, nennt auch eine Grenze für lange Läufe: „no more than 25-30% of the total weekly mileage for runners who run 40 miles a week or less“. PAR-063 erlaubt 40 % und ist die bindende Grenze aller Längen in PAR-084. Die Quelle wird hier also selektiv genutzt.
- **Einordnung:** Bei 3 Einheiten je Woche sind 25–30 % für die längste Einheit rechnerisch nicht möglich (mindestens 33,3 %). Der Wert ist vertretbar, muss aber offen begründet werden.
- **Korrektur:** Text: [N5] nennt 25–30 %, das ist bei 3 Tagen nicht erfüllbar; 40 % sind eigene Wahl; bei 4 oder mehr Tagen wäre eine engere Grenze möglich. Mit 30 % bräuchten 60 min 200 min Umfang statt 150. Ob das bei 4 oder mehr Tagen gilt, entscheidet der Maintainer.
- **Beleg:** `planning-rules.md:83`; https://cdbaca.github.io/ssg/reading-daniels-running-formula-chapter-4.html (Rohtext).

**M9. PAR-013, PAR-026, PAR-027: Die Wirkung der Höhengrenze ist untertrieben, und die Steigungsgrenze läuft teils leer. Typ `Beleg/Text`. Rest von R001 M4.**
- **Problem:** PAR-027 nennt „bis rund 1,5 Prozentpunkte, also rund 6 %“. Mit den eigenen 10 m Vertikalgenauigkeit greift `G` auf 840 m aber erst ab 20 m, also 2,4 Prozentpunkten, rund 10 %. Bei den in PAR-013 erlaubten 15 m sind es 3,6 Prozentpunkte. Das liegt über der Grenze +3 % aus PAR-026, die für solche 5-min-Abschnitte also nie greift: reale Steigungen bis 3 % und mehr gelten als eben. Die Stufe „gut“ bleibt möglich.
- **Einordnung:** Die Regel selbst bleibt die vorsichtigere gegen Rauschen und folgt R001. Falsch ist die genannte Größe.
- **Korrektur:** Zahlen je Genauigkeit nennen (5 m: 1,2; 10 m: 2,4; 15 m: 3,6 Punkte auf 840 m), den Leerlauf von PAR-026 benennen und im Validierungsbedarf zählen. Optional: Gilt die Grenze über 3 %, höchstens „vorläufig“.
- **Beleg:** `model-parameters.md:42`, `:65`, `:66`; Rechnung nach FR-0069.

**M10. PAR-064, PAR-070, PAR-085, PAR-103: Die Art `abgeleitet` ist falsch gekennzeichnet. Typ `Beleg/Text`. Rest von R003 M7, R002 S5.**
- **Problem:** Nach der Lesehilfe folgt ein abgeleiteter Wert aus einer Quelle oder einem benannten Rechenschritt. PAR-064 nennt selbst: „Eigene Wahl sind die 4 Wochen, die Spanne 25–30 min …, RPE höchstens 4, die Obergrenzen 3 × 25 und 3 × 30 min und der Faktor 0,8“, das sind alle Werte. PAR-070: nur 2 Wochen und 41–60 % stammen aus Quellen. PAR-085: „Die Menge ist eigene Wahl“. PAR-103: Die Formel ist abgeleitet, die `r` 0,65 und 0,80 sind nirgends begründet.
- **Korrektur:** PAR-064 `Heuristik`. PAR-070 und PAR-085 getrennt angeben wie PAR-053. PAR-103 `Heuristik, Anker abgeleitet` und die Wahl der `r` nennen. Werte bleiben.
- **Beleg:** `planning-rules.md:11`, `:89`, `:100`, `:142`; `phase-2-3-rules.md:65`.

### Soll

**S1. PAR-115, values-applied: Der NHS-Satz steht doch auf der Seite. Typ `Beleg/Text`.** `values-applied.md:43` schreibt, „stop if something doesn’t feel right“ fehle. Der Rohtext der Plan-Seite enthält: „take things at your own pace and stop if something doesn’t feel right“. Vermutlich scheiterte die Suche am typografischen Apostroph. Der erste Satz des Hinweises ist also nicht eigene Wahl. Der Wortlaut in der App bleibt richtig. https://www.nhs.uk/better-health/get-active/get-running-with-couch-to-5k/couch-to-5k-running-plan/

**S2. PAR-064, PAR-068: Der Einstieg mit „Ja“ fehlt in den Längen. Typ `Beleg/Text`.** Wer ohne Daten „kann 30 min laufen“ angibt, durchläuft erst 4 Wochen Einstieg. An den Obergrenzen sind es 10 km 19, Halbmarathon 31 Wochen, mit Regelziel 10 km 23, Halbmarathon 31, statt 15, 27, 19 und 27. Eine Zeile ergänzen.

**S3. PAR-063, PAR-084: Die Längen gelten nur für 3 Tage. Typ `Wert`.** Bei 2 Tagen und 60 % erreicht ein Einsteiger 60 min in derselben Woche 14 mit 100 statt 150 min Umfang, also mit langem Lauf bei 60 % und gleicher Einstufung. Für 1 Tag sagt PAR-063 nichts, die Abfolge dauert dort 27 Wochen (PAR-141). Vorsichtig: Bei 1 oder 2 Tagen gilt für Distanzziele höchstens „ambitioniert“, und PAR-063 nennt den Fall 1 Tag.

**S4. PAR-052: „Immer +5 min“. Typ `Wert`.** „Bei kleinem Umfang“ ist nicht definiert, und das Skript setzt die Zyklusgrenze vor die +5 min, der Wortlaut „immer“ nicht. Festlegen: unter 50 min je Woche, Zyklusgrenze gilt zuerst, sonst weicht die Regel von der Rechnung ab.

**S5. PAR-051, PAR-070: Stufenwechsel im laufenden Plan. Typ `Wert`.** 10 km ab Einstieg mit Regelziel dauert 28 Wochen, die Stufe wechselt nach 26. Wechselt damit die Reduktion auf 2 Wochen, beginnt sie in der Spitzenwoche 27, und die Zielspitze wird nicht erreicht. Vorsichtig: Reduktion und Einstufung bleiben bis Planende bei der Stufe des Planbeginns; die Sperre für Intensität aus PAR-054 gilt weiter nach Frist.

**S6. values-applied.md: Überholte Stände nicht vollständig markiert. Typ `Beleg/Text`.** Der Nachtrag rechnet noch „Aufbau Regelfall“ mit +10 % (24, 40, 52 Wochen) und nennt das nicht überholt. Abschnitt 4 und 6 führen weiter die Borg-Anker und die Erweiterung von OQ-0048, Abschnitt 7 den Punkt 9. PAR-084 verweist auf diese Datei für die Rechnung. Ergänzen, welche Abschnitte durch den Stand vom selben Tag überholt sind.

**S7. PAR-090, PAR-150, PAR-170: Dauerhafter Fall nicht genannt. Typ `Beleg/Text`.** Ohne Zusage „alles erfasst“ bleibt der Belastungsfaktor dauerhaft weg. Damit bleibt der Wert immer höchstens 74, „Gut erholt“ und die Stufe „gut“ sind nie erreichbar, und PAR-074 und PAR-075 greifen nie. Die Rechnung stimmt, die Folge fehlt in der Erklärung.

**S8. R8, PAR-173: Die Spanne endet bei AR 0,3. Typ `Beleg/Text`.** Eigene Erweiterung des Skripts, Anteil unter 50 am Tag der Einheit: AR 0: 11–33 %, AR 0,3: 15–36 %, AR 0,6: 20–39 %. Das Dokument nennt für `z` AR 0,6, für die Bänder nicht. 39 % liegen knapp unter der Neubewertungsgrenze von 40 %. Die wirkliche Autokorrelation von Nachtwerten ist unbekannt; die Spanne bis 39 % nennen.

**S9. Versionskopf. Typ `Beleg/Text`.** Siehe Punkt f).

## Einschätzung zu den bekannten offenen Punkten

| Punkt | Einschätzung | Beste, vorsichtigste Lösung |
|---|---|---|
| a) Regelziel gleich Obergrenze | Echter Widerspruch, FR-0154 ist so nicht testbar | „Ambitioniert“ bei Gleichstand; realistisch mit einer Woche Reserve (M1) |
| b) Einsteiger eine Woche kürzer | Rechenartefakt der Reduktion, kein Argument für bessere Einstufung | Dieselbe Reserve; Regelziel-Spalte in allen Stufen 20, 28, 36 (M1) |
| c) Längen ohne Rechnung | Alte Regellängen, nicht monoton | Als Konvention kennzeichnen, monotone Einstufung, 12 für Erfahren behalten (M2) |
| d) Umfang und Abfolge | Rechnung stimmt, Ist-Werte brechen die Definition | Abfolge zählt für Vergleichswerte nur mit Laufzeit, danach eine Definition (M5) |
| e) RPE 5 | Echter Widerspruch, auch zu Regeln für Einsteiger | Vorgabe RPE 3–4, gemeldete 5 am Ende nicht als Abweichung (M6) |
| f) Version | Version 2 bleibt vertretbar | Siehe unten |

**Zu f):** NFR-0001 verlangt nur, dass jeder berechnete Fitnesswert Methode und Berechnungsversion nennt. Es gibt noch keinen Code und keinen berechneten Wert, und DEC-0057 sowie OQ-0059 benennen die Ergänzungen ausdrücklich unter Version 2. Eine Version 3 trennte also nichts, was je gerechnet wurde. Der Kopf „Änderungen erhalten eine neue Version“ ist strenger als NFR-0001 und bei gleichem Datum nicht mehr prüfbar. **Empfehlung:** Auch die Korrekturen aus diesem Bericht in Version 2 aufnehmen, dann Version 2 vor der Übergabe einfrieren, im Kopf „abschließend, frühere Stände vom selben Tag ungültig“ vermerken und ab der Übergabe jede Wertänderung als neue Version führen. Der Stand ist dann mit Datum und Prüfsumme oder Commit zu kennzeichnen.

## Stand der alten Befunde

| Befund | Stand | Prüfung am aktuellen Text |
|---|---|---|
| **R002 B1** PAR-052 | Behoben | +25 % bei −20 %, +43 % bei −30 %; Begründung korrekt |
| **R002 B2** PAR-051, PAR-054, PAR-062 | **Teilweise** | Frist, 5 % und 160 min stehen; die 6-Monats-Bedingung greift nicht (B2) |
| **R003 B1** PAR-173 | Behoben | Zeitbezug, Folgewoche, Hauptgröße; R8 nachgerechnet |
| **R003 B2** PAR-161, PAR-162 | Behoben | 7-Nächte-Mittel, MAD/√k; Testfall z = 0,67 stimmt; Schwäche bei AR offen genannt |
| **R003 B3** PAR-190 | Behoben | Einseitig, alle Paces nachgerechnet |
| R001 M1 | Behoben | 29,2; 32,2; 35,0; 40,4; 44,7 stimmen |
| R001 M2 | Behoben | Dugas und Hall am Text bestätigt |
| R001 M3 | Behoben | `Heuristik`, Einschränkung genannt |
| R001 M4 | **Teilweise** | Regel eingetragen, Größe untertrieben (M9) |
| R001 M5, M6 | Behoben | Art geändert |
| R001 M7 | Behoben | Trendabzug; FR-0077 angepasst |
| R001 M8 | Behoben | Vorrang PAR-041, Fenster „letzte“ |
| R001 M9 | Behoben | `n` = 2, FR-0078 erfüllt |
| R001 M10 | Behoben | Tempowechsel und Teilung eindeutig |
| R002 M1 | Behoben | −20, −37, −26, −47 stimmen; nur rollend |
| R002 M2 | Behoben | +3 min, Bindung je Woche; 108,6 %, 35:00 gegen 34:39 stimmen |
| R002 M3 | Behoben | Stufen 50 und 80 % |
| R002 M4 | Behoben | „In einem Zyklus steigt nur eines“ |
| R002 M5 | **Behoben mit Rest** | Längen neu und richtig gerechnet; Einstufung offen (M1, M2) |
| R002 M6, M7, M8 | Behoben | Evidenz beidseitig, „rund 48 h“ gestrichen, `Heuristik` |
| R002 M9 | Behoben | Relph; PAR-056 festgelegt; Wiederholung aktiv nach Auslösern |
| R002 M10, M11 | Behoben | r = 0,84; Lücke genannt, Ende von PAR-090 festgelegt |
| R002 M12 | Behoben | Kosten, Dauer, Pflicht im Rohtext bestätigt |
| R002 M13, M14 | Behoben | Text wie gefordert; Anbieterseiten nicht erneut abgerufen, Funktion zurückgestellt |
| R003 M1 | Behoben | Wiedergabe von [N21], [N22], [N18], [N23] berichtigt |
| R003 M2 | Behoben, Rest gegenstandslos | Riegel-60-min nachgerechnet; Blöcke über 5 min entfallen |
| R003 M3, M4, M5, M6 | Behoben | Obergrenzen, Rückfallregel, Hauptschlafphase, Grad |
| R003 M7 | **Behoben mit Rest** | Tabelle umgesetzt, PAR-103 fehlt (M10) |
| R003 M8, M9 | Behoben | Prüfpunkte, Relph; Zahlen am Volltext bestätigt |
| R003 M10 | Behoben | Skript läuft und reproduziert R8 |
| R003 M11 | Behoben | Tabelle, 82,5, 86,5, 86, 84,5 stimmen |
| R003 M12 | Behoben | Gehpausen, Regel in PAR-107 |

## Geprüft ohne Befund

- **Entscheidungen im Text:** OQ-0047 in Teil D und PAR-189; OQ-0058 in PAR-117, PAR-160, PAR-173, PAR-185; OQ-0059 in PAR-052, PAR-054, PAR-065, PAR-066, PAR-068, PAR-082, PAR-103, PAR-105, PAR-118, PAR-125, PAR-128, PAR-161, PAR-170.
- **Specs gegen Regeln:** FR-0038, FR-0060, FR-0069, FR-0077, FR-0093, FR-0109, FR-0111, FR-0113, FR-0115 bis FR-0117, FR-0129, FR-0139, FR-0140, FR-0148, FR-0151, FR-0153, FR-0154, FR-0157, FR-0200 passen, außer bei den Befunden B1, M1, M2. Die Vorschläge aus `values-applied` Abschnitt 6 sind eingetragen, in FR-0038 in der neueren Fassung.
- **Kennzeichnung:** Heuristiken sind als solche erkennbar, Beobachtung wird nicht als Ursache ausgegeben, Teil D trennt offiziell und Dritte.
- **Texte:** PAR-174 bis PAR-184 bleiben mit FR-0107, FR-0118, FR-0149 vereinbar.

## Plausibilität

Eigene Skripte, Python-Standardbibliothek, nicht das Skript des Researchers: `calc/plan.py` (lokaler Scratchpad, nicht versioniert), `load.py`, `extra.py`. Keine Messergebnisse. Kern der Längenrechnung:

```python
CAP = {"E": (.10, .15), "A": (.15, .20), "F": (.20, .25)}
def sim(tier, v0, L0, c=None, weeks=120, share=.4):
    w, cc = CAP[tier]; c = cc if c is None else c
    out, longs, peak, last, n, cy = [], [L0], v0, v0, 0, 0
    while n < weeks:
        cap = peak * (1 + c)
        for i in range(3):
            x = last if (i == 0 and cy > 0) else min(max(last * (1 + w), last + 5), max(cap, last))  # PAR-052
            ref = max(longs[-4:]); lim = ref * 1.1 if ref >= 30 else max(ref * 1.1, ref + 3)         # PAR-053
            l = max(min(share * x, lim), min(ref, share * x))                                        # PAR-063
            n += 1; out.append((n, x, l)); longs.append(l); last = x
        peak = last; n += 1; out.append((n, last * .8, longs[-1] * .8)); longs.append(longs[-1] * .8); cy += 1  # PAR-057
    return out
```

| Rechnung | Dokument | Nachgerechnet | Urteil |
|---|---|---|---|
| 10 km, Regelziel (E, A, F) | 19, 20, 20 | 18+1, 18+2, 18+2 | Stimmt |
| 10 km, Obergrenze | 15, 13, 12 | 14+1, 11+2, 10+2 | Stimmt |
| HM 90, Regelziel | 27, 28, 28 | 26+1, 26+2, 26+2 | Stimmt |
| HM 90, Obergrenze | 27, 24, 20 | 26+1, 22+2, 18+2 | Stimmt |
| HM 120, Regelziel | 35, 36, 36 | 34+1, 34+2, 34+2 | Stimmt |
| HM 120, Obergrenze | 35, 29, 24 | 34+1, 27+2, 22+2 | Stimmt |
| Ab 3 × 50, HM 90 | A 12, F 9; Regelziel 13 | 10+2, 7+2; 11+2 | Stimmt |
| Sprung nach Entlastung | +25, +43 % | 1/0,8; 1/0,7 | Stimmt |
| R1 | 64, 87, 95 %; 96 %; −57, −15, −5; −23, −28, −33; −25, −30 (Tag 133), −35 | 63,7; 86,8; 95,2; 96,1; −56,9; −15,2; −5,0; −23,0; −28,2; −33,1; −24,8; −30,0; −35,0 | Stimmt |
| R2 | −21, −27, −32, −41, −57 | −21,9; −27,7; −33,2; −41,6; −57,4, mit sofortigem Sprung auf die Spitze; bis 2 Punkte Spielraum wie dort genannt | Stimmt |
| R3 | −20, −37, −26, −47 | −19,6; −36,9; −25,9; −46,8 | Stimmt |
| R4, R5 | wie Dokument | R4 vollständig, R5 als Stichprobe (85 %: 0,78) | Stimmt |
| R6 | 7:25–8:23, 6:01–6:48, 5:21–6:03 | identisch | Stimmt |
| R7 | 108,6 %; 35:00 gegen 34:39; Zeiten | Aus NHS-Rohtext und Formel | Stimmt |
| R8 | Spannen alle Faktoren 0,8–7,3; 61,8–85,8; 11,7–34,4; 0–1,3 | Eigener Lauf mit 20.000 Tagen: 0,8–7,2; 61,6–85,7; 11,8–34,5; 0–1,4. SD von `z`: 1,05, 1,31, 1,70 | Stimmt |
| Fälle A, B, C1, C2, C3 | Spitzen, TRIMP, TSB% | C1 −23,4; C2 −18,2 und ×1,495; C3 −13,4, 160 min Woche 14; B −16,8 | Stimmt |
| Pace 25:00 | 4:51–5:00; 5:15–5:27; 6:00; 3, 6, 10 % | identisch | Stimmt |
| Daniels-Gilbert | Intervalle 91–101, Tempodauerlauf 81–88 %, Vergleich 60 min und 74 % | identisch (15:00 bis 40:00). [N33] nennt für I 97–100 %: das schnelle Ende trifft das, das langsame liegt unter dem Band | Stimmt, ungefährliche Richtung |
| PAR-082 | 5 % gibt rund 6 %, 10 % gibt 12–13 % | 5,7–5,9; 12,2–12,5 | Stimmt |
| PAR-016 | 6,6 bpm, rund 5 % | 172,6 gegen 166; 51,6 auf 54,1 (4,7 %) | Stimmt |
| Readiness | 63, 76, 51, 48, 57, 41, 16, 65; 82,5; 86,5; 86; 84,5 | 63,0; 76,2; 50,5; 48,0; 57,0; 41,25; 15,5; 65,45; 82,5; 86,47; 86,0; 84,55 | Stimmt; 15,5 und 50,5 hängen an Aufrunden |

**Durchgehendes Beispiel: Einsteiger ab Abfolge bis 10 km, 3 Tage, keine Wiederholung**

| Woche | Inhalt | Gesamtzeit | Laufminuten | Längste Einheit |
|---|---|---:|---:|---:|
| 1 bis 9 | Abfolge, PAR-065 | 85,5 / 87 / 75 / 94,5 / 92 / 102 / 105 / 114 / 120 | 24 / 27 / 27 / 48 / 51 / 63 / 75 / 84 / 90 | 28,5 bis 40 (Lauf 1 bis 30) |
| 10 bis 13 | Zyklus 1, +12,5 % | 99 / 101,3 / 101,3 / 81 | gleich | 33 / 36 / 40 / 32 |
| 14 bis 17 | Zyklus 2 | 101,3 / 111,4 / 113,9 / 91,1 | gleich | 40 / 45 / 46 / 36 |
| 18 bis 21 | Zyklus 3 | 113,9 / 125,3 / 128,1 / 102,5 | gleich | 46 / 50 / 51 / 41 |
| 22 bis 25 | Zyklus 4 | 128,1 / 141 / 144,2 / 115,3 | gleich | 51 / 56 / 58 / 46 |
| 26, 27 | Zyklus 5 | 144,2 / 158,6 | gleich | 58 / 63 |
| 28 | Reduktion −30 % | rund 111 | gleich | kürzer |

**Ergebnis:** Zielspitze in Woche 27, Länge 28 wie im Dokument; an der Obergrenze Woche 23, Länge 24. Laufminuten ×6,6 in 27 Wochen. Größte Sprünge: Woche 3 auf 4 +78 %, nach jeder Entlastung +25 %. Keine Entlastung in den ersten 12 Wochen. Die TSB-Schwellen sind bis Woche 18 gesperrt, und ohne PAR-086 oder Puls greifen sie auch dann nicht. Keine intensive Einheit, kein 5-km-Test bis zum Ende der Stufe. Mit dem wörtlichen PAR-051 wäre der Nutzer schon ab Woche 9 „Aufbau“ (B2). In Woche 26 kann die Stufe wechseln und die Reduktion verschieben (S5).

## Gegenbelege

| Gesucht | Ergebnis |
|---|---|
| Belege gegen Zahlen von Dugas | Marsh, in Dugas zitiert, fand +3 %. Der Bereich +3 bis +8 % widerspricht nicht. Hall 2004: ACSM nahe am Bedarf, im Dokument genannt. Keine Korrektur oder Rücknahme bemerkt, nicht systematisch gesucht |
| Grenze für den langen Lauf | [N5] 25–30 %: Befund M8 |
| Ein Plateau oder Ende der Steigerung in den Quellen | [L9] fester Wochenumfang im Zyklus, [L20] konstant 3 × 45: spricht gegen dauerndes Wachstum (B1). Keine Studie zu dauerhafter Steigerung um 10 % je Zyklus gefunden |
| Daniels-Bänder an einer zweiten Quelle | Suche ergab uneinheitliche Sekundärquellen (E 59–74 %, T 83–88 % oder 88 %, I 95–100 % oder 97–100 %). Das Buch bleibt ungelesen, die Einschränkung steht im Dokument |
| Welche Apps RMSSD nach Health Connect schreiben | Keine belastbare Liste gefunden, auch bei gezielter Suche. Die Zahl aus OQ-0006 hängt daran, und das Dokument nennt die Lücke offen. Kein Befund, aber vor Phase 3 am Gerät zu prüfen |
| Ausreißer bei Relph | 27,3 % gegen 64,5 % stehen beide in der Arbeit, die Wiedergabe stimmt |

**An der Quelle bestätigt:**
- **Dugas 2023:** 99 Personen, 41 Frauen, 8 km/h, VO₂max 34,8–63,0, Mittel 47,4, +7,3 und +8,1 %, MAPE 11,3 und 10,8 %, +20,9 %, ±5 bpm, 70 % HRR.
- **Nes 2013:** 3320, `211 − 0,64·age`, SEE 10,8, Unterschätzung ab 30 Jahren.
- **Damsted 2019:** 261, Risikodifferenz 22,6 % (0,9–44,3), Tag 21, kein Unterschied an Tag 56 und 98.
- **ProjectRun21:** 784, 136, 15 km je Woche, 142,6, 98,5 und 114,8 min je Woche, 3 Einheiten, „Runners at all levels“.
- **Relph 2023:** 110, 64 %, 21 bei 20, 19 %, 0,19, 11 von 15, Josh Clark 1996, Gruppeneinheit plus zwei Läufe mit App, Woche 5.
- **Kluitenberg 2016, Silva Oliveira 2024, Dantas 2015, Gordon 2016, Pobiruchin 2017, Gabbett 2016:** Zahlen und Zitate stimmen.
- **Google:** „annual security assessment“, 500–4.500 USD, 2–3 und 4–6 Wochen, „Most scopes“, Stand 2026-09-25. [L79]: Android-Client mit Paketname und SHA-1, Refresh-Token auf dem Server.
- **Daniels-Bezug:** [N5] 8 %, 10 km, 10 %, 3–5 min, 15–20 min, 5:1, 59–74 %, 80–86 %, 88–92 % HFmax, 95–100 %. [N33] Formel und T 83–88 %.
- **NHS:** Gesamtzeit von Lauf 1 aller 9 Wochen und der Aufbau mehrerer Wochen im Rohtext; die übrigen Läufe stützen sich auf R003.

## Nicht geprüft

- Daniels' Running Formula und ACSM-Leitlinie im Original: nicht zugänglich, im Dokument offen genannt.
- Parak 2017 (Q42) im Volltext: Abruf über BioC scheiterte; Aussage nur aus R001 übernommen.
- Anbieterzeilen in Teil D außer Google: nicht erneut abgerufen, Funktion nach OQ-0047 zurückgestellt und Stand im Dokument datiert.
- Q1 bis Q37, L1 bis L70, N1 bis N27 außerhalb der genannten: nicht erneut abgerufen, soweit R001 bis R003 sie geprüft haben und ihr Text unverändert ist.
- Rücknahmen und Korrekturen der neuen Quellen: nicht systematisch geprüft.
- Rechtliche Fragen (OQ-0048) und Feldvalidierung: vom Auftrag ausgenommen.

Die Aussagen, die die Übergabe der Phasen 1 und 2 tragen, sind damit geprüft. Offen bleibt für Phase 3, ob gängige Quell-Apps RMSSD nach Health Connect schreiben; das lässt sich nur am Gerät klären und ist im Dokument offen genannt. Das Urteil NACHBESSERN folgt aus den Befunden, nicht aus dieser Lücke.

## Entscheidungen für den Maintainer

1. **B1:** Regelziel als Obergrenze und Ende der Steigerung: bei Zielspitze halten; offene Ziele nach 3 Zyklen oder beim bestätigten Umfang. Zielt der Halbmarathon-Plan auf 90 oder 120 min?
2. **M1, M2:** Reserve für „realistisch“ bei Einsteigern und monotone Einstufung annehmen?
3. **M3, M4:** Umfang vor Intensität? Geltungsbereich der 160 min, auch für „Erfahren“?
4. **M6:** PAR-110 auf RPE 3–4 ändern?
5. **M7:** Zielspitze bei bekanntem Tempo an die erwartete Dauer binden?
6. **M8:** 40 % auch bei 4 und mehr Tagen?
7. **f):** Korrekturen noch in Version 2, dann einfrieren?
8. **Phase 3:** Vor der Umsetzung am Gerät prüfen, welche Quell-Apps RMSSD nach Health Connect schreiben? Ohne diesen Wert gibt es nach OQ-0006 keine Readiness-Zahl.

B2, M5, M9, M10 und die Soll-Befunde kann der Researcher nach Ihrer Freigabe in einem Durchgang eintragen; B2 und M5 ändern nur die Umsetzung, nicht die Absicht der Entscheidungen. Nötig bleibt danach eine kurze Prüfung dieser Zeilen, kein vollständiges Review.
