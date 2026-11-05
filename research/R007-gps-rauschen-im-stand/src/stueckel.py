"""Stückelung der 30-s-Sitzungen (nCount): einzige Stelle, die den gestückelten Pool baut.

Genutzt von normalize.py (Hauptlauf) und varianten.py (Spannen). Eine Sitzung ist (start_ms, rows, name),
rows = (t_ms, lat, lon, acc, speed, sacc), zeitlich sortiert.
"""
import glob, math, os, random, re


def load(root, crit):
    """Alle Sitzungen; crit(zeile_als_liste) entscheidet, welche FIX-Zeile als GPS zählt."""
    out = []
    for f in sorted(glob.glob(f'{root}/zenodo-20092798/x/nCount GNSS Data/*.txt')):
        start = None
        rows = []
        for l in open(f, errors='replace'):
            if l.startswith('# StartTime:'):
                start = int(l.split(':')[1])
            if l.startswith('FIX,'):
                p = l.strip().split(',')
                if len(p) == 10 and crit(p):
                    rows.append((int(p[1]), float(p[2]), float(p[3]), float(p[5]), float(p[6]), float(p[9])))
        rows.sort()
        out.append((start, rows, os.path.basename(f)))
    return out


def is_full_second(p):
    """Hauptdefinition: FIX-Zeile auf der vollen Sekunde. Annahme, siehe README."""
    return int(p[1]) % 1000 == 0


def has_speed_accuracy(p):
    """Gegenrechnung: FIX-Zeile mit Tempo-Genauigkeit über 0."""
    return float(p[9]) > 0


def keep_after(axis, cut_s):
    """Zeilenauswahl: axis 'first' = ab cut_s nach der ersten GPS-Zeile, 'start' = nach StartTime."""
    if axis == 'first':
        return lambda r, rows, start: r[0] - rows[0][0] >= cut_s * 1000
    return lambda r, rows, start: r[0] - start >= cut_s * 1000


def stitch(sessions, keep, mix_seed, resample=False, spans=None):
    """Hängt die Inkremente aneinander. Die Reihenfolge hängt nur an mix_seed.

    An der Naht entsteht kein Punkt und kein Zeitschritt: Das erste Stück beginnt mit seinem ersten Punkt,
    jedes weitere setzt mit seinem ersten Inkrement am letzten Punkt fort. Nicht steigende Zeiten
    (Dubletten in den Rohdaten) werden übersprungen. resample=True zieht die Sitzungen mit Zurücklegen.
    Rückgabe: Zeilen, Zahl der genutzten Sitzungen. spans (Liste) sammelt je Sitzung (Name, erster Index, Ende) im Ergebnis.
    """
    rnd = random.Random(mix_seed)
    ss = list(sessions)
    if resample:
        ss = rnd.choices(ss, k=len(ss))
    else:
        rnd.shuffle(ss)
    la, lo, t = 48.0, 11.0, 0
    out = []
    used = 0
    for start, rows, name in ss:
        use = [r for r in rows if keep(r, rows, start) and r[3] <= 25]
        if len(use) < 5:
            continue
        used += 1
        first = len(out)
        if not out:
            t += 1000
            out.append((t, la, lo, use[0][3], use[0][4], use[0][5]))
        for a, b in zip(use, use[1:]):
            if b[0] <= a[0]:
                continue
            c = math.cos(math.radians(a[1]))
            la += b[1] - a[1]
            lo += (b[2] - a[2]) * c / math.cos(math.radians(48.0))
            t += b[0] - a[0]
            out.append((t, la, lo, b[3], b[4], b[5]))
        if spans is not None:
            spans.append((name, first, len(out)))
    return out, used


def write_tsv(path, rows):
    with open(path, 'w') as f:
        f.write('t_ms\tlat\tlon\tacc\tspeed\tsacc\n')
        for r in rows:
            f.write('\t'.join('' if v is None else str(v) for v in r) + '\n')
