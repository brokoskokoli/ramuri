#!/bin/sh
# Emulator-Verwaltung für Agenten: tool/emu.sh start <avd> | stop <serial> | list
#   start <avd>   startet den AVD mit -no-audio -no-snapshot-save auf einem freien Port, nimmt einen Lock je AVD
#                 (über alle Worktrees; ist der AVD belegt, wartet das Skript statt einen zweiten Emulator zu starten),
#                 wartet auf sys.boot_completed und gibt als letzte Zeile den Serial (emulator-NNNN) aus.
#                 Der Lock bleibt gehalten, solange der Emulator läuft (/usr/bin/lockf auf der Wrapper-Shell).
#   stop <serial> beendet nur einen mit diesem Skript gestarteten Emulator. Jeder Serial ohne emulator-<Port>
#                 (z. B. ein echtes Gerät) wird abgelehnt; das Skript spricht solche Geräte nie an.
#   list          zeigt laufende Emulatoren (Serial, AVD, ob von diesem Skript gestartet, Wrapper-PID).
# adb wird immer mit -s <emulator-Serial> aufgerufen, außer für die Geräteliste (adb devices); dort werden nur
# Zeilen mit emulator- weiterverwendet.
# Zustand unter $(git rev-parse --git-common-dir)/emu. Zum Testen der Logik ohne Emulator: EMU_EMULATOR und EMU_ADB
# auf Attrappen setzen.
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
EMULATOR=${EMU_EMULATOR:-$sdk/emulator/emulator}
ADB=${EMU_ADB:-$sdk/platform-tools/adb}
BOOT_TIMEOUT=${EMU_BOOT_TIMEOUT:-300}
self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")

gdir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { echo "kein Git-Repository"; exit 1; }
state=$gdir/emu
mkdir -p "$state/avd" "$state/serial" "$state/port" || exit 1

die() { echo "emu.sh: $*" >&2; exit 1; }
valid_serial() { case $1 in emulator-[0-9]*) case ${1#emulator-} in *[!0-9]*) return 1 ;; esac; return 0 ;; *) return 1 ;; esac; }
valid_avd() { case $1 in ""|*[!A-Za-z0-9_.-]*) return 1 ;; esac; return 0; }
alive() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
# Die PID gehört noch zu unserem Prozess (PID-Wiederverwendung): Kommandozeile enthält alle übrigen Argumente.
own() { c=$(ps -o command= -p "$1" 2>/dev/null) || return 1; shift; for a in "$@"; do case " $c " in *" $a "*) ;; *) return 1 ;; esac; done; }

# Wrapper (läuft unter lockf, hält also den AVD-Lock): wählt einen Port, startet den Emulator, schreibt Zustand.
# Aufruf: emu.sh _run <avd> <runfile>
run_wrapper() {
  avd=$1; runfile=$2
  epid=
  cleanup() { [ -n "$port" ] && rm -rf "$state/port/$port"; [ -n "$port" ] && rm -f "$state/serial/emulator-$port"; rm -f "$state/avd/$avd.info"; }
  stop_emulator() { [ -n "$epid" ] && kill -TERM "$epid" 2>/dev/null && wait "$epid" 2>/dev/null; cleanup; exit 143; }
  trap stop_emulator INT TERM
  port=
  p=5554
  while [ $p -le 5584 ]; do
    if mkdir "$state/port/$p" 2>/dev/null || { ! alive "$(cat "$state/port/$p/pid" 2>/dev/null)" && [ -f "$state/port/$p/pid" ] && rm -rf "$state/port/$p" && mkdir "$state/port/$p" 2>/dev/null; }; then
      echo $$ > "$state/port/$p/pid"
      # Port und Folgeport dürfen weder ein bekanntes Gerät noch ein lauschender Socket sein.
      if "$ADB" devices 2>/dev/null | grep -q "^emulator-$p[[:space:]]" || nc -z 127.0.0.1 "$p" 2>/dev/null || nc -z 127.0.0.1 $((p+1)) 2>/dev/null; then
        rm -rf "$state/port/$p"
      else
        port=$p; break
      fi
    fi
    p=$((p+2))
  done
  [ -n "$port" ] || { echo "kein freier Emulator-Port" >&2; echo "FEHLER kein freier Port" > "$runfile"; exit 1; }
  "$EMULATOR" -avd "$avd" -port "$port" -no-audio -no-snapshot-save </dev/null >"$state/avd/$avd.log" 2>&1 &
  epid=$!
  echo "$avd $$ $epid" > "$state/serial/emulator-$port"
  echo "$avd emulator-$port wrapper-pid $$" > "$state/avd/$avd.info"
  echo "emulator-$port $$" > "$runfile"
  wait "$epid"; rc=$?
  cleanup
  exit $rc
}

cmd_start() {
  avd=${1:-}
  valid_avd "$avd" || die "Aufruf: tool/emu.sh start <avd>"
  [ -x "$EMULATOR" ] || die "Emulator nicht gefunden: $EMULATOR"
  "$EMULATOR" -list-avds 2>/dev/null | grep -qx "$avd" || die "AVD '$avd' unbekannt"
  lock=$state/avd/$avd.lock
  runfile=$(mktemp "$state/run.XXXXXX") || exit 1
  : > "$runfile"
  /usr/bin/lockf -t 0 "$lock" true 2>/dev/null
  [ $? -ne 75 ] || echo "wartet auf AVD $avd (belegt: $(cat "$state/avd/$avd.info" 2>/dev/null || echo unbekannt))"
  # Der Wrapper wartet im blockierenden lockf auf den Lock und läuft dann, solange der Emulator läuft.
  /usr/bin/lockf "$lock" sh "$self" _run "$avd" "$runfile" >"$state/avd/$avd.wrapper.log" 2>&1 </dev/null &
  lpid=$!
  abort() { wpid=$(awk '{print $2}' "$runfile" 2>/dev/null); if alive "$wpid"; then kill -TERM "$wpid"; else kill -TERM "$lpid" 2>/dev/null; fi; rm -f "$runfile"; exit 130; }
  trap abort INT TERM
  # Auf Zuteilung warten (Lock frei, Emulator gestartet).
  while [ ! -s "$runfile" ]; do
    alive "$lpid" || { rm -f "$runfile"; cat "$state/avd/$avd.wrapper.log" 2>/dev/null; die "Wrapper beendet, bevor der Emulator lief"; }
    sleep 1
  done
  read -r serial wpid < "$runfile"
  case $serial in emulator-*) ;; *) rm -f "$runfile"; die "Start fehlgeschlagen: $serial" ;; esac
  t=0
  until [ "$("$ADB" -s "$serial" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do
    t=$((t+2)); sleep 2
    alive "$wpid" || { rm -f "$runfile"; die "Emulator $serial endete beim Start (Log: $state/avd/$avd.log)"; }
    [ $t -lt "$BOOT_TIMEOUT" ] || { kill -TERM "$wpid" 2>/dev/null; rm -f "$runfile"; die "Zeitüberschreitung beim Start von $serial"; }
  done
  rm -f "$runfile"
  trap - INT TERM
  echo "$serial"
}

cmd_stop() {
  serial=${1:-}
  valid_serial "$serial" || die "Serial '$serial' abgelehnt: nur emulator-<Port> (nie echte Geräte)"
  info=$state/serial/$serial
  [ -f "$info" ] || die "$serial wurde nicht mit tool/emu.sh gestartet (stop nur für selbst gestartete)"
  read -r avd wpid epid < "$info"
  port=${serial#emulator-}
  alive "$wpid" || { rm -f "$info"; die "$serial: Wrapper läuft nicht mehr (Eintrag entfernt)"; }
  own "$wpid" "_run $avd" || { rm -f "$info"; die "$serial: PID $wpid ist nicht mehr der eigene Wrapper (Eintrag entfernt, nichts beendet)"; }
  kill -TERM "$wpid"
  t=0
  while alive "$wpid" && [ $t -lt 30 ]; do sleep 1; t=$((t+1)); done
  if alive "$wpid"; then
    "$ADB" -s "$serial" emu kill >/dev/null 2>&1
    sleep 3
    alive "$wpid" && {
      own "$epid" "-avd $avd" "-port $port" && kill -KILL "$epid" 2>/dev/null
      own "$wpid" "_run $avd" && kill -KILL "$wpid" 2>/dev/null; }
  fi
  rm -f "$info"
  echo "$serial beendet"
}

cmd_list() {
  "$ADB" devices 2>/dev/null | awk '/^emulator-[0-9]+[ \t]/ {print $1, $2}' | while read -r serial st; do
    if [ -f "$state/serial/$serial" ]; then
      read -r avd wpid epid < "$state/serial/$serial"
      echo "$serial $st avd=$avd selbst-gestartet wrapper-pid=$wpid"
    else
      echo "$serial $st fremd (nicht von emu.sh)"
    fi
  done
}

case ${1:-} in
  start) shift; cmd_start "$@" ;;
  stop) shift; cmd_stop "$@" ;;
  list) cmd_list ;;
  _run) shift; run_wrapper "$@" ;;
  *) echo "Aufruf: tool/emu.sh start <avd> | stop <serial> | list"; exit 2 ;;
esac
