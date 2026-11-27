#!/bin/sh
# Prüfungen am gebauten Release-AAB mit denselben Regeln wie am Release-APK (aus tool/build_signed.sh).
# Aufruf: tool/check_release_aab.sh <aab>. Fail-closed; Exit 0 nur, wenn alle Prüfungen grün sind.
# Weg: Das Basismodul wird als APK im Proto-Format abgelegt (tool/aab_to_apk.py) und mit aapt2 aus den Build-Tools des
# Android SDK in ein binäres APK umgewandelt; darauf läuft tool/check_release_apk.sh (Rechte, Boot-Empfänger, HTTPS,
# Backups, Exporte, FileProvider, Kamera, Marker der Debug-Quellen). Die Marker der Debug-Quellen werden zusätzlich im
# AAB selbst gesucht (auch in den Metadaten des Bundles).
[ $# -eq 1 ] || { echo "Aufruf: tool/check_release_aab.sh <aab>"; exit 2; }
[ -f "$1" ] || { echo "$1 fehlt"; exit 1; }
aab_abs=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")/.." || exit 1
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
aapt2=$(ls "$sdk"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1)
[ -n "$aapt2" ] || { echo "aapt2 nicht gefunden unter $sdk/build-tools"; exit 1; }
python3 tool/check_debug_code.py artifact "$aab_abs" || exit 1
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
python3 tool/aab_to_apk.py "$aab_abs" "$tmp/proto.zip" || exit 1
"$aapt2" convert --output-format binary -o "$tmp/base.apk" "$tmp/proto.zip" || { echo "aapt2 convert scheiterte"; exit 1; }
sh tool/check_release_apk.sh "$tmp/base.apk" || exit 1
echo "Release-AAB: dieselben Prüfungen wie am Release-APK grün"
