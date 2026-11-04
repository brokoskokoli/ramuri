# R004 Nachbesserung: letzte Korrekturrunde

Bezug: [R004-final-review.md](R004-final-review.md), Entscheidungen des Maintainers vom 2026-11-04 (SRC-003, [OQ-0059](../open-questions.md#oq-0059--wertänderungen-aus-der-research-prüfung), DEC-0058). Version 2 ist damit eingefroren.

**Ergebnis:** Von 21 Befunden sind 18 vollständig umgesetzt, 3 mit Abweichung in einem Teil (M4, M7, M9). Die Punkte a bis f sind umgesetzt. Keine echte Unvereinbarkeit, keine Anforderung verliert den Status `Approved`.

## Befunde

| Befund | Stand | Umsetzung und Grund |
|---|---|---|
| B1 | Umgesetzt | PAR-052, PAR-071, PAR-084, FR-0135, FR-0137, FR-0148. Halten an der Zielspitze, offene Ziele 3 Zyklen. Statt „beim bestätigten Wochenumfang“ gilt „bis der Nutzer mehr wählt“ (Entscheidung 1). |
| B2 | Umgesetzt | PAR-051: 26 Wochen seit dem ersten Lauf, 20 davon mit mindestens 1 Lauf. |
| M1, a, b | Umgesetzt | PAR-084: Reserve von 1 Woche bei „Einsteiger“. Regelziel-Spalte in allen Stufen 20, 28, 36, ab Einstieg 29, 37, 45. PAR-070 bleibt bei der Dauer der Reduktion. |
| M2, c | Umgesetzt | PAR-068: 8 Wochen als Konvention, „sicher 10 km“ definiert, 12 Wochen Halbmarathon, 9 nur als Rechnung, ab Einstieg unter 10 Wochen „eher unrealistisch“. |
| M3 | Umgesetzt | PAR-054, PAR-069, PAR-083, PAR-084, PAR-130, FR-0141, FR-0154. Umfang vor Intensität. Für Distanzziele durch Entscheidung 3 ersetzt: keine intensive Einheit. |
| M4 | Teilweise | PAR-054, PAR-117, PAR-118, PAR-124 bis PAR-131, FR-0151. Hürde in allen Stufen. **Nicht umgesetzt:** eine intensive Einheit in einer Entlastungswoche unter 160 min. OQ-0059 sagt ohne Einschränkung „unter 160 min Umfang gibt es keine intensive Einheit“ und geht nach Punkt 4 vor. Die Phase läuft weiter, nur die Einheit dieser Woche ist locker. Dasselbe gilt in der Reduktion. |
| M5, d | Umgesetzt | `Umfang`, PAR-053, PAR-066, PAR-077, Fall A, FR-0140, FR-0167. PAR-178 bleibt bei gemessener Bewegungszeit, weil es kein Planwert ist. |
| M6, e | Umgesetzt | PAR-110. Skala unverändert, `Entscheidungsbedarf` gestrichen. |
| M7 | Teilweise | Durch Entscheidung 2 ersetzt: PAR-191, FR-0135. **Nicht umgesetzt:** 75 % für 10 km, die Entscheidung verlangt die volle Dauer. Text „30 min Laufen“ ohne Tempodaten ist übernommen. |
| M8 | Umgesetzt | PAR-063: [N5] offen genannt, 40 % auch ab 4 Tagen entschieden. |
| M9 | Teilweise | PAR-013, PAR-026, PAR-027, Validierungsbedarf. Zahlen nachgerechnet: 1,2, 2,4, 3,6 Punkte. **Nicht umgesetzt:** die im Bericht optionale Grenze „höchstens vorläufig“. Sie nähme vielen Läufen die Pace (PAR-081) und wäre eine neue Produktentscheidung; gezählt wird im Feldtest. |
| M10 | Umgesetzt | Art von PAR-064, PAR-070, PAR-085, PAR-103. Werte unverändert. |
| S1 | Umgesetzt | PAR-115. Satz am 2026-11-04 im Rohtext der NHS-Seite bestätigt. |
| S2 | Umgesetzt | PAR-064, PAR-068, Spalte in der Tabelle unter A11. |
| S3 | Umgesetzt | PAR-063, PAR-084, FR-0154. |
| S4 | Umgesetzt | PAR-052: unter 50 min, Zyklusgrenze zuerst. |
| S5 | Umgesetzt | PAR-070, PAR-084, FR-0154. |
| S6 | Umgesetzt | [values-applied.md](values-applied.md), Nachtrag. Die Datei ist ein Eintrag der Wertänderungen, kein Prüfbericht. |
| S7 | Umgesetzt | PAR-090, PAR-150, Erreichbarkeit unter PAR-170. |
| S8 | Umgesetzt | PAR-173, Validierungsbedarf. Eigener Lauf, 20.000 Tage je Fall: 12–33, 15–36, 20–39 %. |
| S9, f | Umgesetzt | Kopf der drei Dokumente, Prüfsummen unten. |
| RMSSD-Quellen | Umgesetzt | Validierungspunkt vor Phase 3 in [phase-2-3-rules.md](../../phase-2-3-rules.md), wie vom Maintainer festgelegt. |

## Gesetzte Heuristiken und Lesarten

Alle eigene Wahl, soweit nicht anders genannt, im Dokument gekennzeichnet.

| Stelle | Festlegung | Grund |
|---|---|---|
| PAR-191 | Lockeres Tempo: das langsamere aus Median von mindestens 3 lockeren Läufen in 6 Wochen und Grenze aus PAR-102; sonst schnelles Ende aus PAR-103; sonst keine Tempodaten | Vorhandene Regeln PAR-186, PAR-109, PAR-102, PAR-103; keine neue Eingabe |
| PAR-191 | „Langsam“: unter 134 m/min (7:28 min/km, PAR-030), dann linear bis 120 min bei 120 m/min (8:20 min/km, PAR-031) | Vorhandene Grenzen, kein Sprung |
| PAR-191 | Aufrunden auf ganze Minuten; neu bestimmt beim Planbeginn und je Zyklus; erreichter Umfang sinkt nicht | Für die Umsetzung nötig |
| PAR-084 | „Rechtzeitig“ heißt mit dem Regelziel und mit einer ganzen ersten Phase vor der Reduktion | „Realistisch“ hängt am Regelziel (OQ-0059) |
| PAR-052, PAR-084 | Zeitziele steigen über die Zielspitze bis mindestens 160 min Umfang | Sonst bliebe ein 5-km-Zeitziel ab 3 × 30 min immer darunter |
| PAR-084 | Zeitziel bei „Einsteiger“ höchstens „ambitioniert“ | Stufe des Planbeginns, keine intensive Einheit sicher im Plan |
| PAR-084, PAR-062 | Entscheidung 3 als „Distanzziele enthalten nie eine intensive Einheit“ gelesen | Wörtlichste und vorsichtigste Lesart |
| PAR-069 | Anteil von „Spezifisch“ verhältnisgleich verteilt: 53 und 47 %, „Erfahren“ 38 und 62 % | Keine neue Gewichtung |
| PAR-071 | 3 Zyklen zählen nur mit Zuwachs; jede Wahl des Nutzers gibt 3 weitere | Lesart von „bis der Nutzer mehr wählt“ |
| PAR-117 | Der Test setzt 160 min Umfang voraus, Distanzziele schlagen ihn nicht vor | Er zählt als intensiv, wie schon bei der Frist |
| PAR-084 | Fällt die Reservewoche auf eine Entlastungswoche, bleibt diese | PAR-056 |

Aus R004 übernommen, ebenfalls eigene Wahl des Berichts: 20 von 26 Wochen, unter 50 min, Reserve von 1 Woche, 8 Wochen als Konvention.

## Rechnung

Keine Messergebnisse. Das Skript rechnet R004 zurück, erzeugt die Tabelle unter A11 in [planning-rules.md](../../planning-rules.md) und prüft zwei Dinge: Die Einstufung ist monoton in Länge, Stufe und Tempo (5:00 bis 10:00 min/km, je Distanz- und Zeitziel). Jeder Regelplan von der Grenze zu „realistisch“ bis 40 Wochen darüber erreicht seine Zielspitze vor der Reduktion, hält die Grenzen aus PAR-052 und PAR-063 und hält danach den Umfang; beim Zeitziel liegt die erste Phase ganz vor der Reduktion. Eine Entlastungswoche ändert C2 nicht: tiefster TSB% −18,2, TRIMP ×1,495.

```python
"""R004: Laengen und Einstufung nach PAR-052, -053, -054, -057, -063, -068, -070, -071, -084, -191.
Nur Standardbibliothek. Lauf: python3 -I r004_len.py"""
import math

CAP = {"E": (.10, .15), "A": (.15, .20), "F": (.20, .25)}      # PAR-052: Woche, Zyklus
RULE = {"5": .10, "10": .125, "HM": .15, "offen": .10}         # PAR-052: Regelziel je Zyklus
EPS = 1e-9

def peak(goal, pace=None):
    """PAR-191: Zielspitze in min. pace in min/km, None = keine Tempodaten."""
    if goal == "5":  return 30 if pace is None else max(30, math.ceil(5 * pace - EPS))
    if goal == "10": return 60 if pace is None else max(60, math.ceil(10 * pace - EPS))
    if pace is None: return 90
    return min(120, max(90, math.ceil(90 + 30 * (134 - 1000 / pace) / 14 - EPS)))

def reduction(goal, tier):                                      # PAR-070, 10 Tage aufgerundet
    return 1 if goal == "5" or tier == "E" else 2

def weeks(tier, v0, l0, c=None, n=140, target=None, vol_target=0, max_up=None, hard=(), share=.4):
    """Liste (Woche, Umfang, laengste Einheit, Zyklus). Haelt, sobald target und vol_target erreicht sind (PAR-052).
    max_up: Zyklen mit Zuwachs bei offenen Zielen (PAR-071). hard: Zyklen ohne Zuwachs (PAR-054)."""
    w, cc = CAP[tier]; c = cc if c is None else c
    out, longs, last, cy, up, reached = [], [l0], v0, 0, 0, False
    while len(out) < n:
        cap = last * (1 + c); grew = False
        for i in range(3):
            frozen = reached or cy in hard or (max_up is not None and up >= max_up)
            x = last if (frozen or (i == 0 and cy > 0)) else min(max(last * (1 + w), last + 5), max(cap, last))
            ref = max(longs[-4:])
            lim = ref * 1.1 if ref >= 30 else max(ref * 1.1, ref + 3)
            l = max(min(share * x, lim), min(ref, share * x))    # PAR-053, PAR-063
            if target is not None and l >= target - EPS and x >= vol_target - EPS: reached = True
            grew = grew or x > last + EPS
            out.append((len(out) + 1, x, l, cy)); longs.append(l); last = x
        up += grew
        out.append((len(out) + 1, last * .8, longs[-1] * .8, cy)); longs.append(longs[-1] * .8); cy += 1  # PAR-057
    return out

def first(tier, v0, l0, target, c=None, vol=0, hard=()):
    """Erste Woche mit Zielspitze und Umfang; 0 = schon im Start."""
    if l0 >= target - EPS and v0 >= vol - EPS: return 0
    for nr, x, l, _ in weeks(tier, v0, l0, c, hard=hard):
        if l >= target - EPS and x >= vol - EPS: return nr

def amb(goal, tier, v0, l0, target):
    """Kuerzeste Laenge an den Obergrenzen. Halbmarathon ab sicher 10 km mindestens 12 (Konvention, PAR-068)."""
    n = first(tier, v0, l0, target) + reduction(goal, tier)
    return max(n, 12) if goal == "HM" and (v0, l0) == (150, 60) else n

def real(goal, tier, v0, l0, target):
    """Distanzziel: Regelziel, bei E eine Woche Reserve; 5 km und 10 km ab sicher 10 km ueber 8 Wochen (PAR-068, PAR-084)."""
    n = first(tier, v0, l0, target, RULE[goal]) + reduction(goal, tier) + (tier == "E")
    return max(n, 9) if goal == "5" or (goal == "10" and (v0, l0) == (150, 60)) else n

def timegoal(goal, tier, v0, l0, target):
    """Zeitziel: 160 min mit Regelziel, erste intensive Phase (ein Zyklus ohne Zuwachs) ganz vor der Reduktion.
    Rueckgabe: Laenge, Woche mit 160 min, erste Woche der Phase. E: keine Phase (Stufe bei Planbeginn)."""
    if tier == "E": return None
    c = RULE[goal]
    t160 = first(tier, v0, l0, 0, c, vol=160)
    k = math.ceil(t160 / 4)                                     # naechster Zyklus: Wochen 4k+1 bis 4k+4
    tp = first(tier, v0, l0, target, c)
    if tp >= 4 * k + 1: tp = first(tier, v0, l0, target, c, hard=(k,))
    return max(4 * k + 4, tp) + reduction(goal, tier), t160, 4 * k + 1

def entry(goal, target):
    """E ohne Daten, Rueckgabe (amb, real) ab Abfolge (+9) und ab Einstieg mit Ja (+4)."""
    a, r = first("E", 90, 30, target), first("E", 90, 30, target, RULE[goal])
    return (9 + a + 1, 9 + r + 2), (4 + a + 1, max(4 + r + 2, 9 if goal == "5" else 0))

def rate(goal, tier, v0, l0, target, n, kind):
    """Einstufung bei Laenge n (PAR-084): 2 realistisch, 1 ambitioniert, 0 eher unrealistisch."""
    a, r = amb(goal, tier, v0, l0, target), real(goal, tier, v0, l0, target)
    if kind == "zeit":
        z = timegoal(goal, tier, v0, l0, target)
        r = 10**9 if z is None else max(r, z[0])
    if n >= r: return 2
    if n >= a or (first(tier, v0, l0, target) == 0 and goal in ("5", "10")): return 1
    return 0

GRID = [None] + [5 + i / 12 for i in range(61)]                 # ohne Daten, 5:00 bis 10:00 in 5-s-Schritten
STARTS = ((90, 30, "EAF"), (150, 60, "AF"))

def cases():
    for v0, l0, tiers in STARTS:
        for goal in ("5", "10", "HM"):
            if (v0, goal) != (150, "5"): yield v0, l0, tiers, goal

def checks():
    bad = 0
    for v0, l0, tiers, goal in cases():
        for p in GRID:
            t = peak(goal, p)
            if v0 == 90:
                (a1, r1), (a2, r2) = entry(goal, t)
                bad += a1 > r1 or a2 > r2 or a1 < 10
            for s in tiers:
                bad += amb(goal, s, v0, l0, t) > real(goal, s, v0, l0, t)
                for kind in ("distanz", "zeit"):
                    vals = [rate(goal, s, v0, l0, t, n, kind) for n in range(1, 90)]
                    bad += any(x > y for x, y in zip(vals, vals[1:]))     # laenger nie schlechter
            for lo, hi in zip(tiers, tiers[1:]):
                for n in range(1, 90):
                    for kind in ("distanz", "zeit"):
                        bad += rate(goal, hi, v0, l0, t, n, kind) < rate(goal, lo, v0, l0, t, n, kind)  # hoehere Stufe nie schlechter
        for s in tiers:
            for kind in ("distanz", "zeit"):
                for n in range(1, 90):
                    vals = [rate(goal, s, v0, l0, peak(goal, q), n, kind) for q in GRID[1:]]
                    bad += any(x < y for x, y in zip(vals, vals[1:]))     # langsamer nie besser
    print("Monotonie-Fehler:", bad)
    return bad

def planpass():
    """Regelplaene ab der Grenze von „realistisch“ bis 40 Wochen darueber: Zielspitze vor der Reduktion, Grenzen, Halten."""
    bad = cnt = 0
    for v0, l0, tiers, goal in cases():
        for p in (None, 6, 7, 8, 9):
            t = peak(goal, p)
            for s in tiers:
                r0 = real(goal, s, v0, l0, t)
                w, _ = CAP[s]
                for n in range(r0, r0 + 40):
                    cnt += 1
                    body = weeks(s, v0, l0, RULE[goal], n=n, target=t)[:n - reduction(goal, s)]
                    bad += max(y[2] for y in body) < t - EPS and l0 < t
                    bad += any(y[2] > .4 * y[1] + EPS for y in body)      # PAR-063
                    tops = [v0] + [y[1] for y in body if y[0] % 4]
                    bad += any(b > a * (1 + w) + EPS and b > a + 5 + EPS for a, b in zip(tops, tops[1:]))  # PAR-052 Woche
                    bad += any(b > a * (1 + RULE[goal]) + EPS for a, b in zip(tops[::3], tops[3::3]))      # PAR-052 Zyklus
                    hit = next((i for i, y in enumerate(body) if y[2] >= t - EPS), None)
                    if hit is not None:
                        bad += any(y[1] > body[hit][1] + EPS for y in body[hit:])   # haelt
                    if s != "E":
                        nz, _, start = timegoal(goal, s, v0, l0, t)
                        k = (start - 1) // 4
                        bz = weeks(s, v0, l0, RULE[goal], n=max(nz, n), target=t, vol_target=160, hard=(k,))[:max(nz, n) - reduction(goal, s)]
                        ph = [y for y in bz if y[3] == k]
                        bad += len(ph) != 4 or min(y[1] for y in ph[:3]) < 160 - EPS or 8 / ph[0][1] > .05 + EPS  # PAR-054, PAR-118
                        bad += max(y[2] for y in bz) < t - EPS
    print("Regelplaene geprueft:", cnt, "Fehler:", bad)
    return bad

def regression():
    for (g, s), n in {("10", "E"): 14, ("10", "A"): 11, ("10", "F"): 10, ("HM", "E"): 26, ("HM", "A"): 22, ("HM", "F"): 18}.items():
        assert first(s, 90, 30, peak(g)) == n
    assert (first("E", 90, 30, 120), first("A", 90, 30, 120), first("F", 90, 30, 120)) == (34, 27, 22)
    assert (first("A", 150, 60, 90), first("F", 150, 60, 90), first("A", 150, 60, 90, .15)) == (10, 7, 11)
    for s in "EAF":
        assert (first(s, 90, 30, 60, .125), first(s, 90, 30, 90, .15), first(s, 90, 30, 120, .15)) == (18, 26, 34)
    print("Rueckrechnung R004 B1, M1, Plausibilitaet: stimmt")

def fm(p): return "ohne" if p is None else f"{int(p)}:{round((p % 1) * 60):02d}"

def table():
    print("Start 3 x 30, laengste 30: Ziel Tempo Spitze | ambitioniert E/A/F | realistisch E/A/F | Zeitziel A/F (160 min, Phase ab) | E Abfolge | E Einstieg Ja")
    for goal, ps in (("5", (None, 6, 7, 8, 9)), ("10", (None, 6, 7, 8, 9)), ("HM", (None, 6, 7, 8, 8 + 20 / 60, 9))):
        for p in ps:
            t = peak(goal, p)
            z = [timegoal(goal, s, 90, 30, t) for s in "AF"]
            print(f"{goal:>3} {fm(p):>5} {t:>4} | {[amb(goal, s, 90, 30, t) for s in 'EAF']} | {[real(goal, s, 90, 30, t) for s in 'EAF']} | {[x[0] for x in z]} ({z[0][1]}, {z[0][2]}) | {entry(goal, t)[0]} | {entry(goal, t)[1]}")
    print("Start 3 x 50, laengste 60: Ziel Tempo Spitze | ambitioniert A/F | realistisch A/F | Zeitziel A/F")
    for goal, ps in (("10", (None, 7, 8, 9)), ("HM", (None, 7, 8, 9))):
        for p in ps:
            t = peak(goal, p)
            print(f"{goal:>3} {fm(p):>5} {t:>4} | {[amb(goal, s, 150, 60, t) for s in 'AF']} | {[real(goal, s, 150, 60, t) for s in 'AF']} | {[timegoal(goal, s, 150, 60, t)[0] for s in 'AF']}")

def open_goal():
    for v0, l0 in ((90, 30), (120, 40)):
        pl = weeks("E", v0, l0, RULE["offen"], n=112, max_up=3)
        print("offen ab", v0, "Spitzen", [round(pl[i][1], 1) for i in (2, 6, 10, 50, 102)], "laengste", round(max(y[2] for y in pl), 1))

if __name__ == "__main__":
    regression(); table(); assert checks() == 0; assert planpass() == 0; open_goal()
```

```text
Rueckrechnung R004 B1, M1, Plausibilitaet: stimmt
Start 3 x 30, laengste 30: Ziel Tempo Spitze | ambitioniert E/A/F | realistisch E/A/F | Zeitziel A/F (160 min, Phase ab) | E Abfolge | E Einstieg Ja
  5  ohne   30 | [1, 1, 1] | [9, 9, 9] | [33, 33] (26, 29) | (10, 11) | (5, 9)
  5  6:00   30 | [1, 1, 1] | [9, 9, 9] | [33, 33] (26, 29) | (10, 11) | (5, 9)
  5  7:00   35 | [3, 3, 3] | [9, 9, 9] | [33, 33] (26, 29) | (12, 13) | (7, 9)
  5  8:00   40 | [6, 6, 6] | [9, 9, 9] | [33, 33] (26, 29) | (15, 17) | (10, 12)
  5  9:00   45 | [7, 7, 7] | [12, 11, 11] | [33, 33] (26, 29) | (16, 21) | (11, 16)
 10  ohne   60 | [15, 13, 12] | [20, 20, 20] | [26, 26] (18, 21) | (24, 29) | (19, 24)
 10  6:00   60 | [15, 13, 12] | [20, 20, 20] | [26, 26] (18, 21) | (24, 29) | (19, 24)
 10  7:00   70 | [20, 17, 15] | [24, 24, 24] | [28, 28] (18, 21) | (29, 33) | (24, 28)
 10  8:00   80 | [24, 20, 17] | [28, 28, 28] | [32, 32] (18, 21) | (33, 37) | (28, 32)
 10  9:00   90 | [27, 24, 20] | [32, 32, 32] | [36, 36] (18, 21) | (36, 41) | (31, 36)
 HM  ohne   90 | [27, 24, 20] | [28, 28, 28] | [32, 32] (18, 21) | (36, 37) | (31, 32)
 HM  6:00   90 | [27, 24, 20] | [28, 28, 28] | [32, 32] (18, 21) | (36, 37) | (31, 32)
 HM  7:00   90 | [27, 24, 20] | [28, 28, 28] | [32, 32] (18, 21) | (36, 37) | (31, 32)
 HM  8:00  110 | [32, 28, 24] | [33, 33, 33] | [37, 37] (18, 21) | (41, 42) | (36, 37)
 HM  8:20  120 | [35, 29, 24] | [36, 36, 36] | [40, 40] (18, 21) | (44, 45) | (39, 40)
 HM  9:00  120 | [35, 29, 24] | [36, 36, 36] | [40, 40] (18, 21) | (44, 45) | (39, 40)
Start 3 x 50, laengste 60: Ziel Tempo Spitze | ambitioniert A/F | realistisch A/F | Zeitziel A/F
 10  ohne   60 | [2, 2] | [9, 9] | [10, 10]
 10  7:00   70 | [4, 4] | [9, 9] | [12, 12]
 10  8:00   80 | [9, 8] | [12, 12] | [16, 16]
 10  9:00   90 | [12, 9] | [16, 16] | [20, 20]
 HM  ohne   90 | [12, 12] | [13, 13] | [17, 17]
 HM  7:00   90 | [12, 12] | [13, 13] | [17, 17]
 HM  8:00  110 | [16, 13] | [20, 20] | [24, 24]
 HM  9:00  120 | [17, 16] | [21, 21] | [25, 25]
Monotonie-Fehler: 0
Regelplaene geprueft: 2600 Fehler: 0
offen ab 90 Spitzen [99.0, 108.9, 119.8, 119.8, 119.8] laengste 47.9
offen ab 120 Spitzen [132.0, 145.2, 159.7, 159.7, 159.7] laengste 63.9
```

S8, mit den Funktionen aus R8 in [values-applied.md](values-applied.md), 20.000 Tage je Fall, Seed 1:

```python
for ar in (0, .3, .6):
    vals = []
    for rho in (0, .5):
        for hm, hs, tm in ((7.2, .8, -12), (6.5, 1, -20)):
            rng = random.Random(1); low = 0
            for _ in range(20000):
                xh, xr, g = draw(rng, rho, ar)
                sc = {"hrv": P(z_mean(xh)), "rhr": P(z_mean(xr)), "sleep": D(rng.gauss(hm, hs) + .5 * rho * g),
                      "load": L(rng.gauss(tm, 10)), "mood": MOOD[rng.choices([1, 2, 3, 4, 5], P_MOOD)[0]]}
                low += value(sc, SETS["alle"]) < 50
            vals.append(round(100 * low / 20000, 1))
    print(ar, vals)
# 0 [11.8, 30.6, 15.7, 33.0]; 0.3 [15.3, 33.8, 19.6, 35.9]; 0.6 [19.7, 37.4, 25.1, 39.0]
```

## Stand von Version 2

Kein Git-Repository, deshalb SHA-256 nach `build`:

- `1bee25c6ca627bbc42dd76447d75f7775ba33f227773612c2c8c2c3a35d75646` model-parameters.md
- `eaeeb48f7cfad063e56ffc83d8d88b47302d2437da5ebce1335dc327d63875fc` planning-rules.md
- `3f790804b634064af84c4ff36266147e73899719d961cffd16a6ab1cdb26fa5c` phase-2-3-rules.md
