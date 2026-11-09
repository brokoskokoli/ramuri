"""Gemeinsame Hilfen für R009 (nur Standardbibliothek)."""
import argparse
import math
import statistics

Z975 = statistics.NormalDist().inv_cdf(0.975)  # 1,95996


def args():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--reps", type=int, default=4000)
    return ap.parse_args()


def t_quantile(p, nu):
    """t-Quantil über die Cornish-Fisher-Reihe (Abramowitz/Stegun 26.7.5).
    Fehler < 0,002 ab nu = 9; Kontrolle unten gegen Tabellenwerte."""
    z = statistics.NormalDist().inv_cdf(p)
    g1 = (z ** 3 + z) / 4
    g2 = (5 * z ** 5 + 16 * z ** 3 + 3 * z) / 96
    g3 = (3 * z ** 7 + 19 * z ** 5 + 17 * z ** 3 - 15 * z) / 384
    g4 = (79 * z ** 9 + 776 * z ** 7 + 1482 * z ** 5 - 1920 * z ** 3 - 945 * z) / 92160
    return z + g1 / nu + g2 / nu ** 2 + g3 / nu ** 3 + g4 / nu ** 4


# Kontrolle gegen Tabellenwerte t(0,975; nu): 9 -> 2,262, 13 -> 2,160, 27 -> 2,052
for _nu, _ref in ((9, 2.262), (13, 2.160), (27, 2.052)):
    assert abs(t_quantile(0.975, _nu) - _ref) < 0.002, (_nu, t_quantile(0.975, _nu))


def ar1(rng, n, ar, sd=1.0):
    """Stationäre AR(1)-Reihe mit Randverteilung N(0, sd²)."""
    e = rng.gauss(0, 1)
    out = []
    for _ in range(n):
        e = ar * e + math.sqrt(1 - ar * ar) * rng.gauss(0, 1)
        out.append(sd * e)
    return out


def median_mad(xs):
    m = statistics.median(xs)
    return m, statistics.median(abs(a - m) for a in xs)
