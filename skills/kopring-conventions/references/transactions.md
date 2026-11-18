# Transaction and Lock Conventions

**Owns:** transaction boundaries, external calls and compensation, and lock selection. **Read when:** changing `@Transactional`, a `*Facade`, `TransactionRunner`, a transaction callback, external work around a database write, a boot-time seed, or a distributed lock — read the relevant section and its exceptions before editing.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| TX-1 | | A `@Service` class carries class-level `@Transactional`; a method that changes nothing overrides it with `readOnly = true`; no other bean carries `@Transactional` | [§2](#2-transaction-boundaries) |
| TX-2 | | A `@Service` injects no bean that waits on a remote system or does long-running I/O, so no external call can run inside its transaction | [§3](#3-external-calls-and-compensation) |
| TX-3 | | A use case with an external call around its DB work is a `*Facade` — no transaction, no Repository, Service calls and outbound calls in order — once the upper gate ([STY-27](code-style.md#10-prefer-the-plain-option)) and an `AFTER_COMMIT` listener are ruled out | [§3](#3-external-calls-and-compensation) |
| TX-4 | | A Facade compensates only a definite remote failure (an unknown outcome is marked pending and reconciled), in `runCatching`, in reverse creation order, through the owning domain's methods, cleaning non-transactional side effects; a state-changing call sends an idempotency key | [§3](#3-external-calls-and-compensation) |
| TX-5 | | A bean that is not a Service opens a boundary of its own with `TransactionRunner.inTx`/`inNewTx`; a Service and a Facade never do; inject a raw `TransactionTemplate` only to reach `TransactionStatus` | [§3](#3-external-calls-and-compensation) |
| TX-6 | | Open a programmatic boundary (`inTx`) only for the listed needs, never around a pure read | [§3](#3-external-calls-and-compensation) |
| TX-7 | | `inNewTx` only for a write that must commit on its own, never as a precaution | [§3](#3-external-calls-and-compensation) |
| TX-8 | | *If the project uses PostgreSQL advisory locks / Redis:* advisory lock for DB-write atomicity; Redis lock for periodic duplicate runs, holder identification or Redis-only state | [§4](#4-lock-selection) |
| TX-9 | | *If the project uses PostgreSQL advisory locks:* an advisory lock always runs inside a transaction — a Service method, or `inTx` in a bean that is not a Service — that holds only the lock and the DB work | [§4](#4-lock-selection) |
| TX-10 | | *If the project uses PostgreSQL advisory locks / Redis:* lock-key building that repeats across call sites lives in one private helper of the domain service | [§4](#4-lock-selection) |
| TX-11 | | *If the project uses PostgreSQL advisory locks / Redis:* a lock key constant is `"<domain>:<purpose>:lock"` in its class's `companion object` | [§4](#4-lock-selection) |
| TX-12 | | *If the project uses PostgreSQL advisory locks:* a boot seed that several instances may run takes an advisory lock and filters existing rows before one `saveAll` | [§4](#4-lock-selection) |
| TX-13 | | *If the project uses PostgreSQL:* documents and diagnoses name the lock mode Hibernate emits (`FOR NO KEY UPDATE`), never `FOR UPDATE` | [§4](#4-lock-selection) |
| TX-14 | ⚠ | A concurrently edited entity carries `@Version`; a counter or balance changes through one conditional atomic UPDATE | [§4](#4-lock-selection) |
| TX-15 | ⚠ | A transactional method that can let a checked exception escape declares `rollbackFor`; `TransactionRunner` rethrows the original exception | [§2](#2-transaction-boundaries) |
| TX-16 | ⚠ | A PUT updating an existing `@Version` entity carries the client-read `version`, including partial updates and UPSERT updates; the Service compares it and raises the domain's 409 | [§4](#4-lock-selection) |
| TX-17 | ⚠ | A `readOnly = true` method writes nothing, directly or through a collaborator that joins it | [§2](#2-transaction-boundaries) |
| TX-18 | | A proxy-driven annotation (`@Transactional`, `@Async`, `@Retryable`, `@Cacheable`) works only where another bean's call reaches it: on a public method, never on a private or self-invoked one | [§2](#2-transaction-boundaries) |

Repository implementations carry no `@Transactional` ([REP-4](repository.md#2-query-construction)); test-class transactions follow [TST-8](testing.md#3-test-structure). Service-layer rules live in [service.md](service.md).

## 2. Transaction boundaries

**TX-1** — A `@Service` class carries class-level `@Transactional`: every public method is one atomic read-write transaction unless it says otherwise, and a method that changes nothing says so with `@Transactional(readOnly = true)`. The default is the safe one — a forgotten override costs a read its optimizations, where the opposite default (class-level `readOnly = true`) drops a write whose override was forgotten (TX-17). A read method carries `readOnly = true` for three reasons: Hibernate sets a read-only session's flush mode to `MANUAL` and keeps no dirty-check snapshots of what it loads, lazy associations can be mapped into the Result inside the boundary, and the read can be routed to a replica if the project has one. A method-level `@Transactional` replaces the class-level one as a whole, and `readOnly = true` and `rollbackFor` (TX-15) are the only method-level forms a Service needs. No other bean carries `@Transactional`: not a `*Facade` (TX-3), a controller, a listener, a `@Component` collaborator or a `Custom*RepositoryImpl` ([REP-4](repository.md#2-query-construction)) — each enters a transaction by calling a Service, or opens one with `TransactionRunner` where TX-5 allows. Logic that touches no database is not a Service method; it lives in a `@Component` ([SVC-30](service.md#10-service-vs-component)). Example: [TX-1 · TX-5](examples/service.md#tx-1--tx-5--transactional-placement-and-the-boundary-api).

**TX-15** — Spring's rollback rule stays at its default: a `@Transactional` method rolls back on a `RuntimeException` or an `Error` and commits on a checked exception. Kotlin marks no checked exceptions, so nothing in a signature shows that an `IOException` can pass through: a Service method that lets one escape declares it, `@Transactional(rollbackFor = [IOException::class])`, or the writes made before the throw commit. Every exception these rules throw is a `RuntimeException` ([SVC-14](service.md#5-exceptions-and-failure-forms)), so the declaration is needed only where Java I/O or a library's checked exception can leave the method. `TransactionTemplate` rolls back on any exception but wraps a checked one in `UndeclaredThrowableException`, so `TransactionRunner` (TX-5) unwraps it and rethrows the original — a caller's `catch (e: IOException)` still matches.

**TX-17** — A `@Transactional(readOnly = true)` method writes nothing: no `save`, no entity state-change method, and no call to a collaborator's write method, which joins the read-only transaction instead of opening its own. The read-only session never flushes (TX-1), so a dirty-checked change or a `save` made there is dropped at commit without an error or a log line; only an explicit flush (`saveAndFlush`) fails, rejected by PostgreSQL as a write in a read-only transaction. A read that must record something — a last-read time, a view count — writes it in `transactionRunner.inNewTx { }` (TX-7) or publishes an event whose `AFTER_COMMIT` listener writes it ([SVC-40](service.md#11-spring-events)).

**TX-18** — `@Transactional`, `@Async`, `@Retryable`, `@Cacheable` and `@CacheEvict` take effect only through the bean's proxy, so each works only on a public method that another bean calls. On a `private` method, or when a method of the same class calls it (self-invocation), the proxy is bypassed: nothing runs on the executor, nothing is retried, and nothing reports it. A Service method called from another method of the same Service therefore runs in the caller's transaction with the caller's attributes — its own `readOnly` or `rollbackFor` does nothing there. Work that needs a boundary of its own is entered from another bean: a step of a Facade (TX-3), or `transactionRunner.inNewTx { }` in a listener (TX-7).

## 3. External calls and compensation

**TX-2** — A `@Service` injects no bean that waits on a remote system or does long-running I/O: no HTTP or SSE client (`*Client` — Feign, `RestClient`), no remote `*Reader`, no mail sender, no process runner (`ProcessBuilder`), no wrapper around large file I/O (GB `Files.copy`, S3 multipart) or SSH. Every Service method runs in a transaction (TX-1), and a transaction that waits on such a call holds its row locks and a pooled connection for the whole wait: an external client trying to UPDATE or UPSERT the same row blocks until its own timeout — a silent deadlock that also exhausts the DB connection pool. With no such bean injected, no external call can end up inside a transaction. A Service injects its repositories, other Services ([SVC-39](service.md#6-cross-domain-access)), `ApplicationEventPublisher`, `Clock` and stateless collaborators (`*Policy`, `*Mapper`, `*Resolver`).

A transaction-phase listener is not a Service, and two calls stay open to it:

- a short external call with an explicitly configured client timeout inside `@TransactionalEventListener(AFTER_COMMIT)` — past commit, so the row locks are released, but the listener runs in the committing thread's `afterCompletion` callback, before `cleanupAfterCompletion`, so the pooled connection (Hibernate's `DELAYED_ACQUISITION_AND_HOLD`) and the persistence context are still held. A slow or unbounded external call from an `AFTER_COMMIT` listener is handed to a Spring-managed executor ([STY-43](code-style.md#14-threads-retries-and-lifecycle)) — an explicit exception to the no-`@Async`/executor default of [STY-27](code-style.md#10-prefer-the-plain-option);
- **an external fire-and-forget call that waits for no ack, even from a listener running eagerly inside the transaction** (a broker publish that returns without awaiting the ack) — the criterion is *blocking*, not transaction phase. A broker client's send can still block: `KafkaTemplate.send` waits up to `max.block.ms` (60 s by default) when metadata is unavailable or the buffer is full, so this exemption requires a bounded `max.block.ms`. This covers external side effects that must survive a rollback and therefore cannot use AFTER_COMMIT; a DB write in that position uses `inNewTx` instead (TX-7). **Do not reach for `AFTER_COMPLETION`/`AFTER_ROLLBACK` to buy this exemption** — they run in the same `afterCompletion` callback as `AFTER_COMMIT`, before `cleanupAfterCompletion`, so they hold the same connection. The only fix in that situation is making the call itself asynchronous.

**TX-3** — When a use case needs an external call and a DB write, take the first that fits:

0. **Upper gate — one remote read whose answer is only input.** The controller calls the reader and passes the answer in the Command, and the Service method stays one transaction ([STY-27](code-style.md#10-prefer-the-plain-option)).
1. **`@TransactionalEventListener(AFTER_COMMIT)`** — for side effects that must happen after the write is durable (notification, message publish, cache eviction). **Only for effects that are NOT part of what this request promised** — if the caller's success depends on the effect (deleting the stored files an order delete promised to remove), a listener hides it from the flow and from the response, so it is a Facade step instead. Event payloads follow [SVC-33](service.md#11-spring-events). A reaction in another domain of the same deployable is chosen by [SVC-39](service.md#6-cross-domain-access) and [SVC-40](service.md#11-spring-events).
2. **A `*Facade`** — everything else: a call sandwiched between DB steps, an effect the request promised, a flow that compensates. A Facade is a `@Component` in `<domain>/service/` ([SVC-30](service.md#10-service-vs-component)) with no `@Transactional`. It injects Services and outbound beans and never a Repository, takes a Command and returns a Result like a Service ([SVC-3](service.md#2-method-signatures)), and lists the flow in execution order: a Service call commits and releases its locks, the external call runs outside any transaction, the next Service call opens a new one.

Every DB step of a Facade is a public method of a Service, entered through its proxy, so each step is atomic (TX-1) and none depends on self-invocation (TX-18). Between steps the Facade holds Results and ids, never an entity — an entity is detached once its Service call returns. Writes of several domains that must commit as one unit are not Facade steps: one Service method calls the other Services, which join its transaction, or publishes an event a synchronous `@EventListener` handles ([SVC-40](service.md#11-spring-events)). A Facade exists only for a flow with an outbound call; a use case that is DB work alone is a Service method the controller calls directly.

**TX-4** — Compensation lives in the Facade and runs only on a definite failure: the remote reported a business failure (a 4xx). A timeout, connection reset or 5xx is an unknown outcome — the remote change may have happened — so the local record is marked pending and reconciled, never deleted. Each compensating call is wrapped in `runCatching`, so a failed compensation is logged, never rethrown, and cannot mask the original exception. Compensations run in **reverse creation order** and reuse the owning domain's existing `delete*`/`unlink*` Service methods ([SVC-17](service.md#6-cross-domain-access)). Non-transactional side effects — files on disk, external-system state — are cleaned up explicitly in the same catch block, since no rollback covers them. A state-changing outbound call sends an idempotency key derived from the local id (`order.id`), so a retry or the reconciliation cannot apply it twice.

**TX-5** — A bean that is neither a Service nor a Facade and needs a boundary of its own — a boot seeder, an `AFTER_COMMIT` listener's write (TX-7), a reconcile loop — opens it by injecting `TransactionRunner` (one shared, component-scanned bean) as `private val transactionRunner: TransactionRunner`, the **last constructor parameter**, and wrapping the DB work in `transactionRunner.inTx { }`. A Service never opens one — its methods are the boundaries (TX-1) — and a Facade never does (TX-3). Do NOT inject the raw `TransactionTemplate`: that reopens what the wrapper closes — `isReadOnly` mutated on the shared singleton. The runner exposes `inTx { }` (`REQUIRED`) and `inNewTx { }` (`REQUIRES_NEW`, TX-7) and no read-only variant, because TX-6 rules out a boundary around a pure read. `src/test` fixtures may keep `@Autowired transactionTemplate.execute { … }` for setup and teardown.

The default shape; a project may already have its own equivalent — use that:

```kotlin
@Component
class TransactionRunner(private val provider: ObjectProvider<TransactionTemplate>) {
    private val requiresNewTemplate by lazy {
        TransactionTemplate(checkNotNull(template().transactionManager) { "TransactionTemplate has no transaction manager" })
            .apply { propagationBehavior = TransactionDefinition.PROPAGATION_REQUIRES_NEW }
    }

    fun <T> inTx(block: () -> T): T = unwrapping { template().execute { block() } }

    fun <T> inNewTx(block: () -> T): T = unwrapping { requiresNewTemplate.execute { block() } }

    // TransactionTemplate 은 checked 예외를 UndeclaredThrowableException 으로 감싸므로 원래 예외로 되돌린다 (TX-15)
    private inline fun <T> unwrapping(call: () -> T): T =
        try {
            call()
        } catch (e: UndeclaredThrowableException) {
            throw e.undeclaredThrowable
        }

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

**TX-6** — This rule governs programmatic boundaries only: `transactionRunner.inTx { }` in a bean that is not a Service (TX-5). A Service read method keeps its `@Transactional(readOnly = true)` (TX-1). Open a boundary with `inTx { }` if, and only if, one of the rows below holds. Otherwise call the Service or the repository directly: with `open-in-view: false` a bare repository call acquires and releases its connection per query, and PostgreSQL's default READ COMMITTED gives each statement a fresh snapshot anyway, so wrapping plain reads buys a consistent snapshot only under REPEATABLE READ — that is, nothing.

| Boundary needed when | Why | Example |
|---|---|---|
| **Dirty-checking write** — you mutate a loaded entity, including mutations *after* `save()` | Outside a transaction the entity is detached and the mutation is **silently lost** | A boot seeder's `inTx`: re-read the entity inside the transaction → the transition method mutates the loaded entity |
| **Atomicity across writes** — 2+ calls to collaborators that each own `@Transactional`, a multi-stage `saveAll`, or an ordered batch delete | Without an enclosing boundary a partial run leaves inconsistent state | One `inTx` over a seed's parent and child `saveAll`; a full wipe in FK child → parent order |
| **Bulk UPDATE/DELETE statement** — a QueryDSL `update`/`delete` or a JPQL `executeUpdate` called from a bean that is not a Service | JPA refuses a bulk statement outside a transaction (`TransactionRequiredException`) | A cleanup listener's `inTx` around its `bulkDeleteBy*` |
| **Lazy association traversed after the block** | Otherwise `LazyInitializationException` | — |

❌ Never open a programmatic boundary around a pure read whose block returns a scalar, a locally built DTO, or an association-free entity — that boundary is a no-op, and on a throwing path it makes a nested `REQUIRES_NEW` (a sequence/counter service) hold two pool connections at once. `inTx` is `REQUIRED`, not `REQUIRES_NEW`: it starts a transaction only when none is active and joins an ambient one otherwise.

**TX-7** — `inNewTx` (`REQUIRES_NEW`) is for a write that must commit on its own. It commits at once and survives the caller's rollback, and it is the only safe boundary where the ambient transaction cannot take the write: a read-only transaction, or the `AFTER_COMMIT` phase, which still holds the committed transaction's connection and resources (TX-2), so a `REQUIRED` boundary (`inTx`, `@Transactional`) opened there joins it and its writes are never committed (Spring's documented rule for after-commit callbacks). Wrap the owning Service's write in `transactionRunner.inNewTx { }` rather than deferring the write to a rollback listener. While an outer transaction is open, it holds a second pool connection. Reach for it only when a transaction-bearing call path (re-entry from `@TransactionalEventListener(AFTER_COMMIT)`) actually exists — never as defensive, preemptive propagation. Example: a reconcile listener whose rebuild can run in the committing thread's `AFTER_COMMIT` phase ([§4](#4-lock-selection) borderline case).

Examples (Service placement and the boundary API, a Facade with compensation): [TX-1 · TX-5](examples/service.md#tx-1--tx-5--transactional-placement-and-the-boundary-api), [TX-3 · TX-4](examples/service.md#tx-3--tx-4--facade-and-compensation).

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

**TX-9** — An advisory lock always runs inside a transaction. Without one, `pg_advisory_xact_lock` is released right after acquisition and blocks nothing, and it **leaves neither an error nor a log** — the one point no name or type enforces, so review watches it. The transaction holds only the lock and the DB work. In a Service that is one method (TX-1): work that must happen after the commit — starting a thread, an external call — belongs to the Facade or listener that called it (TX-3), where it sees the committed rows; inside the transaction it would run **in the uncommitted state**. In a bean that is not a Service (a boot seeder) the boundary is `transactionRunner.inTx { lock + DB work }` and the rest stays outside the block — `acquireLocks` sits inside the transaction that block opens, so the lock is still held to the commit.

**TX-10** — A call site states only *what* is being locked. When the rule that builds the lock keys (taking a path's ancestors as shared, and the like) repeats across call sites, it lives in one private helper of that domain service — keeping domain concepts (path, hierarchy, ownership) off the lock template is what lets another domain use it as is. That helper also owns normalization such as `distinct()`, so a call site cannot omit it (the template absorbs duplicates internally with `toSet()`, so an omission never shows up in the code).

**TX-11** — A lock key constant is owned by its domain: it lives in each class's `companion object` in the form `"<domain>:<purpose>:lock"` (`"category:seed:lock"`, `"order:stale-sweep:lock"`), never in a shared lock-constant file.

**TX-12** — A boot-time seed that several instances may run at once takes an advisory lock, then filters out the rows (scopes) that already exist before one `saveAll`, so instances starting together against an empty DB never fail startup on a unique violation.

**TX-13** — Hibernate's `PostgreSQLDialect` emits `FOR NO KEY UPDATE` for `PESSIMISTIC_WRITE`. Documents, comments and performance diagnoses name that mode, never `FOR UPDATE`, which is a different lock with different conflicts.

Examples: [TX-8 · TX-9](examples/service.md#tx-8--tx-9--lock-selection-advisory-vs-redis), [TX-10](examples/service.md#tx-10--lock-key-helper).

**TX-14** — A read-modify-write through dirty checking loses an update when two requests edit the same row: both read the same state, and the second commit overwrites the first. An entity two requests can edit concurrently (an order a member and an operator both change, a shared settings row) carries `@Version var version: Long = 0` with a `protected set` (column `version bigint not null default 0`); the second commit then fails with `ObjectOptimisticLockingFailureException`, which the global exception handler maps to a 409 so the client re-reads and retries; a stale write that never overlaps another transaction is TX-16. A counter or balance (stock, a quota, a sequence) never goes through read-modify-write: it changes through one conditional atomic UPDATE (`set stock = stock - :n where id = :id and stock >= :n`, a QueryDSL `update` in the `Custom*RepositoryImpl`) whose affected-row count decides success. A pessimistic lock (`PESSIMISTIC_WRITE`, TX-13) is for a short critical section that reads and writes several rows as one step, and is never held across an external call (TX-2).

**TX-16** — `@Version` compares the row with the version the same transaction loaded, so it catches only two transactions that overlap. A client that read the resource minutes ago can pass that check and overwrite a newer value when its PUT arrives: full replacement can overwrite the representation, and a partial update can overwrite any supplied field ([CTL-19](controller.md#8-restful-api-design)). The Response of a `@Version` entity therefore carries `version`; a PUT updating that existing row sends it back, including a partial update or the update branch of an UPSERT, and the Service compares before it mutates:

```kotlin
val order = getEntity(command.orderId)
if (order.version != command.version) throw OrderModifiedException(order.id)   // the domain's 409
order.update(memo = command.memo, shippingAddress = command.shippingAddress)
```

The comparison is explicit code: Hibernate checks a managed entity against the version it loaded and ignores a value assigned to the field, so `order.version = command.version` protects nothing (and REP-17's `protected set` forbids it). `@Version` still covers the overlap between this comparison and the commit (TX-14). The create branch of an UPSERT has no previously read version to compare; an input carrying an existing-row version must not recreate a missing target. An action endpoint that changes one field from the current state (`PUT …/hold`, `POST …/cancellations`) sends no version: the entity's transition guard decides.
