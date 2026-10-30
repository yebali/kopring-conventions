---
name: sync-docs
description: "Use when the user asks to sync or verify drift between the markdown docs and the actual code — the docs-versus-code axis. Triggers on \"sync docs\", \"docs audit\", \"check docs against code\", \"are the docs up to date\", \"outdated docs\", \"stale docs\", \"docs drift\"; also invoked by check-conventions Phase 5 (scoped mode) after code fixes. Auto-applies doc fixes and never edits code. NOT for writing documentation for a new feature, and NOT for code-versus-convention violations (use check-conventions)."
---

# Sync Docs — docs ↔ code Drift Audit (AUTO-APPLY)

Reconcile the repository's markdown **docs** against the **code** and **auto-apply** the doc fixes — invocation itself is the approval. This skill **never edits code**. `<kopring-conventions>` below means that skill's directory; its `references/` hold the rule bodies.

- **Sibling axis (routing only)**: code ↔ convention → `check-conventions`, which invokes this skill in its Phase 5.

**Apply policy**: **auto-applies the doc fixes** from Phase 2 / 2B with **no confirmation gate**; **never edits code**.

## Method

- **Output language**: write the report in the user's language; headings stay in English.
- **Dispatch**: one read-only `Explore` subagent per scope, all dispatched in one single message. If a subagent lacks a tool, instruct a Bash `find`/`grep` fallback (use `grep -F` or bracketed classes for patterns containing a paren).
- **Scopes are derived from the filesystem on every run** — never from a remembered list.
- **Model tiering**: scope agents that compare docs against code run with `model: sonnet`; the structural agent (Phase 2B) and every edit-applying agent inherit the session model, because they choose wording. A failed or empty agent is re-dispatched one tier up (sonnet → inherit).
- **Report skeleton**: an English `## … result` heading, severity-tagged sections highest first, then the items that need a human.

## Operating principle

Two sources of truth are reconciled:
- **Code** — the authoritative description of what the system is today.
- **Docs** — human-maintained claims about the system, prone to drift when code changes and docs don't.

Find every claim the code contradicts, then correct the docs (never the code). Do not invent documentation for undocumented features — only correct existing claims and note demonstrable gaps.

## Scoped mode

When the caller passes a list of changed names (class, file, method, enum value, config key, `ErrorCode`, endpoint) — `check-conventions` Phase 5 does — the run is scoped to them:

- Grep every doc scope of Phase 1 for those names only; a doc that mentions none is not read further.
- Run Phase 2 on the matching docs, with the briefs limited to claims about those names.
- Skip Phase 2B: the structural check is a full-repository pass the caller did not ask for.
- Phase 3 applies only the fixes for those claims; Phase 4 reports them and names the names that matched no doc.

## Phase 1 — Discover documentation scopes

Derive the work partition from the filesystem on each run. **Enumerate scopes, not individual files.** A *scope* = a directory owning a coherent doc set plus the code those docs describe:

- **Root scope** — repo root `README*.md` and `AGENTS.md` / `CLAUDE.md`, plus all `docs/**/*.md`. Verifies against repo-wide code (the build files, version catalog and settings file).
- **Module scopes** — one per module directory that has a `docs/` folder (Glob `*/docs`, and any `**/docs` that is not the root `docs/`). Each owns `{module}/docs/**/*.md` and verifies against `{module}/src/**` and that module's migrations and resources.

Exclude `.git/**`, `build/**`, `node_modules/**`, and agent skill or command directories (`**/skills/**`, `**/commands/**`).

Each scope = name + the doc root it owns + the code root it verifies against. Before dispatch, list each scope's actual `.md` files and skim their openings to build a claim map (versions, class names, tables, enum values, env vars, migrations, cross-links).

## Phase 2 — Detect drift (one agent per scope, parallel)

**Dispatch one Explore agent per scope**, all in a single message (§ Method). #agents = #scopes; don't cap, don't collapse (unless a scope has no docs). Each agent's brief, `{scope}` substituted:

> Audit the `{scope}` documentation against code in `{code-root}`. Doc root: `{docs-root}`. Report only drift — mismatches, contradictions, missing coverage the code makes obvious. Use `file:line`. Don't list things in sync.

Per-agent checklist (whatever applies):
- Referenced files/classes/packages/migrations still exist at the stated path.
- Version numbers and image tags match the authoritative build files.
- Enum membership and error-code lists are complete and current.
- Tables/columns match the latest migration state in that module.
- Env var names match `application*.yml` and code usage.
- Cross-references between docs (including cross-scope) resolve.
- Two docs on the same topic don't contradict.
- Any *code* that violates a rule the doc states is surfaced for the user — code fixes are out of scope.

Merge all agents' findings before Phase 2B.

## Phase 2B — Structural health check (docs vs. docs)

Phase 2 compares docs ↔ code; 2B compares docs against **each other and themselves**. Run it after Phase 2; a single Explore agent covers it (inherently cross-scope; structural judgment → omit `model`, inherit).

### 1. Oversized documents (split candidates)

Measure each `.md`: total lines; distinct `#`/`##` topics; whether sections describe unrelated domains. Flag as a split candidate when: more than ~600 lines, OR 4+ unrelated top-level topics, OR a single H2 over ~250 lines that stands alone. For each, propose target filenames and scope, which sections move, the cross-references to redirect, and a stub to leave behind.

**Apply policy**: splitting is a naming decision — do NOT auto-split. Record it in `Items to confirm`. Apply only if the user approved a specific split this session.

### 2. Cross-document duplication

Detect body blocks (paragraph, table, list, code) appearing verbatim or >80% similar in 2+ files (headings alone are not duplication). For each cluster, find the canonical owner by topic: read the repository's docs index or README to see which document owns each topic, and prefer the document whose stated purpose matches. The `kopring-conventions` skill is the canonical owner of the code-style, layering, transaction, persistence, REST and test rule bodies — cite them by rule ID (`STY-19`, `TX-3`, …) and never copy them into a repository document. Rule *rationale* (why a rule exists, rejected alternatives) belongs in `<kopring-conventions>/references/rationale.md` or the repository's own decisions document; never consolidate rule bodies there.

In every non-canonical copy, replace the duplicated block with `> See [<canonical>](<relative-path>#<anchor>) for details.`; preserve the surrounding narrative.

**Apply policy**: verbatim or near-verbatim duplicates are auto-fixed (🟡). If the copies diverged, reconcile them into the best version in the canonical file, then link from the others (still auto-applied; note it in the report).

### 3. Inefficient / redundant content within a single doc

Flag and simplify: paragraphs restating an adjacent table or code block; 2+ examples of the same rule (keep the clearest); orphan or aspirational sections with no code reference; overlong mixed-concern tables (split); dead cross-references (anchors that no longer exist).

**Apply policy**: obvious redundancy is auto-removed (🟡); obvious table reshapes are auto-applied, otherwise surfaced (⚪).

Merge 2B findings with Phase 2 before Phase 3.

## Phase 3 — Apply every fix (no confirmation gate)

**Do not ask which items to apply.** Every Phase 2 (drift) and 2B (structural) item is applied automatically — invocation is the approval. Only items 2B marks "surface to user" (document splits, ambiguous table reshapes) go to `Items to confirm`.

Classify internally (for ordering, reporting and flagging what cannot be auto-fixed):
- 🔴 **Severe** — the doc describes code that no longer exists, or behavior opposite to the current code. Apply first.
- 🟠 **Missing content** — new domains, entities or codes in the code that are absent from docs that should cover them. Apply next.
- 🟡 **Stale details** — renamed classes, moved files, outdated examples, small factual errors. Apply.
- ⚪ **Judgment calls** — apply the most-likely-correct interpretation from the code; if truly undecidable, leave it untouched and record it in `Items to confirm`.

Edit rules: preserve each doc's structure, tone and formatting; don't remove sections unless the referenced code is gone; mirror the existing ordering and heading style when adding; update all docs touched by one change in the same pass. For efficiency, dispatch **one worker agent per scope** in parallel to apply that scope's fixes (root-scope cross-link fixes belong to the root worker; edit-applying agents inherit the session model). Merge the worker outputs into the summary. After all moved topics and incoming references are updated, run the repository's docs check script if it has one.

## Phase 4 — Report

```
## Document Sync Result (docs ↔ code)

### Modified files
- **<file path>**: <reason for change> — <summary of the change>

### Items to confirm
- <⚪ items that could not be auto-applied, or items that need a code change rather than a doc change>
```

## Non-negotiable rules

- Do **not** remove documentation unless the referenced code has been deleted.
- Do **not** add speculative documentation — only document what exists right now.
- Preserve each document's existing structure and formatting style; follow existing ordering when adding.
- Version numbers must match the authoritative build files (e.g. `gradle/libs.versions.toml`) exactly.
- **Never edit code** — if a doc-vs-code mismatch can only be resolved by a code change, surface it and stop.
