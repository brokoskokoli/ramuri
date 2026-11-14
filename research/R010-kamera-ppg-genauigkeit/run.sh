#!/bin/bash
# Führt R010 aus. Alle Parameter mit Standardwerten: ./run.sh --help (gleichlautend zur README).
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID="$(basename "$PWD")"; ID="${ID%%-*}"

SEED=1
REPS=40
WREPS=20
PART=all
PULS="$HOME/ai/puls/messungen/files"
usage() { cat <<HELP
Usage: ./run.sh [--seed N] [--reps N] [--wreps N] [--part synth|real|pairs|window|all] [--puls DIR]
  --seed N    Zufallsstartwert der Synthese (Standard: $SEED)
  --reps N    synthetische Aufnahmen je Fall (Standard: $REPS)
  --wreps N   synthetische 120-s-Aufnahmen je Fall im Teil window (Standard: $WREPS)
  --part P    nur einen Teil rechnen: synth, real, pairs, window oder all (Standard: $PART)
  --puls DIR  Aufnahmen der Vorgänger-App (Standard: ~/ai/puls/messungen/files)
Ausgaben: \$RESEARCH_DATA/work/$ID/<datum-zeit>/ (run.info, synth.txt, real.txt, pairs.txt, window.txt)
HELP
}
while [ $# -gt 0 ]; do
  case "$1" in
    --seed) SEED="$2"; shift 2 ;;
    --reps) REPS="$2"; shift 2 ;;
    --wreps) WREPS="$2"; shift 2 ;;
    --part) PART="$2"; shift 2 ;;
    --puls) PULS="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "Unbekannter Parameter: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$PART" in synth|real|pairs|window|all) ;; *) echo "Unbekannter Teil: $PART" >&2; exit 2 ;; esac
command -v dart >/dev/null || { echo "Fehlt: dart – erst ./init.sh" >&2; exit 1; }

OUT="$(research_work "$ID")/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
{
  echo "seed=$SEED reps=$REPS wreps=$WREPS part=$PART commit=$(git rev-parse --short HEAD 2>/dev/null || echo keiner) dirty=$(git status --porcelain . ../../app/packages/core/lib/src/ppg | wc -l | tr -d " ")"
  echo "app-ppg=$(git log -1 --format=%h -- ../../app/packages/core/lib/src/ppg 2>/dev/null)"
  dart --version 2>&1
  echo "host=$(uname -mns)"
} > "$OUT/run.info"

nice -n 10 dart run src/r010.dart --seed "$SEED" --reps "$REPS" --wreps "$WREPS" --part "$PART" --puls "$PULS" \
  --pairs "$(research_input morgenmessungen-maintainer)" --out "$OUT" | tail -1
echo "Fertig: $OUT"
