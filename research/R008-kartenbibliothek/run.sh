#!/bin/bash
# Fuehrt R008 aus. Alle Schritte und Parameter: ./run.sh --help (gleichlautend zur README).
set -euo pipefail
cd "$(dirname "$0")"
source "$(git rev-parse --show-toplevel)/research/_shared/paths.sh"
ID=R008
WORK="$(research_work "$ID")"; FIX="$WORK/fixtures"
APPS_ALL="base fm fmvt ml"
usage() { cat <<HELP
Usage: ./run.sh <schritt> [Parameter]
Schritte:
| \`host\`     | Host-Tests der Mini-Apps fm und fmvt (flutter test): Hook bzw. Tor, fail-closed, Miniatur, Klartext- und Dateinamen-Gegenprobe |
| \`build\`    | Mini-Apps bauen (Release, arm64/x86_64 einzeln und universal), APK-Groessen nach apk_sizes.tsv |
| \`licenses\` | Lizenzbaum: Dart (pubspec.lock + LICENSE im Pub-Cache) und Gradle (releaseRuntimeClasspath + POM) |
| \`netstatic\`| Netz-APIs und fest eingebaute Hosts in Dart-Paketen, Java/Kotlin-Quellen und nativen Bibliotheken |
| \`emu\`      | Emulator-Messungen (src/emu.sh): Mitschnitt ohne/mit Einwilligung, Live-Seite, Miniaturen, Speicher |
| \`store\`    | Host-Probe der Speicherempfehlung (src/storeprobe): sqlite3mc-Datei gegen AES-GCM je Datei, ohne Netz fuer Kacheln, Ausgabe store.json (laedt beim ersten Mal die SHA-256-gepruefte Bibliothek libsqlite3mc von GitHub) |
Parameter:
| \`--apps "a b"\` | "$APPS_ALL" | Mini-Apps fuer build, licenses, emu |
| \`--api N\`      | 36          | emu: API-Stufe (36 voll, 31 nur Start-Smoke) |
| \`--port N\`     | 5600        | emu: Konsolenport des eigenen Emulators (Serial emulator-N) |
| \`--live-s S\`   | 120         | emu: Dauer der Live-Messung je App in Sekunden |
| \`--profil P\`   | voll        | emu: voll (alle Phasen) oder nachlauf (Werte-Seite, 50 Miniaturen mit Scrollen, Klartext-Gegenprobe) |
Ausgaben: \$RESEARCH_DATA/work/R008/<schritt>-<zeit>/ (nie ueberschrieben). Laufmarker .done nach Exit 0.
HELP
}
STEP="${1:-}"; [ -n "$STEP" ] || { usage >&2; exit 2; }; shift || true
[ "$STEP" = "--help" ] && { usage; exit 0; }
APPS="$APPS_ALL"; API=36; PORT=5600; LIVE_S=120; PROFIL=voll
while [ $# -gt 0 ]; do
  case "$1" in
    --apps) APPS="$2"; shift 2 ;; --api) API="$2"; shift 2 ;; --port) PORT="$2"; shift 2 ;; --live-s) LIVE_S="$2"; shift 2 ;; --profil) PROFIL="$2"; shift 2 ;;
    --help) usage; exit 0 ;; *) echo "Unbekannter Parameter: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -f "$FIX/.done" ] || { echo "Testvorlagen fehlen: erst ./init.sh" >&2; exit 2; }
OUT="$WORK/$STEP-$(date +%Y%m%d-%H%M%S)"; mkdir -p "$OUT"
{ echo "schritt=$STEP apps=$APPS api=$API port=$PORT live_s=$LIVE_S profil=$PROFIL"
  echo "commit=$(git rev-parse --short HEAD) dirty=$(git status --porcelain . | wc -l | tr -d ' ')"
  flutter --version 2>/dev/null | head -1; sw_vers -productVersion; uname -m; } > "$OUT/run.info"
case "$STEP" in
  host)
    VMT=~/.pub-cache/hosted/pub.dev/vector_map_tiles-9.0.0-beta.13; [ -d "$VMT" ] || dart pub cache add vector_map_tiles --version 9.0.0-beta.13
    python3 src/patch_vmt.py "$VMT" "$WORK/apps/vmt_patched" >/dev/null
    for a in fm fmvt; do
      APP=$(src/mkapp.sh $a "$WORK/apps")
      ( cd "$APP" && flutter pub get >/dev/null && R008_FIXTURES="$FIX" R008_OUT="$OUT" flutter test --reporter expanded ) 2>&1 | tee "$OUT/host_$a.log"
    done ;;
  build) src/build.sh "$OUT" $APPS 2>&1 | tee "$OUT/build.log" ;;
  licenses) python3 src/licenses.py "$WORK/apps" "$OUT" $APPS 2>&1 | tee "$OUT/licenses.log" ;;
  netstatic) bash src/netstatic.sh "$WORK/apps" "$OUT" 2>&1 | tee "$OUT/netstatic.log" ;;
  emu) bash src/emu.sh "$OUT" "$API" "$PORT" "$LIVE_S" "$PROFIL" $APPS 2>&1 | tee "$OUT/emu.log" ;;
  store)
    SP="$WORK/apps/storeprobe"; mkdir -p "$SP"; cp -R src/storeprobe/. "$SP/"
    FIXABS="$FIX"; ( cd "$SP" && dart pub get >/dev/null && nice -n 10 dart run bin/storeprobe.dart "$FIXABS" "$OUT/w" ) 2>&1 | tee "$OUT/store.log"
    cp "$OUT/w/store.json" "$OUT/store.json"; trash "$OUT/w" ;;
  *) echo "Unbekannter Schritt: $STEP" >&2; usage >&2; exit 2 ;;
esac
touch "$OUT/.done"; echo "Fertig: $OUT"
