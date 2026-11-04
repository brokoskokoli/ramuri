#!/usr/bin/env python3
"""Pflegt und prüft die Spezifikationsdokumente. Nur Standardbibliothek.

  python3 docs/migration/tools/spec_tool.py build   # generierte Abschnitte aktualisieren
  python3 docs/migration/tools/spec_tool.py check   # Konsistenz prüfen (Exit 1 bei Fehlern)

Generiert werden: Register (requirements.md), Traceability Teil A, Frontmatter
`related_requirements` und "Offene Fragen" der Specs, "Betroffene Anforderungen"
in open-questions.md und die Kennzahlen im Migrationsbericht.
Die Prüfung ersetzt keine semantische Durchsicht.
"""
import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DOCS = ROOT / "docs"
MIG = DOCS / "migration"
SRC_FILE = MIG / "sources" / "Adaptive_Running_App_Funktionales_Konzept-1.md"
REQ_RE = re.compile(r"^### ((?:FR|NFR|CON|SEC)-\d{4}) — (.+)$", re.M)
OQ_RE = re.compile(r"^### (OQ-\d{4}) — (.+)$", re.M)
ANY_ID = re.compile(r"\b(FR-\d{4}|NFR-\d{4}|CON-\d{4}|SEC-\d{4}|DEC-\d{4}|OQ-\d{4}|ACC-\d{2}|FEAT-\d{3}|SRC-\d{3})\b")
CATEGORY = {"FR": "functional", "NFR": "non-functional", "SEC": "non-functional", "CON": "constraint"}
ALLOWED_STATUS = {"Draft", "Blocked", "Approved", "Deprecated"}


def md_files():
    """Alle gepflegten Markdown-Dateien; die Quellkopien gehören nicht dazu."""
    files = [p for p in DOCS.rglob("*.md") if "sources" not in p.parts]
    return sorted(files + [p for p in (ROOT / "README.md", ROOT / "AGENTS.md") if p.exists()])


def slug(heading):
    text = re.sub(r"[^\w\- ]", "", heading.strip().lower(), flags=re.UNICODE)
    return text.replace(" ", "-")


def parse_lines(text):
    """Liest Zeilenangaben wie 'Z. 12, 14–16' als Menge von Zeilennummern."""
    lines = set()
    for match in re.finditer(r"Z\. ([\d–, ]+)", text):
        for part in match.group(1).split(","):
            part = part.strip()
            if not part:
                continue
            start, _, end = part.partition("–")
            lines.update(range(int(start), int(end or start) + 1))
    return lines


def requirements():
    reqs = []
    for path in md_files():
        if MIG in path.parents or path.name == "requirements.md":
            continue
        text = path.read_text(encoding="utf-8")
        matches = list(REQ_RE.finditer(text))
        for i, match in enumerate(matches):
            tail = text[match.end():]
            next_heading = re.search(r"^#{1,3} ", tail, re.M)
            block = tail[: next_heading.start()] if next_heading else tail
            field = lambda name: (re.search(rf"\*\*{name}:\*\* ([^|\n]+)", block) or [None, ""])[1].strip()
            rid = match.group(1)
            reqs.append({
                "id": rid, "title": match.group(2).strip(), "path": path,
                "status": field("Status"), "phase": field("Phase"),
                "source": field("Quelle"), "related": field("Verwandt"),
                "ac": len(re.findall(r"^- \[ \]", block, re.M)),
                "category": CATEGORY[rid.split("-")[0]],
                "body": block,
            })
    return sorted(reqs, key=lambda r: (["FR", "NFR", "SEC", "CON"].index(r["id"].split("-")[0]), r["id"]))


def open_questions():
    text = (MIG / "open-questions.md").read_text(encoding="utf-8")
    result = {}
    for match in OQ_RE.finditer(text):
        tail = text[match.end():]
        end = re.search(r"^#{1,3} ", tail, re.M)
        block = tail[: end.start()] if end else tail
        impact = re.search(r"\*\*Auswirkung:\*\* (\S+)", block)
        result[match.group(1)] = {"title": match.group(2).strip(),
                                  "heading": match.group(0)[4:],
                                  "impact": impact.group(1).strip("—:,") if impact else "",
                                  "block": block,
                                  "open": "**Status:** Open" in block}
    return result


def replace_marked(text, name, content):
    begin, end = f"<!-- BEGIN {name} -->", f"<!-- END {name} -->"
    pattern = re.compile(re.escape(begin) + ".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise SystemExit(f"Marker {name} fehlt")
    return pattern.sub(lambda _: f"{begin}\n{content}\n{end}", text)


def rel(path, start):
    import os
    return os.path.relpath(path, start.parent)


def trace_rows(text):
    """Alle Zeilen aus Teil B der Traceability als (Quelle, Fundstelle)."""
    return re.findall(r"^\| SRC-001 \| ([^|]+) \|", text, re.M)


def stats(reqs, oqs):
    trace = (MIG / "traceability.md").read_text(encoding="utf-8")
    manual = trace.split("<!-- END TRACE -->")[-1]
    a_rows = sum(len([s for s in r["source"].split(";") if s.strip()]) for r in reqs)
    b_rows = trace_rows(manual)
    excluded = len(re.findall(r"\| Nicht übernommen \|", manual))
    dup = len(re.findall(r"\| Duplikat \|", manual))
    count = lambda prefix: sum(r["id"].startswith(prefix) for r in reqs)
    specs = list((DOCS / "specs").glob("*.md"))
    open_oqs = [o for o in oqs.values() if o["open"]]
    blocking = sum(o["impact"] == "blocking" for o in open_oqs)
    return {
        "Quellen im Inventar": len(re.findall(r"^\| SRC-\d{3} \|", (MIG / "source-inventory.md").read_text(encoding="utf-8"), re.M)),
        "Feature-Spezifikationen": len(specs),
        "Anforderungen gesamt": len(reqs),
        "davon FR / NFR / SEC / CON": f"{count('FR')} / {count('NFR')} / {count('SEC')} / {count('CON')}",
        "davon Status Blocked": sum(r["status"] == "Blocked" for r in reqs),
        "Akzeptanzkriterien in Anforderungen": sum(r["ac"] for r in reqs),
        "Fragen gesamt (offen blocking / offen non-blocking / entschieden)": f"{len(oqs)} ({blocking} / {len(open_oqs) - blocking} / {len(oqs) - len(open_oqs)})",
        "Traceability-Zeilen (Teil A / Teil B)": f"{a_rows + len(b_rows)} ({a_rows} / {len(b_rows)})",
        "davon Duplikat zusammengefasst": dup,
        "davon begründet nicht übernommen": excluded,
    }


def build():
    reqs, oqs = requirements(), open_questions()
    reg_path = DOCS / "requirements.md"
    rows = ["| ID | Titel | Kategorie | Status | Phase | Detail | Verwandt |", "|---|---|---|---|---|---|---|"]
    for r in reqs:
        anchor = slug(f"{r['id']} — {r['title']}")
        link = f"[{r['path'].stem}]({rel(r['path'], reg_path)}#{anchor})"
        rows.append(f"| {r['id']} | {r['title']} | {r['category']} | {r['status']} | {r['phase']} | {link} | {r['related'] or '—'} |")
    text = reg_path.read_text(encoding="utf-8")
    reg_path.write_text(replace_marked(text, "REGISTER", "\n".join(rows)), encoding="utf-8")

    trace_path = MIG / "traceability.md"
    rows = ["| Quelle | Fundstelle | Aussage / Kurzfassung | Ergebnis | Dokument | Akzeptanzkriterium | Status |", "|---|---|---|---|---|---|---|"]
    for r in reqs:
        for seg in [s.strip() for s in r["source"].split(";") if s.strip()]:
            src = seg[:7] if seg.startswith("SRC-") else "SRC-001"
            loc = seg[8:] if seg.startswith("SRC-") else seg
            acc = sorted(set(re.findall(r"ACC-\d{2}", r["related"])))
            ac = f"{r['ac']} AK" + (", " + ", ".join(acc) if acc else "") if r["ac"] or acc else "TBD"
            doc = rel(r["path"], trace_path)
            state = "Ungeklärt" if r["status"] == "Blocked" else "Übernommen"
            rows.append(f"| {src} | {loc} | {r['title']} | {r['id']} | [{r['path'].name}]({doc}) | {ac} | {state} |")
    text = trace_path.read_text(encoding="utf-8")
    trace_path.write_text(replace_marked(text, "TRACE", "\n".join(rows)), encoding="utf-8")

    for path in (DOCS / "specs").glob("*.md"):
        text = path.read_text(encoding="utf-8")
        own = [r for r in reqs if r["path"] == path]
        text = re.sub(r"^related_requirements: .*$", "related_requirements: [" + ", ".join(r["id"] for r in own) + "]", text, count=1, flags=re.M)
        approved = sum(r["status"] == "Approved" for r in own)
        status = "Approved" if own and approved == len(own) else "Teilweise Approved" if approved else "Draft"
        text = re.sub(r"^status: .*$", f"status: {status}", text, count=1, flags=re.M)
        ids = sorted({o for r in own for o in re.findall(r"OQ-\d{4}", r["related"])})
        lines = [f"- [{o}]({rel(MIG / 'open-questions.md', path)}#{slug(oqs[o]['heading'])}) ({oqs[o]['impact'] if oqs[o]['open'] else 'entschieden'}): {oqs[o]['title']}" for o in ids] or ["- Keine."]
        path.write_text(replace_marked(text, "OQ", "\n".join(lines)), encoding="utf-8")

    oq_path = MIG / "open-questions.md"
    text = oq_path.read_text(encoding="utf-8")
    for oq in oqs:
        users = [r["id"] for r in reqs if oq in r["related"]]
        block_re = re.compile(rf"(### {oq} — .*?- \*\*Betroffene Anforderungen:\*\*)[^\n]*", re.S)
        text = block_re.sub(lambda m: m.group(1) + " " + (", ".join(users) or "keine direkt"), text, count=1)
    oq_path.write_text(text, encoding="utf-8")

    report = MIG / "migration-report.md"
    if report.exists():
        table = ["| Kennzahl | Wert |", "|---|---|"] + [f"| {k} | {v} |" for k, v in stats(reqs, open_questions()).items()]
        report.write_text(replace_marked(report.read_text(encoding="utf-8"), "STATS", "\n".join(table)), encoding="utf-8")
    print(f"build: {len(reqs)} Anforderungen, {len(oqs)} offene Fragen")


def check():
    errors, reqs, oqs = [], requirements(), open_questions()
    files = md_files()
    defined = {}

    def define(identifier, where):
        if identifier in defined:
            errors.append(f"Doppelte ID {identifier}: {defined[identifier]} und {where}")
        defined[identifier] = where

    for r in reqs:
        define(r["id"], r["path"].name)
        if r["status"] not in ALLOWED_STATUS:
            errors.append(f"{r['id']}: Status '{r['status']}' nicht erlaubt")
        if not r["phase"]:
            errors.append(f"{r['id']}: Phase fehlt")
        if not parse_lines(r["source"]) and "SRC-003" not in r["source"]:
            errors.append(f"{r['id']}: Quelle ohne Zeilenangabe")
        if r["status"] == "Blocked" and not any(oqs.get(o, {}).get("open") for o in re.findall(r"OQ-\d{4}", r["related"])):
            errors.append(f"{r['id']}: Blocked ohne offene Frage")
        if "TBD" in r["phase"] and "OQ-0041" not in r["related"]:
            errors.append(f"{r['id']}: Phase TBD ohne OQ-0041")
    for oq, data in oqs.items():
        define(oq, "open-questions.md")
        if data["impact"] not in {"blocking", "non-blocking"}:
            errors.append(f"{oq}: Auswirkung fehlt oder ungültig")
        for key in ("Frage", "Auslöser/Quellen", "Status"):
            if f"**{key}:**" not in data["block"]:
                errors.append(f"{oq}: Feld {key} fehlt")
        if not any(oq in r["related"] for r in reqs):
            errors.append(f"{oq}: von keiner Anforderung referenziert")
    for path in (DOCS / "specs").glob("*.md"):
        match = re.search(r"^id: (FEAT-\d{3})$", path.read_text(encoding="utf-8"), re.M)
        if not match:
            errors.append(f"{path.name}: FEAT-ID fehlt")
        else:
            define(match.group(1), path.name)
    for name, pattern, path in (("DEC", r"^\| (DEC-\d{4}) \|", DOCS / "product.md"),
                                ("ACC", r"^\| (ACC-\d{2}) \|", DOCS / "quality" / "testing.md"),
                                ("SRC", r"^\| (SRC-\d{3}) \|", MIG / "source-inventory.md")):
        for identifier in re.findall(pattern, path.read_text(encoding="utf-8"), re.M):
            define(identifier, path.name)

    headings = {}
    for path in files:
        headings[path.resolve()] = {slug(h) for h in re.findall(r"^#{1,6} (.+)$", path.read_text(encoding="utf-8"), re.M)}
    links = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        for identifier in set(ANY_ID.findall(text)):
            if identifier not in defined:
                errors.append(f"{path.relative_to(ROOT)}: unbekannte Referenz {identifier}")
        for target in re.findall(r"\]\(([^)\s]+)\)", re.sub(r"```.*?```", "", text, flags=re.S)):
            if re.match(r"https?:", target):
                continue
            links += 1
            file_part, _, anchor = target.partition("#")
            resolved = (path.parent / file_part).resolve() if file_part else path.resolve()
            if not resolved.exists():
                errors.append(f"{path.relative_to(ROOT)}: Link-Ziel fehlt: {target}")
            elif anchor and resolved in headings and anchor not in headings[resolved]:
                errors.append(f"{path.relative_to(ROOT)}: Anker fehlt: {target}")

    source_lines = SRC_FILE.read_text(encoding="utf-8").splitlines()
    covered = set()
    for r in reqs:
        covered |= parse_lines(r["source"])
    trace = (MIG / "traceability.md").read_text(encoding="utf-8")
    for loc in trace_rows(trace.split("<!-- END TRACE -->")[-1]):
        covered |= parse_lines(loc)
    if covered and max(covered) > len(source_lines):
        errors.append(f"Zeilenangabe {max(covered)} jenseits des Quellendes ({len(source_lines)})")
    ignorable = re.compile(r"^(\s*|---|#.*|\$\$)$")
    gaps = [i for i, line in enumerate(source_lines, 1) if i not in covered and not ignorable.match(line)]
    for i in gaps:
        errors.append(f"Quellzeile ohne Zuordnung: Z. {i}: {source_lines[i - 1][:70]}")

    inventory = (MIG / "source-inventory.md").read_text(encoding="utf-8")
    for path in (MIG / "sources").glob("*"):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if digest not in inventory:
            errors.append(f"Prüfsumme von {path.name} passt nicht zum Inventar")

    for message in errors:
        print("FEHLER", message)
    print(f"Geprüft: {len(files)} Dateien, {links} interne Links, {len(defined)} IDs, "
          f"{len(reqs)} Anforderungen, {len(oqs)} offene Fragen, "
          f"Quellzeilen ohne Zuordnung: {len(gaps)}")
    print("Ergebnis:", "FAIL" if errors else "PASS")
    return 1 if errors else 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in {"build", "check"}:
        raise SystemExit(__doc__)
    if sys.argv[1] == "build":
        build()
    else:
        sys.exit(check())
