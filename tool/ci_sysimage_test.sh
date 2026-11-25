#!/usr/bin/env bash
# Test fuer tool/ci_sysimage.sh mit einer Attrappe fuer sdkmanager (kein Netz): Installation, vorhandenes
# Paket, Wiederholung nach Fehlschlag, unvollstaendigem Paket oder Exit 1, Entfernen halber Pakete, Abbruch mit „Systemimage nicht ladbar“
# nach drei Versuchen, ungueltige API-Stufe, fehlendes SDK.
# Aufruf: bash tool/ci_sysimage_test.sh
set -u
script=$(cd "$(dirname "$0")" && pwd)/ci_sysimage.sh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
# sdkmanager: zaehlt Aufrufe und verhaelt sich wie der echte: Liegt package.xml schon im Paketordner, gilt
# das Paket als installiert und es wird nichts geladen. FAKE_FAILS = Anzahl erster Versuche mit Exit 1, die
# einen halben Paketordner (package.xml ohne system.img) hinterlassen; FAKE_PARTIAL = Anzahl erster Versuche,
# die Exit 0 melden, aber ein unvollstaendiges Paket hinterlassen; FAKE_RC = Anzahl erster Versuche, die ein
# vollstaendiges Paket schreiben, aber mit Exit 1 enden.
cat > "$tmp/bin/sdkmanager" <<'X'
#!/usr/bin/env bash
n=$(( $(cat "$FAKE_COUNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE_COUNT"
pkg=${@: -1}; root=; for a in "$@"; do case "$a" in --sdk_root=*) root=${a#--sdk_root=} ;; esac; done
IFS=';' read -r _ plat tag abi <<< "$pkg"; api=${plat#android-}
d=$root/system-images/$plat/$tag/$abi
[[ -f $d/package.xml ]] && { echo "Paket $pkg bereits installiert"; exit 0; }
mkdir -p "$d"; printf '<package/>' > "$d/package.xml"
if [[ $n -le ${FAKE_FAILS:-0} ]]; then
  echo "Warning: An error occurred during installation: Download interrupted"; exit 1
fi
printf 'AndroidVersion.ApiLevel=%s\nSystemImage.Abi=%s\n' "$api" "$abi" > "$d/source.properties"
[[ $n -le ${FAKE_PARTIAL:-0} ]] && exit 0
printf 'img' > "$d/system.img"
[[ $n -le ${FAKE_RC:-0} ]] && exit 1
exit 0
X
chmod +x "$tmp/bin/sdkmanager"
export PATH="$tmp/bin:$PATH" FAKE_COUNT="$tmp/count" SYSIMAGE_PAUSE=0
unset FAKE_FAILS FAKE_PARTIAL FAKE_RC ANDROID_SDK_ROOT GITHUB_ACTIONS
fails=0
img=$tmp/sdk/system-images/android-36/google_apis/x86_64
# run <Name> <rc> <Aufrufe sdkmanager> <api> [VAR=Wert ...]
run() {
  name=$1 want_rc=$2 want_calls=$3 api=$4; shift 4
  rm -f "$FAKE_COUNT"
  env ANDROID_HOME="$tmp/sdk" "$@" bash "$script" "$api" > "$tmp/out" 2>&1; rc=$?
  calls=$(cat "$FAKE_COUNT" 2>/dev/null || echo 0)
  if [[ $rc -eq $want_rc && $calls -eq $want_calls ]]; then echo "OK   $name"; else
    echo "FAIL $name (rc=$rc erwartet $want_rc, Aufrufe $calls erwartet $want_calls)"; sed 's/^/     /' "$tmp/out"; fails=$((fails + 1)); fi
}
mkdir -p "$tmp/sdk"
run "frisch: ein Versuch, installiert" 0 1 36
[[ -s $img/system.img ]] || { echo "FAIL Systemimage fehlt nach Installation"; fails=$((fails + 1)); }
run "vorhanden und vollständig: kein Download" 0 0 36
rm -rf "$tmp/sdk/system-images"
run "erster Versuch scheitert, zweiter klappt" 0 2 36 FAKE_FAILS=1
grep -q 'Versuch 1 gescheitert' "$tmp/out" && grep -q 'Versuch 2 von 3' "$tmp/out" \
  || { echo "FAIL Wiederholung nicht im Log"; fails=$((fails + 1)); }
rm -rf "$tmp/sdk/system-images"
run "zwei Fehlschläge, dritter Versuch klappt" 0 3 36 FAKE_FAILS=2
rm -rf "$tmp/sdk/system-images"
run "unvollständiges Paket wird wiederholt" 0 2 36 FAKE_PARTIAL=1
rm -rf "$tmp/sdk/system-images"
run "vollständiges Paket, aber Exit 1: wird wiederholt" 0 2 36 FAKE_RC=1
rm -rf "$tmp/sdk/system-images"
run "drei Fehlschläge: Abbruch" 1 3 36 FAKE_FAILS=3
grep -q 'FEHLER (Systemimage): Systemimage nicht ladbar: system-images;android-36;google_apis;x86_64 nach 3 Versuchen' "$tmp/out" \
  || { echo "FAIL Meldung unklar"; fails=$((fails + 1)); }
[[ -e $img ]] && { echo "FAIL Reste bleiben liegen"; fails=$((fails + 1)); }
run "Annotation im Workflow" 1 3 36 FAKE_FAILS=3 GITHUB_ACTIONS=true
grep -q '^::error title=Infrastruktur::Systemimage nicht ladbar' "$tmp/out" || { echo "FAIL Annotation fehlt"; fails=$((fails + 1)); }
run "andere API-Stufe im selben SDK" 0 1 31
[[ -s $tmp/sdk/system-images/android-31/google_apis/x86_64/system.img ]] || { echo "FAIL API 31 fehlt"; fails=$((fails + 1)); }
run "ungültige API-Stufe: sofort Abbruch" 1 0 '36;rm'
run "ohne API-Stufe: sofort Abbruch" 1 0 ''
run "ohne SDK: Abbruch" 1 0 36 ANDROID_HOME="$tmp/fehlt"
[[ $fails -eq 0 ]] && echo "ci_sysimage: alle Fälle grün" || { echo "ci_sysimage: $fails Fälle rot"; exit 1; }
