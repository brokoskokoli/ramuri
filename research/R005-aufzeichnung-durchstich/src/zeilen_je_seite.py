#!/usr/bin/env python3
"""R005: Warum die erste Seitenteilung nicht ueberall bei derselben Zeile liegt. Rechnet aus den Feldern des Logs die Zelle je Zeile nach dem Datensatzformat von SQLite (fileformat2.html#record_format)
und damit die Zeilen je Blattseite, und vergleicht mit dbstat an einer frischen Kopie (Blattseite 3). Reserve je Seite: verschluesselt 32 Byte, Klartext 0.
Die Teilungszeile (Zellen + 1) ist nur in wal-device direkt zu sehen: Zwei Commits Schema, danach eine Zeile je Commit, der erste Commit mit mehreren Frames ist die Teilung. In den Kill-Serien ist das WAL schon ueberschrieben.
Aufruf: zeilen_je_seite.py <R005_WORK>; braucht R005_WALTEST und dart."""
import glob,os,re,shutil,struct,subprocess,sys,tempfile
W=sys.argv[1]; WT=os.environ['R005_WALTEST']; MARK='R005KLARTEXTMARKER'
def vl(n):
    c=1
    while n>=128: n>>=7; c+=1
    return c
def ints(i):
    for s,b in ((1,1),(2,2),(3,3),(4,4),(5,6),(6,8)):
        if -(1<<(8*b-1))<=i<(1<<(8*b-1)): return s,b
def cell(seq,run,tf,tr,up):
    note=f'{MARK}-{seq}'
    t=[0,13+2*len(run),7,7]; z=len(run)+16  # seq als rowid-Alias NULL, lat und lon REAL.
    for v in (tf,tr,up):
        s,b=ints(v); t.append(s); z+=b
    t.append(13+2*len(note)); z+=len(note)
    h=sum(vl(x) for x in t); h+=vl(h+1)
    return 2+vl(h+z)+vl(seq)+h+z  # Zeiger, Laenge, rowid, Datensatz
def capacity(R,reserve):
    free=4096-reserve-8; n=0
    for s,run,tf,tr in R:
        c=cell(s,run,tf,tr,tr//1000000)
        if c>free: break
        free-=c; n+=1
    return n
def first_split(src):
    b=open(src+'/x.db-wal','rb').read(); i=32; commit=0; cur=[]
    while i+4120<=len(b):
        pg,c=struct.unpack('>2I',b[i:i+8]); cur.append(pg); i+=4120
        if c:
            commit+=1
            if commit>2 and len(cur)>1: return commit-2,cur
            cur=[]
    return None,None
ok=0;n=0
print('Lauf Laenge-Name tfix-Byte Zelle-bei-Zeile-30 Zeilen-je-Blatt-gerechnet Zeilen-je-Blatt-dbstat gleich Teilungszeile-gesehen Seiten-der-Teilung')
for p in sorted(glob.glob(W+'/wal-device/*'))+sorted(glob.glob(W+'/kill/*_FULL_ck10b_r0'))+sorted(glob.glob(W+'/kill/*_NORMAL_ck10b_r0')):
    R=[(int(m[2]),m[1],int(m[3]),int(m[4])) for m in (re.search(r'R005RCV run=(\S+) seq=(\d+) tfix=(\d+) trecv=(\d+)',l) for l in open(p+'/logcat.txt',errors='replace')) if m]
    plain='plain' in p; dev=os.path.isdir(p+'/vor-checkpoint'); src=p+('/vor-checkpoint' if dev else '/before-open')
    with tempfile.TemporaryDirectory() as t:
        for f in ('x.db','x.db-wal'): shutil.copy2(src+'/'+f,t+'/'+f)
        o=subprocess.run(['dart','run','bin/pagestat.dart',t+'/x.db']+(['--plain'] if plain else []),cwd=WT,capture_output=True,text=True).stdout
    leaf=[l.split('\t') for l in o.splitlines() if '\tleaf' in l][0]; got=int(leaf[3]); calc=capacity(R,0 if plain else 32); n+=1; ok+=got==calc
    sp,pg=first_split(src) if dev else (None,None)
    print(os.path.basename(p),len(R[0][1]),ints(R[0][2])[1],cell(30,R[0][1],R[0][2],R[0][3],R[0][3]//1000000),calc,got,got==calc,sp if sp else '-',pg if pg else '-')
print(f'gleich {ok} von {n}')
