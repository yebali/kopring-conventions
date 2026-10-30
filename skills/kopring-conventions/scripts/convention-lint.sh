#!/usr/bin/env bash
# Detector for the mechanically-greppable subset of the kopring-conventions Hard Rules.
# Report-only — no fix mode. Run from anywhere inside a Kotlin/Spring repository.
#
#   bash convention-lint.sh              # whole tree (src/main/kotlin + src/test/kotlin of every module)
#   bash convention-lint.sh a.kt b.kt    # only these files (main/test decided by their path)
#   → prints `path:line: [ID] message`, exits 1 if any, 2 if no Kotlin source file was scanned
#
#   BASE_PACKAGE=com.acme bash convention-lint.sh   # root package for the STY-2 FQN check;
#                                                   # default: first two segments of the first `package` line
#
# Project exceptions: `.convention-lint-ignore` at the repository root, one `path-glob:ID` per line
# (`#` comments allowed), e.g. `common-core/src/main/kotlin/*:SVC-15`. A hit whose path matches the
# glob and whose ID matches is dropped. Keep each entry backed by the project's own rule document.
#
# Implemented rules (scope · blind spots):
#   STY-1  LoggerFactory, KotlinLogging.logger (main). Not flagged: the file defining the `Logger` base
#       class, and the carve-out form `private val log = KotlinLogging.logger {}` (agent-judged).
#   STY-2  FQN in code — `$BASE_PACKAGE.` dotted path ending in an uppercase identifier on
#       non-import/non-package lines (main + test). Excluded: comment lines and occurrences preceded
#       by a quote/backtick/bracket (KDoc cross-refs, @MethodSource strings). Blind spot: FQNs of
#       other packages (java.util.UUID …).
#   STY-7  `!!` (main + test). Blind spot: `!!` inside a string or comment false-positives.
#   STY-8  @Suppress("UNCHECKED_CAST") (main + test).
#   STY-17 history word in a comment (기존에는 · 예전에는 · 이전에는 · 바뀌었다 · 옮겼다 · 대체했다) (main + test).
#       A rationale written without one of these words stays agent-judged.
#   STY-30 ZoneId.systemDefault() (main).
#   STY-43 Executors.new* (main).
#   STY-45 a retry predicate defaulting to `{ true }` (main).
#   STY-58 no-argument `ZonedDateTime/OffsetDateTime/LocalDateTime/LocalDate/Instant.now()` (main).
#   SVC-13 Hangul inside a thrown message — `throw X(…)`, `require`, `check`, `requireNotNull`,
#       `checkNotNull`, `error(` not called on a receiver (main). Blind spot: a message built on a later line.
#   SVC-15 direct throw of a generic/base exception (main, `*Service.kt` and `service/command/` only).
#       Blind spot: generics thrown from a lambda (`orElseThrow { NoSuchElementException(…) }`).
#   SVC-20 @Lazy (main).
#   SVC-24 `.constraintName` — Hibernate's message-parsed constraint name (main).
#   SVC-34 `fallbackExecution = true` on an AFTER_ROLLBACK/AFTER_COMPLETION listener, or an AFTER_COMMIT/
#       BEFORE_COMMIT listener without it (main). Blind spot: an annotation whose arguments span lines.
#   TX-1   class-level @Transactional — column-0 heuristic (main only; test classes may carry it).
#   CTL-3  `required = false` (main).
#   CTL-10 @Operation( / @Tag( (main).
#   CTL-12 Include.NON_NULL (main).
#   CTL-14 Bean Validation — `import jakarta.validation` / `import javax.validation`, `@Validated` (main).
#   CTL-18 @ResponseStatus other than CREATED / NO_CONTENT (main).
#   CTL-19 @PatchMapping (main).
#   REP-1  @Query / @Modifying (main).
#   REP-3  stereotype on Custom*RepositoryImpl (main).
#   REP-4  @Transactional on Custom*RepositoryImpl (main).
#   REP-10 PageImpl( (main).
#   REP-14 @Column(… unique = true …) (main).
#   REP-15 @ManyToOne without FetchType.LAZY (main). Blind spot: an annotation whose arguments span lines.
#   REP-27 @SQLRestriction / @SQLDelete / @Where( (main).
#   REP-30 a bulk delete named `deleteAllBy*` in Custom*RepositoryImpl (main).
#   TST-6  @DisplayName (test).
#   TST-7  restoreSharedDoubles (test).
#   TST-21 stdlib `assert(` and JUnit/kotlin.test assertEquals/assertTrue/assertFalse/assertNull/
#       assertNotNull/assertThrows (test).
#   TST-27 `relaxed = true` (test).
#   TST-33 @DirtiesContext / @TestPropertySource / @ActiveProfiles / @WebMvcTest / @DataJpaTest outside
#       *TestSupport.kt (test). The migration guard test of COV-10 goes in `.convention-lint-ignore`.
#
# Stays agent-judged (deliberately not here): STY-9 lambda layout, Thread.sleep in tests (TST-29
# tolerates createdAt spacing), everything else in the Hard Rules tables. STY-10 has its own script,
# blank-line-before-return.sh.
set -uo pipefail
# [가-힣] 범위가 다른 멀티바이트 문자에 걸리지 않도록 설치된 UTF-8 로케일로 grep 한다
for loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if locale -a 2>/dev/null | grep -qx "$loc"; then export LC_ALL=$loc; break; fi
done

ALL=$(mktemp) MAIN=$(mktemp) TEST=$(mktemp) SRC=$(mktemp) REPO_IMPL=$(mktemp) SVC=$(mktemp) OUT=$(mktemp)
trap 'rm -f "$ALL" "$MAIN" "$TEST" "$SRC" "$REPO_IMPL" "$SVC" "$OUT"' EXIT

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ "$#" -gt 0 ]; then
  for f in "$@"; do case "$f" in *.kt) [ -f "$f" ] && printf '%s\n' "$f" ;; esac; done > "$ALL"
else
  cd "$ROOT" || exit 2
  find . -name '*.kt' -not -path '*/build/*' \( -path '*/src/main/kotlin/*' -o -path '*/src/test/kotlin/*' \) | sort > "$ALL"
fi
grep -E '(^|/)src/main/kotlin/' "$ALL" > "$MAIN"
grep -E '(^|/)src/test/kotlin/' "$ALL" > "$TEST"
cat "$MAIN" "$TEST" > "$SRC"
if [ ! -s "$SRC" ]; then
  echo "convention-lint: no Kotlin source file under src/main/kotlin or src/test/kotlin was scanned" >&2
  exit 2
fi
grep '/Custom[^/]*RepositoryImpl\.kt$' "$MAIN" > "$REPO_IMPL"
grep -E 'Service\.kt$|/service/command/' "$MAIN" > "$SVC"

g() { [ -s "$1" ] && tr '\n' '\0' < "$1" | xargs -0 grep -nHE "$2"; }   # file-list, pattern → file:line:content
fmt() { awk -v m="$1" -F: '{print $1 ":" $2 ": " m}' >> "$OUT"; }

ANNOT_END='(\(|[[:space:]]|$)'                               # annotation not a prefix of a longer one

g "$SRC" '!!'                             | fmt '[STY-7] !! forbidden — use requireNotNull(x) { "<context>" }'
g "$MAIN" '@Query\(|@Modifying'           | fmt '[REP-1] @Query/@Modifying prohibited — derived query → QueryDSL Custom*Repository'
g "$MAIN" '@ResponseStatus'               | grep -vE 'HttpStatus\.(CREATED|NO_CONTENT)\)' | fmt '[CTL-18] @ResponseStatus only CREATED (creating POST) or NO_CONTENT (body-less PUT/DELETE) — everything else is default 200 OK'
g "$MAIN" "import (jakarta|javax)\.validation|@Validated$ANNOT_END" | fmt '[CTL-14] Bean Validation prohibited — Command.init{} / Service check*()'
g "$SRC" '@Suppress\("UNCHECKED_CAST"\)'  | fmt '[STY-8] UNCHECKED_CAST suppress forbidden — use type-safe expressions'
g "$MAIN" "^@Transactional$ANNOT_END"     | fmt '[TX-1] class-level @Transactional forbidden — method-level in Service only'

g "$SVC" 'throw (BusinessException|IllegalStateException|IllegalArgumentException|RuntimeException|Exception|UnsupportedOperationException)\(' |
    fmt '[SVC-15] generic/base exception thrown directly — use a named domain subclass with dedicated ErrorCode'

g "$MAIN" 'required[[:space:]]*=[[:space:]]*false' | fmt '[CTL-3] required = false forbidden — make the parameter nullable'
g "$MAIN" "@PatchMapping$ANNOT_END"       | fmt '[CTL-19] PATCH forbidden — a PUT replaces the whole resource'
g "$MAIN" '@Operation\(|@Tag\('           | fmt '[CTL-10] @Operation/@Tag forbidden — descriptions live on properties and parameters'
g "$MAIN" 'Include\.NON_NULL'             | fmt '[CTL-12] NON_NULL forbidden — responses serialize null fields'
g "$MAIN" "@Lazy$ANNOT_END"               | fmt '[SVC-20] @Lazy forbidden — move the unnatural dependency edge'
g "$MAIN" 'ZoneId\.systemDefault\(\)'     | fmt '[STY-30] ZoneId.systemDefault() forbidden — use the application time zone'
g "$MAIN" 'Executors\.new'                | fmt '[STY-43] Executors.new* inside a bean forbidden — use a Spring-managed executor'
g "$MAIN" 'PageImpl\('                    | fmt '[REP-10] PageImpl forbidden — PageableExecutionUtils.getPage / Page.empty'
g "$MAIN" "@SQLRestriction|@SQLDelete|@Where\(" | fmt '[REP-27] global soft-delete filter forbidden — state deletedAt.isNull in the query'
g "$MAIN" '[Rr]etryable[^=]*=[[:space:]]*\{[[:space:]]*true[[:space:]]*\}' | fmt '[STY-45] retry predicate defaults to true — the caller must state what is safe to retry'
g "$MAIN" '(ZonedDateTime|OffsetDateTime|LocalDateTime|LocalDate|Instant)\.now\(\)' | fmt '[STY-58] no-argument now() — read the time from the injected Clock'
g "$MAIN" '\.constraintName' | fmt '[SVC-24] constraint name parsed from the message — read PSQLException.serverErrorMessage.constraint'
LISTENER='@TransactionalEventListener([[:space:]]|$|\([^)]*\))'
g "$MAIN" "$LISTENER" | grep -E 'AFTER_ROLLBACK|AFTER_COMPLETION' | grep -E 'fallbackExecution[[:space:]]*=[[:space:]]*true' |
    fmt '[SVC-34] fallbackExecution on a rollback/completion listener — it would run although nothing rolled back'
g "$MAIN" "$LISTENER" | grep -vE 'AFTER_ROLLBACK|AFTER_COMPLETION|fallbackExecution' |
    fmt '[SVC-34] AFTER_COMMIT/BEFORE_COMMIT listener without fallbackExecution = true'
g "$MAIN" '@Column\([^)]*unique[[:space:]]*=[[:space:]]*true' | fmt '[REP-14] @Column(unique = true) — declare a named @Table(uniqueConstraints), none on a soft-delete column'
g "$MAIN" '@ManyToOne([[:space:]]|$|\([^)]*\))' | grep -v 'FetchType\.LAZY' | fmt '[REP-15] @ManyToOne without fetch = FetchType.LAZY — the JPA default is EAGER'
g "$REPO_IMPL" 'fun deleteAllBy'          | fmt '[REP-30] bulk delete named deleteAllBy* — name it bulkDeleteBy*'

BASE_PACKAGE=${BASE_PACKAGE:-}
if [ -z "$BASE_PACKAGE" ]; then
  BASE_PACKAGE=$(tr '\n' '\0' < "$SRC" | xargs -0 grep -h -m1 '^package ' 2>/dev/null | head -1 |
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

LOGGER_BASE=$(g "$MAIN" '^(abstract |open )?class Logger([^A-Za-z0-9_]|$)' | cut -d: -f1 | sort -u)
g "$MAIN" 'LoggerFactory|KotlinLogging\.logger' |
    grep -vE ':[0-9]+:[[:space:]]*private val log = KotlinLogging\.logger' |
    { if [ -n "$LOGGER_BASE" ]; then grep -vF "$LOGGER_BASE"; else cat; fi; } |
    fmt '[STY-1] use the project logger idiom (inherited `logger`) — never LoggerFactory or a per-class KotlinLogging.logger'
g "$MAIN" '"[^"]*[가-힣]' | sed -E 's#[[:space:]]//[[:space:]].*$##' |
    grep -E ':[0-9]+:.*(throw [A-Z][A-Za-z]*\(|[^.A-Za-z_](require|check|requireNotNull|checkNotNull|error)\().*"[^"]*[가-힣]' |
    fmt '[SVC-13] thrown message must be English — Korean belongs in the line comment'

HIST='(//|/\*\*|^[[:space:]]*\*).*(기존에는|예전에는|이전에는|바뀌었다|옮겼다|대체했다)'
g "$SRC" "$HIST" | fmt '[STY-17] comment states history — current state only; history goes to the commit body'

g "$REPO_IMPL" "@(Repository|Component)$ANNOT_END" | fmt '[REP-3] stereotype on Custom*RepositoryImpl forbidden — *Impl suffix auto-registers'
g "$REPO_IMPL" "@Transactional$ANNOT_END"          | fmt '[REP-4] @Transactional on Custom*RepositoryImpl forbidden — transaction boundary belongs to the calling Service'

g "$TEST" '@DisplayName'                  | fmt '[TST-6] @DisplayName forbidden — the Korean backtick method name carries the description'
g "$TEST" '(^|[^.A-Za-z])(assert|assertEquals|assertTrue|assertFalse|assertNull|assertNotNull|assertThrows)\(' |
    fmt '[TST-21] non-AssertJ assertion forbidden — AssertJ assertThat shows actual vs expected'
g "$TEST" 'relaxed[[:space:]]*=[[:space:]]*true' | fmt '[TST-27] relaxed mock forbidden — strict mocks, relaxUnitFun = true only'
g "$TEST" 'restoreSharedDoubles'          | fmt '[TST-7] restoreSharedDoubles is obsolete — springmockk clears shared mocks after each test'
g "$TEST" "@(DirtiesContext|TestPropertySource|ActiveProfiles|WebMvcTest|DataJpaTest)$ANNOT_END" | grep -v 'TestSupport\.kt:' |
    fmt '[TST-33] forks the shared Spring context — configure it once in the test support'

IGNORE="$ROOT/.convention-lint-ignore"
if [ -s "$OUT" ] && [ -f "$IGNORE" ]; then
  KEPT=$(mktemp)
  while IFS= read -r hit; do
    path=${hit%%:*}; path=${path#"$ROOT"/}; path=${path#./}
    id=$(printf '%s' "$hit" | sed -E 's/.*\[([A-Z]+-[0-9]+)\].*/\1/')
    drop=0
    while IFS= read -r entry; do
      case "$entry" in ''|'#'*) continue ;; esac
      pat=${entry%:*}; pat=${pat#./}; eid=${entry##*:}
      # shellcheck disable=SC2254
      case "$path" in $pat) [ "$eid" = "$id" ] && { drop=1; break; } ;; esac
    done < "$IGNORE"
    [ "$drop" -eq 0 ] && printf '%s\n' "$hit"
  done < "$OUT" > "$KEPT"
  mv "$KEPT" "$OUT"
fi

total=$(wc -l < "$OUT" | tr -d ' ')
[ -s "$OUT" ] && sort -t: -k1,1 -k2,2n "$OUT"
echo "---"
echo "total: $total"
[ "$total" -gt 0 ] && exit 1
exit 0
