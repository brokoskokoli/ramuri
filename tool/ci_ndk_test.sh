#!/usr/bin/env bash
# Test fuer tool/ci_ndk.sh mit Attrappen fuer flutter und sdkmanager (kein Netz): Version aus der
# Flutter-Version, Installation, vorhandenes Paket, Wiederholung nach Fehlschlag oder unvollstaendigem
# Paket, klares Scheitern nach drei Versuchen, ungueltige Version.
# Aufruf: bash tool/ci_ndk_test.sh
set -u
script=$(cd "$(dirname "$0")" && pwd)/ci_ndk.sh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/flutter/bin" "$tmp/flutter/packages/flutter_tools/gradle/src/main/kotlin" "$tmp/bin"
cat > "$tmp/flutter/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt" <<'X'
    /** Sets the ndkVersion used by default in Flutter app projects. */
    val ndkVersion: String = "27.1.12297006"
X
printf '#!/bin/sh\nexit 0\n' > "$tmp/flutter/bin/flutter"
# sdkmanager: zaehlt Aufrufe; FAKE_FAILS = Anzahl erster Versuche mit Exit 1, FAKE_PARTIAL = Anzahl
# erster Versuche, die Exit 0 melden, aber ein unvollstaendiges Paket hinterlassen.
cat > "$tmp/bin/sdkmanager" <<'X'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_COUNT"
pkg=${@: -1}; v=${pkg#ndk;}; root=; for a in "$@"; do case "$a" in --sdk_root=*) root=${a#--sdk_root=} ;; esac; done
[[ $n -le ${FAKE_FAILS:-0} ]] && { echo "Error reading Zip content"; exit 1; }
[[ $v == 99.* ]] && { echo "Failed to find package $pkg"; exit 1; }
d=$root/ndk/$v; mkdir -p "$d/toolchains/llvm/prebuilt"
[[ $n -le ${FAKE_PARTIAL:-0} ]] && exit 0
printf 'Pkg.Desc = Android NDK\nPkg.Revision = %s\n' "$v" > "$d/source.properties"
printf '#!/bin/sh\n' > "$d/ndk-build"; chmod +x "$d/ndk-build"
X
chmod +x "$tmp/flutter/bin/flutter" "$tmp/bin/sdkmanager"
export PATH="$tmp/bin:$tmp/flutter/bin:$PATH" FAKE_COUNT="$tmp/count" NDK_PAUSE=0
unset NDK_VERSION FAKE_FAILS FAKE_PARTIAL ANDROID_SDK_ROOT
fails=0
# run <Name> <rc> <Aufrufe sdkmanager> [VAR=Wert ...]
run() {
  name=$1 want_rc=$2 want_calls=$3; shift 3
  rm -f "$FAKE_COUNT" "$tmp/gh_out"
  env ANDROID_HOME="$tmp/sdk" GITHUB_OUTPUT="$tmp/gh_out" "$@" bash "$script" > "$tmp/out" 2>&1; rc=$?
  calls=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0)
  if [[ $rc -eq $want_rc && $calls -eq $want_calls ]]; then echo "OK   $name"; else
    echo "FAIL $name (rc=$rc erwartet $want_rc, Aufrufe $calls erwartet $want_calls)"; sed 's/^/     /' "$tmp/out"; fails=$((fails + 1)); fi
}
v=$(bash "$script" --version)
[[ $v == 27.1.12297006 ]] && echo "OK   Version aus Flutter abgeleitet" || { echo "FAIL Version '$v'"; fails=$((fails + 1)); }
mkdir -p "$tmp/sdk"
run "frisch: ein Versuch, installiert" 0 1
grep -qx 'version=27.1.12297006' "$tmp/gh_out" || { echo "FAIL Version fehlt in GITHUB_OUTPUT"; fails=$((fails + 1)); }
run "vorhanden und vollständig: kein Download" 0 0
rm -rf "$tmp/sdk/ndk"
run "zwei Fehlschläge, dritter Versuch klappt" 0 3 FAKE_FAILS=2
rm -rf "$tmp/sdk/ndk"
run "unvollständiges Paket wird wiederholt" 0 2 FAKE_PARTIAL=1
rm -rf "$tmp/sdk/ndk"
run "drei Fehlschläge: Abbruch" 1 3 FAKE_FAILS=3
grep -q 'FEHLER (NDK): NDK 27.1.12297006 ließ sich nach 3 Versuchen nicht' "$tmp/out" || { echo "FAIL Meldung unklar"; fails=$((fails + 1)); }
[[ -e $tmp/sdk/ndk/27.1.12297006 ]] && { echo "FAIL Reste bleiben liegen"; fails=$((fails + 1)); }
run "falsche Version (Probe): Abbruch nach drei Versuchen" 1 3 NDK_VERSION=99.0.1
grep -q 'FEHLER (NDK): NDK 99.0.1 ließ sich nach 3 Versuchen nicht' "$tmp/out" || { echo "FAIL Meldung Probe unklar"; fails=$((fails + 1)); }
run "ungültige Version: sofort Abbruch" 1 0 'NDK_VERSION=28;rm'
run "ohne SDK: Abbruch" 1 0 ANDROID_HOME="$tmp/fehlt"
[[ $fails -eq 0 ]] && echo "ci_ndk: alle Fälle grün" || { echo "ci_ndk: $fails Fälle rot"; exit 1; }
