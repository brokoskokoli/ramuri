"""R005: liest die Klartext-Koepfe einer WAL-Datei (sqlite3mc verschluesselt nur die Seiteninhalte). Aufbau laut sqlite.org/fileformat2.html#walformat.
wal_info: Frames der aktuellen Generation (Salt gleich Kopf) und liegen gebliebene Frames einer frueheren Generation. ckpt_seq > 0 heisst: das WAL wurde nach einem Checkpoint neu begonnen."""
import struct
def wal_info(path):
    try: b=open(path,'rb').read()
    except OSError: return dict(size=0,valid_header=False)
    if len(b)<32: return dict(size=len(b),valid_header=False)
    magic,ver,page,seq,s1,s2,_,_=struct.unpack('>8I',b[:32])
    if magic not in (0x377f0682,0x377f0683): return dict(size=len(b),valid_header=False)
    cur=old=commits=0; i=32; fs=24+page
    while i+fs<=len(b):
        pg,commit,f1,f2=struct.unpack('>4I',b[i:i+16])
        if (f1,f2)==(s1,s2):
            cur+=1; commits+=commit>0
        elif pg or commit or f1 or f2: old+=1
        i+=fs
    return dict(size=len(b),valid_header=True,page=page,ckpt_seq=seq,frames_cur=cur,commit_frames=commits,frames_old=old)
def wal_frames(path):
    """Geht das WAL ab wie die Wiederherstellung von SQLite (fileformat2.html#walformat): Salt gleich Kopf UND Pruefsummenkette stimmt, Stopp beim ersten Fehler; gueltig sind nur Frames bis zum letzten Commit-Frame.
    Die Pruefsumme laeuft ueber die gespeicherten Bytes, geht also auch beim verschluesselten WAL (geprueft an wal-device/a36_enc_b, a31_enc). Kein Kopf oder Kopf-Pruefsumme falsch: keine gueltigen Frames."""
    try: b=open(path,'rb').read()
    except OSError: return dict(valid_header=False,frames=[],pages=[],tail=0,salt_only=0)
    if len(b)<32: return dict(valid_header=False,frames=[],pages=[],tail=0,salt_only=0)
    magic,ver,page,seq,s1,s2,c1,c2=struct.unpack('>8I',b[:32])
    if magic not in (0x377f0682,0x377f0683): return dict(valid_header=False,frames=[],pages=[],tail=0,salt_only=0)
    e='>' if magic&1 else '<'
    def ck(d,x,y):
        w=struct.unpack(e+'%dI'%(len(d)//4),d)
        for i in range(0,len(w),2):
            x=(x+w[i]+y)&0xffffffff; y=(y+w[i+1]+x)&0xffffffff
        return x,y
    a,c=ck(b[:24],0,0)
    if (a,c)!=(c1,c2): return dict(valid_header=False,frames=[],pages=[],tail=0,salt_only=0)
    i=32; fs=24+page; good=[]; salt=0
    while i+fs<=len(b):
        pg,commit,f1,f2,x1,x2=struct.unpack('>6I',b[i:i+24])
        if (f1,f2)!=(s1,s2): break
        salt+=1
        a,c=ck(b[i:i+8],a,c); a,c=ck(b[i+24:i+fs],a,c)
        if (a,c)!=(x1,x2): break
        good.append((pg,commit)); i+=fs
    last=max((n for n,(_,cm) in enumerate(good,1) if cm),default=0)
    frames=good[:last]
    return dict(valid_header=True,frames=[p for p,_ in frames],pages=sorted({p for p,_ in frames}),tail=len(good)-last,salt_only=salt-len(good))
