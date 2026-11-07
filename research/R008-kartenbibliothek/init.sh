#!/bin/bash
# Stellt alles her, was diese Analyse in research/data/ braucht. Idempotent: Vorhandenes wird nicht neu geladen.
# Usage: ./init.sh [--help]
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID="$(basename "$PWD")"; ID="${ID%%-*}"

if [ "${1:-}" = "--help" ]; then
  cat <<HELP
Lädt bzw. erzeugt für $ID:
  <Modell X>   -> \$RESEARCH_MODELS/<name>/     (~<GB>)
  <Datensatz>  -> \$RESEARCH_DATASETS/<name>/   (~<GB>)
Prüft die benötigten Sammlungen in research/input/ (ändert dort nichts).
Vorher nachsehen, was schon da ist: research/DATA.md, research/data/INDEX.md.
HELP
  exit 0
fi

mkdir -p "$RESEARCH_MODELS" "$RESEARCH_DATASETS" "$(research_work "$ID")"

# Beispiel für einen geteilten, idempotenten Download mit Prüfsumme:
# fetch() { local url="$1" dest="$2" sha="$3"
#   [ -f "$dest.done" ] && return 0
#   mkdir -p "$(dirname "$dest")"; curl -fL "$url" -o "$dest.part"
#   echo "$sha  $dest.part" | shasum -a 256 -c - && mv "$dest.part" "$dest" && touch "$dest.done"; }
# fetch "<url>" "$RESEARCH_MODELS/<name>/<datei>" "<sha256>"
# research_register "models/<name>" "$ID" "<Modell X>, Version <…>"   # Eintrag in data/INDEX.md

# Pflicht-Eingaben prüfen:
# input="$(research_input <sammlung>)"
# [ -n "$(ls "$input"/*.wav 2>/dev/null)" ] || { echo "Fehlt: WAV-Dateien in $input (siehe research/input/README.md)" >&2; exit 1; }

echo "$ID initialisiert (Daten: $RESEARCH_DATA)"
