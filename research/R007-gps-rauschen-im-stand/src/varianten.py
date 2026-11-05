#!/usr/bin/env python3
"""Spannen um den gestückelten Wert, alle durch den echten RunPreprocessor (Harness des Laufs).

Mischungen, Ziehungen, Stichprobe der Sitzungen, Einlauf-Schnitte, GPS-Filter, Parameter. Dazu die
Einlauf-Rechnung ohne Simulation (ersetzt das frühere einlauf_check.py).
Ausgabe: <lauf>/varianten.txt (Bildschirm), <lauf>/varianten.csv, Einzelläufe unter <lauf>/var/.
"""
import csv, math, os, random, statistics as st, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stueckel as S

D, OUT, SEED, MIX, N = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
RUNS, SPEED, TOTAL, STOP, STOPS, BURN = sys.argv[6:12]
RUN_M = float(SPEED) * (int(TOTAL) - int(STOP) * int(STOPS))
LIMIT = RUN_M * 0.01
TOR = 'getspeed_gate_0.5'
MITS_ALL = ['keins', TOR, 'getspeed_integral', 'mindist_5_nurstrecke', 'mindist_8_nurstrecke', 'mittel_10s', 'mittel_20s']
MITS = ['keins', TOR]


def q(v, p):
    v = sorted(v)
    x = p * (len(v) - 1)
    i = int(x)
    return v[i] if i + 1 >= len(v) else v[i] + (v[i + 1] - v[i]) * (x - i)


full = [s for s in S.load(D, S.is_full_second) if len(s[1]) >= 20]
sacc = [s for s in S.load(D, S.has_speed_accuracy) if len(s[1]) >= 20]
print(f'Sitzungen mit mindestens 20 Zeilen: volle Sekunde {len(full)}, Tempo-Genauigkeit über 0 {len(sacc)}')
rows_csv = []


def sim(group, tag, sessions, axis, cut, mix, draw=None, resample=False, burn=None, par=(), mits=MITS):
    """Ein Pool, 200 Läufe (Standard). Rückgabe je Gegenmittel die Kennzahlen."""
    d = f'{OUT}/var/{tag}'
    os.makedirs(f'{d}/norm', exist_ok=True)
    pool, used = S.stitch(sessions, S.keep_after(axis, cut), mix, resample)
    S.write_tsv(f'{d}/norm/ncount_stueckel__1.tsv', pool)
    subprocess.run([f'{OUT}/harness', '--norm', f'{d}/norm', '--out', d, '--seed', str(SEED if draw is None else draw),
                    '--runs', RUNS, '--run-speed', SPEED, '--total-s', TOTAL, '--stop-s', STOP, '--stops', STOPS,
                    '--burn-in-s', str(BURN if burn is None else burn), '--sim-only', '--mitigations', ';'.join(mits), *par],
                   check=True, stdout=subprocess.DEVNULL)
    res = {}
    by = {}
    for r in csv.DictReader(open(f'{d}/runs.csv')):
        by.setdefault(r['mitigation'], []).append(r)
    for m, rs in by.items():
        h = [float(r['sham_stop_m']) for r in rs]
        e = [float(r['dist_err_m']) for r in rs]
        u = [float(r['unpaused']) for r in rs]
        me = [float(r['moving_excess_s']) for r in rs]
        x = dict(group=group, tag=tag, mitigation=m, sessions=used, points=len(pool), med_m=q(h, .5), pct=100 * q(h, .5) / RUN_M,
                 mean_m=st.mean(h), p10=q(h, .1), p90=q(h, .9), err_med=q(e, .5), err_p10=q(e, .1), err_p90=q(e, .9), err_mean=st.mean(e),
                 u_med=q(u, .5), u_mean=st.mean(u), mz=q(me, .5))
        res[m] = x
        rows_csv.append(x)
    return res


def span(rs, m='keins', key='pct'):
    v = [r[m][key] for r in rs]
    return min(v), q(v, .5), max(v)


def fmt(t, unit=' %', dec=2):
    return f'{t[1]:.{dec}f} (min {t[0]:.{dec}f}, max {t[2]:.{dec}f}){unit}'


# Kontrolle: Variante mit dem Seed des Hauptlaufs muss bytegleich zum Pool des Hauptlaufs sein.
main_rs = sim('haupt', 'haupt', full, 'first', 10, MIX, mits=MITS_ALL)
assert open(f'{OUT}/var/haupt/norm/ncount_stueckel__1.tsv').read() == open(f'{OUT}/norm/ncount_stueckel__1.tsv').read(), 'Pool weicht ab'
print('Kontrolle: Pool der Variante mit Mischungs-Seed', MIX, 'ist bytegleich zum Hauptlauf;', main_rs['keins']['sessions'], 'Sitzungen,', main_rs['keins']['points'], 'Punkte,',
      round(main_rs['keins']['points'] / main_rs['keins']['sessions'], 1), 'Punkte je Sitzung')

print(f'\n# V1 Mischungen: Hauptdefinition (volle Sekunde, ab 10 s nach erster GPS-Zeile), {N} Mischungen, gleiche Ziehung (Seed {SEED}), je {RUNS} Läufe')
mix_rs = [sim('mischung', f'mix{i}', full, 'first', 10, i, mits=MITS_ALL) for i in range(1, N + 1)]
print('Gegenmittel: Scheinstrecke Median der Läufe | Mittel der Läufe in m | Stopps ohne Pause Mittel | Mehrzeit | Streckenfehler Median in m')
for m in MITS_ALL:
    print(f" {m}: {fmt(span(mix_rs, m))} | {fmt(span(mix_rs, m, 'mean_m'), ' m', 1)} | {fmt(span(mix_rs, m, 'u_mean'), '', 2)} | {fmt(span(mix_rs, m, 'mz'), ' s', 0)} | {fmt(span(mix_rs, m, 'err_med'), ' m', 1)}")
v = [r['keins']['pct'] for r in mix_rs]
print(f" keins: P10 bis P90 der Mischungen {q(v, .1):.2f} bis {q(v, .9):.2f} %; Mischungen über 1 %: {sum(x > 1 for x in v)} von {len(v)}; Median der Stopps ohne Pause je Lauf höchstens {max(r['keins']['u_med'] for r in mix_rs):.0f}")

print(f'\n# V2 Ziehungen: Pool des Hauptlaufs, andere Ziehung der Fenster')
dr_rs = [sim('ziehung', f'draw{i}', full, 'first', 10, MIX, draw=i) for i in range(1, 6)]
print(f" keins: {fmt(span(dr_rs))}")

print(f'\n# V3 Sitzungs-Stichprobe: Sitzungen mit Zurücklegen gezogen, {2 * N} Wiederholungen. Spiegelt die Unsicherheit durch die Auswahl der Sitzungen und die Mischung')
bs_rs = [sim('stichprobe', f'boot{i}', full, 'first', 10, 1000 + i, resample=True) for i in range(1, 2 * N + 1)]
v = [r['keins']['pct'] for r in bs_rs]
print(f" keins: {fmt(span(bs_rs))}; P2,5 bis P97,5 {q(v, .025):.2f} bis {q(v, .975):.2f} %; unter 1 %: {sum(x <= 1 for x in v)} von {len(v)}")
v = [r[TOR]['pct'] for r in bs_rs]
print(f" Tor: {fmt(span(bs_rs, TOR))}")
v = [r['keins']['u_med'] for r in bs_rs]
print(f" Median der Stopps ohne Pause je Lauf höchstens {max(v):.0f}; Mittel {fmt(span(bs_rs, 'keins', 'u_mean'), '', 2)}")

print('\n# V4 Einlauf-Schnitte (Dokumentation der Spanne, nicht die Suche nach einem besseren Schnitt), je 5 Mischungen')
print('schnitt: Sitzungen, Punkte | Scheinstrecke Median der Läufe | Mittel in m | Stopps ohne Pause Mittel | Mehrzeit')
mixes = [MIX, 1, 2, 3, 4]
for name, axis, cut in (('ab 10 s nach erster GPS-Zeile', 'first', 10), ('ab 15 s nach erster GPS-Zeile', 'first', 15), ('ab 20 s nach erster GPS-Zeile', 'first', 20),
                        ('ab 20 s nach StartTime', 'start', 20), ('ab 25 s nach StartTime', 'start', 25)):
    rs = [sim('schnitt', f'cut_{axis}{cut}_mix{i}', full, axis, cut, i) for i in mixes]
    print(f" {name}: {rs[0]['keins']['sessions']}, {rs[0]['keins']['points']} | {fmt(span(rs))} | {fmt(span(rs, 'keins', 'mean_m'), ' m', 1)} | {fmt(span(rs, 'keins', 'u_mean'), '', 2)} | {fmt(span(rs, 'keins', 'mz'), ' s', 0)}")
    if (axis, cut) == ('first', 20):
        b0 = sim('schnitt', 'cut_first20_burn0', full, axis, cut, MIX, burn=0)
        print(f"   dasselbe ohne die 120 s Einlauf im Pool (Mischung {MIX}): {b0['keins']['pct']:.2f} %")
b0 = sim('schnitt', 'cut_first10_burn0', full, 'first', 10, MIX, burn=0)
print(f" Hauptdefinition ohne die 120 s Einlauf im Pool (Mischung {MIX}): {b0['keins']['pct']:.2f} %")

print('\n# V5 GPS-Filter: Tempo-Genauigkeit über 0 statt voller Sekunde, ab 10 s nach erster GPS-Zeile, 5 Mischungen')
rs = [sim('filter', f'sacc_mix{i}', sacc, 'first', 10, i) for i in mixes]
print(f" Sitzungen {rs[0]['keins']['sessions']}, Punkte {rs[0]['keins']['points']}")
print(f" keins: Scheinstrecke {fmt(span(rs))}, Mittel {fmt(span(rs, 'keins', 'mean_m'), ' m', 1)}, Stopps ohne Pause Mittel {fmt(span(rs, 'keins', 'u_mean'), '', 2)}, Mehrzeit {fmt(span(rs, 'keins', 'mz'), ' s', 0)}")
print(f" Median der Stopps ohne Pause je Lauf höchstens {max(r['keins']['u_med'] for r in rs):.0f}")
print(f" Tor: Scheinstrecke {fmt(span(rs, TOR))}, Streckenfehler Median {fmt(span(rs, TOR, 'err_med'), ' m', 1)}, P90 {fmt(span(rs, TOR, 'err_p90'), ' m', 1)}, Mehrzeit {fmt(span(rs, TOR, 'mz'), ' s', 0)}")
print(' Zeilen, die der Filter volle Sekunde verwirft, obwohl Tempo-Genauigkeit über 0:')
all_sa = S.load(D, S.has_speed_accuracy)
off = [r for _, rows, _ in all_sa for r in rows if r[0] % 1000 != 0]
far = sum(min(r[0] % 1000, 1000 - r[0] % 1000) > 50 for r in off)
print(f"  {len(off)} von {sum(len(x[1]) for x in all_sa)}, davon mehr als 50 ms neben der vollen Sekunde {far}, Genauigkeit Median {st.median(r[3] for r in off):.1f} m")

print('\n# V6 Parameter: Pool des Hauptlaufs, gleiche Ziehung, jede Zeile gegen ihre Kontrolle mit denselben Parametern')
print('zeile: Scheinstrecke Median | Stopps ohne Pause Mittel (Anteil) | Mehrzeit Median')
for name, par in (('heute', ()), ('PAR-014 0,7 und 0,8', ('--standstill-below', '0.7')), ('PAR-014 0,8 und 0,8', ('--standstill-below', '0.8')),
                  ('PAR-014 1,0 und 1,2', ('--standstill-below', '1.0', '--movement-from', '1.2')),
                  ('PAR-002 und -003 aus', ('--hard-jump', '1e9', '--soft-jump', '1e9')), ('PAR-003 ab 5 m/s', ('--soft-jump', '5')),
                  ('PAR-004 5 s', ('--gap-s', '5')), ('PAR-015 5 s', ('--standstill-s', '5')), ('PAR-015 20 s', ('--standstill-s', '20'))):
    r = sim('parameter', 'par_' + name.replace(' ', '_').replace(',', ''), full, 'first', 10, MIX, par=par, mits=['keins'])['keins']
    print(f" {name}: {r['pct']:.2f} % | {r['u_mean']:.2f} ({100 * r['u_mean'] / int(STOPS):.1f} %) | {r['mz']:.1f} s")

# Einlauf ohne Simulation: Raten in m/min, bewusst ohne Umrechnung in Prozent (das wäre kein Wert der Regel).
print('\n# V7 Einlauf ohne Simulation (Raten m/min, kein Wert der Regel). Schritt zählt zu seinem Startpunkt, dt bis 10 s, Genauigkeit bis 25 m')


def dist(a, b):
    la = math.radians((a[1] + b[1]) / 2)
    return 6371000 * math.hypot(math.radians(b[1] - a[1]), math.radians(b[2] - a[2]) * math.cos(la))


def segs(rows):
    o = []
    for a, b in zip(rows, rows[1:]):
        dt = (b[0] - a[0]) / 1000
        if dt <= 0 or dt > 10 or a[3] > 25 or b[3] > 25:
            continue
        o.append((a[0], dist(a, b), dt))
    return o


def rate(g, zero, lo, hi):
    x = [e for e in g if lo <= (e[0] - zero) / 1000 < hi]
    t = sum(e[2] for e in x)
    return (60 * sum(e[1] for e in x) / t, t) if t else (None, 0)


off = sorted((rows[0][0] - start) / 1000 for start, rows, _ in full)
print(f' Erste GPS-Zeile nach StartTime: Median {q(off, .5):.1f} s, P90 {q(off, .9):.1f} s, Maximum {off[-1]:.0f} s')
G = {"first": [(rows[0][0], segs(rows)) for start, rows, _ in full]}
G['start'] = [(start, segs(rows)) for start, rows, _ in full]
G['sacc'] = [(rows[0][0], segs(rows)) for start, rows, _ in sacc]
for lab, key in (('volle Sekunde', 'first'), ('Tempo-Genauigkeit über 0', 'sacc')):
    for lo in (10, 15, 20):
        v = [rate(g, z, lo, 1e9) for z, g in G[key]]
        v = [a for a, t in v if t >= 4]
        d = sum(e[1] for z, g in G[key] for e in g if (e[0] - z) / 1000 >= lo)
        t = sum(e[2] for z, g in G[key] for e in g if (e[0] - z) / 1000 >= lo)
        print(f' {lab}, ab {lo} s nach erster GPS-Zeile: Median je Sitzung {st.median(v):.1f} (n={len(v)}), gepoolt {60 * d / t:.1f}')
rnd = random.Random(SEED)
for lab, key, bins in (('ab erster GPS-Zeile', 'first', [(10, 15), (15, 20), (20, 25)]), ('seit StartTime', 'start', [(10, 15), (15, 20), (20, 25), (25, 30)])):
    P = [(z, g) for z, g in G[key] if all(rate(g, z, *b)[1] >= 4 for b in bins)]
    M = [[rate(g, z, *b)[0] for b in bins] for z, g in P]
    print(f' Gleiche Sitzungen, gleich lange Fenster, {lab}, n={len(M)}: ' + ' / '.join(f'{b[0]}-{b[1]} s {st.median(m[i] for m in M):.1f}' for i, b in enumerate(bins)))
    for i in range(len(bins) - 1):
        d = [m[i] - m[i + 1] for m in M]
        boot = sorted(st.median(rnd.choices(d, k=len(d))) for _ in range(2000))
        print(f'  Differenz {bins[i]} minus {bins[i + 1]}: Median {st.median(d):.1f}, 95 % {boot[50]:.1f} bis {boot[1949]:.1f}')

with open(f'{OUT}/varianten.csv', 'w') as f:
    w = csv.DictWriter(f, fieldnames=list(rows_csv[0].keys()))
    w.writeheader()
    w.writerows(rows_csv)
