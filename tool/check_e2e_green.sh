#!/usr/bin/env bash
# Prüft vor einem Release, dass der Workflow `e2e` auf einem Commit grün war (docs/quality/testing.md, CI-Gates).
# Aufruf: bash tool/check_e2e_green.sh <commit-sha>
# Umgebung: GITHUB_REPOSITORY (owner/name, Pflicht), GH_TOKEN (für gh api, Recht actions: read),
#           GITHUB_SERVER_URL (Vorgabe https://github.com), E2E_WORKFLOW (Vorgabe e2e.yml),
#           E2E_WAIT_SECONDS (Richtwert 2700 = 45 min), E2E_POLL_SECONDS (Vorgabe 30).
# Grün (Exit 0) nur, wenn es für genau diesen Commit einen abgeschlossenen Lauf von `e2e` mit Ergebnis `success`
# gibt, dessen Jobs alle `success` sind. Läuft noch ein Lauf auf dem Commit und gibt es keinen grünen, wird bis
# E2E_WAIT_SECONDS gewartet (Summe der Pausen). Sonst Exit 1 mit „e2e auf <sha> nicht grün“ und Link. Jeder
# Fehler der Abfrage ist rot (fail-closed). Es gibt keine Ausnahme und keinen Schalter zum Umgehen.
# Selbsttest: tool/check_e2e_green_test.sh (Attrappe für gh).
set -u

die() { echo "FEHLER: $*" >&2; exit 1; }

[ $# -eq 1 ] || { echo "Aufruf: $0 <commit-sha>" >&2; exit 2; }
sha=$1
case "$sha" in
  *[!0-9a-f]* | '') die "ungültiger Commit '$sha' (erwartet 40 Hex-Zeichen)" ;;
esac
[ ${#sha} -eq 40 ] || die "ungültiger Commit '$sha' (erwartet 40 Hex-Zeichen)"
repo=${GITHUB_REPOSITORY:-}
case "$repo" in */*) ;; *) die "GITHUB_REPOSITORY fehlt oder ist ungültig" ;; esac
server=${GITHUB_SERVER_URL:-https://github.com}
workflow=${E2E_WORKFLOW:-e2e.yml}
wait_max=${E2E_WAIT_SECONDS:-2700}
poll=${E2E_POLL_SECONDS:-30}
case "$wait_max$poll" in *[!0-9]*) die "E2E_WAIT_SECONDS und E2E_POLL_SECONDS müssen ganze Zahlen sein" ;; esac
[ "$poll" -gt 0 ] || die "E2E_POLL_SECONDS muss größer als 0 sein"
command -v jq >/dev/null 2>&1 || die "jq fehlt"
command -v gh >/dev/null 2>&1 || die "gh fehlt"

list_url="$server/$repo/actions/workflows/$workflow"

# Alle Jobs aller Versuche des Laufs? Maßgeblich ist der letzte Versuch (filter=latest); jeder Job muss success sein.
jobs_green() { # <run-id>
  local out
  out=$(gh api "repos/$repo/actions/runs/$1/jobs?filter=latest&per_page=100") || return 2
  printf '%s' "$out" | jq -e '(.jobs | type == "array") and (.jobs | length > 0) and (.total_count == (.jobs | length))
    and all(.jobs[]; .status == "completed" and .conclusion == "success")' >/dev/null
  case $? in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}

waited=0
while :; do
  runs=$(gh api "repos/$repo/actions/workflows/$workflow/runs?head_sha=$sha&per_page=100") \
    || die "e2e auf $sha nicht grün: Abfrage der Läufe gescheitert ($list_url)"
  # Nur Läufe genau dieses Commits (die API filtert schon, die Prüfung hier ist fail-closed gegen Abweichungen).
  sel=$(printf '%s' "$runs" | jq -c --arg sha "$sha" '[.workflow_runs[]? | select(.head_sha == $sha)]') \
    || die "e2e auf $sha nicht grün: Antwort der API nicht lesbar ($list_url)"
  for id in $(printf '%s' "$sel" | jq -r '.[] | select(.status == "completed" and .conclusion == "success") | .id'); do
    case "$id" in *[!0-9]* | '') die "e2e auf $sha nicht grün: ungültige Lauf-ID ($list_url)" ;; esac
    url=$(printf '%s' "$sel" | jq -r --argjson id "$id" '.[] | select(.id == $id) | .html_url')
    jobs_green "$id"
    case $? in
      0) echo "e2e auf $sha grün: $url"; exit 0 ;;
      1) echo "Lauf $url: Ergebnis success, aber nicht alle Jobs success" >&2 ;;
      *) die "e2e auf $sha nicht grün: Abfrage der Jobs gescheitert ($url)" ;;
    esac
  done
  running=$(printf '%s' "$sel" | jq -r '[.[] | select(.status != "completed")] | sort_by(.created_at) | last | .html_url // empty')
  latest=$(printf '%s' "$sel" | jq -r 'sort_by(.created_at) | last | .html_url // empty')
  if [ -z "$running" ]; then
    if [ -z "$latest" ]; then
      die "e2e auf $sha nicht grün: kein Lauf von e2e auf diesem Commit ($list_url)"
    fi
    die "e2e auf $sha nicht grün: $latest"
  fi
  if [ "$waited" -ge "$wait_max" ]; then
    die "e2e auf $sha nicht grün: Lauf nach $((wait_max / 60)) min nicht abgeschlossen: $running"
  fi
  echo "e2e auf $sha läuft noch ($running), warte ${poll} s (bisher ${waited} s von ${wait_max} s)"
  sleep "$poll"
  waited=$((waited + poll))
done
