#!/usr/bin/env python3
"""Wertet den Harness aus. Nur Standardbibliothek; keine Daten werden verändert."""
import collections, csv, glob, math, os, random, statistics as st, sys

OUT, SPEED, TOTAL, STOP, STOPS, SEED = sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
RUN_M = SPEED * (TOTAL - STOP * STOPS)
LIMIT = RUN_M * 0.01
R = 6371000.0
rnd = random.Random(SEED)
print(f'Laufstrecke {RUN_M:.0f} m, Grenze 1 % = {LIMIT:.1f} m, je Stopp {LIMIT / STOPS:.1f} m (Setzung Maintainer)')
print('Kontrolle:', open(f'{OUT}/control.txt').read().strip())


def q(v, p):
    v = sorted(v)
    if not v:
        return float('nan')
    x = p * (len(v) - 1)
    i = int(x)
    return v[i] if i + 1 >= len(v) else v[i] + (v[i + 1] - v[i]) * (x - i)


def num(s):
    return None if s == '' else float(s)


# A) Kennzahlen der normierten Spuren
sessions = collections.defaultdict(list)
for f in sorted(glob.glob(f'{OUT}/norm/*.tsv')):
    src, sess = os.path.basename(f)[:-4].split('__')
    rows = []
    with open(f) as h:
        next(h)
        for l in h:
            p = l.rstrip('\n').split('\t')
            rows.append((float(p[0]), float(p[1]), float(p[2]), float(p[3]), num(p[4]), num(p[5])))
    sessions[src].append((sess, rows))

print('\n# A Stand- und Gehspuren: Kennzahlen je Quelle (dt<=2 s, 120 s Einlauf übersprungen außer ncount, stopreal)')
print('quelle sitz n s_median_kein_versatz_% v_p50 v_p90 v_p99 v<0.5_% m/min sigma_m rho1 getSpeed=0_% sp_p90 sp>=0.5_% sp>=0.8_% acc_p50 acc>25_%')
for src, sl in sessions.items():
    if src.startswith('synth_ar1'):
        continue
    v, same, sp, acc = [], 0, [], []
    sig, rho = [], []
    dur = 0.0
    dist = 0.0
    for _, rows in sl:
        t0 = rows[0][0]
        burn = 0 if src in ('ncount',) or src.startswith('stopreal') else 120000
        rs = [r for r in rows if r[0] - t0 >= burn]
        if len(rs) < 5:
            continue
        la = st.mean(r[1] for r in rs)
        lo = st.mean(r[2] for r in rs)
        k = R * math.pi / 180
        ex = [(r[2] - lo) * k * math.cos(math.radians(la)) for r in rs]
        ny = [(r[1] - la) * k for r in rs]
        if len(rs) > 300:
            for e in (ex, ny):
                s = st.pstdev(e)
                sig.append(s)
                if s > 0:
                    rho.append(sum(a * b for a, b in zip(e, e[1:])) / (len(e) * s * s))
        for i, (a, b) in enumerate(zip(rs, rs[1:])):
            dt = (b[0] - a[0]) / 1000
            if dt <= 0 or dt > 2:
                continue
            d = math.hypot(ex[i + 1] - ex[i], ny[i + 1] - ny[i])
            v.append(d / dt)
            dist += d
            dur += dt
            if d == 0:
                same += 1
        sp += [r[4] for r in rs if r[4] is not None]
        acc += [r[3] for r in rs]
    if not v:
        continue
    print(src, len(sl), len(v), f'{100 * same / len(v):.1f} {q(v, .5):.3f} {q(v, .9):.3f} {q(v, .99):.3f} {100 * sum(x < .5 for x in v) / len(v):.1f} {60 * dist / dur:.2f}',
          f'{st.median(sig):.2f} {st.median(rho):.3f}' if sig and rho else 'na na',
          (f'{100 * sum(x == 0 for x in sp) / len(sp):.1f} {q(sp, .9):.3f} {100 * sum(x >= .5 for x in sp) / len(sp):.1f} {100 * sum(x >= .8 for x in sp) / len(sp):.1f}' if sp else 'na na na na'),
          f'{q(acc, .5):.1f} {100 * sum(a > 25 for a in acc) / len(acc):.1f}')

# B) Laufsimulation
runs = collections.defaultdict(list)
for r in csv.DictReader(open(f'{OUT}/runs.csv')):
    runs[(r['source'], r['mitigation'])].append(r)
stops = collections.defaultdict(list)
for r in csv.DictReader(open(f'{OUT}/stops.csv')):
    stops[(r['source'], r['mitigation'])].append(r)

print('\n# B Lauf simuliert: Quelle x Gegenmittel')
print('quelle mittel L unpaused_med unpaused_mean P(stopp_ohne_pause)_% schein_med_m schein_mean schein_p90 schein_med_% moving_ueber_med_s moving_ueber_%_von_ctrl disterr_med anteil_in_pause_% resumes/stopp disc_acc disc_soft disc_hard FLAG')
ctrl = 1641.0
try:
    ctrl = float(open(f'{OUT}/control.txt').read().split('moving_s=')[1].split()[0])
except Exception:
    pass
for (src, m), rs in sorted(runs.items()):
    u = [float(r['unpaused']) for r in rs]
    sh = [float(r['sham_stop_m']) for r in rs]
    me = [float(r['moving_excess_s']) for r in rs]
    de = [float(r['dist_err_m']) for r in rs]
    ss = stops[(src, m)]
    pu = sum(r['paused'] == '0' for r in ss) / len(ss)
    ip = sum(float(r['sham_in_pause_m']) for r in ss) / max(1e-9, sum(float(r['sham_m']) for r in ss))
    res = sum(int(float(r['resumes'])) for r in ss) / len(ss)
    fl = []
    if st.median(u) > 1:
        fl.append('STOPPS')
    if st.median(sh) > LIMIT:
        fl.append('STRECKE')
    if st.mean(sh) > LIMIT and st.median(sh) <= LIMIT:
        fl.append('(mittel>1%)')
    print(src, m, len(rs), f'{st.median(u):.1f} {st.mean(u):.2f} {100 * pu:.1f} {st.median(sh):.1f} {st.mean(sh):.1f} {q(sh, .9):.1f} {100 * st.median(sh) / RUN_M:.2f} {st.median(me):.1f} {100 * st.median(me) / ctrl:.2f} {st.median(de):.1f} {100 * ip:.0f} {res:.3f}',
          sum(int(r['disc_acc']) for r in ss), sum(int(r['disc_soft']) for r in ss), sum(int(r['disc_hard']) for r in ss), ','.join(fl) or '-')

print('\n# B2 Je Sitzung (nur keins, ohne Synthetik): Stopps ohne Pause und Schein je Stopp')
ag = collections.defaultdict(list)
for (src, m), ss in stops.items():
    if m != 'keins' or src.startswith('synth'):
        continue
    for r in ss:
        ag[(src, r['session'])].append((r['paused'] == '0', float(r['sham_m'])))
for k, v in sorted(ag.items()):
    print(k[0], k[1], len(v), f'P(ohne)={100 * sum(a for a, _ in v) / len(v):.1f}% schein_med={st.median(b for _, b in v):.2f} p90={q([b for _, b in v], .9):.2f}')

# C) Langsame Bewegung
print('\n# C Echtes Tempo plus echtes Standrauschen (nur Samsung, OnePlus): moving-Anteil, falsche Pausen je 5 min, Streckenverhältnis')
sl = collections.defaultdict(list)
for r in csv.DictReader(open(f'{OUT}/slow.csv')):
    if r['source'].startswith('synth'):
        continue
    sl[(r['mitigation'], float(r['v']))].append(r)
for (m, v), rs in sorted(sl.items()):
    print(m, v, len(rs), f"mov_med={st.median(float(r['moving_share']) for r in rs):.3f} pausen_mean={st.mean(float(r['false_pauses']) for r in rs):.2f} ratio_med={st.median(float(r['dist_ratio']) for r in rs):.3f}")

# D) Spuren einzeln
tr = list(csv.DictReader(open(f'{OUT}/traces.csv')))
print('\n# D1 Gehen, Rad, Bus, natürliche Stopps')
for r in tr:
    if r['source'].startswith(('walk', 'stopreal')):
        print(r['source'], r['session'], r['mitigation'], f"dauer={r['dur_s']} strecke={r['dist_m']} integral={r['integral_m']} moving={r['moving_s']} pausen={r['pauses']} disc_soft={r['disc_soft']} disc_hard={r['disc_hard']} gaps={r['gaps']}")

print('\n# D2 ncount (30 s je Sitzung, viele Geräte, Bedingungen unbekannt, ohne Einlauf)')
nc = collections.defaultdict(list)
for r in tr:
    if r['source'] == 'ncount':
        nc[r['mitigation']].append(r)
hw_of = lambda s: s.split('-')[0]
for m, rs in sorted(nc.items()):
    rate = [60 * float(r['dist_m']) / float(r['dur_s']) for r in rs if float(r['dur_s']) >= 15]
    np_ = [float(r['pauses']) == 0 for r in rs if float(r['dur_s']) >= 15]
    print(m, f'n={len(rate)} m/min_med={q(rate, .5):.2f} p75={q(rate, .75):.2f} p90={q(rate, .9):.2f} rate>{LIMIT / STOPS:.1f}_%={100 * sum(x > LIMIT / STOPS for x in rate) / len(rate):.1f} ohne_pause_%={100 * sum(np_) / len(np_):.1f}')
hw = collections.defaultdict(list)
for r in nc.get('keins', []):
    if float(r['dur_s']) >= 15:
        hw[hw_of(r['session'])[:3]].append(60 * float(r['dist_m']) / float(r['dur_s']))
for h, v in sorted(hw.items(), key=lambda kv: -len(kv[1])):
    print(' hw', h, len(v), f'm/min_med={q(v, .5):.2f} p90={q(v, .9):.2f}')
# Sprünge in der Stand-Spur der 454
ncs = sessions.get('ncount', [])
n = sum(len(r) for _, r in ncs)
sp = [x[4] for _, r in ncs for x in r]
sa = [x[5] for _, r in ncs for x in r]
print(f' Zeilen {n}: speed=0 {100 * sum(x == 0 for x in sp) / n:.1f}%, speedAcc=0 {100 * sum(x == 0 for x in sa) / n:.1f}%, speed>=0.5 {100 * sum(x >= .5 for x in sp) / n:.1f}%, speed>=0.8 {100 * sum(x >= .8 for x in sp) / n:.1f}%')

# E) ncount im Detail: Einlauf gegen späteren Teil der 30 s
print('\n# E ncount: Rate früh gegen spät, nach Genauigkeit und Sprüngen (nur Sitzungen mit mindestens 20 GPS-Zeilen)')
k = R * math.pi / 180
def seg(rows):
    out = []
    for a, b in zip(rows, rows[1:]):
        dt = (b[0] - a[0]) / 1000
        if dt <= 0 or dt > 10 or a[3] > 25 or b[3] > 25:
            continue
        out.append((math.hypot((b[1] - a[1]) * k, (b[2] - a[2]) * k * math.cos(math.radians(a[1]))), dt, b[4], (a[0] - rows[0][0]) / 1000))
    return out
sess = [(n, r, seg(r)) for n, r in sessions.get('ncount', []) if len(r) >= 20]
print(' Sitzungen', len(sess))
def rate(x):
    t = sum(s[1] for s in x)
    return 60 * sum(s[0] for s in x) / t if t else float('nan')
early = [rate([s for s in g if s[3] < 10]) for _, _, g in sess]
late = [rate([s for s in g if s[3] >= 10]) for _, _, g in sess]
for name, v in (('erste 10 s', early), ('ab 10 s', late)):
    v = [x for x in v if x == x]
    print(f' {name}: m/min med={q(v, .5):.1f} p25={q(v, .25):.1f} p75={q(v, .75):.1f} p90={q(v, .9):.1f}, >16.2: {100 * sum(x > 16.2 for x in v) / len(v):.1f}% (n={len(v)})')
med_step = [st.median(s[0] / s[1] for s in g) for _, _, g in sess if g]
print(f' Median je Sitzung der Stufen in m/s: med={q(med_step, .5):.2f} p25={q(med_step, .25):.2f} p75={q(med_step, .75):.2f} p90={q(med_step, .9):.2f}')
# Ohne einzelne Sprünge: Rate aus der Summe der Schritte bis 5 m/s
clean = [rate([s for s in g if s[0] / s[1] <= 5 and s[3] >= 10]) for _, _, g in sess]
clean = [x for x in clean if x == x]
print(f' ab 10 s ohne Stufen über 5 m/s: med={q(clean, .5):.1f} p75={q(clean, .75):.1f} p90={q(clean, .9):.1f}, >16.2: {100 * sum(x > 16.2 for x in clean) / len(clean):.1f}%')
# Pause möglich ab 10 s: 10 Stufen unter 0,5 m/s hintereinander
def has_run(g):
    n = 0
    for s in g:
        n = n + s[1] if s[0] / s[1] < 0.5 else 0
        if n >= 10:
            return True
    return False
print(f' Sitzungen mit mindestens einem 10-s-Lauf unter 0,5 m/s: {100 * sum(has_run(g) for _, _, g in sess) / len(sess):.1f}%')
acc_med = [(st.median(x[3] for x in r), rate(g)) for _, r, g in sess if g]
for lo, hi in ((0, 3), (3, 5), (5, 10), (10, 1000)):
    v = [b for a, b in acc_med if lo <= a < hi]
    if v:
        print(f' Median-Genauigkeit {lo}-{hi} m: n={len(v)} m/min med={q(v, .5):.1f} p90={q(v, .9):.1f}')
# Tempo gegen Stufe
both = [(s[0] / s[1], s[2]) for _, _, g in sess for s in g if s[2] is not None]
print(f' Stufen n={len(both)}: Δs/Δt>=0,5: {100 * sum(a >= .5 for a, _ in both) / len(both):.1f}%, getSpeed>=0,5: {100 * sum(b >= .5 for _, b in both) / len(both):.1f}%, beide: {100 * sum(a >= .5 and b >= .5 for a, b in both) / len(both):.1f}%')
print(f' Anteil getSpeed exakt 0: {100 * sum(b == 0 for _, b in both) / len(both):.1f}%; davon Δs/Δt>=0,5: {100 * sum(a >= .5 and b == 0 for a, b in both) / max(1, sum(b == 0 for _, b in both)):.1f}%')

# F) Natürliche Stopps: bestes und schlechtestes 60-s-Fenster, Nettoversatz
print('\n# F Natürliche Stopps')
for src in ('stopreal_walk', 'stopreal_bus'):
    for n, r in sessions.get(src, []):
        s = seg(r)
        roll = [sum(x[0] for x in s[i:i + 60]) for i in range(0, max(1, len(s) - 59))]
        net = math.hypot((r[-1][1] - r[0][1]) * k, (r[-1][2] - r[0][2]) * k * math.cos(math.radians(r[0][1])))
        print(f' {src} {n}: Dauer {len(r)} s, Weg {sum(x[0] for x in s):.1f} m, netto {net:.1f} m, 60-s-Fenster min={min(roll):.1f} med={st.median(roll):.1f} max={max(roll):.1f} m, Grenze je Stopp {LIMIT / STOPS:.1f}')

# G) Gehspur: Pausen in der Gehspur gegen Chip-Tempo
print('\n# G Gehspur: Abschnitte ab 10 s mit Δs/Δt unter 0,5 m/s und ihr Chip-Tempo')
for n, r in sessions.get('walk_walk', []):
    s = seg(r)
    i = 0
    while i < len(s):
        if s[i][0] / s[i][1] >= .5:
            i += 1
            continue
        j = i
        while j < len(s) and s[j][0] / s[j][1] < .5:
            j += 1
        if j - i >= 10:
            sp = [x[2] for x in s[i:j]]
            print(f'  t={s[i][3]:.0f} s, Dauer {j - i} s, Chip-Tempo Mittel {st.mean(sp):.2f} max {max(sp):.2f} m/s, Weg {sum(x[0] for x in s[i:j]):.1f} m')
        i = j
    # Umgekehrt: Chip-Tempo durchgehend 0 ab 15 s, und löst Δs/Δt dort aus?
    i = 0
    while i < len(s):
        if s[i][2] != 0:
            i += 1
            continue
        j = i
        while j < len(s) and s[j][2] == 0:
            j += 1
        if j - i >= 15:
            print(f'  Chip 0: t={s[i][3]:.0f} s, Dauer {j - i} s, 10-s-Lauf unter 0,5 m/s: {has_run(s[i:j])}, Weg {sum(x[0] for x in s[i:j]):.1f} m')
        i = j
    sp = [x[2] for x in s]
    d = [x[0] / x[1] for x in s]
    print(f'  Gesamt: Chip-Tempo Median {st.median(sp):.2f}, Stufe Median {st.median(d):.2f}, |Stufe-Tempo| Median {st.median(abs(a - b) for a, b in zip(d, sp)):.3f}, p90 {q([abs(a - b) for a, b in zip(d, sp)], .9):.3f} m/s')

# H) Lücken in den Stand-Sitzungen (die Fensterwahl schließt sie aus)
print('\n# H PAR-001, PAR-002, PAR-003, PAR-004 in ganzen Stand-Sitzungen (keins)')
agg = collections.defaultdict(lambda: [0, 0, 0, 0, 0, 0.0])
for r in tr:
    if r['mitigation'] != 'keins' or r['source'].startswith('synth'):
        continue
    a = agg[r['source']]
    a[0] += int(r['n']); a[1] += int(r['disc_acc']); a[2] += int(r['disc_hard']); a[3] += int(r['disc_soft']); a[4] += int(r['gaps']); a[5] += float(r['dur_s'])
for s, a in sorted(agg.items()):
    print(f' {s}: Punkte {a[0]}, Stunden {a[5] / 3600:.1f}, acc {a[1]}, hart {a[2]}, weich {a[3]}, Lücken {a[4]}')
