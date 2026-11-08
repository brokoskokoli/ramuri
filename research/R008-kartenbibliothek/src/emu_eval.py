"""Wertet einen emu-Lauf aus (nur lesen): je Phase Netz (Richtung, Gegenstellen, DNS-Antworten, SNI, Zuordnung),
CPU, Bilder (Flutter FrameTiming aus dem App-Log), Netz-Zaehler der App, Miniaturzeiten.
Usage: emu_eval.py <emu-ausgabeordner>  Ausgabe: Tabellen (TSV) nach stdout, Details nach <ordner>/eval.json
Zuordnung der Gegenstellen: 1. DNS-Antworten (A/AAAA) aus allen Mitschnitten des Laufs, 2. SNI auf dieser IP,
3. Adressbereich (Cloudflare laut https://www.cloudflare.com/ips/, Google-Netze). Lokale Adressen werden ignoriert."""
import ipaddress, json, os, re, statistics, struct, sys, collections

CF = [ipaddress.ip_network(n) for n in (
    '173.245.48.0/20 103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 108.162.192.0/18 190.93.240.0/20 '
    '188.114.96.0/20 197.234.240.0/22 198.41.128.0/17 162.158.0.0/15 104.16.0.0/13 104.24.0.0/14 172.64.0.0/13 131.0.72.0/22 '
    '2400:cb00::/32 2606:4700::/32 2803:f800::/32 2405:b500::/32 2405:8100::/32 2a06:98c0::/29 2c0f:f248::/32').split()]
GOOGLE = [ipaddress.ip_network(n) for n in (
    '8.8.4.0/24 8.8.8.0/24 34.0.0.0/9 35.184.0.0/13 64.233.160.0/19 66.102.0.0/20 66.249.64.0/19 72.14.192.0/18 74.125.0.0/16 '
    '108.177.0.0/17 142.250.0.0/15 172.217.0.0/16 172.253.0.0/16 173.194.0.0/16 209.85.128.0/17 216.58.192.0/19 216.239.32.0/19 '
    '2001:4860::/32 2404:6800::/32 2607:f8b0::/32 2800:3f0::/32 2a00:1450::/32 2c0f:fb50::/32').split()]

def local(a):
    ip = ipaddress.ip_address(a)
    return ip.is_private or ip.is_link_local or ip.is_multicast or ip.is_loopback or a.startswith('fec0')

def name_dns(q, i):
    labels = []
    while i < len(q):
        l = q[i]
        if l == 0: return '.'.join(labels), i + 1
        if l & 0xc0 == 0xc0:
            n, _ = name_dns(q, ((l & 0x3f) << 8) | q[i + 1]); return '.'.join(labels + [n] if n else labels), i + 2
        labels.append(q[i + 1:i + 1 + l].decode(errors='replace')); i += 1 + l
    return '.'.join(labels), i

def packets(path):
    b = open(path, 'rb').read()
    if len(b) < 24: return
    e = '<' if struct.unpack('<I', b[:4])[0] in (0xa1b2c3d4, 0xa1b23c4d) else '>'
    link = struct.unpack(e + 'I', b[20:24])[0]; off = 24
    while off + 16 <= len(b):
        _, _, incl, _ = struct.unpack(e + 'IIII', b[off:off + 16]); off += 16
        pkt = b[off:off + incl]; off += incl
        if link == 1:
            if len(pkt) < 14 or pkt[12:14] not in (b'\x08\x00', b'\x86\xdd'): continue
            ip = pkt[14:]
        elif link in (101, 228): ip = pkt
        else: continue
        if len(ip) >= 40 and ip[0] >> 4 == 6:
            proto, s, d, pl = ip[6], str(ipaddress.ip_address(ip[8:24])), str(ipaddress.ip_address(ip[24:40])), ip[40:]
        elif len(ip) >= 20 and ip[0] >> 4 == 4:
            ihl = (ip[0] & 15) * 4; proto, s, d, pl = ip[9], '.'.join(map(str, ip[12:16])), '.'.join(map(str, ip[16:20])), ip[ihl:]
        else: continue
        yield proto, s, d, pl, len(ip)

def dns_info(pl):
    """(frage, [antwort-IPs]) aus einem UDP-DNS-Paket."""
    q = pl[8:]
    if len(q) < 12: return None, []
    qd, an = struct.unpack('>HH', q[4:8]); i = 12; qname = None
    for _ in range(qd):
        qname, i = name_dns(q, i); i += 4
    ips = []
    for _ in range(an):
        try:
            _, i = name_dns(q, i); t, _, _, rl = struct.unpack('>HHIH', q[i:i + 10]); i += 10
            if t == 1 and rl == 4: ips.append(str(ipaddress.ip_address(q[i:i + 4])))
            if t == 28 and rl == 16: ips.append(str(ipaddress.ip_address(q[i:i + 16])))
            i += rl
        except Exception: break
    return qname, ips

def sni_of(pl):
    data = pl[(pl[12] >> 4) * 4:]
    if not (len(data) > 43 and data[0] == 0x16 and data[5] == 0x01): return None
    try:
        p = 43; p += 1 + data[p]; p += 2 + struct.unpack('>H', data[p:p + 2])[0]; p += 1 + data[p]
        end = p + 2 + struct.unpack('>H', data[p:p + 2])[0]; p += 2
        while p + 4 <= end:
            t, l = struct.unpack('>HH', data[p:p + 4]); p += 4
            if t == 0: return data[p + 5:p + l].decode(errors='replace')
            p += l
    except Exception: return None

def main(d):
    pcaps = sorted(f[:-5] for f in os.listdir(d) if f.endswith('.pcap'))
    ip2name = collections.defaultdict(set); per = {}
    for ph in pcaps:  # Durchgang 1: DNS-Antworten und SNI aus dem ganzen Lauf
        for proto, s, dd, pl, n in packets(f'{d}/{ph}.pcap'):
            if proto == 17 and len(pl) >= 8 and struct.unpack('>H', pl[0:2])[0] == 53:
                qn, ips = dns_info(pl)
                for a in ips: ip2name[a].add(qn)
            if proto == 6 and len(pl) >= 20:
                sn = sni_of(pl)
                if sn: ip2name[dd].add('sni:' + sn)
    def cls(a):
        names = sorted(x.replace('sni:', '') for x in ip2name.get(a, ()))
        net = 'cloudflare' if any(ipaddress.ip_address(a) in n for n in CF) else 'google' if any(ipaddress.ip_address(a) in n for n in GOOGLE) else 'sonst'
        return (','.join(sorted(set(names))) or '?') + f' [{net}]'
    for ph in pcaps:
        dns, sni, peers, npk = collections.Counter(), collections.Counter(), collections.defaultdict(lambda: [0, 0]), 0
        for proto, s, dd, pl, n in packets(f'{d}/{ph}.pcap'):
            npk += 1
            if proto == 17 and len(pl) >= 8 and struct.unpack('>H', pl[2:4])[0] == 53:
                qn, _ = dns_info(pl); dns[qn] += 1
            if proto == 6 and len(pl) >= 20:
                sn = sni_of(pl)
                if sn: sni[sn] += 1
            if local(s) and not local(dd): peers[dd][1] += n   # hinaus
            elif local(dd) and not local(s): peers[s][0] += n   # herein
        groups = collections.defaultdict(lambda: [0, 0, set()])
        for a, (i, o) in peers.items():
            g = groups[cls(a)]; g[0] += i; g[1] += o; g[2].add(a)
        per[ph] = {'packets': npk, 'dns': dict(dns), 'sni': dict(sni),
                   'peers': {k: {'in': v[0], 'out': v[1], 'ips': sorted(v[2])} for k, v in sorted(groups.items(), key=lambda x: -x[1][0])}}
    # Phasen: CPU und App-Log
    rows = [l.rstrip('\n').split('\t') for l in open(f'{d}/phases.tsv')][1:]
    out = []
    for app, ph, route, sec, c0, c1 in rows:
        key = f'{app}-{ph}'; lg = open(f'{d}/{key}.logcat.txt', errors='replace').read().splitlines()
        pid = next((l.split()[2] for l in lg if 'Impeller' in l), None)
        own = [l for l in lg if pid and len(l.split()) > 2 and l.split()[2] == pid]
        fr = [int(m.group(1)) for l in own for m in [re.search(r'frames_30s=(\d+)', l)] if m]
        st = [m for l in own for m in [re.search(r'net_req=(\d+) net_bytes=(\d+)', l)] if m]
        gen = [int(m.group(1)) for l in own for m in [re.search(r'thumb gen ms=(\d+)', l)] if m]
        png = [int(m.group(1)) for l in own for m in [re.search(r'png_bytes=(\d+)', l)] if m]
        ld = [m.group(1) for l in own for m in [re.search(r'thumbs_loaded=(\d+)', l)] if m]
        p = per.get(key, {}); peers = p.get('peers', {})
        cf_in = sum(v['in'] for k, v in peers.items() if '[cloudflare]' in k)
        other = {k: v['in'] + v['out'] for k, v in peers.items() if '[cloudflare]' not in k}
        cpu = (int(c1) - int(c0)) / int(sec) if c0 != 'NA' and c1 != 'NA' else None   # Ticks/s, 100 Hz -> % eines Kerns
        out.append({'app': app, 'phase': ph, 'route': route, 's': int(sec), 'cpu_pct_core': cpu,
                    'frames': (fr[-1] if fr else None), 'frames_n': len(fr), 'fps_mean': (round(fr[-1] / (30 * len(fr)), 1) if fr else None),
                    'app_net_req': (int(st[-1].group(1)) if st else None), 'app_net_bytes': (int(st[-1].group(2)) if st else None),
                    'thumbs_gen_n': len(gen), 'thumb_ms_median': (statistics.median(gen) if gen else None),
                    'thumb_ms_min': (min(gen) if gen else None), 'thumb_ms_max': (max(gen) if gen else None),
                    'png_median': (statistics.median(png) if png else None), 'thumbs_loaded': (ld[-1] if ld else None),
                    'cf_in_bytes': cf_in, 'dns': p.get('dns'), 'sni': p.get('sni'), 'nicht_cloudflare': other})
    json.dump({'phases': out, 'pcap': per, 'ip2name': {k: sorted(v) for k, v in ip2name.items()}}, open(f'{d}/eval.json', 'w'), indent=1)
    print('app\tphase\ts\tcpu_%kern\tframes(fps)\tapp_req\tapp_MB\tcf_in_kB\tthumbs(n,median ms,min-max,png kB)\tDNS\tSNI\tandere Gegenstellen (Bytes)')
    for r in out:
        th = f"{r['thumbs_gen_n']},{r['thumb_ms_median']},{r['thumb_ms_min']}-{r['thumb_ms_max']},{(r['png_median'] or 0)/1000:.1f}" if r['thumbs_gen_n'] else (f"loaded={r['thumbs_loaded']}" if r['thumbs_loaded'] else '-')
        print('\t'.join(map(str, [r['app'], r['phase'], r['s'], f"{r['cpu_pct_core']:.2f}" if r['cpu_pct_core'] is not None else 'NA',
              f"{r['frames']}({r['fps_mean']})" if r['frames'] is not None else '-', r['app_net_req'],
              f"{r['app_net_bytes']/1e6:.2f}" if r['app_net_bytes'] is not None else '-', round(r['cf_in_bytes'] / 1000, 1), th,
              ','.join(f'{k}:{v}' for k, v in (r['dns'] or {}).items()) or '-', ','.join(f'{k}:{v}' for k, v in (r['sni'] or {}).items()) or '-',
              '; '.join(f'{k} {v}' for k, v in r['nicht_cloudflare'].items()) or '-'])))
    print('\nos-idle/positivkontrolle:')
    for k in ('os-idle', 'positivkontrolle'):
        print(k, json.dumps(per.get(k), ensure_ascii=False))
    print('\nCloudflare-IPs und Namen:')
    for k, v in sorted(ip2name.items()):
        if any(ipaddress.ip_address(k) in n for n in CF): print(k, v)

if __name__ == '__main__':
    main(sys.argv[1])
