"""Kachelkoordinaten (z/x/y) um einen Punkt: z14 und z13 je 2x2 um die naechste Kachelecke, z12 eine. Usage: tiles_for.py LAT LON"""
import math, sys
lat, lon = float(sys.argv[1]), float(sys.argv[2])
def tile(z, lat, lon):
    n = 2 ** z
    x = (lon + 180) / 360 * n
    r = math.radians(lat)
    y = (1 - math.asinh(math.tan(r)) / math.pi) / 2 * n
    return x, y
out = []
for z in (14, 13):
    x, y = tile(z, lat, lon)
    x0, y0 = int(round(x)) - 1, int(round(y)) - 1  # 2x2 um die naechste Kachelecke
    out += [f"{z}/{x0 + i}/{y0 + j}" for i in range(2) for j in range(2)]
for z in (12,):
    x, y = tile(z, lat, lon)
    out.append(f"{z}/{int(x)}/{int(y)}")
print(" ".join(out))
