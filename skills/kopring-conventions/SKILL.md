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
| `*Service.kt`, `*Facade.kt`, `service/command/*Command.kt` / `*Result.kt`, domain exceptions, enums and `*EnumMapper`, cross-domain communication, Spring events, message consumers | [service.md](references/service.md) |
| `@Transactional`, a `*Facade`, `TransactionRunner`, an external call near a transaction, locks | [transactions.md](references/transactions.md) |
| `*Repository.kt`, `Custom*RepositoryImpl.kt`, entities, JSONB, Flyway migrations | [repository.md](references/repository.md) |
| `application*.yml`, `${...}` placeholders, `@ConfigurationProperties` / `*Properties.kt` | [configuration.md](references/configuration.md) |
| `*Test.kt` — how a test is written | [testing.md](references/testing.md) |
| which tests must exist, coverage audits | [test-coverage.md](references/test-coverage.md) |
| a rule seems wrong for the case at hand | [rationale.md](references/rationale.md) |

Worked examples: `references/examples/{code-style,service,controller,repository,testing}.md`. Load one when you need a concrete shape.

## Rules most often broken

Without this skill, an agent writing a feature gets these wrong; audits report the code-style rules most. Check each one before you finish:

- **STY-5/29**: ids are `UUID`, and persisted and DTO timestamps are `Instant`. Never use `Long` ids (except an explicitly listed generated-`Long`, composite or `String` natural key) or `ZonedDateTime` fields.
- **STY-12/54**: put one top-level type per file. Lay out packages as `controller/`, `controller/rest/`, `service/`, `service/command/`, `repository/`, `entity/`. Never use `api/`, `application/` or `domain/`.
- **STY-11**: in a call with 2+ arguments, same-typed arguments and every `Boolean`, `null` or literal are named; no lint checks it.
- **STY-16–18** ([code-style §5](references/code-style.md#5-comments-and-kdoc)): every public top-level type and public function carries a one-line Korean KDoc that adds a fact its name does not carry. All comments and KDoc state current behavior only — no past decisions, design or change reasons, history, or future plans, including exception KDoc and `// ponytail:` comments. Line comments are Korean and appear only when a §5.3 trigger holds; never translate the code.
- **STY-19** (§6): a call's result handed straight to the next call (`val saved = repository.save(…)` then `Result.from(saved)`) is inlined with `.let(::from)` unless a keep condition holds.
- **STY-21–24** (§8): no one- or two-line private method that only delegates; split a public method into step calls once it passes about 20 lines; private-call depth at most 2.
- **STY-26** (§9): `associateBy`, `groupBy`, `ifBlank` … instead of a `forEach` filling a `mutableMapOf()` or a wrapper around one standard-library call.
- **STY-27/28** (§10): one Service transaction and a synchronous call before a Facade, `REQUIRES_NEW`, `@Async` or an executor; no interface, base class, flag or optional parameter without a second real use.
- **SVC-3/4/8**: a Service takes a Command and returns a `*Result`, never a raw `Page`/`List` or a view type. Convert with `request.toCommand()`, `command.toEntity()` and `Result.from(entity)`.
- **SVC-9/10/15**: structural validation goes in `Command.init {}` through `requireValid`, never Bean Validation (CTL-14) or the stdlib `require`.
- **SVC-38/39**: never inject another domain's Service just to tell it about your state change — publish an `*Event`. A state change another deployable makes without the caller waiting goes as a `*Message`, not an HTTP call.
- **TX-1/2/3**: every `@Service` carries class-level `@Transactional`, with `readOnly = true` on the methods that change nothing. A Service injects no outbound client; a flow with an external call is a `*Facade`, or an `AFTER_COMMIT` listener for a side effect.
- **CTL-3/11**: a nullable parameter, never `required = false`; paged results as `PaginationResponse`, never `Page`/`PagedModel`.
- **CFG-12/15**: a `@ConfigurationProperties` field is read by code, and its default lives in the yml only, never as a Kotlin default.
- **TST-5/6/8**: group tests with `@Nested` and name tests and groups with English backtick sentences, without `@DisplayName`. A controller test extends `WebMvcTestSupport` and mocks the Service; a repository test extends `DataJpaTestSupport`.
- **REP-8/9/44**: two or more filters go into a `*Query` read through `pageByQuery` / `listByQuery`, never a derived `findByAAndBAndC…` or a method taking several filter parameters. A list read is `listByQuery` from the first one — never a derived `findAllBy*`.
- **REP-15/27**: a reference to another domain's entity is its id (`memberId: UUID`), never a `@ManyToOne`. A soft-delete query states no `deletedAt.isNull`: the shared `@Filter` adds it. The filter skips primary-key loads (`findById`, a `@ManyToOne`, a to-one `join fetch`), so the Service drops a deleted row itself (`getActiveEntity` or an `isDeleted` check).

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

The IDs come from the codebase these rules were extracted from and are never renumbered except as recorded in the repository's `CHANGELOG.md` (`CTL-30` → `CTL-32`). Gaps in a sequence are project-specific rules that were removed, or a number a consuming project uses for its own rule (`CTL-30`, `SVC-43`).

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
