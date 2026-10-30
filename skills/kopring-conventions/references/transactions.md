# Transaction and Lock Conventions

**Owns:** transaction boundaries, external calls and compensation, and lock selection. **Read when:** changing `@Transactional`, `TransactionRunner`, a transaction callback, external work around a database write, a boot-time seed, or a distributed lock — read the relevant section and its exceptions before editing.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| TX-1 | | `@Transactional` is method-level: `readOnly = true` on every Service read, plain for writes, none for stateless or call-interleaving methods | [§2](#2-transaction-boundaries) |
| TX-2 | | No variable or long-running external call inside a transaction (listed exceptions) | [§3](#3-external-calls-and-compensation) |
| TX-3 | | Pass the upper gate ([STY-27](code-style.md#10-prefer-the-plain-option)) first, then take the first of options 1–3 that fits | [§3](#3-external-calls-and-compensation) |
| TX-4 | | Compensate only a definite remote failure (an unknown outcome is marked pending and reconciled), in `runCatching`, in reverse creation order, through the owning domain's methods, cleaning non-transactional side effects; a state-changing call sends an idempotency key | [§3](#3-external-calls-and-compensation) |
| TX-5 | | Open boundaries with `TransactionRunner.inTx`/`inNewTx`; inject a raw `TransactionTemplate` only to reach `TransactionStatus` | [§3](#3-external-calls-and-compensation) |
| TX-6 | | Open a programmatic boundary (`inTx`) only for the listed needs, never around a pure read; a Service read method's `readOnly` is TX-1 | [§3](#3-external-calls-and-compensation) |
| TX-7 | | `inNewTx` only for a write that must commit on its own, never as a precaution | [§3](#3-external-calls-and-compensation) |
| TX-8 | | *If the project uses PostgreSQL advisory locks / Redis:* advisory lock for DB-write atomicity; Redis lock for periodic duplicate runs, holder identification or Redis-only state | [§4](#4-lock-selection) |
| TX-9 | | *If the project uses PostgreSQL advisory locks:* an advisory lock always runs inside a transaction narrowed with `inTx` to the lock and the DB work | [§4](#4-lock-selection) |
| TX-10 | | *If the project uses PostgreSQL advisory locks / Redis:* lock-key building that repeats across call sites lives in one private helper of the domain service | [§4](#4-lock-selection) |
| TX-11 | | *If the project uses PostgreSQL advisory locks / Redis:* a lock key constant is `"<domain>:<purpose>:lock"` in its class's `companion object` | [§4](#4-lock-selection) |
| TX-12 | | *If the project uses PostgreSQL advisory locks:* a boot seed that several instances may run takes an advisory lock and filters existing rows before one `saveAll` | [§4](#4-lock-selection) |
| TX-13 | | *If the project uses PostgreSQL:* documents and diagnoses name the lock mode Hibernate emits (`FOR NO KEY UPDATE`), never `FOR UPDATE` | [§4](#4-lock-selection) |

Repository implementations carry no `@Transactional` ([REP-4](repository.md#2-query-construction)); test-class transactions follow [TST-8](testing.md#3-test-structure). Service-layer rules live in [service.md](service.md).

## 2. Transaction boundaries

**TX-1** — `@Transactional` is method-level only: a class-level annotation silently propagates the wrong attribute to every newly added method. `@Transactional(readOnly = true)` on every Service read method, plain `@Transactional` for writes, and **no annotation** for stateless methods (pure JWT parsing) and for a method that interleaves DB work with an external call. In the latter, each DB access runs in a collaborator's own transaction or an `inTx { }` boundary, and the external call stays outside all of them ([§3](#3-external-calls-and-compensation)). A read method carries `readOnly = true` for three reasons: Hibernate sets a read-only session's flush mode to `MANUAL` and keeps no dirty-check snapshots of what it loads, lazy associations can be mapped into the Result inside the boundary, and the read can be routed to a replica if the project has one. TX-6 governs only programmatic boundaries, not this annotation. Example: [TX-1 · TX-5](examples/service.md#tx-1--tx-5--transactional-placement-and-the-boundary-api).

## 3. External calls and compensation

**TX-2** — No variable or long-running external call inside `@Transactional`: external HTTP/SSE (Feign, `RestClient`, minutes long), external processes (`ProcessBuilder`), large file IO (GB `Files.copy`, S3 multipart), SSH and remote commands. The transaction holds a row lock, so an external client trying to UPDATE or UPSERT the same row waits on that lock until its own timeout — a silent deadlock that also exhausts the DB connection pool.

Allowed:

- a short status check (≤ ~100ms) over HTTP — token refresh, health probe;
- a short external call with an explicitly configured client timeout inside `@TransactionalEventListener(AFTER_COMMIT)` — past commit, so the row locks are released, but the listener runs in the committing thread's `afterCompletion` callback, before `cleanupAfterCompletion`, so the pooled connection (Hibernate's `DELAYED_ACQUISITION_AND_HOLD`) and the persistence context are still held. A slow or unbounded external call from an `AFTER_COMMIT` listener is handed to a Spring-managed executor ([STY-43](code-style.md#14-threads-retries-and-lifecycle)) — an explicit exception to the no-`@Async`/executor default of [STY-27](code-style.md#10-prefer-the-plain-option);
- **an external fire-and-forget call that waits for no ack, even from a listener running eagerly inside the transaction** (a broker publish that returns without awaiting the ack) — the criterion is *blocking*, not transaction phase. A broker client's send can still block: `KafkaTemplate.send` waits up to `max.block.ms` (60 s by default) when metadata is unavailable or the buffer is full, so this exemption requires a bounded `max.block.ms`. This covers external side effects that must survive a rollback and therefore cannot use AFTER_COMMIT; a DB write in that position uses `inNewTx` instead (TX-7). **Do not reach for `AFTER_COMPLETION`/`AFTER_ROLLBACK` to buy this exemption** — they run in the same `afterCompletion` callback as `AFTER_COMMIT`, before `cleanupAfterCompletion`, so they hold the same connection. The only fix in that situation is making the call itself asynchronous.

**TX-3** — When a method needs an external call and a DB write, try these in order and stop at the first that fits:

0. **Upper gate — must this service make the external call at all?** The options below all assume the call lives in this method; break that assumption first. If the call's arguments come from the Command or a constant, hoist it to the caller (controller) or a listener, and this method becomes one plain `@Transactional`. The gate is [STY-27](code-style.md#10-prefer-the-plain-option). If the call is sandwiched between a read and a write of the same row, the gate fails and you descend to 1–3. Never delete an existing boundary to satisfy it.

1. **Delegate to a domain service that already owns a transaction** — the orchestration method carries NO `@Transactional`; each DB step runs inside the collaborator's own `@Transactional` and commits immediately (releasing the lock); the external call sits between them, outside any transaction. Prefer this: `@Transactional` is proxy-based, so self-invocation never opens a boundary; splitting *beans* (not methods) is what works, and the domain services are already split finely enough that it rarely costs a new file.
   **Delegation means calling a collaborator that already exists for its own reasons. If this option requires *creating* a bean, that bean is a wrapper, not a collaborator — go to option 3.** A one-method `*DeletionService` whose only job is `domainService.x()` → `externalCall()` is such a wrapper. Test: does the callee own domain state of its own? `OrderItemService.deleteItem` passes (it owns `OrderItem` and has other methods); a new bean wrapping only `OrderService.deleteOrder` does not.
2. **`@TransactionalEventListener(AFTER_COMMIT)`** — for side effects that must happen after the write is durable (notification, message publish, cache eviction). **Only for effects that are NOT part of what this request promised** — if the caller's success depends on the effect (deleting the stored files an order delete promised to remove), a listener hides it from the flow and from the response, so use option 3 instead. Event payloads follow [SVC-33](service.md#11-spring-events). A reaction in another domain of the same deployable is chosen by [SVC-39](service.md#6-cross-domain-access) and [SVC-40](service.md#11-spring-events).
3. **A programmatic boundary (`transactionRunner.inTx { }`, TX-5)** — when no collaborator owns the write (the persist step is private to this service), **or when several collaborator writes of the same domain must commit as one unit** (each is `@Transactional` on its own, so without an enclosing boundary a partial run leaves inconsistent state — e.g. a user row and its profile row written by two user-domain collaborators). A write in another domain that must commit with this one is not a collaborator call: publish an event that domain handles in a synchronous `@EventListener`, which joins the enclosing boundary ([SVC-40](service.md#11-spring-events)).
   **The block's return value carries what the post-commit step needs.** Read it inside the boundary (it needs the loaded entities), hand it out, and use it after — `inTx { …; existingFiles.map { it.path } }` then `deleteStoredFiles(paths = filePaths, …)`. The whole flow stays in one method and reading order matches execution order: inside the block is what commits, outside is the external call.

**TX-4** — Compensation (options 1 and 3) runs only on a definite failure: the remote reported a business failure (a 4xx). A timeout, connection reset or 5xx is an unknown outcome — the remote change may have happened — so the local record is marked pending and reconciled, never deleted. Each compensating call is wrapped in `runCatching`, so a failed compensation is logged, never rethrown, and cannot mask the original exception. Compensations run in **reverse creation order** and reuse the owning domain's existing `delete*`/`unlink*` Service methods ([SVC-17](service.md#6-cross-domain-access)). Non-transactional side effects — files on disk, external-system state — are cleaned up explicitly in the same catch block, since no rollback covers them. A state-changing outbound call sends an idempotency key derived from the local id (`order.id`), so a retry or the reconciliation cannot apply it twice.

**TX-5** — Production code opens a boundary by injecting `TransactionRunner` (one shared, component-scanned bean) as `private val transactionRunner: TransactionRunner`, the **last constructor parameter**, and wrapping each DB step in `transactionRunner.inTx { }`. Do NOT inject the raw `TransactionTemplate`: that reopens what the wrapper closes — `isReadOnly` mutated on the shared singleton. The runner exposes `inTx { }` (`REQUIRED`) and `inNewTx { }` (`REQUIRES_NEW`, TX-7) and no read-only variant, because TX-6 rules out a boundary around a pure read. `src/test` fixtures may keep `@Autowired transactionTemplate.execute { … }` for setup and teardown.

The default shape; a project may already have its own equivalent — use that:

```kotlin
@Component
class TransactionRunner(private val provider: ObjectProvider<TransactionTemplate>) {
    private val requiresNewTemplate by lazy {
        TransactionTemplate(checkNotNull(template().transactionManager) { "TransactionTemplate has no transaction manager" })
            .apply { propagationBehavior = TransactionDefinition.PROPAGATION_REQUIRES_NEW }
    }

    fun <T> inTx(block: () -> T): T = template().execute { block() }

    fun <T> inNewTx(block: () -> T): T = requiresNewTemplate.execute { block() }

    private fun template(): TransactionTemplate =
        checkNotNull(provider.getIfAvailable()) { "No TransactionTemplate available" }
}
```

| Boundary | API |
|---|---|
| Any boundary — the block's result comes back with its exact type (non-null, `null`, or `Unit`) | `transactionRunner.inTx { … }` |
| A write that must commit on its own (TX-7) — `REQUIRES_NEW`, a second connection while an outer transaction is open | `transactionRunner.inNewTx { … }` |
| Needs `TransactionStatus` (`setRollbackOnly`) | Inject `TransactionTemplate` in that one class and call `execute { status -> … }` — rare, make it explicit |

`TransactionRunner` is a bean, so each boundary binds to the Spring context that owns the repositories.

**TX-6** — This rule governs programmatic boundaries only: `transactionRunner.inTx { }` inside a method that carries no `@Transactional` (TX-1's call-interleaving method). A Service read method keeps its `@Transactional(readOnly = true)` (TX-1). Open a boundary with `inTx { }` if, and only if, one of the rows below holds. Otherwise call the repository directly: with `open-in-view: false` a bare repository call acquires and releases its connection per query, and PostgreSQL's default READ COMMITTED gives each statement a fresh snapshot anyway, so wrapping plain reads buys a consistent snapshot only under REPEATABLE READ — that is, nothing.

| Boundary needed when | Why | Example |
|---|---|---|
| **Dirty-checking write** — you mutate a loaded entity, including mutations *after* `save()` | Outside a transaction the entity is detached and the mutation is **silently lost** | A private `commitMove` runs in `inTx`: re-read the entity inside the new transaction → `move()` mutates the loaded entity |
| **Atomicity across writes** — 2+ calls to collaborators that each own `@Transactional`, a multi-stage `saveAll`, or an ordered batch delete | Without an enclosing boundary a partial run leaves inconsistent state | One `inTx` over every transferred order's writes; a full wipe in FK child → parent order |
| **Bulk UPDATE/DELETE statement** — a QueryDSL `update`/`delete` or a JPQL `executeUpdate` called from a method with no `@Transactional` | JPA refuses a bulk statement outside a transaction (`TransactionRequiredException`) | A digest sender's `inTx` around the claim: it selects the unsent rows with `SKIP LOCKED`, marks them sent, and mails only what it claimed, because the method also holds a remote read and the mail sends and has no boundary |
| **Lazy association traversed after the block** | Otherwise `LazyInitializationException` | — |

❌ Never open a programmatic boundary around a pure read whose block returns a scalar, a locally built DTO, or an association-free entity — that boundary is a no-op, and on a throwing path it makes a nested `REQUIRES_NEW` (a sequence/counter service) hold two pool connections at once. `inTx` is `REQUIRED`, not `REQUIRES_NEW`: it starts a transaction only when none is active and joins an ambient one otherwise.

**TX-7** — `inNewTx` (`REQUIRES_NEW`) is for a write that must commit on its own. It commits at once and survives the caller's rollback, and it is the only safe boundary where the ambient transaction cannot take the write: a read-only transaction, or the `AFTER_COMMIT` phase, where the committed transaction's resources are still bound to the thread, so a `REQUIRED` boundary (`inTx`, `@Transactional`) opened there joins it and its writes are never committed (Spring's documented rule for after-commit callbacks). Wrap the owning service's write in `transactionRunner.inNewTx { }` (or give that service a `REQUIRES_NEW` method) rather than deferring the write to a rollback listener. While an outer transaction is open, it holds a second pool connection. Reach for it only when a transaction-bearing call path (re-entry from `@TransactionalEventListener(AFTER_COMMIT)`) actually exists — never as defensive, preemptive propagation. Example: a reconcile listener whose rebuild can run in the committing thread's `AFTER_COMMIT` phase ([§4](#4-lock-selection) borderline case).

Examples (forbidden boundary hand-rolls, split + compensate skeleton): [TX-1 · TX-5](examples/service.md#tx-1--tx-5--transactional-placement-and-the-boundary-api), [TX-2 · TX-4](examples/service.md#tx-2--tx-4--split-and-compensate).

## 4. Lock selection

*If the project uses PostgreSQL advisory locks / Redis.*

**TX-8** — With **two** distributed locks available, one axis separates them: **does the release outlast the commit?** (`AdvisoryLockTemplate`/`DistributedLockTemplate` below, or the project's equivalents.)

| | `AdvisoryLockTemplate` | `DistributedLockTemplate` |
|---|---|---|
| Lives in | A shared persistence module | A shared lock module (a bean only in modules with Spring Data Redis on the classpath) |
| Backed by | PostgreSQL `pg_advisory_xact_lock` / `_shared` | Redis `SET NX EX` + conditional Lua release |
| Release point | **Automatic at transaction end (commit or rollback)** | The `finally` of `runIfAcquired` |
| When not acquired | Waits until acquired | Returns `false` → the call site skips (`runExclusive`: its `onBusy` throws instead) |
| Holder identification | Impossible (the transaction is the holder) | **Possible** — the token is the holder id |
| Key | String → first 8 bytes of SHA-256 → `Long` | The string as is |
| **When to use** | When **atomicity of a DB write** must be held | To prevent **duplicate runs of periodic work**, for a **user-level lock that must identify its holder** (an edit lock and the like), or to **serialize a read-check-write on state that lives only in Redis** with `runExclusive` — the loser is rejected, never queued |

**A Redis lock cannot guard a DB write.** Its release (`finally`) comes before the commit, so in that gap another instance takes the lock and does the same work without seeing the first instance's uncommitted result — duplicate seeding when several instances start against an empty DB takes exactly this path. `runExclusive` sites that guard Redis-only state (refresh-token rows, OTP rows, throttle records) have no commit for the release to outrun. An advisory lock is not released until the transaction ends, so that window is **structurally absent**. Conversely, **never use advisory for periodic work** — a scheduler's job (a broker publish, a sweep trigger) is unrelated to a DB commit, and what it needs when it fails to acquire is not "wait" but "skip and take the next cycle".

**Borderline case — the idempotent re-run loop.** A Redis lock wrapping a DB write is still correct when the purpose is not atomicity but **preventing duplicate runs**, the work is idempotent, and the lock's lifetime must outlast the transaction. Example: a reconcile listener that, on failure to acquire, only marks the aggregate dirty, while the holding instance runs once more on its way out and converges. Its `do/while` opens and closes `inNewTx` several times, so it cannot be held in a single transaction and `pg_advisory_xact_lock` would release at the first commit. The boundary is `inNewTx`, not `inTx`, because the executor's `CallerRunsPolicy` can run the task in the committing thread's `AFTER_COMMIT` phase (TX-7). Each `inNewTx` also takes the aggregate's exclusive advisory lock, which excludes a concurrent edit inside the transaction. The deciding test is **"does the result change if another instance enters the pre-commit release window?"** — if it changes, advisory; if not, Redis is enough.

**TX-9** — An advisory lock always runs inside a transaction. Without one, `pg_advisory_xact_lock` is released right after acquisition and blocks nothing, and it **leaves neither an error nor a log** — the one point no name or type enforces, so review watches it. Do not put `@Transactional` on the whole method; wrap only the lock and the DB work. When the same method also does work that must happen after the commit (starting a thread, an external call, publishing an event), a method-level `@Transactional` runs that work **in the uncommitted state**, where it cannot see the rows the transaction wrote (TX-2). Narrow the boundary with `transactionRunner.inTx { lock + DB work }` and leave the rest outside the block — `acquireLocks` sits inside the transaction that block opens, so the lock is still held to the commit.

**TX-10** — A call site states only *what* is being locked. When the rule that builds the lock keys (taking a path's ancestors as shared, and the like) repeats across call sites, it lives in one private helper of that domain service — keeping domain concepts (path, hierarchy, ownership) off the lock template is what lets another domain use it as is. That helper also owns normalization such as `distinct()`, so a call site cannot omit it (the template absorbs duplicates internally with `toSet()`, so an omission never shows up in the code).

**TX-11** — A lock key constant is owned by its domain: it lives in each class's `companion object` in the form `"<domain>:<purpose>:lock"` (`"category:seed:lock"`, `"order:stale-sweep:lock"`), never in a shared lock-constant file.

**TX-12** — A boot-time seed that several instances may run at once takes an advisory lock, then filters out the rows (scopes) that already exist before one `saveAll`, so instances starting together against an empty DB never fail startup on a unique violation.

**TX-13** — Hibernate's `PostgreSQLDialect` emits `FOR NO KEY UPDATE` for `PESSIMISTIC_WRITE`. Documents, comments and performance diagnoses name that mode, never `FOR UPDATE`, which is a different lock with different conflicts.

Examples: [TX-8 · TX-9](examples/service.md#tx-8--tx-9--lock-selection-advisory-vs-redis), [TX-10](examples/service.md#tx-10--lock-key-helper).
