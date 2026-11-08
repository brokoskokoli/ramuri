"""Probe (Befund M2 Review 1): Verraten die Dateinamen des verschluesselten Kachelspeichers die Kacheln?
Alte Benennung der Mini-Apps: Dateiname = SHA-256('http:' + URL ohne Datumspfad) + '.bin', ohne Schluessel.
Wer nur das Dateisystem sieht, kann Kandidaten-URLs hashen und vergleichen. Diese Probe macht genau das,
ohne Netz: Kachel-URLs fuer z0-z9 vollstaendig und z10-z14 in einem Fenster um einen Punkt.
Usage: name_leak.py <ordner mit *.bin> LAT LON [FENSTER=7]
Ausgabe: Anzahl Dateien, Anzahl per Hash zugeordneter Dateien, die zugeordneten z/x/y."""
import hashlib, math, os, sys

d, lat, lon = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
win = int(sys.argv[4]) if len(sys.argv) > 4 else 7
names = {f[:-4] for f in os.listdir(d) if f.endswith('.bin')}
base = 'http:https://tiles.openfreemap.org/planet/_/'


def tile(z):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    y = (1 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2 * n
    return int(x), int(y)


cand = {}
for z in range(0, 15):
    n = 2 ** z
    if z <= 9:
        xs, ys = range(n), range(n)
    else:
        x0, y0 = tile(z)
        xs = range(max(0, x0 - win // 2), min(n, x0 + win // 2 + 1))
        ys = range(max(0, y0 - win // 2), min(n, y0 + win // 2 + 1))
    for x in xs:
        for y in ys:
            k = f'{base}{z}/{x}/{y}.pbf'
            cand[hashlib.sha256(k.encode()).hexdigest()] = f'{z}/{x}/{y}'
hit = sorted(cand[h] for h in names if h in cand)
print(f'dateien={len(names)} kandidaten={len(cand)} zugeordnet={len(hit)}')
for t in hit:
    print('  ', t)
