"""Lizenzbaum der Mini-Apps.
Dart: alle Pakete aus pubspec.lock (Zeilenparser); ausgeliefert = transitiver Abschluss der Nicht-Dev-Abhaengigkeiten
      laut `flutter pub deps --json`; Lizenz aus LICENSE-Datei im Pub-Cache, Pfad-Paket bzw. Flutter-SDK.
Gradle: releaseRuntimeClasspath der App; Lizenz aus <licenses> der POM (mit Eltern-POMs). Fehlt die POM im
      Gradle-Cache (Gradle laedt oft nur .module), wird sie einmalig von Google Maven bzw. Maven Central geholt
      und unter <work>/poms/ abgelegt (wenige kleine Anfragen, danach aus dem Ablageordner).
      io.flutter-Engine-Artefakte haben keine Lizenz in der POM: Lizenz = Flutter-Engine (BSD-3-Clause) mit Beleg.
Usage: licenses.py <apps-ordner> <out> <apps...>
Ausgabe: <out>/licenses_dart_<app>.tsv, licenses_gradle_<app>.tsv, licenses_summary.txt"""
import os, re, json, subprocess, sys, pathlib, collections, urllib.request, xml.etree.ElementTree as ET
apps_dir, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
PUB = pathlib.Path.home() / '.pub-cache/hosted/pub.dev'
GRADLE = pathlib.Path.home() / '.gradle/caches/modules-2/files-2.1'
POMS = apps_dir.parent / 'poms'; POMS.mkdir(exist_ok=True)
FLUTTER_ROOT = pathlib.Path(subprocess.run(['flutter', '--version', '--machine'], capture_output=True, text=True).stdout and
                            json.loads(subprocess.run(['flutter', '--version', '--machine'], capture_output=True, text=True).stdout)['flutterRoot'])
REPOS = ['https://dl.google.com/dl/android/maven2', 'https://repo1.maven.org/maven2']
fetch_log = []

def classify(t):
    t = re.sub(r'\s+', ' ', t)
    if 'Apache License' in t and 'Version 2.0' in t: return 'Apache-2.0'
    if 'GNU GENERAL PUBLIC LICENSE' in t.upper() and 'Version 3' in t: return 'GPL-3.0'
    if 'GNU LESSER' in t.upper(): return 'LGPL'
    if 'Mozilla Public License' in t: return 'MPL-2.0'
    if 'Permission is hereby granted, free of charge' in t: return 'MIT'
    if 'Redistribution and use in source and binary forms' in t:
        return 'BSD-3-Clause' if ('endorse or promote' in t) else 'BSD-2-Clause'
    if 'Permission to use, copy, modify, and/or distribute' in t: return 'ISC'
    if 'SIL OPEN FONT LICENSE' in t.upper(): return 'OFL-1.1'
    return 'UNBEKANNT'

GPL_OK = {'MIT', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', 'ISC', 'GPL-3.0', 'LGPL', 'MPL-2.0', 'OFL-1.1',
          'Zlib', 'CC0-1.0', 'Unicode', 'nicht-ausgeliefert'}

def parse_lock(text):
    """Einfacher Zeilenparser: Paket = Zeile mit 2 Leerzeichen Einzug unter 'packages:'."""
    pk, cur, sect = {}, None, None
    for line in text.splitlines():
        if not line.strip() or line.startswith('#'): continue
        if not line.startswith(' '): sect = line.rstrip(':'); continue
        if sect != 'packages': continue
        ind = len(line) - len(line.lstrip(' ')); k, _, v = line.strip().partition(':'); v = v.strip().strip('"')
        if ind == 2: cur = pk.setdefault(k, {'desc': {}})
        elif ind == 4 and k == 'description' and v: cur['desc'] = {'_': v}
        elif ind == 4: cur[k] = v
        elif ind == 6: cur['desc'][k] = v
    return pk

def shipped(app):
    d = json.loads(subprocess.run(['flutter', 'pub', 'deps', '--json'], cwd=apps_dir / app, capture_output=True, text=True).stdout)
    by = {p['name']: p for p in d['packages']}; root = d['root']
    todo, seen = list(by[root]['directDependencies']), set()
    while todo:
        n = todo.pop()
        if n in seen: continue
        seen.add(n); todo += by[n]['dependencies']
    return seen

def lic_file(d):
    for f in ('LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING', 'LICENSE.MIT'):
        if (d / f).exists(): return classify((d / f).read_text(errors='ignore')), str(d / f)
    return 'UNBEKANNT', str(d)

def dart(app):
    lock = parse_lock((apps_dir / app / 'pubspec.lock').read_text()); ship = shipped(app)
    rows = []
    for name, p in sorted(lock.items()):
        src, ver, dep = p.get('source'), p.get('version'), p.get('dependency')
        if src == 'sdk': d = FLUTTER_ROOT / 'packages' / name
        elif src == 'hosted': d = PUB / f'{name}-{ver}'
        elif src == 'path': d = (apps_dir / app / p['desc']['path']).resolve()
        else: d = pathlib.Path('/nonexistent')
        if name == 'sky_engine': d = FLUTTER_ROOT / 'bin/cache/pkg/sky_engine'
        lic, where = lic_file(d)
        if src == 'sdk' and lic == 'UNBEKANNT':  # SDK-Pakete ohne eigene LICENSE: Lizenz des Flutter-SDK
            lic, where = lic_file(FLUTTER_ROOT); lic += ' (Flutter-SDK)'
        if name == 'sky_engine': lic = 'BSD-3-Clause+ (Sammel-LICENSE der Engine, s. Bewertung)'
        rows.append((name, ver, dep, src, 'ja' if name in ship else 'nein (nur Test/Dev)', lic, where.replace(str(pathlib.Path.home()), '~')))
    return rows

def get_pom(g, a, v):
    loc = list((GRADLE / g / a / v).glob('*/*.pom'))
    if loc: return loc[0], 'gradle-cache'
    f = POMS / f'{g}__{a}__{v}.pom'
    if f.exists(): return f, 'ablage'
    for r in REPOS:
        url = f"{r}/{g.replace('.', '/')}/{a}/{v}/{a}-{v}.pom"
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'R008-licenses/1'}), timeout=20).read()
            f.write_bytes(data); fetch_log.append(url); return f, url
        except Exception as e:
            fetch_log.append(f'{url} -> {e}')
    return None, 'nicht gefunden'

def pom_licenses(g, a, v, depth=0):
    f, where = get_pom(g, a, v)
    if not f or depth > 5: return [], where
    root = ET.parse(f).getroot(); ns = root.tag.split('}')[0] + '}' if root.tag.startswith('{') else ''
    names = [(e.findtext(ns + 'name') or '').strip() + ('|' + (e.findtext(ns + 'url') or '').strip()) for e in root.findall(f'{ns}licenses/{ns}license')]
    if names: return names, where if depth == 0 else f'{where} (Eltern-POM {g}:{a}:{v})'
    p = root.find(ns + 'parent')
    if p is not None:
        return pom_licenses(p.findtext(ns + 'groupId'), p.findtext(ns + 'artifactId'), p.findtext(ns + 'version'), depth + 1)
    return [], where

def norm(names):
    s = ' '.join(names).lower()
    if not s: return 'UNBEKANNT'
    if 'apache' in s: return 'Apache-2.0'
    if 'bsd' in s and ('2-clause' in s or 'simplified' in s): return 'BSD-2-Clause'
    if 'bsd' in s: return 'BSD-3-Clause'
    if re.search(r'\bmit\b', s): return 'MIT'
    if 'android software development kit' in s: return 'Android-SDK-Lizenz (proprietaer)'
    if 'eclipse public' in s: return 'EPL'
    return 'ANDERE: ' + ' / '.join(names)

FLUTTER_ENGINE = 'BSD-3-Clause (Flutter-Engine; Beleg: $FLUTTER_ROOT/LICENSE, engine/LICENSE)'

def gradle(app):
    gw = apps_dir / app / 'android'
    r = subprocess.run(['./gradlew', '-q', ':app:dependencies', '--configuration', 'releaseRuntimeClasspath'], cwd=gw, capture_output=True, text=True)
    (out / f'gradle_deps_{app}.txt').write_text(r.stdout + r.stderr)
    arts = set()
    for line in r.stdout.splitlines():
        m = re.search(r'--- ([\w.\-]+):([\w.\-]+):([\w.\-]+)(?: -> ([\w.\-]+))?', line)
        if m and '(c)' not in line:
            g, a, v, v2 = m.groups(); arts.add((g, a, v2 or v))
    rows = []
    for g, a, v in sorted(arts):
        if g == 'io.flutter':
            rows.append((g, a, v, FLUTTER_ENGINE, 'Flutter-SDK')); continue
        names, where = pom_licenses(g, a, v)
        rows.append((g, a, v, norm(names), where + (' | ' + '; '.join(names) if names else '')))
    return rows

summary = []
for app in sys.argv[3:]:
    d = dart(app)
    with open(out / f'licenses_dart_{app}.tsv', 'w') as f:
        f.write('paket\tversion\tabhaengigkeit\tquelle\tausgeliefert\tlizenz\tbeleg\n')
        for r in d: f.write('\t'.join(map(str, r)) + '\n')
    gr = gradle(app)
    with open(out / f'licenses_gradle_{app}.tsv', 'w') as f:
        f.write('gruppe\tartefakt\tversion\tlizenz\tbeleg\n')
        for r in gr: f.write('\t'.join(r) + '\n')
    ds = [r for r in d if r[4] == 'ja']
    cd = collections.Counter(r[5].split(' ')[0] for r in ds); cg = collections.Counter(r[3].split(' ')[0] for r in gr)
    bad = [r[:2] + (r[5],) for r in ds if r[5].split(' ')[0].rstrip('+') not in GPL_OK] + [r[:4] for r in gr if r[3].split(' ')[0] not in GPL_OK]
    summary.append(f'{app}: Dart {len(d)} Pakete im Lock, {len(ds)} ausgeliefert {dict(cd)}; '
                   f'Gradle {len(gr)} Artefakte {dict(cg)}; zu pruefen: {bad}')
(out / 'licenses_summary.txt').write_text('\n'.join(summary) + '\n')
(out / 'pom_fetch.log').write_text('\n'.join(fetch_log) + '\n')
print('\n'.join(summary)); print(f'POM-Anfragen: {len(fetch_log)}')
