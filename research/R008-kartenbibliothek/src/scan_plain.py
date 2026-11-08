"""Sucht Klartext-Signaturen in einem gezogenen App-Verzeichnis: OpenMapTiles-Ebenennamen (PBF), PNG, gzip, SQLite.
gzip zaehlt nur, wenn ein Streaming-Inflate ab einer Signatur tatsaechlich Ausgabe liefert (Anhang erlaubt): Die 3-Byte-Signatur
steht in Zufallsdaten etwa einmal je 16 MiB (Review R008 Runde 2, Befund 3). Im Fehlalarm-Fall steht die Signatur ohne Ausgabe
als gzip-sig in Klammern hinter der Datei.
Usage: scan_plain.py <ordner>  Ausgabe: je Datei Groesse und Treffer, Summe."""
import os, sys, zlib
SIGS = {'pbf:transportation': b'transportation', 'pbf:landcover': b'landcover', 'png': b'\x89PNG', 'sqlite': b'SQLite format 3'}
GZ = b'\x1f\x8b\x08'


def gzip_output(b):
    """(echte Treffer, Signaturen ohne Ausgabe)"""
    real, sig, i = 0, 0, b.find(GZ)
    while i >= 0:
        try:
            out = zlib.decompressobj(31).decompress(b[i:i + 1 << 20])
        except zlib.error:
            out = b''
        if out:
            real += 1
        else:
            sig += 1
        i = b.find(GZ, i + 1)
    return real, sig


if __name__ == '__main__':
    tot, hit = 0, 0
    for root, _, files in os.walk(sys.argv[1]):
        for f in files:
            p = os.path.join(root, f); b = open(p, 'rb').read(); tot += len(b)
            h = [n for n, s in SIGS.items() if s in b]
            real, sig = gzip_output(b)
            if real: h.append('gzip')
            if h: hit += 1
            note = f' (gzip-sig ohne Ausgabe: {sig})' if sig else ''
            print(f'{len(b):>10}  {",".join(h) or "-":<30} {os.path.relpath(p, sys.argv[1])}{note}')
    print(f'SUMME bytes={tot} dateien_mit_treffer={hit}')
