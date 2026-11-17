# Changelog

Rule identifiers added, changed, removed or renumbered, newest first. A consuming project checks this list when it updates the skill, because its own rule document overrides the skill by identifier.

## 2026-11-17

- **Changed** `STY-17`, `STY-18`: every source comment and KDoc describes current behavior only. Past decisions, design and change reasons, earlier behavior, ticket or migration history, and future improvement plans stay outside source comments. A `// ponytail:` comment states only the current operational limit and no longer bypasses the rationale check.
- **Changed** `REP-2`, `SVC-20`: exception KDoc names the current framework constraint, dependencies and behavior; its approval rationale and proposed changes stay in decision records. The rule table, comment decision table, worked examples and `rationale.md` follow the same policy.

## 2026-11-16

- **Changed** `CTL-31`: the frontend derives only what needs no definition — presence, the count or sum of a whole list, a structural position, display formatting. Every other derived value a screen reads is sent: a count or sum over the elements a condition selects, a difference, ratio, average or progress, a verdict, a value that needs data outside the Response, a policy calculation. The rule was "whatever the frontend can compute from the same Response, except the listed cases", which left a conditional count and an average to the frontend. A conditional count stays with the frontend when the screen must list the selected elements anyway. A child that belongs to a parent is now nested under it. Adopting it: a Response that dropped a conditional count, a difference or an average under the earlier rule sends it again when a screen reads it.

## 2026-11-13

Two batches on one day: fifteen new rules for gaps the rule set left open, and a review of the rules that depart from common Kotlin and Spring practice, decided one by one with the maintainer. Thirteen of those were kept as they were (CTL-14, CTL-19, REP-1, REP-7, SVC-6, REP-35, STY-1, STY-34, CTL-33, STY-54, SVC-3, STY-19, STY-28, COV-6); the rest changed and are listed under "Reversed or relaxed".

Adopting these changes in an existing project — the size of the work, measured by running the lint on one consuming project: about 8,400 Korean test and `@Nested` names (TST-5, TST-6), 100 Services without class-level `@Transactional` (TX-1), 25 derived list queries (REP-44), 8 outbound clients injected into a Service (TX-2). Not counted by the lint: `ZonedDateTime` fields (STY-29), cross-domain `@ManyToOne` mappings (REP-15), `deletedAt.isNull` predicates (REP-27), full-context controller tests (TST-8) and missing public KDoc (STY-16). Until a project has moved, it keeps the earlier rule under the same identifier in its own rule document and lists the lint exceptions in `.convention-lint-ignore`.

- **Setup** (`check-conventions all`, Check F): the three test support classes and the wipe (TST-2, TST-12); the `@FilterDef` and the `SoftDeleteFilter` helper (REP-27); the shared `requireValid` (SVC-15); no global `rollbackOn` override (TX-15); `spring.data.web.pageable.max-page-size` (CTL-34); a timeout property for every outbound client (CFG-21); one mutable test clock, reset after each test (TST-35); `version` in the Response and the PUT Request of each `@Version` entity (TX-16).
- **Identifiers:** `SVC-43` is skipped, because a consuming project uses it for its own rule.

Reversed or relaxed:

- **Changed** `TX-1`: a `@Service` carries class-level `@Transactional`, with `readOnly = true` on the methods that change nothing; no other bean carries the annotation. It was method-level only.
- **Changed** `TX-2`, `TX-3`, `TX-4`: a Service injects no outbound bean, and a use case with an external call around its DB work is a `*Facade` (`SVC-30` gains the role). The options "delegate to a collaborator" and "programmatic boundary in the Service" are gone. `STY-27`, `CTL-28`, `TX-5`, `TX-6`, `TX-9` follow.
- **Changed** `TX-15`: Spring's default rollback rule; a method that can let a checked exception escape declares `rollbackFor`. The global `rollbackOn = ALL_EXCEPTIONS` switch is dropped.
- **Changed** `REP-15`: a reference to another domain's entity is its id only; `@ManyToOne` stays inside a domain. `STY-14`, `STY-34`, `REP-14`, `REP-21`, `REP-36` follow.
- **Changed** `REP-27`: deleted rows are left out by one auto-enabled Hibernate `@Filter` that a read can switch off; no predicate repeats `deletedAt.isNull`. An own-PK read is still filtered in the Service (`SVC-18`).
- **Added** `REP-44`: a list or page read is the repository's one `listByQuery` / `pageByQuery` from the first read on; a derived `findAllBy*` is gone. `REP-2`, `REP-8`, `REP-9` follow.
- **Changed** `STY-29`: timestamps are `Instant`. `STY-32`, `STY-58`, `CFG-20`, `TST-25`, `REP-40` follow.
- **Changed** `STY-11`: names are required for same-typed arguments and for a `Boolean`, `null` or literal, not for every call with two arguments.
- **Changed** `STY-16`: every public top-level type and public function carries a one-line KDoc; a private one keeps the trigger test. Tags stay banned.
- **Changed** `SVC-10`, `SVC-14`, `SVC-15`: a Command's structural check is `requireValid`, one shared function with `CommonErrorCode.INVALID_PARAMETER`; a named domain exception is for a business failure.
- **Changed** `TST-2`, `TST-3`, `TST-8`, `TST-33`: three support classes per module — `WebMvcTestSupport` (controllers against mocked Services), `DataJpaTestSupport` (repositories, rolled back), `SpringBootTestSupport` (Services and Facades, real transactions). `TST-15`, `TST-19`, `COV-1`, `COV-2`, `COV-3`, `COV-5`, `COV-6`, `COV-7` follow.
- **Changed** `TST-11`, `TST-12`, `TST-14`: a Service test's rows are truncated by the support after each test; the rule "never clean up, assert over owned data" is gone.
- **Changed** `TST-5`, `TST-6`, `TST-19`: test and `@Nested` names are English sentences in backticks.

New rules:

- **Added** `TX-16`: the PUT of a `@Version` entity carries the `version` the client read, and the Service compares it. `TX-14` points to it.
- **Added** `TX-17`: a `readOnly = true` method writes nothing, directly or through a collaborator.
- **Added** `TX-18`: a proxy-driven annotation works only on a public method another bean calls.
- **Added** `SVC-44`: the scope key of a row-scoped operation comes from the principal; an out-of-scope row is a 404.
- **Added** `SVC-45`: a Command checks the length of every column-bound `String` and the size of every collection.
- **Added** `STY-59`: a singleton bean's mutable field is a thread-safe type. `STY-35` follows.
- **Added** `STY-60`: a `when` over an enum or a sealed type has no `else`.
- **Added** `REP-39`: renaming or removing an entity enum constant ships with a migration that rewrites the stored values.
- **Added** `REP-40`: a time-range filter is half-open.
- **Added** `REP-41`: an `orphanRemoval` collection is never reassigned.
- **Added** `REP-42`: no `Optional`; `getReferenceById` only for a row the transaction already proved to exist.
- **Added** `REP-43`: no unbounded `findAll()`.
- **Added** `CTL-34`: a growing collection is paged, and `max-page-size` caps the page.
- **Added** `CFG-21`: every outbound client declares its timeouts.
- **Added** `TST-35`: one shared test clock, reset after each test. `STY-58` points to it.

Other changes and fixes:

- **Changed** `SVC-29`: covers external codes only; an unknown value in an `@Enumerated` column fails on load, which REP-39 prevents.
- **Changed** `COV-1`: one missing-field case omits a primitive field; the page-size boundary is the cap of CTL-34.
- **Fixed** the `CreateOrderRequest(memberId = …)` test examples (TST-19, TST-20): the Request has no `memberId`, which comes from the principal.

Verified by execution — each behaviour below was run in a throwaway project on Spring Boot 4.1.2 (Hibernate 7.4.13, Spring Framework 7.0.10, Spring Data JPA 4.1.2, Jackson 3.1.7) against PostgreSQL 16.15, 18.7 (the latest release) and 19 RC 2 (general availability is planned for 2026-11-19). All three gave the same result, and the rule text matches what was observed:

- `REP-27`: an auto-enabled `@Filter` declared on a `@MappedSuperclass` filters JPQL and derived queries, `existsById` and `findAllById`; it does not filter `findById`, a lazy `@ManyToOne` or a to-one `join fetch`; a collection is filtered only when it carries `@Filter` itself; `disableFilter` switches the auto-enabled filter off for the session, and the next transaction has it on again.
- `TX-16`: a stale value assigned to the `@Version` field of a managed entity is ignored and the write goes through.
- `TX-17`: a dirty-checked change, a `save` and a collaborator's write inside a read-only transaction are all dropped without an error; `saveAndFlush` is rejected by PostgreSQL.
- `TX-1`, `TX-18`: a method-level `@Transactional` replaces the class-level attributes; a private or self-invoked annotated method gets no transaction and no attributes of its own.
- `TX-15`: a checked exception commits, `rollbackFor` rolls it back, and `TransactionTemplate` rolls back and wraps it in `UndeclaredThrowableException`.
- `REP-39`, `REP-41`, `REP-42`: an unknown enum value fails on load; reassigning an `orphanRemoval` collection throws at flush while `clear()` + `addAll()` works; `getReferenceById` of a missing id fails on first access or as a foreign-key violation at flush.
- `CTL-34`: the page size defaults to 20, is clamped to 2000 without the property and to the configured cap with it, and `size=0` falls back to the default.
- `STY-29`, `TST-25`, `COV-1`: an `Instant` maps to `timestamp with time zone`, serializes with `Z`, accepts a request offset, and equals its re-read copy only when truncated to micros; a missing `Int` or `Boolean` body field is a 400.
- `TST-2`, `TST-8`, `TST-19`: `@WebMvcTest` without a controller list loads every controller, no repository and no `DataSource`, and takes a `@MockkBean` Service; `@DataJpaTest` with `replace = NONE` runs transactional, allows bulk DML and rolls back.
- The lint scripts also pass their fixtures on Linux (mawk 1.3.4, GNU grep 3.11).

Tooling:

- `convention-lint.sh` — new checks: TX-1 (`@Service` without class-level `@Transactional`, or the annotation on another bean), TX-2 (a `*Client` in a Service), TX-18, STY-36, STY-59, SVC-9, CTL-2, CTL-6, REP-8 `get*`, REP-16, REP-35, REP-40, REP-42, REP-44, CFG-15, TST-5 and TST-6 names, TST-31; REP-27 also flags `@SoftDelete`; SVC-13 also reads `requireValid`. Tried against a real project and left agent-judged because most hits were legitimate: STY-33 unit-suffixed constants, STY-54 package names, REP-43 `findAll()`, `getReferenceById`.
- `scripts/tests/run.sh` copies `tests/tree/` as is, for the checks that read a path (`controller/rest/`, `src/test/`).
- `check-conventions`: Check F covers the setup items above; a Service with method-level annotations is a `fix`, a Service that calls out, a cross-domain `@ManyToOne` and a derived list query are `ask`. `test-code` writes controller tests in the web slice, and Facade and repository tests.

## 2026-11-06

Consistency pass: no rule added or renumbered; texts that disagreed with each other now say one thing.

- **Changed** `CTL-25`: the Hard Rules line matches its detail and SVC-38 — a client calling another deployable makes only calls the caller waits on (writes included), not reads only.
- **Changed** `CTL-29`: the inbound adapter wraps the wire DTO, `service.x(XCommand.from(message))`; the Service takes the Command (SVC-3, CTL-24). Examples follow.
- **Changed** `REP-35`: scoped to JPA `@Entity`/`@MappedSuperclass`/`@Embeddable`; a `@RedisHash` entity stays a `data class` (REP-31).
- **Changed** `REP-12`, `REP-23`, `REP-38`: the sort transformer is defined under REP-12 and always receives the query's `SORTABLE` set.
- **Changed** `TST-4`: relies on springmockk's per-test mock clearing (TST-26), not a base `clearAllMocks()`.
- **Changed** `STY-54`: adds the `<domain>.<broker>` package for inbound message handlers (CTL-24).
- **Fixed** the `PaginationResponse` default snippet still carrying `sort` (CTL-11), and ✅ examples that broke STY-11, STY-19, STY-32, SVC-8, SVC-35, REP-17, CTL-19 and TX-9.
- **Lint:** `blank-line-before-return.sh` flags only a function's final top-level `return` (STY-10 as written; early returns in inner blocks are no longer hits). `convention-lint.sh` adds STY-12, labels `restoreSharedDoubles` as TST-26 and `deleteAllBy*` as REP-8, applies `.convention-lint-ignore` from any working directory, and accepts `*` as the rule ID for an exempt tree. New `changed-files.sh` lists a branch's in-scope changes.
- **Skills:** `kopring-conventions` loads a reference's §1 table first instead of the whole file; `check-conventions` caps a run at 20 agents of ~150 files and reports STY-28 folds as `ask`; `structure-metrics.sh` runs in about a second and walks only the modules in `settings.gradle.kts`.

## 2026-10-30

Adopting these changes in an existing project — run `check-conventions all`, whose Check F covers the setup items; the lint covers the line items:

- **Setup:** `@EnableTransactionManagement(rollbackOn = RollbackOn.ALL_EXCEPTIONS)` and the `TransactionRunner` unwrap (TX-15); a `Clock` bean (STY-58); `TZ`, `hibernate.jdbc.time_zone` and `spring.jackson.time-zone` (CFG-20); the scheduling switch off in the test profile (TST-34); `plugin.jpa` and all-open (REP-35); one Feign adapter test per client (COV-9); one migration guard test per module (COV-10); the authorization interceptor on in the shared test support (COV-2); `sort` dropped from the project's `PaginationResponse` (CTL-11).
- **Line items the lint reports:** STY-45 retry predicate defaults, STY-58 no-argument `now()`, SVC-24 `.constraintName`, SVC-34 listener flags, REP-14 `@Column(unique = true)`, REP-15 `@ManyToOne` without `LAZY`, REP-30 `deleteAllBy*`, TST-7 `restoreSharedDoubles`, TST-33 per-class context changes.
- **The project's rule document:** an override that restates a rule corrected here (for example REP-29 "owning relationships", REP-33 "applied migrations", SVC-24, STY-45 `withRetry`, COV-2 `@TestPropertySource`) keeps the old text in force until it is updated. Add the lint exceptions it grants to `.convention-lint-ignore`.

New rules:

- **Added** `TX-14`: a concurrently edited entity carries `@Version`; counters change through an atomic UPDATE.
- **Added** `TX-15`: every exception rolls back (`RollbackOn.ALL_EXCEPTIONS`); `TransactionRunner` rethrows the original exception.
- **Added** `SVC-42`: a message whose loss breaks another deployable goes through an outbox or a named reconciliation job.
- **Added** `REP-35`: entities are plain classes without `equals`/`hashCode`; `plugin.jpa` and all-open.
- **Added** `REP-36`: foreign keys are indexed; `idx_` and `fk_` names.
- **Added** `REP-37`: online migrations on large tables.
- **Added** `REP-38`: a paged read sorts only by allowed properties. `REP-23` points to it.
- **Added** `CTL-33`: fields, enum values and endpoints are removed or renamed directly; consumers are told or changed in the same change.
- **Added** `STY-58`: the current time comes from an injected `Clock`. `STY-29`, `REP-27` (`delete(now)`) follow.
- **Added** `CFG-20`: JVM, Hibernate and Jackson time zones are pinned.
- **Added** `TST-34`: the test profile switches off schedulers and self-starting workers.
- **Added** `COV-9`: each Feign client has an adapter test against a stub HTTP server.
- **Added** `COV-10`: each module has a migration guard test; `TST-33` allows it its own context.

Tooling:

- `blank-line-before-return.sh` (STY-10) moved to `kopring-conventions/scripts/` and takes a file list; `--fix` touches only the files given.
- `convention-lint.sh`: SVC-15 scoped to Services and Commands; SVC-13 no longer flags `logger.error`; STY-1 also flags `KotlinLogging.logger`; CTL-14 and TST-21 widened; new checks for CTL-3, CTL-10, CTL-12, CTL-19, SVC-20, STY-30, STY-43, REP-10, REP-27, TST-27; `.convention-lint-ignore` for project exceptions; exit 2 when no file was scanned.
- `check-conventions` audits CFG rules and `application*.yml`, runs the scripts on the in-scope files only, and no longer edits the installed references. `sync-docs` gains a scoped mode for it. `test-code` takes committed branch changes and writes Service tests.

Contradictions between rules, resolved:

- **Added** `TST-33`: no test class forks the shared Spring context.
- **Changed** `STY-40`, `STY-41`: `runCatching` only where a failure is absorbed; a catch in a `suspend` function rethrows `CancellationException`.
- **Changed** `STY-34`, `STY-35`: an entity change line is always INFO; an unbounded bulk change uses bulk DML and one INFO summary. No id lists of LAZY collections.
- **Changed** `STY-4`, `STY-7`: field injection is test-only.
- **Changed** `STY-17`: log messages are English.
- **Changed** `STY-54`: `api`, `application` and `domain` packages are banned explicitly.
- **Changed** `TX-1`, `TX-6`, `SVC-2`: `readOnly = true` on every Service read; TX-6 governs programmatic boundaries only.
- **Changed** `SVC-24`, `SVC-25`: a link is a join row without data and is created by `ON CONFLICT DO NOTHING`; 409 is for entities carrying data; the constraint name comes from `PSQLException`.
- **Changed** `REP-14`, `REP-28`: no `@Column(unique = true)`; a named `@Table(uniqueConstraints)`, none on a soft-delete column.
- **Changed** `REP-27`, `SVC-18`: derived and own-PK reads may return deleted rows; the Service filters them.
- **Changed** `REP-29`: cascade only from a parent's `@OneToMany`/`@OneToOne`, never from `@ManyToOne`.
- **Changed** `REP-8`, `REP-30`: one Query class per filter axis; a bulk delete is `bulkDeleteBy*`.
- **Changed** `CTL-3`, `CTL-19`: a PUT replaces the whole resource; `null` clears a field.
- **Changed** `COV-1`, `COV-2`, `COV-3`, `COV-6`: 204 for a `Unit` endpoint; the authorization interceptor is on in the shared support; a Service success test asserts a business effect.
- **Changed** `TST-7`, `TST-12`, `TST-13`, `TST-14`, `TST-32`: `init()` assigns no fixture field; one parameterized table per code path.

Corrections to statements that were wrong for Spring Framework 7, Hibernate 7, Spring Boot 4 and springmockk 5:

- **Changed** `TX-2`, `SVC-40`: an `AFTER_COMMIT` listener still holds the pooled connection; only a short call with a configured timeout runs inline, a slow one goes to a Spring-managed executor. A fire-and-forget publish needs a bounded `max.block.ms`.
- **Changed** `SVC-34`: `fallbackExecution = true` only on `AFTER_COMMIT`/`BEFORE_COMMIT`; never on `AFTER_ROLLBACK`/`AFTER_COMPLETION`.
- **Changed** `TX-4`: compensate only a definite failure; an unknown outcome stays pending for reconciliation; a state-changing call sends an idempotency key.
- **Changed** `TX-5`: the `TransactionRunner` snippet returns `execute { }` directly (Spring 7 JSpecify); the `T?` reason is gone.
- **Changed** `SVC-23`: justified by intent; JDBC batching needs `hibernate.jdbc.batch_size` and `order_inserts`.
- **Changed** `REP-2`: the `@EntityGraph` exception for `MultipleBagFetchException` is removed.
- **Changed** `REP-4`: at most one collection fetch join per query, none in a paged read; `Set` is no longer the workaround.
- **Changed** `REP-15`: `@ManyToOne(fetch = FetchType.LAZY)` is written explicitly.
- **Changed** `REP-21`: a list read using a delegated property fetch-joins the relation.
- **Changed** `REP-22`: reason restated; `⚠` dropped.
- **Changed** `REP-32`: the edit window ends at the merge to the shared branch; the boot failure is Flyway validation. `REP-33` follows.
- **Changed** `CFG-2`: a bare placeholder does not fail startup for `@ConfigurationProperties`; the properties class checks required values in `init`.
- **Changed** `STY-1`: the carve-out covers any supertype declaring `logger`; the base class strips `$Companion`.
- **Changed** `STY-9`: states the ktlint line-length prerequisite.
- **Changed** `STY-32`: comparison operators and ordering functions are banned too.
- **Changed** `STY-45`: `RetryTemplate` is the default mechanism; the retry predicate is required.
- **Changed** `STY-47`: example uses `transferTo(Path)` and `ProcessBuilder.directory(File)`.
- **Changed** `TST-4`: only a class without MockK mocks runs concurrently; `parallel.enabled=true` is required.
- **Changed** `TST-7`, `TST-26`: `restoreSharedDoubles()` is removed; springmockk clears mocks after each test, and late async calls are what still leak.
- **Changed** `TST-23`, `TST-8`: a transactional test flushes and clears before re-reading and after bulk DML.
- **Changed** `TST-6`, `TST-21`, `TST-25`: reasons restated.

- **Renumbered** `CTL-30` → `CTL-32` (Response carries only the fields the frontend reads). `CTL-30` is a consuming project's own rule and stays a gap.
- **Changed** `CTL-32`: scoped to Responses consumed only by the web frontend; an unused field is removed directly, without a deprecation phase, and the frontend developers are told.
- **Changed** `CTL-31`: time-relative values (`isExpired`) and policy calculations stay in the Response; the shared `PaginationResponse` keeps its page metadata.
- **Changed** `REP-34`: a time-relative judgement is a method taking the time (`isExpiredAt(now)`), not a getter reading the clock.
- **Added** `CTL-31`, `CTL-32` (as `CTL-30`), `REP-34`.
