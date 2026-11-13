#!/bin/sh
# Test für die Tag-Regel von tool/hooks/pre-push (WP30): Aufruf: sh tool/hooks/pre-push_test.sh
# Legt ein temporäres Repo mit refs/remotes/origin/main an und ruft den Hook mit stdin wie Git auf.
hook=$(cd "$(dirname "$0")" && pwd)/pre-push
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
git init -q . || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
git config commit.gpgsign false
git commit -q --allow-empty -m a && git commit -q --allow-empty -m b || exit 1
inmain=$(git rev-parse HEAD)
git update-ref refs/remotes/origin/main "$inmain"
git commit -q --allow-empty -m c || exit 1
outside=$(git rev-parse HEAD)
git tag -a -m ann v0.1.0-rc1 "$inmain"
git tag -a -m ann v9.9.9-ann "$outside"
git tag v9.9.9-light "$outside"
zero=0000000000000000000000000000000000000000
fails=0
# check <ok|rejected> <Name> <stdin-Zeile>
check() {
  want=$1 name=$2 line=$3
  printf '%s\n' "$line" | sh "$hook" origin url >/dev/null 2>&1; rc=$?
  if { [ "$want" = ok ] && [ $rc -eq 0 ]; } || { [ "$want" = rejected ] && [ $rc -ne 0 ]; }; then
    echo "OK   $name"
  else
    echo "FAIL $name (rc=$rc)"; fails=$((fails + 1))
  fi
}
check ok       "leichter Tag auf Commit in origin/main" "refs/tags/v0.1.0 $inmain refs/tags/v0.1.0 $zero"
check ok       "annotierter Tag auf Commit in origin/main" "refs/tags/v0.1.0-rc1 $(git rev-parse v0.1.0-rc1) refs/tags/v0.1.0-rc1 $zero"
check rejected "leichter Tag außerhalb origin/main" "refs/tags/v9.9.9-light $outside refs/tags/v9.9.9-light $zero"
check rejected "annotierter Tag außerhalb origin/main" "refs/tags/v9.9.9-ann $(git rev-parse v9.9.9-ann) refs/tags/v9.9.9-ann $zero"
check ok       "Tag-Löschung" "(delete) $zero refs/tags/v9.9.9-ann $outside"
check ok       "Nicht-Release-Tag außerhalb origin/main" "refs/tags/foo $outside refs/tags/foo $zero"
check ok       "wp-Branch unverändert frei" "refs/heads/wp/1-x $outside refs/heads/wp/1-x $zero"
git update-ref -d refs/remotes/origin/main
check rejected "Release-Tag ohne origin/main" "refs/tags/v0.1.0 $inmain refs/tags/v0.1.0 $zero"
[ $fails -eq 0 ] && echo "pre-push Tag-Test GRÜN" || { echo "pre-push Tag-Test ROT"; exit 1; }
