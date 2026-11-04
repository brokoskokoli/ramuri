#!/bin/bash
# Fuehrt R005 aus. Alle Parameter: ./run.sh --help (gleichlautend zur README).
set -euo pipefail
cd "$(dirname "$0")"
source src/emu-env.sh
usage() { cat <<HELP
Usage: ./run.sh <schritt> [--api N] [--rep N] [--dur S]
Schritte:
  licenses   Lizenzbaum (Dart, Gradle, native) nach work/R005/licenses
  wal-host   Verschluesseltes WAL am Rechner, mit Kontrollen, nach work/R005/wal-host
  emu-start  Eigenen Emulator (emulator-5600) fuer --api starten und einrichten
  emu-stop   Eigenen Emulator beenden
  gap        Matrix Sperre plus force-idle: own, ffgt, je mit und ohne Wake Lock, dazu Negativkontrolle none und bekannte Luecke
  kill       Kill-Matrix: proc und emu, tx 1, 5, 30, FULL und NORMAL
  swipe      Wischen aus den letzten Apps, own und ffgt
  wal        Verschluesseltes WAL im Emulator, mit Positivkontrolle
  bench      Schreibkosten FULL gegen NORMAL, tx 1, 5, 30
  report     Auswertung aller vorhandenen Laeufe (stdout)
Parameter:
  --api N   API-Stufe des Emulators, 31 oder 36 (Standard: 36)
  --rep N   Wiederholungen je Zelle (Standard: gap 2, kill 10, swipe 2)
  --dur S   Dauer der Sperr- und Idle-Phase in Sekunden bei gap (Standard: 600)
Laeufe mit .done werden uebersprungen. Ausgaben: \$RESEARCH_DATA/work/R005/
HELP
}
STEP="${1:-}"; [ -n "$STEP" ] || { usage >&2; exit 2; }; shift || true
API=36; REP=""; DUR=600
while [ $# -gt 0 ]; do case "$1" in
  --api) API="$2"; shift 2;; --rep) REP="$2"; shift 2;; --dur) DUR="$2"; shift 2;;
  --help) usage; exit 0;; *) echo "Unbekannter Parameter: $1" >&2; usage >&2; exit 2;; esac; done
H="python3 src/harness.py"
[ "$STEP" = "--help" ] && { usage; exit 0; }
mkdir -p "$R005_WORK"; (git rev-parse --short HEAD; flutter --version | head -1; uname -m; sysctl -n hw.ncpu) > "$R005_WORK/run.info" 2>/dev/null || true
case "$STEP" in
  licenses) mkdir -p "$R005_WORK/licenses"; python3 src/licenses.py src/proto "$R005_WORK/licenses";;
  wal-host) mkdir -p "$R005_WORK/wal-host"; (cd src/waltest; dart run bin/waltest.dart "$R005_WORK/wal-host/$(date +%Y%m%d-%H%M%S)");;
  emu-start) $H boot --api "$API";;
  emu-stop)  $H kill-emu;;
  gap)
    for host in own ffgt; do for w in 0 1; do $H gap --api "$API" --host $host --wake $w --dur "$DUR" --rep "${REP:-2}"; done; done
    $H gap --api "$API" --host none --wake 0 --dur "$DUR" --rep 1
    $H gap --api "$API" --host own --wake 0 --dur 120 --rep 1 --tag _pausectl --pause-at 30 --pause-len 30;;
  kill)
    for kind in proc emu; do for sync in FULL NORMAL; do for tx in 1 5 30; do
      $H kill --api "$API" --kind $kind --tx $tx --sync $sync --rep "${REP:-10}"; done; done; done;;
  swipe) for host in own ffgt; do $H swipe --api "$API" --host $host --tx 1 --dur 60 --rep "${REP:-2}"; done;;
  wal)   $H wal --api "$API" --dur 120;;
  bench) $H bench --api "$API" --n 300;;
  report) for k in gap kill swipe wal bench; do echo "== $k"; python3 src/analyze.py $k "$R005_WORK"; done;;
  *) usage >&2; exit 2;;
esac
