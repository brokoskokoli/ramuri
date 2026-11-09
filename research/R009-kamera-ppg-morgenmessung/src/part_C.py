"""R009 Teil C: Streuung von ln RMSSD durch ein kurzes Fenster (60 s gegenüber 300 s), synthetische RR-Reihen.

Stationäres Modell einer ruhigen Person: RR_i = RR0 + A·sin(2π·f_r·t_i + φ) + B·sin(2π·0,1·t_i + ψ) + AR(1)-Rauschen.
f_r (Atmung) je Lauf zufällig 0,2–0,3 Hz und langsam schwankend, Phasen zufällig. Parameter so, dass RMSSD um 40 ms liegt.
Gemessen über unabhängige Läufe: SD von ln RMSSD für ein 60-s- und ein 300-s-Fenster derselben Reihe,
SD der Differenz ln RMSSD(60 s, erste Minute) − ln RMSSD(300 s) und Mittel dieser Differenz.
Zusätzlich das Zeitrauschen einer Kamera (SD je Schlagzeitpunkt) als Aufschlag: RMSSD² wächst um ≈ 6·σ_t² (unabhängige
Fehler je Schlagzeitpunkt, siehe Kontrolle unten).
Untergrenze: Echte Reihen sind nicht stationär, also streut ein 60-s-Wert in Wirklichkeit mehr.
"""
import math
import random
import statistics

from common import args

A = args()


def series(rng, seconds, rr0=1000.0, amp=35.0, lf=20.0, noise=12.0, ar=0.5):
    fr = rng.uniform(0.2, 0.3)
    ph, ps = rng.uniform(0, 2 * math.pi), rng.uniform(0, 2 * math.pi)
    t, e, out = 0.0, 0.0, []
    while t < seconds:
        fr_t = fr + 0.02 * math.sin(2 * math.pi * t / 60.0)  # Atemfrequenz schwankt leicht
        e = ar * e + math.sqrt(1 - ar * ar) * rng.gauss(0, noise)
        rr = rr0 + amp * math.sin(2 * math.pi * fr_t * t + ph) + lf * math.sin(2 * math.pi * 0.1 * t + ps) + e
        out.append(rr)
        t += rr / 1000.0
    return out


def rmssd(rr):
    d = [b - a for a, b in zip(rr, rr[1:])]
    return math.sqrt(sum(x * x for x in d) / len(d))


def with_timing_noise(rng, rr, sd_t):
    """Schlagzeitpunkte mit unabhängigem Fehler sd_t (ms): RR_i' = RR_i + e_{i+1} − e_i."""
    e = [rng.gauss(0, sd_t) for _ in range(len(rr) + 1)]
    return [r + e[i + 1] - e[i] for i, r in enumerate(rr)]


def first(rr, seconds):
    t, out = 0.0, []
    for r in rr:
        if t >= seconds * 1000:
            break
        out.append(r)
        t += r
    return out


reps = max(200, A.reps // 4)
print(f"# Teil C, reps={reps}, seed={A.seed}")
print("sd_t  ln60_mean  ln300_mean  sd_ln60  sd_ln300  mean(ln60-ln300)  sd(ln60-ln300)")
for sd_t in (0.0, 5.0, 10.0, 15.0):
    rng = random.Random(A.seed)
    l60, l300, dif = [], [], []
    for _ in range(reps):
        rr = series(rng, 300)
        rrn = with_timing_noise(rng, rr, sd_t) if sd_t else rr
        a, b = math.log(rmssd(first(rrn, 60))), math.log(rmssd(rrn))
        l60.append(a)
        l300.append(b)
        dif.append(a - b)
    print(f"{sd_t:<5} {statistics.fmean(l60):9.3f}  {statistics.fmean(l300):10.3f}  {statistics.pstdev(l60):7.3f}  "
          f"{statistics.pstdev(l300):8.3f}  {statistics.fmean(dif):16.3f}  {statistics.pstdev(dif):14.3f}")

# Kontrolle Zeitrauschen: Differenz aufeinanderfolgender RR' enthält e_{i+2} − 2e_{i+1} + e_i, Varianz 6·sd_t².
# RMSSD'² ≈ RMSSD² + 6·sd_t². Beispiel RMSSD 40 ms, sd_t 10 ms: sqrt(1600 + 600) = 46,9 ms, ln-Aufschlag 0,159.
print("\nKontrolle Aufschlag durch Zeitrauschen (RMSSD 40 ms):",
      {s: round(math.log(math.sqrt(1600 + 6 * s * s) / 40), 3) for s in (5, 10, 15)})
