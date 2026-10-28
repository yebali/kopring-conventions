---
name: test-code
description: "Use when the user wants integration tests written for the code changed in the current diff — MockMvc tests for new or modified @RestController endpoints and Service methods. Triggers on \"write tests for my changes\", \"generate integration tests\", \"test the changed code\", \"add MockMvc tests\", \"cover the diff\", \"test code\". Scoped to the change, not the whole module. NOT for auditing existing coverage across the codebase (use convention-check)."
---

# Test Code — MockMvc Integration Tests for the Current Diff

Write or modify **end-to-end MockMvc integration tests for the code changed in the current diff** — scoped to the change, not the whole module. `<kopring-conventions>` below means that skill's directory.

## Conventions — defer to `kopring-conventions`

Read [testing.md](../kopring-conventions/references/testing.md) (`TST-N`, how a test is written) and [test-coverage.md](../kopring-conventions/references/test-coverage.md) (`COV-N`, which tests must exist) first, plus the repository's own `CLAUDE.md` / `AGENTS.md` for overrides. This skill does not repeat those rules.

## Method

- **Output language**: write the summary in the user's language.
- **Dispatch**: for 2+ changed classes follow the dispatch rules and model tiering of [coding-workflow](../coding-workflow/SKILL.md#parallel-dispatch--model-tiering). Read-only scan units are `Explore` subagents dispatched in one single message; edit units are `general-purpose` or `worker`. A single changed class is handled inline.

## Steps

1. **Scope from the diff**: run `git diff` and `git status` (committed-since-base, working-tree and untracked changes); identify every changed or newly added Controller endpoint and Service method.
2. **Source cross-reference** (COV-1 / COV-3): for each changed Controller or Service, list its public endpoints or methods, cross-reference the existing `*Test.kt`, and target the untested ones first — do not add redundant coverage. When 2+ classes changed, fan this out with one `Explore` subagent per class.
3. **Write tests** per the TST rules: every test calls the real endpoint through `mockMvc` and verifies the **HTTP contract** (status, response schema, error code) — state effects belong to the Service-layer test, not this one. Apply the full COV-1 parameter-variation matrix to each changed endpoint. When fanning out test *writing*, partition per **module**, not per class — concurrent agents in one module conflict on the module's shared test base class (TST-2 / TST-3). Each writing unit's prompt carries the TST/COV rule IDs and forbids `git commit`, Gradle runs and files outside its list.
4. **Run and verify**: batch each module's test classes into ONE invocation with repeated `--tests` flags — `./gradlew :<module>:test --tests "ATest" --tests "BTest"` — instead of one Gradle run per class (saves repeated JVM and Spring-context warm-ups). Confirm all green. A new test that fails because production behaves differently from the rule is reported, not "fixed" by weakening its assertion.
5. **Summarize** briefly: tests written per target, the COV rule each satisfies, and the run result.
