#!/usr/bin/env bash
# Self-check for the lint scripts. Builds a throwaway git repo from fixtures/ (each fixtures/<module>/*.kt
# lands in <module>/src/main/kotlin/x/), runs the scripts in it and compares their hits with the
# `// HIT <ID>` markers in the fixtures. Prints PASS/FAIL per case; exits 1 on any failure.
#
#   bash scripts/tests/run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd -P)
S=${HERE%/*}
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
cd "$T" || exit 1

for dir in "$HERE"/fixtures/*/; do
  m=${dir%/}; m=${m##*/}
  mkdir -p "$m/src/main/kotlin/x" && cp "$dir"*.kt "$m/src/main/kotlin/x/"
done
cp "$HERE/fixtures/convention-lint-ignore" .convention-lint-ignore
commit() { git -c user.name=t -c user.email=t@t -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -qm "$1"; }
git init -q && git symbolic-ref HEAD refs/heads/main && git add -A && commit base

X=m/src/main/kotlin/x
fail=0
check() {  # name expected actual
  if [ "$2" = "$3" ]; then echo "PASS  $1"; else printf 'FAIL  %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"; fail=1; fi
}
marks() {  # tag-regex file… → the `// HIT <tag>` markers as sorted `path:line`
  local tag=$1; shift
  grep -nE "// HIT ($tag)\$" "$@" /dev/null | cut -d: -f1,2 | LC_ALL=C sort | tr '\n' ' '
}
hits() {  # tag-regex script arg… → the script's hits with that tag as sorted `path:line` (STY-10 hits carry no tag)
  local tag=$1; shift
  bash "$S/$1" "${@:2}" | grep -E "^[^ :]+:[0-9]+(: \[($tag)\]|\$)" | cut -d: -f1,2 | LC_ALL=C sort | tr '\n' ' '
}

# STY-10, run from the module directory with relative paths — hits are reported from the repo root
for c in EarlyReturnInIf WhenBranchReturn FinalReturn MultiLineSignature MultiLineReturn; do
  check "STY-10 $c" "$(marks STY-10 $X/$c.kt)" "$(cd m && hits STY-10 blank-line-before-return.sh src/main/kotlin/x/$c.kt)"
done
bash "$S/blank-line-before-return.sh" --fix $X/*.kt >/dev/null
check "STY-10 --fix inserts one line per hit only" "1 0 $X/FinalReturn.kt 1 0 $X/MultiLineSignature.kt " "$(git diff --numstat | tr '\t\n' '  ')"
git checkout -q -- .

# STY-12
for c in TwoClasses SealedResult OrderLine MailConfig TextFormat; do
  check "STY-12 $c" "$(marks STY-12 $X/$c.kt)" "$(hits STY-12 convention-lint.sh $X/$c.kt)"
done
check "STY-12 message" "$(marks STY-12 $X/TwoClasses.kt | tr -d ' '): [STY-12] 2 top-level types (Foo, Bar)" \
  "$(bash "$S/convention-lint.sh" $X/TwoClasses.kt | grep STY-12)"

# SVC-13 — Hangul in a thrown message, matched as UTF-8 bytes so GNU grep in C.UTF-8 does not drop it
check "SVC-13 KoreanMessage" "$(marks SVC-13 $X/KoreanMessage.kt)" "$(hits SVC-13 convention-lint.sh $X/KoreanMessage.kt)"

# .convention-lint-ignore — a path:ID entry from a module directory, and `legacy/*:*` over the whole tree
check "ignore from a module dir, relative paths" "$(marks REP-10 $X/PagedKept.kt)" \
  "$(cd m && hits '[A-Z]+-[0-9]+' convention-lint.sh src/main/kotlin/x/Paged.kt src/main/kotlin/x/PagedKept.kt)"
check "whole tree: convention-lint hits = markers (legacy/* ignored)" "$(marks 'REP-10|STY-12|SVC-13' $X/*.kt)" "$(hits '[A-Z]+-[0-9]+' convention-lint.sh)"
check "whole tree: STY-10 hits = markers (legacy/* ignored)" "$(marks STY-10 $X/*.kt)" "$(hits STY-10 blank-line-before-return.sh)"

# changed-files.sh — committed on the branch, modified, untracked; README and the `*`-ignored tree left out
git checkout -q -b feature
echo 'class Committed' > $X/Committed.kt && git add -A && commit feature
echo 'class New' > $X/New.kt
echo 'class New' > legacy/src/main/kotlin/x/New.kt
mkdir -p m/src/main/resources && echo 'a: 1' > m/src/main/resources/application.yml
echo '# m' > m/README.md
echo '// edited' >> $X/TextFormat.kt
check "changed-files paths" "$X/Committed.kt $X/New.kt $X/TextFormat.kt m/src/main/resources/application.yml " \
  "$(bash "$S/changed-files.sh" 2>/dev/null | tr '\n' ' ')"
check "changed-files base" "base: main" "$(bash "$S/changed-files.sh" 2>&1 >/dev/null)"

exit "$fail"
