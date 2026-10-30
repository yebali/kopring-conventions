# Rationale

**Owns:** Why the rules exist and what was rejected. **Read when:** a rule looks wrong for the case at hand, or someone asks why. The rule text lives in the layer files; headings here carry the ID they explain.

## 1. Kotlin style

### STY-25 Latest API and standard library

**STY-25 is a tie-breaker.** STY-19 (inline single-use intermediates), STY-9 (one-line trailing lambda) and STY-10 (blank line before the final `return`) all shorten code. Applied mechanically they shorten without limit, and a reviewer citing IDs has nothing to cite back when the result stops being readable. Where any of them collides with clarity, clarity wins. The deprecation half is the same idea: an idiom the adopted version has moved past is a readability cost paid on every future read.

**Standard library first (STY-26)** — every Kotlin reader already knows `associateBy` or `ifBlank`. A project helper that does the same has to be found, read and kept in step with the function it wraps, and two names for one operation drift apart.

### STY-7 No not-null assertion

When an NPE fires, the stack trace alone cannot tell which call failed, which fixture was missing, or whether it is a production regression or a test-setup bug. `requireNotNull(x) { "<context>" }` names it. So `!!` is never used — not in production, tests or shared helpers.

### STY-8 No unchecked cast suppression

`@Suppress` leaves only a `ClassCastException` on failure — you cannot tell which value mismatched which type — and gives up the compiler's type-safety guarantee.

### STY-9 Single-expression trailing lambda on one line

Spreading a short message lambda across three lines burns vertical space and hurts scanning. Other single-expression lambdas follow the same reasoning up to 120 characters; past that a one-line form buries the body in the call, so the three-line form stays.

### STY-10 Blank line before the final return

It visually separates the point where the function ends, which makes a function easier to scan.

### STY-11 Named arguments for multi-argument calls

Prevents argument-order mistakes (especially adjacent same-type parameters) and makes each argument's meaning visible at the call site. `maxOf`/`minOf`/`min`/`max` and vararg calls are exempt: their arguments are interchangeable, so `maxOf(a = x, b = y)` only adds noise.

### STY-19 Inline single-use intermediates

**Why not chain everything** — folding a remote call into a chain via `.let { client.… }` reads like a pure collection pipeline and hides the round trip. A remote call is its own statement; only guards fold into chain steps. That is why holding a remote call's result is a keep condition.

**Why a meaningful name does not keep a variable** — the name repeats what the expression already says, and a comment written to replace it would be the code translation STY-17 deletes.

**Canonical keep case** — a "before" snapshot referenced once but captured before the mutation that follows (`val before = OrderSnapshot.of(order)` ahead of `order.apply(input)`): without the variable the value no longer exists.

### STY-20 No plumbing parameters

A parameter that only carries a value from the caller to a deeper call encodes "this value comes from there" twice — at the call site and in the signature. A shorter signature also lightens STY-11.

### STY-17 Comment policy

**Altitude, not a WHAT/WHY split.** A reader deciding whether to open a file needs the type's role in one line; a reader inside a function only needs help at the lines that are genuinely hard on a first read. Commenting every line buries the lines that need it.

**Why KDoc is minimal but allowed (STY-16)** — background paragraphs sprawl and rot unreviewed. One line of WHAT, written only when a trigger holds, gives the summary without that risk.

**WHY / history / invariants stay out of source** — they are never reviewed at commit time and drift from the code; a stale rationale is worse than none. They belong in the commit body, docs, or test names.

**Column alignment is forbidden** because `ktlintFormat` reverts it anyway.

### STY-18 Deliberate-simplification comment

A deliberate simplification has a ceiling — a global lock, a full scan, a naive heuristic — and the reader at that line is the one who needs to know it before extending the code. The limit is current state, so it passes STY-17; the fixed `// ponytail:` marker keeps such comments distinguishable from rationale comments and greppable as a debt ledger.

### STY-21 Method shape

**A reader learns the feature from the public method.** When it lists the steps at one level, the reader can stop there or open exactly one step. When it mixes step calls with another step's low-level code, every reader has to read all of it.

**Why simple features are not split** — "small methods" alone turns a 10-line flow into five one-line helpers; each adds a hop and hides no work.

**Why depth stops at 2 (STY-22)** — each private hop is one more frame to hold in mind. Past two hops the chain is usually a responsibility of its own, and pass-through parameters (STY-20) start travelling with it. Moving that chain to a collaborator is a cohesion fix, not the premature abstraction STY-28 guards against.

**Why the limits sit where they do** — measured on the codebase these rules came from; each limit sits at or just above the 95th percentile, so it flags outliers, not ordinary code.

| Metric | Median | p95 | Limit |
|---|---|---|---|
| Public method body | 5 lines | 21 lines | about 20 lines → step methods (STY-21) |
| Method name | 12 chars | 27 chars | about 30 chars (STY-24) |
| Private-call depth below a public method | — | 2 | 2 (STY-22) |
| Nesting | — | 3 | 3 (STY-23) |

**Why a long name is a smell** — most long names list the filter conditions of a query (`…By…And…With…`). The conditions belong in a parameter or a `*Query`, where the call site reads them as named arguments.

### STY-29 Time zones and timestamps

With `timestamptz` columns, `ZonedDateTime.now()` stores the same instant whatever the JVM zone is — the type is not the risk. The zone matters where a wall-clock value is derived: containers often run in UTC while developer machines run in a local zone, so "today", a numbering year, or a cron firing at 04:00 differ between the two. The application time zone fixes every date boundary and time-of-day schedule, and `ZoneId.systemDefault()` is forbidden because it silently follows the host. `equals` compares zones as well as instants, and `compareTo`, `<` and ordering functions break a tie between equal instants by local date-time and zone; `isBefore`/`isAfter`/`isEqual` and `toInstant()` compare the instant alone. `Instant` stays allowed where an API demands it (Spring `Trigger`) and for in-memory arithmetic.

### STY-33 Durations as Duration

A number whose unit lives only in its name (`_SECONDS`, `_MS`) gets converted by hand (`Thread.sleep(X_SECONDS * 1000L)`) and multiplied wrong. A unit carried by the type cannot be, and the call site reads `Duration.ofSeconds(30)`.

### STY-35 Application log format and content

One shape — `{Subject} {action}: key=value` — lets a single grep find every line about an id. Ids, emails and client addresses are what an operator searches by, so they stay; passwords, tokens and keys never do, and neither does a whole command or properties object, because its `toString` prints every field — including a secret added later (STY-38). A Service repeating its entity's change log doubles every mutation line without adding a fact (STY-37).

**Why volume sets the level** — a line repeated per chunk, frame or tick hides the state changes an operator is looking for. Removing whole operations from production logs is the wrong cut: one INFO line per operation stays, carrying the result (ids or counts created, changed, deleted, skipped), and only the repetition inside an operation goes to DEBUG. A line that only says an operation started cannot tell whether it finished.

### STY-39 Failure handling

A failure that is absorbed must still be visible, and only failures whose consequence is bounded (cleanup, enrichment, metrics) may be absorbed at all. `Throwable` includes `OutOfMemoryError` and interrupts, so catching it is only safe when the block rethrows after cleanup. `runCatching` catches `Throwable` too, so it fits only a failure absorbed on purpose; a rethrowing or converting `runCatching` turns an `OutOfMemoryError` or an unrelated bug into the domain exception it throws (STY-40). `runCatching` inside a `suspend` function also catches `CancellationException`, which breaks structured cancellation, and so does any catch of `IllegalStateException` or wider, because `CancellationException` extends it (STY-41). A remote lookup that degrades to empty looks like "no data" to its caller, so it is allowed only where empty is harmless — display enrichment — and the KDoc says so.

### STY-43 Threads and lifecycle

Executors from `Executors.new*` inside a bean are invisible to Spring's shutdown, so in-flight work is cut off on redeploy; an unbounded thread-per-task helper turns a burst into thousands of threads. Hand-written retry loops each get their own backoff behavior and their own idea of what is safe to repeat; one shared mechanism with a required retry predicate (STY-45) keeps both uniform. Starting long-running work on `ApplicationReadyEvent` instead of `@PostConstruct` guarantees every bean it calls is ready, and one stop hook keeps shutdown in one place.

### STY-47 Files and streams

Mixing `java.io.File` and NIO `Path` means converting back and forth and ignoring the `Boolean` results of `File.delete()`/`mkdirs()`; NIO throws instead. A Result carrying an open `InputStream` leaks the descriptor whenever an exception lands between opening and the controller wrapping it, because nobody owns the close; returning a `Path` or a writer keeps opening and closing in one place.

## 2. Naming

### STY-50 No filler suffixes

A suffix is allowed only when a name collision is essential — and even then, check first whether package separation or a Kotlin rename import (`as`) avoids it.

### STY-52 Transport DTO suffix

**The suffix answers one question — does this cross a message broker?** With `*Event` shared between broker messages and in-process Spring events, a name cannot say which side of the wire a class is on. `*Message` for everything on the broker and `*Event` for in-JVM only makes the name alone answer it.

**One tense for both makes half of them a lie.** Many broker messages are commands (`CancelOrder`, `ShipOrder`) or requests, not facts. `*Message` is just a carrier and needs no tense, so it covers commands, requests and facts. The past-participle rule stays for `*Event`, where every class is a fact that already happened (STY-53).

### STY-55 ErrorCode numbering

**Why a retired number stays empty** — reusing it would make the same code mean different incidents across deploys in logs and metrics.

## 3. Layering and structure

### SVC-7 Entity types do not cross layers

Using an entity as a response type makes adding a column a silent breaking change to the response schema, and the `jakarta.persistence` dependency leaks to the REST surface. For the same reason an entity's inner enum is mapped to a service-layer enum before use.

### SVC-6 Inner DTOs with duplication

- Each Command/Result/Request/Response is independent — a change on one side never ripples to the other.
- Opening one file reveals the whole structure of that class.
- No cascading changes from a shared file.

Even when shapes are identical, a clear responsibility boundary outweighs the cost of duplicate declarations.

### SVC-4 List result wrapper

A consistent return shape, easy to extend with metadata, and a clear distinction between single- and multi-item reads.

### STY-12 File and package placement

**The only judgment axis is "does it replicate the layer tree."** A directory need not carry a layer name — as long as it does not replicate the layer tree, it is fine. When two placement schemes coexist in one domain, every new file becomes a guessing game. **The cost of flattening**: layer directories grow large, so inside them the domain name prefix is the only clue to which feature a file belongs to — the prefix is mandatory, not stylistic.

### SVC-38 · SVC-39 Cross-domain communication

**Domains stay separable only when each knows as little as possible about the others.** A Service that injects another domain's Service to push a write or to decorate its Result binds the two domains together: the publisher's code changes whenever a new domain needs to react, and two domains that call each other close a bean cycle. An event reverses the dependency — the reacting domain knows the event, the publisher knows nobody — and composing in the inbound adapter keeps every Service reading its own domain only. Injection stays for the one case an event cannot cover: the Service needs the answer to go on.

**The deployable boundary follows the same split with different transport.** Inside one process an event is a method call with no network in between, so it can even share the publisher's transaction. Between deployables nothing is shared, so the question is whether the caller waits. A caller that needs the answer, or whose own result depends on the other side having finished, calls over HTTP: it gets the outcome or the failure on the spot and can roll back. A caller that only tells the other side to act, and whose response and commit do not wait for it, sends a broker message: the same call over HTTP fails when the other side is down and leaves the two sides inconsistent — or, when the failure is swallowed, silently loses the work — while a message waits until the consumer is back and is redelivered. Splitting by "reads over HTTP, writes over the broker" would instead push a message onto a write the end user is waiting on, with no way to hand its result back.

**Asking and telling follow the caller's outcome, not the return type.** A precondition made before the caller's own writes is asking even when it returns `Unit`; turning it into an event would run the gate after the writes it was meant to guard. A call made after the caller's own state change, with its result discarded, is telling.

## 4. Controller

### CTL-15 Limits are enforced where the bytes pass

A count limit is a property of the request body, so the Command validates it. A size limit on uploaded bytes belongs to the service the bytes actually stream through — the only place that can reject an oversized file before writing it. Moving it elsewhere means either accepting the write and deleting afterwards, or routing bytes through a service with no other reason to see them.

### CTL-18 Response status only CREATED and NO_CONTENT

Unifying everything to 200 OK loses the difference between "created" and "done" for the generated OpenAPI spec and every client. Only the two codes that carry meaning for every client are allowed — 201 for a creating `POST`, 204 for a body-less `PUT`/`DELETE`; everything else stays 200, so there is no per-endpoint status decision beyond those two shapes.

### CTL-3 No required false

A parameter-level default object doubly encodes the same "empty" state as a DTO field default. To allow an empty request, the client sends `{}` and every Request field carries a default.

### CTL-19 PUT replaces the whole resource

With full replacement a `null` in the body has one meaning, "clear", so the server needs no third state to tell "unchanged" from "cleared", and the request alone states the result.

### CTL-28 Composition in the inbound adapter

A response that shows several domains' data is a presentation need, not a business rule, so no domain Service should own it. When the adapter composes, each Service keeps returning its own domain's Result, the Results stay reusable by other callers, and no Service grows an injection whose only purpose is one screen. The adapter only passes ids along and never branches on what comes back; once a decision depends on a Result, it is logic and moves into a Service.

### CTL-22 Service ownership of endpoints

When an endpoint in one service takes or returns another service's data, the client cannot tell which service owns the API, and the owning service's rules have to be mirrored in the foreign DTOs. Keeping each contract inside one service means the owner alone decides. An internal call that carries another service's data is the same leak, only hidden from the API docs.

### CTL-21 One read endpoint per resource

One read path per type or lookup key multiplies Request/Response/Command copies, and the copies drift (one includes deleted rows, another does not). Every client must know which path matches which case, and a new case means a new endpoint. Branching on a filter or a response field costs a client nothing when a type is added. Commands are left out because their rules can genuinely differ per type. `POST …/search` survives because a body is the only place nested filters fit, and `POST` on the collection already means create.

### CTL-29 Shared-module wire DTO mapping

A DTO from a shared module cannot get a `toCommand()` (the shared module cannot see service Commands), so the mapping lives in a service-layer `Command.from(dto)` factory.

### SVC-11 Reporting every missing id

The client needs to learn every bad id in one round trip. It is not extracted into a generic util because the thrown exception differs per domain (SVC-14); extraction would force call sites to inject an exception type. The rule unifies an **idiom**, not a helper.

### CTL-31 · CTL-32 Response fields

- **Only what the frontend reads** — every field is a contract: it has to be documented, kept in sync and kept compatible. An unread field costs that upkeep for nothing, and adding one later is a one-line change.
- **Direct removal** — the frontend and backend ship as one team; a deprecation phase keeps a dead field alive for a release nobody waits for. Telling the frontend developers in the same change replaces it. A field another deployable reads is code-consumed and is out of this rule's scope.
- **No derivable values** — a value sent next to its inputs can disagree with them, and the frontend must choose which to believe. Computing it from the inputs leaves one source of truth.
- **Exceptions** — a permission verdict, a server-time judgement and a rule the frontend cannot see have a single correct owner, the server; recomputing them on the client duplicates logic that then drifts.

### CTL-13 Count responses include zero counts

A chart needs every value present, but `GROUP BY` returns only values that occur. `Count*Result.from` walks the service enum and fills the gaps, so the response shape does not depend on the data.

### CTL-12 Null fields in responses

Serializing nulls is the Jackson default and keeps every response's shape fixed in the OpenAPI schema; otherwise the same optional field is absent in one endpoint and `null` in another.

### CTL-23 Default page size

A client that omits `size` should not need to know which endpoint it is calling to know how many rows it gets. Per-controller constants drift.

### CTL-26 Feign timeouts and error translation

When some clients take timeouts from properties and others hard-code them, whether a timeout can be tuned without a release depends on the client. When failures are translated several ways (per-client `ErrorDecoder`, call-site wrappers, raw `FeignException` to the global handler), the same downstream 404 surfaces as different errors. One decoder per client maps downstream statuses once, next to the client that knows them.

## 5. Service and transactions

### STY-27 Prefer the plain option

Even when each advanced feature is individually justified, the reading cost accumulates — execution order diverges from code order, you have to trace where the commit happens, and failure gets a separate compensation path.

**The gate does not forbid `inTx`** — erasing an existing boundary silently loses dirty checking. What moves is the location of the external call, not the boundary.

**Canonical shape the gate cannot pass** — an external call whose argument comes from a DB row and whose result flows back into that row. Hoisting it to the controller would add a round trip just to fetch the argument and leak the use case into the controller. Querying the row twice is a structural cost TX-2 forces, not a violation.

**Abstraction waits for its second use (STY-28).** An interface with one implementation adds a hop to every read and a file to every change, and fixes the seam before a second use shows where the variation really is. Extracting when that use arrives is a local refactor; removing a wrong abstraction touches every caller. A dedicated executor is not created per domain either — check whether an existing pool or a synchronous call will do.

### TX-2 Long-running external calls inside a transaction

A transaction held across a slow external call holds its row locks and a pooled connection for the duration of that call. **Canonical incident** — adding `@Transactional` to an initializer made the next executor task start inside the uncommitted transaction; that task called another service, which called back to read the not-yet-committed row (invisible under READ COMMITTED), and the callback INSERT blocked on the UNIQUE index until commit.

`TransactionRunner` takes an `ObjectProvider<TransactionTemplate>` so the context still starts in modules without a transaction manager. `REQUIRES_NEW` is designed only when a call path that already holds a transaction actually exists — applying it preemptively for a hypothetical caller leaves fossil code (TX-7).

### TX-8 Why the two locks are not merged

Release timing blocks unification. Standardizing on advisory locks would force a transaction onto scheduler work that otherwise runs without one; standardizing on Redis would bring back a pre-commit release window for DB writes. The two locks solve different problems.

### TX-12 Startup seeding under concurrent instances

Instances starting simultaneously against an empty DB each see "no rows" and insert the same seed, so the second breaks startup on a unique violation. An advisory lock plus a filter of existing rows before one `saveAll` is equivalent to `ON CONFLICT DO NOTHING`, expressed in the application rather than native SQL.

### TX-13 Naming the lock mode

Hibernate's `PostgreSQLDialect` emits `for no key update` for `PESSIMISTIC_WRITE`, so writing `FOR UPDATE` in a document or diagnosis describes a lock the code never takes. The difference matters: `FOR KEY SHARE` (the FK lock an INSERT into a child table takes) conflicts only with `FOR UPDATE`, so child inserts do not wait behind the parent's update lock.

### SVC-24 Duplicate creates and link semantics

A pre-check (`exists*`) followed by `save` passes for both of two concurrent requests, and the second INSERT fails on the UNIQUE constraint as a raw 500. `translateUniqueViolation` turns that into a domain 409 wherever an insert of an entity that carries data is guarded by a UNIQUE constraint — a second insert may carry different data, so it is a real conflict. A link carries nothing a repeat could change, so linking what is already linked succeeds unchanged (SVC-25); it goes through `ON CONFLICT DO NOTHING` because a caught violation has already doomed the transaction. Removing what is not there is a 404, like every other single-resource miss.

### SVC-26 Handler idempotency

Reconnects, broker redelivery and sender-side retries can all deliver the same message twice or more. A row lock only serializes concurrent processing — it does not dedupe retransmission.

### SVC-29 Unknown external codes

External systems evolve independently, so a code the enum does not know arrives in production before the enum learns it. Failing loses the rest of an otherwise valid payload and redelivers it forever; storing a placeholder writes a value no screen can explain. Skipping the item with a WARN keeps the rest and makes the gap visible until the enum is extended.

### SVC-33 Event payloads

The persistence context is still open while an `AFTER_COMMIT` listener runs inline, but a listener may run later or elsewhere — on an executor thread, or in a different transaction — so an entity carried across that boundary brings a lazy association that fails or state that is stale; an authentication object drags auth state into code that only needs the actor id. A synchronous listener would see a live entity, but it would then depend on the publishing domain's entity structure, which undoes the separation the event exists for. Carrying the data listeners need, rather than ids alone, keeps a listener from calling the publisher's Service back — an injection in the reverse direction.

### STY-34 Entity change logging

**Why an audit log cannot replace it** — an audit log records only the events it declares, so changes made by schedulers, message handlers or boot-time initializers are not in it, and an audit record whose publish fails after commit is lost; only the log line keeps it.

**Why not a reflection dump** — a dump defaults to "expose everything", so someone must remember to block each new sensitive field. Explicit enumeration flips the default to "nothing goes out".

**Why bulk DML for an unbounded change** — a job that changes ten thousand rows through entity methods would print ten thousand INFO lines and bury every other operation (STY-35). The entity cannot lower its own level, because it does not know which path called it; a bulk DML bypasses the entity method, and one INFO summary keeps the result visible.

## 6. Enum

### SVC-27 Enum layer separation

The split preserves entity encapsulation, lets the Service enum evolve independently, and makes the Service enum the public contract. An `else`-less `when` in the mapper (SVC-28) turns a new constant into a compile error at every crossing instead of a silent fallthrough.

## 7. Repository and data

### REP-1 No Query or Modifying

An `@Query` string bypasses Kotlin's compile-time type checking, leaks JPQL/SQL into the API surface, breaks IDE renames, and encourages one-off queries that fragment the data-access layer. `@Modifying`'s `clearAutomatically`/`flushAutomatically` traps become something you manage by hand.

### REP-5 Query skeleton stays inline

QueryDSL is most readable when it maps 1:1 to the SQL that runs. Extracting the skeleton into a generic helper hides "exactly which query does this method run" from the call site. That duplication is not something to remove; extracting a `by()` predicate, reused across the id query and the count query, is encouraged.

### REP-8 countGroupedBy naming

`countBy*` is a Spring Data derived-query prefix, so `countByStatus(query)` reads as "count filtered by status." When the meaning is "count grouped by status," a `GroupedBy` token separates that axis.

### REP-11 Empty filters and stable ordering

If an empty list meant "no condition", a filter computed from the caller's allowances would turn an empty allowance into every row, and a client's "nothing selected" into "everything". Null = no condition, empty = no rows is the one meaning that can never widen a result.

Offset paging over a non-unique sort key (`createdAt`) lets equal-key rows swap between page queries, so a row is skipped on one page and repeated on the next. The id as the last key makes the order total (REP-12).

### REP-13 Native SQL binding

Reading rows as positional `Array<*>` with `(row[i] as Number)` casts fails with a `ClassCastException` when a column is reordered, and interpolating SQL text is one edit away from injection. Bound parameters and `Tuple` aliases fail loudly by name.

### REP-14 Reserved words and the Column exception

When an entity name is a Kotlin/Java reserved word, QueryDSL generates `keyword$`; for a reserved-word property, kapt silently skips the Q-class path. Avoiding reserved words (REP-20) avoids both.

### REP-15 Entity mapping choices

- **`@ManyToOne` inside a domain too** — a reference is a reference whichever domain owns the target; a raw id field leaves the repository unable to take the parent instance and grows workarounds.
- **`@Enumerated(STRING)`** — ordinals break when constants are reordered.
- **`protected set`** — public setters let any caller bypass the transition methods that carry the guards and the STY-34 change log.
- **Derived values are computed (REP-34)** — a stored copy of what other properties determine can disagree with them, and every new input adds a synchronization point in each transition method. A getter cannot be wrong. The cost is that QueryDSL cannot read it, which is why a value a query must filter or sort on in the database is the exception.
- **`Persistable` only for bulk inserts** — with an application-assigned id, `save` takes the merge path and issues a SELECT first. That costs one query per row in `saveAll` batches but nothing measurable for single saves, while `Persistable` adds a `new` flag every entity would have to maintain.

### REP-24 Immutable insert-only JSONB entities

When a nested collection goes into a `@JdbcTypeCode(SqlTypes.JSON)` field, Hibernate's JSON type does not deep-copy the snapshot, so the entity is judged dirty on every flush — one extra UPDATE per row right after the INSERT, rewriting the same value. It does not reproduce with a flat map, which makes it hard to spot.

### REP-27 Soft delete without a global filter

Some paths deliberately read deleted rows (tombstone lookups for audit and history screens), and a global filter silently breaks them, so the cost is an explicit predicate in each QueryDSL read, and an `isDeleted` check in the Service after a derived or own-PK read.

### REP-31 Redis TTL extension uses EXPIRE

Spring Data Redis `save` deletes and rewrites the key and refreshes `@Indexed` secondary indexes, and that path issues a Redis `KEYS` command per index. Redis is single-threaded, so a re-save on a hot request path stalls every other client. Spring Data Redis also populates only constructor properties on read, so the REP-17 `protected set` shape cannot apply to a `@RedisHash` entity.

## 8. Testing

### TST-17 Shared test helpers

Private copies of `runConcurrently` with different thread counts and error collection, and log capture attached by hand that left the appender and a forced level in place when the system under test threw, leaked into later tests in the same JVM. One helper per concern in the support class gives every test the same failure behavior and one knob for slow CI.

### TST-22 Exception assertions

When an exception type maps to one ErrorCode, the type already pins the behavior; asserting messages couples tests to wording that carries no contract. The ErrorCode is the contract only where one type carries several codes, and at the HTTP boundary, where `$.type` is what clients branch on.

### TST-33 One shared test context

Spring's test context cache keys on a class's full configuration, so any per-class variation starts another context with its own Testcontainers set and mock singletons in the same JVM, adding startup time and container load for each fork. A forked context's mocks are also not the support's shared ones, so the shared-mock guarantees of TST-3 and TST-26 quietly stop holding for that class.
