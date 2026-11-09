"""R009 Teil B: rollendes 7-Tage-Mittel nach PAR-161/162 bei fehlenden Tagen und Kamera-Streuung (Erweiterung von R8).

Tag 0..28, heute = Tag 28. Wahre Tageswerte (lnRMSSD bzw. Ruhepuls) = AR(1) mit biologischer SD sb.
Gemessen = wahr + Kamerafehler N(0, sm) (+ mit Wahrscheinlichkeit q eine Fehlmessung, die die Qualitätsprüfung
passiert: lnRMSSD +0,4, Ruhepuls +4 1/min). Fehlende Tage: zufällig mit p oder „nur Werktage“ (2 von 7 fehlen).
Regel wie PAR-161: x = Mittel der gültigen Werte der letzten 7 Tage (Tag 22..28), k ≥ 3, heute muss vorliegen;
Referenz = Median und MAD der gültigen Werte der 28 Tage vor heute (Tag 0..27), mindestens 14;
z = (x − Median) / (1,4826 · MAD / √k). HRV: kein z bei MAD < 0,02. Ruhepuls: Vorzeichen umgedreht, kein z bei MAD < 1.
Echte Änderung: ab Tag 28 − d + 1 sinkt lnRMSSD um delta·sb (bzw. steigt der Ruhepuls), d = Tage seit Beginn.
Ausgegeben:
  avail   Anteil der Läufe mit z (alle Bedingungen erfüllt), ohne Änderung
  sd_z    SD von z ohne Änderung (Soll bei unabhängigen Tagen ≈ 1; R8: breiter bei AR > 0)
  fa1     P(z ≤ −1 | z vorhanden) ohne Änderung (Fehlalarm; Normalverteilung: 15,9 %)
  fa2     P(z ≤ −2 | z vorhanden) ohne Änderung (2,3 %)
  det_d   P(z ≤ −1 | z vorhanden) nach d Tagen Abfall um delta·sb
  kal_d   wie det_d, aber mit der Schwelle, unter der ohne Änderung 15,9 % der z liegen (gleiche Fehlalarmrate für alle
          Fälle; vergleicht die Trennschärfe unabhängig davon, wie breit z ist)
"""
import math
import random
import statistics

from common import ar1, args, median_mad

A = args()
DAYS = 29
DS = (1, 3, 5, 7)


def missing_mask(rng, p):
    if p == "wd":  # nur Werktage: feste Woche mit zufälliger Phase, 2 von 7 Tagen fehlen
        ph = rng.randrange(7)
        return [((i + ph) % 7) < 5 for i in range(DAYS)]
    return [rng.random() >= p for _ in range(DAYS)]


def z_of(meas, mask, mad_min, rounding=False, today_required=True, kmin=3, refmin=14, ref_excl=False, window=7):
    vals = [round(v) if rounding else v for v in meas]
    ref_end = DAYS - window if ref_excl else 28   # ref_excl: Referenz endet vor dem Fenster (Tag 0..21)
    ref = [v for v, ok in zip(vals[:ref_end], mask[:ref_end]) if ok]
    win = [v for v, ok in zip(vals[DAYS - window:], mask[DAYS - window:]) if ok]
    if today_required and not mask[28]:
        return None, "heute fehlt"
    if len(win) < kmin:
        return None, "k<3"
    if len(ref) < refmin:
        return None, "Ref<14"
    med, mad = median_mad(ref)
    if mad < mad_min:
        return None, "MAD"
    k = len(win)
    return (statistics.fmean(win) - med) / (1.4826 * mad / math.sqrt(k)), "ok"


def run(kind, sb, sm, ar, p, q, delta=1.0, rounding=False, reps=A.reps, out=None, **rule):
    """kind 'hrv' (ln-Einheiten, Abfall ungünstig) oder 'rhr' (1/min, Anstieg ungünstig, z umgedreht)."""
    sign = -1 if kind == "hrv" else 1        # Richtung der ungünstigen Änderung
    out_size = out if out is not None else (0.4 if kind == "hrv" else 4.0)
    mad_min = rule.pop("mad_min", 0.02 if kind == "hrv" else 1.0)
    rng = random.Random(A.seed)
    zs, reasons = [], {}
    det = {d: [] for d in DS}
    for _ in range(reps):
        true = ar1(rng, DAYS, ar, sb)
        noise = [rng.gauss(0, sm) + (out_size if rng.random() < q else 0.0) for _ in range(DAYS)]
        mask = missing_mask(rng, p)
        meas = [t + e for t, e in zip(true, noise)]
        z, why = z_of(meas, mask, mad_min, rounding, **rule)
        reasons[why] = reasons.get(why, 0) + 1
        if z is not None:
            zs.append(z if kind == "hrv" else -z)
        for d in DS:
            m2 = [v + (sign * delta * sb if i >= DAYS - d else 0.0) for i, v in enumerate(meas)]
            z2, _ = z_of(m2, mask, mad_min, rounding, **rule)
            if z2 is not None:
                det[d].append(z2 if kind == "hrv" else -z2)
    n = len(zs)
    sd = statistics.pstdev(zs) if n > 1 else float("nan")
    fa1 = 100 * sum(z <= -1 for z in zs) / n if n else float("nan")
    fa2 = 100 * sum(z <= -2 for z in zs) / n if n else float("nan")
    dets = "  ".join(f"{100 * sum(z <= -1 for z in det[d]) / len(det[d]):5.1f}" if det[d] else "  nan" for d in DS)
    # kalibriert: Schwelle so, dass ohne Änderung genau 15,9 % der Tage darunter liegen (fairer Vergleich der Varianten)
    thr = sorted(zs)[int(0.159 * n)] if n else float("nan")
    cal = "  ".join(f"{100 * sum(z <= thr for z in det[d]) / len(det[d]):5.1f}" if det[d] else "  nan" for d in DS)
    dets += f" | {cal}"
    why = ", ".join(f"{k} {100 * v / reps:.0f}%" for k, v in sorted(reasons.items()) if k != "ok")
    return f"{100 * n / reps:5.1f}  {sd:4.2f}  {fa1:5.1f}  {fa2:4.1f}  {dets}   {why}"


HEAD = "avail%  sd_z  fa1%   fa2%  det1%  det3%  det5%  det7% | kal1%  kal3%  kal5%  kal7%   ohne z wegen"

print(f"# Teil B, reps={A.reps}, seed={A.seed}; Abfall delta = 1 · sb; Fehlmessung lnRMSSD +0,4 bzw. Ruhepuls +4")

print("\n## B1 lnRMSSD, sb = 0,10 und 0,15 (ln), Kamerafehler sm, AR, Lücken p, Fehlmessungen q")
print("sb    sm    AR   p     q     " + HEAD)
for sb in (0.10, 0.15):
    for ar in (0.0, 0.3, 0.6):
        for sm in (0.0, 0.05, 0.10):
            print(f"{sb:<5} {sm:<5} {ar:<4} {0:<5} {0:<5} " + run("hrv", sb, sm, ar, 0.0, 0.0))
for sb in (0.10,):
    for sm in (0.05,):
        for p in (0.2, 0.4, "wd"):
            for q in (0.0, 0.05):
                print(f"{sb:<5} {sm:<5} {0.3:<4} {p:<5} {q:<5} " + run("hrv", sb, sm, 0.3, p, q))
        for sm2 in (0.15,):
            print(f"{sb:<5} {sm2:<5} {0.3:<4} {0.2:<5} {0.05:<5} " + run("hrv", sb, sm2, 0.3, 0.2, 0.05))

print("\n## B2 Ruhepuls (1/min), sb = 1,5 / 2 / 3, Kamerafehler sm, gerundet ja/nein, AR 0,3")
print("sb    sm    rund p     q     " + HEAD)
for sb in (1.5, 2.0, 3.0):
    for sm in (0.0, 1.0):
        for rnd in (False, True):
            print(f"{sb:<5} {sm:<5} {'ja' if rnd else 'nein':<4} {0:<5} {0:<5} " + run("rhr", sb, sm, 0.3, 0.0, 0.0, rounding=rnd))
for p in (0.2, 0.4, "wd"):
    print(f"{2.0:<5} {1.0:<5} {'nein':<4} {p:<5} {0.05:<5} " + run("rhr", 2.0, 1.0, 0.3, p, 0.05))

print("\n## B3 Regelvarianten, lnRMSSD sb 0,10, sm 0,05, AR 0,3, Lücken p 0,2, Fehlmessungen q 0,05")
print("Variante                                   " + HEAD)
VAR = [("PAR-161 wie heute", {}),
       ("Referenz ohne die 7 Fenstertage (Tag 0-21)", {"ref_excl": True}),
       ("heute nicht Pflicht", {"today_required": False}),
       ("heute nicht Pflicht + Referenz ohne Fenster", {"today_required": False, "ref_excl": True}),
       ("k mindestens 4", {"kmin": 4}),
       ("Einzeltag (Fenster 1, MAD ohne /√k)", {"window": 1, "kmin": 1})]
for name, rule in VAR:
    print(f"{name:<42} " + run("hrv", 0.10, 0.05, 0.3, 0.2, 0.05, **rule))
print("Ruhepuls sb 2, sm 1, AR 0,3, p 0,2, q 0,05, MAD-Grenze 1 vs. 0,5:")
print(f"{'Ruhepuls PAR-162 wie heute':<42} " + run("rhr", 2.0, 1.0, 0.3, 0.2, 0.05))
print(f"{'Ruhepuls MAD-Grenze 0,5':<42} " + run("rhr", 2.0, 1.0, 0.3, 0.2, 0.05, mad_min=0.5))
print(f"{'Ruhepuls sb 1,5, MAD-Grenze 1':<42} " + run("rhr", 1.5, 1.0, 0.3, 0.2, 0.05))
print(f"{'Ruhepuls sb 1,5, MAD-Grenze 0,5':<42} " + run("rhr", 1.5, 1.0, 0.3, 0.2, 0.05, mad_min=0.5))

print("\n## B4 lnRMSSD mit realistischer Tagesstreuung sb = 0,33 ln (Nuuttila 2024, Plews-Dissertation), sm 0,5·sb,")
print("AR 0,3, Lücken p 0,2: Wirkung der Fehlmessungen (+0,4 ln fest bzw. +4·sb) im Vergleich zu sb 0,10")
print("sb    sm     q     out    " + HEAD)
for sb, sm in ((0.10, 0.05), (0.33, 0.165)):
    for q, out in ((0.0, 0.4), (0.05, 0.4), (0.05, 4 * sb)):
        print(f"{sb:<5} {sm:<6} {q:<5} {out:<6.2f} " + run("hrv", sb, sm, 0.3, 0.2, q, out=out))

# Kontrolle: Erwartete MAD einer Normalverteilung = 0,6745·SD. Bei sb=1,5 liegt sie also bei ≈1,01 1/min,
# d. h. rund die Hälfte der Referenzen fällt unter die Grenze 1 aus PAR-162.
print("\nKontrolle MAD-Erwartung 0,6745·sb:", [round(0.6745 * s, 2) for s in (1.5, 2.0, 3.0)])
