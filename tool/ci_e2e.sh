#!/bin/sh
# Laeuft im Emulator-Schritt von .github/workflows/e2e.yml (Argument: Ausgabeordner).
# Startet die Integrationstests und sammelt bei Rot Logcat (gefiltert), ein
# Bildschirmfoto und die Fehlermeldung. Bei einem Fehler haelt der Test die App
# 20 s offen und gibt "E2E_CI_FAIL_HOLD" aus; das letzte Foto mit App im Vordergrund bleibt liegen.
set -u
out="${1:-e2e-out}"
mkdir -p "$out"
log="$out/flutter-test.log"
adb logcat -c
(cd app && flutter test integration_test/e2e_recalc_test.dart -d emulator-5554) >"$log" 2>&1 &
pid=$!
# Die Testausgabe erreicht den Host erst am Testende (die App ist dann schon
# geschlossen). Darum alle 2 s ein Foto, solange die App im Vordergrund ist; das
# letzte bleibt liegen (der Test haelt die App bei Rot 20 s offen).
pkg=io.github.brokoskokoli.ramuri
while kill -0 "$pid" 2>/dev/null; do
  if adb shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "$pkg"; then
    adb exec-out screencap -p >"$out/screen.tmp" 2>/dev/null && mv "$out/screen.tmp" "$out/screen-last.png"
  fi
  sleep 2
done
wait "$pid"
rc=$?
tail -n 40 "$log"
if [ "$rc" -ne 0 ]; then
  # Gefilterter Logcat: nur Flutter-Ausgabe (Tag "flutter") und Abstuerze
  # (AndroidRuntime), kein Systemlog (SEC-0001..0010). Die Flutter-Zeilen mit
  # "E2E_" (Wertausgaben der Tests) bleiben draussen.
  adb logcat -d -s flutter:V AndroidRuntime:E | grep -v 'E2E_' >"$out/logcat-filtered.txt"
  # Nur Testname und Fehlermeldung, keine E2E_-Wertzeilen.
  grep -E 'The test description was|TestFailure|Expected:|Actual:|Which:|tests passed|Some tests failed|Exception:' "$log" | grep -v 'E2E_' >"$out/test-failures.txt"
fi
rm -f "$log"
exit "$rc"
