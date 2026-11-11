#!/bin/sh
# Gate: tool/gate.sh [--fast | --changed]. Spec-Prüfung, Datenschutz und, sobald app/ existiert, Flutter.
#   (ohne Option)  voll: alle Schritte, Pflicht vor Review-Abgabe und Fertigmeldung. Nimmt den Gate-Lock.
#   --fast         Zwischenstand: spec, privat, Netz, Format und Analyse aller Pakete, Tests nur der gegenüber
#                  der Basis (merge-base main) geänderten Pakete und der von ihnen abhängigen (app ← adapters ← core); kein Release/Drift/Kotlin, kein Lock;
#                  pub get nur bei geändertem pubspec.* (oder fehlender Paketauflösung). Ersetzt nie das volle Gate.
#   --changed      wie voll, lässt aber Flutter aus, wenn app/, tool/gate.sh und die von Tests gelesenen Dokumente
#                  (getrackt, ungetrackt, committet) gegenüber main unverändert sind (auf main gegenüber dem Stand vor
#                  dem letzten Commit), und Drift/Kotlin/Release nur, wenn sich ihre Eingaben (Listen unten) geändert haben.
#                  Nimmt den Gate-Lock.
# Im Zweifel (kein main, Fehler beim Vergleich) wird geprüft statt ausgelassen.
# Ablauf: Stufe "schnell" (billige Prüfungen, Format und Analyse aller Pakete) zeigt alle Ergebnisse; ist dort etwas
# rot, endet das Gate danach. Danach (Tests, drift, kotlin, release, lock) bricht es beim ersten roten Schritt ab.
# Jede Zeile nennt die Dauer des Schritts in Sekunden.
# Lock: über alle Worktrees höchstens ein volles/--changed-Gate gleichzeitig (/usr/bin/lockf auf $(git-common-dir)/gate.lock,
# der Lock hängt am Prozess und wird bei Ende, Absturz oder Signal frei). Grenze: kill -9 an lockf lässt das Gate ohne
# Lock weiterlaufen; abbrechen per TERM/Ctrl-C an die PID aus gate.lock.info.

# Eingaben der Schritte bei --changed (Git-Pfadangaben, durch Leerzeichen getrennt, ohne Leerzeichen in Pfaden).
# Alle Listen enthalten tool/gate.sh (die Schrittfunktionen stehen dort) und pubspec.* samt pubspec.lock.
GATE_DRIFT_PATHS="app/packages/adapters/lib/src/storage app/packages/adapters/drift_schemas tool/gate.sh :(glob)app/**/pubspec.*"
GATE_KOTLIN_PATHS="app/android tool/gate.sh :(glob)app/**/pubspec.*"
GATE_RELEASE_PATHS="app/android app/lib app/packages app/assets app/l10n.yaml tool/check_release_manifest.py tool/gate.sh :(glob)app/**/pubspec.*"
GATE_RELEASE_NAME="release: INTERNET, keine verbotenen Rechte, Boot nur Erinnerungs-Empfänger, nur HTTPS, kein Test-Sensor"

mode=full
case "${1:-}" in
  "") ;;
  --fast) mode=fast ;;
  --changed) mode=changed ;;
  *) echo "Aufruf: sh tool/gate.sh [--fast | --changed]"; exit 2 ;;
esac

self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(git rev-parse --show-toplevel)" || exit 1

# Lock (nicht bei --fast): das Skript startet sich einmal unter lockf neu. Erst ein nicht blockierender Versuch
# (Exit 75 = belegt), dann ein einmaliger Hinweis und blockierendes Warten.
if [ "$mode" != fast ] && [ -z "${GATE_LOCK_HELD:-}" ]; then
  gdir=$(git rev-parse --path-format=absolute --git-common-dir) || exit 1
  lock=$gdir/gate.lock
  /usr/bin/lockf -t 0 "$lock" env GATE_LOCK_HELD="$lock" sh "$self" "$@"; rc=$?
  if [ $rc -eq 75 ]; then
    echo "wartet auf Gate von $(cat "$lock.info" 2>/dev/null || echo unbekannt)"
    exec /usr/bin/lockf "$lock" env GATE_LOCK_HELD="$lock" sh "$self" "$@"
  fi
  exit $rc
fi
[ -n "${GATE_LOCK_HELD:-}" ] && echo "$(pwd) PID $$" > "$GATE_LOCK_HELD.info"

fail=0
failfast=0
cur=
t_start=$(date +%s)
set -m   # jeder Schritt läuft in eigener Prozessgruppe, damit ein Signal auch Flutter, Gradle usw. beendet
abbruch() { [ -n "$cur" ] && kill -TERM -- "-$cur" 2>/dev/null; echo "GATE ABGEBROCHEN"; exit 143; }
trap abbruch INT TERM
step() {
  name=$1; shift; log=$(mktemp); t0=$(date +%s)
  "$@" </dev/null >"$log" 2>&1 & cur=$!
  wait "$cur"; rc=$?; cur=
  dt=$(( $(date +%s) - t0 ))
  if [ $rc -eq 0 ]; then echo "OK    $name ($dt s)"; else echo "ROT   $name ($dt s)"; tail -30 "$log"; fail=1; fi
  rm -f "$log"
  if [ $fail -ne 0 ] && [ $failfast -eq 1 ]; then echo "GATE ROT ($(( $(date +%s) - t_start )) s gesamt)"; exit 1; fi
}
# Nach der schnellen Stufe: bei Rot enden, ab jetzt bricht jeder rote Schritt sofort ab.
ende_schnelle_stufe() {
  [ $fail -eq 0 ] || { echo "GATE ROT ($(( $(date +%s) - t_start )) s gesamt, nach der schnellen Stufe)"; exit 1; }
  failfast=1
}
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
# SEC-0002, SEC-0008, ADR-0009: Netz-APIs und Kartenbibliotheken nur im Kartenadapter (fail-closed mit Freigabeliste tool/net_allowed_packages.txt, siehe tool/check_net.py; der Selbsttest tool/check_net_test.py belegt jede Umgehung als rot).
[ -f app/pubspec.yaml ] && step "Netz nur im Kartenadapter" python3 tool/check_net.py
[ -f app/pubspec.yaml ] && step "Netz-Prüfung Selbsttest" python3 tool/check_net_test.py
[ -f app/pubspec.yaml ] && step "Release-Manifest-Prüfung Selbsttest" python3 tool/check_release_manifest_test.py

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

# Wie app_changed, aber für eine Liste von Git-Pfadangaben (ein String, durch Leerzeichen getrennt): 0 = geändert
# oder unklar, 1 = unverändert. Gleiche Basis wie app_changed.
paths_changed() {
  if [ "$(git symbolic-ref -q --short HEAD)" = main ]; then
    pbase=$(git rev-parse -q --verify HEAD^1) || return 0
  else
    pbase=$(git merge-base HEAD main 2>/dev/null) || return 0
  fi
  [ -n "$pbase" ] || return 0
  set -f   # Pfadangaben wie :(glob)app/**/pubspec.* nicht von der Shell expandieren lassen
  # shellcheck disable=SC2086
  git diff --quiet "$pbase" -- $1 || { set +f; return 0; }
  # shellcheck disable=SC2086
  [ -z "$(git ls-files -o --exclude-standard -- $1)" ] || { set +f; return 0; }
  set +f
  return 1
}

# Für --changed: Schritt nur bei geänderten Eingaben (Liste siehe oben im Skript), sonst SKIP.
step_wenn_geaendert() {   # <Eingaben> <Name> <Funktion>
  if paths_changed "$1"; then step "$2" "$3"; else echo "SKIP  $2 (Eingaben unverändert: $1)"; fi
}

# Pfade der Pakete in app/packages, von denen <Paket> über path-Abhängigkeiten (auch transitiv) abhängt.
pkg_deps() {
  acc=; todo=$1
  while [ -n "$todo" ]; do
    next=
    for q in $todo; do
      for n in $(grep -oE 'path:[[:space:]]*(\.\./|packages/)[A-Za-z0-9_]+' "$q/pubspec.yaml" 2>/dev/null | sed -E 's,path:[[:space:]]*(\.\./|packages/),,'); do
        c=app/packages/$n
        case " $acc " in *" $c "*) ;; *) acc="$acc $c"; next="$next $c" ;; esac
      done
    done
    todo=$next
  done
  echo $acc
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
  # gradlew ist erzeugt und nicht versioniert; in einem frischen Worktree fehlt er bis zum ersten Android-Build.
  if [ ! -x app/android/gradlew ]; then
    ( cd app && flutter build apk --config-only ) || { echo "flutter build apk --config-only scheiterte"; return 1; }
  fi
  ( cd app/android && JAVA_HOME="$jh" ./gradlew -q :app:testDebugUnitTest )
}

# WP14: Die Paket-ID des gebauten APK ist io.github.brokoskokoli.ramuri (aapt dump badging). Eine andere applicationId
# ändert nebenbei die FileProvider-Authority. Aufruf: paket_id_pruefen <aapt> <apk> [erwartete ID]; fail-closed.
paket_id_pruefen() {
  erwartet=${3:-io.github.brokoskokoli.ramuri}
  badging=$("$1" dump badging "$2") || { echo "aapt dump badging scheiterte"; return 1; }
  ist=$(echo "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
  [ "$ist" = "$erwartet" ] || { echo "Paket-ID des APK ist '$ist', erwartet '$erwartet'"; return 1; }
}

# SEC-0008 (WP13): Das Release-APK fordert INTERNET (nur für Kartenkacheln, Einwilligung, Gate-Schritt "net"), aber keine
# Hintergrund-Standortberechtigung, keine exakten Wecker und BOOT_COMPLETED nur für den Erinnerungs-Empfänger. Geprüft am gebauten APK (aapt), nicht am Quell-Manifest,
# weil Plugins per Manifest-Merge Berechtigungen hinzufügen können. Fail-closed: fehlt aapt oder die Ausgabe, ist der
# Schritt rot. Auch Klartext-Verkehr (usesCleartextTraffic, Netzwerk-Sicherheitskonfiguration) wird am APK geprüft.
release_rechte() {
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}
  aapt=$(ls "$sdk"/build-tools/*/aapt 2>/dev/null | sort -V | tail -1)
  [ -n "$aapt" ] || { echo "aapt nicht gefunden unter $sdk/build-tools"; return 1; }
  ( cd app && flutter build apk --release ) || return 1
  apk=app/build/app/outputs/flutter-apk/app-release.apk
  [ -f "$apk" ] || { echo "$apk fehlt"; return 1; }
  paket_id_pruefen "$aapt" "$apk" || return 1
  perms=$("$aapt" dump permissions "$apk") || { echo "aapt dump permissions scheiterte"; return 1; }
  echo "$perms" | grep -q '^package: ' || { echo "aapt-Ausgabe unerwartet"; return 1; }
  echo "$perms"
  if ! echo "$perms" | grep -q 'android.permission.INTERNET'; then
    echo "Release-APK fordert android.permission.INTERNET nicht (WP13: Kartenkacheln)"; return 1
  fi
  tree=$("$aapt" dump xmltree "$apk" AndroidManifest.xml) || { echo "aapt dump xmltree scheiterte"; return 1; }
  echo "$tree" | grep -q 'networkSecurityConfig' || { echo "Release-APK: android:networkSecurityConfig fehlt"; return 1; }
  if echo "$tree" | grep 'usesCleartextTraffic' | grep -qv ')0x0$'; then
    echo "Release-APK erlaubt Klartext-Verkehr (usesCleartextTraffic)"; return 1
  fi
  # Die Konfiguration selbst (res/xml kann im APK umbenannt sein): cleartextTrafficPermitted muss false sein.
  nscfile=$(unzip -Z1 "$apk" | grep -E '^res/.*\.xml$' | while IFS= read -r f; do
    "$aapt" dump xmltree "$apk" "$f" 2>/dev/null | grep -q 'network-security-config' && { echo "$f"; break; }
  done)
  [ -n "$nscfile" ] || { echo "Release-APK: network-security-config nicht gefunden"; return 1; }
  nsc=$("$aapt" dump xmltree "$apk" "$nscfile")
  echo "$nsc" | grep -q 'cleartextTrafficPermitted' || { echo "Release-APK: cleartextTrafficPermitted fehlt"; return 1; }
  if echo "$nsc" | grep 'cleartextTrafficPermitted' | grep -qv ')0x0$'; then
    echo "Release-APK: Klartext-Verkehr in der Netzwerk-Sicherheitskonfiguration erlaubt"; return 1
  fi
  # WP08/WP22: keine Hintergrund-Standortberechtigung, keine exakten Wecker; RECEIVE_BOOT_COMPLETED nur mit genau einem
  # Empfänger TrainingReminderReceiver, exported=false, der nur Erinnerungs-Wecker neu plant (ADR-0005 Punkt 6 mit
  # Nachtrag, Maintainer 2026-11-10). Am gemergten Manifest des APK; Selbsttest tool/check_release_manifest_test.py.
  rdir=$(mktemp -d) || return 1
  echo "$perms" >"$rdir/perms.txt"; echo "$tree" >"$rdir/tree.txt"
  python3 tool/check_release_manifest.py "$rdir/perms.txt" "$rdir/tree.txt"; rc=$?
  rm -rf "$rdir"
  [ $rc -eq 0 ] || return 1
  # WP07: Der Test-Sensor gehört nur in den Debug-Einstieg. Sein Marker darf in keiner Datei des Release-APK stehen.
  marker=$(sed -n "s/^const String testSensorMarker = '\(.*\)';$/\1/p" app/lib/debug/debug_test_sensor.dart)
  [ -n "$marker" ] || { echo "testSensorMarker in app/lib/debug/debug_test_sensor.dart nicht gefunden"; return 1; }
  if unzip -p "$apk" | LC_ALL=C grep -a -q -F "$marker"; then
    echo "Release-APK enthält den Test-Sensor ($marker)"; return 1
  fi
  echo "Test-Sensor nicht im Release-APK"
}

if [ -f app/pubspec.yaml ]; then
  if [ "$mode" = changed ] && ! app_changed; then
    echo "SKIP  flutter (app/, tool/gate.sh und von Tests gelesene Dokumente unverändert)"
  else
    # --- Stufe schnell: alle Schritte laufen, auch nach einem roten ---
    if [ "$mode" != fast ]; then
      step "flutter version" flutter_version
    fi
    lock_before=$(lock_hash)
    if [ "$mode" != fast ] || paths_changed ":(glob)app/**/pubspec.*" || [ ! -f app/.dart_tool/package_config.json ]; then
      step "pub get" sh -c 'cd app && flutter pub get --enforce-lockfile'
    else
      echo "SKIP  pub get (pubspec.* unverändert)"
    fi
    if [ "$mode" != fast ]; then
      step "core flutterfrei" core_flutterfrei
    fi
    for p in app app/packages/*; do
      if [ ! -f "$p/pubspec.yaml" ]; then step "$p pubspec" sh -c "echo 'pubspec.yaml fehlt in $p'; exit 1"; continue; fi
      step "$p format" pkg_format "$p"
      step "$p analyze" pkg_analyze "$p"
    done
    ende_schnelle_stufe
    # --- Stufe schwer: Tests, Drift, Kotlin, Release, Lock; erster roter Schritt beendet das Gate ---
    for p in app app/packages/*; do
      if [ "$mode" = fast ]; then
        if [ "$p" = app ]; then spec_p="app :(exclude)app/packages $(watched_paths | tail -n +2 | tr '\n' ' ')"; else spec_p=$p; fi
        # Hängt das Paket (transitiv, per path-Abhängigkeit) von einem geänderten ab, laufen seine Tests mit.
        # (getrennt geprüft: das ":(exclude)app/packages" von app würde sonst die Abhängigkeiten ausschließen)
        deps_p=$(pkg_deps "$p")
        paths_changed "$spec_p" || { [ -n "$deps_p" ] && paths_changed "$deps_p"; } || { echo "SKIP  $p test (Paket und Abhängigkeiten gegenüber der Basis unverändert)"; continue; }
      fi
      step "$p test" pkg_test "$p"
    done
    if [ "$mode" = fast ]; then
      echo "FAST  ohne drift schema, kotlin test, release, lock unverändert (nur das volle Gate gilt vor der Fertigmeldung)"
    else
      if [ "$mode" = changed ]; then
        step_wenn_geaendert "$GATE_DRIFT_PATHS" "drift schema" drift_aktuell
        step_wenn_geaendert "$GATE_KOTLIN_PATHS" "kotlin test" kotlin_tests
        step_wenn_geaendert "$GATE_RELEASE_PATHS" "$GATE_RELEASE_NAME" release_rechte
      else
        step "drift schema" drift_aktuell
        step "kotlin test" kotlin_tests
        step "$GATE_RELEASE_NAME" release_rechte
      fi
      step "lock unverändert" lock_unveraendert
    fi
  fi
fi
total=$(( $(date +%s) - t_start ))
[ $fail -eq 0 ] && echo "GATE GRÜN ($total s gesamt)" || { echo "GATE ROT ($total s gesamt)"; exit 1; }
