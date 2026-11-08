#!/bin/bash
# Emulator-Messungen R008. Usage: emu.sh <out> <api> <port> <live_s> <apps...>
# Startet genau einen eigenen Emulator (running_app_api<api>, Serial emulator-<port>, -no-audio, -read-only: AVD bleibt unveraendert) und beendet ihn per PID.
# Bricht ab, wenn schon ein anderer Emulator laeuft. Mitschnitt je Phase per "adb emu network capture".
set -uo pipefail
OUT=$1; API=$2; PORT=$3; LIVE_S=$4; shift 4; APPS="$*"
HERE="$(cd "$(dirname "$0")" && pwd)"; SDK=~/Library/Android/sdk; ADB="$SDK/platform-tools/adb -s emulator-$PORT"
BUILD=$(ls -d "$(dirname "$OUT")"/build-*/ | tail -1)
if pgrep -f qemu-system >/dev/null; then echo "Anderer Emulator laeuft (pgrep qemu-system): Abbruch, nichts gestartet" >&2; exit 3; fi
"$SDK/emulator/emulator" -avd "running_app_api$API" -port "$PORT" -no-audio -no-snapshot-save -no-boot-anim -read-only > "$OUT/emulator.log" 2>&1 &
EPID=$!; echo "$EPID" > "$OUT/emulator.pid"; echo "emulator pid=$EPID"
stop_emu() { # sauber ueber die Konsole, dann eigene PIDs (Startprozess und dessen qemu-Kind), kein pkill
  $ADB emu kill >/dev/null 2>&1; sleep 10
  for p in $(pgrep -P "$EPID" 2>/dev/null) "$EPID"; do kill "$p" 2>/dev/null; done; wait "$EPID" 2>/dev/null
  pgrep -f "qemu-system.*-port $PORT|emulator-$PORT|avd running_app_api$API" >/dev/null && echo "WARNUNG: Emulator-Prozess lebt noch" || echo "emulator beendet"
}
trap stop_emu EXIT
echo "serial=emulator-$PORT"; $ADB wait-for-device; until [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; done
$ADB root >/dev/null; sleep 3; $ADB wait-for-device
$ADB shell settings put global window_animation_scale 0; $ADB shell svc power stayon true; $ADB shell input keyevent KEYCODE_WAKEUP
# Netz: Mitschnitt (Konsole "network capture", wie -tcpdump) sieht nur eth0 (Mobilfunk ueber slirp), nicht das
# Netsim-WLAN. Daher WLAN aus, Mobilfunk an (-read-only: Aenderung wird verworfen).
# Flugmodus aus (im AVD running_app_api31 war er an, -read-only verwirft auch das), WLAN aus, Mobilfunk an
$ADB shell cmd connectivity airplane-mode disable; $ADB shell svc wifi disable; $ADB shell svc data enable
sleep 60   # Systemstart abklingen lassen
# Positivkontrolle: Mitschnitt muss eine bekannte DNS-Anfrage sehen, sonst Abbruch (Nullen waeren wertlos)
$ADB emu network capture start "$OUT/positivkontrolle.pcap" >/dev/null; $ADB shell ping -c1 -W3 example.com > "$OUT/positivkontrolle.txt" 2>&1
sleep 2; $ADB emu network capture stop >/dev/null; python3 "$HERE/pcap_hosts.py" "$OUT/positivkontrolle.pcap" > "$OUT/positivkontrolle.hosts.json"
grep -q '"example.com"' "$OUT/positivkontrolle.hosts.json" || { echo "Positivkontrolle Mitschnitt fehlgeschlagen: Abbruch" >&2; exit 4; }
echo "Positivkontrolle Mitschnitt ok"; $ADB shell ip route > "$OUT/ip_route.txt"
pkg() { echo "io.github.r008.r008_$1"; }
cap_start() { $ADB emu network capture start "$OUT/$1.pcap" >/dev/null; }
cap_stop() { $ADB emu network capture stop >/dev/null; python3 "$HERE/pcap_hosts.py" "$OUT/$1.pcap" > "$OUT/$1.hosts.json"; }
cputime() { local p; p=$($ADB shell pidof "$(pkg "$1")" | tr -d '\r'); [ -n "$p" ] && $ADB shell cat /proc/$p/stat | awk '{print $14+$15}' || echo NA; }
launch() { $ADB shell am force-stop "$(pkg "$1")"; $ADB logcat -c; $ADB shell am start -W -n "$(pkg "$1")/.MainActivity" --es route "'$2'" >/dev/null; }  # einfache Anfuehrung fuer die Geraete-Shell: sonst trennt dort "&" die Route ab (Fehler im Lauf emu-20261108-003341)
measure() { # app name route seconds
  local a=$1 n=$2 r=$3 s=$4
  cap_start "$a-$n"; launch "$a" "$r"; sleep 5
  $ADB shell dumpsys gfxinfo "$(pkg "$a")" reset >/dev/null; local c0; c0=$(cputime "$a"); local t0; t0=$(date +%s)
  sleep "$s"
  local c1; c1=$(cputime "$a"); local t1; t1=$(date +%s)
  $ADB shell dumpsys gfxinfo "$(pkg "$a")" > "$OUT/$a-$n.gfxinfo.txt"
  $ADB exec-out screencap -p > "$OUT/$a-$n.png"
  $ADB logcat -d -s flutter:I > "$OUT/$a-$n.logcat.txt"
  cap_stop "$a-$n"
  echo -e "$a\t$n\t$r\t$((t1-t0))\t$c0\t$c1" >> "$OUT/phases.tsv"
}
storage_scan() { # app tag
  local a=$1 d="$OUT/files-$1-$2"; mkdir -p "$d"
  $ADB shell find /data/data/"$(pkg "$a")" /data/user_de/0/"$(pkg "$a")" /sdcard/Android/data/"$(pkg "$a")" -type f -exec ls -l {} + > "$d/ls.txt" 2>/dev/null
  $ADB pull /data/data/"$(pkg "$a")" "$d/" >/dev/null 2>&1
  $ADB pull /sdcard/Android/data/"$(pkg "$a")" "$d/external" >/dev/null 2>&1
  python3 "$HERE/scan_plain.py" "$d" > "$d/scan.txt"; cat "$d/scan.txt"
}
echo -e "app\tphase\troute\tsekunden\tcpu_ticks_start\tcpu_ticks_ende" > "$OUT/phases.tsv"
cap_start "os-idle"; sleep 60; cap_stop "os-idle"   # Grundrauschen des Systems ohne App
for a in $APPS; do
  [ "$a" = base ] && continue
  apk="$BUILD/$a-app-arm64-v8a-release.apk"; $ADB install -r -g "$apk" >/dev/null || { echo "install $a fehlgeschlagen"; continue; }
  $ADB shell pm clear "$(pkg "$a")" >/dev/null
  if [ "$API" = 31 ]; then   # nur Start-Smoke
    measure "$a" smoke "/live?consent=1&page=1" 30
    $ADB shell pidof "$(pkg "$a")" >/dev/null && echo "$a smoke: Prozess laeuft" || echo "$a smoke: Prozess FEHLT"
    $ADB shell am force-stop "$(pkg "$a")"; continue
  fi
  measure "$a" noconsent-live "/live?consent=0&page=1" 45
  measure "$a" noconsent-thumbs "/thumbs?consent=0&n=50&auto=1" 60
  storage_scan "$a" noconsent
  measure "$a" idle "/idle" "$LIVE_S"
  measure "$a" live "/live?consent=1&page=1" "$LIVE_S"
  measure "$a" values "/live?consent=1&page=0" "$LIVE_S"
  measure "$a" thumbs-gen "/thumbs?consent=1&n=50&auto=1" 150
  measure "$a" thumbs-stored "/thumbs?consent=1&n=50&auto=1" 60
  measure "$a" detail "/detail?consent=1" 20
  storage_scan "$a" consent
  if [ "$a" = fm ] || [ "$a" = fmvt ]; then measure "$a" plaincache "/detail?consent=1&plaincache=1" 20; storage_scan "$a" plaincache; fi
  if [ "$a" = ml ]; then $ADB shell pm clear "$(pkg ml)" >/dev/null; measure ml ambient "/detail?consent=1&ambient=1" 20; storage_scan ml ambient; fi
  $ADB shell am force-stop "$(pkg "$a")"   # App nicht im Hintergrund weiterlaufen lassen (im Lauf emu-20261108-003341 liefen fm/fmvt weiter)
done
echo "Emulator-Messung fertig: $OUT"
