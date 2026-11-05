#!/bin/bash
# Stellt die offenen Stand- und Gehdaten für R007 her. Idempotent. Usage: ./init.sh [--help]
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID=R007
if [ "${1:-}" = "--help" ]; then
  cat <<HELP
Lädt für $ID (zusammen ca. 770 MB, CC BY 4.0, ohne Konto):
  zenodo-1312834/        Samsung Galaxy, Stand, GPGGA (Zenodo 1312834, ~57 MB)
  zenodo-20092798/       454 Stand-Sitzungen à 30 s, FIX-Zeilen (Zenodo 20092798, ~11 MB)
  zenodo-14712684/       GNSSLogger Gehen u. a. (Zenodo 14712684, ~141 MB)
  mendeley-kybmdyrzb3-v1/ OnePlus Nord 2T, Stativ, GNSSLogger (Mendeley, ~565 MB, entpackt nur Logs)
Ziel: \$RESEARCH_DATASETS. Vorher nachsehen: research/DATA.md, research/data/INDEX.md.
HELP
  exit 0
fi
mkdir -p "$RESEARCH_DATASETS" "$(research_work "$ID")"
Z=https://zenodo.org/api/records

# Dateien eines Zenodo-Eintrags laden und gegen die MD5 aus der Zenodo-API prüfen.
zen() { local rec="$1" d="$RESEARCH_DATASETS/zenodo-$1"; mkdir -p "$d"
  [ -f "$d/.done" ] && return 0
  curl -fsSL --max-time 60 "$Z/$rec" -o "$d/record.json"
  python3 -I -c '
import json,sys
for f in json.load(open(sys.argv[1]))["files"]:
    print(f["key"],f["checksum"].split(":")[1],f["links"]["self"],sep="\t")
' "$d/record.json" > "$d/files.tsv"
  while IFS=$'\t' read -r key md5sum url; do
    [ "$(md5 -q "$d/$key" 2>/dev/null || true)" = "$md5sum" ] && continue
    curl -fsSL "$url" -o "$d/$key.part"
    [ "$(md5 -q "$d/$key.part")" = "$md5sum" ] || { echo "Prüfsumme falsch: $key" >&2; exit 1; }
    mv "$d/$key.part" "$d/$key"
  done < "$d/files.tsv"
  touch "$d/.done"; }

zen 1312834
zen 20092798
zen 14712684
research_register datasets/zenodo-1312834 $ID "Samsung Galaxy Stand, GPGGA, Zenodo 1312834 (CC BY 4.0)"
research_register datasets/zenodo-20092798 $ID "454 Stand-Sitzungen à 30 s, Zenodo 20092798 (CC BY 4.0)"
research_register datasets/zenodo-14712684 $ID "GNSSLogger Gehen u. a., Zenodo 14712684 (CC BY 4.0)"

# Entpackt nur Textlogs; nichts daraus wird ausgeführt.
n="$RESEARCH_DATASETS/zenodo-20092798"
[ -d "$n/x" ] || unzip -qo "$n/Raw GNSS Data.zip" -d "$n/x"
g="$RESEARCH_DATASETS/zenodo-14712684"
[ -d "$g/x" ] || unzip -qo "$g/MultiModaldata.zip" '*.txt' '*.nmea' -d "$g/x"

m="$RESEARCH_DATASETS/mendeley-kybmdyrzb3-v1"; mkdir -p "$m"
if [ ! -f "$m/.done" ]; then
  if [ ! -f "$m/data.zip" ]; then
    url="$(curl -s --max-time 30 -o /dev/null -w '%{redirect_url}' https://data.mendeley.com/public-api/zip/kybmdyrzb3/download/1)"
    curl -fsSL "$url" -o "$m/data.zip.part"
    mv "$m/data.zip.part" "$m/data.zip"
  fi
  [ "$(stat -f %z "$m/data.zip")" = "564940929" ] || { echo "Größe von data.zip unerwartet" >&2; exit 1; }
  unzip -qo "$m/data.zip" '*.txt' '*.nmea' -d "$m/x"
  touch "$m/.done"
fi
research_register datasets/mendeley-kybmdyrzb3-v1 $ID "OnePlus Nord 2T, Stativ, GNSSLogger, Mendeley kybmdyrzb3 v1 (CC BY 4.0)"
echo "$ID initialisiert (Daten: $RESEARCH_DATA)"
