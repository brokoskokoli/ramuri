#!/usr/bin/env python3
"""Selbsttest für tool/aab_to_apk.py: Abbildung des Basismoduls auf die APK-Pfade; Unerwartetes ist rot."""
import os, subprocess, sys, tempfile, zipfile

CHECK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "aab_to_apk.py")

BASE = {
    "BundleConfig.pb": b"cfg", "BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map": b"map",
    "META-INF/MANIFEST.MF": b"mf", "base/assets.pb": b"a", "base/native.pb": b"n",
    "base/manifest/AndroidManifest.xml": b"manifest", "base/resources.pb": b"res",
    "base/res/4j.xml": b"der", "base/lib/arm64-v8a/libapp.so": b"so", "base/assets/flutter_assets/x": b"asset",
    "base/dex/classes.dex": b"dex", "base/dex/classes2.dex": b"dex2", "base/root/kotlin/k.kotlin_builtins": b"k",
}
EXPECTED = {
    "AndroidManifest.xml": b"manifest", "resources.pb": b"res", "res/4j.xml": b"der", "lib/arm64-v8a/libapp.so": b"so",
    "assets/flutter_assets/x": b"asset", "classes.dex": b"dex", "classes2.dex": b"dex2",
    "kotlin/k.kotlin_builtins": b"k",
}


def run(entries):
    with tempfile.TemporaryDirectory() as d:
        aab, out = os.path.join(d, "app.aab"), os.path.join(d, "proto.zip")
        with zipfile.ZipFile(aab, "w") as z:
            for k, v in entries.items():
                z.writestr(k, v)
        r = subprocess.run([sys.executable, CHECK, aab, out], capture_output=True, text=True)
        content = None
        if os.path.exists(out):
            with zipfile.ZipFile(out) as z:
                content = {n: z.read(n) for n in z.namelist()}
        return r.returncode, r.stdout + r.stderr, content


CASES = [
    ("zweites Modul", dict(BASE, **{"feature/manifest/AndroidManifest.xml": b"m"}), "außerhalb des Basismoduls"),
    ("unbekannter Eintrag im Basismodul", dict(BASE, **{"base/other/x": b"x"}), "unbekannter Eintrag"),
    ("dex in Unterordner", dict(BASE, **{"base/dex/sub/classes.dex": b"x"}), "unbekannter Eintrag"),
    ("Manifest fehlt", {k: v for k, v in BASE.items() if "manifest/" not in k}, "AndroidManifest.xml fehlt"),
    ("Ressourcentabelle fehlt", {k: v for k, v in BASE.items() if k != "base/resources.pb"}, "resources.pb fehlt"),
    ("doppelter Zielpfad", dict(BASE, **{"base/root/classes.dex": b"x"}), "doppelter Zielpfad"),
]


def main():
    failed = 0
    rc, out, content = run(BASE)
    ok = rc == 0 and content == EXPECTED
    print(("OK    " if ok else "FALSCH") + " Basismodul wird abgebildet" + ("" if ok else f" (rc={rc}): {out} {content}"))
    failed += not ok
    for name, entries, expect in CASES:
        rc, out, _ = run(entries)
        ok = rc == 1 and expect in out
        print(("OK    " if ok else "FALSCH") + f" {name}" + ("" if ok else f" (rc={rc}): {out.strip()}"))
        failed += not ok
    print("Selbsttest grün" if not failed else f"Selbsttest rot: {failed} Fälle")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
