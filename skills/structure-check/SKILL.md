---
name: structure-check
description: Use when the user wants to find Kotlin Spring Boot code that follows every convention yet is still too complex, low-cohesion, or entangled — the code-versus-structural-health axis. Produces a refactoring plan document and never edits code. Triggers on "structural audit", "cohesion audit", "find refactoring targets", "find complex code", "god service", "configuration is tangled", "simplify the structure", or a refactoring-plan request. NOT for convention violations (use convention-check).
---

# Structure Check — code ↔ structural-health Audit (PLAN ONLY)

Find production code that is **hard to work in** — low cohesion, tangled configuration, one-off structures where a general one would do — and hand the result to another model as a refactoring plan document. This skill operates on the **code ↔ structural health** axis. `<kopring-conventions>` below means the `kopring-conventions` skill's directory; its `references/` hold the rules.

**Why this is a separate axis, not part of `convention-check`**: `convention-check` is rule-bound by construction — it reports what a documented rule forbids. The findings this skill exists for **violate no rule**. A service injecting 49 dependencies, a setting whose effective value is assembled from four layers, a bespoke executor where a synchronous call fits — every one of those passes a convention audit clean. Nothing else looks for them.

**Apply policy**: **plan only** — **never edits code, configuration, or docs.** The single artifact is one new plan document.

## Method

- **Output language**: write the report and plan in the user's language; headings and identifiers stay in English.
- **Dispatch**: scan-partition agents are read-only `Explore` subagents, all dispatched in one single message. If a subagent lacks a tool, instruct a Bash `find`/`grep` fallback (use `grep -F` or bracketed classes for patterns containing a paren).
- **Partitions are derived from the filesystem on every run** — never from a remembered list.

## Scope — the request names a module

Valid module names are read from `settings.gradle.kts` **on every run** — never from a list written here, so a module added tomorrow is accepted tomorrow. `scripts/structure-metrics.sh` performs the same validation and is the executable source of truth for it.

- **empty** → the whole repository (every module's `src/main`).
- **a module name** → that module's `src/main` only.
- **an unrecognized value** (a typo) → **STOP.** Print the valid module list and end the run. Do **not** widen to a full scan — silent widening turns a request to look at one module into an unrequested repo-wide run.

**Two things stay repo-wide even when a module is named**, because narrowing them would destroy the check itself:
- the **Phase 1 carve-out registry** — the rationale docs govern every module.
- **Phase 2 check S5 (generalization opportunity)** — it asks "is there already an ordinary pattern for this elsewhere in the repo?". Restricted to one module, that comparison has nothing to compare against.

Always excluded: `build/`, generated sources, and `*Test.kt` — test structure is owned by `references/testing.md` and `references/test-coverage.md`.

## Tooling & parallelism

- **Hotspot ranking has a dedicated script** — `scripts/structure-metrics.sh`. Run it in Phase 0 instead of having agents eyeball a directory. The metric inventory, each metric's exemptions, and its blind spots live in the **script's header comment — the single source of truth**; do not re-enumerate them here.
- Scan agents are read-only — they detect and report candidates; they never edit and never design fixes. `Explore` (which has no `Edit`) fits exactly.

## Phase 0 — Resolve scope → rank hotspots → derive partitions

1. **Resolve the scope** from the request per the Scope section above. An unrecognized module stops the run here.
2. **Rank hotspots**: `bash scripts/structure-metrics.sh --top [module]` (path relative to this skill's directory). This prints a leaderboard per metric (`deps` · `xdomain` · `funs` · `depth` · `cfg` · `loc`). The **union of those lists is the hotspot set**. Record it — Phase 3 checks findings against it, and Phase 4 quotes it as evidence. `BASE_PACKAGE`, `DOMAIN_SEGMENTS` and `SHARED_RE` tune the `xdomain` metric (see the script header).
3. **Derive partitions dynamically** from the filesystem: one partition per in-scope module, and for a large module one partition per top-level domain directory under its base package. Keep the domain split even when the scope is a single module — it is what preserves the parallelism.

Each partition agent receives **its partition's hotspot rows plus its full file list**. The hotspots say where to look first; the file list is what the partition is accountable for.

## Phase 1 — Load the intentional-complexity registry

A project documents its own deliberate oddities. **Skipping this phase produces a report that proposes breaking working design** — and burns the report's credibility with it. Read and build the carve-out list **dynamically** (the docs grow; do not hardcode entries):

- `<kopring-conventions>/references/rationale.md` — "why it is this way", including which look-alike duplications are mandated and must not be consolidated.
- The project's own design-decision docs: `CLAUDE.md` / `AGENTS.md`, architecture or ADR documents, anything marked "do not revert".
- `code-style.md` §10 (prefer the plain option, STY-27/STY-28 — **the upper gate is the exact test check S4 applies**, and its list of hoisted call sites) and §19 (module and package layout).
- `transactions.md` §3 — the "Boundary needed when" table, which separates a justified transaction boundary from a relocatable one.
- The `## 1. Hard Rules` table of every reference — rules whose carve-outs name a specific structure.

A registry entry is `{structure, why it is deliberate, source citation}`. Phase 3 matches findings against it.

## Phase 2 — Parallel structural scan

Dispatch **one agent per partition** (`Explore`, all in a single message, `model: sonnet`). Each agent runs all five checks over its partition and returns candidates against a fixed schema.

- **S1 — Cohesion.** A class whose methods split into disjoint field-usage clusters (the methods using fields A/B never touch C/D — two classes wearing one name). A service reaching into 3+ other domain packages. A class whose name no longer covers what it does.
- **S2 — Complexity.** Nesting or private-call depth past the limits of [STY-22/STY-23](../../references/code-style.md#8-method-shape), where an early return, a guard, or lifting a step flattens it; a method doing several unrelated things in sequence; branching that a `when` table or a map lookup expresses directly. **A long flat `when` is not a finding** — a flat table is the target shape, not the problem.
- **S3 — Configuration entanglement.** A setting whose effective value is assembled across 2+ layers (`application*.yml` ↔ env var ↔ database setting row ↔ profile ↔ `@ConditionalOn`); a bean graph that differs per profile; one value read in two places with different defaults. Cross-check against the project's own configuration-ownership rule, if it has one, before reporting.
- **S4 — Special-case structure.** A shape that exists for exactly one caller: an interface with one implementation, a dedicated executor / AOP / custom propagation / extra transaction boundary where the plain form fits, a hand-rolled utility that Kotlin stdlib or Spring already ships. Apply the STY-27 upper gate verbatim: *if the external call moved to the caller or a listener, would this boundary disappear entirely?* **Never propose deleting a transaction boundary** — that silently loses dirty-checking writes; what moves is the external call's location.
  - **Before reporting a one-implementation interface, trace the bean graph.** Dependency inversion is the sanctioned way to break a Spring bean cycle (SVC-20 bans `@Lazy` and requires moving the responsibility instead), so a one-impl interface whose direct-injection alternative would close a cycle is **correct design, not indirection**. Follow the chain the direct injection would create, hop by hop, across the whole module — **not just your partition** — before claiming the interface is redundant. A partition-local view sees "one interface, one impl, one caller" and reaches the wrong verdict.
- **S5 — Generalization opportunity.** N near-identical bespoke implementations that one pattern **already used elsewhere in this repo** would cover. Name the existing pattern and where it already lives; a proposal to invent a new abstraction is not an S5 finding.

**Not findings — do not report these**, each is a convention working as designed:
- Command/Result/Request/Response inner data classes that look alike (SVC-6 and CTL-5 require each to declare its own).
- QueryDSL query skeletons (REP-5 forbids extracting them) and the `pageByQuery` + `by()` + `PageableExecutionUtils` shape (REP-10 requires exactly it).
- Per-domain `*NotFoundException` classes (SVC-14), and the layered enums (SVC-27).
- An authenticated-principal controller parameter that appears unused (CTL-1) — it is the authentication boundary, deliberately kept (STY-20 does not apply to it).

**Each agent also returns a mechanism inventory** — one line per non-trivial mechanism it saw (`<name> — <what it does> — <the shape: entity kind, storage, key collaborators>`), whether or not it became a candidate. Phase 3 cross-references these across partitions. Without it, S5 asks a question no partition can answer from inside itself: an agent that sees only its own directory cannot know the repo already has the pattern.

**Required output schema per candidate** (agents produce nothing else — no ranking, no fix design):

```
check: S1|S2|S3|S4|S5
file: <path>            (+ method/class name; plans cite methods, not line numbers)
observed: <what is literally there — counts, names, the concrete shape>
why it costs: <what is harder to do because of it>
evidence: <the metric row, grep hit, or quoted lines that back the claim>
```

**Model tiering**: `model: sonnet` — structural candidates a later gate verifies: the script pins the targets, the five checks pin the patterns, and **Phase 3 verifies every surviving candidate against the real code**.

### Partition completeness — verify, never skip silently

After the agents return, confirm **every partition produced a valid structured report**. A partition that errored, returned nothing, or listed no inspected files is a **failed partition** — it did not cover its domain. Re-dispatch each failed partition **without `model`** before proceeding. A zero-candidate report that shows its inspected file list is a valid result, not a failure. Never report while a partition is unaccounted for.

## Phase 3 — Session model: filter, verify, rank

The session model owns this phase; it is not delegated.

1. **Cross-partition consolidation — run this BEFORE filtering.** Merge every partition's mechanism inventory and cross-reference it. A mechanism implemented once per domain is invisible to every partition agent individually and only appears here, so this step produces **new** S5 candidates that then go through the same filtering and verification as the rest. Look for: the same storage+lifecycle shape under two names, the same policy assembled in two services, a helper re-implemented beside an existing shared one in the shared modules or a module's `util/`.
   > This step is not optional: a duplication spanning two domains that no agent was pointed at (e.g. one one-time-code mechanism implemented in two domains) is visible only here.

2. **Filter against the Phase 1 registry.** A candidate matching a carve-out moves to the **intentional-complexity section** — it is shown with its rationale citation, not deleted, and never enters the work plan. (Suppressing it silently would remove the only chance to notice a rationale has gone stale.)
3. **Deduplicate** — the same cross-domain coupling surfaces from both ends.
4. **Verify every surviving candidate by reading the actual code.** This is the gate that licenses `model: sonnet` in Phase 2. Drop what does not hold up; do not soften a false positive into a weak finding.
5. **Rank** each survivor by:
   - **Blast radius** — how many files a fix touches.
   - **Regression risk** — does a `*Test.kt` cover the affected code today? Untested code ranks riskier, not safer.
   - **Difficulty** — mechanical rename/move vs. a change that alters a transaction or concurrency boundary.

Order the plan **cheapest and safest first**, so the early steps can ship independently of whether the later ones are ever done.

## Phase 4 — Write the refactoring plan document

Write exactly one file: `structure-refactor-<scope>-<YYYY-MM-DD>.md` (`<scope>` = the module name, or `all`) in the project's plans directory (use the existing convention if there is one, otherwise `plans/`). Per-module runs must not overwrite each other.

Write it as an execution procedure — one another model executes without needing this conversation.

Required structure:

- **Opening line** — scope actually inspected, the criteria used, and the doc's lifetime (when it is discarded).
- **`P0`..`PN` phases**, cheapest and safest first. Each phase carries: target files and methods · current structure · target structure · change outline · regression tests (which existing tests must stay green, which new one is needed) · **acceptance criteria** (a command to paste and the output to expect).
- **`## Intentional complexity (excluded)`** — every Phase 3 registry match, each with its rationale citation. This section is why a reader can trust the rest.
- **`## Evidence`** — the Phase 0 metric snapshot and the run date, so the next run can tell what moved.

Cite **paths plus method/class names, not `file:line`** — it stays accurate as the file drifts.

## Phase 5 — Inline report

Report in **3–5 lines plus the document path**. Every detail belongs in the document; do not restate it in the terminal. Include the scope, the phase count, the top finding, and how many items landed in the intentional-complexity section.

## Output Format

```
## Structure Audit Result — <scope>

- Inspected: <N> files / <M> partitions (all partitions returned)
- Plan: P0~P<N>, <total> items — top: <one line>
- Excluded as intentional complexity: <N>
- Plan document: `<plans dir>/structure-refactor-<scope>-<date>.md`
```

## Self-check

Before reporting, confirm:
- Phase 0 resolved the scope; an unrecognized module stopped the run instead of widening.
- Partitions were derived dynamically this run (not a remembered list), and the domain split was kept even for a single-module scope.
- Phase 2 agents dispatched as `subagent_type: Explore`, all in ONE single message.
- Every partition returned a valid structured report; failed partitions were re-dispatched without `model` — none silently skipped.
- Phase 1 registry was built by reading the rationale docs this run, and Phase 3 actually applied it — the intentional-complexity section exists even if empty.
- Phase 3's cross-partition consolidation ran against the union of every partition's mechanism inventory — not skipped because the per-partition reports already looked full.
- Every finding in the plan was verified against real code by the session model (the gate that licenses `model: sonnet` in Phase 2).
- **No code, configuration, or documentation was edited.** `git status` shows exactly one new file, the plan document.
- The plan is ordered cheapest-and-safest first, and every phase has acceptance criteria that can be pasted and run.
