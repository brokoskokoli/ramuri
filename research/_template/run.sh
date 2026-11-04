#!/bin/bash
# Führt die Analyse aus. Alle Parameter mit Standardwerten: ./run.sh --help (gleichlautend zur README).
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID="$(basename "$PWD")"; ID="${ID%%-*}"

SEED=42
usage() { cat <<HELP
Usage: ./run.sh [--seed N]
  --seed N   Zufallsstartwert (Standard: $SEED)
HELP
}
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unbekannter Parameter: $1" >&2; usage >&2; exit 2 ;;
  esac
done

OUT="$(research_work "$ID")/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
echo "seed=$SEED commit=$(git rev-parse --short HEAD 2>/dev/null || echo keiner) dirty=$(git status --porcelain . | wc -l | tr -d " ")" > "$OUT/run.info"

# <eigentliche Analyse, z. B.: python3 src/analyse.py --seed "$SEED" --out "$OUT">

echo "Fertig: $OUT"
