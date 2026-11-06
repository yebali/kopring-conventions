---
name: kopring-conventions
description: Use when writing, reviewing, or refactoring Kotlin Spring Boot code — @RestController endpoints and Request/Response DTOs, @Service classes and Command/Result DTOs, JPA entities, Spring Data or QueryDSL Custom*Repository queries, @Transactional boundaries and locks, Flyway migrations, or Spring Boot tests (MockMvc, Testcontainers, MockK, AssertJ); also application*.yml placeholders and @ConfigurationProperties classes.
---

# kopring-conventions

Team conventions for Kotlin + Spring Boot backends. The rules live in `references/`; this file routes you to them.

## Before writing code

Read the **Hard Rules table (§1)** of every reference the change touches, then apply it while writing — not afterwards. Load §1 alone:

```bash
sed -n '/^## 1\. Hard Rules/,/^## 2/p' <kopring-conventions>/references/<file>.md
```

A table row is a locator: open only the detail sections the relevant rows link to, with their exceptions, before applying the rule — `grep -n '^## 5\.' <file>.md` gives the line, then Read with `offset`/`limit`. Never load a whole reference unless the task spans it.

| You are touching | Read |
|---|---|
| any `*.kt` | [code-style.md](references/code-style.md) — always |
| `*Controller.kt`, `controller/rest/*Request.kt` / `*Response.kt`, Feign clients, SSE | [controller.md](references/controller.md) |
| `*Service.kt`, `service/command/*Command.kt` / `*Result.kt`, domain exceptions, enums and `*EnumMapper`, cross-domain communication, Spring events, message consumers | [service.md](references/service.md) |
| `@Transactional`, `TransactionRunner`, an external call near a transaction, locks | [transactions.md](references/transactions.md) |
| `*Repository.kt`, `Custom*RepositoryImpl.kt`, entities, JSONB, Flyway migrations | [repository.md](references/repository.md) |
| `application*.yml`, `${...}` placeholders, `@ConfigurationProperties` / `*Properties.kt` | [configuration.md](references/configuration.md) |
| `*Test.kt` — how a test is written | [testing.md](references/testing.md) |
| which tests must exist, coverage audits | [test-coverage.md](references/test-coverage.md) |
| a rule seems wrong for the case at hand | [rationale.md](references/rationale.md) |

Worked examples: `references/examples/{code-style,service,controller,repository,testing}.md`. Load one when you need a concrete shape.

## Rules most often broken

Without this skill, an agent writing a feature gets these wrong; audits report the code-style rules most. Check each one before you finish:

- **STY-5/29**: ids are `UUID`, and persisted and DTO timestamps are `ZonedDateTime`. Never use `Long` ids (except an explicitly listed generated-`Long`, composite or `String` natural key) or `Instant` fields.
- **STY-12/54**: put one top-level type per file. Lay out packages as `controller/`, `controller/rest/`, `service/`, `service/command/`, `repository/`, `entity/`. Never use `api/`, `application/` or `domain/`.
- **STY-11**: a call passing 2+ arguments names them; no lint checks it.
- **STY-16–18** ([code-style §5](references/code-style.md#5-comments-and-kdoc)): KDoc and line comments are in Korean, current state only, and appear only when a §5.3 trigger holds — never a comment that translates the code or records why it changed.
- **STY-19** (§6): a call's result handed straight to the next call (`val saved = repository.save(…)` then `Result.from(saved)`) is inlined with `.let(::from)` unless a keep condition holds.
- **STY-21–24** (§8): no one- or two-line private method that only delegates; split a public method into step calls once it passes about 20 lines; private-call depth at most 2.
- **STY-26** (§9): `associateBy`, `groupBy`, `ifBlank` … instead of a `forEach` filling a `mutableMapOf()` or a wrapper around one standard-library call.
- **STY-27/28** (§10): one `@Transactional` and a synchronous call before `REQUIRES_NEW`, `@Async` or an executor; no interface, base class, flag or optional parameter without a second real use.
- **SVC-3/4/8**: a Service takes a Command and returns a `*Result`, never a raw `Page`/`List` or a view type. Convert with `request.toCommand()`, `command.toEntity()` and `Result.from(entity)`.
- **SVC-9/10**: structural validation goes in `Command.init {}`, never Bean Validation (CTL-14).
- **SVC-38/39**: never inject another domain's Service just to tell it about your state change — publish an `*Event`. A state change another deployable makes without the caller waiting goes as a `*Message`, not an HTTP call.
- **TX-1/2**: `@Transactional` on methods, never on the class. No external call inside a transaction; use an `AFTER_COMMIT` listener or call it outside.
- **CTL-3/11**: a nullable parameter, never `required = false`; paged results as `PaginationResponse`, never `Page`/`PagedModel`.
- **CFG-12/15**: a `@ConfigurationProperties` field is read by code, and its default lives in the yml only, never as a Kotlin default.
- **TST-5**: group tests with `@Nested` and name tests and groups with Korean backtick sentences, without `@DisplayName`.
- **REP-8/9**: two or more filters go into a `*Query` read through `pageByQuery` / `listByQuery`, never a derived `findByAAndBAndC…` or a method taking several filter parameters.

## Rule IDs

Rule IDs take the form `PREFIX-N`:

| Prefix | Area |
|---|---|
| `STY` | Code style |
| `SVC` | Services |
| `TX` | Transactions |
| `CTL` | Controllers |
| `REP` | Repositories and entities |
| `TST` | Test mechanics |
| `COV` | Test coverage |
| `CFG` | Configuration properties |

The IDs come from the codebase these rules were extracted from and are never renumbered except as recorded in the repository's `CHANGELOG.md` (`CTL-30` → `CTL-32`). Gaps in a sequence are project-specific rules that were removed, or a number a consuming project uses for its own rule (`CTL-30`).

`⚠` marks a rule whose violation corrupts data, breaks the wire contract, or misleads every reader. Check these first in a review.

A rule marked *"If the project uses X"* applies only when it does.

## Precedence

1. The project's own instructions (`CLAUDE.md`, `AGENTS.md`, `docs/`) override this skill.
2. This skill overrides general-purpose skills such as ponytail and superpowers. Conflicts are settled in the External skill precedence section of [code-style.md](references/code-style.md).
3. Building blocks shown as snippets have a default shape: logger base class, `RetryTemplate` usage, `TransactionRunner`, `ErrorCode`/`BusinessException`, `translateUniqueViolation`, `PaginationResponse`. If the project already has its own equivalent, use it.

## Checking code

```bash
bash <kopring-conventions>/scripts/convention-lint.sh a.kt b.kt          # these files; no arguments = whole repository
bash <kopring-conventions>/scripts/blank-line-before-return.sh a.kt b.kt # STY-10; --fix a.kt inserts the blank lines
bash <kopring-conventions>/scripts/changed-files.sh                      # in-scope paths changed on this branch; `base: <branch>` on stderr
```

`<kopring-conventions>` is this skill's directory; run the scripts from the project's repository, not from here.

- **Output**: one `path:line: [ID] message` line per hit (`path:line` for STY-10). The exit code is 1 when anything is found, and 2 when no Kotlin source file was scanned — never read exit 2 as clean.
- **`BASE_PACKAGE=com.acme`**: sets the root package for the STY-2 FQN check. The default is detected from the sources.
- **`.convention-lint-ignore`** at the project root: one `path-glob:ID` per line for an exception the project's own rule document grants; `path-glob:*` exempts a whole tree, which `changed-files.sh` also drops.

The lint covers only the greppable subset of the rules. For a read-only review, run it first, then read the touched code against the Hard Rules tables of its layers. An audit that also fixes is the `check-conventions` skill.
