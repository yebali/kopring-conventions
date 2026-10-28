---
name: coding-workflow
description: "Use when starting ANY coding task in a Kotlin Spring Boot repository — implementing, refactoring, fixing bugs, writing or running tests, exploring code, or auditing — before the first code read or edit, and before dispatching ANY subagent. Sets the always-on baseline: apply the kopring-conventions rules while writing, run the lint before saying done, and plan, tier and review parallel subagent work."
---

# Coding Workflow — Always-On Baseline

Loaded at the start of every coding task. It owns the cross-cutting execution policy; keep each policy to one short H2 section. The rules themselves live in the `kopring-conventions` skill (`references/`); `<kopring-conventions>` below means that skill's directory.

## Write it right the first time

The `convention-check` skill catches what slipped through; it should find little. Before writing Kotlin, read the Hard Rules table of every `kopring-conventions` reference you touch and apply it while writing, not afterwards. The rules an audit reports most often are the code-style Hard Rules ([code-style.md](../kopring-conventions/references/code-style.md) §1), the comment policy (STY-16–18, §5), single-use intermediates (STY-19, §6), method shape (STY-21–24, §8), standard library first (STY-26, §9), and the plain option (STY-27–28, §10). The references own the rule text; put the rule IDs (`STY-19`, `SVC-15`, …) into every subagent prompt that edits Kotlin.

**Before you say done**:
1. `bash <kopring-conventions>/scripts/convention-lint.sh <touched .kt files>` and `bash <convention-check>/scripts/blank-line-before-return.sh` (whole tree, one awk pass) — both `total: 0`.
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
- Read-only units use `subagent_type: Explore`; edit units use `general-purpose` or `worker`.
- Tier every unit: locate/list or a pinned literal edit → `model: haiku`; a read-and-summarize `Explore` or frozen-spec implementation → `model: sonnet`; authorization, transaction and lock boundaries, migrations, design → inherit the session model. A unit that fails on a cheaper tier is re-dispatched one tier up (`retier:`) with the exact mismatch in the prompt.
- **Cap every report** in the prompt (e.g. ≤30 lines, `file:line` + one-line finding, no restating the prompt) — the report lands in the session context.

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
- [ ] Each unit's diff reviewed against the plan as it returns; mismatches fixed or re-dispatched
- [ ] Gradle run once by the session, cross-unit contract checked
