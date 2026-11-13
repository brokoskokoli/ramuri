#!/bin/sh
# Laeuft im Emulator-Schritt von .github/workflows/e2e.yml (Argument: Ausgabeordner).
# Startet die Integrationstests und sammelt bei Rot Logcat (gefiltert), ein
# Bildschirmfoto und die Fehlermeldung. Bei einem Fehler haelt der Test die App
# 20 s offen und gibt "E2E_CI_FAIL_HOLD" aus; in dieser Zeit entsteht das Foto.
set -u
out="${1:-e2e-out}"
mkdir -p "$out"
log="$out/flutter-test.log"
adb logcat -c
(cd app && flutter test integration_test/e2e_recalc_test.dart -d emulator-5554) >"$log" 2>&1 &
pid=$!
shot=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$shot" = 0 ] && grep -q 'E2E_CI_FAIL_HOLD' "$log" 2>/dev/null; then
    # Drei Fotos im Abstand von 4 s (die Haltezeit des Tests ist 20 s) und der
    # Vordergrund-Fokus dazu, falls die App nicht mehr oben liegt.
    for n in 1 2 3; do
      adb exec-out screencap -p >"$out/screen$n.png" 2>/dev/null
      echo "foto $n: $(adb shell dumpsys window | grep -m1 mCurrentFocus)"
      sleep 4
    done
    shot=1
  fi
  sleep 1
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
