"""Sucht Klartext-Signaturen in einem gezogenen App-Verzeichnis: OpenMapTiles-Ebenennamen (PBF), PNG, gzip, SQLite.
Usage: scan_plain.py <ordner>  Ausgabe: je Datei Groesse und Treffer, Summe."""
import os, sys
SIGS = {'pbf:transportation': b'transportation', 'pbf:landcover': b'landcover', 'png': b'\x89PNG', 'gzip': b'\x1f\x8b\x08', 'sqlite': b'SQLite format 3'}
tot, hit = 0, 0
for root, _, files in os.walk(sys.argv[1]):
    for f in files:
        p = os.path.join(root, f); b = open(p, 'rb').read(); tot += len(b)
        h = [n for n, s in SIGS.items() if s in b]
        if h: hit += 1
        print(f'{len(b):>10}  {",".join(h) or "-":<30} {os.path.relpath(p, sys.argv[1])}')
print(f'SUMME bytes={tot} dateien_mit_treffer={hit}')
