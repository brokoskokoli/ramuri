#!/usr/bin/env python3
"""Debug-Quellen (app/lib/debug/) gehören nur in den Debug-Einstieg, nie in den Release-Build (SEC-0009).

Aufruf:
  check_debug_code.py static [<repo>]             Gate, statisch: Nur app/lib/main_debug.dart und Dateien unter
                                                  app/lib/debug/ dürfen eine Datei aus app/lib/debug/ per import,
                                                  export oder part einbinden (auch bedingt, relativ oder über
                                                  package:running_app/debug/).
  check_debug_code.py artifact <apk|aab> [<repo>]  Release-Artefakt: Jede Datei app/lib/debug/*.dart trägt einen
                                                  Marker (const String <name>Marker = '…';). Keiner davon darf in
                                                  einer Datei des Artefakts stehen.

<repo> ist die Repo-Wurzel (Vorgabe: Elternordner von tool/). Fail-closed: fehlender Ordner, Datei ohne Marker oder
unlesbares Artefakt ist rot. Der Selbsttest tool/check_debug_code_test.py belegt jede Regel als rot."""
import os, re, sys, zipfile

PACKAGE = "running_app"
LIB = os.path.join("app", "lib")
DEBUG = os.path.join(LIB, "debug")
ENTRY = os.path.join(LIB, "main_debug.dart")

_DIRECTIVE = re.compile(r"^\s*(?:import|export|part)\b([^;]*);", re.M | re.S)
_STRING = re.compile(r"""(?:'([^']*)'|"([^"]*)")""")
_MARKER = re.compile(r"^const String (\w+Marker) = '([^']+)';$", re.M)


def is_debug_target(root, source, uri):
    """True, wenn die URI aus der Datei source (relativ zur Repo-Wurzel) eine Datei unter app/lib/debug/ meint."""
    if uri.startswith("package:"):
        return uri.startswith(f"package:{PACKAGE}/debug/")
    if ":" in uri:
        return False
    target = os.path.normpath(os.path.join(os.path.dirname(source), uri))
    return target == DEBUG or target.startswith(DEBUG + os.sep)


def check_static(root):
    lib = os.path.join(root, LIB)
    if not os.path.isdir(os.path.join(root, DEBUG)):
        return [f"{DEBUG} fehlt"]
    errors = []
    for d, _, files in os.walk(lib):
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            rel = os.path.relpath(os.path.join(d, name), root)
            if rel == ENTRY or rel.startswith(DEBUG + os.sep):
                continue
            with open(os.path.join(root, rel), encoding="utf-8") as f:
                text = f.read()
            for m in _DIRECTIVE.finditer(text):
                for s in _STRING.finditer(m.group(1)):
                    uri = s.group(1) if s.group(1) is not None else s.group(2)
                    if is_debug_target(root, rel, uri):
                        errors.append(f"{rel} bindet die Debug-Quelle {uri} ein (nur {ENTRY} und {DEBUG}/ dürfen das)")
    return errors


def markers(root):
    """(Marker je Datei unter app/lib/debug/, Fehler). Jede .dart-Datei braucht genau einen Marker."""
    debug = os.path.join(root, DEBUG)
    if not os.path.isdir(debug):
        return [], [f"{DEBUG} fehlt"]
    found, errors = [], []
    for d, _, files in os.walk(debug):
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            rel = os.path.relpath(os.path.join(d, name), root)
            with open(os.path.join(root, rel), encoding="utf-8") as f:
                hits = _MARKER.findall(f.read())
            if len(hits) != 1:
                errors.append(f"{rel}: genau ein Marker (const String <name>Marker = '…';) erwartet, gefunden: "
                              f"{len(hits)}")
                continue
            found.append((rel, hits[0][0], hits[0][1]))
    if not found and not errors:
        errors.append(f"{DEBUG}: keine Debug-Quelle gefunden")
    return found, errors


def check_artifact(path, root):
    found, errors = markers(root)
    if errors:
        return errors
    try:
        with zipfile.ZipFile(path) as z:
            for entry in z.namelist():
                data = z.read(entry)
                for rel, name, marker in found:
                    if marker.encode() in data:
                        errors.append(f"{os.path.basename(path)} enthält die Debug-Quelle {rel} ({name} in {entry})")
    except (OSError, zipfile.BadZipFile) as e:
        return [f"{path}: nicht lesbar ({e})"]
    return errors


def main(argv):
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if len(argv) in (2, 3) and argv[1] == "static":
        root = argv[2] if len(argv) == 3 else here
        errors = check_static(root)
        ok = f"Debug-Quellen nur aus {ENTRY} und {DEBUG}/ eingebunden"
    elif len(argv) in (3, 4) and argv[1] == "artifact":
        root = argv[3] if len(argv) == 4 else here
        errors = check_artifact(argv[2], root)
        ok = f"Keine Debug-Quelle aus {DEBUG}/ in {os.path.basename(argv[2])} (Marker je Datei geprüft)"
    else:
        print(__doc__.split("\n\n")[1])
        return 2
    for e in errors:
        print(e)
    if not errors:
        print(ok)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
