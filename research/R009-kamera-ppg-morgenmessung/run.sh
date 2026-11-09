#!/bin/bash
# Führt die Analyse aus. Alle Parameter mit Standardwerten: ./run.sh --help (gleichlautend zur README).
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID="$(basename "$PWD")"; ID="${ID%%-*}"

SEED=1
REPS=4000
PART=all
usage() { cat <<HELP
Usage: ./run.sh [--seed N] [--reps N] [--part A|B|C|all]
  --seed N             Zufallsstartwert (Standard: $SEED)
  --reps N             Wiederholungen je Fall in A und B (Standard: $REPS)
  --part A|B|C|all     nur einen Teil rechnen (Standard: $PART)
                       A Fallzahl Bland-Altman, B 7-Tage-Mittel bei Lücken und Kamera-Streuung,
                       C Streuung von ln RMSSD über 60 s gegenüber 300 s
HELP
}
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    --part) PART="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unbekannter Parameter: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -d "$(research_work "$ID")" ] || { echo "Arbeitsordner fehlt, erst ./init.sh" >&2; exit 1; }

OUT="$(research_work "$ID")/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
{
  echo "seed=$SEED reps=$REPS part=$PART"
  echo "commit=$(git rev-parse --short HEAD 2>/dev/null || echo keiner) dirty=$(git status --porcelain . | wc -l | tr -d " ")"
  echo "python=$(python3 -c 'import sys; print(sys.version.split()[0])') host=$(uname -sm)"
} > "$OUT/run.info"

for p in A B C; do
  if [ "$PART" = all ] || [ "$PART" = "$p" ]; then
    start=$(date +%s)
    python3 -E -s "src/part_$p.py" --seed "$SEED" --reps "$REPS" | tee "$OUT/$p.txt"
    echo "Teil $p: $(( $(date +%s) - start )) s" | tee -a "$OUT/run.info"
  fi
done
echo "Fertig: $OUT"
