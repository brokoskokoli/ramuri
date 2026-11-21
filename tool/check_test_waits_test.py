#!/usr/bin/env python3
"""Selbsttest für tool/check_test_waits.py. Aufruf: check_test_waits_test.py [Repo-Wurzel]

Baut kleine Beispielbäume unter app/test/ und prüft sie mit einer Kopie des Skripts, deren Grundlinie auf den Wert des
Falls gesetzt ist. Jeder Fall erwartet grün oder rot mit einer bestimmten Meldung. Zuletzt läuft das echte Skript auf
dem echten Baum (grün). Wird die Zählung in check_test_waits.py aufgeweicht oder die Ratsche entfernt, wird der
zugehörige Fall grün und dieser Test rot."""
import os, re, shutil, subprocess, sys, tempfile

REPO = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), ".."))
CHECK = os.path.join(REPO, "tool", "check_test_waits.py")
T = "app/test/"

# Grundbaum: zwei feste Wartezeiten; dazu Ähnliches, das nicht zählt.
BASE = {
    T + "a_test.dart": "Future<void> f() async {\n  await Future<void>.delayed(Duration.zero);\n}\n",
    T + "sub/b_test.dart": "void g() {\n  Future.delayed(const Duration(milliseconds: 5));\n}\n",
    T + "c_test.dart": "Future<void> h() async {\n  await Future<void>(() {});\n  await Future.value(1);\n"
                       "  final delayedStart = 1;\n  myFuture.delayed;\n}\n",
    T + "notes.txt": "Future.delayed Future.delayed\n",
}

CASES = [
    # (Name, Änderungen am Grundbaum, Grundlinie, erwartete Meldung oder None für grün)
    ("Grundlinie getroffen", {}, 2, None),
    ("neues Future<void>.delayed", {T + "d_test.dart": "x() => Future<void>.delayed(Duration.zero);\n"}, 2,
     r"3 Future\.delayed, Grundlinie 2: neue feste Wartezeit"),
    ("neue Fundstelle mit Datei:Zeile", {T + "d_test.dart": "\n\nx() => Future<void>.delayed(Duration.zero);\n"}, 2,
     r"^  app/test/d_test\.dart:3$"),
    ("neues Future.delayed ohne Typ", {T + "d_test.dart": "x() => Future.delayed(Duration.zero);\n"}, 2,
     r"3 Future\.delayed, Grundlinie 2"),
    ("anderes Typargument", {T + "d_test.dart": "x() => Future<(int, String)>.delayed(Duration.zero);\n"}, 2,
     r"3 Future\.delayed, Grundlinie 2"),
    ("über Zeilenumbruch", {T + "d_test.dart": "x() => Future<void>\n    .delayed(Duration.zero);\n"}, 2,
     r"3 Future\.delayed, Grundlinie 2"),
    ("in einem Hilfsordner", {T + "support/h.dart": "x() => Future<void>.delayed(Duration.zero);\n"}, 2,
     r"3 Future\.delayed, Grundlinie 2"),
    ("zwei in einer Zeile", {T + "d_test.dart": "x() => [Future.delayed(a), Future.delayed(b)];\n"}, 3,
     r"4 Future\.delayed, Grundlinie 3"),
    ("weniger als die Grundlinie", {T + "sub/b_test.dart": "void g() {}\n"}, 2,
     r"1 Future\.delayed, weniger als die Grundlinie: Grundlinie auf 1 senken"),
    ("andere Dateiarten zählen nicht", {T + "more.json": "\"Future.delayed\"\n"}, 2, None),
    ("app/test fehlt", {"__remove__": T}, 0, r"app/test/ fehlt"),
    ("symbolischer Link", {"__link__": (T + "link_test.dart", T + "a_test.dart")}, 2, r"link_test\.dart: symbolischer Link"),
]


def build(tmp, changes, baseline):
    files = dict(BASE)
    for k, v in changes.items():
        if not k.startswith("__"):
            files[k] = v
    for rel, text in files.items():
        p = os.path.join(tmp, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
    if "__remove__" in changes:
        shutil.rmtree(os.path.join(tmp, changes["__remove__"]))
    if "__link__" in changes:
        link, target = changes["__link__"]
        os.symlink(os.path.join(tmp, target), os.path.join(tmp, link))
    with open(CHECK, encoding="utf-8") as fh:
        src = fh.read()
    src, n = re.subn(r"^TEST_WAITS = \d+$", f"TEST_WAITS = {baseline}", src, flags=re.M)
    assert n == 1, "Grundlinie TEST_WAITS nicht gefunden"
    script = os.path.join(tmp, "check.py")
    with open(script, "w", encoding="utf-8") as fh:
        fh.write(src)
    return script


def main():
    fails = 0
    for name, changes, baseline, expect in CASES:
        with tempfile.TemporaryDirectory() as tmp:
            script = build(tmp, changes, baseline)
            r = subprocess.run([sys.executable, "-I", script, tmp], capture_output=True, text=True)
            out = r.stdout + r.stderr
            ok = r.returncode == 0 if expect is None else (r.returncode != 0 and re.search(expect, out, re.M))
            print(f"{'OK  ' if ok else 'FAIL'} {name}")
            if not ok:
                fails += 1
                print(f"     erwartet {'grün' if expect is None else 'rot mit ' + expect!r}, Exit {r.returncode}:")
                print("     " + out.replace("\n", "\n     "))
    r = subprocess.run([sys.executable, "-I", CHECK, REPO], capture_output=True, text=True)
    print(f"{'OK  ' if r.returncode == 0 else 'FAIL'} echter Baum grün")
    if r.returncode != 0:
        fails += 1
        print(r.stdout + r.stderr)
    if fails:
        print(f"check_test_waits Selbsttest rot: {fails} Fall/Fälle")
        sys.exit(1)
    print("check_test_waits Selbsttest grün")


if __name__ == "__main__":
    main()
