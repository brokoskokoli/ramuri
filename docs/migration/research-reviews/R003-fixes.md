# R003 Nachbesserung: Befunde vom Typ `Beleg/Text`

Bezug: [R003-phase-2-3-rules.md](R003-phase-2-3-rules.md), Stand 2026-11-04. Geändert wurden nur [phase-2-3-rules.md](../../phase-2-3-rules.md) und diese Datei. Keine Spalte `Startwert`, keine Spalte `Anforderung`, kein Rechenbeispiel und keine neue FR-, OQ- oder DEC-ID.

**Ergebnis:** Von 26 Befunden sind die 16 vom Typ `Beleg/Text` umgesetzt, 11 davon mit Abweichung vom Bericht. Die 10 vom Typ `Wert` sind auftragsgemäß nicht umgesetzt. Kein `Beleg/Text`-Befund ist als Ganzes falsch. In 8 davon ist ein Teil falsch oder nicht belegbar und deshalb nicht übernommen: M1, M3, M8, M10, M11, S1, S2, S7. Blocker vom Typ `Beleg/Text` gibt es nicht; der Auftrag nennt sie, der Bericht führt keinen.

## Typ `Beleg/Text`

| Befund | Status | Prüfung an der Quelle | Abweichung vom Bericht und Grund |
|---|---|---|---|
| M1 | umgesetzt, Abweichung | [N21], [N22], [N18], [N23], Abstracts im Rohtext; [N23] auch Volltext | Satz des Berichts, [N23] stütze keine Regel „höher ist besser“, **nicht übernommen**: Die Reaktion der LnRMSSD auf Überlastung korrelierte mit der Änderung der 3000-m-Zeit mit r = −0,50, höher ging also mit schneller einher. Im Dokument steht die Zahl ohne diesen Schluss. |
| M3 | umgesetzt, Abweichung | [N5] über WebFetch; [L9] Tabelle 2 im Rohtext; [N4] Abstract | „weil [N4] … höhere Anteile zeigen“ **nicht übernommen**: Das Abstract nennt keinen Wochenumfang der Studienphase; mit den rund 6 h vorab wären 32 min rund 9 %. Auch falsch: [L9] sei „nicht zwingend Einheitsmenge“. Die 3 km hart liegen laut Tabelle 2 in einer Einheit von 6 km. |
| M6 | umgesetzt | [N12] über WebFetch, [N14] Abstract | Keine. `Heuristik, Evidenz niedrig`. |
| M7 | umgesetzt, Abweichung | Zeilen und Definition im Dokument, OQ-0057 | PAR-109 wird `Heuristik, Anker abgeleitet` statt `Heuristik`, weil die Obergrenze `r` 0,70 aus OQ-0057 folgt. Die vom Bericht geforderte Durchsicht ergab PAR-115, PAR-119, PAR-122, PAR-155 und PAR-161 zusätzlich. PAR-103 nennt keine eigene Wahl und bleibt. |
| M8 | umgesetzt, Abweichung | [N1] und Plan-Seite im Rohtext; Liste ausgenommener Inhalte; [N28]; c25k.com; Wikipedia | Punkte stehen in der **Begründung** von PAR-142, damit die Spalte `Startwert` unverändert bleibt. „Dem Plan von Josh Clark gleichen“ abgeschwächt: Verglichen ist nur c25k.com, das keinen Autor nennt, und Woche 3 endet dort mit einer weiteren Gehphase. Herkunft zitiert [N28] statt nur Wikipedia, dort steht der Satz ohne Einzelnachweis. Ergänzt: 3.10, und dass die Liste ausgenommener Inhalte Couch to 5K nicht nennt. |
| M9 | umgesetzt, Abweichung | [N28] Volltext im Rohtext | „19 % Verletzungen“ präzisiert: 19 % sind in der Arbeit 0,19 Verletzungen je Läufer, also 21/110. Betroffen waren 20 Läufer, das wären 18,2 %. 27,3 % gegen 64,5 % bleibt ungelöst und ist so vermerkt. |
| M10 | umgesetzt, Abweichung | Eigene Rechnung, Skript unten | „Nur näherungsweise wiederholbar“ ist **widerlegt**: Das Skript vom 2026-11-03 (`sim2.py` im Scratchpad, Seed 1) ergibt 63,6 und 33,5, also genau die Spannen des Dokuments. Dem Bericht fehlten zwei nicht dokumentierte Annahmen: Schlaf am gemeinsamen Faktor gekoppelt, Band am ungerundeten Wert. Die Zahlen bleiben, die Annahmen stehen jetzt in R8. Eine Kennzeichnung als nicht reproduzierbar ist damit nicht nötig. Herkunft des Skripts ist nur durch Datum und übereinstimmende Zahlen belegt. Auch falsch: Die Bänder verschieben sich bei 14 Referenzwerten nicht um 1–3, sondern um bis zu 4,7 Punkte. Fälle mit fehlenden Faktoren stammen aus demselben Modell, deshalb etwas andere Spannen als im Bericht (HRV und Schlaf: Erholung bis 4,0 statt 2,5 %). |
| M11 | umgesetzt, Abweichung | Eigene Rechnung, Skript unten | Tabelle und alle Höchstwerte bestätigt. „Unter rund 6,33 h unerreichbar“ gilt nur ohne Effizienz, mit `E` ab 95 % liegt die Grenze bei 6,07 h. Häufigkeit bei 8 h 13,8 statt rund 12 %. Eine Entscheidung habe ich nicht protokolliert, weil sie dem Maintainer zusteht: PAR-168 und PAR-161 stehen unter `Entscheidungsbedarf`. |
| S1 | umgesetzt, Abweichung | [N29] Abstract im Rohtext | ACSM-Teil **nicht umgesetzt**: Die Tabelle war erneut nur hinter reCAPTCHA, und der Bericht macht die Erwähnung von dieser Prüfung abhängig. Gleiche Anker in der App sind Produktverhalten, siehe unten. |
| S2 | umgesetzt, Abweichung | Nachgerechnet | 0,82 bestätigt. Die Spanne im Bericht ist an einer Stelle **falsch**: 90 % bei HFRuhe 75 ergibt 96/115 = 0,8348, also 0,83 und nicht 0,84. |
| S3 | umgesetzt | Formel über WebFetch, nachgerechnet | Alle Zahlen bestätigt. Ergänzt: Das 10-km-Tempo liegt bei schnellen Läufern mit bis 92 % VDOT über T. |
| S6 | umgesetzt | Fitbit-Seite über WebFetch | Keine. Die Angabe „Ende am 30.10.2026“ stammt von der Seite; ob die API tatsächlich aus ist, wurde nicht geprüft. |
| S7 | umgesetzt, Abweichung | Rohtext [Q27], [N23]; PMC-ID-Abfrage | [Q27] und [N23] gelesen, PMC-Kennungen bestätigt und vermerkt. [N10], [N17], [N24], [N25], [L28] bleiben Abstract. **[N21] nicht gelesen:** Der JYX-Datensatz lädt, die PDF läuft in Zeitüberschreitung. Der Bericht verweist für das Zitat zum 7-Tage-Mittel auf den JYX-Datensatz 50625; es steht aber in der Masterarbeit, Datensatz 45036. Diese ist als [N34] getrennt zitiert. |
| S8 | umgesetzt, Abweichung | FR-0163, FR-0165, OQ-0058 | Verweise berichtigt. Vorgabe „wegen kurzer Schlafdauer“ **nicht umgesetzt**, weil das den Startwert von PAR-172 ändert. Siehe unten. |
| S10 | umgesetzt | Nachgerechnet | 44,7, 37,0, 6:01 und 4:38 bestätigt. |
| S11 | umgesetzt | [N20], [N17], [N14] Abstracts im Rohtext | [N14] geht über Eliteathleten hinaus, deshalb „zu Athleten, vor allem Eliteathleten“. |

Bestätigt und übernommen sind außerdem alle Zahlen aus [N19]: 0,20 ± 0,28, 0,49 ± 0,33, −0,02 ± 0,23, −0,25 ± 0,22, 90 % CL. Sie stehen in PAR-161, die Regel selbst bleibt unverändert.

## Typ `Wert`: nicht umgesetzt

Diese Befunde bleiben unberührt, darüber entscheidet der Maintainer: **B1, B2, B3, M2, M4, M5, M12, S4, S5, S9.** Nicht geprüft habe ich ihre Rechnungen und Simulationen. Berührt haben sie die Arbeit nur an zwei Stellen: Die Zahlen aus [N19] und der Hinweis auf den Median in PAR-160 stehen als Beleg im Text, ohne dass sich eine Regel ändert. Eine Beobachtung zu B2: Das Zitat aus [N21] zum 7-Tage-Mittel in B2 stammt aus der Masterarbeit [N34], siehe S7.

## Wertentscheidungen aus `Beleg/Text`-Befunden

Diese Punkte brauchen doch eine Entscheidung. Die Werte bleiben bis dahin unverändert.

| Punkt | Aus | Frage |
|---|---|---|
| PAR-163 | M1 | Eine hohe HRV wird bis `S` = 90 aufgewertet, obwohl [N21] auch dann locker plant und [N18] die Abweichung nach oben nicht als günstig stützt. [N23] weist eher in die andere Richtung. Steigung und Kappung bleiben Annahme. |
| PAR-118 | M3 | Eine Einheit darf bis zum Wochenanteil von 15–20 % wachsen, das 2- bis 2,5-Fache der Grenze aus [N5]. |
| PAR-172 | S8 | Soll der Text bei reinem Schlafmangel „wegen kurzer Schlafdauer“ nennen? |
| PAR-105, FR-0038 | S1 | Soll die App die Anker der Borg-Skala CR-10 zeigen? Sonst gilt [N29] nur näherungsweise. |
| PAR-168, PAR-170 | M11 | „Gut erholt“ trotz PAR-072 und der Sprung an Tag 127. Steht unter `Entscheidungsbedarf`. |
| PAR-161 | M11 | Einzelwert gegen Mehrtagesmittel, zusammen mit B2 zu entscheiden. |

## Offen außerhalb dieser Datei

- **Version:** Das Dokument verlangt für Änderungen eine neue Version (NFR-0001), freigegeben ist Version 1 (OQ-0057). Da die Startwerte gleich blieben und die Freigabe beim Maintainer liegt, steht dort weiter Version 1 mit einem eigenen Stand für Begründungen und Quellen.
- **Konflikte ohne `Entschieden`:** Auch PAR-100, PAR-116, PAR-123 und PAR-141 tragen einen **Konflikt** ohne diese Marke. Der Bericht nennt sie nicht, sie sind mit Version 1 freigegeben und deshalb nicht unter `Entscheidungsbedarf` aufgeführt.
- **PAR-065** in [planning-rules.md](../../planning-rules.md) sagt weiter „eine prüfende Studie wurde nicht gefunden“ und „NHS-Struktur“.
- `spec_tool.py build` wurde auftragsgemäß nicht ausgeführt.

## Skript zu R8 und zur Erreichbarkeit

Python-Standardbibliothek, gelaufen mit Python 3.15.0: `python3 -I r8.py`. `part1` ist seedgleich zur Rechnung vom 2026-11-03 und ergibt für alle Faktoren dieselben Zahlen.

```python
"""R8: Sensitivitaetsrechnung Readiness. Nur Standardbibliothek."""
import math, random, statistics

def c(x, a=0, b=100): return max(a, min(b, x))
def P(z): return c(60 + 25 * z) if z < 0 else min(60 + 20 * z, 90)                # PAR-163
def D(h): return 80 if h >= 8 else (70 + 10 * (h - 7) if h >= 7 else c(70 - 25 * (7 - h)))  # PAR-165
def L(t): return min(60, c(60 + 2 * (t + 10)))                                    # PAR-168
MOOD = {1: 10, 2: 35, 3: 60, 4: 75, 5: 90}                                        # PAR-169
P_MOOD = [.03, .12, .5, .25, .1]
def value(sc, keys):
    w = {"hrv": 25, "rhr": 20, "sleep": 30, "load": 15, "mood": 10}               # FR-0110
    return sum(w[k] * sc[k] for k in keys) / sum(w[k] for k in keys)              # PAR-170
def band(v): return 0 if v >= 75 else 1 if v >= 50 else 2 if v >= 25 else 3       # OQ-0029
SETS = {"alle": ("hrv", "rhr", "sleep", "load", "mood"), "ohne Belastung": ("hrv", "rhr", "sleep", "mood"),
        "HRV, Ruhepuls, Schlaf": ("hrv", "rhr", "sleep"), "HRV, Schlaf": ("hrv", "sleep")}
N = 200_000

def part1():
    random.seed(1)
    for rho in (0, .5):
        for hm, hs, tm in ((7.2, .8, -12), (6.5, 1, -20)):
            cnt = {k: [0] * 4 for k in SETS}; rounded = [0] * 4
            for _ in range(N):
                g = random.gauss(0, 1)
                zh = rho ** .5 * g + (1 - rho) ** .5 * random.gauss(0, 1)
                zr = rho ** .5 * g + (1 - rho) ** .5 * random.gauss(0, 1)
                h = random.gauss(hm, hs) + .5 * rho * g     # Schlaf am gemeinsamen Faktor gekoppelt
                t = random.gauss(tm, 10)
                fe = random.choices([1, 2, 3, 4, 5], P_MOOD)[0]
                sc = {"hrv": P(zh), "rhr": P(zr), "sleep": D(h), "load": L(t), "mood": MOOD[fe]}
                for k, keys in SETS.items():
                    cnt[k][band(value(sc, keys))] += 1
                rounded[band(math.floor(value(sc, SETS["alle"]) + .5))] += 1
            for k, v in cnt.items():
                print(rho, hm, k, [round(100 * x / N, 1) for x in v])
            print(rho, hm, "alle, gerundet", [round(100 * x / N, 1) for x in rounded])

def part2():  # feste Schlafdauer, TSB% -5, Korrelation 0,5, alle Faktoren
    random.seed(1); rho = .5
    for h in (6, 7, 8):
        cnt = [0] * 4; rounded = [0] * 4
        for _ in range(N):
            g = random.gauss(0, 1)
            zh = rho ** .5 * g + (1 - rho) ** .5 * random.gauss(0, 1)
            zr = rho ** .5 * g + (1 - rho) ** .5 * random.gauss(0, 1)
            fe = random.choices([1, 2, 3, 4, 5], P_MOOD)[0]
            sc = {"hrv": P(zh), "rhr": P(zr), "sleep": D(h), "load": L(-5), "mood": MOOD[fe]}
            v = value(sc, SETS["alle"])
            cnt[band(v)] += 1; rounded[band(math.floor(v + .5))] += 1
        print("Schlaf fest", h, [round(100 * x / N, 1) for x in cnt], "gerundet", [round(100 * x / N, 1) for x in rounded])

def z_ref(rng, m):  # z nach FR-0113 aus m Referenzwerten
    x = [rng.gauss(0, 1) for _ in range(m)]
    med = statistics.median(x); mad = statistics.median(abs(a - med) for a in x)
    return (rng.gauss(0, 1) - med) / (1.4826 * mad)

def part3():  # Breite von z und Wirkung auf die Baender, alle Faktoren, z unabhaengig
    for m in (14, 28):
        rng = random.Random(1); z = [z_ref(rng, m) for _ in range(N)]
        print("Referenz", m, "SD", round(statistics.pstdev(z), 2), "P(z<-2)", round(100 * sum(a < -2 for a in z) / N, 1))
    for hm, hs, tm in ((7.2, .8, -12), (6.5, 1, -20)):
        for m in (None, 14, 28):
            rng = random.Random(1); cnt = [0] * 4; n = 50_000
            for _ in range(n):
                zh, zr = (rng.gauss(0, 1), rng.gauss(0, 1)) if m is None else (z_ref(rng, m), z_ref(rng, m))
                sc = {"hrv": P(zh), "rhr": P(zr), "sleep": D(rng.gauss(hm, hs)), "load": L(rng.gauss(tm, 10)),
                      "mood": MOOD[rng.choices([1, 2, 3, 4, 5], P_MOOD)[0]]}
                cnt[band(value(sc, SETS["alle"]))] += 1
            print("Baender", hm, "Referenz", m, [round(100 * x / n, 1) for x in cnt])

if __name__ == "__main__":
    part1(); part2(); part3()
```

Ausgabe in %, Reihenfolge gut, normal, erhöht, Erholung. Fall: Korrelation, mittlere Schlafdauer, Faktoren.

```text
0 7.2 alle [2.0, 86.0, 12.1, 0.0]
0 7.2 ohne Belastung [6.8, 81.8, 11.3, 0.0]
0 7.2 HRV, Ruhepuls, Schlaf [9.2, 77.1, 13.7, 0.1]
0 7.2 HRV, Schlaf [16.4, 69.5, 13.8, 0.3]
0 7.2 alle, gerundet [2.4, 86.5, 11.0, 0.0]
0 6.5 alle [0.5, 67.5, 31.7, 0.2]
0 6.5 ohne Belastung [3.5, 70.8, 25.3, 0.3]
0 6.5 HRV, Ruhepuls, Schlaf [4.9, 65.7, 28.6, 0.8]
0 6.5 HRV, Schlaf [8.6, 58.5, 30.4, 2.6]
0 6.5 alle, gerundet [0.7, 69.1, 30.1, 0.2]
0.5 7.2 alle [5.3, 77.5, 17.2, 0.1]
0.5 7.2 ohne Belastung [13.0, 70.2, 16.6, 0.3]
0.5 7.2 HRV, Ruhepuls, Schlaf [16.2, 64.4, 18.7, 0.7]
0.5 7.2 HRV, Schlaf [19.1, 64.5, 15.8, 0.6]
0.5 7.2 alle, gerundet [6.1, 77.7, 16.1, 0.1]
0.5 6.5 alle [1.8, 63.6, 33.5, 1.0]
0.5 6.5 ohne Belastung [7.7, 63.0, 27.9, 1.4]
0.5 6.5 HRV, Ruhepuls, Schlaf [10.0, 57.6, 29.7, 2.8]
0.5 6.5 HRV, Schlaf [10.8, 55.1, 30.1, 4.0]
0.5 6.5 alle, gerundet [2.2, 64.7, 32.1, 0.9]
Schlaf fest 6 [0.0, 71.5, 28.5, 0.0] gerundet [0.0, 73.2, 26.8, 0.0]
Schlaf fest 7 [4.8, 86.0, 9.2, 0.0] gerundet [5.7, 85.9, 8.4, 0.0]
Schlaf fest 8 [12.1, 82.9, 5.0, 0.0] gerundet [13.8, 81.7, 4.5, 0.0]
Referenz 14 SD 1.32 P(z<-2) 5.8
Referenz 28 SD 1.14 P(z<-2) 3.9
Baender 7.2 Referenz None [1.9, 86.3, 11.8, 0.0]
Baender 7.2 Referenz 14 [2.9, 81.6, 15.5, 0.0]
Baender 7.2 Referenz 28 [2.4, 83.7, 13.9, 0.0]
Baender 6.5 Referenz None [0.5, 67.7, 31.5, 0.2]
Baender 6.5 Referenz 14 [0.8, 64.6, 34.1, 0.5]
Baender 6.5 Referenz 28 [0.7, 65.7, 33.3, 0.4]
```
