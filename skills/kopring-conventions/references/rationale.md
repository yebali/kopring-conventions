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

### STY-11 Named arguments where position is ambiguous

A swapped pair of same-typed arguments compiles, and a bare `true` or `10` says nothing at the call site; those are the cases a name prevents. Naming every argument of every call was the earlier rule: it made `foo(id = id, name = name)` the common shape and repeated what the types already separate, so it was narrowed to Kotlin's own coding convention. `maxOf`/`minOf`/`min`/`max` and vararg calls are exempt: their arguments are interchangeable, so `maxOf(a = x, b = y)` only adds noise.

### STY-19 Inline single-use intermediates

**Why not chain everything** — folding a remote call into a chain via `.let { client.… }` reads like a pure collection pipeline and hides the round trip. A remote call is its own statement; only guards fold into chain steps. That is why holding a remote call's result is a keep condition.

**Why a meaningful name does not keep a variable** — the name repeats what the expression already says, and a comment written to replace it would be the code translation STY-17 deletes.

**Canonical keep case** — a "before" snapshot referenced once but captured before the mutation that follows (`val before = OrderSnapshot.of(order)` ahead of `order.apply(input)`): without the variable the value no longer exists.

### STY-20 No plumbing parameters

A parameter that only carries a value from the caller to a deeper call encodes "this value comes from there" twice — at the call site and in the signature.

### STY-17 Comment policy

**Altitude, not a WHAT/WHY split.** A reader deciding whether to open a file needs the type's role in one line; a reader inside a function only needs help at the lines that are genuinely hard on a first read. Commenting every line buries the lines that need it.

**Why every public declaration gets one line (STY-16)** — a caller should not have to open a body to learn what a public type or function is for, and "only when a trigger holds" left that to each author's reading of the triggers. One line keeps the cost bounded; the requirement that it add a fact the name does not carry is what keeps it from becoming the name restated. Background paragraphs still sprawl and rot unreviewed, so tags and multi-paragraph KDoc stay out, and a private declaration keeps the trigger test.

**Comments describe current behavior only** — a past decision, design rationale, change reason, earlier behavior or future plan does not state what a caller can rely on now. Keep those in decision records, commit messages or the issue tracker. A current contract, precondition, ordering guarantee or operational limit may remain when STY-16 or STY-17 calls for it. Exception KDoc follows the same rule.

**Column alignment is forbidden** because `ktlintFormat` reverts it anyway.

### STY-18 Deliberate-simplification comment

A global lock, a full scan or a naive heuristic has a current operational limit the reader may need before relying on it. The fixed `// ponytail:` marker identifies that limit; it does not permit an explanation of the original decision or a plan for replacing it. Apply the history-and-rationale check before accepting a limit comment.

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

A timestamp is a point in time, and `Instant` is that and nothing more: two values are equal when they are the same moment, they order without a tie-break, and no host setting changes what is stored or sent. `ZonedDateTime` was the earlier choice; it carried a zone into every entity and DTO, which needed a comparison rule (`equals` compares zones too), three pinned zone settings to keep the serialized offset stable, and `toInstant()` in every test assertion. The zone still matters where a wall-clock value is derived: containers often run in UTC while developer machines run in a local zone, so "today", a numbering year, or a cron firing at 04:00 differ between the two. The application time zone fixes every date boundary and time-of-day schedule, and `ZoneId.systemDefault()` is forbidden because it silently follows the host. The cost of `Instant` is that a response always carries UTC and the client converts for display.

### STY-33 Durations as Duration

A number whose unit lives only in its name (`_SECONDS`, `_MS`) gets converted by hand (`Thread.sleep(X_SECONDS * 1000L)`) and multiplied wrong. A unit carried by the type cannot be, and the call site reads `Duration.ofSeconds(30)`.

### STY-35 Application log format and content

One shape — `{Subject} {action}: key=value` — lets a single grep find every line about an id. Ids, emails and client addresses are what an operator searches by, so they stay; passwords, tokens and keys never do, and neither does a whole command or properties object, because its `toString` prints every field — including a secret added later (STY-38). A Service repeating its entity's change log doubles every mutation line without adding a fact (STY-37).

**Why volume sets the level** — a line repeated per chunk, frame or tick hides the state changes an operator is looking for. Removing whole operations from production logs is the wrong cut: one INFO line per operation stays, carrying the result (ids or counts created, changed, deleted, skipped), and only the repetition inside an operation goes to DEBUG. A line that only says an operation started cannot tell whether it finished.

### STY-39 Failure handling

A failure that is absorbed must still be visible, and only failures whose consequence is bounded (cleanup, enrichment, metrics) may be absorbed at all. `Throwable` includes `OutOfMemoryError` and interrupts, so catching it is only safe when the block rethrows after cleanup. `runCatching` catches `Throwable` too, so it fits only a failure absorbed on purpose; a rethrowing or converting `runCatching` turns an `OutOfMemoryError` or an unrelated bug into the domain exception it throws (STY-40). `runCatching` inside a `suspend` function also catches `CancellationException`, which breaks structured cancellation, and so does any catch of `IllegalStateException` or wider, because `CancellationException` extends it (STY-41). A remote lookup that degrades to empty looks like "no data" to its caller, so it is allowed only where empty is harmless — display enrichment — and the KDoc says so.

### STY-43 Threads and lifecycle

Executors from `Executors.new*` inside a bean are invisible to Spring's shutdown, so in-flight work is cut off on redeploy; an unbounded thread-per-task helper turns a burst into thousands of threads. Hand-written retry loops each get their own backoff behavior and their own idea of what is safe to repeat; one shared mechanism with a required retry predicate (STY-45) keeps both uniform. Starting long-running work on `ApplicationReadyEvent` instead of `@PostConstruct` guarantees every bean it calls is ready, and one stop hook keeps shutdown in one place.

### STY-59 Shared bean state

A plain `var` or `HashMap` in a bean passes every single-threaded test and fails only under concurrent requests, as a lost update or a corrupted map that no stack trace points to. Naming the allowed types makes the question "who else writes this?" part of declaring the field, and keeping per-instance memory out of cross-instance decisions stops a second replica from disagreeing with the first.

### STY-60 Exhaustive when

An `else` answers for constants that do not exist yet, so the person adding one is never asked what it should do there. Without it the compiler lists every decision the new constant needs. The mappers already relied on this (SVC-28); the same reasoning holds for every branch on a closed set.

### STY-47 Files and streams

Mixing `java.io.File` and NIO `Path` means converting back and forth and ignoring the `Boolean` results of `File.delete()`/`mkdirs()`; NIO throws instead. A Result carrying an open `InputStream` leaks the descriptor whenever an exception lands between opening and the controller wrapping it, because nobody owns the close; returning a `Path` or a writer keeps opening and closing in one place.

### STY-58 · CFG-20 The clock and the zone

A no-argument `now()` makes every date boundary depend on the moment the test runs, so a "today" or year-end rule is tested only on the day it happens to matter. An injected `Clock` lets a test stand on any instant. Pinning the JVM, Hibernate and Jackson zones keeps whatever still derives a date or a wall-clock time — a log line, a formatted value, a legacy column — from depending on which host ran it.

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

### STY-14 File and package placement

**The only judgment axis is "does it replicate the layer tree."** A directory need not carry a layer name — as long as it does not replicate the layer tree, it is fine. When two placement schemes coexist in one domain, every new file becomes a guessing game. **The cost of flattening**: layer directories grow large, so inside them the domain name prefix is the only clue to which feature a file belongs to — the prefix is mandatory, not stylistic.

### SVC-38 · SVC-39 Cross-domain communication

**Domains stay separable only when each knows as little as possible about the others.** A Service that injects another domain's Service to push a write or to decorate its Result binds the two domains together: the publisher's code changes whenever a new domain needs to react, and two domains that call each other close a bean cycle. An event reverses the dependency — the reacting domain knows the event, the publisher knows nobody — and composing in the inbound adapter keeps every Service reading its own domain only. Injection stays for the one case an event cannot cover: the Service needs the answer to go on.

**The deployable boundary follows the same split with different transport.** Inside one process an event is a method call with no network in between, so it can even share the publisher's transaction. Between deployables nothing is shared, so the question is whether the caller waits. A caller that needs the answer, or whose own result depends on the other side having finished, calls over HTTP: it gets the outcome or the failure on the spot and can roll back. A caller that only tells the other side to act, and whose response and commit do not wait for it, sends a broker message: the same call over HTTP fails when the other side is down and leaves the two sides inconsistent — or, when the failure is swallowed, silently loses the work — while a message waits until the consumer is back and is redelivered. Splitting by "reads over HTTP, writes over the broker" would instead push a message onto a write the end user is waiting on, with no way to hand its result back.

**Asking and telling follow the caller's outcome, not the return type.** A precondition made before the caller's own writes is asking even when it returns `Unit`; turning it into an event would run the gate after the writes it was meant to guard. A call made after the caller's own state change, with its result discarded, is telling.

## 4. Controller

### CTL-15 Limits are enforced where the bytes pass

A count limit is a property of the request body, so the Command validates it. A size limit on uploaded bytes belongs to the service the bytes actually stream through — the only place that can reject an oversized file before writing it. Moving it elsewhere means either accepting the write and deleting afterwards, or routing bytes through a service with no other reason to see them.

### CTL-18 Response status only CREATED and NO_CONTENT

Unifying everything to 200 OK loses the difference between "created" and "done" for the generated OpenAPI spec and every client. Only the two codes that carry meaning for every client are allowed — 201 for creation by `POST` or an UPSERT `PUT`, 204 for a body-less update of an existing target or a `DELETE`; other successful responses stay 200. An UPSERT exposes its actual creation outcome so the controller selects 201 versus 200/204, so there is no per-endpoint status decision beyond those two shapes.

### CTL-3 No required false

A parameter-level default object doubly encodes the same "empty" state as a DTO field default. To allow an empty request, the client sends `{}` and every Request field carries a default.

### CTL-19 PUT contracts

PUT supports partial update, full replacement and UPSERT, and PATCH stays out, so every change to an existing URI uses one verb and a client never chooses between two per endpoint. What the change does is then a property of the endpoint, not of the verb, so each endpoint states its contract. The endpoint contract makes omission, explicit null and missing-target behavior predictable. Partial update needs a presence-aware input so omission preserves a value while explicit null clears it. Full replacement describes every updatable field. UPSERT needs a stable target key and atomic uniqueness so repeating or racing the request does not create duplicate resources. Its creation outcome determines the 201 versus 200/204 response (CTL-18).

### CTL-28 Composition in the inbound adapter

A response that shows several domains' data is a presentation need, not a business rule, so no domain Service should own it. When the adapter composes, each Service keeps returning its own domain's Result, the Results stay reusable by other callers, and no Service grows an injection whose only purpose is one screen. The adapter only passes ids along; business decisions depending on a Result move into a Service. Selecting an UPSERT HTTP status from its `created` outcome is response conversion, while deciding whether to create or update remains in the Service.

### CTL-22 Service ownership of endpoints

When an endpoint in one service takes or returns another service's data, the client cannot tell which service owns the API, and the owning service's rules have to be mirrored in the foreign DTOs. Keeping each contract inside one service means the owner alone decides. An internal call that carries another service's data is the same leak, only hidden from the API docs.

### CTL-21 One read endpoint per resource

One read path per type or lookup key multiplies Request/Response/Command copies, and the copies drift (one includes deleted rows, another does not). Every client must know which path matches which case, and a new case means a new endpoint. Branching on a filter or a response field costs a client nothing when a type is added. Commands are left out because their rules can genuinely differ per type. `POST …/search` survives because a body is the only place nested filters fit, and `POST` on the collection already means create.

### CTL-29 Shared-module wire DTO mapping

A DTO from a shared module cannot get a `toCommand()` (the shared module cannot see service Commands), so the mapping lives in a service-layer `Command.from(dto)` factory.

### SVC-11 Reporting every missing id

The client needs to learn every bad id in one round trip. It is not extracted into a generic util because the thrown exception differs per domain (SVC-14); extraction would force call sites to inject an exception type. The rule unifies an **idiom**, not a helper.

### SVC-15 One code for structural checks

A named exception and an ErrorCode per length or range check produced dozens of classes no client ever branched on. One shared function and one shared code keep the check a single line; a failure a client must tell apart is by definition a business failure and keeps its own exception. The function is not the stdlib `require`, because answering `IllegalArgumentException` with a 400 would hide a library's or a bug's exception behind a client error.

### SVC-44 Scope from the principal

An id in the request is a claim; the principal is the only identity the server verified. A scope key read from the body or the query lets any signed-in caller name someone else's rows, and no test written from the happy path notices. Answering 404 rather than 403 for an out-of-scope row keeps the endpoint from confirming which ids exist. The rule lived only in the coverage table (COV-1), which told tests what to expect without telling the code how to get there.

### SVC-45 · CTL-34 Bounded input

A length or count nobody checked is still enforced — by the column, the driver's parameter limit or the heap — and reported as a 500 at whatever layer hits it first. Checking in the Command turns it into a 400 that names the field, and reusing the entity's length constant keeps the check from drifting from the column. Spring Data's page cap is 2000 unless set, and it clamps instead of rejecting, so an unset cap silently defines the heaviest request every paged endpoint accepts.

### CTL-31 · CTL-32 Response fields

- **Only what the frontend reads** — every field is a contract: it has to be documented, kept in sync and kept compatible. An unread field costs that upkeep for nothing, and adding one later is a one-line change.
- **Direct removal** — the frontend and backend ship as one team; a deprecation phase keeps a dead field alive for a release nobody waits for. Telling the frontend developers in the same change replaces it. A field another deployable reads is code-consumed and is out of this rule's scope.
- **A definition has one owner** — a derivation that decides something (which elements count, the zero case, rounding, the current moment, the caller) is a definition. Recomputed on the client, it is copied into every screen and every frontend, and the copies drift the next time the rule changes; sent by the server, it changes in one place. A derivation that decides nothing — presence, a whole-list count or sum, a position, a format — cannot drift from its inputs, so sending it too would state the same fact twice.
- **A closed list** — "whatever the frontend can compute" left each case to judgment: a conditional count or a ratio is computable from the inputs, yet it carries a definition. Naming the four kinds the frontend derives, and sending everything else, lets two reviewers reach the same answer. The one carve-out is a conditional count of elements the screen must hold and list anyway: the count is then the length of a list it already has, and sending it beside that list would state the same fact twice.
- **Common practice** — public APIs send derived values that carry a definition: Stripe's invoice sends `amount_remaining` beside `amount_due` and `amount_paid`, and CloudWatch's statistics send `Average` beside `Sum` and `SampleCount`. This rule matches them there and is stricter only on restatements such as a flag beside the timestamp it reads.

### CTL-13 Count responses include zero counts

A chart needs every value present, but `GROUP BY` returns only values that occur. `Count*Result.from` walks the service enum and fills the gaps, so the response shape does not depend on the data.

### CTL-12 Null fields in responses

Serializing nulls is the Jackson default and keeps every response's shape fixed in the OpenAPI schema; otherwise the same optional field is absent in one endpoint and `null` in another.

### CTL-23 Default page size

A client that omits `size` should not need to know which endpoint it is calling to know how many rows it gets. Per-controller constants drift.

### CTL-26 Feign timeouts and error translation

When some clients take timeouts from properties and others hard-code them, whether a timeout can be tuned without a release depends on the client. When failures are translated several ways (per-client `ErrorDecoder`, call-site wrappers, raw `FeignException` to the global handler), the same downstream 404 surfaces as different errors. One decoder per client maps downstream statuses once, next to the client that knows them.

### CTL-33 No deprecation phase

The frontend and the backend ship as one team, and the other clients are deployables of the same system, so every consumer is known and can change in step. A deprecation phase would keep dead fields alive for consumers that do not exist; telling the frontend and changing the internal clients in the same change replaces it.

## 5. Service and transactions

### STY-27 Prefer the plain option

Even when each advanced feature is individually justified, the reading cost accumulates — execution order diverges from code order, you have to trace where the commit happens, and failure gets a separate compensation path.

**The gate comes before the Facade** — a single remote read whose answer is only input does not need a second class: the controller makes the call and the Service stays one transaction. A Facade is for what the gate cannot pass.

**Canonical shape the gate cannot pass** — an external call whose argument comes from a DB row and whose result flows back into that row. Hoisting it to the controller would add a round trip just to fetch the argument and leak the use case into the controller. Reading the row in two transactions is a structural cost TX-2 forces, not a violation.

**Abstraction waits for its second use (STY-28).** An interface with one implementation adds a hop to every read and a file to every change, and fixes the seam before a second use shows where the variation really is. Extracting when that use arrives is a local refactor; removing a wrong abstraction touches every caller. A dedicated executor is not created per domain either — check whether an existing pool or a synchronous call will do.

### TX-1 · TX-2 · TX-3 Transactional Services and Facades

**The default that fails safe.** With `@Transactional` on each method, a write method whose annotation was forgotten runs every repository call in its own transaction: nothing is atomic and a dirty-checked change is lost. With class-level `readOnly = true`, a forgotten override drops the write. With class-level read-write, a forgotten `readOnly` costs a read its optimizations and nothing else — the only one of the three whose mistake does not lose data.

**Why the external call is kept out by structure.** A transaction held across a slow external call holds its row locks and a pooled connection for the duration of that call. "Do not call out inside a transaction" was a rule each method had to remember, and marking a method non-transactional inside a transactional class leaves a trap: a call to a write method of the same class skips the proxy and opens no transaction (TX-18). A Service that cannot inject an outbound bean cannot make the mistake, and a Facade always reaches its DB steps through another bean's proxy. The cost is one class per flow with an outbound call; the earlier rule avoided that class and paid for it in `inTx` blocks whose correctness depended on reading order.

**Canonical incident** — adding `@Transactional` to an initializer made the next executor task start inside the uncommitted transaction; that task called another service, which called back to read the not-yet-committed row (invisible under READ COMMITTED), and the callback INSERT blocked on the UNIQUE index until commit.

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

### TX-14 Lost updates

Dirty checking writes back whatever the transaction read, so two concurrent edits silently keep the later one. `@Version` turns the loss into a visible 409, and an atomic UPDATE removes the read from the counter path entirely; neither holds a lock across the request.

### TX-15 Checked exceptions and rollback

Spring's default is kept so that the code behaves as every Spring reference describes, and a global `rollbackOn` switch was dropped for that reason. The price is a trap Kotlin makes easy: no signature shows a checked exception, so nobody is prompted to write `rollbackFor`, and a partial write commits. The rule therefore names the place it bites — a Service method that lets Java I/O or a library's checked exception escape — and unwrapping in `TransactionRunner` keeps the two boundary APIs throwing the same exception.

### TX-16 Stale writes

`@Version` alone protects overlapping transactions, not the time a form stays open. A full replacement can overwrite newer fields, and a partial update can still overwrite the fields it supplies. A version in the Request lets the Service compare the state the client edited with the current row; the update branch of an UPSERT needs the same protection. A create has no previously read version, and a stale update must not recreate a deleted target. The version travels in the body alongside the supplied fields.

### TX-17 · TX-18 Annotations that silently do nothing

Both fail without a signal. A write inside a read-only transaction is never flushed, and an annotation on a private or self-invoked method never reaches the proxy; the code reads as correct and the tests that call the method directly pass. Stating each as a rule gives review and the lint something to cite, where before only a sentence inside another rule mentioned them.

### CFG-21 Timeouts

A missing timeout is found during the other side's outage, when every request thread is already waiting on it. Declaring each one as a property makes the wait a reviewed number per environment instead of whatever the library ships.

### SVC-42 Messages that must not be lost

A commit and a broker send are two systems; no ordering of the two calls makes them atomic. The outbox makes the message part of the commit and retries the send; a reconciliation job accepts the loss and repairs it later. Naming best-effort publishes keeps the distinction visible in review.

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

### REP-20 Reserved words and the Column exception

When an entity name is a Kotlin/Java reserved word, QueryDSL generates `keyword$`; for a reserved-word property, kapt silently skips the Q-class path. Avoiding reserved words avoids both.

### REP-15 Entity mapping choices

- **`@ManyToOne` inside a domain, an id across domains** — inside a domain a raw id field leaves the repository unable to take the parent instance and grows workarounds, so the reference is an association. Across domains the association was the earlier rule too; it let one domain's query fetch and lazily load another domain's rows, which is the coupling SVC-17 and SVC-39 keep out of the Services. An id stops at the boundary: the other domain's data comes from its Service, and the foreign key in the migration still guards integrity.
- **`@Enumerated(STRING)`** — ordinals break when constants are reordered.
- **`protected set`** — public setters let any caller bypass the transition methods that carry the guards and the STY-34 change log.
- **Derived values are computed (REP-34)** — a stored copy of what other properties determine can disagree with them, and every new input adds a synchronization point in each transition method. A getter cannot be wrong. The cost is that QueryDSL cannot read it, which is why a value a query must filter or sort on in the database is the exception.
- **`Persistable` only for bulk inserts** — with an application-assigned id, `save` takes the merge path and issues a SELECT first. That costs one query per row in `saveAll` batches but nothing measurable for single saves, while `Persistable` adds a `new` flag every entity would have to maintain.

### REP-24 Immutable insert-only JSONB entities

When a nested collection goes into a `@JdbcTypeCode(SqlTypes.JSON)` field, Hibernate's JSON type does not deep-copy the snapshot, so the entity is judged dirty on every flush — one extra UPDATE per row right after the INSERT, rewriting the same value. It does not reproduce with a flat map, which makes it hard to spot.

### REP-27 Soft delete through a switchable filter

Repeating `deletedAt.isNull` in every query was the earlier rule, and one forgotten predicate showed deleted rows to ordinary users. A filter that is on by default removes that mistake. It has to be one that can be switched off, because some paths read deleted rows on purpose — a super-admin screen, audit and history lookups: `@SQLRestriction` and `@SoftDelete` cannot be disabled and would push those reads into native SQL or a second mapping of the table. A Hibernate `@Filter` does not apply to a lookup by primary key, so the Service still drops a deleted row after `findById`; that keeps a to-one association to a deleted row loadable instead of failing on access.

### REP-35 Plain entity classes

A Kotlin `data class` derives equality and hashing from every property, which for an entity means lazy loading, recursion through bidirectional relations and a hash that moves when a field changes. Hibernate already guarantees one instance per row inside a persistence context, so default identity is the correct equality there.

### REP-36 · REP-37 Indexes and online migrations

PostgreSQL leaves foreign keys unindexed, so a cascade delete or a lookup by parent scans the child table once the table grows. Index builds and constraint checks lock out writes on large tables; `CONCURRENTLY`, `NOT VALID` and `lock_timeout` keep a deployment from stalling production traffic behind a migration.

### REP-39 Stored enum names

The column holds the constant's name, so a rename in Kotlin leaves rows that no constant matches, and they fail on load — in production, on the first read of an old row, not in a test whose schema and data are new. Tying the data migration to the same change is the only point where the author still knows the old name.

### REP-40 Half-open ranges

An inclusive end needs a "last instant", and every way of writing one is wrong at some precision; `[from, to)` needs none, and adjacent ranges tile without sharing a row.

### REP-41 Orphan-removal collections

Hibernate tracks removed children through the collection instance it handed out. Reassigning the property looks like the simplest way to replace the set and fails only at flush, away from the line that caused it.

### REP-42 · REP-43 Optional, references and unbounded reads

`Optional` in Kotlin duplicates the nullable type and adds a second idiom for the same read. `getReferenceById` on an id nobody checked trades one SELECT for an error that arrives late and as the wrong status; on a row the transaction already holds it is only the foreign key, which is why it is limited rather than banned. A bare `findAll()` works on the day's data and grows into the outage; requiring a bound makes the author say what limits the result.

### REP-44 One list method

A derived `findAllByX` is the first of a family: the next condition adds `findAllByXAndY`, then a fetch-graph variant, and callers must know which one filters what. One `listByQuery` whose Query class grows by a field keeps a single place to read what the list can be filtered by, and starting that way from the first read removes the later migration and the judgment of when two reads are "variations" of each other.

### REP-38 Sortable properties

`?sort=` is client input that becomes SQL. Without an allow-list it reaches unindexed columns, implicit joins and fields the client may not see, and an expensive sort is a cheap way to load the database.

### REP-31 Redis TTL extension uses EXPIRE

Spring Data Redis `save` deletes and rewrites the key and refreshes `@Indexed` secondary indexes, and that path issues a Redis `KEYS` command per index. Redis is single-threaded, so a re-save on a hot request path stalls every other client. Spring Data Redis also populates only constructor properties on read, so the REP-17 `protected set` shape cannot apply to a `@RedisHash` entity.

## 8. Testing

### TST-17 Shared test helpers

Private copies of `runConcurrently` with different thread counts and error collection, and log capture attached by hand that left the appender and a forced level in place when the system under test threw, leaked into later tests in the same JVM. One helper per concern in the support class gives every test the same failure behavior and one knob for slow CI.

### TST-22 Exception assertions

When an exception type maps to one ErrorCode, the type already pins the behavior; asserting messages couples tests to wording that carries no contract. The ErrorCode is the contract only where one type carries several codes, and at the HTTP boundary, where `$.type` is what clients branch on.

### TST-6 English test names

Test names are read next to the code they exercise, in failure reports and CI logs that also carry English identifiers and messages; one language keeps a name searchable beside the class and enum names it mentions. Korean names were the earlier rule.

### TST-8 · TST-11 Slices and cleanup

A controller test against a mocked Service checks one thing — the HTTP contract and the Command it produces — and needs no database, so it cannot be broken by data. A repository test in the JPA slice rolls back, which removes exactly what it wrote. Only Service tests commit, and they cannot roll back without hiding the commit-time behaviour they exist to check, so their rows are truncated after each test; serial classes and one database per fork make that wipe equal to "delete what this test created". The earlier rule kept one full context for every test and never cleaned up, which made every count assertion depend on scoping to owned data. The cost of the slices is that no test runs a request from HTTP through to the database.

### TST-33 Three fixed test contexts

Spring's test context cache keys on a class's full configuration, so any per-class variation starts another context with its own Testcontainers set and mock singletons in the same JVM, adding startup time and container load for each fork. Three support classes fix the count at three per module. A forked context's mocks are also not the support's shared ones, so the shared-mock guarantees of TST-3 and TST-26 quietly stop holding for that class.

### TST-34 · COV-9 · COV-10 What the shared context hides

A scheduler firing mid-test changes rows and mock state at random moments, which turns into flaky failures nobody can reproduce. Mocking every Feign client keeps service tests fast but leaves the client's own mapping and error translation untested, so each client gets one test at its real HTTP boundary. Entity-generated test schemas never run the migrations, so one guard per module proves the migrations and the mapping agree before a deployment does.

### TST-35 One test clock

The `Clock` bean is as shared as any mock: one instance for every class in the JVM. A clock a test moved and left there shifts "now" for whichever test runs next, which fails far from its cause. One clock in the support class, reset after each test, gives time the same ownership rule as the other shared doubles, and separates "what time is it" (the clock) from "how old is this row" (backdating).
