---
name: kopring-conventions
description: Use when writing, reviewing, or refactoring Kotlin Spring Boot code — @RestController endpoints and Request/Response DTOs, @Service classes and Command/Result DTOs, JPA entities, Spring Data or QueryDSL Custom*Repository queries, @Transactional boundaries and locks, Flyway migrations, or Spring Boot tests (MockMvc, Testcontainers, MockK, AssertJ); also application*.yml placeholders and @ConfigurationProperties classes; also when auditing Kotlin code for convention violations.
---

# kopring-conventions

Team conventions for Kotlin + Spring Boot backends. The rules live in `references/`; this file routes you to them.

## Before writing code

Read the **Hard Rules table (§1)** of every reference the change touches, then apply it while writing — not afterwards. A table row is a locator: read its linked detail section and exceptions before applying the rule.

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

Without this skill, an agent writing a feature gets these wrong. Check each one before you finish:

- **STY-5/29**: ids are `UUID`, and persisted and DTO timestamps are `ZonedDateTime`. Never use `Long` ids or `Instant` fields.
- **STY-12/54**: put one top-level type per file. Lay out packages as `controller/`, `controller/rest/`, `service/`, `service/command/`, `repository/`, `entity/`. Never use `api/`, `application/` or `domain/`.
- **SVC-3/4/8**: a Service takes a Command and returns a `*Result`, never a raw `Page`/`List` or a view type. Convert with `request.toCommand()`, `command.toEntity()` and `Result.from(entity)`.
- **SVC-38/39**: between domains of one deployable, compose outputs in the controller (or scheduler or listener), inject another domain's Service only when you use its answer, and publish an `*Event` when your state change affects another domain. Between deployables, state changes go over the message broker and HTTP clients only read.
- **SVC-9/10**: `check*` throws. Structural validation goes in `Command.init {}`, never Bean Validation (CTL-14).
- **SVC-13/15**: write exception messages in English and throw named domain exceptions, never generic ones.
- **TX-1/2**: put `@Transactional` on methods, never on the class. Make no external call inside a transaction; use an `AFTER_COMMIT` listener or call it outside the transaction.
- **CTL-3/8/11**: use a nullable parameter instead of `required = false`. Give every Response a `from(result)`. Return paged results as `PaginationResponse`, never `Page`/`PagedModel`.
- **REP-8/9**: two or more filters go into a `*Query` object, read through `pageByQuery` / `listByQuery`.
- **STY-1/10/11**: log through the inherited `logger`. Put a blank line before the final `return`. Use named arguments for calls with 2+ arguments.
- **STY-16–19**: KDoc and line comments are in Korean, current state only, and appear only when their trigger applies. Inline single-use intermediates.
- **CFG-12/15**: a `@ConfigurationProperties` field is read by code, and its default lives in the yml only, never as a Kotlin default.
- **STY-21–28**: keep public methods to about 20 lines. Private-call depth is at most 2. Use the standard library and the plain option first, and add no abstraction without a second real use.
- **TST-5/6/21**: group tests with `@Nested` and name tests and groups with Korean backtick sentences, without `@DisplayName`. Assert with AssertJ only.

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

The IDs come from the codebase these rules were extracted from and are never renumbered. Gaps in a sequence are project-specific rules that were removed.

`⚠` marks a rule whose violation corrupts data, breaks the wire contract, or misleads every reader. Check these first in a review.

A rule marked *"If the project uses X"* applies only when it does.

## Precedence

1. The project's own instructions (`CLAUDE.md`, `AGENTS.md`, `docs/`) override this skill.
2. This skill overrides general-purpose skills such as ponytail and superpowers. Conflicts are settled in the External skill precedence section of [code-style.md](references/code-style.md).
3. Building blocks shown as snippets have a default shape: logger base class, `withRetry`, `TransactionRunner`, `ErrorCode`/`BusinessException`, `translateUniqueViolation`, `PaginationResponse`. If the project already has its own equivalent, use it.

## Checking code

```bash
bash scripts/convention-lint.sh              # whole repository
bash scripts/convention-lint.sh a.kt b.kt    # only these files
```

The path is relative to this skill's directory.

- **Output**: one `path:line: [ID] message` line per hit. The exit code is 1 when anything is found.
- **`BASE_PACKAGE=com.acme`**: sets the root package for the STY-2 FQN check. The default is detected from the sources.

The script covers only the greppable subset of the rules. For a review or audit, run it first, then read the touched code against the Hard Rules tables of its layers.
