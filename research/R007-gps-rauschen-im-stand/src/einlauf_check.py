import sys,glob,math,statistics as st,random
d=sys.argv[1]
def dist(a,b):
    R=6371000;la=math.radians((a[0]+b[0])/2)
    return R*math.hypot(math.radians(b[0]-a[0]),math.radians(b[1]-a[1])*math.cos(la))
bins={}  # second bin -> per session (dist,dur)
sess=[]
for f in glob.glob(d+'/ncount__*.tsv'):
    rows=[l.split('\t') for l in open(f).read().split('\n')[1:] if l]
    if len(rows)<20: continue
    r=[(int(x[0])/1000,float(x[1]),float(x[2]),float(x[4]) if x[4] else None) for x in rows]
    t0=r[0][0]; s={}
    for a,b in zip(r,r[1:]):
        dt=b[0]-a[0]
        if dt<=0 or dt>2: continue
        k=int((b[0]-t0)//5)*5
        x=s.setdefault(k,[0,0]); x[0]+=dist(a[1:3],b[1:3]); x[1]+=dt
    sess.append(s)
print('sessions',len(sess))
for k in sorted({k for s in sess for k in s}):
    v=[s[k][0]/s[k][1]*60 for s in sess if k in s and s[k][1]>0]
    tot=sum(s[k][0] for s in sess if k in s)/sum(s[k][1] for s in sess if k in s)*60
    print(f'{k:3d}-{k+5:3d}s n={len(v):3d} median {st.median(v):7.1f} m/min  pooled {tot:7.1f} m/min')
# ab 10 vs ab 20: pooled und Median je Sitzung
for lo in (10,15,20):
    v=[]
    for s in sess:
        D=sum(x[0] for k,x in s.items() if k>=lo);T=sum(x[1] for k,x in s.items() if k>=lo)
        if T>=4: v.append(D/T*60)
    print(f'ab {lo}s: n={len(v)} median je Sitzung {st.median(v):.1f} m/min -> {st.median(v)*3/4860*100:.2f}% bei 3 Stopps; mean {st.mean(v):.1f}')
