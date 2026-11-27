#!/usr/bin/env bash
# Selbsttest für tool/check_e2e_green.sh mit Attrappen für gh und sleep (kein Netz, keine echte Wartezeit):
# grüner Lauf, roter Lauf, kein Lauf, Lauf mit Ergebnis success aber rotem Job, Lauf eines anderen Commits,
# laufender Lauf wird grün bzw. rot, Wartegrenze erreicht, Fehler der API, unlesbare Antwort, falsche Aufrufe.
# Aufruf: bash tool/check_e2e_green_test.sh
set -u
script=$(cd "$(dirname "$0")" && pwd)/check_e2e_green.sh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
SHA=0123456789abcdef0123456789abcdef01234567
OTHER=fedcba9876543210fedcba9876543210fedcba98

# gh: zählt Abfragen der Läufe. Antwort für die n-te Abfrage aus $FAKE/runs.<n>.json, sonst $FAKE/runs.json;
# Jobs eines Laufs aus $FAKE/jobs.<id>.json. Fehlt die Datei, endet gh mit Exit 1 (Fehler der API).
# Jeder Aufruf wird in $FAKE/calls protokolliert.
cat > "$tmp/bin/gh" <<'X'
#!/usr/bin/env bash
echo "$*" >> "$FAKE/calls"
[ "$1" = api ] || exit 3
case "$2" in
  repos/owner/repo/actions/workflows/e2e.yml/runs\?head_sha=*)
    n=$(( $(cat "$FAKE/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$FAKE/count"
    f=$FAKE/runs.$n.json; [ -f "$f" ] || f=$FAKE/runs.json
    cat "$f" 2>/dev/null || { echo "HTTP 500" >&2; exit 1; } ;;
  repos/owner/repo/actions/runs/*/jobs\?*)
    id=${2#repos/owner/repo/actions/runs/}; id=${id%%/*}
    cat "$FAKE/jobs.$id.json" 2>/dev/null || { echo "HTTP 404" >&2; exit 1; } ;;
  *) echo "unerwarteter Pfad $2" >&2; exit 3 ;;
esac
X
# sleep: wartet nicht, protokolliert nur die Sekunden.
cat > "$tmp/bin/sleep" <<'X'
#!/usr/bin/env bash
echo "$1" >> "$FAKE/sleeps"
X
chmod +x "$tmp/bin/gh" "$tmp/bin/sleep"
export PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=owner/repo GITHUB_SERVER_URL=https://example.invalid
unset E2E_WAIT_SECONDS E2E_POLL_SECONDS E2E_WORKFLOW
fails=0

run_json() { # <id> <sha> <status> <conclusion|null> <created_at>
  c=$4; [ "$c" = null ] || c="\"$c\""
  printf '{"id":%s,"head_sha":"%s","status":"%s","conclusion":%s,"created_at":"%s","html_url":"https://example.invalid/owner/repo/actions/runs/%s"}' \
    "$1" "$2" "$3" "$c" "$5" "$1"
}
runs() { # <datei> <lauf-json>...
  f=$1; shift; (IFS=,; printf '{"total_count":%s,"workflow_runs":[%s]}' "$#" "$*") > "$FAKE/$f"
}
jobs() { # <id> <conclusion>... (je Job eine)
  id=$1; shift; out=; for c in "$@"; do out="$out${out:+,}{\"status\":\"completed\",\"conclusion\":\"$c\"}"; done
  printf '{"total_count":%s,"jobs":[%s]}' "$#" "$out" > "$FAKE/jobs.$id.json"
}
fresh() { export FAKE="$tmp/f$((++case_no))"; mkdir -p "$FAKE"; }
case_no=0
# check <Name> <rc> <erwartete Ausgabe (grep -F)> <Abfragen der Läufe> <Summe der Pausen> [Argumente ...]
check() {
  name=$1 want_rc=$2 want_out=$3 want_q=$4 want_s=$5; shift 5
  [ $# -gt 0 ] || set -- "$SHA"
  # Obergrenze gegen eine Endlosschleife (etwa Wartezeit zählt nicht hoch); Exit 124 = Zeit überschritten.
  timeout 60 bash "$script" "$@" > "$FAKE/out" 2>&1; rc=$?
  q=$(cat "$FAKE/count" 2>/dev/null || echo 0)
  s=$(awk '{t += $1} END {print t + 0}' "$FAKE/sleeps" 2>/dev/null || echo 0)
  if [ "$rc" -eq "$want_rc" ] && grep -qF -- "$want_out" "$FAKE/out" && [ "$q" -eq "$want_q" ] && [ "$s" -eq "$want_s" ]; then
    echo "OK   $name"
  else
    echo "FAIL $name (rc=$rc erwartet $want_rc, Abfragen $q erwartet $want_q, Pausen $s erwartet $want_s, Text '$want_out')"
    sed 's/^/     /' "$FAKE/out"; fails=$((fails + 1))
  fi
}

fresh; runs runs.json "$(run_json 11 "$SHA" completed success 2026-01-01T10:00:00Z)"; jobs 11 success success success success
check "grüner Lauf, alle Jobs grün" 0 "e2e auf $SHA grün: https://example.invalid/owner/repo/actions/runs/11" 1 0

fresh; runs runs.json "$(run_json 12 "$SHA" completed failure 2026-01-01T10:00:00Z)"
check "roter Lauf" 1 "e2e auf $SHA nicht grün: https://example.invalid/owner/repo/actions/runs/12" 1 0

fresh; runs runs.json "$(run_json 13 "$SHA" completed cancelled 2026-01-01T10:00:00Z)"
check "abgebrochener Lauf" 1 "e2e auf $SHA nicht grün: https://example.invalid/owner/repo/actions/runs/13" 1 0

fresh; runs runs.json
check "kein Lauf auf dem Commit" 1 "e2e auf $SHA nicht grün: kein Lauf von e2e auf diesem Commit (https://example.invalid/owner/repo/actions/workflows/e2e.yml)" 1 0

fresh; runs runs.json "$(run_json 14 "$SHA" completed success 2026-01-01T10:00:00Z)"; jobs 14 success failure success success
check "Lauf success, ein Job rot" 1 "e2e auf $SHA nicht grün: https://example.invalid/owner/repo/actions/runs/14" 1 0

fresh; runs runs.json "$(run_json 15 "$SHA" completed success 2026-01-01T10:00:00Z)"; jobs 15 success skipped
check "Lauf success, ein Job übersprungen" 1 "e2e auf $SHA nicht grün" 1 0

fresh; runs runs.json "$(run_json 16 "$SHA" completed success 2026-01-01T10:00:00Z)"; printf '{"total_count":0,"jobs":[]}' > "$FAKE/jobs.16.json"
check "Lauf success ohne Jobs" 1 "e2e auf $SHA nicht grün" 1 0

fresh; runs runs.json "$(run_json 17 "$SHA" completed success 2026-01-01T10:00:00Z)"; printf '{"total_count":5,"jobs":[{"status":"completed","conclusion":"success"}]}' > "$FAKE/jobs.17.json"
check "Lauf success, Jobliste unvollständig" 1 "e2e auf $SHA nicht grün" 1 0

fresh; runs runs.json "$(run_json 18 "$OTHER" completed success 2026-01-01T10:00:00Z)"; jobs 18 success
check "grüner Lauf nur auf anderem Commit" 1 "kein Lauf von e2e auf diesem Commit" 1 0

fresh; runs runs.json "$(run_json 19 "$SHA" completed failure 2026-01-01T10:00:00Z)" "$(run_json 20 "$SHA" completed success 2026-01-02T10:00:00Z)"; jobs 20 success success
check "roter und späterer grüner Lauf" 0 "e2e auf $SHA grün: https://example.invalid/owner/repo/actions/runs/20" 1 0

fresh; runs runs.json "$(run_json 21 "$SHA" completed success 2026-01-01T10:00:00Z)"
check "Fehler der API bei den Jobs" 1 "Abfrage der Jobs gescheitert" 1 0

fresh
check "Fehler der API bei den Läufen" 1 "e2e auf $SHA nicht grün: Abfrage der Läufe gescheitert" 1 0

fresh; printf 'kein json' > "$FAKE/runs.json"
check "unlesbare Antwort" 1 "e2e auf $SHA nicht grün: Antwort der API nicht lesbar" 1 0

# Laufender Lauf: wartet und wird grün bzw. rot.
fresh
runs runs.1.json "$(run_json 30 "$SHA" in_progress null 2026-01-01T10:00:00Z)"
runs runs.2.json "$(run_json 30 "$SHA" queued null 2026-01-01T10:00:00Z)"
runs runs.json "$(run_json 30 "$SHA" completed success 2026-01-01T10:00:00Z)"; jobs 30 success success
check "laufender Lauf wird grün" 0 "e2e auf $SHA grün: https://example.invalid/owner/repo/actions/runs/30" 3 60

fresh
runs runs.1.json "$(run_json 31 "$SHA" in_progress null 2026-01-01T10:00:00Z)"
runs runs.json "$(run_json 31 "$SHA" completed failure 2026-01-01T10:00:00Z)"
check "laufender Lauf wird rot" 1 "e2e auf $SHA nicht grün: https://example.invalid/owner/repo/actions/runs/31" 2 30

fresh
runs runs.1.json "$(run_json 32 "$SHA" completed failure 2026-01-01T10:00:00Z)" "$(run_json 33 "$SHA" in_progress null 2026-01-02T10:00:00Z)"
runs runs.json "$(run_json 32 "$SHA" completed failure 2026-01-01T10:00:00Z)" "$(run_json 33 "$SHA" completed success 2026-01-02T10:00:00Z)"; jobs 33 success
check "roter Lauf und laufende Wiederholung: wartet" 0 "e2e auf $SHA grün: https://example.invalid/owner/repo/actions/runs/33" 2 30

# Wartegrenze: Richtwert 45 min (2700 s) in Pausen zu 30 s = 90 Pausen, 91 Abfragen.
fresh; runs runs.json "$(run_json 34 "$SHA" in_progress null 2026-01-01T10:00:00Z)"
check "Wartegrenze 45 min erreicht" 1 "e2e auf $SHA nicht grün: Lauf nach 45 min nicht abgeschlossen: https://example.invalid/owner/repo/actions/runs/34" 91 2700

fresh; runs runs.json "$(run_json 35 "$SHA" in_progress null 2026-01-01T10:00:00Z)"
for i in $(seq 1 90); do cp "$FAKE/runs.json" "$FAKE/runs.$i.json"; done
runs runs.json "$(run_json 35 "$SHA" completed success 2026-01-01T10:00:00Z)"; jobs 35 success
check "grün genau an der Wartegrenze" 0 "e2e auf $SHA grün" 91 2700

fresh; runs runs.json "$(run_json 36 "$SHA" in_progress null 2026-01-01T10:00:00Z)"
E2E_WAIT_SECONDS=60 E2E_POLL_SECONDS=15 check "Wartegrenze über Umgebung" 1 "Lauf nach 1 min nicht abgeschlossen" 5 60

# Falsche Aufrufe und Umgebung: Exit ungleich 0, keine Abfrage.
fresh; timeout 60 bash "$script" > "$FAKE/out" 2>&1; rc=$?
[ "$rc" -eq 2 ] && echo "OK   ohne Argument (Exit 2)" || { echo "FAIL ohne Argument: rc=$rc"; fails=$((fails + 1)); }
fresh; check "zwei Argumente" 2 "Aufruf:" 0 0 "$SHA" "$SHA"
fresh; check "kurzer Commit" 1 "ungültiger Commit" 0 0 0123456
fresh; check "Großbuchstaben im Commit" 1 "ungültiger Commit" 0 0 0123456789ABCDEF0123456789ABCDEF01234567
fresh; GITHUB_REPOSITORY= check "ohne Repository" 1 "GITHUB_REPOSITORY fehlt" 0 0
fresh; E2E_POLL_SECONDS=0 check "Pause 0" 1 "größer als 0" 0 0

[ "$fails" -eq 0 ] && echo "check_e2e_green: alle Fälle grün" || { echo "check_e2e_green: $fails Fälle rot"; exit 1; }
