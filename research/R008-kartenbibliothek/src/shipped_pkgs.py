"""Gibt je ausgeliefertem Dart-Paket einer App (Abschluss der Nicht-Dev-Abhaengigkeiten laut `flutter pub deps --json`)
Name, Version und Quellordner aus. Usage: shipped_pkgs.py <app-ordner>"""
import json, subprocess, sys, pathlib
app = pathlib.Path(sys.argv[1]); PUB = pathlib.Path.home() / '.pub-cache/hosted/pub.dev'
d = json.loads(subprocess.run(['flutter', 'pub', 'deps', '--json'], cwd=app, capture_output=True, text=True).stdout)
by = {p['name']: p for p in d['packages']}
todo, seen = list(by[d['root']]['directDependencies']), set()
while todo:
    n = todo.pop()
    if n not in seen: seen.add(n); todo += by[n]['dependencies']
lock = (app / 'pubspec.lock').read_text().splitlines()
paths = {}  # Pfad-Pakete: Ordner aus dem Lock
cur = None
for l in lock:
    if l.startswith('  ') and not l.startswith('   '): cur = l.strip().rstrip(':')
    if l.strip().startswith('path:') and cur: paths[cur] = (app / l.split(':', 1)[1].strip().strip('"')).resolve()
for n in sorted(seen):
    p = by[n]
    if p['source'] == 'hosted': print(n, p['version'], PUB / f"{n}-{p['version']}")
    elif p['source'] == 'path': print(n, p['version'], paths.get(n, '?'))
