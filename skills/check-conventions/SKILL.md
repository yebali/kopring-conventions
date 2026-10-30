---
name: check-conventions
description: "Use when the user wants Kotlin code (production and tests) audited against the kopring-conventions rule set AND fixed — the code-versus-convention axis. It edits code: rule-decided violations are fixed directly, missing tests are written, judgment items are asked. Triggers on \"convention audit\", \"check conventions\", \"fix rule violations\", \"@Service / @Component audit\", \"duplicate code review\", \"common method extraction review\", or a request to scan a branch or the whole codebase for Kotlin Spring Boot convention violations. NOT for docs-versus-code drift, and NOT for a read-only review."
---

# Convention Check — Code ↔ Convention Drift Detection & Fix

Scan Kotlin code — production and test sources — against the `kopring-conventions` rule set, report violations, fix the rule-decided ones (including writing tests the coverage rules require), and ask about the rest. `<kopring-conventions>` below means that skill's directory; its `references/` hold the rules.

**Apply policy**: does NOT stop at reporting — **directly FIXES every `fix` finding** (the rule decides the change — the code itself is fixed), **collects every `ask` finding and asks the user about them together** (Phase 4 § Ask), then applies the answers, then in Phase 5 **updates docs when a fix is doc-visible**.

Rules are cited by identifier (`STY-19`, `SVC-15`, `TST-22`, `COV-3`, …). The prefix names the owning reference (STY → code-style, SVC → service, TX → transactions, CTL → controller, REP → repository, TST → testing, COV → test-coverage, CFG → configuration); each reference's `## 1. Hard Rules` table lists its rules.

## Method

- **Output language**: write the report in the user's language; headings stay in English.
- **Dispatch**: scan-partition agents are read-only `Explore` subagents, all dispatched in one single message. If a subagent lacks a tool, instruct a Bash `find`/`grep` fallback (use `grep -F` or bracketed classes for patterns containing a paren).
- **Partitions are derived from the filesystem on every run** — never from a remembered list.
- **Model tiering**: `model: haiku` only for purely mechanical checks (Check C); every judgment check inherits the session model. A failed or empty agent is re-dispatched without `model`.

## Scope — two modes (set by the user's request)

- **Default (no argument) — current-branch changes (committed OR modified)**: `*.kt` files under `src/main/kotlin` or `src/test/kotlin`, and `application*.yml` files under `src/main/resources` (for the CFG rules), changed on the current branch — committed-since-base ∪ working-tree ∪ untracked (**Phase 0 is canonical** for the exact definition of the union and base-branch detection); each in-scope file is audited **end to end** (full content, not just changed lines). If the set is empty, STOP and tell the user there is nothing to audit, suggesting the `all` mode — do NOT silently widen to a full audit.
- **`all` — the ENTIRE codebase**: every `*.kt` file under `src/main/kotlin` and `src/test/kotlin`, and every `application*.yml` under `src/main/resources`, in every module.
- **Both modes** exclude `build/`, generated sources, and any tree the project's own instructions declare exempt from the conventions (for example a one-off data migrator) — those are **not scanned and not reported**. Both modes always run end to end — detect, report, AND fix (no report-only switch) — and always run the Phase 3 duplication & extraction review. The ONLY difference between the modes is **which files are in scope**.
- **Invariant**: the Phase 2 rule scan, the Phase 3 duplication & extraction review, and the Phase 4 fix ALWAYS run over the in-scope file set. The run never stops at reporting.

## Tooling & parallelism

- Discover files → **Glob**. Search patterns (annotations, `!!`, `@Query`, …) → **Grep**. Read contents → **Read**.
- **STY-10 (blank line before the final `return`) has a dedicated detector** — `<kopring-conventions>/scripts/blank-line-before-return.sh`. Run it in report mode during Phase 2 on the in-scope `.kt` files (no arguments in `all` mode = the whole tree) instead of asking an agent to eyeball it: a regex that only checks "is the next line the closing brace" undercounts by ~4x because it misses multi-line `return` expressions. Phase 4 applies its fixes with `--fix` and the same file list — never the whole tree in default mode — then re-runs it in report mode: **0 hits is the self-verification** for that rule.
- **Check D's greppable subset has a dedicated detector** — `<kopring-conventions>/scripts/convention-lint.sh` (rule inventory and blind spots in its header; report-only, no fix mode; `BASE_PACKAGE=com.acme` sets the root package for the STY-2 check; the project's documented exceptions live in `.convention-lint-ignore` at the repository root). The orchestrator runs it once during Phase 2 on the in-scope `.kt` files (no arguments in `all` mode); after Phase 4 applies fixes (by the orchestrator — the script never edits), it re-runs it on the edited files — **exit 0 is the self-verification** for those rules. Exit 2 means no file was scanned: fix the file list, never read it as clean.
- **Agent report schema** — every finding is one record: `file:line · rule (ID, or Check B1–B5) · action (fix|ask) · old → new (or delete)`. `fix` = the cited rule decides the change and the agent gives the exact `old → new`; `ask` = a Phase 4 judgment-queue kind, or a finding with no exact `old → new`. Tell each agent to quote the **current text of the line** in `old` so the orchestrator can verify the line before applying; a record whose `old` does not match the file is dropped, not guessed. Do not repeat an item already reported earlier in the session.
- **Missing-test record (COV rules)** — `test file (existing or to create) · rule COV-N · action fix · target (Service method / endpoint / area) · cases to add (one line each: input → expected)`. These are written in Phase 4 by test-writing units, not as `old → new`.
- Scan-partition agents are read-only — they detect and report; they do NOT apply fixes. The Phase 4 fix is applied by the main orchestrator (and its test-writing units).
- The `./gradlew` verification commands in Phase 4 run via Bash.

**Scope partitioning** — split the in-scope file set (from Phase 0) into the smallest independently-auditable units to maximize the agent count (unless the small-scope shortcut applies):
- **`all` mode**: one partition per module and source set (`<module>/src/main`, `<module>/src/test`); for large modules, split further into one partition per top-level domain package (derive the domain list from the module's source directories), plus `client` / `config` / `util` and the test support files. The union of all partitions MUST cover the entire in-scope set.
- **Default mode**: group the Phase 0 changed-file list by `{module}/{source set}/{domain}` and dispatch one agent per group, passing each agent its **explicit file list** (not a whole-directory glob). The union of all partitions MUST cover exactly the changed-file set.

**Prevention first**: the rules this audit reports most often are listed in `coding-workflow` § *Write it right the first time*, which every coding task loads. A finding here means that step was skipped — fix it, and when the same rule recurs across runs, tighten that list (or add an edit-time hook that runs `convention-lint.sh`) rather than relying on this audit.

## Small-scope shortcut (default mode only)

When the Phase 0 set is **≤ 5 files in one module**, skip the Explore fan-out: the orchestrator reads each file end to end and runs Phase 2 / Phase 3 itself (the scripts and the Phase 1 rule map still apply). When the set spans **one module but more than 5 files**, dispatch a **single** agent for the whole module instead of one per domain. `all` mode and multi-module sets keep the full partition fan-out. The small path does not relax coverage — the Summary still shows inspected / in-scope.

## Phase 0 — Determine the in-scope file set

Resolve the scope mode from the request BEFORE anything else:

- **`all`** → in-scope set = every `*.kt` under `*/src/main/kotlin` and `*/src/test/kotlin` (exclude `build/`, generated sources, and the project's exempt trees).
- **default (no argument)** → in-scope set = current-branch changed `*.kt` (committed OR modified). First **detect the real base branch** (do NOT hardcode `main` — this branch may fork from `develop` or another integration branch), then take the union of committed + working-tree + untracked:
  ```bash
  # 1) detect base = the candidate integration branch whose merge-base with HEAD is the MOST RECENT
  #    (fewest commits ahead) — i.e. the branch this one actually forked from.
  cur=$(git rev-parse --abbrev-ref HEAD); base=""; basemb=""; best=-1
  for c in develop main master origin/develop origin/main origin/master; do
    git rev-parse --verify --quiet "$c" >/dev/null 2>&1 || continue
    [ "$c" = "$cur" ] && continue
    mb=$(git merge-base "$c" HEAD) || continue
    ahead=$(git rev-list --count "$mb..HEAD")
    if [ "$best" -lt 0 ] || [ "$ahead" -lt "$best" ]; then best=$ahead; base=$c; basemb=$mb; fi
  done
  # 2) in-scope = committed-since-base ∪ working-tree-modified ∪ untracked
  { git diff --diff-filter=d --name-only "$basemb..HEAD"; \
    git diff --diff-filter=d --name-only HEAD; \
    git ls-files --others --exclude-standard; } \
    | sort -u | grep -E '/src/(main|test)/kotlin/.*\.kt$|/src/main/resources/application[^/]*\.ya?ml$'
  # then drop the project's exempt trees with an extra `grep -v`
  ```
  - Report the detected base branch in the final output (e.g. "base: develop") so the user can sanity-check it.
  - `git diff HEAD` covers staged + unstaged tracked edits; `ls-files --others --exclude-standard` covers untracked new files; `$basemb..HEAD` covers commits since the fork point. `--diff-filter=d` drops deletions (nothing to audit).
  - If the union is empty → STOP, report "There are no Kotlin changes to audit on the current branch (base: <detected>)" and suggest the `all` mode. Do NOT widen to a full audit.

Record the in-scope file counts (main and test separately) now — Phase 4 coverage verification checks against them.

## Phase 1 — Collect the rule surface (dynamic)

Do NOT hardcode the check list. On every run, read the canonical sources in `<kopring-conventions>/references/` and build the check list:

- The `## 1. Hard Rules` table of **every reference** (`code-style`, `service`, `transactions`, `controller`, `repository`, `testing`, `test-coverage`, `configuration`) — **every row present**, whatever the current count (the tables grow; do not assume a fixed range). Also read the project's own `CLAUDE.md` / `AGENTS.md` for overrides and exemptions.
- `service.md` §10 — the `@Service` / `@Component` category table (read the current rows; do not assume a fixed count).
- `code-style.md` §4 (STY-12 carve-outs and the util placement table) · §5 (comment policy and its §5.3 decision table) · §6 (STY-19 keep conditions) · §8 (method shape — which single-use private methods are legitimate steps) · §10 (prefer the plain option and the list of hoisted call sites) · §20 (ErrorCode numbering) — **must read before Phase 3**: code-string overlap across services is allowed there, so skipping it makes the duplication scan flag a correct design as a defect.
- `transactions.md` §3 — the "Boundary needed when" table and gate 0 (the STY-27 check needs both to tell a justified boundary from a relocatable one).
- `test-coverage.md` §1 and `testing.md` §1 — `COV-N` and `TST-N`. Check E derives from these.

When rules are added or changed, Phase 1 picks them up automatically — Phase 2's checks derive from Phase 1's result.

## Phase 2 — Rule scan (massively parallel)

Dispatch **one agent per scope partition** (Explore, single message). Each partition agent receives the Phase 1 rule map and runs the full check set on its partition (Checks A–D on main partitions; Checks B (test form), D and E on test partitions):

- **Check A — @Service / @Component** (SVC-30, SVC-31): map every `@Service` / `@Component` class to the categories in service.md §10; flag annotation↔category mismatch and suffix↔category mismatch. A mismatch the table decides → `fix`; a class whose category itself is ambiguous (e.g. whether to promote a strategy impl to `@Service`) → `ask`.
- **Check B — Comment policy** (STY-16, STY-17, STY-18): apply [code-style §5](../kopring-conventions/references/code-style.md#5-comments-and-kdoc). Its §5.3 decision table owns every test and fix, and its "never commented" list (§5.1) is never a finding — this check does not restate either. Report each finding under the table row it matched — **B1** missing class/function summary · **B2** code-translating · **B3** line comment on simple logic · **B4** history or rationale · **B5** oversized summary — **all `fix`**. A `// ponytail:` comment in the STY-18 form is never a B3/B4 finding. Each agent reports the exact replacement (`old → new`, or `delete`); for B1, one record per declaration with the proposed KDoc line, never a per-file count. The orchestrator applies the text as given, without re-judging.
  - **Test partitions** apply TST-1 instead: every comment other than `// given` / `// when` / `// then` and tool directives is `delete`; B1 never applies to tests.
- **Check C — File organization** (STY-12): files with 2+ top-level `class` / `object` / `interface` / `enum class`; skip the carve-outs [code-style §4](../kopring-conventions/references/code-style.md#4-files-and-packages) lists.
- **Check D — Every other Hard Rules row**: the `convention-lint.sh` run above covers the greppable subset (report-only; exit 0 = clean, exit 1 = findings as `path:line: [ID] message`). The rule inventory and each rule's blind spots live in the **script's header comment — the single source of truth**; do not re-enumerate them here. The script runs over the in-scope files only; a hit outside them is not this run's finding. Every other row of the Phase 1 rule map is **agent-judged**: report `fix` when the rule's detail section decides the exact change (e.g. a `ZonedDateTime.equals` → `isEqual`, a duration constant → `Duration`, a missing `fallbackExecution = true` on an `AFTER_COMMIT`/`BEFORE_COMMIT` listener (SVC-34), `@PageableDefault` size → 20, a missing `id` tie-break, `takeIf { it.isNotEmpty() }` on a filter → the REP-11 form, a public state setter → `protected set`, an insert of a data-carrying entity behind a UNIQUE constraint → `translateUniqueViolation` (SVC-24; a link follows SVC-25)), and `ask` when the change needs a design choice the rule leaves open (moving work to another class, introducing an `ErrorDecoder`, restructuring a consumer loop). Judgment rules that need care:
  - **STY-9** — a single-expression trailing-lambda call whose `{` · body · `}` are needlessly split across 3 lines: message lambdas (`requireNotNull`/`require`/`check`) always; other single-expression trailing lambdas when the merged line is ≤ 120 characters (**exempt** when the argument itself is genuinely multi-line).
  - **SVC-14 / SVC-15** — a named exception subclass with wrong semantics, or a failure form the service.md §5 table does not allow (the script only catches direct generic/base-exception throws).
  - **SVC-38 / SVC-39** — read every call a Service makes into another domain's Service, and every state-changing Feign call to another deployable of the same system, and classify it by the asking/telling/decorating test of [service.md §6](../kopring-conventions/references/service.md#6-cross-domain-access). A call the test moves elsewhere is `ask`, naming the target: the event (publisher, event, the affected domain's listener and its SVC-40 kind), the composition in the inbound adapter, or the broker message.
  - **STY-27 prefer the plain form** — for each `inTx` / `REQUIRES_NEW` / `@Async` / dedicated `ThreadPoolTaskExecutor` `@Configuration` in scope, ask the upper gate (*would this boundary disappear if the external call moved to the caller or a listener?*). Report it as `ask`, naming the concrete relocation; **never propose deleting a boundary** (that silently loses dirty-checking writes), and treat a boundary that matches a row of transactions.md §3's "Boundary needed when" table and holds no external call as clean. **STY-28** reports as `fix` an interface, abstract base class, type parameter, strategy or factory, configuration flag, or optional parameter with one real use that none of code-style §10's carve-outs covers; fix = fold it into its one use.
  - **STY-26 standard-library first** reports as `fix` a loop, util, or extension function that re-implements or re-wraps a standard-library function; fix = call the standard-library function.
  - **STY-21 – STY-24 method shape** (code-style §8, applied in both modes): a one- or two-line delegating private method → `fix` (fold it into the caller); any other limit → `ask`, naming the concrete restructure.
  - **CFG rows** — judged on the in-scope `application*.yml` files and the `@ConfigurationProperties` classes they bind (configuration.md).
  - Rules that open with *"If the project uses X"* are checked only when the project does use X.
- **Check E — Tests** (test partitions; `TST-N`, `COV-N`): every TST row is judged like Check D on the test sources (`fix` with `old → new`). Coverage rules compare the production classes of the partition's domain with their tests: a public Service method without a success test or without a failure test per domain exception it throws (COV-3), an endpoint missing a COV-1 variation or the COV-2 binding cases, an area COV-5 lists without its standalone test → one **missing-test record** each, `fix`. A test that COV-6 or COV-7 forbids → `delete` (`fix`). Do not report a missing test that COV-8 would reject.
- **Check F — Project setup** (`all` mode only; the orchestrator, once per run): some rules hold for the project as a whole and no line check sees them — TX-15 (the `rollbackOn` switch and the `TransactionRunner` unwrap), STY-58 (the `Clock` bean), CFG-20 (the three time-zone settings), TST-34 (the scheduling switch in the test profile), REP-35 (`plugin.jpa` and all-open in the build), COV-9 (one adapter test per Feign client), COV-10 (one migration guard test per module), and a `.convention-lint-ignore` entry for each lint hit the project's own rule document allows. Check each once against the build files, `application*.yml` and the test support classes; a missing piece is `ask`, naming the concrete change, because it touches shared setup. Also report as `ask` every rule the project's own rule document restates in a form the skill has since corrected — the project text overrides the skill, so the correction never reaches that project until its document changes.

Do NOT re-derive the rule bodies in the report — cite the identifier and let the reference own the text.

Each partition agent also collects, for Phase 3, the **method/util inventory** of its partition (signatures, short body summaries, util-like helpers) so cross-partition duplication can be consolidated.

To push parallelism even further — and unlock cheap-model tiering — additionally split each partition by check group — separate agents for Check A / B / C / D / E per partition — and dispatch them all in the same single message. Tiers when split:

- **Check C → `model: haiku`** — declaration shape and annotations decide every finding, including the five exceptions.
- **Every other agent → inherit** — Check D's split agent holds the agent-judged rules; Check A decides a class's category; every Check B finding needs a reader to apply the decision table to the surrounding code and to write the replacement text; Check E needs a reader who can tell which behavior a test already pins; unsplit agents mix checks with the Phase 3 inventory.

The split is most worthwhile in `all` mode, where the fan-out is largest.

### Partition completeness — verify, never skip silently

After the parallel agents return, **verify every partition produced a valid structured report** (its `fix` / `ask` records and file inventory). A partition whose agent returned an empty report, an error, a "cannot audit / tool unavailable" message, or no file inventory is a **failed partition** — it did NOT cover its domain. For every failed partition, **re-dispatch it** (as `Explore`, without a cheaper `model`; instruct the Bash `find`/`grep` fallback if needed) before proceeding to Phase 4. The audit MUST NOT report results while any partition is unaccounted for — silent partial coverage is the failure mode this guards against.

## Phase 3 — Duplication & extraction review (ALWAYS runs, cannot be skipped)

**Every audit run MUST include this phase.** It implements the "review existing code for duplicates" duty of STY-15 (code-style §4).

**NOT duplication candidates — five kinds of intentional sameness** (the same list as `structure-check`'s "Not findings"; keep the two in step). Report none of these; each is a convention working as designed, and calling one "drift" burns the report's credibility:

1. **`Command`/`Result`/`Request`/`Response` inner DTOs** — same-shape inner data classes across (or within) these classes are intentional (SVC-6, CTL-5): each declares its own, never reuses another's. Don't report `GetXxxResponse` ↔ `ListXxxResponse` nested DTOs.
2. **`ErrorCode` strings colliding across services** — code-style §20 allows it explicitly (STY-55/57). Report a collision **only** when a single client would have to take *different action* on the same `type`.
3. **Shapes another rule mandates** — QueryDSL chains (REP-5 forbids extracting the skeleton), `pageByQuery`+`by(query)`+`PageableExecutionUtils` (REP-10 requires that exact shape), per-domain `*NotFoundException` (SVC-14), layered enums (SVC-27).
4. **Per-module test copies** — each module keeps its own `SpringBootTestSupport`, `TestcontainersConfiguration` and architecture/guard tests on purpose (TST-2, TST-3, testing §2). Duplicated helpers **within** one module's tests are candidates (TST-16).
5. **The authenticated-principal controller parameter** that appears unused (CTL-1) — it is the authentication boundary, kept on purpose.

**General test before reporting any candidate**: name what breaks if the two copies drift apart. If nothing does — because a rule forces them to look alike, or because the two copies are never read by the same consumer — it is not duplication.

1. **Local duplication scan (parallel)** — dispatch one agent per scope partition in a single message (semantic judgment → inherit the session model); each scans its partition for intra-partition duplicate / near-duplicate methods and extraction candidates. (Phase 2 partition agents may collect this inline to save round-trips.)
2. **Cross-partition consolidation** — merge every partition's method/util inventory and cross-reference it to find logic duplicated *across* modules/domains. This step needs the union of all partition inventories, so it runs after the parallel partition agents return.
3. **Classify** each candidate by usage span: single-domain / multi-domain within one service / 2+ modules.
4. **Placement proposal** — per the STY-15 table (code-style §4): 2+ modules → the shared pure-Kotlin module / the shared Spring module; multi-domain within a module → `{module}/.../util/`.
5. **Ask before extracting** — duplication / extraction is a semantic judgment. Every candidate goes to the Phase 4 judgment queue; an extract or move is applied only for items the user approves there (this prevents wrongly abstracting coincidentally-similar code).

## Phase 4 — Report & fix

### Coverage verification (before reporting)
Before writing the report, confirm the partitions actually covered the **Phase 0 in-scope set**: confirm the union of all partitions' inspected-file lists equals that set (in `all` mode that is the per-module `*.kt` total of `src/main` and `src/test` after the exclusions; in default mode it is the current-branch changed-file list). If any in-scope file is unaccounted for, scan it before reporting. The audit's value depends on full coverage of the in-scope set — a partial run is an invalid run.

### Report
- Group findings by check. Each item: `file:line`, the violated rule ID, the rationale (why it is a violation), and the recommended fix.
- Put Phase 3 duplication / extraction candidates in their own section — per candidate: all duplicate locations, usage-span classification, placement proposal.
- Put missing-test records in their own section — per record: the target, the COV rule, the cases written.
- End with a summary table — including an **inspected-files / total-files** row (main and test) proving full coverage.

### Fix (always — every run)
- Apply every `fix` finding — Check B included — as the agent's `old → new` text. This always happens — there is no report-only mode. The cited rule decides each change, not taste: a missing KDoc gets the proposed line, a one-use variable (STY-19), a one- or two-line delegating private method (STY-21), or a one-use abstraction (STY-28) is folded in, a standard-library re-implementation becomes the standard call (STY-26), a mismatched comment placement is moved, an inconsistent literal becomes the constant its siblings use. A change no rule backs is never invented — that finding is `ask`.
- **Missing tests** — after the rule fixes, dispatch test-writing units (`general-purpose`, inherit; one unit per module — concurrent agents in one module conflict on its test-support base class, see `coding-workflow`). Each unit receives its missing-test records, the TST/COV rule IDs, and `references/testing.md` / `references/test-coverage.md`; it writes the tests and nothing else (no production edits, no commit, no Gradle).
- **Judgment queue (`ask`)** — never auto-applied, always asked (next section): a Check A class whose category is ambiguous · STY-27's transaction-boundary relocations (never delete a boundary) · a rename of a public class/file · every Phase 3 duplication candidate · any finding with no rule-backed change.
- After fixing, run the verification below **only on the modules whose files were edited**: `./gradlew :<module>:ktlintCheck :<module>:compileKotlin :<module>:compileTestKotlin`, plus `convention-lint.sh <edited files>` and `blank-line-before-return.sh <edited files>` (exit 0). Run that module's tests that cover the edited classes and every test written or edited in this run (`./gradlew :<module>:test --tests '<ClassName>*'`); a new test that fails because production behaves differently from the rule is reported, not "fixed" by weakening its assertion. Before each edit, re-read the target line and confirm it matches the agent's `old` text. `ktlintCheck` matters because the comment constraints of code-style §5 can break `check`.

### Ask (judgment queue)
After the rule-decided fixes are applied and verified, ask the user about every queued item **together** with `AskUserQuestion` — up to 4 questions per call, as many calls as the queue needs. Each question names `file:line`, the rule, what the code does now, and concrete options: the proposed change first (marked `(Recommended)` when a rule leans that way) and "leave as is". Apply each answer as given, re-run the verification above on the touched modules, and report the question, the answer, and what changed. An item without an answer is left untouched.

## Phase 5 — Documentation sync (final step, every run)

The audit changes **code** (annotations, comments, signatures, file splits, tests). Those changes can make the project's markdown docs stale.

- **Gate**: update docs only when a fix changed something a doc can cite — a class/file name or location, a public signature, an enum value, a config key or default, an `ErrorCode`, an API default (page size, null fields, filter semantics), or a convention rule. Comment-only edits, private helper inlining, local-variable folding and added tests cannot drift a doc: run the project's docs check if it has one, and write `docs sync skipped — no doc-visible change` in the report.
- When the gate is open, run the `sync-docs` skill in **scoped mode**, passing the list of changed names: it greps the project's docs (`README`, `AGENTS.md` / `CLAUDE.md`, `docs/`) for those names only and reconciles them with the modified code, without editing code or restructuring unrelated docs.
- If this run surfaced a convention *rule* to add or change (not just applied existing ones), write it in the **project's own rule document** under a project-local identifier and report it. Never edit the installed skill's `references/` — the next install overwrites it, and a reused identifier collides with the skill's. A change to the skill itself is made in the `kopring-conventions` repository (its README, "Adding or changing a rule") and reinstalled.

## Output Format

```
## Convention Check Result — entire project (all modules)

### Fixed (N)
**1. {check} — {title}**
- Location: `file:line`
- Rule: {ID, e.g. STY-19}
- Why: {why it is a violation}
- Change: {applied old → new}

### Tests written (N)
**1. {target}** — rule COV-N · `test file` · cases: {list} · result: pass / reported failure

### Asked (N)
**1. {title}** — `file:line` · rule · question · answer · applied change (or "left as is")

### Duplication / extraction candidates (N)
**1. {title}**
- Locations: `file:line`, ... (every duplicate site)
- Span: single-domain / within-module / 2+ modules
- Proposal: {target location}
- Answer: {answer · applied change, or "left as is"}

### Summary
| Category | Count |
|----------|-------|
| Fixed | N |
| Tests written / failing | N / N |
| Asked / applied | N / N |
| Duplication candidates asked / applied | N / N |
| Scope mode | default (base: <detected branch>) / all |
| Inspected files / in-scope (main · test) | N / N · N / N (coverage confirmed) |

### Phase 5 — Documentation sync result
{summary of docs modified, or "no drift"}
```

## Self-check

Before reporting, confirm:
- Every partition returned a valid structured report; failed/empty partitions were re-dispatched — none silently skipped.
- Coverage verified: inspected-files count == Phase 0 in-scope count for main and test; the Summary table shows it.
- Exempt trees were excluded from scanning and reporting.
- Phase 3 duplication & extraction review was performed (mandatory).
- Missing-test records were written by per-module units and their tests were run.
- Phase 5: docs were reconciled when a doc-visible change was made, otherwise the skip was stated.
- Phase 2 / Phase 3 scan agents dispatched as `subagent_type: Explore` in one single message, partitioned to maximize agent count — or the small-scope shortcut applied and stated.
- Model tiering: `model: haiku` only on split Check C agents; every other agent inherited; failed partitions re-dispatched without `model`.
- Every `fix` finding was applied; every `ask` finding was asked with `AskUserQuestion`, and only the answered ones were applied.
- The check list came dynamically from Phase 1 (no hardcoding).
- Phase 0 resolved the scope mode; default-mode empty set stopped instead of widening.
