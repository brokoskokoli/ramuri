#!/usr/bin/env python3
"""R005: erzeugt alle Tabellen von RESULTS.md aus den Rohdaten. Aufruf: tables.py <work-dir> (vorher analyze.py gap und kill, die summary.json schreiben).
Spannen sind min bis max ueber die Laeufe einer Zelle. Obergrenze Kill: exakt einseitig 95 % bei 0 Treffern in n, also 1-0.05^(1/n)."""
import bisect,collections,csv,glob,json,os,re,sys
W=sys.argv[1]
def rng(xs,f='%.2f'):
    xs=[x for x in xs if x is not None]
    if not xs: return '–'
    a,b=min(xs),max(xs); return f%a if a==b else (f%a)+' bis '+(f%b)
def table(head,rows):
    print('| '+' | '.join(head)+' |'); print('|'+' --- |'*len(head))
    for r in rows: print('| '+' | '.join(str(x) for x in r)+' |')
    print()
S=json.load(open(W+'/gap/summary.json'))
CTRL=('pausectl','stopctl','ctl_','forced','abst','none')
def api(r): return r['run'][:3]
def host(r): return r['run'].split('_')[1]
def wake(r): return r['run'].split('_')[2]
def natural(r): return '_nat' in r['run']
base=[r for r in S if not any(c in r['run'] for c in CTRL)]
print('## Tabelle 1: Standardbedingung (emulator_wake_lock gehalten, kein Suspend), gesperrt, force-idle, ohne eigenen Wake Lock\n')
rows=[]
for a in ('a36','a31'):
  for h in ('own','ffgt'):
    c=[r for r in base if api(r)==a and host(r)==h and not natural(r)]
    if not c: continue
    rows.append((a[1:],h,len(c),sum(r['idle_s'] for r in c),sum(r['idle_rows'] for r in c),rng([r['rate'] for r in c],'%.3f'),rng([r['coverage'] for r in c]),rng([r['gap_p99'] for r in c]),'%.1f'%max(r['gap_max'] for r in c),sum(r['n_gt2'] for r in c),sum(r['n_gt5'] for r in c),sum(r['n_gt30'] for r in c),'%.1f'%max(r['hb_max'] for r in c),rng([r['ack_p50_us']/1e3 for r in c],'%.1f'),'%.1f'%(max(r['ack_p99_us'] for r in c)/1e3),'%d (gelesen in %d von %d)'%(sum(int(r['susp_ok'] or 0) for r in c),sum(r['susp_ok'] is not None for r in c),len(c))))
table('API Host Läufe Idle-s Zeilen Rate/s Abdeckung p99-Abstand-s max-Abstand-s >2s >5s >30s Herzschlag-max-s Commit-p50-ms Commit-p99-ms Suspend-Erfolge'.split(),rows)
print('## Tabelle 2: Bedingung natural (emulator_wake_lock geloest), gesperrt, force-idle\n')
rows=[]
for a in ('a36','a31'):
  for h in ('own','ffgt'):
    for w in ('w1','w0'):
      c=[r for r in base if api(r)==a and host(r)==h and wake(r)==w and natural(r)]
      if not c: continue
      rows.append((a[1:],h,'ja' if w=='w1' else 'nein',len(c),sum(r['idle_s'] for r in c),sum(r['idle_rows'] for r in c),rng([r['rate'] for r in c],'%.3f'),rng([r['coverage'] for r in c]),'%.1f'%max(r['gap_max'] for r in c),'%d/%d'%(sum(r['n_gt5']>0 for r in c),len(c)),sum(r['n_gt5'] for r in c),'%d'%sum(int(r['susp_ok'] or 0) for r in c) if w=='w1' else '–',rng([r.get('susp_entries') for r in c],'%d') if w=='w0' else '–'))
table('API Host Wake-Lock Läufe Idle-s Zeilen Rate/s Abdeckung max-Abstand-s Läufe-mit->5s Summe->5s Suspend-Erfolge suspend-entry-je-Lauf'.split(),rows)
print('Einzelne Laeufe natural (Zeilen in der Idle-Phase von Idle-s):')
for r in base:
    if natural(r): print(' ',r['run'],r['idle_rows'],'/',r['idle_s'],'max',r['gap_max'],'entries',r.get('susp_entries'),'succ',r.get('susp_ok'))
print('\n## Tabelle 3: Kontrollen (je Einzellauf)\n')
rows=[]
for r in S:
    if any(c in r['run'] for c in ('pausectl','stopctl','none','forced')):
        rows.append((r['run'],r['idle_rows'],r['idle_s'],r['coverage'],r['gap_max'],r['poschg_max'],r['n_gt5'],r['hb_max'],r['susp_ok']))
table('Lauf Zeilen Idle-s Abdeckung max-Abstand-s max-Positionswechsel-s >5s Herzschlag-max-s Suspend-Erfolge'.split(),rows)
print('## Tabelle 4: Probe Abstaende API 36, GNSS-HAL gegen Datenbank\n')
rows=[]
for tag,name in (('noinj','ohne Einspeisung im Idle'),('inj10','alle 10 s'),('inj1','jede Sekunde')):
    o=f'{W}/gap/a36_own_w0_i1_240s_abst_{tag}_r0'; ph=dict(json.load(open(o+'/phases.json'))['phase']); L=[]
    for l in open(o+'/hal-log.txt',errors='replace'):
        m=re.match(r'\s*(\d+\.\d+)\s+\d+\s+\d+ D \S+: Gnss:onGnssLocationCb:(\d+)',l)
        if m: L.append((float(m[1]),int(m[2])))
    acc=[t for t,n in L if n==333]; drop=[t for t,n in L if n==321]; rcv=[]
    for l in open(o+'/logcat.txt',errors='replace'):
        m=re.search(r'^\s*(\d+\.\d+).*R005RCV ',l)
        if m: rcv.append(float(m[1]))
    db=sum(1 for l in open(o+'/afterstop/rows.tsv') if l.strip() and not l.startswith('#'))
    a,b=ph['idle_start'],ph['end']; I=[t for t in rcv if a<=t<=b]; lg=[(x,y) for x,y in zip(I,I[1:]) if y-x>1.1]
    d=[y-x for x,y in zip(I,I[1:])]
    dt=[t-acc[bisect.bisect_right(acc,t)-1] for t in drop if a<=t<=b and bisect.bisect_right(acc,t)>0]; dt.sort()
    hit=sum(any(x<q<y for q in drop) for x,y in lg)
    rows.append((name,sum(n==311 for t,n in L),len(drop),len(acc),db,len(I),'%.1f %%'%(100*len(lg)/len(d)),'%.2f'%max(d),'%d/%d'%(hit,len(lg)),'%.3f'%dt[len(dt)//2]))
table('Einspeisung HAL-Eingang(311) HAL-verworfen(321) HAL-weiter(333) DB-Zeilen Idle-Zeilen Anteil->1,1s max-s lange-Abstände-mit-Verwerfung Median-Abstand-Verworfener-zum-letzten-Fix-s'.split(),rows)
print('Histogramm der Abstaende in der Idle-Phase, 0,1-s-Klassen (Klasse:Anzahl):')
for tag in ('noinj','inj10','inj1'):
    o=f'{W}/gap/a36_own_w0_i1_240s_abst_{tag}_r0'; ph=dict(json.load(open(o+'/phases.json'))['phase']); I=[]
    for l in open(o+'/logcat.txt',errors='replace'):
        m=re.search(r'^\s*(\d+\.\d+).*R005RCV ',l)
        if m and ph['idle_start']<=float(m[1])<=ph['end']: I.append(float(m[1]))
    print(' ',tag,sorted(collections.Counter(round(y-x,1) for x,y in zip(I,I[1:])).items()))
K=json.load(open(W+'/kill/summary.json'))['rows']
print('\n## Tabelle 5: Kill\n')
cells=collections.defaultdict(list)
for r in K: cells[(r['api'],r['kind'],r['host'],r['sync'],r['tx'])].append(r)
rows=[]
for k in sorted(cells,key=lambda k:(k[0]!='a36',k[1]!='proc',k[1],k[2],k[3],k[4])):
    v=cells[k]; L=[x['lost_acked'] for x in v]; Q=[x['rcv_not_db'] for x in v]
    rows.append((k[0][1:],k[1],k[2],k[3],k[4],len(v),'%d/%d'%(sum(l>0 for l in L),len(v)),max(L),sum(L),rng(Q,'%d'),'%.1f'%(sum(Q)/len(Q)),sum(x['holes'] for x in v),sum(x['integ']!='ok' for x in v),len(v)-sum(1 for x in v if x['dev'] and int(x['dev']['max'] if x['dev']['max']!='null' else 0)==x['db_max'])))
table('API Art Host Sync tx n Läufe-mit-Verlust max-lost_acked Summe rcv_not_db mittel Löcher integrity-nicht-ok Gerätecheck-fehlt'.split(),rows)
for ap in ('a36','a31'):
    for kinds,name in ((('sigkill','emu'),'sigkill+emu'),(('proc',),'proc')):
        v=[r for r in K if r['api']==ap and r['sync']=='FULL' and r['kind'] in kinds]; n=len(v); l=sum(r['lost_acked']>0 for r in v)
        print(f'FULL {ap} {name}: {l}/{n} Laeufe mit Verlust, Obergrenze 95 %% bei 0 Treffern {100*(1-0.05**(1/n)):.0f} %%'%() if n else '')
print()
print('## Tabelle 6: Wischen\n')
rows=[]
for o in sorted(glob.glob(W+'/swipe/*/')):
    if not os.path.exists(o+'.done'): continue
    m=json.load(open(o+'meta.json')); R=[int(l.split('\t')[4])/1e9 for l in open(o+'rows.tsv') if l.strip() and not l.startswith('#')]
    d=[y-x for x,y in zip(R,R[1:])]; rows.append((os.path.basename(o[:-1]),len(R),'gleich' if m['pid0']==m['pid1'] else 'neu','%s→%s'%(m['recents_before'],m['recents_after']),'%.2f'%max(d),sum(x>5 for x in d)))
table('Lauf Zeilen PID Recents max-Abstand-s >5s'.split(),rows)
print('## Tabelle 7: Lizenzen\n')
L=list(csv.DictReader(open(W+'/licenses/licenses.tsv'),delimiter='\t')); c=collections.Counter()
def norm(s):
    if 'Apache' in s: return 'Apache-2.0'
    if 'BSD-3' in s: return 'BSD-3-Clause'
    if 'MIT' in s: return 'MIT'
    return s.split(' <')[0]
for r in L: c[(r['oekosystem'],norm(r['lizenz']))]+=1
table('Ökosystem Lizenz Einträge'.split(),[(a,b,n) for (a,b),n in sorted(c.items())])
