#!/bin/sh
# Gate: tool/gate.sh [--changed]. Spec-Prüfung, Datenschutz und, sobald app/ existiert, Flutter.
# --changed lässt Flutter aus, wenn app/ gegenüber main unverändert ist.
cd "$(git rev-parse --show-toplevel)" || exit 1
fail=0
step() { name=$1; shift; log=$(mktemp); if "$@" >"$log" 2>&1; then echo "OK    $name"; else echo "ROT   $name"; tail -30 "$log"; fail=1; fi; rm -f "$log"; }
# Generierte Abschnitte müssen aktuell sein: build darf den Stand von docs/ nicht verändern.
spec() {
  before=$(git ls-files -m -o --exclude-standard docs | xargs -I{} shasum {} | shasum; git ls-files docs | xargs shasum | shasum)
  python3 docs/migration/tools/spec_tool.py build || return 1
  after=$(git ls-files -m -o --exclude-standard docs | xargs -I{} shasum {} | shasum; git ls-files docs | xargs shasum | shasum)
  [ "$before" = "$after" ] || { echo "Generierte Abschnitte waren veraltet; spec_tool build hat sie aktualisiert, bitte committen."; return 1; }
  python3 docs/migration/tools/spec_tool.py check
}
step "spec" spec
step "privat" sh tool/check_private.sh
if [ -f app/pubspec.yaml ]; then
  if [ "${1:-}" = --changed ] && git diff --quiet "$(git merge-base HEAD main 2>/dev/null || echo HEAD)" -- app; then
    echo "SKIP  flutter (app/ unverändert)"
  else
    cd app || exit 1
    step "pub get" flutter pub get
    step "format" dart format --output=none --set-exit-if-changed lib test
    step "analyze" flutter analyze
    step "test" flutter test --coverage
    cd ..
  fi
fi
[ $fail -eq 0 ] && echo "GATE GRÜN" || { echo "GATE ROT"; exit 1; }
