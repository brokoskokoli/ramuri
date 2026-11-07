"""Lizenzbaum der Mini-Apps. Dart: pubspec.lock + LICENSE-Dateien im Pub-Cache (bzw. Pfad-Paket).
Gradle: releaseRuntimeClasspath der App + <licenses> aus den POMs (mit Eltern-POMs) im Gradle-Cache.
Usage: licenses.py <apps-ordner> <out> <apps...>   Ausgabe: <out>/licenses_<app>.tsv und Zusammenfassung."""
import os, re, subprocess, sys, pathlib, collections, xml.etree.ElementTree as ET
apps_dir, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
PUB = pathlib.Path.home() / '.pub-cache/hosted/pub.dev'
GRADLE = pathlib.Path.home() / '.gradle/caches/modules-2/files-2.1'

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

GPL_OK = {'MIT', 'BSD-2-Clause', 'BSD-3-Clause', 'Apache-2.0', 'ISC', 'GPL-3.0', 'LGPL', 'MPL-2.0', 'OFL-1.1', 'Zlib', 'CC0-1.0', 'Unicode'}

def dart(app):
    lock = (apps_dir / app / 'pubspec.lock').read_text()
    rows = []
    for m in re.finditer(r'\n  (\S+):\n    dependency: "([^"]+)"\n    description:(.*?)\n    source: (\w+)\n    version: "([^"]+)"', lock, re.S):
        name, dep, desc, src, ver = m.groups()
        if src == 'sdk':
            rows.append((name, ver, dep, 'sdk', 'BSD-3-Clause (Flutter SDK)')); continue
        d = PUB / f'{name}-{ver}' if src == 'hosted' else (apps_dir / app / re.search(r'path: "([^"]+)"', desc).group(1)).resolve()
        lic = 'UNBEKANNT'
        for f in ('LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING'):
            if (d / f).exists():
                lic = classify((d / f).read_text(errors='ignore')); break
        rows.append((name, ver, dep, src, lic))
    return rows

def pom_licenses(g, a, v, depth=0):
    base = GRADLE / g / a / v
    poms = list(base.glob('*/*.pom'))
    if not poms or depth > 4: return []
    root = ET.parse(poms[0]).getroot()
    ns = {'m': root.tag.split('}')[0].strip('{')} if root.tag.startswith('{') else {'m': ''}
    q = (lambda p: p.replace('/', '/m:').replace('//m:', '//') if ns['m'] else p)
    names = [e.text.strip() for e in root.findall('.//' + ('m:' if ns['m'] else '') + 'licenses/' + ('m:' if ns['m'] else '') + 'license/' + ('m:' if ns['m'] else '') + 'name', ns) if e.text]
    if names: return names
    p = root.find(('m:' if ns['m'] else '') + 'parent', ns)
    if p is not None:
        f = lambda k: p.find(('m:' if ns['m'] else '') + k, ns).text
        return pom_licenses(f('groupId'), f('artifactId'), f('version'), depth + 1)
    return []

def norm(names):
    s = ' '.join(names).lower()
    if not s: return 'UNBEKANNT'
    if 'apache' in s: return 'Apache-2.0'
    if 'bsd' in s and '2' in s and '3' not in s: return 'BSD-2-Clause'
    if 'bsd' in s: return 'BSD-3-Clause'
    if 'mit' in s: return 'MIT'
    if 'android software development kit' in s or 'android sdk' in s: return 'Android-SDK-Lizenz (proprietaer)'
    if 'eclipse public' in s or 'epl' in s: return 'EPL'
    return 'ANDERE: ' + ' / '.join(names)

def gradle(app):
    gw = apps_dir / app / 'android'
    r = subprocess.run(['./gradlew', '-q', ':app:dependencies', '--configuration', 'releaseRuntimeClasspath'], cwd=gw, capture_output=True, text=True)
    (out / f'gradle_deps_{app}.txt').write_text(r.stdout + r.stderr)
    arts = set()
    for line in r.stdout.splitlines():
        m = re.search(r'--- ([\w.\-]+):([\w.\-]+):([\w.\-]+)(?: -> ([\w.\-]+))?', line)
        if m:
            g, a, v, v2 = m.groups(); arts.add((g, a, v2 or v))
    return [(g, a, v, norm(pom_licenses(g, a, v))) for g, a, v in sorted(arts)]

summary = []
for app in sys.argv[3:]:
    d = dart(app)
    with open(out / f'licenses_dart_{app}.tsv', 'w') as f:
        f.write('paket\tversion\tabhaengigkeit\tquelle\tlizenz\n')
        for r in d: f.write('\t'.join(r) + '\n')
    gr = gradle(app)
    with open(out / f'licenses_gradle_{app}.tsv', 'w') as f:
        f.write('gruppe\tartefakt\tversion\tlizenz\n')
        for r in gr: f.write('\t'.join(r) + '\n')
    cd = collections.Counter(r[4].split(' ')[0] for r in d); cg = collections.Counter(r[3] for r in gr)
    bad = [r for r in d if r[4].split(' ')[0] not in GPL_OK] + [r for r in gr if r[3] not in GPL_OK]
    summary.append(f'{app}: Dart {len(d)} Pakete {dict(cd)}; Gradle {len(gr)} Artefakte {dict(cg)}; zu pruefen: {bad}')
(out / 'licenses_summary.txt').write_text('\n'.join(summary) + '\n')
print('\n'.join(summary))
