#!/bin/bash
# Führt R007 aus: normieren, Harness, Auswertung. Parameter: ./run.sh --help (gleichlautend zur README).
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID=R007
SEED=42; RUNS=200; SPEED=3; TOTAL=1800; STOP=60; STOPS=3; BURN=120; TAG=""
usage() { cat <<HELP
Usage: ./run.sh [--seed N] [--runs N] [--run-speed V] [--total-s N] [--stop-s N] [--stops N] [--burn-in-s N] [--tag T]
  --seed N       Zufallsstartwert (Standard: $SEED)
  --runs N       simulierte Läufe je Quelle (Standard: $RUNS)
  --run-speed V  Lauftempo in m/s (Standard: $SPEED)
  --total-s N    Laufdauer in s (Standard: $TOTAL)
  --stop-s N     Dauer eines Stopps in s (Standard: $STOP)
  --stops N      Zahl der Stopps (Standard: $STOPS)
  --burn-in-s N  Einlaufzeit je Stand-Sitzung, die nicht gezogen wird (Standard: $BURN)
  --tag T        Zusatz im Namen des Laufordners (Standard: leer)
HELP
}
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --run-speed) SPEED="$2"; shift 2 ;;
    --total-s) TOTAL="$2"; shift 2 ;;
    --stop-s) STOP="$2"; shift 2 ;;
    --stops) STOPS="$2"; shift 2 ;;
    --burn-in-s) BURN="$2"; shift 2 ;;
    --tag) TAG="-$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unbekannter Parameter: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -f "$RESEARCH_DATASETS/mendeley-kybmdyrzb3-v1/.done" ] || { echo "Daten fehlen: erst ./init.sh" >&2; exit 1; }
OUT="$(research_work "$ID")/$(date +%Y%m%d-%H%M%S)$TAG"
mkdir -p "$OUT"
ROOT="$(git rev-parse --show-toplevel)"
echo "seed=$SEED runs=$RUNS speed=$SPEED total=$TOTAL stop=$STOP stops=$STOPS burn=$BURN commit=$(git rev-parse --short HEAD) dirty=$(git status --porcelain . | wc -l | tr -d " ") $(dart --version)" > "$OUT/run.info"
# core wird nur gelesen; der Paketpfad ersetzt ein pubspec, weil core zum Workspace von app/ gehört.
python3 -I -c "
import json,pathlib,sys
r=pathlib.Path(sys.argv[1]).resolve()
print(json.dumps({'configVersion':2,'packages':[{'name':'core','rootUri':r.as_uri(),'packageUri':'lib/','languageVersion':'3.10'}]}))" "$ROOT/app/packages/core" > "$OUT/package_config.json"
nice -n 10 python3 -I src/normalize.py "$RESEARCH_DATASETS" "$OUT" "$SEED"
nice -n 10 dart compile exe --packages="$OUT/package_config.json" src/harness.dart -o "$OUT/harness" | tail -1
nice -n 10 "$OUT/harness" --norm "$OUT/norm" --out "$OUT" --seed "$SEED" --runs "$RUNS" --run-speed "$SPEED" --total-s "$TOTAL" --stop-s "$STOP" --stops "$STOPS" --burn-in-s "$BURN" > "$OUT/harness.log"
nice -n 10 python3 -I src/analyse.py "$OUT" "$SPEED" "$TOTAL" "$STOP" "$STOPS" "$SEED" | tee "$OUT/report.txt"
echo "Fertig: $OUT"
