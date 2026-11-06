#!/bin/sh
# Gate: tool/gate.sh [--changed]. Spec-Prüfung, Datenschutz und, sobald app/ existiert, Flutter.
# --changed lässt Flutter nur aus, wenn app/, tool/gate.sh und die von Tests gelesenen Dokumente (getrackt, ungetrackt,
# committet) gegenüber main unverändert sind; auf main gegenüber dem Stand vor dem letzten Commit.
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

# Pfade, die Flutter betreffen: app/, tool/gate.sh und Dokumente, die Tests lesen (z. B. docs/model-parameters.md).
watched_paths() {
  echo app tool/gate.sh
  grep -rhoE "docs/[A-Za-z0-9_./-]+\.md" app --include='*_test.dart' 2>/dev/null | sort -u
}

# Gibt 0 zurück, wenn die überwachten Pfade gegenüber main verändert sein könnten (oder unklar ist).
# Auf main selbst ist die Basis der erste Elternteil von HEAD, also der Stand vor dem letzten Commit.
app_changed() {
  if [ "$(git symbolic-ref -q --short HEAD)" = main ]; then
    base=$(git rev-parse -q --verify HEAD^1) || return 0
  else
    base=$(git merge-base HEAD main 2>/dev/null) || return 0
  fi
  [ -n "$base" ] || return 0
  paths=$(watched_paths)
  # shellcheck disable=SC2086
  git diff --quiet "$base" -- $paths || return 0   # committet, gestaged, ungestaged (Fehler => 1 => geändert)
  # shellcheck disable=SC2086
  [ -z "$(git ls-files -o --exclude-standard -- $paths)" ] || return 0   # ungetrackte Dateien
  return 1
}

# Verzeichnisse, die Format und Analyse prüfen (im Paketverzeichnis aufrufen): lib, test und, falls vorhanden, integration_test.
pkg_dirs() { dirs="lib test"; [ -d integration_test ] && dirs="$dirs integration_test"; return 0; }
pkg_format() {
  ( cd "$1" || exit 1
    [ -d lib ] || { echo "lib/ fehlt in $1"; exit 1; }
    [ -d test ] || { echo "test/ fehlt in $1"; exit 1; }
    pkg_dirs
    dart format --output=none --set-exit-if-changed $dirs )
}
pkg_analyze() {
  ( cd "$1" || exit 1
    pkg_dirs
    if is_flutter .; then flutter analyze $dirs; else dart analyze --fatal-infos; fi )
}
pkg_test() {
  ( cd "$1" || exit 1
    [ -d test ] || { echo "test/ fehlt in $1"; exit 1; }
    if is_flutter .; then
      if [ "$1" = app ]; then flutter test --coverage; else flutter test; fi
    else dart test; fi )
}

# Lock muss zur pubspec passen. --enforce-lockfile scheitert bei neuen oder geänderten Paketen, meldet "von
# transitiv zu direkt" aber nur als Text mit Exit 0; die späteren Schritte (analyze, test) schreiben das Lock dann
# still um. Darum prüft der letzte Schritt zusätzlich, dass pubspec.lock am Ende unverändert ist.
lock_hash() { shasum app/pubspec.lock 2>/dev/null || echo fehlt; }
lock_unveraendert() {
  [ "$lock_before" != fehlt ] || { echo "app/pubspec.lock fehlt"; return 1; }
  [ "$lock_before" = "$(lock_hash)" ] || { echo "app/pubspec.lock wurde während des Gates verändert; pubspec.yaml und Lock passen nicht zusammen (flutter pub get ausführen und Lock committen)"; return 1; }
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

# core bleibt frei von Flutter. Der Pub-Workspace teilt eine package_config, ein Flutter-Import löst sich dort
# sonst still auf. Darum: (1) Abhängigkeits-Walk, (2) core wird in ein Temp-Verzeichnis außerhalb des Workspace
# kopiert, dort aufgelöst (nur eigene Abhängigkeiten) und mit allen Bibliotheken (alle .dart-Dateien außer .dart_tool und build) kompiliert.
# Ein Import von flutter, dart:ui, sky_engine oder adapters scheitert dort an der Auflösung, unabhängig von Lints.
core_flutterfrei() {
  core=app/packages/core
  [ -d "$core" ] || { echo "$core fehlt"; return 1; }
  rc=0
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
  tmp=$(mktemp -d) || return 1
  root=$(pwd)
  ( # kein set -e: es wäre wegen des || unten wirkungslos, darum prüft jeder Befehl selbst
    tar -C app/packages --exclude core/.dart_tool --exclude core/build -cf - core | tar -C "$tmp" -xf - || exit 1
    cd "$tmp/core" || exit 1
    grep -Eq '^resolution:[[:space:]]*workspace[[:space:]]*$' pubspec.yaml || { echo "core/pubspec.yaml: 'resolution: workspace' fehlt"; exit 1; }
    grep -Ev '^resolution:[[:space:]]*workspace[[:space:]]*$' pubspec.yaml > pubspec.tmp && mv pubspec.tmp pubspec.yaml || exit 1
    cp "$root/app/pubspec.lock" pubspec.lock || exit 1   # dieselben Versionen wie im Workspace-Lock, nicht die des lokalen Caches
    dart pub get --offline || exit 1
    python3 - <<'PY'
import os, re
def strip(t): return re.sub(r"//[^\n]*", "", re.sub(r"/\*.*?\*/", "", t, flags=re.S))
files = {}
for d, dn, fs in os.walk("."):
    if d == ".": dn[:] = [x for x in dn if x not in (".dart_tool", "build")]
    for f in sorted(fs):
        if f.endswith(".dart") and not (d == "." and f == "gate_entry.dart"):
            path = os.path.relpath(os.path.join(d, f)).replace(os.sep, "/")
            files[path] = strip(open(path, encoding="utf-8").read())
# Bedingte Importe/Exporte (dart.library.*) sind in core verboten: Analyzer und Kompilat prüfen den Zweig nicht,
# im App-Build wäre er aktiv. Kommentare sind vorher entfernt.
cond = [p for p, t in sorted(files.items()) if re.search(r"^\s*(?:import|export)\b[^;]*\bif\s*\(\s*dart\.library\.", t, re.M)]
if cond: raise SystemExit("bedingter Import/Export (if (dart.library.…)) in core verboten: " + ", ".join(cond))
# Eine Datei mit "part of" wird nur ausgelassen, wenn eine andere Datei sie per "part" einbindet.
# Sonst zählt sie als Bibliothek und scheitert beim Kompilieren (fail-closed).
included = set()
for path, text in files.items():
    for m in re.finditer(r"^\s*part\s+['\"]([^'\"]+)['\"]", text, re.M):
        included.add(os.path.normpath(os.path.join(os.path.dirname(path), m.group(1))).replace(os.sep, "/"))
imports, n = [], 0
for path, text in sorted(files.items()):
    if re.match(r"\s*part\s+of\b", text) and path in included: continue   # "part of" muss die erste Direktive sein
    uri = "package:core/" + path[4:] if path.startswith("lib/") else path   # übrige Pfade (bin/, test/, ...) relativ zu gate_entry.dart
    imports.append("import '%s' as l%d;" % (uri, n)); n += 1
if n == 0: raise SystemExit("keine Dart-Dateien in core gefunden")
open("gate_entry.dart", "w").write("\n".join(imports) + "\nvoid main() {}\n")
print(n, "Bibliotheken")
PY
    [ $? -eq 0 ] || exit 1
    dart compile kernel gate_entry.dart -o gate_entry.dill
  ) || rc=1
  rm -rf "$tmp"
  return $rc
}

# Drift: app_database.g.dart muss aus schema.drift entstehen (build_runner/drift_dev), sonst laufen beide unbemerkt
# auseinander. Der erzeugte Stand wird mit dem eingecheckten verglichen; die Datei wird danach immer wiederhergestellt.
drift_aktuell() {
  dir=app/packages/adapters
  g=$dir/lib/src/storage/app_database.g.dart
  [ -f "$g" ] || { echo "$g fehlt"; return 1; }
  bak=$(mktemp) || return 1
  out=$(mktemp) || { rm -f "$bak"; return 1; }
  cp "$g" "$bak" || { rm -f "$bak" "$out"; return 1; }
  rc=0
  # Abbruch (INT/TERM/EXIT) stellt die Datei wieder her und entfernt die Sicherung.
  ( trap 'cp "$bak" "$g"; rm -f "$bak" "$out"' EXIT
    trap 'exit 130' INT TERM
    # Erst clean: sonst überspringt build_runner bei unveränderten Eingaben alles ("skipped") und gibt die Warnungen
    # nicht noch einmal aus; ein zweiter Lauf oder ein manueller build_runner-Lauf machte den Schritt falsch grün.
    # clean löscht die .g.dart nicht (sie ist eingecheckt); sie wird neu erzeugt, die Sicherung stellt der trap wieder her.
    ( cd "$dir" && dart run build_runner clean && dart run build_runner build ) > "$out" 2>&1 || { cat "$out"; echo "build_runner scheiterte"; exit 1; }
    # drift_dev meldet Syntaxfehler in schema.drift nur als Warnung (W drift_dev ...) bei Exit 0; die kaputte Tabelle
    # fehlte dann still in der .g.dart. Darum zählen Warnungen und Fehler (Zeilen W/E/SEVERE) als rot.
    if grep -Eq '^(\[[A-Z]+\] )?(W|E|SEVERE)[[:space:]]' "$out"; then
      grep -E '^(\[[A-Z]+\] )?(W|E|SEVERE)[[:space:]]' "$out" | head -20
      echo "build_runner/drift_dev meldet Warnungen oder Fehler (z. B. Syntaxfehler in schema.drift)"; exit 1
    fi
    if ! cmp -s "$bak" "$g"; then
      echo "app_database.g.dart passt nicht zu schema.drift; build_runner neu laufen lassen (siehe drift_schemas/README.md)"
      diff "$bak" "$g" | head -20
      exit 1
    fi )
  rc=$?
  rm -f "$bak" "$out"
  return $rc
}

# Kotlin-JVM-Tests der Android-Schicht (WP08). JDK 27 scheitert an jlink, daher das JBR von Android Studio;
# KOTLIN_TEST_JAVA_HOME überschreibt den Pfad. Fail-closed: fehlt das JDK, ist der Schritt rot.
kotlin_tests() {
  jh=${KOTLIN_TEST_JAVA_HOME:-/Applications/Android Studio.app/Contents/jbr/Contents/Home}
  [ -x "$jh/bin/java" ] || { echo "JDK für die Kotlin-Tests fehlt: $jh (KOTLIN_TEST_JAVA_HOME setzen)"; return 1; }
  ( cd app/android && JAVA_HOME="$jh" ./gradlew -q :app:testDebugUnitTest )
}

# SEC-0008: Das Release-APK fordert kein INTERNET. Geprüft am gebauten APK (aapt), nicht am Quell-Manifest, weil Plugins
# per Manifest-Merge Berechtigungen hinzufügen können. Fail-closed: fehlt aapt oder die Ausgabe, ist der Schritt rot.
release_ohne_internet() {
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
  aapt=$(ls "$sdk"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
  [ -n "$aapt" ] || { echo "aapt nicht gefunden unter $sdk/build-tools"; return 1; }
  ( cd app && flutter build apk --release ) || return 1
  apk=app/build/app/outputs/flutter-apk/app-release.apk
  [ -f "$apk" ] || { echo "$apk fehlt"; return 1; }
  perms=$("$aapt" dump permissions "$apk") || { echo "aapt dump permissions scheiterte"; return 1; }
  echo "$perms" | grep -q '^package: ' || { echo "aapt-Ausgabe unerwartet"; return 1; }
  echo "$perms"
  if echo "$perms" | grep -q 'android.permission.INTERNET'; then
    echo "Release-APK fordert android.permission.INTERNET (SEC-0008)"; return 1
  fi
  # WP08: keine Hintergrund-Standortberechtigung und kein Start nach dem Booten (ADR-0005).
  for verboten in android.permission.ACCESS_BACKGROUND_LOCATION android.permission.RECEIVE_BOOT_COMPLETED; do
    if echo "$perms" | grep -q "$verboten"; then
      echo "Release-APK fordert $verboten (ADR-0005)"; return 1
    fi
  done
  # WP07: Der Test-Sensor gehört nur in den Debug-Einstieg. Sein Marker darf in keiner Datei des Release-APK stehen.
  marker=$(sed -n "s/^const String testSensorMarker = '\(.*\)';$/\1/p" app/lib/debug/debug_test_sensor.dart)
  [ -n "$marker" ] || { echo "testSensorMarker in app/lib/debug/debug_test_sensor.dart nicht gefunden"; return 1; }
  if unzip -p "$apk" | LC_ALL=C grep -a -q -F "$marker"; then
    echo "Release-APK enthält den Test-Sensor ($marker)"; return 1
  fi
  echo "Test-Sensor nicht im Release-APK"
}

if [ -f app/pubspec.yaml ]; then
  if [ "${1:-}" = --changed ] && ! app_changed; then
    echo "SKIP  flutter (app/, tool/gate.sh und von Tests gelesene Dokumente unverändert)"
  else
    step "flutter version" flutter_version
    lock_before=$(lock_hash)
    step "pub get" sh -c 'cd app && flutter pub get --enforce-lockfile'
    step "core flutterfrei" core_flutterfrei
    for p in app app/packages/*; do
      if [ ! -f "$p/pubspec.yaml" ]; then step "$p pubspec" sh -c "echo 'pubspec.yaml fehlt in $p'; exit 1"; continue; fi
      step "$p format" pkg_format "$p"
      step "$p analyze" pkg_analyze "$p"
      step "$p test" pkg_test "$p"
    done
    step "drift schema" drift_aktuell
    step "kotlin test" kotlin_tests
    step "release ohne verbotene Rechte und Test-Sensor" release_ohne_internet
    step "lock unverändert" lock_unveraendert
  fi
fi
[ $fail -eq 0 ] && echo "GATE GRÜN" || { echo "GATE ROT"; exit 1; }
