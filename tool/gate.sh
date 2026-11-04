#!/bin/sh
# Gate: tool/gate.sh [--changed]. Spec-Prüfung, Datenschutz und, sobald app/ existiert, Flutter.
# --changed lässt Flutter nur aus, wenn app/ (getrackt, ungetrackt, committet) gegenüber main unverändert ist.
# Im Zweifel (kein main, Fehler beim Vergleich) wird geprüft statt ausgelassen.
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

# --- Flutter und Dart: je Paket (app und app/packages/*) ---
is_flutter() { grep -Eq '^[[:space:]]+sdk:[[:space:]]*flutter[[:space:]]*$' "$1/pubspec.yaml"; }

# Gibt 0 zurück, wenn app/ gegenüber main verändert sein könnte (oder unklar ist).
app_changed() {
  base=$(git merge-base HEAD main 2>/dev/null) || return 0
  [ -n "$base" ] || return 0
  git diff --quiet "$base" -- app || return 0   # committet, gestaged, ungestaged (Fehler => 1 => geändert)
  [ -z "$(git ls-files -o --exclude-standard -- app)" ] || return 0   # ungetrackte Dateien
  return 1
}

pkg_format() {
  ( cd "$1" || exit 1
    [ -d lib ] || { echo "lib/ fehlt in $1"; exit 1; }
    [ -d test ] || { echo "test/ fehlt in $1"; exit 1; }
    dirs="lib test"; [ -d integration_test ] && dirs="$dirs integration_test"
    dart format --output=none --set-exit-if-changed $dirs )
}
pkg_analyze() {
  ( cd "$1" || exit 1
    if is_flutter .; then flutter analyze; else dart analyze --fatal-infos; fi )
}
pkg_test() {
  ( cd "$1" || exit 1
    [ -d test ] || { echo "test/ fehlt in $1"; exit 1; }
    if is_flutter .; then
      if [ "$1" = app ]; then flutter test --coverage; else flutter test; fi
    else dart test; fi )
}

# Die laufende Flutter-Version muss exakt environment.flutter aus app/pubspec.yaml entsprechen (fail-closed).
flutter_version() {
  want=$(python3 - app/pubspec.yaml <<'PY'
import re, sys
env = False
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.split("#", 1)[0].rstrip()
    if re.match(r"^environment:\s*$", line): env = True; continue
    if env and re.match(r"^\S", line): break
    m = re.match(r"^\s+flutter:\s*['\"]?([^'\"\s]+)['\"]?\s*$", line) if env else None
    if m: print(m.group(1)); break
PY
  )
  [ -n "$want" ] || { echo "environment.flutter fehlt oder ist nicht lesbar in app/pubspec.yaml"; return 1; }
  have=$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["frameworkVersion"])') || return 1
  [ -n "$have" ] || { echo "laufende Flutter-Version nicht lesbar"; return 1; }
  [ "$have" = "$want" ] || { echo "Flutter-Version: laufend $have, verlangt $want"; return 1; }
  echo "Flutter $have"
}

# core bleibt frei von Flutter: kein Import, keine (auch transitive) Abhängigkeit.
# Der Pub-Workspace teilt eine package_config, ein Flutter-Import löst sich dort sonst still auf.
core_flutterfrei() {
  core=app/packages/core
  [ -d "$core" ] || { echo "$core fehlt"; return 1; }
  rc=0
  hits=$(grep -rnE 'package:flutter|dart:ui' "$core" --include='*.dart' --exclude-dir=.dart_tool --exclude-dir=build) \
    && { echo "Flutter-Import in core:"; echo "$hits"; rc=1; }
  deps=$(mktemp)
  ( cd "$core" && dart pub deps --json ) > "$deps" 2>/dev/null || { echo "dart pub deps schlug fehl"; rm -f "$deps"; return 1; }
  python3 - "$deps" <<'PY' || rc=1
import json, sys
d = json.load(open(sys.argv[1]))
pk = {p["name"]: p for p in d["packages"]}
if "core" not in pk: print("core fehlt in pub deps"); sys.exit(1)
seen, todo, bad = set(), ["core"], []
while todo:
    n = todo.pop()
    if n in seen: continue
    seen.add(n)
    for c in pk.get(n, {}).get("dependencies", []):
        todo.append(c)
for n in sorted(seen - {"core"}):
    p = pk.get(n, {})
    if n in ("flutter", "sky_engine", "adapters") or n.startswith("flutter_") or p.get("kind") == "root":
        bad.append(n)
if bad:
    print("core hängt (auch transitiv) ab von:", ", ".join(bad)); sys.exit(1)
PY
  rm -f "$deps"
  return $rc
}

if [ -f app/pubspec.yaml ]; then
  if [ "${1:-}" = --changed ] && ! app_changed; then
    echo "SKIP  flutter (app/ gegenüber main unverändert)"
  else
    step "flutter version" flutter_version
    step "pub get" sh -c 'cd app && flutter pub get'
    step "core flutterfrei" core_flutterfrei
    for p in app app/packages/*; do
      if [ ! -f "$p/pubspec.yaml" ]; then step "$p pubspec" sh -c "echo 'pubspec.yaml fehlt in $p'; exit 1"; continue; fi
      step "$p format" pkg_format "$p"
      step "$p analyze" pkg_analyze "$p"
      step "$p test" pkg_test "$p"
    done
  fi
fi
[ $fail -eq 0 ] && echo "GATE GRÜN" || { echo "GATE ROT"; exit 1; }
