#!/bin/sh
# Laeuft im Emulator-Schritt von .github/workflows/e2e.yml (Argument: Ausgabeordner)
# und lokal gegen einen Emulator (ANDROID_SERIAL, Standard emulator-5554).
#
# Stufen (je ein `flutter test` = ein Build und Install):
#   sammlung        integration_test/all_test.dart: alle Ablaeufe ohne Prozessende
#   storage-a/-b    e2e_storage_test.dart PHASE=write, Prozessende, PHASE=read
#   recover-a/-b    e2e_recover_test.dart PHASE=a (Lauf laeuft), Prozessende, PHASE=b
#   m2-flow         e2e_m2_flow_test.dart: Plan, gefuehrte Einheit in Echtzeit (~5,5 min), Anpassung;
#                   eigene Stufe wegen der Dauer, kein Prozessende
# Prozessende: Der Test gibt "NEED_KILL" (Zeile E2E_...) aus (der Host liest es aus dem Testlog),
# der Host fuehrt `adb shell am force-stop` aus. Die Stufen davor laufen mit
# --no-uninstall, damit Daten und Schluessel bis zur Folgestufe bleiben.
# GPS: Der Emulator bekommt im Hintergrund synthetische Positionen
# (`adb emu geo fix`, ca. 3 m/s nach Norden); Rechte werden per `pm grant` gesetzt.
# Auswahl: E2E_SHARD=sammlung|stufen (so ruft .github/workflows/e2e.yml auf; die Zuordnung
# Shard -> Stufen steht nur hier) oder lokal E2E_STUFEN="recover-a recover-b"; beides zusammen
# oder ein unbekannter Name ist ein Fehler (Exit 1), ebenso ein Lauf ohne eine einzige Stufe.
# Ohne beides laufen alle Stufen. Test: tool/ci_e2e_test.sh.
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

# Jede Testdatei muss laufen: in all_test.dart eingebunden oder als Stufe unten (Zeile `stufe ... integration_test/<datei>`).
for f in app/integration_test/e2e_*_test.dart; do
  b=$(basename "$f")
  # Mehrphasen- und Host-Tests laufen nur lokal (app/integration_test/README.md), nicht in der CI.
  case "$b" in e2e_storage_test.dart | e2e_recover_test.dart | e2e_health_real_test.dart | e2e_health_revoke_test.dart) continue ;; esac
  grep -q "^stufe [^ ]* [01] integration_test/$b" "$0" && continue
  grep -q "^import '$b'" app/integration_test/all_test.dart || { echo "FEHLT in all_test.dart und als Stufe: $b"; exit 1; }
done

shard_sammlung="sammlung"
shard_stufen="storage-a storage-b recover-a recover-b m2-flow"
alle_stufen="$shard_sammlung $shard_stufen"
# Waechter: Jede Zeile `stufe <name> ...` unten muss in einem Shard stehen, sonst liefe sie in der CI nie.
for n in $(grep '^stufe [^ ]* [01] ' "$0" | cut -d' ' -f2); do
  case " $alle_stufen " in *" $n "*) ;; *) echo "Stufe $n steht in keinem Shard"; exit 1 ;; esac
done
if [ -n "${E2E_SHARD:-}" ] && [ -n "${E2E_STUFEN:-}" ]; then echo "E2E_SHARD und E2E_STUFEN zusammen"; exit 1; fi
case "${E2E_SHARD:-}" in
  "") auswahl="${E2E_STUFEN-$alle_stufen}" ;;
  sammlung) auswahl="$shard_sammlung" ;;
  stufen) auswahl="$shard_stufen" ;;
  *) echo "unbekannter Shard: $E2E_SHARD"; exit 1 ;;
esac
for n in $auswahl; do
  case " $alle_stufen " in *" $n "*) ;; *) echo "unbekannte Stufe: $n"; exit 1 ;; esac
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
ran=0

# stufe <name> <kill:0|1> <flutter-test-Argumente...>
stufe() {
  name="$1"; kill_after="$2"; shift 2
  case " $auswahl " in *" $name "*) ;; *) return 0 ;; esac
  ran=$((ran + 1))
  log="$out/flutter-test-$name.log"
  t0=$(date +%s)
  a logcat -c
  (cd app && flutter test --reporter expanded "$@" -d "$serial") >"$log" 2>&1 &
  pid=$!
  grant_until_done &
  gpid=$!
  killed=1
  while kill -0 "$pid" 2>/dev/null; do
    # Ab dem ersten fehlgeschlagenen Test ("[E]" im expanded-Reporter) kein neues Foto mehr:
    # Sonst zeigt es am Ende einen spaeteren Test der Sammlung statt der Fehlerstelle.
    if grep -q '\[E\]' "$log" 2>/dev/null; then :
    elif a shell dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | grep -q "$pkg"; then
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
stufe m2-flow 0 integration_test/e2e_m2_flow_test.dart
[ "$ran" -gt 0 ] || { echo "keine Stufe gelaufen (Auswahl: '$auswahl')"; exit 1; }
exit "$rc_all"
