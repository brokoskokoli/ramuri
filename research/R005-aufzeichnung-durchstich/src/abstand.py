#!/usr/bin/env python3
"""R005: Woher kommen die Abstaende 1,1 bis 2,0 s und die Abdeckung unter 1 auf API 36? Liest nur Rohdaten eines gap-Laufs. Aufruf: abstand.py <gap-lauf-ordner>...
Spalten: Abstand im Adapter (trecv), Abstand des Fix-Zeitstempels (tfix), Latenz Einspeisung bis Eingang je Position, uebersprungene Positionen."""
import json,re,sys,os
def q(x,p):
    x=sorted(x); return x[min(len(x)-1,int(p/100*len(x)))] if x else float('nan')
for o in sys.argv[1:]:
    ph=dict(json.load(open(o+'/phases.json'))['phase'])
    R=[]
    for l in open(o+'/logcat.txt',errors='replace'):
        m=re.search(r'^\s*(\d+\.\d+).*R005RCV .*seq=(\d+) tfix=(\d+) trecv=(\d+) lat=(\S+) lon=(\S+)',l)
        if m: R.append((float(m[1]),int(m[2]),int(m[3])/1e9,int(m[4])/1e9,float(m[5]),float(m[6])))
    inj=[]
    for l in open(o+'/inject.tsv'):
        i,a,b,la,lo=l.split('\t'); inj.append((int(i),float(a),float(b),float(la),float(lo)))
    def nearest(r):
        # naechste Position im Zeitfenster -5..+1 s (Spur: Schrittweite ~3e-5 Grad, NMEA rundet)
        c=[q_ for q_ in inj if r[0]-5<=q_[1]<=r[0]+1] or inj
        b=min(c,key=lambda q_:(q_[3]-r[4])**2+(q_[4]-r[5])**2)
        return b if abs(b[3]-r[4])<1.2e-5 and abs(b[4]-r[5])<1.2e-5 else None
    for name,a,b in [('Referenz',0,ph['locked_start']),('Idle',ph['idle_start'],ph['end'])]:
        S=[r for r in R if a<=r[0]<=b]
        if len(S)<5: print(os.path.basename(o),name,'zu wenig',len(S)); continue
        dr=[y[3]-x[3] for x,y in zip(S,S[1:])]; df=[y[2]-x[2] for x,y in zip(S,S[1:])]; dl=[y[0]-x[0] for x,y in zip(S,S[1:])]
        M=[nearest(r) for r in S]; seen={}
        for r,m in zip(S,M):
            if m and m[0] not in seen: seen[m[0]]=r
        lat=[seen[i][0]-t for i,t in [(q_[0],q_[2]) for q_ in inj] if i in seen]
        lo,hi=min(seen),max(seen); idx=[q_[0] for q_ in inj if lo<=q_[0]<=hi]; miss=[i for i in idx if i not in seen]
        rep=sum(1 for x,y in zip(M,M[1:]) if x and y and x[0]==y[0])
        # fuehrt jeder lange Abstand zu einer uebersprungenen Position?
        lg=[(x,y) for x,y in zip(S,S[1:]) if y[3]-x[3]>1.1]
        lgskip=0
        for x,y in lg:
            mx,my=nearest(x),nearest(y)
            if mx and my and my[0]-mx[0]>=2: lgskip+=1
        short=sum(1 for d in dr if d<0.97)
        ij=[y[1]-x[1] for x,y in zip(inj,inj[1:]) if a<=x[1]<=b]; lj=[q_[2]-q_[1] for q_ in inj if a<=q_[1]<=b]
        print(os.path.basename(o),name,'n',len(S),
          '| trecv p1 %.3f p50 %.3f p90 %.3f p99 %.3f max %.2f, Anteil>1.1 %.3f, Anteil<0.97 %.4f'%(q(dr,1),q(dr,50),q(dr,90),q(dr,99),max(dr),sum(d>1.1 for d in dr)/len(dr),short/len(dr)),
          '| tfix p50 %.3f p90 %.3f max %.2f'%(q(df,50),q(df,90),max(df)),
          '| Einsp bis Eingang p10 %.3f p50 %.3f p90 %.3f'%(q(lat,10),q(lat,50),q(lat,90)) if lat else '',
          '| Positionen %d, fehlen %d (%.3f), Wiederholung %d, lange Abst. %d davon mit Sprung %d'%(len(idx),len(miss),len(miss)/max(1,len(idx)),rep,len(lg),lgskip),
          '| inject Takt p50 %.3f max %.3f, adb-Dauer p50 %.3f p99 %.3f'%(q(ij,50),max(ij) if ij else 0,q(lj,50),q(lj,99)))
