#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Erzeugt Testvektoren fuer das Archivformat (docs/contracts/archive.md).

Unabhaengig vom Dart-Code, nur nach dem Vertragstext geschrieben.
Aufruf:  python -I tool/archive_vectors/make_vectors.py --out <verzeichnis>
Alle Daten sind synthetisch; Passwoerter und Salze sind fest.
"""
import argparse, gzip, hashlib, json, os, struct, unicodedata

from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.argon2 import Argon2id

MAGIC = b"RUNARCHV"
MEM, T, P, KLEN = 65536, 3, 1, 32
CHUNK = 65536


def header(salt: bytes) -> bytes:
    h = MAGIC + struct.pack(">HIIBB", 1, MEM, T, P, KLEN) + salt
    assert len(h) == 36
    return h


def derive(password: bytes, salt: bytes) -> bytes:
    return Argon2id(salt=salt, length=KLEN, iterations=T, lanes=P,
                    memory_cost=MEM).derive(password)


def nonce(counter: int, last: bool) -> bytes:
    return counter.to_bytes(11, "big") + (b"\x01" if last else b"\x00")


def split(pt: bytes):
    """Stuecke nach 3.2: leer -> ein leeres letztes Stueck; sonst letztes nicht leer."""
    if not pt:
        return [b""]
    return [pt[i:i + CHUNK] for i in range(0, len(pt), CHUNK)]


def encrypt(pt: bytes, salt: bytes, key: bytes):
    h = header(salt)
    aead = ChaCha20Poly1305(key)
    parts = split(pt)
    cts = [aead.encrypt(nonce(i, i == len(parts) - 1), c, h)
           for i, c in enumerate(parts)]
    return h, cts


def stream(label: str, n: int) -> bytes:
    """Deterministische Pseudo-Bytes (SHA-256 im Zaehlermodus), nicht komprimierbar."""
    out, i = bytearray(), 0
    while len(out) < n:
        out += hashlib.sha256(f"{label}/{i}".encode()).digest()
        i += 1
    return bytes(out[:n])


SECTIONS = ["runs", "laps", "run_gaps", "raw_positions", "raw_heart_rates",
            "raw_altitudes", "raw_steps", "preprocessing_results",
            "preprocessed_samples", "preprocessed_spans", "rated_sections",
            "computed_values", "value_sections", "profile", "settings",
            "known_devices", "goals", "plans", "active_warning"]


def archive_rows():
    t0 = 1792000000000000
    r = {s: [] for s in SECTIONS}
    r["runs"] = [
        dict(id=1, state="finished", started_at_us=t0, ended_at_us=t0 + 600_000_000, ended_utc_offset_s=3600),
        dict(id=7, state="active", started_at_us=t0 + 86_400_000_000, ended_at_us=None, ended_utc_offset_s=None),
    ]
    r["laps"] = [dict(id=1, run_id=1, lap_index=1, marked_at_us=t0 + 300_000_000, lap_time_s=300.5)]
    r["run_gaps"] = [dict(id=1, run_id=1, kind="manual_pause", start_us=t0 + 100_000_000, end_us=None)]
    r["raw_positions"] = [
        dict(id=1, run_id=1, time_us=t0 + 1_000_000, source="gps", state="present", latitude_deg=52.5, longitude_deg=13.25,
             accuracy_m=4.5, speed_mps=3.0, speed_accuracy_mps=0.5, vertical_accuracy_m=None),
        dict(id=2, run_id=1, time_us=t0 + 2_000_000, source="gps", state="unavailable", latitude_deg=None,
             longitude_deg=None, accuracy_m=None, speed_mps=None, speed_accuracy_mps=None, vertical_accuracy_m=None),
    ]
    r["raw_heart_rates"] = [dict(id=1, run_id=1, time_us=t0 + 1_000_000, source="ble", state="present", bpm=150, contact="good"),
                            dict(id=2, run_id=1, time_us=t0 + 2_000_000, source="ble", state="unavailable", bpm=None, contact="unsupported")]
    r["raw_altitudes"] = [dict(id=1, run_id=1, time_us=t0 + 1_000_000, source="baro", state="present", altitude_m=34.25, vertical_accuracy_m=1.0)]
    r["raw_steps"] = [dict(id=1, run_id=1, time_us=t0 + 1_000_000, source="pedometer", state="present", step_count=1234)]
    r["preprocessing_results"] = [dict(
        id=1, run_id=1, method="basic", method_version=1, parameter_version=1, computed_at_us=t0 + 700_000_000,
        total_time_s=600.0, moving_time_s=590, distance_m=2000.0, bridged_distance_m=0, average_bpm=150.5,
        max_bpm=172, median_bpm=151.0, best_pace_s_per_km=285.0, lap_count=1, heart_rate_time_s=None)]
    r["preprocessed_samples"] = [dict(id=1, run_id=1, channel="position", raw_id=1, time_us=t0 + 1_000_000, state="present", discard_reason=None),
                                 dict(id=2, run_id=1, channel="position", raw_id=2, time_us=t0 + 2_000_000, state="discarded", discard_reason="accuracy")]
    r["preprocessed_spans"] = [dict(id=1, run_id=1, kind="settling", start_us=t0 + 10_000_000, end_us=t0 + 20_000_000)]
    r["rated_sections"] = [dict(
        id=1, run_id=1, start_us=t0, end_us=t0 + 600_000_000, method="rating", method_version=1, parameter_version=1,
        assessed_at_us=t0 + 710_000_000, heart_rate_present=550, heart_rate_estimated=0, heart_rate_unavailable=40,
        heart_rate_discarded=10, position_present=580, position_estimated=0, position_unavailable=10, position_discarded=10,
        missing_heart_rate_share=0.0666667, longest_heart_rate_gap_s=12.5, meets_heart_rate_gap_rule=1,
        settling_overlap_s=0, settling_share=0, gps_gaps='[[1,2,0]]')]
    # Je (Lauf oder Tag, value_key) genau eine Zeile je Rolle (Vertrag 4.2); original
    # vor current, ids aufsteigend. value_sections folgen der Reihenfolge der Werte.
    def cv(i, run, day, key, role, val, **kw):
        d = dict(id=i, run_id=run, day=day, value_key=key, role=role, value_real=val, unit="au",
                 computed_at_us=t0 + 700_000_000 + i * 10_000_000, data_from_us=None, data_to_us=None,
                 measurement_count=1, sources="[]", method="trimp", method_version=1, parameter_version=1,
                 quality="good", unavailable_reason=None, hr_max_bpm=None, hr_rest_bpm=None,
                 hr_max_is_estimated=None)
        d.update(kw)
        return d
    run_kw = dict(data_from_us=t0, data_to_us=t0 + 600_000_000, measurement_count=550, sources='["heart_rate"]',
                  hr_max_bpm=190, hr_rest_bpm=55)
    gone = dict(unit="x", data_from_us=None, data_to_us=None, measurement_count=0, sources="[]",
                method="neue_methode", method_version=9, parameter_version=9, quality="undeterminable",
                unavailable_reason="neuer_code")
    r["computed_values"] = [
        cv(1, 1, None, "trimp_run", "original", 87.5, hr_max_is_estimated=0, **run_kw),
        cv(2, 1, None, "trimp_run", "current", 88.0, parameter_version=2, hr_max_is_estimated=1, **run_kw),
        cv(3, 1, None, "zukunft_kennzahl_äö", "original", None, **gone),
        cv(4, 1, None, "zukunft_kennzahl_äö", "current", None, **gone),
        cv(5, None, "2026-11-07", "trimp_day", "original", 9007199254740993.0 / 2),
        cv(6, None, "2026-11-07", "trimp_day", "current", 4503599627370497.5),
    ]
    vs = lambda i, cvid, est: dict(
        id=i, computed_value_id=cvid, position=0, start_us=t0, end_us=t0 + 600_000_000, gps_median_accuracy_m=4.5,
        weight=1.0, late_factor=1, status="eligible", discard=None, reasons='["a","b"]', oxygen_demand=None, estimate=est)
    r["value_sections"] = [vs(1, 1, 87.5), vs(2, 2, 88.0)]
    r["profile"] = [dict(id=1, birth_year=1985, body_weight_kg=72.5, body_height_m=1.78, resting_heart_rate_bpm=55,
                         max_heart_rate_bpm=None, weekly_run_minutes=120, training_days_mask=21, usual_training_minutes=45)]
    r["settings"] = [dict(key="a.unknown.key", value="Wert „Umlaut“ \U0001F3C3 \"q\" \\ \n", updated_at_us=9007199254740993),
                     dict(key="units", value="metric", updated_at_us=t0)]
    r["known_devices"] = [dict(id=1, device_id="AA:BB:CC:DD:EE:FF", display_name=None, is_preferred=1, added_at_us=t0)]
    return r


def archive_plaintext():
    r = archive_rows()
    lines = [{"type": "manifest", "format": 1, "schema_version": 4, "created_at_us": 1793000000000000}]
    for s in SECTIONS:
        lines.append({"type": "section", "name": s})
        lines += [{"type": "row", "data": d} for d in r[s]]
    lines.append({"type": "end", "rows": {s: len(r[s]) for s in SECTIONS}})
    jl = b"".join(json.dumps(l, separators=(",", ":"), ensure_ascii=False,
                             allow_nan=False).encode("utf-8") + b"\n" for l in lines)
    return jl, gzip.compress(jl, compresslevel=9, mtime=0)


def selftest():
    """Prueft die Bibliothek gegen oeffentliche Referenzvektoren (RFC 9106 4.4, RFC 8439 2.8.2)."""
    tag = Argon2id(salt=b"\x02" * 16, length=32, iterations=3, lanes=4, memory_cost=32,
                   ad=b"\x04" * 12, secret=b"\x03" * 8).derive(b"\x01" * 32)
    assert tag.hex() == "0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659", tag.hex()
    key = bytes(range(0x80, 0xA0))
    n = bytes.fromhex("070000004041424344454647")
    aad = bytes.fromhex("50515253c0c1c2c3c4c5c6c7")
    pt = (b"Ladies and Gentlemen of the class of '99: If I could offer you only one tip "
          b"for the future, sunscreen would be it.")
    ct = ChaCha20Poly1305(key).encrypt(n, pt, aad)
    assert ct[-16:].hex() == "1ae10b594f09e26a7e902ecbd0600691", ct[-16:].hex()


def main():
    selftest()
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    out = ap.parse_args().out
    os.makedirs(out, exist_ok=True)

    jl, gz = archive_plaintext()
    # (name, passwort, salz, klartext)
    pw_uni = "Pässwörd-ünïcode-€-123"
    pw_nfd = unicodedata.normalize("NFD", "Äé-nicht-normalisiert-ok")
    cases = [
        ("empty", "correct horse battery staple", bytes(range(16)), b""),
        ("short", pw_uni, bytes(range(16, 32)), b"Hallo Archiv"),
        ("exact_65536", "synthetisches-Passwort-0003", bytes([0xA5] * 16), stream("v3", 65536)),
        ("exact_65537", pw_nfd, bytes([0x5A] * 16), stream("v4", 65537)),
        ("multi_150k", "synthetisches-Passwort-0005", bytes(range(100, 116)), stream("v5", 150 * 1024)),
        ("exact_131072", "", bytes([0xFF] * 16), stream("v6", 131072)),
        ("archive_small", "archiv-test-passwort-15+", bytes(range(200, 216)), gz),
    ]
    manifest = []
    for name, pw, salt, pt in cases:
        key = derive(pw.encode("utf-8"), salt)
        h, cts = encrypt(pt, salt, key)
        fname = f"{name}.runarchv"
        open(os.path.join(out, fname), "wb").write(h + b"".join(cts))
        open(os.path.join(out, f"{name}.plain"), "wb").write(pt)
        manifest.append(dict(
            name=name, file=fname, plaintext_file=f"{name}.plain",
            password=pw, password_utf8_hex=pw.encode("utf-8").hex(),
            salt_hex=salt.hex(), key_hex=key.hex(), header_hex=h.hex(),
            plaintext_len=len(pt), plaintext_sha256=hashlib.sha256(pt).hexdigest(),
            chunk_count=len(cts), file_len=len(h) + sum(map(len, cts)),
            expect="ok"))
        if name == "archive_small":
            open(os.path.join(out, "archive_small.jsonl"), "wb").write(jl)
            manifest[-1]["jsonl_file"] = "archive_small.jsonl"
            manifest[-1]["jsonl_sha256"] = hashlib.sha256(jl).hexdigest()
            manifest[-1]["row_counts"] = {s: len(archive_rows()[s]) for s in SECTIONS}

    # Negativvektoren, abgeleitet aus multi_150k (3 Stuecke) und exact_65536.
    def raw(n): return open(os.path.join(out, f"{n}.runarchv"), "rb").read()
    m150, m64 = raw("multi_150k"), raw("exact_65536")
    full = 36 + 65552
    neg = [
        ("neg_truncate_at_boundary", m150[:full + 65552], "corrupt", "multi_150k", "Abschneiden an der zweiten Stueckgrenze (Stueck 1 mit Flag 0 gelesen als letztes)"),
        ("neg_truncate_after_first_chunk", m150[:full], "wrong_password_or_start_damaged", "multi_150k", "Abschneiden nach dem ersten Stueck: das erste Stueck scheitert (Fehlertabelle Zeile 1; Zeile 2 sagt scheinbar damaged)"),
        ("neg_append_byte", m150 + b"\x00", "corrupt", "multi_150k", "Byte angehaengt"),
        ("neg_swap_chunks", m150[:36] + m150[full:full + 65552] + m150[36:full] + m150[full + 65552:], "wrong_password_or_start_damaged", "multi_150k", "Stueck 0 und 1 vertauscht (Stueck 0 scheitert)"),
        ("neg_flip_late_byte", m150[:-1] + bytes([m150[-1] ^ 1]), "corrupt", "multi_150k", "Bit im letzten Stueck"),
        ("neg_flip_first_byte", m150[:40] + bytes([m150[40] ^ 1]) + m150[41:], "wrong_password_or_start_damaged", "multi_150k", "Bit im ersten Stueck"),
        ("neg_header_only", m150[:36], "wrong_password_or_start_damaged", "multi_150k", "Datei endet nach Kopf"),
        ("neg_extra_empty_last", None, "corrupt", "exact_65536", "volles Stueck als nicht-letztes + leeres letztes Stueck (Zaehler>0)"),
        ("neg_full_chunk_flagged_not_last", None, "wrong_password_or_start_damaged", "exact_65536", "einziges volles Stueck mit Flag 0 geschrieben: erstes Stueck scheitert"),
        ("neg_version_2", m64[:8] + b"\x00\x02" + m64[10:], "unknown_version", "exact_65536", "Formatversion 2"),
        ("neg_memory_1024", m64[:10] + struct.pack(">I", 1024) + m64[14:], "unsupported_parameters", "exact_65536", "Speicher 1024 KiB (kein Schluessel abgeleitet)"),
        ("neg_bad_magic", b"RUNARCHX" + m64[8:], "not_an_archive", "exact_65536", "Magic falsch"),
        ("neg_short_header", m64[:20], "corrupt", "exact_65536", "20 Byte (Magic+Version ok)"),
    ]
    c = {n: (pw, salt, pt) for n, pw, salt, pt in cases}
    pw, salt, pt = c["exact_65536"]
    key = derive(pw.encode(), salt)
    h = header(salt); aead = ChaCha20Poly1305(key)
    ct0 = aead.encrypt(nonce(0, False), pt, h)
    ct1 = aead.encrypt(nonce(1, True), b"", h)
    ctx = aead.encrypt(nonce(0, False), pt, h)  # Flag 0 am einzigen Stueck
    for n, data, err, base, note in neg:
        if n == "neg_extra_empty_last": data = h + ct0 + ct1
        if n == "neg_full_chunk_flagged_not_last": data = h + ctx
        open(os.path.join(out, f"{n}.runarchv"), "wb").write(data)
        b = next(x for x in manifest if x["name"] == base)
        manifest.append(dict(name=n, file=f"{n}.runarchv", password=b["password"],
                             salt_hex=b["salt_hex"], key_hex=b["key_hex"], expect=err, note=note,
                             file_len=len(data)))
    json.dump(dict(contract="docs/contracts/archive.md", generator="tool/archive_vectors/make_vectors.py",
                   vectors=manifest), open(os.path.join(out, "vectors.json"), "w"), indent=2, ensure_ascii=False)
    open(os.path.join(out, "vectors.json"), "a").write("\n")


if __name__ == "__main__":
    main()
