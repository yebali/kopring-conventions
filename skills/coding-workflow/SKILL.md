---
name: coding-workflow
description: "Use when starting ANY coding task in a Kotlin Spring Boot repository — implementing, refactoring, fixing bugs, writing or running tests, or exploring code — before the first code read or edit, and before dispatching ANY subagent. Sets the always-on baseline: apply the kopring-conventions rules while writing, run the lint before saying done, and plan, tier and review parallel subagent work."
---

# Coding Workflow — Always-On Baseline

Loaded at the start of every coding task. It owns the cross-cutting execution policy; keep each policy to one short H2 section. The rules themselves live in the `kopring-conventions` skill (`references/`); `<kopring-conventions>` below means that skill's directory.

## Write it right the first time

The `check-conventions` skill catches what slipped through; it should find little. Before writing Kotlin, load the Hard Rules table of every `kopring-conventions` reference you touch ([Before writing code](../kopring-conventions/SKILL.md#before-writing-code) shows how to load §1 alone) and apply it while writing, not afterwards. Check its [Rules most often broken](../kopring-conventions/SKILL.md#rules-most-often-broken) before you finish.

**Before you say done**:
1. `bash <kopring-conventions>/scripts/convention-lint.sh <touched .kt files>` and `bash <kopring-conventions>/scripts/blank-line-before-return.sh <touched .kt files>` — both `total: 0`. Exit 2 means no file was scanned; fix the file list.
2. Run code-style §5.3 *Deciding a comment finding* on every comment you wrote and every new public declaration; fix what it flags now.

## Parallel dispatch & model tiering

**Plan on the session model, implement in parallel.** Speed outranks token cost: a subagent costs roughly 20–30K tokens before it does any work, which is acceptable when independent units run at the same time. Work inline only when the change is a single unit, or when the spec would be longer than the edit itself.

Dispatch when one of these holds:

- two or more independent units, each touching more than one file;
- a read-only, repo-wide scan whose raw output would flood the session context;
- the user asks for it.

Before dispatching, the session freezes the plan: per unit the files, signatures, and rules to apply, plus the order between units. Dependent phases (spec → implement → verify) stay sequential. A request to understand or compare code stays read-only; show the plan and dispatch edit units only after the user approves it.

When you dispatch:

- Derive units from the real tree (Glob / `git diff`) and launch all independent units in **one** message.
- Split by domain or endpoint, not by layer — layers depend on each other and run serially. A test unit may run beside its implementation unit when the spec freezes the signatures it tests against. Test-writing units split per module, not per class — concurrent agents in one module conflict on the shared test-support base class (TST-2/3).
- Give shared files a single owner (the session or one agent): Flyway migration versions, permission or access tables, the dependency version catalog, and any Service class that two units would edit.
- Agents edit only. The session runs the build once after they finish, because concurrent Gradle runs in one tree contend for the lock.
- Every edit unit's prompt carries the rule IDs (`STY-19`, `SVC-15`, …) and the reference section it must apply — never assume the agent knows the rules — and forbids `git commit`, Gradle runs, and files outside the unit's list.
- Read-only units use `subagent_type: Explore`; edit units use `general-purpose`.
- Tier every unit. This list is the single source for every skill; the others cite it:
  - `model: haiku` — locate or list, or a pinned literal edit.
  - `model: sonnet` — a read-and-summarize `Explore` whose candidates the session verifies before acting on them, a frozen-spec implementation (including tests written from a fixed case list), or the scan and fix roles of [Scan → verify → fix](#scan--verify--fix).
  - `model: opus` — the verify role and the re-scan of [Scan → verify → fix](#scan--verify--fix).
  - inherit the session model (omit `model`) — rule judgment whose output is applied as given, wording choices (doc edits, KDoc text), authorization, transaction and lock boundaries, migrations, design.
- A unit that fails, returns empty or misses the spec is re-dispatched one tier up (haiku → sonnet → inherit; an inheriting unit as is) with the exact mismatch in the prompt (`retier:`).
- **Cap every report** in the prompt (e.g. ≤30 lines, `file:line` + one-line finding, no restating the prompt) — the report lands in the session context.

### Scan → verify → fix

A scan over several partitions whose findings change code runs as three roles, never as one agent that both finds and edits. `check-conventions` is the full implementation; a scan of five files or fewer in one module runs inline instead. Doc edits (`sync-docs`, wording is session-model work) and plan-only scans (`structure-check`) keep their own tiers. Haiku is not a scan model: on this rule set it missed most of the violations a Sonnet scan found and the verifier confirmed.

| Role | Model | Unit | Output |
|---|---|---|---|
| Scan | `model: sonnet` | read-only `Explore` per partition of about 300 KB of source, in waves of at most 20 | candidate records `file:line · rule · old → new`, quoting the current line in `old` |
| Verify | `model: opus` | read-only `Explore` per partition | every record re-judged against the code and the rule: `fix` (the final `old → new`), `ask` (the question and its options) or `drop` (one-line reason); it adds nothing the scan missed |
| Fix | `model: sonnet` | `general-purpose` per partition; shared files keep one owner | each `fix` record applied verbatim after re-reading `old`; a record whose `old` no longer matches comes back unapplied, never re-judged |

The verifier removes false findings but cannot see a miss, so the scan is re-run with `model: opus` and verified again when:

- a scan report is empty, failed or off-schema;
- its inspected files miss any it was given;
- the verifier drops more than 30% of its records;

A unit that still fails after the Opus re-scan is finished inline by the session.

### Review against the plan

The session model reviews each unit as soon as its agent returns, without waiting for the others. Read the unit's diff (`git diff -- <unit files>`) and compare it with the frozen plan:

- only the planned files changed, and nothing outside the unit's scope;
- signatures and behavior match the spec;
- every rule the spec listed for the unit is applied;
- no abstraction, parameter, or branch the plan did not ask for.

Verdict per unit: accept; fix inline when the gap is trivial; or re-dispatch one tier up with the exact mismatch in the prompt. A unit that still fails after one re-dispatch is finished inline by the session.

After every unit is accepted, the session runs the focused Gradle tests once, then checks the units against each other (callers and callees agree on signatures) and against the plan as a whole before claiming completion.

### Checklist (only when dispatching)

- [ ] A dispatch condition above holds; otherwise work inline
- [ ] Plan frozen by the session; units split by domain, shared files owned once
- [ ] Independent units in one message, each tiered, report length capped
- [ ] A code-changing scan ran as Scan → verify → fix (sonnet → opus → sonnet), with its re-scan triggers checked
- [ ] Each unit's diff reviewed against the plan as it returns; mismatches fixed or re-dispatched
- [ ] Gradle run once by the session, cross-unit contract checked
