#!/bin/bash
# Stellt alles her, was R008 in research/data/ braucht. Idempotent: Vorhandenes wird nicht neu geladen.
# Usage: ./init.sh [--help]
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID=R008
FIX="$(research_work "$ID")/fixtures"

if [ "${1:-}" = "--help" ]; then
  cat <<HELP
Laedt fuer $ID wenige Testvorlagen von OpenFreeMap (insgesamt 15 Anfragen, ca. 1,5 MB):
  Stil liberty, TileJSON planet, Sprite (json, png, @2x), 9 Vektorkacheln
  (z14 und z13 je 2x2, z12 eine) ueber dem Tempelhofer Feld in Berlin (oeffentliche Flaeche, synthetische Route)
  -> \$RESEARCH_DATA/work/R008/fixtures/  (manifest.tsv mit URL, Groesse, SHA-256)
OpenFreeMap baut die Kacheln woechentlich neu (Datum im Pfad). Ist der Pfad aus manifest.tsv nicht mehr
erreichbar, wird der aktuelle geladen und im Manifest vermerkt; die Pruefsummen gelten dann nicht mehr.
Kein Massenabruf. Keine Sammlung aus research/input/ noetig.
HELP
  exit 0
fi

mkdir -p "$FIX/tiles"
[ -f "$FIX/.done" ] && [ "$(cat "$FIX/.done")" = v2 ] && { echo "$ID: Testvorlagen vorhanden ($FIX)"; exit 0; }
UA="running-app-research-R008"
get() { [ -s "$2" ] || { curl -fsS -A "$UA" "$1" -o "$2.part" && mv "$2.part" "$2"; sleep 1; }; }
get https://tiles.openfreemap.org/styles/liberty "$FIX/liberty.json"
get https://tiles.openfreemap.org/planet "$FIX/planet.json"
SPRITE=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['sprite'])" "$FIX/liberty.json")
for s in ".json" ".png" "@2x.json" "@2x.png"; do get "$SPRITE$s" "$FIX/sprite$s"; done
TPL=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['tiles'][0])" "$FIX/planet.json")
echo "$TPL" > "$FIX/tile_template.txt"
# Kacheln um das Tempelhofer Feld (52.4731 N, 13.4031 O): z14 2x2, z13 und z12 je eine
for zxy in $(python3 src/tiles_for.py 52.4731 13.4031); do
  z=${zxy%%/*}; rest=${zxy#*/}; x=${rest%%/*}; y=${rest#*/}
  url=${TPL/\{z\}/$z}; url=${url/\{x\}/$x}; url=${url/\{y\}/$y}
  get "$url" "$FIX/tiles/$z-$x-$y.pbf"
done
( cd "$FIX"; for f in liberty.json planet.json sprite* tiles/*; do printf '%s\t%s\t%s\n' "$f" "$(stat -f %z "$f")" "$(shasum -a 256 "$f" | cut -d' ' -f1)"; done ) > "$FIX/manifest.tsv"
echo v2 > "$FIX/.done"
research_register "work/R008/fixtures" "$ID" "OpenFreeMap liberty, TileJSON, Sprite, 9 Kacheln Tempelhofer Feld (OSM ODbL, OpenMapTiles)"
echo "$ID initialisiert (Daten: $FIX)"
