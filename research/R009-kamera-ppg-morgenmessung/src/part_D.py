"""R009 Teil D: Trennschärfe der Akzeptanzkriterien für lnRMSSD im Validierungsplan (Nachbesserung 1).

Modell (alles in Einheiten der wahren Tages-SD sb = 1):
  H9-Reihe h_i (lnRMSSD aus den Brustgurt-RR im selben 60-s-Fenster) = AR(1) mit Autokorrelation 0,3 über N_all Tage.
  Differenz Kamera − H9 an den Prüftagen: d_i = beta·h_i + e_i, e unabhängig N(0, ratio) (bzw. AR(1) 0,3).
  Die Kamera misst dieselben Schläge wie der H9, das Fensterrauschen ist also gemeinsam und steckt nicht in d.
D1 Verhältniskriterium: r_hat = SD(d über n_test Prüftage) / SD(h über N_all Tage).
   bestanden: r_hat ≤ 0,5; eingeschränkt: r_hat ≤ 1. Ausgegeben P(bestanden), P(höchstens eingeschränkt) und das
   2,5-/97,5-%-Quantil von r_hat.
D2 Proportionaler Bias: Steigung b der Regression d auf h (Prüftage). Kriterium |b| ≤ 0,2. Ausgegeben P(|b| ≤ 0,2),
   mittlere halbe Breite des 95-%-KI von b und zur Kontrolle die Steigung gegen den Mittelwert (Kamera + H9)/2,
   die bei beta = 0 künstlich positiv ist.
D3 Analytisch: Steigung des Aufschlags durch Zeitrauschen, f(L) = ½·ln(1 + 6·σ_t²·e^(−2L)), L = ln RMSSD,
   df/dL = −6σ_t²e^(−2L) / (1 + 6σ_t²e^(−2L)). Das ist der proportionale Bias, den Zeitrauschen erzeugt.
"""
import math
import random
import statistics

from common import ar1, args, t_quantile

A = args()
RATIOS = (0.3, 0.4, 0.5, 0.6, 0.7, 0.85, 1.0, 1.3, 1.6)
DESIGNS = [  # (n_test, N_all, Beschreibung)
    (10, 14, "14 Tage, nach Verwerfen 10 gewertet"),
    (14, 14, "14 Tage, alle gewertet"),
    (14, 28, "28 Tage: 14 Kalibrier + 14 Prüftage"),
    (22, 28, "28 Tage, Kreuzvalidierung, 80 % gültig"),
    (28, 28, "28 Tage, Kreuzvalidierung, alle gültig"),
    (22, 42, "42 Tage: 14 Kalibrier + 28 Prüf, 80 % gültig"),
    (28, 42, "42 Tage: 14 Kalibrier + 28 Prüftage"),
]


def ols_slope(x, y):
    mx, my = statistics.fmean(x), statistics.fmean(y)
    sxx = sum((a - mx) ** 2 for a in x)
    b = sum((a - mx) * (c - my) for a, c in zip(x, y)) / sxx
    res = [c - my - b * (a - mx) for a, c in zip(x, y)]
    se = math.sqrt(sum(r * r for r in res) / (len(x) - 2) / sxx)
    return b, se


def sim(n_test, n_all, ratio, beta=0.0, ar_d=0.0, rng=None):
    h = ar1(rng, n_all, 0.3, 1.0)
    ht = h[n_all - n_test:]                      # Prüftage = die letzten n_test Tage
    e = ar1(rng, n_test, ar_d, ratio) if ar_d else [rng.gauss(0, ratio) for _ in range(n_test)]
    d = [beta * a + b for a, b in zip(ht, e)]
    return h, ht, d


print(f"# Teil D, reps={A.reps}, seed={A.seed}; Einheiten: wahre Tages-SD der H9-Reihe = 1, AR der Reihe 0,3")

print("\n## D1 Verhältniskriterium SD(d)/Tages-SD: P(bestanden ≤ 0,5) / P(höchstens eingeschränkt ≤ 1) in %")
print(f"{'Design':<46} n_test N_all  " + "  ".join(f"r={r:<9}" for r in RATIOS))
for ar_d in (0.0, 0.3):
    print(f"-- Differenzen d {'unabhängig' if not ar_d else 'AR(1) 0,3'}")
    for n_test, n_all, name in DESIGNS:
        cells = []
        for r in RATIOS:
            rng = random.Random(A.seed)
            ok = lim = 0
            for _ in range(A.reps):
                h, ht, d = sim(n_test, n_all, r, ar_d=ar_d, rng=rng)
                rh = statistics.stdev(d) / statistics.stdev(h)
                ok += rh <= 0.5
                lim += rh <= 1.0
            cells.append(f"{100 * ok / A.reps:4.0f}/{100 * lim / A.reps:<4.0f}")
        print(f"{name:<46} {n_test:>6} {n_all:>5}  " + "  ".join(f"{c:<11}" for c in cells))

print("\n## D1b Streubereich von r_hat (2,5- und 97,5-%-Quantil), d unabhängig")
print(f"{'Design':<46} " + "  ".join(f"r={r:<11}" for r in (0.5, 0.7, 1.0, 1.3)))
for n_test, n_all, name in DESIGNS:
    cells = []
    for r in (0.5, 0.7, 1.0, 1.3):
        rng = random.Random(A.seed)
        xs = sorted(statistics.stdev(d) / statistics.stdev(h)
                    for h, ht, d in (sim(n_test, n_all, r, rng=rng) for _ in range(A.reps)))
        cells.append(f"{xs[int(0.025 * len(xs))]:.2f}–{xs[int(0.975 * len(xs))]:.2f}")
    print(f"{name:<46} " + "  ".join(f"{c:<13}" for c in cells))

print("\n## D2 Proportionaler Bias, ratio 0,5: P(|b| ≤ 0,2) in %, halbe KI-Breite von b, Steigung gegen Mittelwert")
print("n_test  beta   P(|b|<=0,2)  KI±   b_mittel(gegen H9)  b_mittel(gegen (K+H9)/2)")
for n_test in (14, 22, 28):
    for beta in (0.0, -0.1, -0.2, -0.3, -0.4):
        rng = random.Random(A.seed)
        ok = 0
        hw = bs = bm = 0.0
        for _ in range(A.reps):
            h, ht, d = sim(n_test, n_test, 0.5, beta=beta, rng=rng)
            b, se = ols_slope(ht, d)
            ok += abs(b) <= 0.2
            hw += t_quantile(0.975, n_test - 2) * se
            bs += b
            mean = [a + c / 2 for a, c in zip(ht, d)]   # (Kamera + H9)/2 = H9 + d/2
            bm += ols_slope(mean, d)[0]
        r = A.reps
        print(f"{n_test:>6}  {beta:<5}  {100 * ok / r:10.0f}  {hw / r:5.2f}  {bs / r:17.3f}  {bm / r:22.3f}")

print("\n## D3 Proportionaler Bias durch Zeitrauschen (analytisch): Steigung df/dL bei RMSSD und σ_t")
print("RMSSD_ms  " + "  ".join(f"σt={s:<4}" for s in (3, 5, 7, 10, 15)))
for rm in (25, 40, 60):
    cells = []
    for s in (3, 5, 7, 10, 15):
        a = 6 * s * s / rm ** 2
        cells.append(f"{-a / (1 + a):+7.3f}")
    print(f"{rm:<8}  " + "  ".join(cells))

# Kontrollen:
# 1) SD(d)-Schätzer: bei ratio 0,5, n_test 28, N_all 28, d unabhängig, liegt P(bestanden) knapp unter 50 %,
#    weil die Stichproben-SD einer AR-Reihe im Mittel etwas zu klein ist (Nenner kleiner -> r_hat größer).
#    Review-Runde 1 rechnete unabhängig 47 % (r 0,5) und 4 % (r 0,7) bei 28 Tagen.
# 2) Steigung gegen den Mittelwert bei beta 0: erwartet ≈ (ratio²/2)/(1 + ratio²/4) = 0,125/1,0625 = 0,118.
print("\nKontrolle erwartete Scheinsteigung gegen Mittelwert bei ratio 0,5:", round(0.125 / 1.0625, 3))
