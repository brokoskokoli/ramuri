#!/bin/sh
# Laeuft im Emulator-Schritt von .github/workflows/e2e.yml (Argument: Ausgabeordner)
# und lokal gegen einen Emulator (ANDROID_SERIAL, Standard emulator-5554).
#
# Stufen (je ein `flutter test` = ein Build und Install):
#   sammlung        integration_test/all_test.dart: alle Ablaeufe ohne Prozessende
#   storage-a/-b    e2e_storage_test.dart PHASE=write, Prozessende, PHASE=read
#   recover-a/-b    e2e_recover_test.dart PHASE=a (Lauf laeuft), Prozessende, PHASE=b
# Prozessende: Der Test gibt "NEED_KILL" (Zeile E2E_...) aus (der Host liest es aus dem Testlog),
# der Host fuehrt `adb shell am force-stop` aus. Die Stufen davor laufen mit
# --no-uninstall, damit Daten und Schluessel bis zur Folgestufe bleiben.
# GPS: Der Emulator bekommt im Hintergrund synthetische Positionen
# (`adb emu geo fix`, ca. 3 m/s nach Norden); Rechte werden per `pm grant` gesetzt.
# Lokal einzelne Stufen: E2E_STUFEN="recover-a recover-b".
# Bei Rot: Logcat (gefiltert), Bildschirmfoto je Stufe und gefiltertes Testlog (ohne E2E_-Zeilen) in <Ausgabeordner>.
# Der Reporter ist fest "expanded": Unter GitHub Actions waehlt flutter test sonst
# den github-Reporter, der die Ausgabe eines Tests erst an dessen Ende ausgibt
# (NEED_KILL kaeme zu spaet). Zusaetzlich alle 2 s ein Foto, solange die App vorn
# liegt; bei Fehlern haelt der Test die App 20 s offen.
set -u
out="${1:-e2e-out}"
mkdir -p "$out"
serial="${ANDROID_SERIAL:-emulator-5554}"
pkg=io.github.brokoskokoli.ramuri
# Jeder adb-Aufruf mit festem Serial (auf Entwicklerrechnern laufen mehrere Emulatoren).
a() { adb -s "$serial" "$@"; }

# Jede Testdatei muss laufen: in all_test.dart eingebunden oder als Stufe unten.
for f in app/integration_test/e2e_*_test.dart; do
  b=$(basename "$f")
  case "$b" in e2e_storage_test.dart | e2e_recover_test.dart) continue ;; esac
  grep -q "$b" app/integration_test/all_test.dart || { echo "FEHLT in all_test.dart: $b"; exit 1; }
done

gps_feed() {
  lat=10.0
  while :; do
    lat=$(awk -v l="$lat" 'BEGIN { printf "%.6f", l + 0.00003 }')
    a emu geo fix 20.0 "$lat" >/dev/null 2>&1
    sleep 1
  done
}

# Rechte setzen: Wartebedingung mit Ende. `pm grant` schlaegt fehl, solange die App
# nicht installiert ist; sobald alle Rechte gewaehrt und per dumpsys bestaetigt
# sind, endet die Schleife. flutter test installiert mit `adb install -r`, das
# Laufzeitrechte behaelt; die Stufen mit --no-uninstall behalten sie samt App.
# Die Start-Seite der App prueft nach (run_block_recheck im Lauf-Test).
grant_until_done() {
  while :; do
    for p in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION POST_NOTIFICATIONS ACTIVITY_RECOGNITION BLUETOOTH_SCAN BLUETOOTH_CONNECT; do
      a shell pm grant "$pkg" android.permission.$p >/dev/null 2>&1
    done
    # Ende, sobald das Standortrecht steht (es sperrt den Lauf; POST_NOTIFICATIONS
    # gibt es erst ab API 33, dort schlaegt der Grant auf API 31 immer fehl).
    a shell dumpsys package "$pkg" 2>/dev/null | grep -q 'android.permission.ACCESS_FINE_LOCATION: granted=true' && return 0
    sleep 1
  done
}

rc_all=0

# stufe <name> <kill:0|1> <flutter-test-Argumente...>
stufe() {
  name="$1"; kill_after="$2"; shift 2
  # Lokal einzelne Stufen: E2E_STUFEN="recover-a recover-b" (leer = alle).
  case " ${E2E_STUFEN:-$name} " in *" $name "*) ;; *) return 0 ;; esac
  log="$out/flutter-test-$name.log"
  t0=$(date +%s)
  a logcat -c
  (cd app && flutter test --reporter expanded "$@" -d "$serial") >"$log" 2>&1 &
  pid=$!
  grant_until_done &
  gpid=$!
  killed=1
  while kill -0 "$pid" 2>/dev/null; do
    if a shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "$pkg"; then
      a exec-out screencap -p >"$out/screen.tmp" 2>/dev/null && mv "$out/screen.tmp" "$out/screen-$name.png"
    fi
    if [ "$kill_after" = 1 ] && [ "$killed" = 1 ] && grep -q 'NEED_KILL' "$log"; then
      a shell am force-stop "$pkg"
      killed=0
    fi
    sleep 2
  done
  wait "$pid"
  rc=$?
  kill "$gpid" 2>/dev/null
  if [ "$kill_after" = 1 ]; then
    # Das Testende nach dem Prozessende ist erwartet; fehlt das Zeichen, ist die Stufe rot.
    if [ "$killed" = 0 ]; then rc=0; else rc=1; echo "kein NEED_KILL in Stufe $name"; fi
  fi
  echo "STUFE $name rc=$rc dauer=$(($(date +%s) - t0))s"
  # Nur Zeilen ohne "E2E_" (Wertausgaben der Tests) in das oeffentliche Log.
  grep -v 'E2E_' "$log" >"$log.pub"
  tail -n 40 "$log.pub"
  if [ "$rc" -ne 0 ]; then
    rc_all=1
    # Gefilterter Logcat: nur Flutter-Ausgabe und Abstuerze, kein Systemlog (SEC-0001..0010).
    a logcat -d -s flutter:V AndroidRuntime:E | grep -v 'E2E_' >>"$out/logcat-filtered.txt"
    # Die Fehlermeldung liegt vor den letzten Zeilen: ab der ersten Fehlerzeile
    # (EXCEPTION CAUGHT, Expected, Test failed) ins Log und das ganze Testlog
    # (ohne E2E_-Zeilen) ins Artefakt.
    echo "--- Fehlermeldung Stufe $name ---"
    awk '/EXCEPTION CAUGHT|Test failed|Expected:|TimeoutException/ { f = 1 } f' "$log.pub" | head -n 60
    cp "$log.pub" "$out/test-output-$name.txt"
  else
    rm -f "$out/screen-$name.png"
  fi
  rm -f "$log" "$log.pub"
}

# Sauberer Anfang: keine App und keine Daten aus frueheren Laeufen.
a uninstall "$pkg" >/dev/null 2>&1
gps_feed &
fpid=$!
trap 'kill "$fpid" 2>/dev/null' EXIT

stufe sammlung 0 integration_test/all_test.dart
stufe storage-a 1 integration_test/e2e_storage_test.dart --no-uninstall --dart-define=PHASE=write --dart-define=MARKER=ci-marker-7f3a
stufe storage-b 0 integration_test/e2e_storage_test.dart --dart-define=PHASE=read --dart-define=MARKER=ci-marker-7f3a
stufe recover-a 1 integration_test/e2e_recover_test.dart --no-uninstall --dart-define=PHASE=a
stufe recover-b 0 integration_test/e2e_recover_test.dart --dart-define=PHASE=b
exit "$rc_all"
