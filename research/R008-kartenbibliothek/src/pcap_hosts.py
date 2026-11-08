"""Liest einen Emulator-Mitschnitt (pcap) und listet DNS-Anfragen, TLS-SNI und Ziel-IPs mit Bytes.
Keine Kachelkoordinaten: Inhalte sind TLS-verschluesselt, ausgegeben werden nur Hostnamen.
Usage: pcap_hosts.py <datei.pcap>   Ausgabe: JSON {dns: {...}, sni: {...}, dst: {...}, packets: n}"""
import json, struct, sys, collections

def parse(path):
    b = open(path, 'rb').read()
    magic = struct.unpack('<I', b[:4])[0]
    e = '<' if magic in (0xa1b2c3d4, 0xa1b23c4d) else '>'
    link = struct.unpack(e + 'I', b[20:24])[0]
    off, n = 24, 0
    dns, sni, dst, ports = collections.Counter(), collections.Counter(), collections.Counter(), collections.Counter()
    while off + 16 <= len(b):
        _, _, incl, _ = struct.unpack(e + 'IIII', b[off:off + 16]); off += 16
        pkt = b[off:off + incl]; off += incl; n += 1
        if link == 1:  # Ethernet
            if len(pkt) < 14 or pkt[12:14] not in (b'\x08\x00', b'\x86\xdd'): continue
            ip = pkt[14:]
        elif link in (101, 228):  # raw IPv4
            ip = pkt
        else:
            continue
        if len(ip) >= 40 and ip[0] >> 4 == 6:  # IPv6 ohne Erweiterungskoepfe
            proto = ip[6]; d = ip[24:40].hex(':', 2); pl = ip[40:]
        elif len(ip) >= 20 and ip[0] >> 4 == 4:
            ihl = (ip[0] & 15) * 4; proto = ip[9]; d = '.'.join(map(str, ip[16:20])); pl = ip[ihl:]
        else:
            continue
        dst[d] += len(ip)
        if proto in (6, 17) and len(pl) >= 4:  # Zielport (DoT 853, QUIC udp/443 fallen hier auf)
            ports[('tcp' if proto == 6 else 'udp') + '/' + str(struct.unpack('>H', pl[2:4])[0])] += 1
        if proto == 17 and len(pl) >= 8 and struct.unpack('>H', pl[2:4])[0] == 53:
            q = pl[8 + 12:]; labels = []; i = 0
            while i < len(q) and q[i]:
                labels.append(q[i + 1:i + 1 + q[i]].decode(errors='replace')); i += 1 + q[i]
            dns['.'.join(labels)] += 1
        if proto == 6 and len(pl) >= 20:
            data = pl[(pl[12] >> 4) * 4:]
            if len(data) > 43 and data[0] == 0x16 and data[5] == 0x01:  # TLS Handshake ClientHello
                try:
                    p = 43; p += 1 + data[p]; p += 2 + struct.unpack('>H', data[p:p + 2])[0]; p += 1 + data[p]
                    end = p + 2 + struct.unpack('>H', data[p:p + 2])[0]; p += 2
                    while p + 4 <= end:
                        t, l = struct.unpack('>HH', data[p:p + 4]); p += 4
                        if t == 0: sni[data[p + 5:p + l].decode(errors='replace')] += 1
                        p += l
                except Exception:
                    pass
    return {'packets': n, 'dns': dict(dns), 'sni': dict(sni), 'dst_bytes': dict(dst.most_common(15)), 'dst_ports': dict(ports.most_common(15))}

if __name__ == '__main__':
    print(json.dumps(parse(sys.argv[1]), indent=1))
