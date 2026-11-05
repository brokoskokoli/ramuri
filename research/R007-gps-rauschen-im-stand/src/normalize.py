#!/usr/bin/env python3
"""Normiert die Rohdaten für den Harness und schreibt Kennzahlen der Stand-Spuren.

Ausgabe <out>/norm/<quelle>__<sitzung>.tsv: t_ms lat lon acc speed sacc (leer = fehlt).
Nichts wird aus den Downloads ausgeführt; sie werden nur gelesen.
"""
import glob, math, os, random, re, sys, zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stueckel

D, OUT, SEED, MIX_SEED = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
NORM = os.path.join(OUT, 'norm')
os.makedirs(NORM, exist_ok=True)
FIXED_ACC = 5.0  # GGA/RMC melden keine Genauigkeit; Setzung, siehe README
R = 6371000.0  # nur für die Kennzahlen
info = []


def write(source, session, rows):
    if not rows:
        return
    with open(f'{NORM}/{source}__{session}.tsv', 'w') as f:
        f.write('t_ms\tlat\tlon\tacc\tspeed\tsacc\n')
        for r in rows:
            f.write('\t'.join('' if v is None else str(v) for v in r) + '\n')
    info.append((source, session, len(rows)))


def nmea_deg(v, hemi):
    v = float(v)
    d = int(v / 100)
    x = d + (v - d * 100) / 60
    return -x if hemi in 'SW' else x


def hms_ms(s):
    return int(s[0:2]) * 3600000 + int(s[2:4]) * 60000 + round(float(s[4:]) * 1000)


class Roll:
    """Tageswechsel in reinen Uhrzeiten."""
    def __init__(self):
        self.base = 0
        self.last = None

    def __call__(self, t):
        if self.last is not None and t < self.last - 3600000:
            self.base += 86400000
        self.last = t
        return t + self.base


# 1) Samsung, Stand, Dach, freie Sicht; GPGGA ohne Genauigkeit und ohne Tempo.
for path in sorted(glob.glob(f'{D}/zenodo-1312834/* Samsung Galaxy *.csv')):
    base = os.path.basename(path)[:-4]
    camp, model = base.split(' Samsung Galaxy ')
    model = model.replace(' ', '')
    roll = Roll()
    rows = []
    for l in open(path, errors='replace'):
        p = l.strip().split(';')
        if len(p) < 9 or not p[0].endswith('GGA') or p[6] == '0' or not p[2] or not p[1]:
            continue
        try:
            rows.append((roll(hms_ms(p[1])), nmea_deg(p[2], p[3]), nmea_deg(p[4], p[5]), FIXED_ACC, None, None))
        except ValueError:
            continue
    write(f'samsung_{model}', camp, rows)

# 2) OnePlus Nord 2T, Stativ, Dach, GNSSLogger: Fix,GPS (GPS_PROVIDER) mit Tempo.
root = f'{D}/mendeley-kybmdyrzb3-v1/x/NavICGNSS android raw measurments'


def gnsslogger_fixes(path):
    rows = []
    for l in open(path, errors='replace'):
        if not l.startswith('Fix,GPS,'):
            continue
        p = l.split(',')
        rows.append((int(p[8]), float(p[2]), float(p[3]), float(p[6]) if p[6] else FIXED_ACC,
                     float(p[5]) if p[5] else None, float(p[9]) if p[9] else None))
    rows.sort(key=lambda r: r[0])
    return rows


for f in sorted(glob.glob(f'{root}/1_Data with no inclination/*/gnss_log*.txt')):
    if '_rnx_' in f:
        continue
    write('oneplus_nord2t', os.path.basename(os.path.dirname(f)), gnsslogger_fixes(f))
for f in sorted(glob.glob(f'{root}/2_Data with inclination/*/gnss_log*.txt')):
    if '_rnx_' in f:
        continue
    write('oneplus_nord2t_neigung', os.path.basename(os.path.dirname(f)), gnsslogger_fixes(f))

# 3) 454 Sitzungen à 30 s: nur Zeilen auf der vollen Sekunde (Annahme, siehe README; Gegenrechnung in varianten.py).
nc_sessions = []
for start, rows, name in stueckel.load(D, stueckel.is_full_second):
    hw = 'unbekannt'
    for l in open(f'{D}/zenodo-20092798/x/nCount GNSS Data/{name}', errors='replace'):
        if l.startswith('# Hardware:'):
            hw = re.sub(r'[^a-zA-Z0-9]', '', l.split(':', 1)[1]) or 'unbekannt'
            break
    sid = re.search(r'gnss_(\d+)', name).group(1)
    write('ncount', f'{hw}-{sid}', rows)
    if len(rows) >= 20:
        nc_sessions.append((start, rows, name))

# 3b) Gestückelter Stand: je Sitzung nur der Teil ab 10 s nach der ersten GPS-Zeile, Inkremente aneinandergehängt.
# Übertragen, keine Messung am Stück. Seed der Mischung getrennt vom Seed der Ziehung im Harness.
out, used = stueckel.stitch(nc_sessions, stueckel.keep_after('first', 10), MIX_SEED)
write('ncount_stueckel', '1', out)
print('gestückelt:', used, 'Sitzungen,', len(out), 'Punkte, je Sitzung', round(len(out) / used, 1))

# 4) Gehen, Rad, Bus: NMEA-RMC der GNSSLogger-Spuren (Chip, 1 Hz, Tempo in Knoten).
def rmc(path):
    roll = Roll()
    rows = []
    for l in open(path, errors='replace'):
        m = l.split(',')
        if len(m) < 10 or not m[1].endswith('RMC') or m[3] != 'A' or not m[2] or not m[4] or not m[8]:
            continue
        try:
            rows.append((roll(hms_ms(m[2])), nmea_deg(m[4], m[5]), nmea_deg(m[6], m[7]), FIXED_ACC, float(m[8]) * 0.514444, None))
        except ValueError:
            continue
    return rows


MM = f'{D}/zenodo-14712684/x'
for mode in ['WALK', 'BIKE', 'BUS']:
    for n in sorted(glob.glob(f'{MM}/{mode}/*.nmea')):
        rows = rmc(n)
        write(f'walk_{mode.lower()}', os.path.basename(n)[9:28], rows)
        # Natürliche Stopps: mindestens 60 s Chip-Tempo 0 ohne Zeitsprung.
        i = 0
        k = 0
        while i < len(rows):
            if rows[i][4] != 0:
                i += 1
                continue
            j = i
            while j + 1 < len(rows) and rows[j + 1][4] == 0 and rows[j + 1][0] - rows[j][0] <= 2000:
                j += 1
            if rows[j][0] - rows[i][0] >= 60000:
                write(f'stopreal_{mode.lower()}', f'{k:03d}', rows[i:j + 1])
                k += 1
            i = j + 1

# 5) Synthetik: Worst Case und AR(1)-Raster (übertragen, keine Messung).
rnd = random.Random(SEED)
LAT0, LON0 = 48.0, 11.0
MPD = R * math.pi / 180
pm = [(i * 1000, LAT0 + (3 if i % 2 == 0 else -3) / MPD, LON0, 5.0, None, None) for i in range(3600)]
write('synth_pm3m', '1', pm)
for sigma in (1, 2, 3, 5, 8):
    for rho in (0.8, 0.9, 0.95, 0.98, 0.995):
        # sigma = Standardabweichung je Achse, rho = Autokorrelation je Sekunde.
        x = rnd.gauss(0, sigma)
        y = rnd.gauss(0, sigma)
        q = sigma * math.sqrt(1 - rho * rho)
        rows = []
        for i in range(7200):
            x = rho * x + rnd.gauss(0, q)
            y = rho * y + rnd.gauss(0, q)
            rows.append((i * 1000, LAT0 + y / MPD, LON0 + x / (MPD * math.cos(math.radians(LAT0))), 5.0, None, None))
        write(f'synth_ar1_s{sigma}_r{int(rho * 1000):03d}', '1', rows)

with open(os.path.join(OUT, 'norm_info.tsv'), 'w') as f:
    for r in info:
        f.write('\t'.join(map(str, r)) + '\n')
print(len(info), 'Sitzungen')
