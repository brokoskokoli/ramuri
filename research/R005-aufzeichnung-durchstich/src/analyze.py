#!/usr/bin/env python3
"""Auswertung R005. Aufruf: analyze.py gap|kill|bench|wal|swipe <work-dir> . Messdefinition siehe README."""
import glob,json,os,re,statistics as st,sys,subprocess
from walhdr import wal_info
def log_check(path,R,ev,tmax=None):
    # Gueltigkeit gegen veraltete DB (Review R005, Befund 2): Log und DB muessen denselben Lauf zeigen. Liefert Gruende, leer heisst bestanden.
    why=[]; ev=[e for e in ev if tmax is None or e[0]<=tmax]
    if not any(e[1]=='R005ACK' for e in ev): why.append('kein R005ACK')
    sq=0
    for l in open(path,errors='replace'):
        if 'SqliteException' in l:
            m=re.match(r'\s*(\d+\.\d+)\s',l)
            if tmax is None or (m and float(m[1])<=tmax): sq+=1
    if sq: why.append('SqliteException %d'%sq)
    log={int(kv(e[2])['seq']):int(kv(e[2])['trecv']) for e in ev if e[1]=='R005RCV' and 'trecv' in kv(e[2])}
    common=[r for r in R if r[0] in log]; off=sum(log[r[0]]!=r[4] for r in common)
    if off: why.append('trecv DB ungleich Log in %d von %d'%(off,len(common)))
    return why
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
def snap_of(work,run):
    # Zustand beim Beginn der Idle-Phase und isForeground: aus den Treiber-Logs (matrix.log usw.), weil natural w0 im Schlaf keine Herzschlaege mehr nach logcat liefert
    for f in sorted(glob.glob(work+'/*.log')):
        L=open(f,errors='replace').read().split('\n')
        for i,l in enumerate(L):
            if l.endswith('fertig '+run) or l.endswith('fertig '+run+' mit SIGKILL'):
                snap=None; fg=None
                for k in range(i,max(0,i-40),-1):
                    if fg is None and 'isForeground=' in L[k]: fg=L[k].count('isForeground=true')>0
                    if " {'deep'" in L[k]: snap=L[k]; break
                return snap,fg
    return None,None
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
        # Epochenzeit je Zeile aus trecv plus Versatz (Median), damit fehlende Logzeilen am Ende die Phase nicht verfaelschen
        if not R or not any(r[0] in rcv for r in R):
            rec=dict(run=run,rows=len(R),valid=False,why='keine Zeile, auch nicht in der Referenzphase: Standortweg lieferte nichts'); out.append(rec); print(json.dumps(rec)); continue
        off=sorted(rcv[r[0]]-r[4]/1e9 for r in R if r[0] in rcv)[len([r for r in R if r[0] in rcv])//2]
        rcv={r[0]:r[4]/1e9+off for r in R}|rcv
        def phase(a,b):
            sel=[r for r in R if a<=rcv[r[0]]<=b]
            d=[(y[4]-x[4])/1e9 for x,y in zip(sel,sel[1:])]  # trecv: Eingang im Adapter (elapsedRealtimeNanos); tfix ist im Emulator nicht verlaesslich (Epoche statt Elapsed)
            return sel,d
        base,db=phase(0,p['locked_start']); idle,di=phase(p['idle_start'],p['end'])
        dur=p['end']-p['idle_start']
        # Rand: Zeit von Phasenbeginn bis zum ersten und vom letzten Punkt bis Phasenende zaehlt mit (Logzeit), sonst blieben Ausfaelle am Rand unsichtbar
        if idle:
            di=[rcv[idle[0][0]]-p['idle_start']]+di+[p['end']-rcv[idle[-1][0]]]
        else: di=[dur]
        inj=inject(o+'inject.tsv')
        il=[(k[0],k[1],v[0]) for k,v in inj.items()]; il=[(float(a),float(b),c) for a,b,c in il]
        ids=[]
        for r in idle:  # NMEA rundet; naechste eingespeiste Position, Schrittweite der Spur ~3e-5 Grad
            best=min(il,key=lambda q:(q[0]-r[1])**2+(q[1]-r[2])**2)
            if abs(best[0]-r[1])<1.2e-5 and abs(best[1]-r[2])<1.2e-5: ids.append(best[2])
        injn=[v for v in inj.values() if p['idle_start']+3<=v[1]<=p['end']-3]
        got=set(ids); cov=(sum(1 for v in injn if v[0] in got)/len(injn)) if injn else float('nan')
        locked=sum(1 for h in hb_idle if h.get('locked')=='true')/max(1,len(hb_idle)); inter=sum(1 for h in hb_idle if h.get('inter')=='true')
        idl=sum(1 for h in hb_idle if h.get('idle')=='true')/max(1,len(hb_idle))
        # Schlaf-Beleg: Kernelzaehler vor/nach dem Lauf und dmesg. el-up taugt auf diesem Kernel nicht (bleibt auch bei belegtem Suspend 0).
        susp_ok=susp_fail=None; holdw=None
        if os.path.exists(o+'suspend.json'):
            sj=json.load(open(o+'suspend.json')); b4,af=sj['before'],sj['after']
            try: susp_ok=int(af['success'])-int(b4['success']); susp_fail=int(af['fail'])-int(b4['fail'])
            except ValueError: pass
        states=[json.loads(l.split('\t',1)[1]) for l in open(o+'state.tsv') if '{' in l]
        deep=(sum(1 for s in states if s['deep']=='IDLE')/len(states)) if states else None
        lhb=[(y['t']-x['t']) for x,y in zip(hb_idle,hb_idle[1:])]
        if hb_idle: lhb=[hb_idle[0]['t']-p['idle_start']]+lhb+[p['end']-hb_idle[-1]['t']]  # Rand zaehlt mit, sonst bleibt ein Einfrieren bis Phasenende unsichtbar
        else: lhb=[dur]
        acks=[int(kv(e[2])['us']) for e in ev if e[1]=='R005ACK']
        # Positionswechsel: der Emulator wiederholt die letzte Position je Sekunde, also zaehlt auch der Abstand der Wechsel
        chg=[rcv[idle[0][0]]] if idle else []
        for x,y in zip(idle,idle[1:]):
            if (x[1],x[2])!=(y[1],y[2]): chg.append(rcv[y[0]])
        dch=[b-a for a,b in zip(chg,chg[1:])]
        rec=dict(run=run,hb_edge=round(p['end']-hb_idle[-1]['t'],1) if hb_idle else None,integ=integ.split('\t')[-1],rows=len(R),idle_rows=len(idle),idle_s=round(dur),
          rate=round(len(idle)/dur,3),coverage=round(cov,4),gap_p50=round(pct(di,50),2),gap_p99=round(pct(di,99),2),gap_max=round(max(di),1) if di else None,
          n_gt2=sum(x>2 for x in di),n_gt5=sum(x>5 for x in di),n_gt30=sum(x>30 for x in di),poschg_p99=round(pct(dch,99),2) if dch else None,poschg_max=round(max(dch),1) if dch else None,poschg_gt5=sum(x>5 for x in dch),base_p99=round(pct(db,99),2),base_max=round(max(db),2) if db else None,
          hb_n=len(hb_idle),hb_max=round(max(lhb),1) if lhb else None,locked=round(locked,2),inter=inter,appIdle=round(idl,2),deepIDLE=round(deep,2) if states else None,susp_ok=susp_ok,susp_fail=susp_fail,hb_gt5=sum(x>5 for x in lhb),
          errs=sum(1 for e in ev if e[1]=='R005ERR'),ack_p50_us=round(pct(acks,50)) if acks else None,ack_p99_us=round(pct(acks,99)) if acks else None,load=round(st.mean(s['load'] for s in states),1) if states else None)
        if 'post_end' in p:  # natuerlicher Suspend: Nachphase, kommen wieder Standorte?
            po=[r for r in R if p['end']<=rcv[r[0]]<=p['post_end']]
            rec['post_rows']=len(po); rec['post_s']=round(p['post_end']-p['end'])
            hb_all=[h['t'] for h in hb]; rec['hb_maxgap_all']=round(max((b-a for a,b in zip(hb_all,hb_all[1:])),default=0),1)
            alld=[(y[4]-x[4])/1e9 for x,y in zip(R,R[1:])]; rec['db_maxgap_all']=round(max(alld,default=0),1)
        # Gueltigkeit: Host lief, Sperre und Idle belegt, Einspeisung lief bis zum Ende, R005START da, Referenz lieferte (ausser Kontrollen ohne Bezug)
        names=[e[1] for e in ev]; host=json.load(open(o+'meta.json')).get('host','own')
        svc=('R005SVC' in names) if host=='own' else (any(e[1]=='R005ENGINE' and 'ffgt' in e[2] for e in ev) if host=='ffgt' else 'R005SVC' not in names)
        it=sorted(v[1] for v in inj.values()); igap=max((b-a for a,b in zip(it,it[1:])),default=0)
        act=open(o+'activity.txt',errors='replace').read() if os.path.exists(o+'activity.txt') else ''
        why=[]
        if 'R005START' not in names: why.append('kein R005START')
        if not svc: why.append('Host nicht belegt')
        if rec['errs']: why.append('R005ERR')
        why+=log_check(o+'logcat.txt',R,ev)
        snap,fg=snap_of(work,run); pm=open(o+'kernel-pm.txt',errors='replace').read() if os.path.exists(o+'kernel-pm.txt') else None
        rec['susp_entries']=pm.count('suspend entry') if pm is not None else None; rec['sigkill_end']=pm is not None
        rec['hb_share']=round(len(hb_idle)/max(1,dur),3)
        if len(hb_idle)>=0.5*dur:
            if locked<0.99: why.append('nicht gesperrt')
            if idl<0.99 and not 'stopctl' in run: why.append('nicht idle')
        else:  # keine Herzschlaege im Log (Schlaf, adb offline oder eingefroren): Zustand aus dem Snapshot zu Beginn der Idle-Phase
            if not snap or "'deep': 'IDLE'" not in snap or 'isKeyguardShowing=true' not in snap: why.append('Zustand zu Beginn nicht belegt')
            rec['state_from']='snapshot'
        if inter: why.append('interaktiv')
        if len(base)<50: why.append('Referenz %d Zeilen'%len(base))
        if not it or it[-1]<p['end']-5: why.append('Einspeisung endet vor Phasenende')
        if igap>5 and 'pausectl' not in run: why.append('Einspeisung setzt aus %.1fs'%igap)
        rec.update(valid=not why,why=why,inj_n=len(it),inj_gap_max=round(igap,1),base_rows=len(base),base_rate=round(len(base)/max(1,p['locked_start']-min(rcv.values())),3),fgs=fg)
        out.append(rec); print(json.dumps(rec))
    json.dump(out,open(work+'/gap/summary.json','w'),indent=1)
def kill(work):
    out=[]
    for o in sorted(glob.glob(work+'/kill/*/')):
        if not os.path.exists(o+'.done'): continue
        m=json.load(open(o+'meta.json')); ev=parse_log(o+'logcat.txt')
        R=rows(o+'rows.tsv'); integ=open(o+'rows.tsv').readline().strip().split('\t')[-1]
        db=set(r[0] for r in R); mx=max(db) if db else 0
        tk=m['tkill']; post=sum(1 for e in ev if e[1]=='R005RCV' and e[0]>tk+1)  # Zeilen nach dem Kill: Prozess lebt noch (ffgt: Neustart)
        ack=[int(kv(e[2])['seq']) for e in ev if e[1]=='R005ACK' and e[0]<=tk+1]; rcv=[int(kv(e[2])['seq']) for e in ev if e[1]=='R005RCV' and e[0]<=tk+1]
        ok=(m.get('boot_s') is not None and post==0) if m['kind']!='proc' else (m.get('pid_after_kill')!=m['pid'] and (post==0 or m.get('host')=='ffgt'))
        pa=str(m.get('pid_after_kill') or '')
        why=[] if ok else ['Kill-Wirkung nicht belegt']
        why+=log_check(o+'logcat.txt',R,ev,tk+1)  # nur bis zum Kill: ffgt schreibt nach dem Neustart mit neuer Nummerierung
        autock=m.get('autock'); dbb=m['pull'].get('db')
        if autock is not None and dbb<=4096: why.append('Hauptdatei %d Byte, kein Checkpoint belegt'%dbb)
        la,lr=max(ack,default=0),max(rcv,default=0)
        acked=set(range(1,la+1)); lost_acked=len(acked-db)
        holes=len(set(range(1,mx+1))-db)
        ver=[kv(e[2]) for e in parse_log(o+'logcat2.txt') if e[1]=='R005VERIFY']
        rec=dict(run=os.path.basename(o[:-1]),via=m.get('kill_via','run-as' if m['kind']=='proc' else 'host'),post_kill_rcv=post,restart_pid=pa,wait=round(m['wait'],1),api=os.path.basename(o[:-1])[:3],host=m.get('host','own'),kind=m['kind'],tx=m['tx'],sync=m['sync'],last_ack=la,last_rcv=lr,db_rows=len(db),db_max=mx,lost_acked=lost_acked,rcv_not_db=lr-mx,db_beyond_ack=mx-la,holes=holes,integ=integ,dev=ver[0] if ver else None,wal=m['pull'].get('-wal'),autock=autock,db_bytes=dbb,wal_info=m.get('wal_info'),valid=not why,why=why)
        out.append(rec); print(json.dumps(rec))
        if why: print('UNGUELTIG:',rec['run'],why,'lost_acked',lost_acked)
    cells={}
    for r in out:
      if r['valid'] and r['autock'] is None: cells.setdefault((r['kind'],r['api'],r['host'],r['tx'],r['sync']),[]).append(r)
    print('kind api host tx sync n | lost_acked sum/runs-with-loss/max | rcv_not_db mean min max | db_beyond_ack max | integ-not-ok | dev-mismatch')
    tab=[]
    for k,v in sorted(cells.items()):
        L=[x['lost_acked'] for x in v]; Q=[x['rcv_not_db'] for x in v]
        bad=sum(x['integ']!='ok' for x in v); dv=sum(1 for x in v if not x['dev'] or int(x['dev']['max'] if x['dev']['max']!='null' else 0)!=x['db_max'])
        row=(*k,len(v),sum(L),sum(l>0 for l in L),max(L),round(st.mean(Q),1),min(Q),max(Q),max(x['db_beyond_ack'] for x in v),bad,dv); tab.append(row); print(*row)
    json.dump(dict(rows=out,cells=tab),open(work+'/kill/summary.json','w'),indent=1)
def ckgate(work,run):
    # Vorpruefung der Checkpoint-Serie: Abbruch nach dem ersten Lauf, wenn der Zustand gar nicht erreicht wird, statt 1 h zu messen
    o=f'{work}/kill/{run}/'; m=json.load(open(o+'meta.json')); wi=m.get('wal_info') or {}
    print(run,'Hauptdatei',m['pull'].get('db'),'WAL',wi)
    sys.exit(0 if m['pull'].get('db',0)>4096 else 1)
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
        print(run,'acks',len(ack),'wal_info',wal_info(d+'x.db-wal'),'db:',dbl[0][2][:110] if dbl else None)  # Frame-Koepfe bleiben Klartext
def swipe(work):
    for o in sorted(glob.glob(work+'/swipe/*/')):
        if not os.path.exists(o+'.done'): continue
        m=json.load(open(o+'meta.json')); R=rows(o+'rows.tsv'); ev=parse_log(o+'logcat.txt')
        d=[(y[4]-x[4])/1e9 for x,y in zip(R,R[1:])]
        print(os.path.basename(o[:-1]),'rows',len(R),'pid',m['pid0'],m['pid1'],'recents',m['recents_before'],m['recents_after'],'gap_max',round(max(d),2) if d else None,'n_gt5',sum(x>5 for x in d),'svc',re.findall(r'isForeground=\w+',m['svc']),[e[2][:40] for e in ev if e[1]=='R005SVC'])
{'gap':gap,'kill':kill,'bench':bench,'wal':wal,'swipe':swipe,'ckgate':lambda w:ckgate(w,sys.argv[3])}[sys.argv[1]](sys.argv[2])
