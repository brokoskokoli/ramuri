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


def header(salt: bytes, version: int = 1) -> bytes:
    h = MAGIC + struct.pack(">HIIBB", version, MEM, T, P, KLEN) + salt
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


def encrypt(pt: bytes, salt: bytes, key: bytes, version: int = 1):
    h = header(salt, version)
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


# Format 2 (Schema 5, WP18): Abschnitte 17 und 18 kommen nach known_devices (Vertrag 4.3).
SECTIONS_V2 = SECTIONS[:16] + ["run_feedback", "manual_trainings"] + SECTIONS[16:]

# Schema 6 (WP20, weiter Format 2): Abschnitte 22 und 23 ans Ende (Vertrag 4.3).
SECTIONS_S6 = SECTIONS_V2 + ["reference_performances", "rejected_suggestions"]

# Schema 7 (WP21, weiter Format 2): Abschnitte 19 `goals` und 20 `plans` tragen Zeilen, 21 bleibt
# leer; `plan_units` kommt als Nummer 24 ans Ende (Vertrag 4.3).
SECTIONS_S7 = SECTIONS_S6 + ["plan_units"]

# Schema 8 (WP22, weiter Format 2): gleiche Abschnitte, `plan_units` hat die Spalte `fixed` am Ende
# (Vertrag 4.3); Archive mit Schema 7 lesen sich mit fixed = "none".
SECTIONS_S8 = SECTIONS_S7

# "Heute" der Leser-Tests im Adapter-Paket (Ortstag, siehe archive_import_vectors_test.dart).
# manual_trainings darf nicht nach diesem Tag liegen (Vertrag 4.3).
V2_TODAY = "2026-11-20"


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


def archive_rows_v2(future_training=False):
    """Format 2: die Zeilen von Format 1 plus run_feedback und manual_trainings."""
    r = archive_rows()
    r["run_feedback"] = [
        # Lauf 1: alle Angaben, sRPE = 590 s / 60 * 6 = 59 (srpe_duration_rpe, Version 1)
        dict(run_id=1, rpe=6, wellbeing=4, complaints="Wade links \u00e4\u00f6", warning_answer="no",
             note="Notiz \u201eUmlaut\u201c", srpe_points=59.0, srpe_duration_s=590.0,
             srpe_method="srpe_duration_rpe", srpe_method_version=1),
        # Lauf 7: nur Beschwerden mit Warnsignal-Antwort, ohne RPE und ohne sRPE
        dict(run_id=7, rpe=None, wellbeing=None, complaints="Knie", warning_answer="yes", note=None,
             srpe_points=None, srpe_duration_s=None, srpe_method=None, srpe_method_version=None),
    ]
    r["manual_trainings"] = [
        dict(id=1, day="2026-11-01", kind="other", duration_s=3600, rpe=4),
        dict(id=2, day=V2_TODAY, kind="run", duration_s=1800, rpe=0),  # Grenzfall: heute, angenommen
    ]
    if future_training:  # Tag nach heute: der Leser lehnt das ganze Archiv ab
        r["manual_trainings"].append(dict(id=3, day="2026-11-21", kind="other", duration_s=600, rpe=3))
    return r


def archive_rows_s6():
    """Schema 6: die Zeilen von Format 2/Schema 5 plus Referenzleistungen und abgelehnte Vorschlaege."""
    r = archive_rows_v2()
    r["reference_performances"] = [
        dict(id=1, kind="race", distance_m=10000.0, time_s=3000.0, performed_on="2026-10-04",
             created_at_us=1791100000000000, run_id=None),
        dict(id=2, kind="test", distance_m=5000.0, time_s=1260.5, performed_on="2026-10-20",
             created_at_us=1792500000000000, run_id=None),
        # bestaetigter Lauf: verweist auf Lauf 1 des Archivs
        dict(id=3, kind="confirmedRun", distance_m=4200.0, time_s=1200.0, performed_on="2026-11-02",
             created_at_us=1793000000000000, run_id=1),
    ]
    r["rejected_suggestions"] = [dict(id=1, run_id=7)]
    return r


def archive_rows_s7():
    """Schema 7: die Zeilen von Schema 6 plus Trainingsziel (Singleton, id 1), Plan und Plan-Einheiten."""
    r = archive_rows_s6()
    # Zeitziel ueber 10 km; Lauftage Mo, Mi, Fr (Bitmaske 1+4+16 = 21, Bit 0 = Montag).
    r["goals"] = [dict(id=1, type="time", distance="tenKilometers", target_s=3000.0,
                       target_date="2027-03-20", run_days=21, max_session_s=3600.0,
                       weekly_cap_s=14400.0, current_weekly_s=7200.0, can_run_30="yes",
                       hard_session=1, created_at_us=1793000000000000)]
    # Eine Fassung des Plans (inputs, summary: JSON-Text) und zwei Einheiten: ein Geh-Lauf mit
    # Segmenten in Sekunden und Zuordnung zu Lauf 1, ein Ruhetag (pinned, ohne Lauf).
    r["plans"] = [dict(id=1, goal_id=1, created_at_us=1793000100000000, valid_from="2026-11-09",
                       trigger="create", reason="goalCreated", method="plan-rules", method_version=1,
                       parameter_version=1,
                       inputs=json.dumps(
                           {"inputsVersion": 1, "anchor": "2026-11-09", "startWeeklyMinutes": 120,
                            "walkRunWeeks": 0, "easyPaceSecondsPerKm": None, "easyRunCount": 0,
                            "lastWeekMinutes": None, "achievedShare": None, "walkRunStart": None,
                            "walkRunFrom": None, "intensity": None, "today": "2026-11-09"},
                           separators=(",", ":")),
                       summary=json.dumps({"weeks": 12, "estimated": True},
                                          separators=(",", ":")))]
    walk_run = [
        {"kind": "walk", "minutes": 5, "seconds": 300},
        {"kind": "run", "minutes": 2, "seconds": 90,
         "intensity": {"rpeMin": 3, "rpeMax": 4, "paceFast": 360.0, "paceSlow": 420.0,
                       "basis": "estimate", "hrMin": None, "hrMax": None, "estimated": True,
                       "maxHrEstimated": False, "paceIsLimit": False}},
    ]
    r["plan_units"] = [
        dict(id=1, plan_id=1, day="2026-11-09", week=0, phase="entry", kind="walkRun", minutes=30,
             structure=json.dumps(walk_run, separators=(",", ":")), run_id=1, pinned=0),
        dict(id=2, plan_id=1, day="2026-11-10", week=0, phase="entry", kind="rest", minutes=0,
             structure="[]", run_id=None, pinned=1),
    ]
    return r


def archive_rows_s8():
    """Schema 8: die Zeilen von Schema 7, Plan-Einheiten mit `fixed`; dazu eine ersetzte Einheit
    (Art vom Nutzer, fixed = "kind", pinned) neben dem Ruhetag (fixed = "day") und eine harte
    Einheit, die der Nutzer durch einen lockeren Lauf ersetzt hat (fixed = "easyForHard", nur mit
    kind = "easy" und pinned)."""
    r = archive_rows_s7()
    units = [dict(u, fixed="day" if u["kind"] == "rest" else "none") for u in r["plan_units"]]
    tempo = [{"kind": "warmUp", "minutes": 10}, {"kind": "tempo", "minutes": 15},
             {"kind": "coolDown", "minutes": 5}]
    units.append(dict(id=3, plan_id=1, day="2026-11-11", week=0, phase="entry", kind="tempo",
                      minutes=30, structure=json.dumps(tempo, separators=(",", ":")), run_id=None,
                      pinned=1, fixed="kind"))
    easy = [{"kind": "easy", "minutes": 30}]
    units.append(dict(id=4, plan_id=1, day="2026-11-12", week=0, phase="entry", kind="easy",
                      minutes=30, structure=json.dumps(easy, separators=(",", ":")), run_id=None,
                      pinned=1, fixed="easyForHard"))
    r["plan_units"] = units
    return r


def archive_plaintext(version=1, future_training=False, schema=None):
    if schema == 8:
        r, sections = archive_rows_s8(), SECTIONS_S8
    elif schema == 7:
        r, sections = archive_rows_s7(), SECTIONS_S7
    elif schema == 6:
        r, sections = archive_rows_s6(), SECTIONS_S6
    else:
        r = archive_rows_v2(future_training) if version == 2 else archive_rows()
        sections = SECTIONS_V2 if version == 2 else SECTIONS
    schema = schema or (5 if version == 2 else 4)
    lines = [{"type": "manifest", "format": version, "schema_version": schema, "created_at_us": 1793000000000000}]
    for s in sections:
        lines.append({"type": "section", "name": s})
        lines += [{"type": "row", "data": d} for d in r[s]]
    lines.append({"type": "end", "rows": {s: len(r[s]) for s in sections}})
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
    jl2, gz2 = archive_plaintext(2)
    jl6, gz6 = archive_plaintext(2, schema=6)
    jl7, gz7 = archive_plaintext(2, schema=7)
    jl8, gz8 = archive_plaintext(2, schema=8)
    _, gz2_future = archive_plaintext(2, future_training=True)
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
        ("archive_v2", "archiv-test-passwort-v2+", bytes(range(216, 232)), gz2),
        ("archive_v2_s6", "archiv-test-passwort-s6+", bytes(range(232, 248)), gz6),
        ("archive_v2_s7", "archiv-test-passwort-s7+", bytes(range(248, 256)) + bytes(range(8)), gz7),
        ("archive_v2_s8", "archiv-test-passwort-s8+", bytes(range(8, 24)), gz8),
    ]
    # Format 2 mit einem Training nach heute (V2_TODAY): Negativvektor "corrupt", Quelle von neg_v2_*.
    v2_future = ("v2_future_training_src", "archiv-test-passwort-v2+", bytes(range(216, 232)), gz2_future)
    manifest = []
    for name, pw, salt, pt in cases:
        key = derive(pw.encode("utf-8"), salt)
        ver = 2 if name in ("archive_v2", "archive_v2_s6", "archive_v2_s7", "archive_v2_s8") else 1
        h, cts = encrypt(pt, salt, key, ver)
        fname = f"{name}.runarchv"
        open(os.path.join(out, fname), "wb").write(h + b"".join(cts))
        open(os.path.join(out, f"{name}.plain"), "wb").write(pt)
        manifest.append(dict(
            name=name, file=fname, plaintext_file=f"{name}.plain",
            password=pw, password_utf8_hex=pw.encode("utf-8").hex(),
            salt_hex=salt.hex(), key_hex=key.hex(), header_hex=h.hex(),
            plaintext_len=len(pt), plaintext_sha256=hashlib.sha256(pt).hexdigest(),
            chunk_count=len(cts), file_len=len(h) + sum(map(len, cts)),
            expect="ok", format=ver))
        if name == "archive_v2":
            open(os.path.join(out, "archive_v2.jsonl"), "wb").write(jl2)
            manifest[-1]["jsonl_file"] = "archive_v2.jsonl"
            manifest[-1]["jsonl_sha256"] = hashlib.sha256(jl2).hexdigest()
            manifest[-1]["row_counts"] = {s: len(archive_rows_v2()[s]) for s in SECTIONS_V2}
            manifest[-1]["today"] = V2_TODAY
        if name == "archive_v2_s6":
            open(os.path.join(out, "archive_v2_s6.jsonl"), "wb").write(jl6)
            manifest[-1]["jsonl_file"] = "archive_v2_s6.jsonl"
            manifest[-1]["jsonl_sha256"] = hashlib.sha256(jl6).hexdigest()
            manifest[-1]["row_counts"] = {s: len(archive_rows_s6()[s]) for s in SECTIONS_S6}
            manifest[-1]["today"] = V2_TODAY
        if name == "archive_v2_s7":
            open(os.path.join(out, "archive_v2_s7.jsonl"), "wb").write(jl7)
            manifest[-1]["jsonl_file"] = "archive_v2_s7.jsonl"
            manifest[-1]["jsonl_sha256"] = hashlib.sha256(jl7).hexdigest()
            manifest[-1]["row_counts"] = {s: len(archive_rows_s7()[s]) for s in SECTIONS_S7}
            manifest[-1]["today"] = V2_TODAY
        if name == "archive_v2_s8":
            open(os.path.join(out, "archive_v2_s8.jsonl"), "wb").write(jl8)
            manifest[-1]["jsonl_file"] = "archive_v2_s8.jsonl"
            manifest[-1]["jsonl_sha256"] = hashlib.sha256(jl8).hexdigest()
            manifest[-1]["row_counts"] = {s: len(archive_rows_s8()[s]) for s in SECTIONS_S8}
            manifest[-1]["today"] = V2_TODAY
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
        ("neg_version_3", m64[:8] + b"\x00\x03" + m64[10:], "unknown_version", "exact_65536", "Formatversion 3"),
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
    # Format 2, Training am Tag nach V2_TODAY: sonst gueltig, vollstaendig verschluesselt.
    _, fsalt, fpt = v2_future[1:]
    fkey = derive(v2_future[1].encode(), fsalt)
    fh, fcts = encrypt(fpt, fsalt, fkey, 2)
    neg.append(("neg_v2_training_after_today", fh + b"".join(fcts), "corrupt", "archive_v2",
                f"Format 2, manual_trainings mit Tag nach heute ({V2_TODAY}): Archiv abgelehnt"))
    for n, data, err, base, note in neg:
        if n == "neg_extra_empty_last": data = h + ct0 + ct1
        if n == "neg_full_chunk_flagged_not_last": data = h + ctx
        open(os.path.join(out, f"{n}.runarchv"), "wb").write(data)
        b = next(x for x in manifest if x["name"] == base)
        manifest.append(dict(name=n, file=f"{n}.runarchv", password=b["password"],
                             salt_hex=b["salt_hex"], key_hex=b["key_hex"], expect=err, note=note,
                             file_len=len(data)))
        if n == "neg_v2_training_after_today":  # Rahmen und Kryptografie gueltig, Inhalt abgelehnt
            manifest[-1].update(layer="content", today=V2_TODAY)
    json.dump(dict(contract="docs/contracts/archive.md", generator="tool/archive_vectors/make_vectors.py",
                   vectors=manifest), open(os.path.join(out, "vectors.json"), "w"), indent=2, ensure_ascii=False)
    open(os.path.join(out, "vectors.json"), "a").write("\n")


if __name__ == "__main__":
    main()
