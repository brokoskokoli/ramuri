#!/bin/bash
# Stellt alles her, was diese Analyse in research/data/ braucht. Idempotent.
# Usage: ./init.sh [--help]
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID="$(basename "$PWD")"; ID="${ID%%-*}"

if [ "${1:-}" = "--help" ]; then
  cat <<HELP
$ID lädt nichts herunter und nutzt keine Sammlung aus research/input/.
Legt nur den Arbeitsordner \$RESEARCH_DATA/work/$ID/ an (Ausgaben von ./run.sh, < 1 MB je Lauf).
Prüft, dass python3 (>= 3.10) vorhanden ist; gebraucht wird nur die Standardbibliothek.
HELP
  exit 0
fi

python3 -c 'import sys; assert sys.version_info >= (3, 10), sys.version' \
  || { echo "python3 >= 3.10 fehlt" >&2; exit 1; }
mkdir -p "$(research_work "$ID")"
echo "$ID initialisiert (Daten: $RESEARCH_DATA, Arbeitsordner: $(research_work "$ID"))"
