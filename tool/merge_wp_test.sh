#!/bin/sh
# Test für die CI-Entscheidung in tool/merge_wp.sh (--dry-run, Attrappe MERGE_WP_CI statt gh): Der neueste Lauf der Workflows
# gate und e2e auf genau Branch und SHA muss completed/success sein; sonst Abbruch mit rc 1. Aufruf: sh tool/merge_wp_test.sh
script=$(cd "$(dirname "$0")" && pwd)/merge_wp.sh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q -b main . || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
git config commit.gpgsign false
git commit -q --allow-empty -m base || exit 1
git checkout -q -b wp/x && git commit -q --allow-empty -m work && git checkout -q main || exit 1
sha=$(git rev-parse wp/x)
other=0000000000000000000000000000000000000001
# Attrappe: gibt je Workflow die Zeilen aus der Datei $tmp/ci.<workflow> aus (Umgebung wie bei gh: WORKFLOW, BRANCH, SHA).
cat > "$tmp/ci.sh" <<X
#!/bin/sh
cat "$tmp/ci.\$WORKFLOW" 2>/dev/null
exit 0
X
export MERGE_WP_CI="sh $tmp/ci.sh" MERGE_WP_NAME=t MERGE_WP_EMAIL=t@example.invalid
fails=0
# row <Workflow> <Zeit> <SHA> <Branch> <status> <conclusion>: hängt eine Laufzeile an.
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$2" "$3" "$4" "$5" "$6" >> "$tmp/ci.$1"; }
# check <Name> <erwarteter rc>
check() {
  bash "$script" wp/x --dry-run > "$tmp/out" 2>&1; rc=$?
  # Der Grund zählt: rc 1 nur durch die CI-Prüfung, rc 0 nur im Trockenlauf bis zum Ende.
  if [ "$2" -eq 0 ]; then grep -q 'dry-run.*Prüfungen ok' "$tmp/out" || rc=99
  else grep -q 'ohne grünen CI-Lauf' "$tmp/out" || rc=99; fi
  if [ "$rc" -eq "$2" ]; then echo "OK   $1"; else
    echo "FAIL $1 (rc=$rc erwartet $2)"; sed 's/^/     /' "$tmp/out"; fails=$((fails + 1)); fi
}
reset() { rm -f "$tmp"/ci.gate "$tmp"/ci.e2e; }
green() { row "$1" 2030-01-01T10:00:00Z "$sha" wp/x completed success; }

reset; green gate; green e2e
check "gate und e2e grün" 0
reset; green gate
check "e2e fehlt" 1
reset; green e2e
check "gate fehlt" 1
reset; green gate; row e2e 2030-01-01T10:00:00Z "$sha" wp/x completed failure
check "e2e rot" 1
reset; green e2e; row gate 2030-01-01T10:00:00Z "$sha" wp/x completed failure
check "gate rot" 1
reset; green gate; row e2e 2030-01-01T10:00:00Z "$other" wp/x completed success
check "e2e auf anderem SHA" 1
reset; green gate; row e2e 2030-01-01T10:00:00Z "$sha" wp/anders completed success
check "e2e auf anderem Branch" 1
reset; green gate; green e2e; row e2e 2030-01-01T11:00:00Z "$sha" wp/x in_progress ""
check "neuester e2e in_progress (älterer grün)" 1
reset; green gate; green e2e; row e2e 2030-01-01T11:00:00Z "$sha" wp/x completed cancelled
check "neuester e2e abgebrochen (älterer grün)" 1
reset; green gate; row e2e 2030-01-01T10:00:00Z "$sha" wp/x completed failure; row e2e 2030-01-01T11:00:00Z "$sha" wp/x completed success
check "neuester e2e grün (älterer rot)" 0
[ "$fails" -eq 0 ] || { echo "$fails Fälle rot"; exit 1; }
echo "merge_wp_test: alle Fälle ok"
