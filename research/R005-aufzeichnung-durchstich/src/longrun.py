#!/usr/bin/env python3
"""R005: Auswertung des Langlaufs. Aufruf: longrun.py <gap-lauf-ordner>. Abstaende aus afterstop/rows.tsv (DB), Ressourcen aus resources.tsv, je 10-Minuten-Fenster."""
import json,re,sys
o=sys.argv[1]; ph=dict(json.load(open(o+'/phases.json'))['phase'])
def q(x,p):
    x=sorted(x); return x[min(len(x)-1,int(p/100*len(x)))] if x else float('nan')
R=[]
for l in open(o+'/afterstop/rows.tsv'):
    if l.startswith('#') or not l.strip(): continue
    p=l.split('\t'); R.append((int(p[0]),int(p[4])/1e9))
ev={}
for l in open(o+'/logcat.txt',errors='replace'):
    m=re.search(r'^\s*(\d+\.\d+).*R005RCV .*seq=(\d+).*trecv=(\d+)',l)
    if m: ev[int(m[2])]=(float(m[1]),int(m[3])/1e9)
off=q([v[0]-v[1] for v in ev.values()],50)
ids=dict(R); print('Zeilen DB',len(R),'seq min/max',R[0][0],R[-1][0],'Loecher',R[-1][0]-R[0][0]+1-len(R),'rcv-Log',len(ev),'rcv nicht in DB',len(set(ev)-set(ids)))
T=[(s,t+off) for s,t in R]
a,b=ph['idle_start'],ph['end']; S=[x for x in T if a<=x[1]<=b]
d=[y[1]-x[1] for x,y in zip(S,S[1:])]
print('Idle-Phase %.0f s, Zeilen %d, Rate %.3f/s, Rand vorn %.2f s hinten %.2f s'%(b-a,len(S),len(S)/(b-a),S[0][1]-a,b-S[-1][1]))
print('Abstand p50 %.3f p90 %.3f p99 %.3f p99.9 %.3f max %.2f; >1.1: %.3f; >2: %d; >5: %d; >30: %d'%(q(d,50),q(d,90),q(d,99),q(d,99.9),max(d),sum(x>1.1 for x in d)/len(d),sum(x>2 for x in d),sum(x>5 for x in d),sum(x>30 for x in d)))
ack=[]
for l in open(o+'/logcat.txt',errors='replace'):
    m=re.search(r'^\s*(\d+\.\d+).*R005ACK .*us=(\d+)',l)
    if m: ack.append((float(m[1]),int(m[2])/1e3))
hb=[]
for l in open(o+'/logcat.txt',errors='replace'):
    m=re.search(r'^\s*(\d+\.\d+).*R005HB',l)
    if m: hb.append(float(m[1]))
res=[l.rstrip('\n').split('\t') for l in open(o+'/resources.tsv')]; H=res[0]; res=[dict(zip(H,r)) for r in res[1:]]
def fi(r,k):
    try: return float(r[k])
    except: return float('nan')
print('Min | Zeilen | Abst p50 p99 max | >2 | Commit-Latenz ms p50 p99 max (n) | HB-Abstand max | PSS MB (Anon/File) | RSS MB | WAL kB min-max | DB kB | Last | qemu fremd %')
w=600
t=a; i=0
while t<b-1 and b-t>=60:
    e=min(t+w,b); s=[x for x in T if t<=x[1]<e]; dd=[y[1]-x[1] for x,y in zip(s,s[1:])]
    A=[x[1] for x in ack if t<=x[0]<e]; hh=[x for x in hb if t<=x<e]; hd=[y-x for x,y in zip(hh,hh[1:])]
    rr=[r for r in res if t<=float(r['t'])<e and r['pss_kb']]
    pss=[fi(r,'pss_kb')/1024 for r in rr]; m=lambda k:sum(fi(r,k) for r in rr)/len(rr) if rr else float('nan')
    wal=[fi(r,'wal_b')/1024 for r in rr]; db=[fi(r,'db_b')/1024 for r in rr]
    print('%3d | %d | %.3f %.3f %.2f | %d | %.2f %.2f %.1f (%d) | %.2f | %.1f (%.1f/%.1f) | %.1f | %.0f-%.0f | %.0f | %.1f | %.0f'%(i*10,len(s),q(dd,50),q(dd,99),max(dd),sum(x>2 for x in dd),q(A,50),q(A,99),max(A),len(A),max(hd),sum(pss)/len(pss),m('pss_anon_kb')/1024,m('pss_file_kb')/1024,m('rss_kb')/1024,min(wal),max(wal),max(db),m('load1'),m('qemu_other_pct')))
    t+=w;i+=1
P=[(float(r['t'])-a,fi(r,'pss_kb')/1024) for r in res if r['pss_kb'] and float(r['t'])>=a]
n=len(P); mx=sum(p[0] for p in P)/n; my=sum(p[1] for p in P)/n
sl=sum((p[0]-mx)*(p[1]-my) for p in P)/sum((p[0]-mx)**2 for p in P)
print('PSS erstes %.1f letztes %.1f min %.1f max %.1f MB, Steigung %.3f MB/h (n=%d)'%(P[0][1],P[-1][1],min(p[1] for p in P),max(p[1] for p in P),sl*3600,n))
print('PIDs in resources:',sorted(set(r['pid'] for r in res)))
