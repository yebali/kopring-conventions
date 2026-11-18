#!/usr/bin/env bash
# Detector for the mechanically-greppable subset of the kopring-conventions Hard Rules.
# Report-only — no fix mode. Run from anywhere inside a Kotlin/Spring repository.
#
#   bash convention-lint.sh              # whole tree (src/main/kotlin + src/test/kotlin of every module)
#   bash convention-lint.sh a.kt b.kt    # only these files (main/test decided by their path; relative to the
#                                        # current directory or absolute — hits are reported relative to the repo root)
#   → prints `path:line: [ID] message`, exits 1 if any, 2 if no Kotlin source file was scanned
#
#   BASE_PACKAGE=com.acme bash convention-lint.sh   # root package for the STY-2 FQN check;
#                                                   # default: first two segments of the first `package` line
#
# Project exceptions: `.convention-lint-ignore` at the repository root, one `path-glob:ID` per line
# (`#` comments allowed), e.g. `common-core/src/main/kotlin/*:SVC-15`. A hit whose path matches the
# glob and whose ID matches is dropped; the ID `*` matches every rule (`legacy-module/*:*` exempts a whole
# tree, and changed-files.sh leaves it out too). Keep each entry backed by the project's own rule document.
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
#   STY-12 2+ top-level types in one file — column-0 `class` (any modifier) / `object` / `interface` (main + test),
#       reported at the second declaration. A carve-out is judged by declaration shape: a sealed type whose
#       other types list it among their supertypes, an @Entity with the type its @IdClass(X::class) names, a
#       @Configuration with only @ConfigurationProperties classes, one `object` with only `enum class`es
#       (`fun main` is no type, so the @SpringBootApplication carve-out needs no check). Blind spots: whether
#       the @Configuration really binds the properties class, a deeper sealed level (a subtype of a subtype is
#       a hit), a supertype on a line after the header that does not follow a trailing comma, annotations
#       separated from the declaration by a comment or blank line, a declaration inside a raw string.
#   STY-17 history word in a comment (기존에는 · 예전에는 · 이전에는 · 바뀌었다 · 옮겼다 · 대체했다) (main + test).
#       A rationale written without one of these words stays agent-judged.
#   STY-30 ZoneId.systemDefault() (main).
#   STY-36 `$command` / `$request` / `$properties` interpolated whole into a logger line (main).
#   STY-43 Executors.new* (main).
#   STY-45 a retry predicate defaulting to `{ true }` (main).
#   STY-58 no-argument `ZonedDateTime/OffsetDateTime/LocalDateTime/LocalDate/Instant.now()` (main).
#   STY-59 in a file with a column-0 bean stereotype: a member `private|protected|internal var`, or such a
#       `val` initialised with a plain mutable collection, unless @Volatile (main). Not flagged: a
#       `lateinit var` (the lifecycle handle the rule allows). Blind spots: a public `var`, a prototype- or
#       request-scoped bean, a meta-annotated stereotype.
#   SVC-9  `fun validate*` (main; an `override` is skipped).
#   SVC-13 Hangul inside a thrown message — `throw X(…)`, `requireValid`, `require`, `check`, `requireNotNull`,
#       `checkNotNull`, `error(` not called on a receiver (main). Blind spot: a message built on a later line.
#   SVC-15 direct throw of a generic/base exception (main, `*Service.kt` and `service/command/` only).
#       Blind spot: generics thrown from a lambda (`orElseThrow { NoSuchElementException(…) }`).
#   SVC-20 @Lazy (main).
#   SVC-24 `.constraintName` — Hibernate's message-parsed constraint name (main).
#   SVC-34 `fallbackExecution = true` on an AFTER_ROLLBACK/AFTER_COMPLETION listener, or an AFTER_COMMIT/
#       BEFORE_COMMIT listener without it (main). Blind spot: an annotation whose arguments span lines.
#   TX-1   a file with a class-level @Service but no class-level @Transactional, reported at @Service; a
#       class-level @Transactional in a file without @Service, reported at @Transactional (main). Blind spot: a
#       module without transactions, whose entry-point @Service goes in `.convention-lint-ignore`.
#   TX-2   a `val …: *Client` in a file with a class-level @Service (main). Blind spot: an outbound bean
#       whose type does not end in Client (a remote *Reader, a mail sender).
#   TX-18  @Transactional / @Async / @Retryable / @Cacheable / @CacheEvict / @CachePut on a `private fun` (main).
#       Blind spot: self-invocation of a public method stays agent-judged.
#   CTL-2  @RequestMapping("…") whose path does not start with /api/v<N> (main). Blind spots: the
#       `value = […]` form, and a controller mapped only at method level.
#   CTL-3  `required = false` (main).
#   CTL-6  `import ….entity.…` in a file under controller/rest/ (main).
#   CTL-10 @Operation( / @Tag( (main).
#   CTL-12 Include.NON_NULL (main).
#   CTL-14 Bean Validation — `import jakarta.validation` / `import javax.validation`, `@Validated` (main).
#   CTL-18 @ResponseStatus other than NO_CONTENT (main).
#   CTL-19 @PatchMapping (main).
#   REP-1  @Query / @Modifying (main).
#   REP-3  stereotype on Custom*RepositoryImpl (main).
#   REP-4  @Transactional on Custom*RepositoryImpl (main).
#   REP-8  a bulk delete named `deleteAllBy*` in Custom*RepositoryImpl; `fun get*` other than Spring Data's
#       own `getReferenceById` in *Repository.kt / *RepositoryImpl.kt (main).
#   REP-10 PageImpl( (main).
#   REP-14 @Column(… unique = true …) (main).
#   REP-15 @ManyToOne without FetchType.LAZY (main). Blind spot: an annotation whose arguments span lines.
#   REP-16 @Enumerated without EnumType.STRING on the same line (main).
#   REP-27 @SQLRestriction / @SQLDelete / @Where( / @SoftDelete (main).
#   REP-35 `data class` annotated @Entity / @Embeddable / @MappedSuperclass (main).
#   REP-40 `.between(` on a path named *At / *Date / *Time / *Timestamp (main).
#   REP-44 `fun findAllBy*` in *Repository.kt / *RepositoryImpl.kt (main). A Redis repository's derived
#       list read goes in `.convention-lint-ignore`.
#   REP-42 `Optional<`, `.orElseThrow`, `.orElseGet(`, `findById(…).get()/.isPresent/.isEmpty/.orElse(`
#       (main; an `override fun` signature is skipped). `getReferenceById` stays agent-judged.
#   CFG-15 a Kotlin default on a constructor property in *Properties.kt (main). Blind spot: a properties
#       class declared in its @Configuration's file.
#   TST-5  a backtick class name with Hangul (test).
#   TST-6  @DisplayName; a backtick `fun` name with Hangul; a @Test / @ParameterizedTest `fun` with a
#       plain name (test).
#   TST-21 stdlib `assert(` and JUnit/kotlin.test assertEquals/assertTrue/assertFalse/assertNull/
#       assertNotNull/assertThrows (test).
#   TST-26 restoreSharedDoubles (test).
#   TST-27 `relaxed = true` (test).
#   TST-31 Files.createTempDirectory / createTempFile without a parent directory, deleteOnExit( (test).
#       Blind spot: a prefix passed as a variable.
#   TST-33 @DirtiesContext / @TestPropertySource / @ActiveProfiles / @WebMvcTest / @DataJpaTest outside
#       *TestSupport.kt (test). The migration guard test of COV-10 goes in `.convention-lint-ignore`.
#
# Stays agent-judged (deliberately not here): STY-9 lambda layout, Thread.sleep in tests (TST-29
# tolerates createdAt spacing), STY-33 unit-suffixed constants (an annotation argument must be a number),
# STY-54 package names (a shared module may own an `api` package), REP-43 `findAll()` (most hits are
# tables bounded by design), everything else in the Hard Rules tables. STY-10 has its own script,
# blank-line-before-return.sh.
set -uo pipefail
# [가-힣] 범위가 다른 멀티바이트 문자에 걸리지 않도록 설치된 UTF-8 로케일로 grep 한다
for loc in C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8; do
  if locale -a 2>/dev/null | grep -qx "$loc"; then export LC_ALL=$loc; break; fi
done

ALL=$(mktemp) MAIN=$(mktemp) TEST=$(mktemp) SRC=$(mktemp) REPO_IMPL=$(mktemp) SVC=$(mktemp) OUT=$(mktemp)
REST=$(mktemp) REPO=$(mktemp) PROPS=$(mktemp) SVCBEAN=$(mktemp)
trap 'rm -f "$ALL" "$MAIN" "$TEST" "$SRC" "$REPO_IMPL" "$SVC" "$OUT" "$REST" "$REPO" "$PROPS" "$SVCBEAN"' EXIT

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
# every argument becomes a ROOT-relative path, whatever the current directory
for f in "$@"; do
  case "$f" in *.kt) [ -f "$f" ] || continue ;; *) continue ;; esac
  case "$f" in */*) d=${f%/*} ;; *) d=. ;; esac
  f=$(cd "$d" && pwd -P)/${f##*/}
  printf '%s\n' "${f#"$ROOT"/}"
done > "$ALL"
cd "$ROOT" || exit 2
if [ "$#" -eq 0 ]; then
  find . -name '*.kt' -not -path '*/build/*' \( -path '*/src/main/kotlin/*' -o -path '*/src/test/kotlin/*' \) |
      sed 's#^\./##' | sort > "$ALL"
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
grep -E '/controller/(.*/)?rest/' "$MAIN" > "$REST"
grep -E 'Repository(Impl)?\.kt$' "$MAIN" > "$REPO"
grep 'Properties\.kt$' "$MAIN" > "$PROPS"
CLASS_ANNOT='^(@[A-Za-z]+(\([^)]*\))? +)*'                 # annotations that may share the line, before the one looked for
[ -s "$MAIN" ] && tr '\n' '\0' < "$MAIN" | xargs -0 grep -lE "${CLASS_ANNOT}@Service([^A-Za-z0-9_]|\$)" > "$SVCBEAN"

g() { [ -s "$1" ] && tr '\n' '\0' < "$1" | xargs -0 grep -nHE "$2"; }   # file-list, pattern → file:line:content
# 한글 음절(U+AC00–U+D7A3)의 UTF-8 바이트 패턴 — C 로케일 grep 으로 쓴다. GNU grep 3.11 은 C.UTF-8 에서
# [가-힣] 범위를 "Invalid collation character" 로 거부해 검사가 조용히 빠진다
HANGUL=$(printf '(\352[\260-\277]|[\353\354][\200-\277]|\355[\200-\236])')
fmt() { awk -v m="$1" -F: '{print $1 ":" $2 ": " m}' >> "$OUT"; }

ANNOT_END='(\(|[[:space:]]|$)'                               # annotation not a prefix of a longer one

g "$SRC" '!!'                             | fmt '[STY-7] !! forbidden — use requireNotNull(x) { "<context>" }'
g "$MAIN" '@Query\(|@Modifying'           | fmt '[REP-1] @Query/@Modifying prohibited — derived query → QueryDSL Custom*Repository'
g "$MAIN" '@ResponseStatus'               | grep -vE 'HttpStatus\.NO_CONTENT\)' | fmt '[CTL-18] @ResponseStatus only NO_CONTENT — a creating POST returns ResponseEntity.created(location), an UPSERT selects 201/204 through ResponseEntity'
g "$MAIN" "import (jakarta|javax)\.validation|@Validated$ANNOT_END" | fmt '[CTL-14] Bean Validation prohibited — Command.init{} / Service check*()'
g "$SRC" '@Suppress\("UNCHECKED_CAST"\)'  | fmt '[STY-8] UNCHECKED_CAST suppress forbidden — use type-safe expressions'
# TX-1: per file, a class-level @Service needs a class-level @Transactional, and nothing else carries one
[ -s "$MAIN" ] && tr '\n' '\0' < "$MAIN" | xargs -0 awk -v pre="$CLASS_ANNOT" '
  function flush() {
    if (svc && !tx) print f ":" svc ": [TX-1] @Service without class-level @Transactional — annotate the class, readOnly = true on its read methods"
    if (tx && !svc) print f ":" tx ": [TX-1] class-level @Transactional on a bean that is not a @Service — a transaction is a Service method"
  }
  FNR == 1 { if (NR > 1) flush(); f = FILENAME; svc = 0; tx = 0 }
  $0 ~ pre "@Service([^A-Za-z0-9_]|$)" { svc = FNR }
  $0 ~ pre "@Transactional([^A-Za-z0-9_]|$)" { tx = FNR }
  END { if (NR > 0) flush() }
' >> "$OUT"
g "$SVCBEAN" '(^|[(,[:space:]])val [A-Za-z0-9_]+: [A-Za-z0-9_.]*Client([,)[:space:]]|$)' |
    fmt '[TX-2] outbound client injected into a @Service — call it from a Facade, a listener or the controller gate'

g "$SVC" 'throw (BusinessException|IllegalStateException|IllegalArgumentException|RuntimeException|Exception|UnsupportedOperationException)\(' |
    fmt '[SVC-15] generic/base exception thrown directly — use a named domain subclass with dedicated ErrorCode'

g "$MAIN" 'required[[:space:]]*=[[:space:]]*false' | fmt '[CTL-3] required = false forbidden — make the parameter nullable'
g "$MAIN" "@PatchMapping$ANNOT_END"       | fmt '[CTL-19] PATCH forbidden — PUT a complete body to the URI whose scope you change'
g "$MAIN" '@Operation\(|@Tag\('           | fmt '[CTL-10] @Operation/@Tag forbidden — descriptions live on properties and parameters'
g "$MAIN" 'Include\.NON_NULL'             | fmt '[CTL-12] NON_NULL forbidden — responses serialize null fields'
g "$MAIN" "@Lazy$ANNOT_END"               | fmt '[SVC-20] @Lazy forbidden — move the unnatural dependency edge'
g "$MAIN" 'ZoneId\.systemDefault\(\)'     | fmt '[STY-30] ZoneId.systemDefault() forbidden — use the application time zone'
g "$MAIN" 'Executors\.new'                | fmt '[STY-43] Executors.new* inside a bean forbidden — use a Spring-managed executor'
g "$MAIN" 'PageImpl\('                    | fmt '[REP-10] PageImpl forbidden — PageableExecutionUtils.getPage / Page.empty'
g "$MAIN" "@SQLRestriction|@SQLDelete|@Where\(|@SoftDelete$ANNOT_END" | fmt '[REP-27] soft-delete annotation that cannot be switched off — use the shared @Filter'
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
g "$REPO_IMPL" 'fun deleteAllBy'          | fmt '[REP-8] bulk delete named deleteAllBy* — name it bulkDeleteBy*'
g "$REPO" 'fun findAllBy[A-Z]'            | fmt '[REP-44] derived list query — the one listByQuery(List*Query) of the repository'
g "$REPO" '^[[:space:]]*(override[[:space:]]+)?fun get[A-Z]' | grep -v 'fun getReferenceById' | fmt '[REP-8] get* on a repository — find* for one row, list*/page* for several'
g "$MAIN" '@RequestMapping\("'           | grep -vE '@RequestMapping\("/api/v[0-9]+(/|")' | fmt '[CTL-2] endpoint outside /api/v1 — every controller is mapped under /api/v1'
g "$REST" '^import .*\.entity\.'          | fmt '[CTL-6] entity import in a Request/Response — build the Response from a Result'
g "$MAIN" "@Enumerated$ANNOT_END"         | grep -vE '\((value[[:space:]]*=[[:space:]]*)?(EnumType\.)?STRING\)' | fmt '[REP-16] @Enumerated without EnumType.STRING — the default stores the ordinal'
g "$MAIN" '(^|[[:space:]])fun validate[A-Z(]' | grep -v 'override' | fmt '[SVC-9] validate* prefix — check* throws, verify* returns a result'
g "$MAIN" '(logger|log)\.(debug|info|warn|error).*(\$\{(command|request|properties)\}|\$(command|request|properties)([^A-Za-z0-9_]|$))' |
    fmt '[STY-36] whole command/request/properties object in a log line — list the fields the message needs'
g "$PROPS" '(^[[:space:]]+(@[^ ]+ +)*val [A-Za-z0-9_]+: [^=]+ = [^/]*,[[:space:]]*(//.*)?$)|(class [^(]*\(.*val [A-Za-z0-9_]+: [^,)=]+ = )' |
    fmt '[CFG-15] Kotlin default on a properties field — the default lives in the yml placeholder'
g "$MAIN" '(At|Date|Time|Timestamp)\.between\(' | fmt '[REP-40] between on a time path includes both ends — goe(from) and lt(to)'
g "$MAIN" 'Optional<|\.orElseThrow|\.orElseGet\(|findById\([^)]*\)\.(get\(\)|isPresent|isEmpty|orElse\()' | grep -v 'override fun' |
    fmt '[REP-42] Optional in Kotlin code — findByIdOrNull(id) ?: throw'

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
LC_ALL=C g "$MAIN" "\"[^\"]*$HANGUL" | LC_ALL=C sed -E 's#[[:space:]]//[[:space:]].*$##' |
    LC_ALL=C grep -E ":[0-9]+:.*(throw [A-Z][A-Za-z]*\\(|[^.A-Za-z_](requireValid|require|check|requireNotNull|checkNotNull|error)\\().*\"[^\"]*$HANGUL" |
    fmt '[SVC-13] thrown message must be English — Korean belongs in the line comment'

HIST='(//|/\*\*|^[[:space:]]*\*).*(기존에는|예전에는|이전에는|바뀌었다|옮겼다|대체했다)'
g "$SRC" "$HIST" | fmt '[STY-17] comment states history — current state only; history goes to the commit body'

# STY-12: one awk pass over every source (BSD awk has no ENDFILE, so a file is judged when the next starts).
# Per type: its annotations (the `@` lines right above plus inline ones), its kind (`sealed interface`,
# `enum class` …), and its header up to the end of the primary constructor and supertype list.
tr '\n' '\0' < "$SRC" | xargs -0 awk '
  function supers(h,   n, k, part, out) {                 # " A B " — simple names of the supertypes
    while (gsub(/\([^()]*\)/, "", h)) ;
    sub(/\{.*/, "", h)
    while (gsub(/<[^<>]*>/, "", h)) ;
    if (!index(h, ":")) return " "
    h = substr(h, index(h, ":") + 1); sub(/ where .*/, "", h)
    n = split(h, part, ","); out = " "
    for (k = 1; k <= n; k++) { sub(/ by .*/, "", part[k]); gsub(/ /, "", part[k]); sub(/.*\./, "", part[k]); out = out part[k] " " }
    return out
  }
  function pairs(i, j) {                                  # may type j share a file with anchor type i?
    return (kind[i] ~ /sealed/ && index(supers(hdr[j]), " " name[i] " ")) ||
      (ann[i] ~ /@Entity([^A-Za-z0-9_]|$)/ && idc[i] == name[j]) ||
      (ann[i] ~ /@Configuration([^A-Za-z0-9_]|$)/ && ann[j] ~ /@ConfigurationProperties([^A-Za-z0-9_]|$)/) ||
      (kind[i] ~ /(^| )object $/ && kind[j] ~ /(^| )enum class $/)
  }
  function flush(   i, j, ok, names) {
    if (nt < 2) return
    for (i = 1; i <= nt; i++) {
      ok = 1
      for (j = 1; j <= nt; j++) if (j != i && !pairs(i, j)) ok = 0
      if (ok) return
    }
    names = name[1]; for (i = 2; i <= nt; i++) names = names ", " name[i]
    print f ":" at[2] ": [STY-12] " nt " top-level types (" names ")"
  }
  FNR == 1 { if (NR > 1) flush(); f = FILENAME; nt = 0; a = ""; cont = 0 }
  cont && /^[ )]/ {                                       # the rest of a multi-line declaration header
    hdr[nt] = hdr[nt] " " $0
    depth += gsub(/\(/, "(") - gsub(/\)/, ")"); cont = depth > 0 || /,[ ]*$/
    next
  }
  { cont = 0 }
  /^(@[A-Za-z0-9_.]+(\([^)]*\))? +)*((public|internal|private|protected|abstract|open|final|sealed|data|enum|annotation|value|inline|inner|expect|actual|fun|external) +)*(class|interface|object) +[A-Za-z_]/ {
    s = $0; sub(/^(@[A-Za-z0-9_.]+(\([^)]*\))? +)*/, "", s)
    match(s, /(class|interface|object) +[A-Za-z_][A-Za-z0-9_]*/)
    nm = substr(s, RSTART, RLENGTH); sub(/.* /, "", nm)
    nt++; at[nt] = FNR; name[nt] = nm; ann[nt] = a " " $0; a = ""
    kind[nt] = substr(s, 1, RSTART + RLENGTH - 1 - length(nm)); hdr[nt] = substr(s, RSTART + RLENGTH)
    idc[nt] = ""
    if (match(ann[nt], /@IdClass\([A-Za-z0-9_.]+::class/)) { idc[nt] = substr(ann[nt], RSTART + 9, RLENGTH - 16); sub(/.*\./, "", idc[nt]) }
    depth = gsub(/\(/, "(") - gsub(/\)/, ")"); cont = depth > 0 || /,[ ]*$/
    next
  }
  /^@/ || (a != "" && /^[ )]/) { a = a " " $0; next }     # an annotation, or the arguments of a multi-line one
  { a = "" }
  END { flush() }
' >> "$OUT"

g "$REPO_IMPL" "@(Repository|Component)$ANNOT_END" | fmt '[REP-3] stereotype on Custom*RepositoryImpl forbidden — *Impl suffix auto-registers'
g "$REPO_IMPL" "@Transactional$ANNOT_END"          | fmt '[REP-4] @Transactional on Custom*RepositoryImpl forbidden — transaction boundary belongs to the calling Service'

g "$TEST" '@DisplayName'                  | fmt '[TST-6] @DisplayName forbidden — the backtick method name carries the description'
g "$TEST" '(^|[^.A-Za-z])(assert|assertEquals|assertTrue|assertFalse|assertNull|assertNotNull|assertThrows)\(' |
    fmt '[TST-21] non-AssertJ assertion forbidden — AssertJ assertThat shows actual vs expected'
g "$TEST" 'relaxed[[:space:]]*=[[:space:]]*true' | fmt '[TST-27] relaxed mock forbidden — strict mocks, relaxUnitFun = true only'
g "$TEST" 'Files\.createTemp(Directory|File)\(("|null)|deleteOnExit\(' | fmt '[TST-31] hand-made temporary file — use @TempDir'
LC_ALL=C g "$TEST" "fun \`[^\`]*$HANGUL"   | fmt '[TST-6] Korean test name — an English sentence in backticks'
LC_ALL=C g "$TEST" "class \`[^\`]*$HANGUL" | fmt '[TST-5] Korean @Nested class name — an English phrase in backticks'

# Annotation-driven checks: a declaration is judged with the annotations right above it and on its own line.
# `a` collects those annotation lines (a multi-line argument list included); any other line clears it.
ANN_AWK='
  function hit(id, msg) { print FILENAME ":" FNR ": [" id "] " msg }
  function parens(s,   u, o, c) { u = s; o = gsub(/\(/, "", u); u = s; c = gsub(/\)/, "", u); return o - c }
  FNR == 1 { a = ""; depth = 0; bean = 0 }
  /^@(Service|Component|RestController|Controller|Repository|Configuration)([^A-Za-z0-9_]|$)/ { bean = 1 }
  {
    t = $0; gsub(/"[^"]*"/, "\"\"", t); sub(/[[:space:]]*\/\/.*$/, "", t)
    if (depth > 0) { a = a " " t; depth += parens(t); next }
    full = a " " t
    if (t ~ /^[[:space:]]*@/ && t !~ /(^|[[:space:])])(fun|class|interface|object|val|var)[[:space:]]/) {
      a = full; depth = parens(t); if (depth < 0) depth = 0
      next
    }
    if (mode == "main") {
      if (t ~ /(^|[[:space:]])private[[:space:]]+((suspend|inline|tailrec)[[:space:]]+)*fun[[:space:]]/ &&
          full ~ /@(Transactional|Async|Retryable|Cacheable|CacheEvict|CachePut)([^A-Za-z0-9_]|$)/)
        hit("TX-18", "proxy annotation on a private method does nothing — a public method another bean calls")
      if (t ~ /(^|[[:space:]])data[[:space:]]+class[[:space:]]/ && full ~ /@(Entity|Embeddable|MappedSuperclass)([^A-Za-z0-9_]|$)/)
        hit("REP-35", "JPA type declared as a data class — a plain class without equals/hashCode")
      if (bean && full !~ /@(Volatile|Autowired|Value)([^A-Za-z0-9_]|$)/ &&
          (t ~ /^    ((private|protected|internal)[[:space:]]+)+var[[:space:]]/ ||
           t ~ /^    ((private|protected|internal)[[:space:]]+)+val[[:space:]]+[A-Za-z0-9_]+[^=]*=[[:space:]]*(mutable(List|Map|Set)Of|HashMap|ArrayList|HashSet|LinkedHashMap|ArrayDeque)[[:space:]]*[<(]/))
        hit("STY-59", "mutable field on a singleton bean — a thread-safe type (Atomic*, ConcurrentHashMap, @Volatile)")
    } else if (full ~ /@(Test|ParameterizedTest|RepeatedTest|TestFactory)([^A-Za-z0-9_]|$)/ && t ~ /(^|[[:space:]])fun[[:space:]]+[A-Za-z_]/)
      hit("TST-6", "test method without a backtick name — an English sentence in backticks")
    a = ""
  }
'
ann() { [ -s "$1" ] && tr '\n' '\0' < "$1" | xargs -0 awk -v mode="$2" "$ANN_AWK" >> "$OUT"; }
ann "$MAIN" main
ann "$TEST" test
g "$TEST" 'restoreSharedDoubles'          | fmt '[TST-26] restoreSharedDoubles is obsolete — springmockk clears shared mocks after each test'
g "$TEST" "@(DirtiesContext|TestPropertySource|ActiveProfiles|WebMvcTest|DataJpaTest)$ANNOT_END" | grep -v 'TestSupport\.kt:' |
    fmt '[TST-33] forks the shared Spring context — configure it once in the test support'

IGNORE=.convention-lint-ignore
if [ -s "$OUT" ] && [ -f "$IGNORE" ]; then
  KEPT=$(mktemp)
  while IFS= read -r hit; do
    path=${hit%%:*}; id=${hit#*: \[}; id=${id%%\]*}
    drop=0
    while IFS= read -r entry || [ -n "$entry" ]; do
      case "$entry" in ''|'#'*) continue ;; esac
      pat=${entry%:*}; pat=${pat#./}
      case "${entry##*:}" in "$id"|'*') ;; *) continue ;; esac
      # shellcheck disable=SC2254
      case "$path" in $pat) drop=1; break ;; esac
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
