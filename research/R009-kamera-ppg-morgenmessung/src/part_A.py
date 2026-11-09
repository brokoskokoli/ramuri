"""R009 Teil A: Fallzahl für den Bland-Altman-Vergleich Kamera gegen Polar H9 (eine Person, je Tag ein Paar).

Modell: Differenz Kamera − Referenz am Tag i: d_i = mu + e_i, e als AR(1) mit SD sigma und Autokorrelation rho
(rho > 0 bildet Tagesbedingungen ab, z. B. kalte Finger über mehrere Tage). Je Lauf n Tage.
Ausgewertet wie üblich: Bias = Mittel(d), LoA = Bias ± 1,96·s.
Konfidenzintervall der LoA nach Bland und Altman (1986/1999): LoA ± t(0,975; n−1)·√(3/n)·s.
Gemessen:
  ci_bias   mittlere halbe Breite des 95-%-KI des Bias
  ci_loa    mittlere halbe Breite des 95-%-KI einer LoA
  cover     Anteil der Läufe, in denen das KI die wahre obere LoA (mu + 1,96·sigma) enthält (Soll ≈ 95 %)
  pass      Anteil der Läufe, in denen beide äußeren KI-Enden innerhalb ±Delta liegen
            (Akzeptanz nach dem Ansatz von Lu et al. 2016: oberes KI-Ende der oberen LoA ≤ Delta usw.)
"""
import math
import random
import statistics

from common import Z975, ar1, args, t_quantile

A = args()
NS = (10, 14, 21, 28, 42)


def one(rng, n, mu, sigma, rho):
    d = [mu + x for x in ar1(rng, n, rho, sigma)]
    m = statistics.fmean(d)
    s = statistics.stdev(d)
    t = t_quantile(0.975, n - 1)
    hb = t * s / math.sqrt(n)
    hl = t * math.sqrt(3 / n) * s
    up, lo = m + Z975 * s, m - Z975 * s
    return hb, hl, up, lo


def table(name, unit, cases, deltas):
    print(f"\n## {name} ({unit}); Zeilen: mu, sigma, rho, n; reps={A.reps}")
    head = "mu     sigma  rho   n   ci_bias  ci_loa  cover%  " + "  ".join(f"pass(D={d})%" for d in deltas)
    print(head)
    for mu, sigma, rho in cases:
        for n in NS:
            rng = random.Random(A.seed)
            hb_s = hl_s = cov = 0.0
            ok = [0] * len(deltas)
            true_up = mu + Z975 * sigma
            for _ in range(A.reps):
                hb, hl, up, lo = one(rng, n, mu, sigma, rho)
                hb_s += hb
                hl_s += hl
                cov += (up - hl <= true_up <= up + hl)
                for j, D in enumerate(deltas):
                    ok[j] += (up + hl <= D) and (lo - hl >= -D)
            r = A.reps
            print(f"{mu:<6} {sigma:<6} {rho:<4} {n:>3}  {hb_s / r:7.3f}  {hl_s / r:6.3f}  {100 * cov / r:6.1f}  "
                  + "  ".join(f"{100 * k / r:12.1f}" for k in ok))


# Puls in 1/min. Akzeptanz Delta 2 und 3 (siehe RESULTS.md).
table("Puls", "1/min",
      [(mu, s, rho) for mu in (0.0, 0.5) for s in (0.5, 1.0, 1.5) for rho in (0.0,)] + [(0.0, 1.0, 0.5)],
      (2.0, 3.0))
# ln RMSSD: entfällt seit Nachbesserung 1. Das Kriterium für lnRMSSD ist kein festes Delta, sondern das Verhältnis
# SD(d) / Tages-SD der H9-Reihe; seine Trennschärfe rechnet Teil D.

# Handrechnung zur Kontrolle: n=21, s=1, t(0,975;20)=2,086 -> ci_bias 0,455, ci_loa 2,086*sqrt(3/21)=0,789
print("\nKontrolle n=21, s=1:", round(t_quantile(0.975, 20) / math.sqrt(21), 3), round(t_quantile(0.975, 20) * math.sqrt(3 / 21), 3))
