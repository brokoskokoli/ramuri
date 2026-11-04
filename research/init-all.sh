#!/bin/bash
# Stellt research/data/ für alle Analysen wieder her, indem es jedes init.sh aufruft.
# Usage: research/init-all.sh   (Parameter werden an jedes init.sh weitergereicht)
set -euo pipefail
cd "$(dirname "$0")"
failed=()
for init in R[0-9][0-9][0-9]-*/init.sh; do
  [ -e "$init" ] || { echo "Keine Analysen mit init.sh gefunden."; exit 0; }
  echo "== ${init%/init.sh}"
  (cd "$(dirname "$init")" && ./init.sh "$@") || failed+=("${init%/init.sh}")
done
if [ ${#failed[@]} -gt 0 ]; then echo "Fehlgeschlagen: ${failed[*]}" >&2; exit 1; fi
echo "Alle Analysen initialisiert."
