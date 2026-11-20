#!/bin/sh
# Laeuft im Emulator-Schritt von .github/workflows/e2e.yml (Argument: Ausgabeordner)
# und lokal gegen einen Emulator (ANDROID_SERIAL, Standard emulator-5554).
#
# Stufen (je ein `flutter test` = ein Build und Install):
#   sammlung        integration_test/all_test.dart: alle Ablaeufe ohne Prozessende
#   treadmill-plan  e2e_treadmill_test.dart TREADMILL_PLAN=true: gefuehrte Einheit aus dem Plan auf dem Laufband
#                   in Echtzeit (~5 min Abschnitt); eigene Stufe wegen frischem Speicher ohne Ziel und der Dauer,
#                   im Shard sammlung (der kuerzere), kein Prozessende
#   storage-a/-b    e2e_storage_test.dart PHASE=write, Prozessende, PHASE=read
#   recover-a/-b    e2e_recover_test.dart PHASE=a (Lauf laeuft), Prozessende, PHASE=b
#   m2-flow         e2e_m2_flow_test.dart: Plan, gefuehrte Einheit in Echtzeit (~5,5 min), Anpassung;
#                   eigene Stufe wegen der Dauer, kein Prozessende
#   readiness       e2e_readiness_test.dart: Erholung (WP34); eigene Stufe mit frischer Installation, weil
#                   sie Morgenmessungen (nicht loeschbar), Health-Reihen, Einwilligungen und Warnsignal
#                   setzt und einen leeren Ausgangszustand braucht; kein Prozessende
#   plan-adapt      e2e_plan_adapt_test.dart: Plananpassung an Erholung (adaptiv/fix); eigene Stufe mit frischer
#                   Installation, weil sie Ziel, Plan, Morgenmessungen und Entwicklermodus setzt und mit fester
#                   Uhr laeuft; kein Prozessende
# Prozessende: Der Test gibt "NEED_KILL" (Zeile E2E_...) aus (der Host liest es aus dem Testlog),
# der Host fuehrt `adb shell am force-stop` aus. Die Stufen davor laufen mit
# --no-uninstall, damit Daten und Schluessel bis zur Folgestufe bleiben.
# GPS: Der Emulator bekommt im Hintergrund synthetische Positionen
# (`adb emu geo fix`, ca. 3 m/s nach Norden); Rechte werden per `pm grant` gesetzt.
# Auswahl: E2E_SHARD=sammlung|stufen (so ruft .github/workflows/e2e.yml auf; die Zuordnung
# Shard -> Stufen steht nur hier) oder lokal E2E_STUFEN="recover-a recover-b"; beides zusammen
# oder ein unbekannter Name ist ein Fehler (Exit 1), ebenso ein Lauf ohne eine einzige Stufe.
# Ohne beides laufen alle Stufen. Test: tool/ci_e2e_test.sh.
# Bildschirmfotos: E2E_SHOTS=1 reicht --dart-define=E2E_SHOTS=true an jede Stufe weiter (der Test haelt die Seite
# bei jeder Marke "SHOT <name>" 2,5 s, shot in app/integration_test/support/e2e_support.dart); der Host macht
# waehrend der Stufe je neue Zeile "E2E_<zeit> SHOT <name>" genau ein Foto <Ausgabeordner>/shots/<stufe>-<name>.png.
# Name nur aus [a-z0-9_-], sonst verworfen. Ohne Schalter weder Fotos noch Pause; ein anderer Wert ist ein Fehler.
# Die SHOT-Zeilen bleiben E2E_-Zeilen (nicht im oeffentlichen Log), die Fotos zeigen nur synthetische Testdaten.
# Zeilen der Tests mit Praefix PUB_ (Schluesselnamen, Fehlertext, Schrittmarken "SCHRITT <name>", nie Werte) bleiben im Log
# und stehen bei Rot im Fehlerabschnitt, dazu die letzte Schrittmarke vor dem ersten fehlgeschlagenen Test.
# Bei Rot: Logcat (gefiltert), Bildschirmfoto je Stufe und gefiltertes Testlog (ohne E2E_-Zeilen) in <Ausgabeordner>.
# Der Reporter ist fest "expanded": Unter GitHub Actions waehlt flutter test sonst
# den github-Reporter, der die Ausgabe eines Tests erst an dessen Ende ausgibt
# (NEED_KILL kaeme zu spaet). Zusaetzlich alle 2 s ein Foto, solange die App vorn
# liegt; bei Fehlern haelt der Test die App 20 s offen.
# Zeitlimit je Stufe (grenze_s unten, Herleitung dort): Laeuft flutter test laenger (Wanduhr ab Start der Stufe),
# beendet der Host flutter test samt Kindprozessen, fuehrt `am force-stop` aus und meldet
# "Zeitlimit in Stufe <name> nach <s> s"; die Stufe ist rot (Log, Logcat, Foto wie bei jedem Rot), die folgenden
# Stufen laufen weiter. So endet eine haengende Stufe rot mit Artefakt statt mit dem Abbruch des Jobs.
# E2E_STUFE_LIMIT_S=<s> (positive ganze Zahl) ersetzt die Grenze aller Stufen (lokal, Selbsttest); ein anderer
# Wert ist ein Fehler vor der ersten Stufe.
# Zeitlimit je adb-Aufruf (adb_limit_s unten, Herleitung dort): Haengt ein adb-Aufruf des Hosts (Warteschleife,
# Logcat, Rechte, GPS, Fotos), beendet der Host genau diesen Aufruf, meldet "adb-Zeitlimit nach <s> s: <unterbefehl>"
# auf stderr und macht weiter wie nach einem fehlgeschlagenen Aufruf; so greift auch das Zeitlimit je Stufe.
# E2E_ADB_LIMIT_S=<s> (positive ganze Zahl) ersetzt es (lokal, Selbsttest); ein anderer Wert ist ein Fehler vor
# der ersten Stufe.
set -u
out="${1:-e2e-out}"
mkdir -p "$out"
serial="${ANDROID_SERIAL:-emulator-5554}"
pkg=io.github.brokoskokoli.ramuri
# Zeitlimit je adb-Aufruf in s. Herleitung: ein Vielfaches der ueblichen Dauer von dumpsys, screencap, logcat -d und
# uninstall (wenige Sekunden) und deutlich unter der kleinsten Stufengrenze (300 s, grenze_s unten).
adb_limit_s=60
# Meldungen von a() gehen auf das stderr des Skripts, auch wenn der Aufruf selbst 2>/dev/null hat.
exec 9>&2
# a <unterbefehl> ...: jeder adb-Aufruf mit festem Serial (auf Entwicklerrechnern laufen mehrere Emulatoren) und
# Zeitlimit. Ohne timeout(1) (fehlt auf macOS): adb im Hintergrund, ein Waechter beendet ihn nach adb_limit_s.
# stdout geht wie bisher in Pipe bzw. Umleitung des Aufrufs; der Waechter haelt sie nicht offen.
# Variablennamen apid, wpid, arc: a() laeuft auch im Hauptablauf von stufe() (pid, gpid, rc).
a() {
  adb -s "$serial" "$@" </dev/null &
  apid=$!
  (
    sleep "$adb_limit_s"
    if kill -0 "$apid" 2>/dev/null; then
      echo "adb-Zeitlimit nach $adb_limit_s s: $1" >&9
      beende_baum "$apid"
    fi
  ) </dev/null >/dev/null 2>&1 &
  wpid=$!
  wait "$apid"
  arc=$?
  beende_baum "$wpid"
  wait "$wpid" 2>/dev/null
  return "$arc"
}

# Jede Testdatei muss laufen: in all_test.dart eingebunden oder als Stufe unten (Zeile `stufe ... integration_test/<datei>`).
for f in app/integration_test/e2e_*_test.dart; do
  b=$(basename "$f")
  # Mehrphasen- und Host-Tests laufen nur lokal (app/integration_test/README.md), nicht in der CI.
  case "$b" in e2e_storage_test.dart | e2e_recover_test.dart | e2e_health_real_test.dart | e2e_health_revoke_test.dart) continue ;; esac
  grep -q "^stufe [^ ]* [01] integration_test/$b" "$0" && continue
  grep -q "^import '$b'" app/integration_test/all_test.dart || { echo "FEHLT in all_test.dart und als Stufe: $b"; exit 1; }
done

shard_sammlung="sammlung treadmill-plan"
shard_stufen="storage-a storage-b recover-a recover-b m2-flow readiness plan-adapt"
alle_stufen="$shard_sammlung $shard_stufen"
# Zeitlimit je Stufe in s, fuer die gesamte Laufzeit von flutter test (Build, Install, Tests).
# Herleitung: das Doppelte der laengsten gemessenen Dauer (Zeilen "STUFE ... dauer=") aus sechs gruenen Laeufen
# des Workflows e2e auf main, je API 31 und 36 (Messtabelle in PR #69), aufgerundet auf volle Minuten,
# mindestens 5 min. Gemessene Hoechstwerte: sammlung 733 s, treadmill-plan 376 s, storage-a 319 s,
# storage-b 43 s, recover-a 73 s, recover-b 57 s, m2-flow 101 s, readiness 106 s.
# plan-adapt (neu, noch ohne Messung) wie readiness: 5 min.
# Waechst eine Stufe deutlich, hier neu messen und nachziehen.
grenze_s() {
  case "$1" in
    sammlung) echo 1500 ;;
    treadmill-plan) echo 780 ;;
    storage-a) echo 660 ;;
    storage-b | recover-a | recover-b | m2-flow | readiness | plan-adapt) echo 300 ;;
  esac
}
# Waechter: Jede Zeile `stufe <name> ...` unten muss in einem Shard stehen, sonst liefe sie in der CI nie,
# und ein Zeitlimit haben.
for n in $(grep '^stufe [^ ]* [01] ' "$0" | cut -d' ' -f2); do
  case " $alle_stufen " in *" $n "*) ;; *) echo "Stufe $n steht in keinem Shard"; exit 1 ;; esac
  [ -n "$(grenze_s "$n")" ] || { echo "Stufe $n hat kein Zeitlimit (grenze_s)"; exit 1; }
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

case "${E2E_SHOTS:-}" in
  "") shots_define="" ;;
  1) shots_define="--dart-define=E2E_SHOTS=true" ;;
  *) echo "E2E_SHOTS nur 1 oder leer"; exit 1 ;;
esac

# Leer wie nicht gesetzt (Grenzen aus grenze_s); sonst nur Ziffern und groesser als 0.
case "${E2E_STUFE_LIMIT_S:-}" in
  "") ;;
  *[!0-9]*) echo "E2E_STUFE_LIMIT_S keine positive ganze Zahl"; exit 1 ;;
  *) [ "$E2E_STUFE_LIMIT_S" -gt 0 ] 2>/dev/null || { echo "E2E_STUFE_LIMIT_S keine positive ganze Zahl"; exit 1; } ;;
esac
# Ebenso das Zeitlimit je adb-Aufruf (leer: adb_limit_s oben).
case "${E2E_ADB_LIMIT_S:-}" in
  "") ;;
  *[!0-9]*) echo "E2E_ADB_LIMIT_S keine positive ganze Zahl"; exit 1 ;;
  *) [ "$E2E_ADB_LIMIT_S" -gt 0 ] 2>/dev/null || { echo "E2E_ADB_LIMIT_S keine positive ganze Zahl"; exit 1; }
    adb_limit_s=$E2E_ADB_LIMIT_S ;;
esac

# shot_watch <testlog> <stufe>: je neue vollstaendige Zeile "E2E_<zeit> SHOT <name>" genau ein Foto
# <out>/shots/<stufe>-<name>.png (der Test steht dabei 2,5 s); ungueltiger Name -> kein Foto.
# Laeuft im Hintergrund, bis die Stufe endet.
shot_watch() {
  seen=0
  while :; do
    # Nur Zeilen mit Zeilenende (die letzte kann noch halb geschrieben sein).
    lines=$(wc -l <"$1" 2>/dev/null) || lines=0
    n=$(head -n "$lines" "$1" 2>/dev/null | grep -c 'E2E_[^ ]* SHOT ') || n=0
    if [ "$n" -gt "$seen" ]; then
      # Je Marke ein Wort: der Name, oder "!" fuer einen ungueltigen (dann ohne Leerzeichen im Wort).
      for s in $(head -n "$lines" "$1" | grep 'E2E_[^ ]* SHOT ' | sed -n "$((seen + 1)),${n}p" |
        sed 's/^.*E2E_[^ ]* SHOT //; /^[a-z0-9_-]\{1,\}$/!s/.*/!/'); do
        if [ "$s" = '!' ]; then echo "SHOT-Marke verworfen (Name nicht aus [a-z0-9_-])"; continue; fi
        a exec-out screencap -p >"$out/shots/$2-$s.tmp" 2>/dev/null && mv "$out/shots/$2-$s.tmp" "$out/shots/$2-$s.png"
      done
      seen=$n
    fi
    sleep 0.2
  done
}

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

# baum <pid>: die PID und alle Nachfahren (flutter test startet Tool, adb usw.).
baum() {
  for c in $(pgrep -P "$1" 2>/dev/null); do baum "$c"; done
  echo "$1"
}

# beende_baum <pid>: haelt den Prozessbaum an (keine neuen Kinder mehr), liest ihn erneut und beendet alle.
# Nicht nur die PID der Subshell: verwaiste Kinder (flutter_tester, adb) liefen sonst weiter.
beende_baum() {
  # shellcheck disable=SC2046
  kill -STOP $(baum "$1") 2>/dev/null
  # shellcheck disable=SC2046
  kill -KILL $(baum "$1") 2>/dev/null
}

rc_all=0
ran=0

# stufe <name> <kill:0|1> <flutter-test-Argumente...>
stufe() {
  name="$1"; kill_after="$2"; shift 2
  case " $auswahl " in *" $name "*) ;; *) return 0 ;; esac
  ran=$((ran + 1))
  log="$out/flutter-test-$name.log"
  limit="${E2E_STUFE_LIMIT_S:-$(grenze_s "$name")}"
  t0=$(date +%s)
  a logcat -c
  : >"$log"
  # $shots_define ist leer oder ein Wort ohne Leerzeichen (ungequotet: leer = kein Argument).
  # shellcheck disable=SC2086
  (cd app && flutter test --reporter expanded "$@" $shots_define -d "$serial") >"$log" 2>&1 &
  pid=$!
  spid=""
  if [ -n "$shots_define" ]; then
    mkdir -p "$out/shots"
    shot_watch "$log" "$name" &
    spid=$!
  fi
  grant_until_done &
  gpid=$!
  killed=1
  zeitlimit=0
  while kill -0 "$pid" 2>/dev/null; do
    el=$(($(date +%s) - t0))
    if [ "$el" -ge "$limit" ]; then
      echo "Zeitlimit in Stufe $name nach $el s"
      zeitlimit=1
      beende_baum "$pid"
      a shell am force-stop "$pkg"
      break
    fi
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
  # Samt Kindern (laufender adb-Aufruf und sein Waechter), sonst liefen sie weiter.
  beende_baum "$gpid"
  wait "$gpid" 2>/dev/null
  if [ -n "$spid" ]; then
    beende_baum "$spid"
    wait "$spid" 2>/dev/null
    echo "FOTOS Stufe $name: $(find "$out/shots" -name "$name-*.png" | wc -l | tr -d ' ')"
  fi
  if [ "$kill_after" = 1 ]; then
    # Das Testende nach dem Prozessende ist erwartet; fehlt das Zeichen, ist die Stufe rot.
    if [ "$killed" = 0 ]; then rc=0; else rc=1; echo "kein NEED_KILL in Stufe $name"; fi
  fi
  # Nach dem Zeitlimit immer rot, auch wenn NEED_KILL schon kam.
  [ "$zeitlimit" = 0 ] || rc=1
  echo "STUFE $name rc=$rc dauer=$(($(date +%s) - t0))s"
  # Nur Zeilen ohne "E2E_" (Wertausgaben der Tests) in das oeffentliche Log.
  grep -v 'E2E_' "$log" >"$log.pub"
  # Alle Schrittmarken der Stufe (die letzten Zeilen unten zeigen bei langen Stufen nur das Ende).
  echo "--- Schritte Stufe $name ---"
  grep 'PUB_[^ ]* SCHRITT ' "$log.pub"
  tail -n 40 "$log.pub"
  if [ "$rc" -ne 0 ]; then
    rc_all=1
    # Gefilterter Logcat: nur Flutter-Ausgabe und Abstuerze, kein Systemlog (SEC-0001..0010).
    a logcat -d -s flutter:V AndroidRuntime:E | grep -v 'E2E_' >>"$out/logcat-filtered.txt"
    # Die Fehlermeldung liegt vor den letzten Zeilen: ab der ersten Fehlerzeile
    # (EXCEPTION CAUGHT, Expected, Test failed) ins Log und das ganze Testlog
    # (ohne E2E_-Zeilen) ins Artefakt.
    echo "--- Fehlermeldung Stufe $name ---"
    # PUB_-Zeilen: Zustandsmarker und Testfehlertext ohne Werte (Praefix statt E2E_, siehe e2e_support.dart logPub).
    grep 'PUB_' "$log.pub" | tail -n 20
    # Letzte Schrittmarke (step in e2e_support.dart) vor dem ersten fehlgeschlagenen Test ("[E]"):
    # In der Sammlung laufen danach weitere Tests, deren Marken sonst den Fehlerort verdecken.
    awk '/PUB_[^ ]* SCHRITT / { s = $0 } /\[E\]/ { exit } END { print "letzter Schritt vor dem Fehler: " (s == "" ? "keiner" : s) }' "$log.pub"
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
trap 'beende_baum "$fpid"' EXIT

stufe sammlung 0 integration_test/all_test.dart
stufe treadmill-plan 0 integration_test/e2e_treadmill_test.dart --dart-define=TREADMILL_PLAN=true
stufe storage-a 1 integration_test/e2e_storage_test.dart --no-uninstall --dart-define=PHASE=write --dart-define=MARKER=ci-marker-7f3a
stufe storage-b 0 integration_test/e2e_storage_test.dart --dart-define=PHASE=read --dart-define=MARKER=ci-marker-7f3a
stufe recover-a 1 integration_test/e2e_recover_test.dart --no-uninstall --dart-define=PHASE=a
stufe recover-b 0 integration_test/e2e_recover_test.dart --dart-define=PHASE=b
stufe m2-flow 0 integration_test/e2e_m2_flow_test.dart
stufe readiness 0 integration_test/e2e_readiness_test.dart
stufe plan-adapt 0 integration_test/e2e_plan_adapt_test.dart
[ "$ran" -gt 0 ] || { echo "keine Stufe gelaufen (Auswahl: '$auswahl')"; exit 1; }
exit "$rc_all"
