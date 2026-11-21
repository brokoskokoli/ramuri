#!/usr/bin/env python3
"""Gate-Schritt "Wartezeiten in App-Tests": Ratsche für feste Wartezeiten. Aufruf: check_test_waits.py [Repo-Wurzel].

Gezählt wird jedes `Future.delayed` in Dart-Dateien unter app/test/ (auch mit Typargument wie `Future<void>.delayed`
und über Zeilenumbrüche, auch in Kommentaren). Widget-Tests warten stattdessen auf das Ereignis, das sie brauchen
(Helfer app/test/support/settle_storage.dart, siehe docs/quality/testing.md).

Ratsche: Mehr als die Grundlinie ist rot (mit Datei:Zeile aller Fundstellen), weniger ebenfalls rot mit
"Grundlinie auf <n> senken" - so sinkt sie mit jeder Umstellung.

Fail-closed: fehlendes app/test/, unlesbare Dateien und symbolische Links sind rot."""
import os, re, sys

# Grundlinie: gemessener Stand. Nur senken (der Hinweis nennt den neuen Wert), nie erhöhen.
TEST_WAITS = 57

TEST_DIR = "app/test"
PATTERN = re.compile(r"\bFuture\s*(?:<[^;{}]*?>)?\s*\.\s*delayed\b")


def scan(root):
    """Liefert (Fundstellen [(Datei, Zeile)], Fehler)."""
    base = os.path.join(root, TEST_DIR)
    hits, errors = [], []
    if not os.path.isdir(base) or os.path.islink(base):
        return hits, [f"{TEST_DIR}/ fehlt oder ist kein Ordner"]
    for d, dirs, files in os.walk(base):
        for x in sorted(dirs):
            if os.path.islink(os.path.join(d, x)):
                errors.append(f"{os.path.relpath(os.path.join(d, x), root)}: symbolischer Link")
        dirs[:] = sorted(x for x in dirs if not os.path.islink(os.path.join(d, x)))
        for f in sorted(files):
            p = os.path.join(d, f)
            rel = os.path.relpath(p, root)
            if os.path.islink(p):
                errors.append(f"{rel}: symbolischer Link")
                continue
            if not f.endswith(".dart"):
                continue
            try:
                with open(p, encoding="utf-8") as fh:
                    text = fh.read()
            except (OSError, UnicodeDecodeError) as e:
                errors.append(f"{rel}: unlesbar ({e.__class__.__name__})")
                continue
            for m in PATTERN.finditer(text):
                hits.append((rel, text.count("\n", 0, m.start()) + 1))
    return hits, errors


def main():
    root = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else ".")
    hits, errors = scan(root)
    n = len(hits)
    print(f"Wartezeiten in {TEST_DIR}/: {n} Future.delayed (Grundlinie TEST_WAITS = {TEST_WAITS})")
    if errors:
        print("Wartezeiten-Prüfung rot:")
        print("\n".join(errors))
        sys.exit(1)
    if n > TEST_WAITS:
        print(f"Wartezeiten-Prüfung rot: {n} Future.delayed, Grundlinie {TEST_WAITS}: neue feste Wartezeit. "
              f"Auf das Ereignis warten (settleStorage in app/test/support/settle_storage.dart) statt fest zu warten.")
        for f, l in hits:
            print(f"  {f}:{l}")
        sys.exit(1)
    if n < TEST_WAITS:
        print(f"Wartezeiten-Prüfung rot: {n} Future.delayed, weniger als die Grundlinie: Grundlinie auf {n} senken "
              f"(TEST_WAITS in tool/check_test_waits.py)")
        sys.exit(1)


if __name__ == "__main__":
    main()
