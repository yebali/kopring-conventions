# kopring-conventions

Kotlin + Spring Boot coding conventions as agent skills: controllers, services, transactions, JPA/QueryDSL repositories and tests. The rules carry stable identifiers (`STY-5`, `SVC-3`, `TX-1`, …) so a review, a commit message or a project document can cite one.

## Skills

| Skill | Use it to |
|---|---|
| `kopring-conventions` | Write, review or refactor Kotlin Spring Boot code. Holds the rule references, worked examples and `scripts/convention-lint.sh`. |
| `coding-workflow` | Set the baseline for any coding task: apply the rules while writing, run the lint before saying done, plan and review parallel subagent work. |
| `check-conventions` | Audit production and test code (and `application*.yml`) against the rules, fix the violations a rule decides, write missing tests and ask about the rest. It edits code. |
| `structure-check` | Find code that follows every rule yet is too complex or tangled, and write a refactoring plan. It never edits code. |
| `sync-docs` | Find where the markdown docs no longer match the code and fix the docs. It never edits code. |
| `test-code` | Write MockMvc integration tests for the code changed in the current diff, following the testing and coverage rules. |

An installed skill is also a slash command: `/kopring-conventions`, `/coding-workflow`, `/check-conventions`, `/structure-check`, `/sync-docs`, `/test-code`.

## Install

```bash
npx skills add yebali/kopring-conventions -g
```

`-g` installs for the user, so every project sees the skills. Without it the skills land in the current project (`.agents/skills/`). Run the same command again to update.

## Rules

The rules live in `skills/kopring-conventions/references/`. Each document starts with a Hard Rules table that lists every rule on one line and links to its full text, exceptions and example.

| Prefix | Document | Area |
|---|---|---|
| `STY` | `code-style.md` | Style, comments, logging, files, naming |
| `SVC` | `service.md` | Services, Command/Result, exceptions, cross-domain communication, events |
| `TX` | `transactions.md` | Transaction boundaries, external calls, locks |
| `CTL` | `controller.md` | Controllers, wire DTOs, REST design |
| `REP` | `repository.md` | Repositories, queries, entities, migrations |
| `TST` | `testing.md` | How a test is written |
| `COV` | `test-coverage.md` | Which tests a suite needs |
| `CFG` | `configuration.md` | Environment placeholders and `@ConfigurationProperties` classes |

`rationale.md` records why a rule exists. `examples/` holds one worked example file per layer. Identifiers are never renumbered once a consuming project relies on them; a gap in a sequence is a project-specific rule that was removed, or a number a consuming project uses for its own rule (`CTL-30`). A `⚠` marks a rule whose violation corrupts data, breaks the wire contract or misleads every reader.

A project's own instructions (`CLAUDE.md`, `AGENTS.md`, `docs/`) override these rules. List only the differences there, keyed by rule ID, and cite the skill for the rest.

## Lint

```bash
bash skills/kopring-conventions/scripts/convention-lint.sh              # whole repository
bash skills/kopring-conventions/scripts/convention-lint.sh a.kt b.kt    # only these files
bash skills/kopring-conventions/scripts/blank-line-before-return.sh [--fix] [a.kt b.kt]   # STY-10
```

Run them from the project's repository. `convention-lint.sh` prints one `path:line: [ID] message` line per hit; both scripts exit 1 when anything is found and 2 when no Kotlin source file was scanned. `BASE_PACKAGE=com.acme` sets the root package for the fully-qualified-name check; the default is detected from the sources. A project lists the exceptions its own rule document grants in `.convention-lint-ignore` at its root, one `path-glob:ID` per line. The lint covers only the greppable subset of the rules.

## Layout

```
skills/
  kopring-conventions/   SKILL.md, references/, references/examples/, scripts/
  coding-workflow/       SKILL.md
  check-conventions/     SKILL.md
  structure-check/       SKILL.md, scripts/structure-metrics.sh
  sync-docs/             SKILL.md
  test-code/             SKILL.md
```

The installer only discovers skills under `skills/` when the repository root has no `SKILL.md`, so keep it that way. `check-conventions` and `structure-check` link to `../kopring-conventions/references/`, which works when the skills are installed side by side.

## Changing a skill

Edit and commit here, push to `main`, then run the install command above in each place that uses the skills. Do not edit an installed copy.

### Adding or changing a rule

- A new rule takes its prefix's highest number + 1. A gap is never reused.
- Before picking the number, check the project-rule document of each known consuming project (`docs/conventions/PROJECT_RULES.md`) for local identifiers above the current highest number, and skip them: a project rule with the same identifier silently overrides the skill rule there.
- A new rule adds its Hard Rules row, its detail paragraph and a `rationale.md` entry; an example only when the shape is unfamiliar.
- Record every added, changed, removed or renumbered identifier in [CHANGELOG.md](CHANGELOG.md).
