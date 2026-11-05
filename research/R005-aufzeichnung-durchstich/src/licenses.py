#!/usr/bin/env python3
"""Lizenzbaum des Prototyps: Dart (flutter pub deps --json + LICENSE im Pub-Cache), Gradle (POM-Lizenzen), native .so der APK.
Aufruf: licenses.py <proto-dir> <out-dir> . Schreibt licenses.tsv und gradle-*.txt; druckt Zusammenfassung und alle Treffer, die nicht klar permissiv sind."""
import json,os,re,subprocess,sys,glob,zipfile,urllib.request,xml.etree.ElementTree as ET
proto,out=sys.argv[1:3]
PUB=os.path.expanduser(os.environ.get('PUB_CACHE','~/.pub-cache'))
GC=os.path.expanduser('~/.gradle/caches/modules-2/files-2.1')
def classify(t):
    t2=re.sub(r'\s+',' ',t)
    if 'Mozilla Public License' in t2: return 'MPL-2.0'
    if re.search(r'GNU (LESSER|AFFERO)? ?GENERAL PUBLIC',t2,re.I): return 'GPL-Familie'
    if 'Apache License' in t2 and 'Version 2.0' in t2: return 'Apache-2.0'
    if 'Mozilla Public License' in t2: return 'MPL-2.0'
    if 'Redistribution and use in source and binary forms' in t2:
        return 'BSD-3-Clause' if re.search(r'Neither the name|names? of (its|the) contributors',t2) else 'BSD-2-Clause'
    if 'Permission is hereby granted, free of charge' in t2: return 'MIT'
    if 'Permission to use, copy, modify' in t2: return 'ISC'
    return 'UNBEKANNT'
rows=[]
deps=json.loads(subprocess.check_output(['flutter','pub','deps','--json'],cwd=proto,text=True))
direct={}
for p in deps['packages']: direct[p['name']]=p
for p in deps['packages']:
    n,v,src,kind=p['name'],p['version'],p.get('source'),p['kind']
    if n=='r005_proto' or src=='path': continue
    if src=='sdk':
        rows.append(('dart',n,v,kind,'BSD-3-Clause (Flutter SDK)','flutter/LICENSE')); continue
    d=f'{PUB}/hosted/pub.dev/{n}-{v}'
    fs=[f for f in glob.glob(d+'/LICEN*')+glob.glob(d+'/COPYING*')]
    lic=classify(open(fs[0],errors='replace').read()) if fs else 'KEINE LIZENZDATEI'
    natv=os.path.isdir(d+'/android') or os.path.isdir(d+'/hook')
    rows.append(('dart',n,v,kind+('+native' if natv else ''),lic,os.path.basename(fs[0]) if fs else ''))
# Gradle
ORDER={}
def parse_tree(cfg,txt):
    s=set()
    for l in txt.splitlines():
        m=re.search(r'[+\\]--- ([\w.\-]+):([\w.\-]+):([\w.\-]*)(?: -> ([\w.\-]+))?',l)
        if m:
            g,a,v,r=m.groups()
            if r and ':' not in r: v=r
            s.add((g,a,v))
        else:
            m=re.search(r'[+\\]--- ([\w.\-]+):([\w.\-]+) -> ([\w.\-]+)',l)
            if m: s.add(m.groups())
    return s
def pom(g,a,v):
    fs=glob.glob(f'{GC}/{g}/{a}/{v}/*/*.pom')
    if fs: return open(fs[0],'rb').read()
    for base in ['https://dl.google.com/android/maven2','https://repo.maven.apache.org/maven2','https://storage.googleapis.com/download.flutter.io']:
        try: return urllib.request.urlopen(f"{base}/{g.replace('.','/')}/{a}/{v}/{a}-{v}.pom",timeout=20).read()
        except Exception: pass
    return None
def lic(g,a,v,depth=0):
    b=pom(g,a,v)
    if not b or depth>4: return ['POM FEHLT']
    b=re.sub(rb'xmlns="[^"]+"',b'',b,count=1)
    try: r=ET.fromstring(b)
    except Exception: return ['POM kaputt']
    ls=[(x.findtext('name') or '').strip()+(' <'+(x.findtext('url') or '').strip()+'>' if x.findtext('url') else '') for x in r.findall('licenses/license')]
    if ls: return ls
    p=r.find('parent')
    if p is not None: return lic(p.findtext('groupId'),p.findtext('artifactId'),p.findtext('version'),depth+1)
    return ['KEINE ANGABE IM POM']
gr={}
for cfg in ['profileRuntimeClasspath','releaseRuntimeClasspath','hcProbe']:
    t=subprocess.run(['./gradlew','-q',':app:dependencies','--configuration',cfg],cwd=proto+'/android',text=True,capture_output=True)
    open(f'{out}/gradle-{cfg}.txt','w').write(t.stdout+t.stderr)
    for e in parse_tree(cfg,t.stdout): gr.setdefault(e,set()).add(cfg)
for (g,a,v),cf in sorted(gr.items()):
    rows.append(('gradle',f'{g}:{a}',v,','.join(sorted(cf)),' | '.join(lic(g,a,v)),''))
with open(f'{out}/licenses.tsv','w') as f:
    f.write('oekosystem\tpaket\tversion\tart\tlizenz\tquelle\n')
    for r in rows: f.write('\t'.join(r)+'\n')
from collections import Counter
print(Counter((r[0],re.sub(r' <.*','',r[4])) for r in rows))
print('--- nicht klar permissiv / proprietaer verdaechtig:')
OK=re.compile(r'Apache|MIT|BSD|ISC|Eclipse Public License|public domain',re.I)
for r in rows:
    if not OK.search(r[4]) or re.search('play-services|gms|firebase|android-sdk|Android Software',r[1]+r[4],re.I): print(r)
print('--- Direktabhaengigkeiten:',[ (p['name'],p['version']) for p in deps['packages'] if p['kind'] in('direct','dev')])
