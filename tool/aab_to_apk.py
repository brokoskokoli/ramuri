#!/usr/bin/env python3
"""Legt das Basismodul eines Android App Bundle (AAB) als APK im Proto-Format ab, damit `aapt2 convert` daraus ein
gewöhnliches (binäres) APK machen kann, das tool/check_release_apk.sh mit denselben Regeln wie das Release-APK prüft.

Aufruf: aab_to_apk.py <app.aab> <ausgabe.zip>

Abbildung wie beim Erzeugen eines APK aus dem Bundle: base/manifest/AndroidManifest.xml -> AndroidManifest.xml,
base/resources.pb -> resources.pb, base/res|lib|assets/** unverändert, base/dex/* -> Wurzel, base/root/** -> Wurzel.
Andere Module als base oder unbekannte Einträge unter base/ sind rot (fail-closed): Sie kämen sonst ungeprüft mit.
Ausgelassen werden nur die Metadaten des Bundles (BundleConfig.pb, BUNDLE-METADATA/, META-INF/, base/*.pb außer
resources.pb). Selbsttest: tool/aab_to_apk_test.py."""
import sys, zipfile

BUNDLE_META = ("BundleConfig.pb",)
BUNDLE_META_DIRS = ("BUNDLE-METADATA/", "META-INF/")
BASE_META = ("base/assets.pb", "base/native.pb")


def target(entry):
    """Pfad im APK, None für ausgelassene Metadaten; ValueError für Unerwartetes."""
    if entry.endswith("/"):
        return None
    if entry in BUNDLE_META or entry.startswith(BUNDLE_META_DIRS) or entry in BASE_META:
        return None
    if not entry.startswith("base/"):
        raise ValueError(f"Eintrag außerhalb des Basismoduls: {entry}")
    rest = entry[len("base/"):]
    if rest == "manifest/AndroidManifest.xml":
        return "AndroidManifest.xml"
    if rest == "resources.pb":
        return "resources.pb"
    if rest.startswith(("res/", "lib/", "assets/")):
        return rest
    if rest.startswith("dex/") and rest.count("/") == 1 and rest.endswith(".dex"):
        return rest[len("dex/"):]
    if rest.startswith("root/") and len(rest) > len("root/"):
        return rest[len("root/"):]
    raise ValueError(f"unbekannter Eintrag im Basismodul: {entry}")


def convert(aab, out):
    with zipfile.ZipFile(aab) as z:
        names = z.namelist()
        mapping = []
        for n in names:
            t = target(n)
            if t is not None:
                mapping.append((n, t))
        targets = [t for _, t in mapping]
        for required in ("AndroidManifest.xml", "resources.pb"):
            if required not in targets:
                raise ValueError(f"{required} fehlt im Basismodul")
        if len(set(targets)) != len(targets):
            raise ValueError("doppelter Zielpfad im APK")
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as o:
            for n, t in mapping:
                o.writestr(t, z.read(n))


def main(argv):
    if len(argv) != 3:
        print(__doc__.split("\n\n")[1])
        return 2
    try:
        convert(argv[1], argv[2])
    except (OSError, zipfile.BadZipFile, ValueError) as e:
        print(f"AAB nicht umwandelbar: {e}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
