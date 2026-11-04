#!/usr/bin/env python3
"""R005-Mess-Harness: steuert genau einen eigenen Emulator (Serial emulator-5600), zeichnet logcat auf dem Rechner mit.
Unterbefehle siehe --help. Ausgaben unter $RESEARCH_DATA/work/R005/<art>/<lauf>/ . Fremde Emulatoren werden nie angefasst."""
import argparse,json,math,os,random,re,shutil,signal,subprocess,sys,threading,time
SDK=os.path.expanduser('~/Library/Android/sdk'); ADB=SDK+'/platform-tools/adb'; EMU=SDK+'/emulator/emulator'
S='emulator-5600'; PORT=5600; PKG='org.runningapp.r005.r005_proto'; ACT=PKG+'/.MainActivity'; PIN='1234'
WORK=os.environ['R005_WORK']; APK=os.environ['R005_APK']
def avd(api): return f'running_app_r005_api{api}'
def sh(*a,timeout=60,check=False):
    try:
        r=subprocess.run(a,capture_output=True,text=True,timeout=timeout)
        if check and r.returncode: raise RuntimeError(f'{a}: {r.stderr}')
        return r.stdout
    except subprocess.TimeoutExpired: return ''
def adb(*a,timeout=60,check=False): return sh(ADB,'-s',S,*a,timeout=timeout,check=check)
def ash(c,timeout=60,check=False): return adb('shell',c,timeout=timeout,check=check)
def log(*a): print(time.strftime('%H:%M:%S'),*a,flush=True)
# ---- Emulator
def emu_pidfile(): return f'{WORK}/emulator.pid'
def emu_pid():
    try:
        p=int(open(emu_pidfile()).read()); os.kill(p,0)
        if 'emulator' in sh('ps','-o','command=','-p',str(p)) or 'qemu' in sh('ps','-o','command=','-p',str(p)): return p
    except Exception: pass
    return None
def emu_start(api):
    assert emu_pid() is None, 'eigener Emulator laeuft schon'
    lg=open(f'{WORK}/emulator-api{api}.log','a')
    p=subprocess.Popen(['nice','-n','0',EMU,'-avd',avd(api),'-port',str(PORT),'-no-window','-no-audio','-no-boot-anim','-no-snapshot-save','-no-snapshot-load','-gpu','swiftshader_indirect','-no-metrics']+os.environ.get('R005_EMU_EXTRA','').split(),stdout=lg,stderr=lg,start_new_session=True)
    open(emu_pidfile(),'w').write(str(p.pid)); return p
def wait_boot(t=600):
    t0=time.time()
    adb('wait-for-device',timeout=t)
    while time.time()-t0<t:
        if ash('getprop sys.boot_completed',timeout=10).strip()=='1' and 'bootanim' not in ash('getprop init.svc.bootanim',timeout=10).replace('stopped',''):
            log('boot ok %.0fs'%(time.time()-t0)); return time.time()-t0
        time.sleep(2)
    raise RuntimeError('boot timeout')
def unlock():
    for _ in range(10):
        ash('input keyevent 224'); ash('wm dismiss-keyguard'); time.sleep(1)
        ash(f'input text {PIN}'); ash('input keyevent 66'); time.sleep(2)
        d=ash('dumpsys window')
        if not re.search(r'(isKeyguardShowing|mKeyguardShowing|KeyguardShowing)=true|mDreamingLockscreen=true',d) and 'mInputRestricted=true' not in d: return True
    raise RuntimeError('entsperren misslungen')
def setup():
    log(adb('install','-r','-g',APK,timeout=180).strip()[-30:])
    for p in ['ACCESS_FINE_LOCATION','ACCESS_COARSE_LOCATION','ACTIVITY_RECOGNITION','POST_NOTIFICATIONS']: ash(f'pm grant {PKG} android.permission.{p}')
    ash('cmd location set-location-enabled true')
    ash('settings put global stay_on_while_plugged_in 0'); ash('svc power stayon false')
    ash(f'locksettings set-pin {PIN}')
    for k in ['window_animation_scale','transition_animation_scale','animator_duration_scale']: ash(f'settings put global {k} 0')
    ash('settings put system screen_off_timeout 1800000')
def state_snapshot():
    pw=ash('dumpsys power | grep -E "mWakefulness=|mHoldingWakeLockSuspendBlocker|mHoldingDisplaySuspendBlocker|mHalAutoSuspendModeEnabled"').split()
    return dict(deep=ash('dumpsys deviceidle get deep').strip(),light=ash('dumpsys deviceidle get light').strip(),power=' '.join(pw),
      batt=' '.join(ash('dumpsys battery | grep -E "AC powered|USB powered|status"').split()),load=os.getloadavg()[0],
      kbd=' '.join(re.findall(r'(?:mDreamingLockscreen|isKeyguardShowing|mShowingLockscreen)=\w+',ash('dumpsys window'))),holders=holders())
def root():
    # adb root startet adbd neu und bricht ein laufendes logcat ab: nur vor einem Lauf aufrufen. Noetig fuer suspend_stats und dmesg.
    if 'uid=0' in ash('id',timeout=20): return
    adb('root',timeout=20); time.sleep(3); adb('wait-for-device',timeout=60)
def susp():
    r={}
    for k in ['success','fail','failed_freeze','failed_prepare','failed_suspend','failed_suspend_noirq','last_failed_dev']:
        r[k]=ash(f'cat /sys/power/suspend_stats/{k}',timeout=30).strip()
    r['wake_lock']=ash('cat /sys/power/wake_lock',timeout=30).strip()
    r['autosuspend']=' '.join(re.findall(r'mHalAutoSuspendModeEnabled=\w+|mHoldingWakeLockSuspendBlocker=\w+|mHoldingDisplaySuspendBlocker=\w+',ash('dumpsys power',timeout=30)))
    r['t']=time.time(); return r
def holders(): return ash(r'dumpsys power | sed -n "/Wake Locks: size/,/^$/p; /Suspend Blockers: size/,/^$/p"',timeout=30)
def start_app(lc_path,**kw):
    # Ein zu frueh gesendeter Befehl geht beim ersten Start nach der Installation verloren (R005CMD fehlt im Log): pruefen statt still leer messen.
    for i in range(4):
        r=am_start(**kw); t=time.time()
        while time.time()-t<15:
            time.sleep(0.5)
            if 'R005START' in open(lc_path,errors='replace').read(): return r
        log('kein R005START, sende Befehl erneut',i)
    raise RuntimeError('App startet nicht')
# ---- Eingabe: synthetische Spur mit festem Seed, geo fix 1 Hz
class Injector(threading.Thread):
    def __init__(s,path,seed,pause=None):
        super().__init__(daemon=True); s.f=open(path,'w'); s.rng=random.Random(seed); s.stop_=False; s.pause=pause; s.lat=48.0+s.rng.random()/10; s.lon=11.0+s.rng.random()/10
    def run(s):
        t=time.monotonic(); i=0; t0=t; h=s.rng.random()*6.28
        while not s.stop_:
            h+=s.rng.gauss(0,0.2); s.lat+=2.7e-5*math.cos(h); s.lon+=4e-5*math.sin(h)
            el=time.monotonic()-t0
            if not (s.pause and s.pause[0]<=el<s.pause[1]):
                a=time.time(); adb('emu','geo','fix','%.6f'%s.lon,'%.6f'%s.lat,timeout=5); b=time.time()
                s.f.write(f'{i}\t{a:.3f}\t{b:.3f}\t{s.lat:.6f}\t{s.lon:.6f}\n'); s.f.flush()
            i+=1; t+=1.0; d=t-time.monotonic()
            if d>0: time.sleep(d)
class Logcat:
    def __init__(s,path):
        s.f=open(path,'w'); adb('logcat','-G','16M'); adb('logcat','-c'); s.p=subprocess.Popen([ADB,'-s',S,'logcat','-v','epoch','flutter:I','R005:I','ActivityManager:I','DeviceIdleController:I','*:S'],stdout=s.f,stderr=subprocess.DEVNULL)
    def stop(s):
        try: s.p.terminate(); s.p.wait(5)
        except Exception: s.p.kill()
        s.f.close()
def am_start(**kw):
    x=''
    for k,v in kw.items():
        if isinstance(v,bool): x+=f' --ez {k} {str(v).lower()}'
        elif isinstance(v,int): x+=f' --ei {k} {v}'
        else: x+=f' --es {k} {v}'
    return ash(f'am start -n {ACT}{x}')
def pidof(): return ash(f'pidof {PKG}').strip()
def pull(run,dst,prefix='r005'):
    d=f'/data/user/0/{PKG}/no_backup/{prefix}-{run}.db'; os.makedirs(dst,exist_ok=True); sizes={}
    for suf in ['','-wal','-shm']:
        with open(f'{dst}/x.db{suf}','wb') as f:
            r=subprocess.run([ADB,'-s',S,'exec-out',f'run-as {PKG} cat {d}{suf}'],stdout=f,stderr=subprocess.PIPE,timeout=120)
        sizes[suf or 'db']=os.path.getsize(f'{dst}/x.db{suf}')
    return sizes
def rm_runs(): ash(f'run-as {PKG} sh -c "rm -f no_backup/*.db no_backup/*.db-wal no_backup/*.db-shm"')
def fresh():
    ash(f'am force-stop {PKG}'); time.sleep(1)
def dump_db(dbdir,plain=False):
    out=subprocess.run(['dart','run','--resident=false' if False else 'bin/dump.dart',f'{dbdir}/x.db']+(['--plain'] if plain else []),cwd=os.environ['R005_WALTEST'],capture_output=True,text=True,timeout=120)
    return out.stdout,out.stderr
# ---- Langlauf: Ressourcen im Zeitverlauf (nur lesend, adb root ist aktiv)
class Sampler(threading.Thread):
    def __init__(s,o,run,every):
        super().__init__(daemon=True); s.f=open(o+'/resources.tsv','w'); s.m=open(o+'/meminfo.txt','w'); s.run_=run; s.every=every; s.stop_=False
        s.f.write('t\tpid\trss_kb\tpss_kb\tpss_anon_kb\tpss_file_kb\tdb_b\twal_b\tshm_b\tload1\tqemu_self_pct\tqemu_other_pct\tqemu_other\n'); s.f.flush()
    def run(s):
        d=f'/data/user/0/{PKG}/no_backup/r005-{s.run_}.db'; n=0
        while not s.stop_:
            t=time.time()
            o=ash(f'P=$(pidof {PKG}); echo PID=$P; grep -E "^(Rss|Pss|Pss_Anon|Pss_File):" /proc/$P/smaps_rollup; stat -c "F%n=%s" {d} {d}-wal {d}-shm',timeout=20)
            g=lambda k:(re.search(rf'^{k}:\s+(\d+)',o,re.M) or [0,''])[1]
            f=lambda e:(re.search(rf'^F\S*\.db{e}=(\d+)',o,re.M) or [0,''])[1]
            pid=(re.search(r'PID=(\S*)',o) or [0,''])[1]
            ps=sh('ps','-axo','pcpu=,command=',timeout=10); me=emu_pid(); self_=other=0.0; names=[]
            for l in ps.splitlines():
                m=re.match(r'\s*([\d.,]+)\s+(\S*qemu-system\S*).*-avd (\S+)',l)
                if m:
                    c=float(m[1].replace(',','.'))
                    if m[3].startswith('running_app_r005'): self_+=c
                    else: other+=c; names.append(m[3])
            s.f.write(f"{t:.1f}\t{pid}\t{g('Rss')}\t{g('Pss')}\t{g('Pss_Anon')}\t{g('Pss_File')}\t{f('')}\t{f('-wal')}\t{f('-shm')}\t{os.getloadavg()[0]:.2f}\t{self_:.0f}\t{other:.0f}\t{','.join(names)}\n"); s.f.flush()
            if n%20==0:
                s.m.write(f'=== {t:.1f}\n'+ash(f'dumpsys meminfo {PKG}',timeout=30)); s.m.flush()
            n+=1; time.sleep(max(0,s.every-(time.time()-t)))
# ---- Gap
def trial_gap(a,run,base=60):
    o=f'{WORK}/gap/{run}'
    if os.path.exists(o+'/.done'): log('schon da',run); return
    if os.path.exists(o): shutil.rmtree(o)
    os.makedirs(o); json.dump(vars(a)|{'run':run},open(o+'/meta.json','w'),default=str)
    root(); fresh(); ash('dumpsys deviceidle unforce'); ash('dumpsys battery reset'); unlock()
    ash('dumpsys battery unplug'); s0=susp()
    lc=Logcat(o+'/logcat.txt'); inj=Injector(o+'/inject.tsv',a.seed,pause=(base+a.pause_at,base+a.pause_at+a.pause_len) if a.pause_len else None); inj.start()
    time.sleep(3)
    log(start_app(o+'/logcat.txt',cmd='start',host=a.host,run=run,tx=a.tx,sync=a.sync,wake=a.wake,steps=True).strip()[-60:])
    smp=None
    if a.sample: smp=Sampler(o,run,a.sample); smp.start()
    st=open(o+'/state.tsv','w'); phase=[]; elog0=os.path.getsize(f'{WORK}/emulator-api{a.api}.log')
    if a.force_at:  # Probe: erzwungener Suspend (umgeht die Wake-Lock-Zaehlung, kein Beleg zum Wake Lock), bei laufender Einspeisung
        threading.Timer(base+a.force_at,lambda:(st.write(f'{time.time():.1f}\tFORCE mem\n'),st.flush(),ash('echo mem > /sys/power/state',timeout=40),st.write(f'{time.time():.1f}\tFORCE zurueck\n'),st.flush())).start()
    if a.stop_len:  # Kontrolle: Prozess echt anhalten (SIGSTOP), sonst nichts geaendert
        P=pidof(); assert P,'kein PID fuer SIGSTOP'
        threading.Timer(base+a.stop_at,lambda:(ash(f'run-as {PKG} sh -c "kill -STOP {P}"'),st.write(f'{time.time():.1f}\tSIGSTOP {P}\n'))).start()
        threading.Timer(base+a.stop_at+a.stop_len,lambda:(ash(f'run-as {PKG} sh -c "kill -CONT {P}"'),st.write(f'{time.time():.1f}\tSIGCONT {P}\n'))).start()
    t0=time.time(); time.sleep(base); phase.append(('locked_start',time.time()))
    ash('input keyevent 3'); time.sleep(1); ash('input keyevent 223'); time.sleep(3)
    if a.idle: log('force-idle:',ash('dumpsys deviceidle force-idle').strip()[:80])
    phase.append(('idle_start',time.time())); snap=state_snapshot(); log(snap)
    open(o+'/holders-start.txt','w').write(snap['holders'])
    if a.natural:
        # Goldfish haelt den Kernel-Wake-Lock emulator_wake_lock, der Autosuspend verhindert. Loesen: alles Weitere macht system_suspend selbst,
        # die Wake-Lock-Zaehlung bleibt in Kraft. Weckung: RTC-Alarm zum Phasenende; ein Waechter im Geraet setzt dann die Sperre wieder (adb ist waehrend des Schlafs offline).
        N=int(base+a.dur-(time.time()-t0))
        # Weckung von aussen geht nicht (Konsolen-Ereignisse, Netzteil und RTC-wakealarm brachten das Geraet in den Proben nicht zurueck).
        # Laeufe ohne Wake Lock enden deshalb mit SIGKILL des Emulators; die mit FULL gesicherten Zeilen werden danach gelesen, der Schlaf steht im Kernel-Log (R005_EMU_EXTRA=-show-kernel).
        st.write(f'{time.time():.1f}\tWAKE_UNLOCK emulator_wake_lock N={N}\n'); st.flush()
        ash('echo emulator_wake_lock > /sys/power/wake_unlock',timeout=5)
    n=0
    while time.time()-t0<base+a.dur:
        if a.quiet:  # keine adb-Abfragen, die das System wach halten koennten
            time.sleep(min(15,base+a.dur-(time.time()-t0))); continue
        time.sleep(a.poll); snap=state_snapshot(); st.write(f'{time.time():.1f}\t'+json.dumps(snap)+'\n'); st.flush(); n+=1
        if a.idle and snap['deep']!='IDLE':
            st.write(f'{time.time():.1f}\tREIDLE\n'); ash('dumpsys deviceidle force-idle')
    phase.append(('end',time.time()))
    if smp: smp.stop_=True; smp.join(40)
    json.dump(dict(phase=phase,t0=t0),open(o+'/phases.json','w'))
    up=ash('echo up',timeout=8).strip()=='up'; st.write(f'{time.time():.1f}\tADB_ANTWORTET {up}\n'); st.flush(); log('adb antwortet',up)
    if (a.natural or a.force_at) and not up:
        inj.stop_=True; inj.join(5); lc.stop(); kp=emu_pid(); elog=f'{WORK}/emulator-api{a.api}.log'
        st.write(f'{time.time():.1f}\tSIGKILL Emulator\n'); st.flush(); os.kill(kp,signal.SIGKILL); time.sleep(2)
        with open(elog,errors='replace') as f:
            f.seek(elog0); open(o+'/kernel-pm.txt','w').writelines(l for l in f if re.search(r'PM: suspend|Freezing|failed to suspend|Abort:',l))
        emu_start(a.api); wait_boot(); root(); unlock(); time.sleep(3)
        log(pull(run,o+'/live')); log(pull(run,o+'/afterstop')); rm_runs(); ash('dumpsys battery reset')
        json.dump(dict(before=s0,after=dict(success='',fail='',note='nach Neustart nicht lesbar, siehe kernel-pm.txt')),open(o+'/suspend.json','w'))
        open(o+'/.done','w').write('ok'); log('fertig',run,'mit SIGKILL'); return
    s1=susp(); json.dump(dict(before=s0,after=s1),open(o+'/suspend.json','w')); log('suspend',s0.get('success'),'->',s1.get('success'),'fail',s1.get('fail'),s1.get('autosuspend'))
    open(o+'/dmesg-pm.txt','w').write(ash('dmesg | grep -E "PM: |Freezing|Restarting|wakeup|Wakeup|wake"',timeout=30)); open(o+'/suspend_control.txt','w').write(ash('dumpsys suspend_control_internal',timeout=30)); open(o+'/holders-end.txt','w').write(holders())
    if a.natural: ash('echo emulator_wake_lock > /sys/power/wake_lock')
    pidb=pidof(); log('pid',pidb,'services',ash(f'dumpsys activity services {PKG} | grep -E "isForeground|foregroundServiceType|ServiceRecord"').strip()[:300])
    open(o+'/activity.txt','w').write(ash(f'dumpsys activity processes | grep -A12 -E "ProcessRecord.*{PKG}"')+ash('dumpsys deviceidle | tail -5'))
    log(pull(run,o+'/live'))
    fresh(); log(pull(run,o+'/afterstop'))
    inj.stop_=True; inj.join(5); lc.stop()
    if a.force_at: open(o+'/logcat.txt','w').write(adb('logcat','-d','-v','epoch','flutter:I','R005:I','ActivityManager:I','DeviceIdleController:I','*:S',timeout=60))  # adb logcat bricht beim Suspend ab, der Puffer im Geraet hat alles
    ash('dumpsys deviceidle unforce'); ash('dumpsys battery reset'); rm_runs()
    open(o+'/.done','w').write('ok'); log('fertig',run)
# ---- Kill
def trial_kill(a,run,kind):
    o=f'{WORK}/kill/{run}'
    if os.path.exists(o+'/.done'): log('schon da',run); return
    if os.path.exists(o): shutil.rmtree(o)
    os.makedirs(o)
    fresh(); unlock(); time.sleep(1)
    rng=random.Random(run)
    lc=Logcat(o+'/logcat.txt'); inj=Injector(o+'/inject.tsv',rng.randint(0,1<<30)); inj.start(); time.sleep(2)
    start_app(o+'/logcat.txt',cmd='start',host=a.host,run=run,tx=a.tx,sync=a.sync,wake=False)
    wait=rng.uniform(a.minrun,a.maxrun); time.sleep(wait)
    t=time.time(); pid=pidof(); kp=None
    if kind=='proc': ash(f'run-as {PKG} sh -c "kill -9 {pid}"')
    elif kind=='emu':
        inj.stop_=True; kp=emu_pid(); adb('emu','kill',timeout=10)
    elif kind=='sigkill':  # haertere Kontrolle: qemu ohne jede Abschaltlogik
        inj.stop_=True; kp=emu_pid(); os.kill(kp,signal.SIGKILL)
    meta=dict(run=run,host=a.host,kind=kind,tx=a.tx,sync=a.sync,wait=wait,tkill=t,pid=pid)
    inj.stop_=True
    time.sleep(2); inj.join(3)
    bootS=None
    if kp:
        for _ in range(120):
            try: os.kill(kp,0); time.sleep(0.5)
            except OSError: break
        lc.stop(); emu_start(a.api); bootS=wait_boot(); unlock(); time.sleep(3)
    else:
        lc.stop()
    meta['boot_s']=bootS; meta['pid_after_kill']=pidof()
    meta['pull']=pull(run,o+'/after'); so,se=dump_db(o+'/after'); open(o+'/rows.tsv','w').write(so); meta['dump_err']=se[:300]
    lc2=Logcat(o+'/logcat2.txt'); am_start(cmd='verify',run=run); time.sleep(5); lc2.stop(); fresh(); rm_runs()
    json.dump(meta,open(o+'/meta.json','w')); open(o+'/.done','w').write('ok'); log('fertig',run,'wait %.1f'%wait,meta['pull'])
# ---- WAL im Geraet
def trial_wal(a,run,enc):
    o=f'{WORK}/wal-device/{run}'
    if os.path.exists(o+'/.done'): log('schon da',run); return
    if os.path.exists(o): shutil.rmtree(o)
    os.makedirs(o); fresh(); unlock(); lc=Logcat(o+'/logcat.txt'); inj=Injector(o+'/inject.tsv',a.seed); inj.start(); time.sleep(2)
    start_app(o+'/logcat.txt',cmd='start',host='own',run=run,tx=1,sync='FULL',wake=False,enc=enc,autock=0)
    time.sleep(a.dur)
    log(pull(run,o+'/vor-checkpoint')); inj.stop_=True; time.sleep(2); fresh(); lc.stop(); rm_runs()
    open(o+'/.done','w').write('ok')
def swipe_trial(a,run):
    o=f'{WORK}/swipe/{run}'
    if os.path.exists(o+'/.done'): log('schon da',run); return
    if os.path.exists(o): shutil.rmtree(o)
    os.makedirs(o); fresh(); ash('dumpsys battery reset'); unlock(); lc=Logcat(o+'/logcat.txt'); inj=Injector(o+'/inject.tsv',a.seed); inj.start(); time.sleep(2)
    start_app(o+'/logcat.txt',cmd='start',host=a.host,run=run,tx=a.tx,sync=a.sync,wake=False)
    time.sleep(a.dur)
    size=re.search(r'(\d+)x(\d+)',ash('wm size')); W,H=int(size[1]),int(size[2])
    pid0=pidof(); r0=ash('dumpsys activity recents | grep -c "'+PKG+'"').strip()
    tries=0; r1=r0; shot0=''
    # Die Geste wirkt nicht immer (Uebersicht noch nicht bereit): wiederholen, bis die Aufgabe weg ist; recents_after belegt die Wirkung
    while tries<4 and r1!='0':
        tries+=1; ash('input keyevent 3'); time.sleep(1); ash('input keyevent 187'); time.sleep(4); shot0=ash('dumpsys window | grep -E "mCurrentFocus|mFocusedApp"').strip()
        ash(f'input swipe {W//2} {H//2} {W//2} {H//20} 200'); time.sleep(2)
        r1=ash('dumpsys activity recents | grep -c "'+PKG+'"').strip(); log('swipe versuch',tries,'recents',r1)
    ash('input keyevent 3')
    tsw=time.time(); time.sleep(a.dur)
    meta=dict(run=run,host=a.host,swipe_tries=tries,pid0=pid0,pid1=pidof(),recents_before=r0,recents_after=r1,focus=shot0,tswipe=tsw)
    meta['pull']=pull(run,o+'/live'); so,se=dump_db(o+'/live'); open(o+'/rows.tsv','w').write(so)
    meta['svc']=ash(f'dumpsys activity services {PKG} | grep -E "ServiceRecord|isForeground"')[:400]
    inj.stop_=True; time.sleep(1); fresh(); lc.stop(); rm_runs()
    json.dump(meta,open(o+'/meta.json','w')); open(o+'/.done','w').write('ok'); log(meta)
def main():
    ap=argparse.ArgumentParser(description=__doc__); ap.add_argument('cmd',choices=['boot','kill-emu','gap','kill','wal','swipe','bench','smoke'])
    ap.add_argument('--api',type=int,default=36); ap.add_argument('--host',default='own'); ap.add_argument('--wake',type=int,default=0)
    ap.add_argument('--idle',type=int,default=1); ap.add_argument('--tx',type=int,default=1); ap.add_argument('--sync',default='FULL')
    ap.add_argument('--dur',type=int,default=600); ap.add_argument('--rep',type=int,default=1); ap.add_argument('--seed',type=int,default=42); ap.add_argument('--kind',default='proc')
    ap.add_argument('--minrun',type=float,default=20); ap.add_argument('--maxrun',type=float,default=40); ap.add_argument('--pause-at',type=int,default=0); ap.add_argument('--pause-len',type=int,default=0); ap.add_argument('--stop-at',type=int,default=0); ap.add_argument('--stop-len',type=int,default=0)
    ap.add_argument('--natural',type=int,default=0); ap.add_argument('--force-at',type=int,default=0); ap.add_argument('--post',type=int,default=30); ap.add_argument('--quiet',type=int,default=0); ap.add_argument('--n',type=int,default=300); ap.add_argument('--tag',default=''); ap.add_argument('--poll',type=int,default=15); ap.add_argument('--sample',type=int,default=0)
    a=ap.parse_args(); a.wake=bool(a.wake); a.idle=bool(a.idle)
    os.makedirs(WORK,exist_ok=True)
    if a.cmd=='boot':
        if emu_pid() is None: emu_start(a.api)
        wait_boot(); setup(); root(); unlock(); log('bereit',ash('getprop ro.build.version.sdk').strip())
    elif a.cmd=='kill-emu':
        p=emu_pid()
        if p:
            adb('emu','kill',timeout=10)
            for _ in range(60):
                try: os.kill(p,0); time.sleep(1)
                except OSError: break
        try: os.remove(emu_pidfile())
        except OSError: pass
        log('Emulator gestoppt')
    elif a.cmd=='gap':
        for r in range(a.rep):
            run=f'a{a.api}_{a.host}_w{int(a.wake)}_i{int(a.idle)}_{a.dur}s{a.tag}_r{r}'
            a.seed=42+r; trial_gap(a,run)
    elif a.cmd=='kill':
        for r in range(a.rep):
            trial_kill(a,f'a{a.api}_{a.kind}'+('' if a.host=='own' else '_'+a.host)+f'_tx{a.tx}_{a.sync}{a.tag}_r{r}',a.kind)
    elif a.cmd=='wal':
        trial_wal(a,f'a{a.api}_enc{a.tag}',True); trial_wal(a,f'a{a.api}_plain{a.tag}',False)
    elif a.cmd=='swipe':
        for r in range(a.rep): swipe_trial(a,f'a{a.api}_{a.host}{a.tag}_r{r}')
    elif a.cmd=='bench':
        run=f'a{a.api}{a.tag}'; o=f'{WORK}/bench/{run}'
        os.makedirs(o,exist_ok=True); fresh(); unlock(); lc=Logcat(o+'/logcat.txt'); am_start(cmd='bench',run=run,n=a.n)
        t0=time.time()
        while time.time()-t0<3600 and f'R005BENCHDONE' not in open(o+'/logcat.txt').read(): time.sleep(5)
        lc.stop(); fresh(); rm_runs(); open(o+'/.done','w').write('ok'); log('bench fertig %.0fs'%(time.time()-t0))
main()
