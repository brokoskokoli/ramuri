#!/usr/bin/env bash
# Test der Versionsrechnung von tool/build_signed.sh (WP30, Tags und Nightly), ohne Build. Aufruf: bash tool/build_signed_test.sh
set -u
cd "$(dirname "$0")/.." || exit 1
fail=0
ok()   { echo "ok    $1"; }
nok()  { echo "FAIL  $1"; fail=1; }
code() { ./tool/build_signed.sh --print-version "$1" 2>/dev/null | awk '{print $2}'; }

# Erwartete Paare (Name, Code)
check() { out=$(./tool/build_signed.sh --print-version "$1" 2>&1) && [ "$out" = "$2" ] && ok "$1 -> $2" || nok "$1: erwartet '$2', erhalten '$out'"; }
check v0.1.0-rc1 "0.1.0-rc1 10001"
check v0.1.0 "0.1.0 10099"
check v0.1.0-rc98 "0.1.0-rc98 10098"
check v1.2.3 "1.2.3 1020399"
check v0.99.99 "0.99.99 999999"
check v2000.0.0 "2000.0.0 2000000099"

for bad in v0.1.0-rc99 v0.1.0-rc0 v0.1.0-rc01 v1.2 1.2.3 v1.100.0 v1.0.100 v01.2.3 v1.02.3 v1.2.3-rc v1.2.3-beta v1.2.3-rc1x v2001.0.0 ""; do
  if ./tool/build_signed.sh --print-version "$bad" >/dev/null 2>&1; then nok "'$bad' wurde nicht abgelehnt"; else ok "'$bad' abgelehnt"; fi
done

# Jede Version liegt über allen ihren RCs und unter dem nächsten RC der Folgeversion.
for v in v0.1.0 v1.2.3 v0.99.99 v3.0.0; do
  vc=$(code "$v"); max=0
  for n in 1 2 50 98; do c=$(code "$v-rc$n"); [ "$c" -gt "$max" ] && max=$c; done
  [ "$vc" -gt "$max" ] && ok "$v ($vc) > alle RCs ($max)" || nok "$v ($vc) nicht über allen RCs ($max)"
done
prev=0
for v in v0.1.0-rc1 v0.1.0-rc98 v0.1.0 v0.1.1-rc1 v0.1.1 v0.2.0-rc1 v0.99.99 v1.0.0-rc1 v1.0.0; do
  c=$(code "$v"); [ "$c" -gt "$prev" ] && ok "$v ($c) > $prev" || nok "$v ($c) nicht über $prev"; prev=$c
done
# Unbekannte Optionen und überzählige Argumente werden abgelehnt.
for args in "--foo" "--nightly --foo" "--nightly v0.1.0" "--print-version --foo" "--print-version --nightly --foo" "--print-version --nightly v0.1.0" "--print-version"; do
  # shellcheck disable=SC2086 # Wortzerlegung gewollt
  if ./tool/build_signed.sh $args >/dev/null 2>&1; then nok "'$args' wurde nicht abgelehnt"; else ok "'$args' abgelehnt"; fi
done

# --- Nightly: Version aus einem temporären Git-Repo mit einer Kopie des Skripts ---
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ramuri-nightly-test.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT
g() { git -C "$tmp/r" -c user.name=Test -c user.email=test@example.invalid -c commit.gpgsign=false -c tag.gpgsign=false "$@"; }
# commit <Datum mit Zone>: leerer Commit mit fester Autor- und Commit-Zeit
commit() { GIT_AUTHOR_DATE=$1 GIT_COMMITTER_DATE=$1 g commit -q --allow-empty -m "c $1"; }
# nightly [Verzeichnis]: stdout der Nightly-Version, stderr landet getrennt in $tmp/err.
nightly() { (cd "${1:-$tmp/r}" && ./tool/build_signed.sh --print-version --nightly 2>"$tmp/err"); }
expect_nightly() { # <beschreibung> <erwartete Ausgabe> [TZ]; erwartet außerdem leeres stderr
  out=$(if [ -n "${3:-}" ]; then TZ=$3 nightly; else nightly; fi) && [ "$out" = "$2" ] && ok "Nightly $1 -> $2" || nok "Nightly $1: erwartet '$2', erhalten '$out'"
  [ ! -s "$tmp/err" ] && ok "Nightly $1: stderr leer" || nok "Nightly $1: stderr nicht leer: '$(cat "$tmp/err")'"
}
sha7() { g rev-parse HEAD | cut -c1-7; }
mkdir -p "$tmp/r/tool" && git init -q "$tmp/r" && cp tool/build_signed.sh "$tmp/r/tool/" || exit 1

# Ohne Commit: Fehler statt Version.
if nightly >/dev/null; then nok "Nightly ohne Commit nicht abgelehnt"; else ok "Nightly ohne Commit abgelehnt"; fi

# Ohne passenden Tag (nur nightly und foo): Basis 0.0.0, Code 1.
commit "2026-11-10T12:00:00+00:00"
g tag nightly; g tag foo
# stdout unverändert, Exit-Code 0, genau eine Warnzeile auf stderr.
exp0="0.0.0-nightly.20261110+$(sha7) 1"
out=$(nightly) && [ "$out" = "$exp0" ] && ok "Nightly ohne passenden Tag -> $exp0" || nok "Nightly ohne passenden Tag: erwartet '$exp0', erhalten '$out'"
err=$(cat "$tmp/err")
if [[ $err == WARNUNG:* && $(wc -l <"$tmp/err") -eq 1 && $err == *"0.0.0"* && $err == *"versionCode 1"* ]]; then
  ok "Nightly ohne passenden Tag: eine Zeile WARNUNG auf stderr"
else
  nok "Nightly ohne passenden Tag: erwartet eine Zeile 'WARNUNG: …' auf stderr, erhalten '$err'"
fi

# Tag v0.1.0-rc1 und ein Commit danach (23:30 UTC am 18.11., mit Zone +14:00 aufgezeichnet).
# Ein näherer Tag, den version_aus_tag nicht annimmt (v1.2), zählt nicht.
commit "2026-11-11T12:00:00+00:00"
g tag v0.1.0-rc1
commit "2026-11-19T13:30:00+14:00"
g tag v1.2
exp="0.1.0-rc1-nightly.20261118+$(sha7) 10001"
expect_nightly "nach v0.1.0-rc1" "$exp"
expect_nightly "TZ=Pacific/Kiritimati" "$exp" Pacific/Kiritimati
expect_nightly "TZ=America/Los_Angeles" "$exp" America/Los_Angeles

# Flacher Klon desselben Stands (file://, sonst ignoriert Git --depth bei lokalen Pfaden): Nightly abgelehnt, stdout
# leer; der Tag-Aufruf geht dort weiter.
git clone -q --depth 1 "file://$tmp/r" "$tmp/f" && mkdir -p "$tmp/f/tool" && cp tool/build_signed.sh "$tmp/f/tool/" || exit 1
if [ "$(git -C "$tmp/f" rev-parse --is-shallow-repository)" != true ]; then
  nok "Testaufbau: Klon in $tmp/f ist nicht flach"
elif out=$(nightly "$tmp/f"); then
  nok "Nightly flacher Klon nicht abgelehnt (Ausgabe '$out')"
elif [ -n "$out" ]; then
  nok "Nightly flacher Klon: stdout nicht leer: '$out'"
elif ! grep -q 'Flacher Git-Klon' "$tmp/err"; then
  nok "Nightly flacher Klon: stderr ohne 'Flacher Git-Klon': '$(cat "$tmp/err")'"
else
  ok "Nightly flacher Klon abgelehnt"
fi
out=$(cd "$tmp/f" && ./tool/build_signed.sh --print-version v1.2.3 2>&1) && [ "$out" = "1.2.3 1020399" ] \
  && ok "flacher Klon: v1.2.3 -> 1.2.3 1020399" || nok "flacher Klon: v1.2.3: erwartet '1.2.3 1020399', erhalten '$out'"

# Ein Tag, der nicht Vorfahre von HEAD ist, zählt nicht.
main=$(g rev-parse HEAD)
g checkout -q --detach
commit "2026-11-12T12:00:00+00:00"
g tag v5.0.0
g checkout -q "$main"
expect_nightly "Tag v5.0.0 auf Nebenzweig" "$exp"

# Tag v1.2.3 und ein Commit danach: Code 1020399.
g tag v1.2.3
commit "2026-11-20T00:00:00+00:00"
expect_nightly "nach v1.2.3" "1.2.3-nightly.20261120+$(sha7) 1020399"

[ $fail -eq 0 ] && echo "ALLE GRÜN" || { echo "ROT"; exit 1; }
