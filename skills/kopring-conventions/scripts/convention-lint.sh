#!/usr/bin/env bash
# Detector for the mechanically-greppable subset of the kopring-conventions Hard Rules.
# Report-only — no fix mode. Run from anywhere inside a Kotlin/Spring repository.
#
#   bash convention-lint.sh              # whole tree (src/main/kotlin + src/test/kotlin of every module)
#   bash convention-lint.sh a.kt b.kt    # only these files (main/test decided by their path)
#   → prints `path:line: [ID] message`, exits 1 if any
#
#   BASE_PACKAGE=com.acme bash convention-lint.sh   # root package for the STY-2 FQN check;
#                                                   # default: first two segments of the first main `package` line
#
# Implemented rules (scope · blind spots):
#   STY-1  LoggerFactory (main).
#   STY-2  FQN in code — `$BASE_PACKAGE.` dotted path ending in an uppercase identifier on
#       non-import/non-package lines (main + test). Excluded: comment lines and occurrences preceded
#       by a quote/backtick/bracket (KDoc cross-refs, @MethodSource strings). Blind spot: FQNs of
#       other packages (java.util.UUID …).
#   STY-7  `!!` (main + test). Blind spot: `!!` inside a string or comment false-positives.
#   STY-8  @Suppress("UNCHECKED_CAST") (main + test).
#   STY-17 history word in a comment (기존에는 · 예전에는 · 이전에는 · 바뀌었다 · 옮겼다 · 대체했다) (main + test).
#       A rationale written without one of these words stays agent-judged.
#   SVC-13 Hangul inside a thrown message — `throw X(…)`, `require`, `check`, `requireNotNull`,
#       `checkNotNull`, `error(` (main). Blind spot: a message built on a later line.
#   SVC-15 direct throw of a generic/base exception (main). Blind spot: generics thrown from a
#       lambda (`orElseThrow { NoSuchElementException(…) }`).
#   TX-1   class-level @Transactional — column-0 heuristic (main only; test classes may carry it).
#   CTL-14 Bean Validation — `import jakarta.validation` (main).
#   CTL-18 @ResponseStatus other than CREATED / NO_CONTENT (main).
#   REP-1  @Query / @Modifying (main).
#   REP-3  stereotype on Custom*RepositoryImpl (main).
#   REP-4  @Transactional on Custom*RepositoryImpl (main).
#   TST-6  @DisplayName (test).   TST-21  stdlib `assert(` (test).
#
# Stays agent-judged (deliberately not here): STY-9 lambda layout, Thread.sleep in tests (TST-29
# tolerates createdAt spacing), everything else in the Hard Rules tables.
set -uo pipefail
# [가-힣] 범위가 다른 멀티바이트 문자에 걸리지 않도록 UTF-8 로케일로 grep 한다
export LC_ALL=C.UTF-8

ALL=$(mktemp) MAIN=$(mktemp) TEST=$(mktemp) SRC=$(mktemp) REPO_IMPL=$(mktemp) OUT=$(mktemp)
trap 'rm -f "$ALL" "$MAIN" "$TEST" "$SRC" "$REPO_IMPL" "$OUT"' EXIT

if [ "$#" -gt 0 ]; then
  for f in "$@"; do case "$f" in *.kt) [ -f "$f" ] && printf '%s\n' "$f" ;; esac; done > "$ALL"
else
  cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2
  find . -name '*.kt' -not -path '*/build/*' \( -path '*/src/main/kotlin/*' -o -path '*/src/test/kotlin/*' \) | sort > "$ALL"
fi
grep -E '(^|/)src/main/kotlin/' "$ALL" > "$MAIN"
grep -E '(^|/)src/test/kotlin/' "$ALL" > "$TEST"
cat "$MAIN" "$TEST" > "$SRC"
grep '/Custom[^/]*RepositoryImpl\.kt$' "$MAIN" > "$REPO_IMPL"

g() { [ -s "$1" ] && tr '\n' '\0' < "$1" | xargs -0 grep -nHE "$2"; }   # file-list, pattern → file:line:content
fmt() { awk -v m="$1" -F: '{print $1 ":" $2 ": " m}' >> "$OUT"; }

ANNOT_END='(\(|[[:space:]]|$)'                               # annotation not a prefix of a longer one

g "$SRC" '!!'                             | fmt '[STY-7] !! forbidden — use requireNotNull(x) { "<context>" }'
g "$MAIN" '@Query\(|@Modifying'           | fmt '[REP-1] @Query/@Modifying prohibited — derived query → QueryDSL Custom*Repository'
g "$MAIN" '@ResponseStatus'               | grep -vE 'HttpStatus\.(CREATED|NO_CONTENT)\)' | fmt '[CTL-18] @ResponseStatus only CREATED (creating POST) or NO_CONTENT (body-less PUT/DELETE) — everything else is default 200 OK'
g "$MAIN" 'import jakarta\.validation'    | fmt '[CTL-14] Bean Validation prohibited — Command.init{} / Service check*()'
g "$SRC" '@Suppress\("UNCHECKED_CAST"\)'  | fmt '[STY-8] UNCHECKED_CAST suppress forbidden — use type-safe expressions'
g "$MAIN" "^@Transactional$ANNOT_END"     | fmt '[TX-1] class-level @Transactional forbidden — method-level in Service only'

g "$MAIN" 'throw (BusinessException|IllegalStateException|IllegalArgumentException|RuntimeException|Exception|UnsupportedOperationException)\(' |
    fmt '[SVC-15] generic/base exception thrown directly — use a named domain subclass with dedicated ErrorCode'

BASE_PACKAGE=${BASE_PACKAGE:-}
if [ -z "$BASE_PACKAGE" ] && [ -s "$MAIN" ]; then
  BASE_PACKAGE=$(tr '\n' '\0' < "$MAIN" | xargs -0 grep -h -m1 '^package ' 2>/dev/null | head -1 |
      sed -E 's/^package[[:space:]]+([A-Za-z0-9_]+(\.[A-Za-z0-9_]+)?).*/\1/')
fi
if [ -n "$BASE_PACKAGE" ]; then
  BP=$(printf '%s' "$BASE_PACKAGE" | sed 's/\./\\./g')
  g "$SRC" "$BP\.([a-z][A-Za-z0-9]*\.)+[A-Z][A-Za-z0-9]*" |
      grep -vE ':[0-9]+:[[:space:]]*(import|package)[[:space:]]' |
      grep -vE ':[0-9]+:[[:space:]]*(\*|//|/\*)' |
      grep -vE "[\"\`\\[]$BP" |
      fmt '[STY-2] FQN in code — use an import statement'
fi

g "$MAIN" 'LoggerFactory' | fmt '[STY-1] use the project logger idiom (inherited `logger`) — never LoggerFactory'
g "$MAIN" '"[^"]*[가-힣]' | sed -E 's#[[:space:]]//[[:space:]].*$##' |
    grep -E ':[0-9]+:.*(throw [A-Z][A-Za-z]*\(|require\(|check\(|requireNotNull\(|checkNotNull\(|error\().*"[^"]*[가-힣]' |
    fmt '[SVC-13] thrown message must be English — Korean belongs in the line comment'

HIST='(//|/\*\*|^[[:space:]]*\*).*(기존에는|예전에는|이전에는|바뀌었다|옮겼다|대체했다)'
g "$SRC" "$HIST" | fmt '[STY-17] comment states history — current state only; history goes to the commit body'

g "$REPO_IMPL" "@(Repository|Component)$ANNOT_END" | fmt '[REP-3] stereotype on Custom*RepositoryImpl forbidden — *Impl suffix auto-registers'
g "$REPO_IMPL" "@Transactional$ANNOT_END"          | fmt '[REP-4] @Transactional on Custom*RepositoryImpl forbidden — transaction boundary belongs to the calling Service'

g "$TEST" '@DisplayName'                  | fmt '[TST-6] @DisplayName forbidden — the Korean backtick method name carries the description'
g "$TEST" '(^|[^.A-Za-z])assert\('        | fmt '[TST-21] stdlib assert() forbidden — AssertJ assertThat shows actual vs expected'

total=$(wc -l < "$OUT" | tr -d ' ')
[ -s "$OUT" ] && sort -t: -k1,1 -k2,2n "$OUT"
echo "---"
echo "total: $total"
[ "$total" -gt 0 ] && exit 1
exit 0
