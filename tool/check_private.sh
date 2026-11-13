#!/bin/sh
# Sucht private Daten und Geheimnisse: --staged prüft den Index, sonst alle versionierten Dateien.
# --push <rev-list-Argumente> (Pre-Push-Hook) prüft die neuen Commits des Bereichs: Dateinamen, Commit-Nachricht und
# hinzugefügte Zeilen jedes Nicht-Merge-Commits, nicht den Arbeitsbaum. Die Ausgabe nennt nur Commit und Datei,
# nie die Fundstelle (die Logs sind öffentlich); ein nicht auswertbarer Bereich gilt als Treffer.
# Verbotene Begriffe stehen nur lokal in ~/.config/running-app/forbidden-terms (fehlt in CI);
# RUNNING_APP_FORBIDDEN_TERMS überschreibt den Pfad (Tests).
mode=${1:-}
terms="${RUNNING_APP_FORBIDDEN_TERMS:-$HOME/.config/running-app/forbidden-terms}"
pat='/Users/[a-z]|/private/tmp/claude|BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20}|sk-ant-[A-Za-z0-9]|AKIA[0-9A-Z]{16}'
# matches: liest stdin, Exit 0 bei Treffer (Muster oder Termliste), gibt nichts aus.
matches() {
  cat > "$scan"
  grep -qIE "$pat" "$scan" && return 0
  [ -f "$terms" ] && grep -qIiEf "$terms" "$scan" && return 0
  return 1
}
scan=$(mktemp); tmp=$(mktemp); trap 'rm -f "$scan" "$tmp"' EXIT
rc=0
if [ "$mode" = --push ]; then
  shift
  git rev-list --no-merges "$@" > "$tmp" || { echo "check_private: Commit-Bereich nicht auswertbar ($*); abgelehnt." >&2; exit 1; }
  while IFS= read -r c; do
    s=$(git rev-parse --short "$c")
    git log -n 1 --format=%B "$c" | matches && { echo "check_private: Commit $s: Treffer in der Commit-Nachricht" >&2; rc=1; }
    git diff-tree --root -r --no-renames --name-only --no-commit-id -z "$c" | tr '\0' '\n' > "$tmp.f"
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      printf '%s\n' "$f" | matches && { echo "check_private: Commit $s: Treffer im Dateinamen" >&2; rc=1; }
      git diff-tree --root -p -U0 --no-renames --no-commit-id "$c" -- "$f" | grep '^+' | grep -v '^+++ ' | matches \
        && { echo "check_private: Commit $s, Datei $f: Treffer in hinzugefügten Zeilen" >&2; rc=1; }
    done < "$tmp.f"
    rm -f "$tmp.f"
  done < "$tmp"
  exit $rc
fi
list() { if [ "$mode" = --staged ]; then git diff --cached --name-only --diff-filter=ACMR; else git ls-files; fi; }
show() { if [ "$mode" = --staged ]; then git show ":$1"; else cat "$1"; fi; }
list > "$tmp"
while IFS= read -r f; do
  case "$f" in tool/check_private.sh|LICENSE) continue ;; esac
  hit=$(show "$f" | grep -nIE "$pat" | cut -c1-120)
  if [ -f "$terms" ]; then hit="$hit$(show "$f" | grep -nIiEf "$terms" | cut -c1-120)"; fi
  if [ -n "$hit" ]; then echo "check_private: $f: $hit" >&2; rc=1; fi
done < "$tmp"
exit $rc
