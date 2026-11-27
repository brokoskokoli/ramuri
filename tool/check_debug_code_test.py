#!/usr/bin/env python3
"""Selbsttest für tool/check_debug_code.py.

Statisch: Ein kleiner Nachbau von app/lib/ (Einstieg main_debug.dart, Debug-Quellen unter debug/, Release-Code
daneben) ist grün; jede Einbindung einer Debug-Quelle aus einer anderen Datei ist rot. Artefakt: Ein ZIP ohne Marker
ist grün; ein ZIP mit dem Marker einer Debug-Quelle des Repos (auch debug_ppg_panel.dart) ist rot. Wird eine Regel im
Prüfskript entfernt oder aufgeweicht, wird der zugehörige Fall grün und dieser Test rot."""
import os, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
CHECK = os.path.join(HERE, "check_debug_code.py")
REPO = os.path.dirname(HERE)

BASE = {
    "app/lib/main.dart": "import 'app.dart';\n\nvoid main() {}\n",
    "app/lib/main_debug.dart": "import 'app.dart';\nimport 'debug/debug_a.dart';\n"
                               "import 'package:running_app/debug/debug_b.dart';\n",
    "app/lib/app.dart": "import 'package:flutter/widgets.dart';\nimport 'features/x/x.dart';\n"
                        "// import 'debug/debug_a.dart';\n/// Siehe debug/debug_a.dart\n",
    "app/lib/features/x/x.dart": "import '../../ui/debugging_hint.dart';\nimport 'package:other/debug/y.dart';\n",
    "app/lib/ui/debugging_hint.dart": "const String hint = 'debug/';\n",
    "app/lib/debug/debug_a.dart": "import 'debug_b.dart';\n\nconst String aMarker = 'TEST-DEBUG-A-111111';\n",
    "app/lib/debug/debug_b.dart": "import '../app.dart';\n\nconst String bMarker = 'TEST-DEBUG-B-222222';\n",
    "app/test/debug_a_test.dart": "import 'package:running_app/debug/debug_a.dart';\n",
}


def with_file(path, content):
    out = dict(BASE)
    out[path] = content
    return out


# (Name, Dateien, erwartete Meldung oder None für grün)
STATIC = [
    ("Ausgangslage grün", BASE, None),
    ("relativer Import aus dem Release-Code", with_file("app/lib/app.dart", "import 'debug/debug_a.dart';\n"),
     "app/lib/app.dart bindet die Debug-Quelle debug/debug_a.dart ein"),
    ("package-Import aus einem Feature",
     with_file("app/lib/features/x/x.dart", "import 'package:running_app/debug/debug_b.dart';\n"),
     "app/lib/features/x/x.dart bindet die Debug-Quelle package:running_app/debug/debug_b.dart ein"),
    ("relativer Import mit ../", with_file("app/lib/features/x/x.dart", "import '../../debug/debug_a.dart';\n"),
     "bindet die Debug-Quelle ../../debug/debug_a.dart ein"),
    ("Umweg über ./ und ..", with_file("app/lib/ui/u.dart", "import './../debug/./debug_a.dart';\n"),
     "app/lib/ui/u.dart bindet die Debug-Quelle"),
    ("export", with_file("app/lib/app.dart", 'export "debug/debug_b.dart" show bMarker;\n'),
     "bindet die Debug-Quelle debug/debug_b.dart ein"),
    ("part", with_file("app/lib/app.dart", "part 'debug/debug_a.dart';\n"), "bindet die Debug-Quelle debug/debug_a.dart"),
    ("bedingter Import", with_file("app/lib/app.dart", "import 'stub.dart'\n    if (dart.library.io) "
                                   "'debug/debug_a.dart';\n"), "bindet die Debug-Quelle debug/debug_a.dart"),
    ("Import mit Einrückung und as", with_file("app/lib/app.dart", "  import 'debug/debug_a.dart' as d;\n"),
     "bindet die Debug-Quelle debug/debug_a.dart"),
    ("Datei in Unterordner von debug/", with_file("app/lib/app.dart", "import 'debug/sub/c.dart';\n"),
     "bindet die Debug-Quelle debug/sub/c.dart"),
    ("Ordner debug/ fehlt", {k: v for k, v in BASE.items() if "/debug/" not in k}, "app/lib/debug fehlt"),
]

ARTIFACT = [
    # (Name, Dateien, Einträge des Artefakts, erwartete Meldung oder None)
    ("Artefakt ohne Marker grün", BASE, {"lib/arm64-v8a/libapp.so": b"\x7fELF RUNAPP sonst nichts"}, None),
    ("Marker einer Debug-Quelle im Artefakt", BASE,
     {"classes.dex": b"x", "lib/arm64-v8a/libapp.so": b"\x00TEST-DEBUG-B-222222\x00"},
     "enthält die Debug-Quelle app/lib/debug/debug_b.dart (bMarker in lib/arm64-v8a/libapp.so)"),
    ("Marker im AAB-Modul", BASE, {"base/lib/x86_64/libapp.so": b"..TEST-DEBUG-A-111111.."},
     "app/lib/debug/debug_a.dart (aMarker in base/lib/x86_64/libapp.so)"),
    ("Debug-Quelle ohne Marker", with_file("app/lib/debug/debug_c.dart", "class C {}\n"), {"x": b""},
     "app/lib/debug/debug_c.dart: genau ein Marker"),
    ("Debug-Quelle mit zwei Markern",
     with_file("app/lib/debug/debug_c.dart", "const String cMarker = 'C1';\nconst String dMarker = 'C2';\n"),
     {"x": b""}, "app/lib/debug/debug_c.dart: genau ein Marker"),
    ("Debug-Quelle im Unterordner ohne Marker", with_file("app/lib/debug/sub/c.dart", "class C {}\n"), {"x": b""},
     "app/lib/debug/sub/c.dart: genau ein Marker"),
    ("leerer Ordner debug/", {k: v for k, v in BASE.items() if "/debug/" not in k} | {"app/lib/debug/x.txt": ""},
     {"x": b""}, "keine Debug-Quelle gefunden"),
]


def write_tree(root, tree):
    for path, content in tree.items():
        full = os.path.join(root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as f:
            f.write(content)


def run(*args):
    r = subprocess.run([sys.executable, CHECK, *args], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def judge(name, rc, out, expect):
    ok = rc == 0 if expect is None else (rc == 1 and expect in out)
    print(("OK    " if ok else "FALSCH") + f" {name}" + ("" if ok else f" (rc={rc}): {out.strip()}"))
    return not ok


def main():
    failed = 0
    for name, tree, expect in STATIC:
        with tempfile.TemporaryDirectory() as d:
            write_tree(d, tree)
            failed += judge("statisch: " + name, *run("static", d), expect)
    for name, tree, entries, expect in ARTIFACT:
        with tempfile.TemporaryDirectory() as d:
            write_tree(d, tree)
            art = os.path.join(d, "out.apk")
            with zipfile.ZipFile(art, "w", zipfile.ZIP_DEFLATED) as z:
                for entry, data in entries.items():
                    z.writestr(entry, data)
            failed += judge("Artefakt: " + name, *run("artifact", art, d), expect)
    # Mit den echten Debug-Quellen des Repos: jede trägt einen Marker; der Marker von debug_ppg_panel.dart in einem
    # Artefakt ist rot, ein Artefakt ohne Marker grün. Kein lesbares Artefakt ist rot.
    panel = os.path.join(REPO, "app", "lib", "debug", "debug_ppg_panel.dart")
    with open(panel, encoding="utf-8") as f:
        marker = next(l.split("'")[1] for l in f if l.startswith("const String debugPpgPanelMarker = '"))
    with tempfile.TemporaryDirectory() as d:
        art = os.path.join(d, "release.apk")
        with zipfile.ZipFile(art, "w", zipfile.ZIP_DEFLATED) as z:
            z.writestr("lib/arm64-v8a/libapp.so", b"\x00" + marker.encode() + b"\x00")
        failed += judge("Repo: Marker von debug_ppg_panel.dart im Release-APK", *run("artifact", art, REPO),
                        "enthält die Debug-Quelle app/lib/debug/debug_ppg_panel.dart (debugPpgPanelMarker")
        with zipfile.ZipFile(art, "w") as z:
            z.writestr("lib/arm64-v8a/libapp.so", b"\x00ohne\x00")
        failed += judge("Repo: Artefakt ohne Marker grün", *run("artifact", art, REPO), None)
        with open(art, "wb") as f:
            f.write(b"kein zip")
        failed += judge("Repo: unlesbares Artefakt", *run("artifact", art, REPO), "nicht lesbar")
        failed += judge("Repo: Artefakt fehlt", *run("artifact", os.path.join(d, "fehlt.apk"), REPO), "nicht lesbar")
    failed += judge("Repo: statisch grün", *run("static", REPO), None)
    rc, out = run()
    ok = rc == 2 and "Aufruf" in out
    print(("OK    " if ok else "FALSCH") + " Aufruf ohne Modus: Exit 2 mit Hilfe" + ("" if ok else f" (rc={rc})"))
    failed += not ok
    print("Selbsttest grün" if not failed else f"Selbsttest rot: {failed} Fälle")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
