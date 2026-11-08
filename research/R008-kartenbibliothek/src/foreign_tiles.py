"""Ordnet jede Datei eines Emulator-Abzugs (Benennung vor der HMAC-Umstellung) per URL-Hash zu und trennt die Vektorkacheln
nach "um die Route" und "um das Standardzentrum von flutter_map" (MapOptions.initialCenter = 50.5/30.51, Review 2, M1).
Nur Lesen, ohne Netz, ohne Entschluesseln. Usage: foreign_tiles.py <map-tiles-ordner> [LAT LON]  (Standard: Park der Route)
Ausgabe: je Klasse Anzahl und Klartextbytes (Dateigroesse - 28), dazu z/x/y."""
import hashlib, math, os, sys

d = sys.argv[1]
lat, lon = (float(sys.argv[2]), float(sys.argv[3])) if len(sys.argv) > 3 else (52.4731, 13.4031)
KIEW = (50.5, 30.51)
B = 'https://tiles.openfreemap.org'


def h(u):
    return hashlib.sha256(('http:' + u).encode()).hexdigest()


def tile(la, lo, z):
    n = 2 ** z
    return int((lo + 180) / 360 * n), int((1 - math.asinh(math.tan(math.radians(la))) / math.pi) / 2 * n)


cand = {}
for name, (la, lo) in {'route': (lat, lon), 'standardzentrum': KIEW}.items():
    for z in range(10, 15):
        x0, y0 = tile(la, lo, z)
        for x in range(x0 - 8, x0 + 9):
            for y in range(y0 - 8, y0 + 9):
                cand[h(f'{B}/planet/_/{z}/{x}/{y}.pbf')] = (f'vektor-{name}', f'{z}/{x}/{y}')
for z in range(0, 10):  # Raster und grobe Vektorkacheln: ganze Welt
    for x in range(2 ** z):
        for y in range(2 ** z):
            cand[h(f'{B}/natural_earth/ne2sr/{z}/{x}/{y}.png')] = ('raster', f'{z}/{x}/{y}')
            cand[h(f'{B}/planet/_/{z}/{x}/{y}.pbf')] = ('vektor-grob', f'{z}/{x}/{y}')
for u in ['/styles/liberty', '/planet', '/natural_earth', '/sprites/ofm_f384/ofm.json', '/sprites/ofm_f384/ofm.png',
          '/sprites/ofm_f384/ofm@2x.json', '/sprites/ofm_f384/ofm@2x.png']:
    cand[h(B + u)] = ('stil', u)
for font in ['Noto Sans Regular', 'Noto Sans Bold', 'Noto Sans Italic']:
    for s in range(0, 65536, 256):
        for f in (font, font.replace(' ', '%20')):
            cand[h(f'{B}/fonts/{f}/{s}-{s + 255}.pbf')] = ('stil', f'font {font} {s}')
res = {}
for f in sorted(os.listdir(d)):
    if not f.endswith('.bin'):
        continue
    c, t = cand.get(f[:-4], ('ungeklaert', f[:12]))
    res.setdefault(c, []).append((t, os.path.getsize(os.path.join(d, f)) - 28))
tot = sum(s for v in res.values() for _, s in v)
print(f'dateien={sum(len(v) for v in res.values())} klartextbytes={tot}')
for c, v in sorted(res.items()):
    b = sum(s for _, s in v)
    print(f'{c:<24} n={len(v):>3} bytes={b:>8} ({b / tot * 100:.1f} %)')
    for t, s in sorted(v):
        print(f'    {t:<30} {s}')
