#!/bin/bash
# Gemeinsame Pfade und Hilfsfunktionen für alle Research-Skripte (siehe research/CLAUDE.md → Daten).
# Einbinden mit: source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
# Zeigt auch aus einem Worktree heraus auf den Haupt-Checkout, denn nur dort liegen data/ und die Dateien in input/.

RESEARCH_MAIN="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
export RESEARCH_MAIN
export RESEARCH_DATA="${RESEARCH_DATA:-$RESEARCH_MAIN/research/data}"
export RESEARCH_INPUT="$RESEARCH_MAIN/research/input"
export RESEARCH_MODELS="$RESEARCH_DATA/models"
export RESEARCH_DATASETS="$RESEARCH_DATA/datasets"

# Arbeitsordner einer Analyse für Zwischen- und Laufausgaben, z. B. research_work R001
research_work() { echo "$RESEARCH_DATA/work/$1"; }

# Nicht wiederherstellbare Sammlung (nur lesen), z. B. research_input stimme-maintainer-2026-10
research_input() { echo "$RESEARCH_INPUT/$1"; }

# Trägt einen hergestellten Eintrag in data/INDEX.md ein (ersetzt einen alten Eintrag mit demselben Pfad).
# Usage: research_register <pfad relativ zu data/> <hergestellt von, z. B. R001> <beschreibung inkl. Version>
research_register() {
  local rel="$1" by="$2" desc="$3" index="$RESEARCH_DATA/INDEX.md" size tmp
  size="$(du -sh "$RESEARCH_DATA/$rel" 2>/dev/null | cut -f1)"
  mkdir -p "$RESEARCH_DATA"
  if [ ! -f "$index" ]; then
    cat > "$index" <<HEAD
# Inhalt von research/data/ (automatisch, nicht in Git)

Ist-Stand, gepflegt von den init.sh der Analysen über research_register. Katalog dessen, was hier liegen kann: research/DATA.md.

| Pfad | Beschreibung | Größe | Hergestellt von | Datum |
| --- | --- | --- | --- | --- |
HEAD
  fi
  tmp="$(mktemp "$index.XXXX")"
  grep -vF "| \`$rel\` |" "$index" > "$tmp" || true
  printf '| `%s` | %s | %s | %s | %s |\n' "$rel" "$desc" "${size:-?}" "$by" "$(date +%Y-%m-%d)" >> "$tmp"
  mv "$tmp" "$index"
}
