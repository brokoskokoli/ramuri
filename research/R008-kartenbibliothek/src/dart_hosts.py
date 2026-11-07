"""Fest eingebaute Hosts in den Quellen der ausgelieferten Dart-Pakete (lib/, ohne Kommentarzeilen).
Usage: dart_hosts.py <app-ordner>   Ausgabe: host <TAB> pakete"""
import re, subprocess, sys, pathlib, collections
here = pathlib.Path(__file__).parent
rows = subprocess.run([sys.executable, str(here / 'shipped_pkgs.py'), sys.argv[1]], capture_output=True, text=True).stdout.split('\n')
hosts = collections.defaultdict(set)
for r in rows:
    if not r.strip(): continue
    name, ver, d = r.split(' ', 2)
    for f in pathlib.Path(d, 'lib').rglob('*.dart'):
        for line in f.read_text(errors='ignore').splitlines():
            if line.strip().startswith('//'): continue
            for h in re.findall(r'https?://([A-Za-z0-9.-]+)', line):
                hosts[h].add(name)
for h in sorted(hosts): print(f'{h}\t{",".join(sorted(hosts[h]))}')
