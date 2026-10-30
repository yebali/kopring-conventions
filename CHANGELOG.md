# Changelog

Rule identifiers added, changed, removed or renumbered, newest first. A consuming project checks this list when it updates the skill, because its own rule document overrides the skill by identifier.

## 2026-10-30

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
