#!/usr/bin/env python3
"""Pflegt und prüft die Spezifikation unter docs/. Nur Standardbibliothek.

  python3 tool/spec_tool.py build   # generierte Abschnitte aktualisieren
  python3 tool/spec_tool.py check   # Konsistenz prüfen (Exit 1 bei Fehlern)

Generiert werden: das Register (docs/requirements.md) und in jeder Spec der Frontmatter (`related_requirements`,
`status`) und der Abschnitt "Offene Fragen" (Marker OQ: die IDs aus "Verwandt" ihrer Anforderungen).

Geprüft werden: IDs eindeutig, Kopf jeder Anforderung (Status, Phase, Quelle), Blocked nur mit einer verwandten
offenen Frage, Phase TBD nur mit OQ-0041, jede Referenz auf eine ID dieser Spezifikation (FR, NFR, SEC, CON, DEC,
ACC, FEAT) definiert, interne Links und Anker, dazu die Architektur-Doku (architecture_errors): jede ADR-Datei in
docs/index.md verlinkt und mit ihrem Status genannt, Status und Datum jeder ADR in der Tabelle von docs/architecture/overview.md wie in der
ADR-Datei, jeder Pfad in Backticks in docs/architecture/code-map.md vorhanden und die Suchbegriffe ihrer Tabelle
"Große Dateien" in der genannten Datei enthalten.

Externe IDs: Die offenen Fragen und Entscheidungen des Maintainers (OQ-nnnn), das Quelleninventar (SRC-nnn) samt
Ursprungskonzept und die Traceability werden außerhalb dieses Repos gepflegt. Hier wird nur ihre Form geprüft; ob es
sie gibt, ob eine Frage offen ist und ob jede Zeile des Ursprungskonzepts zugeordnet ist, prüft die Pflege dort mit
demselben Parser (requirements(), slug(), parse_lines() dieser Datei).
Die Prüfung ersetzt keine semantische Durchsicht.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
REQ_RE = re.compile(r"^### ((?:FR|NFR|CON|SEC)-\d{4}) — (.+)$", re.M)
ANY_ID = re.compile(r"\b(FR-\d{4}|NFR-\d{4}|CON-\d{4}|SEC-\d{4}|DEC-\d{4}|ACC-\d{2}|FEAT-\d{3})\b")
EXTERNAL_ID = re.compile(r"\b(?:OQ-\d{4}|SRC-\d{3})\b")
CATEGORY = {"FR": "functional", "NFR": "non-functional", "SEC": "non-functional", "CON": "constraint"}
ALLOWED_STATUS = {"Draft", "Blocked", "Approved", "Deprecated"}


def md_files(root=ROOT):
    """Alle gepflegten Markdown-Dateien der Spezifikation."""
    docs = root / "docs"
    return sorted(list(docs.rglob("*.md")) + [p for p in (root / "README.md", root / "AGENTS.md") if p.exists()])


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


def requirements(root=ROOT):
    reqs = []
    for path in md_files(root):
        if path.name == "requirements.md":
            continue
        text = path.read_text(encoding="utf-8")
        matches = list(REQ_RE.finditer(text))
        for match in matches:
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


def replace_marked(text, name, content):
    begin, end = f"<!-- BEGIN {name} -->", f"<!-- END {name} -->"
    pattern = re.compile(re.escape(begin) + ".*?" + re.escape(end), re.S)
    if not pattern.search(text):
        raise SystemExit(f"Marker {name} fehlt")
    return pattern.sub(lambda _: f"{begin}\n{content}\n{end}", text)


def rel(path, start):
    import os
    return os.path.relpath(path, start.parent)


def build():
    reqs = requirements()
    reg_path = DOCS / "requirements.md"
    rows = ["| ID | Titel | Kategorie | Status | Phase | Detail | Verwandt |", "|---|---|---|---|---|---|---|"]
    for r in reqs:
        anchor = slug(f"{r['id']} — {r['title']}")
        link = f"[{r['path'].stem}]({rel(r['path'], reg_path)}#{anchor})"
        rows.append(f"| {r['id']} | {r['title']} | {r['category']} | {r['status']} | {r['phase']} | {link} | {r['related'] or '—'} |")
    text = reg_path.read_text(encoding="utf-8")
    reg_path.write_text(replace_marked(text, "REGISTER", "\n".join(rows)), encoding="utf-8")

    for path in (DOCS / "specs").glob("*.md"):
        text = path.read_text(encoding="utf-8")
        own = [r for r in reqs if r["path"] == path]
        text = re.sub(r"^related_requirements: .*$", "related_requirements: [" + ", ".join(r["id"] for r in own) + "]", text, count=1, flags=re.M)
        approved = sum(r["status"] == "Approved" for r in own)
        status = "Approved" if own and approved == len(own) else "Teilweise Approved" if approved else "Draft"
        text = re.sub(r"^status: .*$", f"status: {status}", text, count=1, flags=re.M)
        ids = sorted({o for r in own for o in re.findall(r"OQ-\d{4}", r["related"])})
        lines = [f"- {o}" for o in ids] or ["- Keine."]
        path.write_text(replace_marked(text, "OQ", "\n".join(lines)), encoding="utf-8")
    print(f"build: {len(reqs)} Anforderungen")


ADR_STATUS = re.compile(r"^- \*\*Status:\*\* (\w+)", re.M)
ADR_DATE = re.compile(r"^- \*\*Datum:\*\* (\d{4}-\d{2}-\d{2})", re.M)
ADR_STATES = {"Proposed", "Accepted", "Rejected", "Superseded", "Deprecated"}
REPO_PATH = re.compile(r"`((?:app|tool|docs|\.github)/[^`\s]*)`")


def architecture_errors(root=ROOT):
    """Prüft die Architektur-Doku gegen die ADR-Dateien und den Code. Liefert die Fehlermeldungen."""
    errors = []
    arch = root / "docs" / "architecture"
    adrs = sorted((arch / "adr").glob("ADR-*.md"))
    if not adrs:
        return [f"{arch.relative_to(root)}/adr: keine ADR-Datei gefunden"]
    index = (root / "docs" / "index.md").read_text(encoding="utf-8")
    overview = (arch / "overview.md").read_text(encoding="utf-8")
    rows = {}
    for line in overview.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        for cell in cells:
            for name in re.findall(r"\]\(adr/(ADR-\d{4}[^)]*\.md)\)", cell):
                rows.setdefault(name, []).append(cells)
    for adr in adrs:
        text = adr.read_text(encoding="utf-8")
        status, date = ADR_STATUS.search(text), ADR_DATE.search(text)
        if not status or not date:
            errors.append(f"{adr.relative_to(root)}: Status- oder Datumszeile fehlt")
            continue
        lines = [line for line in index.splitlines() if f"(architecture/adr/{adr.name})" in line]
        if not lines:
            errors.append(f"docs/index.md: {adr.name} nicht verlinkt")
        elif not any(re.search(rf"\b{status.group(1)}\b", line) for line in lines):
            errors.append(f"docs/index.md: {adr.name} ohne Status {status.group(1)} der ADR-Datei")
        elif any(re.search(rf"\b{s}\b", line) for line in lines for s in ADR_STATES - {status.group(1)}):
            errors.append(f"docs/index.md: {adr.name} mit abweichendem Status")
        found = rows.get(adr.name, [])
        if len(found) != 1:
            errors.append(f"docs/architecture/overview.md: {adr.name} steht {len(found)}-mal in der ADR-Tabelle, erwartet 1")
            continue
        cells = found[0]
        if status.group(1) not in cells:
            errors.append(f"docs/architecture/overview.md: {adr.name} ohne Status {status.group(1)} der ADR-Datei")
        if date.group(1) not in cells:
            errors.append(f"docs/architecture/overview.md: {adr.name} ohne Datum {date.group(1)} der ADR-Datei")
        others = {s for s in ADR_STATES if any(re.search(rf"\b{s}\b", c) for c in cells)} - {status.group(1)}
        if others:
            errors.append(f"docs/architecture/overview.md: {adr.name} mit abweichendem Status {', '.join(sorted(others))}")
    code_map = arch / "code-map.md"
    if not code_map.exists():
        return errors + ["docs/architecture/code-map.md fehlt"]
    text = code_map.read_text(encoding="utf-8")
    for path in sorted(set(REPO_PATH.findall(text))):
        real = path.split("<", 1)[0]
        if not (root / real).exists():
            errors.append(f"docs/architecture/code-map.md: Pfad fehlt: {path}")
    section = re.search(r"^## Große Dateien\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not section:
        errors.append("docs/architecture/code-map.md: Abschnitt 'Große Dateien' fehlt")
        return errors
    hotspots = 0
    for line in section.group(1).splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 3 or not REPO_PATH.fullmatch(cells[0]):
            continue
        hotspots += 1
        source = root / cells[0].strip("`")
        if not source.exists():
            continue  # schon oben als fehlender Pfad gemeldet
        content = source.read_text(encoding="utf-8")
        for symbol in re.findall(r"`([^`]+)`", cells[2]):
            if symbol not in content:
                errors.append(f"docs/architecture/code-map.md: Suchbegriff fehlt in {cells[0]}: {symbol}")
    if not hotspots:
        errors.append("docs/architecture/code-map.md: Tabelle 'Große Dateien' ohne Zeilen")
    return errors


def check():
    errors, reqs = [], requirements()
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
        if r["status"] == "Blocked" and not re.search(r"OQ-\d{4}", r["related"]):
            errors.append(f"{r['id']}: Blocked ohne verwandte offene Frage")
        if "TBD" in r["phase"] and "OQ-0041" not in r["related"]:
            errors.append(f"{r['id']}: Phase TBD ohne OQ-0041")
    for path in (DOCS / "specs").glob("*.md"):
        match = re.search(r"^id: (FEAT-\d{3})$", path.read_text(encoding="utf-8"), re.M)
        if not match:
            errors.append(f"{path.name}: FEAT-ID fehlt")
        else:
            define(match.group(1), path.name)
    for name, pattern, path in (("DEC", r"^\| (DEC-\d{4}) \|", DOCS / "product.md"),
                                ("ACC", r"^\| (ACC-\d{2}) \|", DOCS / "quality" / "testing.md")):
        for identifier in re.findall(pattern, path.read_text(encoding="utf-8"), re.M):
            define(identifier, path.name)

    headings = {}
    for path in files:
        headings[path.resolve()] = {slug(h) for h in re.findall(r"^#{1,6} (.+)$", path.read_text(encoding="utf-8"), re.M)}
    links = external = 0
    for path in files:
        text = path.read_text(encoding="utf-8")
        for identifier in set(ANY_ID.findall(text)):
            if identifier not in defined:
                errors.append(f"{path.relative_to(ROOT)}: unbekannte Referenz {identifier}")
        external += len(set(EXTERNAL_ID.findall(text)))
        for target in re.findall(r"\]\(([^)\s]+)\)", re.sub(r"```.*?```", "", text, flags=re.S)):
            if re.match(r"(https?|mailto):", target):
                continue
            links += 1
            file_part, _, anchor = target.partition("#")
            resolved = (path.parent / file_part).resolve() if file_part else path.resolve()
            if not resolved.exists():
                errors.append(f"{path.relative_to(ROOT)}: Link-Ziel fehlt: {target}")
            elif anchor and resolved in headings and anchor not in headings[resolved]:
                errors.append(f"{path.relative_to(ROOT)}: Anker fehlt: {target}")

    architecture = architecture_errors()
    errors += architecture

    for message in errors:
        print("FEHLER", message)
    print(f"Geprüft: {len(files)} Dateien, {links} interne Links, {len(defined)} IDs, "
          f"{len(reqs)} Anforderungen, externe Referenzen (OQ/SRC, nur Form): {external}")
    print("Ergebnis:", "FAIL" if errors else "PASS")
    return 1 if errors else 0


if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in {"build", "check"}:
        raise SystemExit(__doc__)
    if sys.argv[1] == "build":
        build()
    else:
        sys.exit(check())
