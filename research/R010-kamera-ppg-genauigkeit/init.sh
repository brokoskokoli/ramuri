#!/bin/bash
# Prüft, was R010 braucht. Lädt nichts herunter und ändert keine Eingaben. Idempotent.
# Usage: ./init.sh [--help]
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID="$(basename "$PWD")"; ID="${ID%%-*}"
PULS="${PULS_DIR:-$HOME/ai/puls/messungen/files}"

if [ "${1:-}" = "--help" ]; then
  cat <<HELP
R010 lädt nichts. init.sh prüft nur:
  - Dart SDK (dart --version), App-Code unter app/packages/core/lib/src/ppg/ (aus dem Repository)
  - Aufnahmen der Vorgänger-App in \$PULS_DIR (Standard ~/ai/puls/messungen/files, nur lesen, K70)
  - Sammlung research/input/morgenmessungen-maintainer/ (nur lesen, darf leer sein)
Legt den Arbeitsordner \$RESEARCH_DATA/work/$ID an (Größe der Läufe < 1 MB).
HELP
  exit 0
fi

command -v dart >/dev/null || { echo "Fehlt: dart (Flutter/Dart SDK)" >&2; exit 1; }
[ -f ../../app/packages/core/lib/src/ppg/ppg_analyzer.dart ] || { echo "Fehlt: App-Code app/packages/core/lib/src/ppg/" >&2; exit 1; }
mkdir -p "$(research_work "$ID")"
n=$( (ls "$PULS"/*_frames.csv 2>/dev/null || true) | wc -l | tr -d ' ')
echo "Aufnahmen der Vorgänger-App: $n in $PULS (Teil real; ohne sie wird der Teil übersprungen)"
input="$(research_input morgenmessungen-maintainer)"
m=$( (ls "$input"/*.csv 2>/dev/null || true) | wc -l | tr -d ' ')
echo "Messpaar-Dateien: $m in $input (Teil pairs; darf leer sein)"
echo "$ID initialisiert (Daten: $RESEARCH_DATA)"
