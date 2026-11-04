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
