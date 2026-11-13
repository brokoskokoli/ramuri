#!/usr/bin/env bash
# Test der Versionsrechnung von tool/build_signed.sh (WP30), ohne Build. Aufruf: bash tool/build_signed_test.sh
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
[ $fail -eq 0 ] && echo "ALLE GRÜN" || { echo "ROT"; exit 1; }
