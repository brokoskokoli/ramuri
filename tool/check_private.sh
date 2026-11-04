#!/bin/sh
# Sucht private Daten und Geheimnisse: --staged prüft den Index, sonst alle versionierten Dateien.
# Verbotene Begriffe stehen nur lokal in ~/.config/running-app/forbidden-terms (fehlt in CI).
mode=${1:-}
list() { if [ "$mode" = --staged ]; then git diff --cached --name-only --diff-filter=ACMR; else git ls-files; fi; }
show() { if [ "$mode" = --staged ]; then git show ":$1"; else cat "$1"; fi; }
terms="$HOME/.config/running-app/forbidden-terms"
pat='/Users/[a-z]|/private/tmp/claude|BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{20}|sk-ant-[A-Za-z0-9]|AKIA[0-9A-Z]{16}'
rc=0; tmp=$(mktemp)
list > "$tmp"
while IFS= read -r f; do
  case "$f" in tool/check_private.sh|LICENSE) continue ;; esac
  hit=$(show "$f" | grep -nIE "$pat" | cut -c1-120)
  if [ -f "$terms" ]; then hit="$hit$(show "$f" | grep -nIiEf "$terms" | cut -c1-120)"; fi
  if [ -n "$hit" ]; then echo "check_private: $f: $hit" >&2; rc=1; fi
done < "$tmp"
rm -f "$tmp"; exit $rc
