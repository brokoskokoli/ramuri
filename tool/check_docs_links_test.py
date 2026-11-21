#!/usr/bin/env python3
"""Selbsttest für die Prüfung der Architektur-Doku in tool/spec_tool.py (architecture_errors).

Baut einen kleinen Baum mit zwei ADRs, Index, Überblick und Code-Landkarte (grün), führt jede Abweichung einzeln
darauf aus (jeweils rot, mit erwarteter Meldung) und prüft zuletzt den echten Baum (grün). Wird eine Regel in
architecture_errors entfernt oder aufgeweicht, wird der zugehörige Fall grün und dieser Test rot.
Aufruf: python3 tool/check_docs_links_test.py"""
import contextlib
import importlib.util
import io
import shutil
import sys
import tempfile
from pathlib import Path

TOOL = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("spec_tool", TOOL / "spec_tool.py")
spec_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(spec_tool)

ADR = {
    "ADR-0001-erste.md": "# ADR-0001 — Erste\n\n- **Status:** Accepted\n- **Datum:** 2030-01-02\n",
    "ADR-0002-zweite.md": "# ADR-0002 — Zweite\n\n- **Status:** Proposed (Entwurf)\n- **Datum:** 2030-02-03\n",
}
INDEX = """# Index

- [ADR-0001: Erste](architecture/adr/ADR-0001-erste.md) — Accepted
- [ADR-0002: Zweite](architecture/adr/ADR-0002-zweite.md) — Proposed
"""
OVERVIEW = """# Überblick

| ADR | Entscheidung | Status | Datum |
|---|---|---|---|
| [ADR-0001](adr/ADR-0001-erste.md) | Erste | Accepted | 2030-01-02 |
| [ADR-0002](adr/ADR-0002-zweite.md) | Zweite | Proposed | 2030-02-03 |
"""
CODE_MAP = """# Code-Landkarte

Pfade: `app/lib/main.dart`, `app/lib/features/<bereich>/`, `tool/`.

## Große Dateien

| Datei | Zeilen | Abschnitte (Suchbegriffe) |
|---|---|---|
| `app/lib/main.dart` | 3 | `void main`, `class App` |

## Danach

`ohne/pfadprüfung` steht hier nur als Text.
"""
FILES = {
    "docs/index.md": INDEX,
    "docs/architecture/overview.md": OVERVIEW,
    "docs/architecture/code-map.md": CODE_MAP,
    "app/lib/main.dart": "void main() {}\nclass App {}\n",
    "app/lib/features/plan/plan.dart": "",
    "tool/x.py": "",
    **{f"docs/architecture/adr/{name}": text for name, text in ADR.items()},
}

# (Name, Datei, alter Text, neuer Text, erwartete Meldung)
CASES = [
    ("ADR-Link im Index entfernt", "docs/index.md",
     "- [ADR-0002: Zweite](architecture/adr/ADR-0002-zweite.md) — Proposed\n", "",
     "docs/index.md: ADR-0002-zweite.md nicht verlinkt"),
    ("Status im Index abweichend", "docs/index.md",
     "ADR-0002-zweite.md) — Proposed", "ADR-0002-zweite.md) — Accepted",
     "docs/index.md: ADR-0002-zweite.md ohne Status Proposed der ADR-Datei"),
    ("zusätzlicher Status im Index", "docs/index.md",
     "ADR-0001-erste.md) — Accepted", "ADR-0001-erste.md) — Accepted (vorher Proposed)",
     "docs/index.md: ADR-0001-erste.md mit abweichendem Status"),
    ("Status im Überblick geändert", "docs/architecture/overview.md",
     "| Zweite | Proposed |", "| Zweite | Accepted |",
     "overview.md: ADR-0002-zweite.md ohne Status Proposed der ADR-Datei"),
    ("zusätzlicher Status im Überblick", "docs/architecture/overview.md",
     "| Erste | Accepted |", "| Erste (Proposed) | Accepted |",
     "overview.md: ADR-0001-erste.md mit abweichendem Status Proposed"),
    ("Datum im Überblick geändert", "docs/architecture/overview.md",
     "2030-01-02", "2030-01-03",
     "overview.md: ADR-0001-erste.md ohne Datum 2030-01-02 der ADR-Datei"),
    ("ADR fehlt in der Tabelle", "docs/architecture/overview.md",
     "| [ADR-0001](adr/ADR-0001-erste.md) | Erste | Accepted | 2030-01-02 |\n", "",
     "overview.md: ADR-0001-erste.md steht 0-mal in der ADR-Tabelle"),
    ("ADR doppelt in der Tabelle", "docs/architecture/overview.md",
     "| [ADR-0001](adr/ADR-0001-erste.md) | Erste | Accepted | 2030-01-02 |\n",
     "| [ADR-0001](adr/ADR-0001-erste.md) | Erste | Accepted | 2030-01-02 |\n" * 2,
     "overview.md: ADR-0001-erste.md steht 2-mal in der ADR-Tabelle"),
    ("Status der ADR-Datei geändert", "docs/architecture/adr/ADR-0001-erste.md",
     "**Status:** Accepted", "**Status:** Superseded",
     "overview.md: ADR-0001-erste.md ohne Status Superseded der ADR-Datei"),
    ("Statuszeile der ADR fehlt", "docs/architecture/adr/ADR-0001-erste.md",
     "- **Status:** Accepted\n", "",
     "ADR-0001-erste.md: Status- oder Datumszeile fehlt"),
    ("Pfad der Code-Landkarte fehlt", "docs/architecture/code-map.md",
     "`tool/`", "`tool/gibt_es_nicht.py`",
     "code-map.md: Pfad fehlt: tool/gibt_es_nicht.py"),
    ("Pfad vor dem Platzhalter fehlt", "docs/architecture/code-map.md",
     "`app/lib/features/<bereich>/`", "`app/lib/feature/<bereich>/`",
     "code-map.md: Pfad fehlt: app/lib/feature/<bereich>/"),
    ("Suchbegriff fehlt", "docs/architecture/code-map.md",
     "`class App`", "`class Gone`",
     "code-map.md: Suchbegriff fehlt in `app/lib/main.dart`: class Gone"),
    ("Abschnitt Große Dateien fehlt", "docs/architecture/code-map.md",
     "## Große Dateien", "## Andere Dateien",
     "code-map.md: Abschnitt 'Große Dateien' fehlt"),
    ("Code-Landkarte fehlt", "docs/architecture/code-map.md", None, None,
     "docs/architecture/code-map.md fehlt"),
]


def build(root):
    for rel, text in FILES.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")


def main():
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp) / "base"
        build(base)
        errors = spec_tool.architecture_errors(base)
        if errors:
            failures.append(f"Grundbaum nicht grün: {errors}")
        for name, rel, old, new, expected in CASES:
            root = Path(tmp) / "case"
            shutil.rmtree(root, ignore_errors=True)
            build(root)
            path = root / rel
            if old is None:
                path.unlink()
            else:
                text = path.read_text(encoding="utf-8")
                if old not in text:
                    failures.append(f"{name}: Ausgangstext nicht gefunden")
                    continue
                path.write_text(text.replace(old, new, 1), encoding="utf-8")
            errors = spec_tool.architecture_errors(root)
            if not any(expected in e for e in errors):
                failures.append(f"{name}: erwartet '{expected}', erhalten {errors}")
            else:
                print(f"rot wie erwartet: {name}")
    # Anschluss: check() muss die Meldungen von architecture_errors übernehmen (sonst liefe die Prüfung nie im Gate).
    real = spec_tool.architecture_errors
    spec_tool.architecture_errors = lambda root=spec_tool.ROOT: ["Probe-Abweichung"]
    try:
        with contextlib.redirect_stdout(io.StringIO()) as out:
            rc = spec_tool.check()
    finally:
        spec_tool.architecture_errors = real
    if rc != 1 or "FEHLER Probe-Abweichung" not in out.getvalue():
        failures.append(f"check() übernimmt architecture_errors nicht (Exit {rc})")
    else:
        print("rot wie erwartet: check() mit Abweichung der Architektur-Doku")
    errors = spec_tool.architecture_errors(spec_tool.ROOT)
    if errors:
        failures.append(f"echter Baum nicht grün: {errors}")
    for failure in failures:
        print("FEHLER", failure)
    print("Ergebnis:", "FAIL" if failures else "PASS")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
