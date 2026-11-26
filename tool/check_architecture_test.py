#!/usr/bin/env python3
"""Selbsttest für tool/check_architecture.py. Aufruf: check_architecture_test.py [Repo-Wurzel]

Baut kleine Beispielbäume (core-Module unter app/packages/core/lib/src/, Features unter app/lib/features/) und prüft
sie mit einer Kopie des Skripts, deren Grundlinien auf den Wert des Falls gesetzt sind. Jeder Fall erwartet grün oder
rot mit einer bestimmten Meldung. Zuletzt läuft das echte Skript auf dem echten Baum (grün). Wird eine Regel in
check_architecture.py entfernt oder aufgeweicht, wird der zugehörige Fall grün und dieser Test rot."""
import os, re, shutil, subprocess, sys, tempfile

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
CHECK = os.path.join(REPO, "tool", "check_architecture.py")
C = "app/packages/core/lib/src/"
A = "app/lib/features/"

# Grundbaum ohne Zyklus: core a → b → c, App x → y; dazu Fremdimporte, die nicht zählen.
BASE = {
    C + "a/a.dart": "import 'dart:math';\nimport '../b/b.dart';\nimport '../../ports/p.dart';\nclass A {}\n",
    C + "b/b.dart": "import '../c/c.dart';\n// import '../a/a.dart';\nfinal s = \"import '../a/a.dart';\";\nclass B {}\n",
    C + "c/c.dart": "import '../shared.dart';\nclass Cc {}\n",
    C + "shared.dart": "enum Shared { x }\n",
    C + "calendar/day.dart": "import '../../ports/p.dart';\nclass Day {}\n",
    C + "algorithms/registry.dart": "import '../a/a.dart';\nimport '../calendar/day.dart';\nclass R {}\n",
    "app/packages/core/lib/ports/p.dart": "import '../src/a/a.dart';\nclass P {}\n",
    A + "x/x_screen.dart": "import 'package:flutter/widgets.dart';\nimport 'package:core/core.dart';\n"
                           "import '../y/y.dart';\nimport '../../ui/ui.dart';\nclass X {}\n",
    A + "y/y.dart": "import '../../app.dart';\nclass Y {}\n",
}

CYCLE = {C + "c/c.dart": "import '../a/a.dart';\nclass Cc {}\n"}

CASES = [
    # (Name, Änderungen am Grundbaum, Grundlinie core, Grundlinie app, erwartete Meldung oder None für grün)
    ("kein Zyklus", {}, 0, 0, None),
    ("Zyklus mit passender Grundlinie", CYCLE, 3, 0, None),
    ("neuer Zyklus über import", CYCLE, 0, 0,
     r"core: 3 Module in Zyklen, Grundlinie 0: neuer Zyklus"),
    ("ein Modul mehr als die Grundlinie", CYCLE, 2, 0, r"core: 3 Module in Zyklen, Grundlinie 2: neuer Zyklus"),
    ("neuer Zyklus nennt Modulnamen und Datei:Zeile", CYCLE, 0, 0,
     r"c → a: app/packages/core/lib/src/c/c\.dart:1 \(zurück über a → b → c\)"),
    ("neuer Zyklus über export", {C + "c/c.dart": "export '../a/a.dart';\n"}, 0, 0,
     r"c → a: app/packages/core/lib/src/c/c\.dart:1"),
    ("neuer Zyklus über part", {C + "c/c.dart": "part '../a/a_part.dart';\n", C + "a/a_part.dart": "part of 'x.dart';\n"}, 0, 0,
     r"c → a: app/packages/core/lib/src/c/c\.dart:1"),
    ("neuer Zyklus über package:core/src", {C + "c/c.dart": "import 'package:core/src/a/a.dart';\n"}, 0, 0,
     r"c → a: app/packages/core/lib/src/c/c\.dart:1"),
    ("neuer Zyklus über bedingten Import", {C + "c/c.dart": "import 'c_io.dart' if (dart.library.io) '../a/a.dart';\n"}, 0, 0,
     r"c → a: app/packages/core/lib/src/c/c\.dart:1"),
    ("neuer Zyklus über Datei direkt in src", {C + "c/c.dart": "import '../shared.dart';\n",
                                                C + "shared.dart": "import 'a/a.dart';\n"}, 0, 0,
     r"c → a: app/packages/core/lib/src/c/c\.dart:1"),
    ("neuer Zyklus in erzeugter Datei", {C + "c/c.g.dart": "import '../a/a.dart';\n"}, 0, 0,
     r"c → a: app/packages/core/lib/src/c/c\.g\.dart:1"),
    ("neuer Zyklus zwischen Features", {A + "y/y.dart": "import '../x/x_screen.dart';\n"}, 0, 0,
     r"y → x: app/lib/features/y/y\.dart:1"),
    ("neuer Zyklus zwischen Features über package:", {A + "y/y.dart": "import 'package:running_app/features/x/x_screen.dart';\n"},
     0, 0, r"app: 2 Module in Zyklen, Grundlinie 0: neuer Zyklus"),
    ("Grundlinie core unterschritten", {}, 3, 0, r"core: 0 Module in Zyklen, weniger als die Grundlinie: Grundlinie auf 0 senken"),
    ("Grundlinie app unterschritten", {}, 0, 2, r"app: 0 Module in Zyklen, weniger als die Grundlinie: Grundlinie auf 0 senken"),
    ("Blattmodul importiert anderes Modul", {C + "calendar/day.dart": "import '../c/c.dart';\n"}, 0, 0,
     r"src/calendar/day\.dart:1: Blattmodul calendar importiert Modul c"),
    ("Blattmodul importiert Modul über Datei direkt in src",
     {C + "calendar/day.dart": "import '../shared.dart';\n", C + "shared.dart": "import 'c/c.dart';\n"}, 0, 0,
     r"src/calendar/day\.dart:1: Blattmodul calendar importiert Modul c"),
    ("Blattmodul fehlt", {C + "calendar/day.dart": None}, 0, 0, r"core: Blattmodul calendar fehlt"),
    ("Modul importiert oberes Modul", {C + "c/c.dart": "import '../algorithms/registry.dart';\n"}, 0, 0,
     r"src/c/c\.dart:1: Modul c importiert oberes Modul algorithms"),
    ("Modul importiert oberes Modul über Datei direkt in src",
     {C + "c/c.dart": "import '../shared.dart';\n", C + "shared.dart": "import 'algorithms/registry.dart';\n"}, 0, 0,
     r"src/c/c\.dart:1: Modul c importiert oberes Modul algorithms"),
    ("oberes Modul fehlt", {C + "algorithms/registry.dart": None}, 0, 0, r"core: Oberes Modul algorithms fehlt"),
    ("unlesbare Datei", {C + "b/bad.dart": b"\xff\xfe import"}, 0, 0, r"src/b/bad\.dart: nicht lesbar \(fail-closed\)"),
    ("Barrel innerhalb von core", {C + "c/c.dart": "import 'package:core/core.dart';\n"}, 0, 0,
     r"src/c/c\.dart:1: Barrel package:core/core\.dart"),
    ("unbekanntes URI-Schema", {C + "c/c.dart": "import 'file:///x/a.dart';\n"}, 0, 0, r"src/c/c\.dart:1: URI-Schema nicht erlaubt"),
    ("Import ohne Zeichenkette", {C + "c/c.dart": "import foo;\n"}, 0, 0, r"src/c/c\.dart:1: import: unbekannte Form"),
    ("Interpolation im URI", {C + "c/c.dart": "import '../${x}/a.dart';\n"}, 0, 0, r"src/c/c\.dart:1: import(: unbekannte Form| ohne lesbare URI)"),
    ("aneinandergereihte Zeichenketten", {C + "c/c.dart": "import '../a' '/a.dart';\n"}, 0, 0,
     r"src/c/c\.dart:1: import: aneinandergereihte Zeichenketten"),
    ("Kommentar nicht beendet", {C + "c/c.dart": "/* import '../a/a.dart';\n"}, 0, 0, r"src/c/c\.dart:1: Kommentar nicht beendet"),
    ("Suchpfad fehlt", {A + "x/x_screen.dart": None, A + "y/y.dart": None}, 0, 0, r"app/lib/features/: Suchpfad fehlt"),
]

def build(extra):
    d = tempfile.mkdtemp(prefix="check_arch_")
    for rel, content in {**BASE, **extra}.items():
        if content is None:
            continue
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w" if isinstance(content, str) else "wb").write(content)
    for rel, content in extra.items():  # leere Ordner nach Entfernen aufräumen
        if content is None:
            par = os.path.dirname(os.path.join(d, rel))
            while os.path.isdir(par) and not os.listdir(par) and par != d:
                os.rmdir(par)
                par = os.path.dirname(par)
    return d

def script(tmp, core, app):
    text = open(CHECK, encoding="utf-8").read()
    for const, val in (("CORE_CYCLE_MODULES", core), ("APP_CYCLE_FEATURES", app)):
        text, n = re.subn(rf"^{const} = \d+$", f"{const} = {val}", text, flags=re.M)
        if n != 1:
            sys.exit(f"FEHLER: Konstante {const} nicht genau einmal in check_architecture.py")
    p = os.path.join(tmp, "check_architecture.py")
    open(p, "w", encoding="utf-8").write(text)
    return p

def run(path, d):
    r = subprocess.run([sys.executable, path, d], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr

def main():
    fails = 0
    tmp = tempfile.mkdtemp(prefix="check_arch_bin_")
    try:
        cases = list(CASES)
        for name, extra, core, app, want in cases:
            d = build(extra)
            try:
                rc, out = run(script(tmp, core, app), d)
            finally:
                shutil.rmtree(d)
            ok = (rc == 0) if want is None else (rc == 1 and re.search(want, out))
            print(("ok  " if ok else "FEHL") + f"  {name}")
            if not ok:
                fails += 1
                print(f"      Exit {rc}, erwartet {'grün' if want is None else want!r}\n" + out)
        # Symbolischer Link auf ein Verzeichnis
        d = build({})
        try:
            os.symlink(os.path.join(d, C, "a"), os.path.join(d, C, "z"))
            rc, out = run(script(tmp, 0, 0), d)
        finally:
            shutil.rmtree(d)
        ok = rc == 1 and "src/z: symbolischer Link" in out
        print(("ok  " if ok else "FEHL") + "  symbolischer Link")
        fails += 0 if ok else 1
        if not ok:
            print(out)
    finally:
        shutil.rmtree(tmp)
    rc, out = run(CHECK, REPO)
    print(("ok  " if rc == 0 else "FEHL") + "  echter Baum mit den Grundlinien im Skript")
    if rc != 0:
        fails += 1
        print(out)
    if fails:
        print(f"{fails} Fall/Fälle falsch")
        sys.exit(1)
    print(f"{len(CASES) + 2} Fälle richtig")

main()
