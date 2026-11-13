#!/bin/sh
# Laeuft im Emulator-Schritt von .github/workflows/e2e.yml (Argument: Ausgabeordner).
# Startet die Integrationstests und sammelt bei Rot Logcat (gefiltert) und Bildschirmfotos.
set -u
out="${1:-e2e-out}"
mkdir -p "$out"
adb logcat -c
cd app || exit 1
flutter test integration_test/e2e_recalc_test.dart -d emulator-5554 >"../$out/flutter-test.log" 2>&1
rc=$?
cd ..
tail -n 40 "$out/flutter-test.log"
if [ "$rc" -ne 0 ]; then
  # Gefilterter Logcat: nur Flutter-Ausgabe (print der Tests, Tag "flutter") und
  # Abstuerze (AndroidRuntime). Kein ungefilterter Systemlog, weil dieser
  # Geraete-/Fremddaten enthalten kann (SEC-0001..0010: keine Gesundheitswerte).
  adb logcat -d -s flutter:V AndroidRuntime:E >"$out/logcat-filtered.txt" 2>&1
  adb exec-out screencap -p >"$out/screen.png" 2>/dev/null
  # flutter-test.log wird nicht hochgeladen (kann Pfade/Details enthalten); nur Fehlerzeilen:
  grep -n "Error\|Exception\|FAILED\|Some tests failed\|E2E_" "$out/flutter-test.log" >"$out/test-failures.txt" || true
fi
rm -f "$out/flutter-test.log"
exit "$rc"
