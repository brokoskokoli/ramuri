#!/usr/bin/env python3
"""Auswertung R005. Aufruf: analyze.py gap|kill|bench|wal|swipe <work-dir> . Messdefinition siehe README."""
import glob,json,os,re,statistics as st,sys,subprocess
def pct(xs,p):
    if not xs: return float('nan')
    xs=sorted(xs); return xs[min(len(xs)-1,int(p/100*len(xs)))]
def rows(path):
    r=[]
    for l in open(path):
        if l.startswith('#') or not l.strip(): continue
        p=l.rstrip('\n').split('\t'); r.append((int(p[0]),float(p[1]),float(p[2]),int(p[3]),int(p[4]),int(p[5])))
    return r
def parse_log(path):
    ev=[]
    for l in open(path,errors='replace'):
        m=re.match(r'\s*(\d+\.\d+)\s.*?(R005\w+)\s?(.*)',l)
        if m: ev.append((float(m[1]),m[2],m[3]))
    return ev
def kv(s): return dict(re.findall(r'(\w+)=(\S+)',s))
def dump(dbdir,plain=False):
    o=subprocess.run(['dart','run','bin/dump.dart',dbdir+'/x.db']+(['--plain'] if plain else []),cwd=os.environ['R005_WALTEST'],capture_output=True,text=True)
    open(dbdir+'/rows.tsv','w').write(o.stdout); return dbdir+'/rows.tsv',o.stdout.split('\n',1)[0]
def inject(path):
    d={}
    for l in open(path):
        i,a,b,la,lo=l.split('\t'); d[(la,lo.strip())]=(int(i),float(a))
    return d
def gap(work):
    out=[]
    for o in sorted(glob.glob(work+'/gap/*/')):
        if not os.path.exists(o+'.done'): continue
        run=os.path.basename(o[:-1]); ph=json.load(open(o+'phases.json'))
        p=dict((a,b) for a,b in ph['phase'])
        rt,integ=dump(o+'afterstop'); R=rows(rt)
        ev=parse_log(o+'logcat.txt')
        hb=[kv(e[2])|{'t':e[0]} for e in ev if e[1]=='R005HB']
        hb_idle=[h for h in hb if p['idle_start']<=h['t']<=p['end']]
        # Zeitbasis: Abstaende der Fix-Zeitstempel in der DB (elapsedRealtimeNanos), Phase ueber RCV-Logzeit
        rcv={int(kv(e[2])['seq']):e[0] for e in ev if e[1]=='R005RCV'}
        dbseq=[r[0] for r in R]
        def phase(a,b):
            sel=[r for r in R if a<=rcv.get(r[0],0)<=b]
            d=[(y[3]-x[3])/1e9 for x,y in zip(sel,sel[1:])]
            return sel,d
        base,db=phase(0,p['locked_start']); idle,di=phase(p['idle_start'],p['end'])
        dur=p['end']-p['idle_start']
        inj=inject(o+'inject.tsv')
        ids=[inj[('%.6f'%r[1],'%.6f'%r[2])][0] for r in idle if ('%.6f'%r[1],'%.6f'%r[2]) in inj]
        injn=[v for v in inj.values() if p['idle_start']+3<=v[1]<=p['end']-3]
        got=set(ids); cov=(sum(1 for v in injn if v[0] in got)/len(injn)) if injn else float('nan')
        locked=sum(1 for h in hb_idle if h.get('locked')=='true')/max(1,len(hb_idle)); inter=sum(1 for h in hb_idle if h.get('inter')=='true')
        idl=sum(1 for h in hb_idle if h.get('idle')=='true')/max(1,len(hb_idle))
        susp=None
        if len(hb_idle)>1:
            a,b=hb_idle[0],hb_idle[-1]; susp=(int(b['el'])-int(a['el'])-(int(b['up'])-int(a['up'])))/1000
        states=[json.loads(l.split('\t',1)[1]) for l in open(o+'state.tsv') if '{' in l]
        deep=sum(1 for s in states if s['deep']=='IDLE')/max(1,len(states))
        lhb=[(y['t']-x['t']) for x,y in zip(hb_idle,hb_idle[1:])]
        acks=[int(kv(e[2])['us']) for e in ev if e[1]=='R005ACK']
        rec=dict(run=run,integ=integ.split('\t')[-1],rows=len(R),idle_rows=len(idle),idle_s=round(dur),
          rate=round(len(idle)/dur,3),coverage=round(cov,4),gap_p50=round(pct(di,50),2),gap_p99=round(pct(di,99),2),gap_max=round(max(di),1) if di else None,
          n_gt2=sum(x>2 for x in di),n_gt5=sum(x>5 for x in di),n_gt30=sum(x>30 for x in di),base_p99=round(pct(db,99),2),base_max=round(max(db),2) if db else None,
          hb_n=len(hb_idle),hb_max=round(max(lhb),1) if lhb else None,locked=round(locked,2),inter=inter,appIdle=round(idl,2),deepIDLE=round(deep,2),suspend_s=susp,
          errs=sum(1 for e in ev if e[1]=='R005ERR'),ack_p50_us=round(pct(acks,50)),ack_p99_us=round(pct(acks,99)),load=round(st.mean(s['load'] for s in states),1) if states else None)
        out.append(rec); print(json.dumps(rec))
    json.dump(out,open(work+'/gap/summary.json','w'),indent=1)
def kill(work):
    out=[]
    for o in sorted(glob.glob(work+'/kill/*/')):
        if not os.path.exists(o+'.done'): continue
        m=json.load(open(o+'meta.json')); ev=parse_log(o+'logcat.txt')
        R=rows(o+'rows.tsv'); integ=open(o+'rows.tsv').readline().strip().split('\t')[-1]
        db=set(r[0] for r in R); mx=max(db) if db else 0
        ack=[int(kv(e[2])['seq']) for e in ev if e[1]=='R005ACK']; rcv=[int(kv(e[2])['seq']) for e in ev if e[1]=='R005RCV']
        la,lr=max(ack,default=0),max(rcv,default=0)
        acked=set(range(1,la+1)); lost_acked=len(acked-db)
        holes=len(set(range(1,mx+1))-db)
        ver=[kv(e[2]) for e in parse_log(o+'logcat2.txt') if e[1]=='R005VERIFY']
        rec=dict(run=os.path.basename(o[:-1]),kind=m['kind'],tx=m['tx'],sync=m['sync'],last_ack=la,last_rcv=lr,db_rows=len(db),db_max=mx,lost_acked=lost_acked,rcv_not_db=lr-mx,db_beyond_ack=mx-la,holes=holes,integ=integ,dev=ver[0] if ver else None,wal=m['pull'].get('-wal'))
        out.append(rec); print(json.dumps(rec))
    cells={}
    for r in out: cells.setdefault((r['kind'],r['tx'],r['sync']),[]).append(r)
    print('kind tx sync n | lost_acked sum/runs-with-loss/max | rcv_not_db mean min max | db_beyond_ack max | integ-not-ok | dev-mismatch')
    tab=[]
    for k,v in sorted(cells.items()):
        L=[x['lost_acked'] for x in v]; Q=[x['rcv_not_db'] for x in v]
        bad=sum(x['integ']!='ok' for x in v); dv=sum(1 for x in v if not x['dev'] or int(x['dev']['max'] if x['dev']['max']!='null' else 0)!=x['db_max'])
        row=(*k,len(v),sum(L),sum(l>0 for l in L),max(L),round(st.mean(Q),1),min(Q),max(Q),max(x['db_beyond_ack'] for x in v),bad,dv); tab.append(row); print(*row)
    json.dump(dict(rows=out,cells=tab),open(work+'/kill/summary.json','w'),indent=1)
def bench(work):
    for o in sorted(glob.glob(work+'/bench/*/')):
        d={}
        for e in parse_log(o+'logcat.txt'):
            if e[1]=='R005BENCH':
                k=kv(e[2]); d.setdefault((k['sync'],int(k['tx'])),[]).append(int(k['us']))
        print(os.path.basename(o[:-1]))
        for k,v in sorted(d.items()):
            v=v[20:]  # Einlauf verwerfen
            print(k,'n',len(v),'p50_ms %.2f p95_ms %.2f max_ms %.1f je_zeile_p50_ms %.2f'%(pct(v,50)/1e3,pct(v,95)/1e3,max(v)/1e3,pct(v,50)/1e3/k[1]))
def wal(work):
    import struct,math
    for o in sorted(glob.glob(work+'/wal-device/*/')):
        d=o+'vor-checkpoint/'; run=os.path.basename(o[:-1]); ev=parse_log(o+'logcat.txt')
        ack=[kv(e[2]) for e in ev if e[1]=='R005ACK']; dbl=[e for e in ev if e[1]=='R005DB']; lat=None
        rcv=[kv(e[2]) for e in ev if e[1]=='R005RCV']
        for f in ['x.db','x.db-wal']:
            b=open(d+f,'rb').read(); mk=b.count(b'R005KLARTEXTMARKER'); hd=b.count(b'SQLite format 3')
            lats=sum(b.count(struct.pack('>d',float(r['lat']))) for r in rcv[:50])
            pg=b
            if f.endswith('wal') and len(b)>32: pg=b''.join(b[i+24:i+24+4096] for i in range(32,len(b)-4119,4120))
            h=[0]*256
            for x in pg: h[x]+=1
            e=len(pg)/256 or 1; chi=sum((c-e)**2/e for c in h)
            print(run,f,'size',len(b),'frames',(len(b)-32)//4120 if f.endswith('wal') else '-','marker',mk,'lat_bytes',lats,'sqliteHeader',hd,'chi2',round(chi))
        print(run,'acks',len(ack),'db:',dbl[0][2][:110] if dbl else None)
def swipe(work):
    for o in sorted(glob.glob(work+'/swipe/*/')):
        if not os.path.exists(o+'.done'): continue
        m=json.load(open(o+'meta.json')); R=rows(o+'rows.tsv'); ev=parse_log(o+'logcat.txt')
        d=[(y[3]-x[3])/1e9 for x,y in zip(R,R[1:])]
        print(os.path.basename(o[:-1]),'rows',len(R),'pid',m['pid0'],m['pid1'],'recents',m['recents_before'],m['recents_after'],'gap_max',round(max(d),2) if d else None,'n_gt5',sum(x>5 for x in d),'svc',re.findall(r'isForeground=\w+',m['svc']),[e[2][:40] for e in ev if e[1]=='R005SVC'])
{'gap':gap,'kill':kill,'bench':bench,'wal':wal,'swipe':swipe}[sys.argv[1]](sys.argv[2])
