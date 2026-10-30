# Service Layer Conventions

**Owns:** Service method signatures, Command/Result mapping, validation, exceptions and failure forms, cross-domain access and communication, method order, writes and idempotency, enum layers, bean roles, Spring events, and message consumers. **Read when:** Editing a Service, a Command/Result, an enum mapper, an event listener, a message consumer, or a domain dependency.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| SVC-1 | | Read the callers, tests and dependents of a Service or Entity before changing it | — |
| SVC-2 | ⚠ | Internal entity-returning methods are named bare `getEntity`/`findEntityBy…`/`listEntitiesBy…`; a qualifier only disambiguates | [§2](#2-method-signatures) |
| SVC-3 | | A Service takes a Command and returns a `*Result` (or an entity to another Service), never a Response | [§2](#2-method-signatures) |
| SVC-4 | | Multiple results are wrapped in a `List*Result`/`Page*Result`, never a raw `List<*Result>` | [§2](#2-method-signatures) |
| SVC-5 | | No raw entity-field value as a public return | [§2](#2-method-signatures) |
| SVC-6 | | DTOs a Command or Result uses are its own inner data classes; duplicate a shape, never extract it | [§3](#3-command-and-result) |
| SVC-7 | | Entity types are never Command/Result field types; an entity appears only as a `from(entity)` parameter | [§3](#3-command-and-result) |
| SVC-8 | | Conversions: `request.toCommand(…)`, `command.toEntity()`, `Result.from(entity)` | [§3](#3-command-and-result) |
| SVC-9 | | Validation prefixes: `check*` throws, `verify*` returns a result, `is*`/`can*`/`has*` return Boolean; no `validate*` | [§4](#4-validation) |
| SVC-10 | | Structural validation in `Command.init {}`, business validation in a private `check*` | [§4](#4-validation) |
| SVC-11 | | A not-found check over requested ids reports every missing id | [§4](#4-validation) |
| SVC-12 | | A `resolve*` that crosses a service boundary carries a KDoc naming the callee and is never folded into a chain | [§4](#4-validation) |
| SVC-13 | ⚠ | Exception messages are English | [§5](#5-exceptions-and-failure-forms) |
| SVC-14 | | A Service throws only its own domain's named exceptions with a domain `ErrorCode` | [§5](#5-exceptions-and-failure-forms) |
| SVC-15 | | Failure forms follow the table: no stdlib assert or generic exception in Service/Command; `requireNotNull` only for internal invariants | [§5](#5-exceptions-and-failure-forms) |
| SVC-16 | | A 4xx is logged without its stack trace, message built inside the lambda; a 5xx keeps the trace | [§5](#5-exceptions-and-failure-forms) |
| SVC-17 | | Never inject another domain's Repository; call its Service (listed exceptions) | [§6](#6-cross-domain-access) |
| SVC-18 | | A qualified entity-returning variant exists only for a different fetch graph or an extra check, and its name says which | [§6](#6-cross-domain-access) |
| SVC-19 | | Choose the fetch strategy from the caller's access pattern; traversal outside the transaction or in a loop is always a fetch join | [§6.1](#61-fetch-strategy) |
| SVC-20 | | Never `@Lazy` to break a bean cycle; move the unnatural edge | [§6.3](#63-breaking-bean-cycles-without-lazy) |
| SVC-21 | | Public methods in CRUD order; state transitions and other actions come last | [§7](#7-method-order) |
| SVC-22 | | Private methods after public: checks, then step methods in call order, then conversions; `companion object` last | [§7](#7-method-order) |
| SVC-23 | | Persist a collection with one `saveAll`, never `save` in a loop | [§8](#8-writes-duplicates-and-idempotency) |
| SVC-24 | | An insert guarded by a UNIQUE constraint runs inside `translateUniqueViolation`, which raises the domain's 409 exception | [§8](#8-writes-duplicates-and-idempotency) |
| SVC-25 | | Re-creating an existing link succeeds without change; removing a missing link is a 404 | [§8](#8-writes-duplicates-and-idempotency) |
| SVC-26 | | A handler of redeliverable messages is idempotent | [§8](#8-writes-duplicates-and-idempotency) |
| SVC-27 | | Enum layers follow the boundaries the enum crosses; never merge the entity enum with the service enum | [§9](#9-enum-layer-separation) |
| SVC-28 | | Enum mappers are `{Domain}EnumMapper`/`{Protocol}EnumMapper` with an `else`-less `when` and `to{Layer}{Type}` names | [§9.2](#92-two-mappers) |
| SVC-29 | | An unknown external code is skipped with a WARN log, never stored or thrown | [§9.3](#93-unknown-external-values) |
| SVC-30 | | `@Service` only for a transactional domain use-case entry point; other beans are `@Component` with a role suffix | [§10](#10-service-vs-component) |
| SVC-31 | | Drop a bean's suffix and keep it only if what remains is not a usable name | [§10](#10-service-vs-component) |
| SVC-33 | | An event carries ids plus the data its listeners need; never an entity, an `@Embeddable`, an entity-inner enum or the authenticated principal object | [§11](#11-spring-events) |
| SVC-34 | | An `AFTER_COMMIT`/`BEFORE_COMMIT` `@TransactionalEventListener` sets `fallbackExecution = true`; an `AFTER_ROLLBACK`/`AFTER_COMPLETION` one never does | [§11](#11-spring-events) |
| SVC-35 | | Listener methods are `on{Event}`; the publisher field is `applicationEventPublisher` | [§11](#11-spring-events) |
| SVC-37 | | A failed message is redelivered up to the maximum attempts, then dead-lettered; a periodic snapshot may be acked and dropped | [§12](#12-message-consumers) |
| SVC-38 | | Between deployables a call the caller waits on is an HTTP client call and a state change the caller does not wait for is a `*Message` over the message broker; domains inside one deployable follow SVC-39 | [§6](#6-cross-domain-access) |
| SVC-39 | | Between domains of one deployable: compose outputs in the inbound adapter, inject another domain's Service only to use its answer, publish an event when a state change affects another domain; asking and telling are decided by the caller's outcome, not the return type | [§6](#6-cross-domain-access) |
| SVC-40 | | A listener that must commit with the publisher is a synchronous `@EventListener`; one that may run after commit is `AFTER_COMMIT` and writes through `inNewTx` | [§11](#11-spring-events) |
| SVC-41 | | The publishing domain owns the event class; the affected domain owns a thin listener that delegates to its own Service | [§11](#11-spring-events) |

Service code also follows the cross-cutting rules: logging ([STY-1](code-style.md#2-baseline), [logging](code-style.md#12-logging)), single-use intermediates ([STY-19](code-style.md#6-single-use-intermediates)) and the plain option ([STY-27](code-style.md#10-prefer-the-plain-option)). Transaction boundaries, external calls and locks are TX rules in [transactions.md](transactions.md).

---

## 2. Method signatures

Services live in `service/*.kt`, Commands and Results in `service/command/*.kt`. A Service owns business logic, transactions and validation.

**SVC-2** — An entity-returning method that another Service calls drops the domain noun, because the receiver already carries it: bare `getEntity`/`findEntityBy…` for one row, `listEntitiesBy…`/`getEntities` for several. `get*` throws the owning domain's not-found exception when the row is absent; `find*` returns null. A qualifier appears only to disambiguate (`getEntityWithItems`, `getActiveEntity`; [SVC-18](#6-cross-domain-access)). These methods are internal: a Controller never calls them, and each is `@Transactional(readOnly = true)` or joins the caller's transaction. ✅ `getEntity(id): Order` ❌ `getOrderEntity(id)`

**SVC-3** — A Service accepts a Command and returns a `*Result`, never an Entity or a Response. The one exception is the internal entity-returning method of SVC-2.

| Return type | Use case | Example |
|---|---|---|
| `*Result` | Single item to the Controller | `getOrder(cmd): OrderResult` |
| `List*Result` (wrapper) | Multiple items to the Controller | `listOrders(cmd): ListOrderResult` |
| `Page*Result` | Paginated items to the Controller | `pageOrders(cmd): PageOrderResult` |
| Entity (bare `Entity`/`Entities`, no domain noun) | Internal Service-to-Service only; never from a Controller (SVC-2) | `getEntity(id): Order`, `listEntitiesByIds(ids)` |
| `Unit` | Side effect only | `deleteOrder(cmd)` |

**SVC-4** — Never return a raw `List<*Result>`; wrap it. The wrapper declares its own inner DTO and never reuses another `*Result` as its element type (SVC-6 — duplicate even when the shapes match):

```kotlin
// ✅ the wrapper Result declares its own nested DTO (siblings may redeclare the same shape)
// the entity is imported as `OrderEntity` so the nested DTO keeps the plain name (STY-50)
data class ListOrderResult(val orders: List<Order>) {
    data class Order(val id: UUID, val memberId: UUID)
    companion object { fun from(orders: List<OrderEntity>) = ListOrderResult(orders.map { Order(it.id, it.memberId) }) }
}
// ❌ reusing OrderResult as the element type
data class ListOrderResult(val orders: List<OrderResult>)
```

**SVC-5** — A public Service method never hands back a bare value pulled from entity fields (`List<BigDecimal>`, `List<UUID>`, a `Map`, a scalar). The correct form depends on what the caller needs: (a) the related **entity** across domains → return it through bare `getEntity`/`listEntitiesBy…` (SVC-2) and let the caller extract; (b) a **projection or view** → wrap it in a `*Result`. Exempt: a computed `Boolean`, count or intersection; ids or counts a mutating command produces (`deleteByOrderId(orderId): Long`, `startSession(memberId): UUID`); and any `*Result`-wrapped return (the rule targets the public return type, not internals).

```kotlin
// ❌ raw field projection
fun listPricesByIds(ids: List<UUID>): List<BigDecimal> = repo.listPricesByIds(ids)

// ✅ the caller needs the entity → return it; the caller does .map { it.price }
fun listEntitiesByIds(ids: List<UUID>): List<Product> = ...
// ✅ a projection for a response → wrap it
fun listItemIds(orderId: UUID): ListOrderItemIdsResult = ListOrderItemIdsResult(repo.findItemIds(orderId))
```

---

## 3. Command and Result

```
Request.toCommand() → Command → Service → Result.from(Entity) → Response.from(Result)
```

| Layer | Location | Naming | Purpose |
|---|---|---|---|
| Request/Response | `controller/rest/*.kt` | `{Action}{Entity}Request/Response` | HTTP contracts |
| Command/Result | `service/command/*.kt` | `{Action}{Entity}Command/Result` | Business DTOs |
| Query | `repository/query/*.kt` | `{Action}{Entity}Query` | Repository input |
| Entity | `entity/*.kt` | `{Entity}` | Persistence |

File placement — one class per file at the `service/command/` root — follows [STY-12](code-style.md#4-files-and-packages).

**SVC-6** — DTOs a Command or Result uses are its own inner data classes. When two files need the same shape, each declares its own copy; never extract a shared DTO and never reuse another `*Result` as a field or element type. The Request/Response counterpart is [CTL-5](controller.md#41-inner-data-classes).

**SVC-7** — `@Entity`, `@Embeddable` and entity-inner enum types are never Command/Result field types: use an inner DTO and the service-layer enum (duplication allowed). An entity import appears only as the parameter of a `companion object { fun from(entity: Xxx) }` factory. The controller-side rule is [CTL-6](controller.md#42-no-entity-imports).

```kotlin
// ❌ an @Embeddable and an entity-inner enum leaking into a Command (Address here is the entity type)
data class CreateOrderCommand(val shippingAddress: Address, val status: Order.Status)
// ✅ own inner DTO + service-layer enum — the name stays `Address` (the declaring class differs,
//    so nothing collides); filler suffixes such as `AddressInput`/`AddressDto` are forbidden (STY-50)
data class CreateOrderCommand(val shippingAddress: Address, val status: OrderStatus) {
    data class Address(val street: String, val zipCode: String)
}
```

**SVC-8** — Each conversion has one fixed place:

| Conversion | Method | Location |
|---|---|---|
| Request → Command | `request.toCommand(…)` | `*Request` (controller) |
| Command → Entity | `command.toEntity()` | `*Command` |
| Entity → Result | `Result.from(entity)` | `*Result` companion |
| Result → Response | `Response.from(result)` | `*Response` companion |

---

## 4. Validation

**SVC-9** — The prefix states what a validation method does:

| Prefix | Behavior | Return |
|---|---|---|
| `check*` | Throws a domain exception on failure | `Unit` |
| `verify*` | Returns the validation result as an object, never throws | `Verify*Result` |
| `is*` / `can*` / `has*` | Boolean predicate | `Boolean` |

Forbidden: the `validate*` prefix (its meaning overlaps `check*` and `verify*`); a `check*` that returns `Boolean`; a `verify*` that returns `Unit` and throws (rename it `check*`). Example: [SVC-9](examples/service.md#svc-9--validation-method-naming).

**SVC-10** — Structural validation (required, length, format, empty collection) lives in `Command.init {}`. Business validation (entity existence, permissions, state) lives in a private Service `check*()`. Validation that returns a result to the caller (token validity) is a public Service `verify*()`.

**SVC-11** — A check of "which requested ids were not found" collects **every** missing id with `requested - found.map { it.id }.toSet()` and throws the domain's named exception ([SVC-14](#5-exceptions-and-failure-forms)) with all of them. It never throws on the first miss, because the client must learn every bad id in one round trip. The idiom is the rule; it is not extracted into a shared util, because each domain throws a different exception. Example: [SVC-10 · SVC-11](examples/service.md#svc-10--svc-11--structural-checks-and-every-missing-id).

**SVC-12** — The `resolve*` prefix says nothing about cost: it spans pure in-memory computation (`resolveThumbnail`) and remote round trips (`MemberReader.resolveMembers` calls another service per page). A `resolve*` that crosses a service boundary therefore carries a one-line KDoc naming the callee — the summary trigger of [STY-16](code-style.md#5-comments-and-kdoc) — not a line comment. Its call site never folds it into a `.let {}` chain, so the remote call stays visible ([STY-19](code-style.md#6-single-use-intermediates)).

---

## 5. Exceptions and failure forms

**SVC-13** — A thrown exception's `message` is English; comments stay Korean ([code-style §5](code-style.md#5-comments-and-kdoc)). ❌ `throw OrderNotFoundException("<Korean text>")`

**SVC-14** — A Service throws only its own domain's exceptions: the order Service never throws `PaymentNotFoundException`, because a cross-domain exception reference is a layer-boundary violation. Every throw uses a named domain subclass (`OrderNotFoundException : EntityNotFoundException`) with a domain-specific `ErrorCode`; generic shared codes (`CommonErrorCode`) and an `ENTITY_NOT_FOUND` code are forbidden.

The hierarchy lives in a shared module: `BusinessException : RuntimeException` (the base, carrying an `ErrorCode`) → `EntityNotFoundException` (resource missing) or `InvalidValueException` (bad input) → the domain subclass. Each module has its own `ErrorCode` enum implementing the shared `ErrorCode` interface, plus a `CommonErrorCode` for shared concepts raised by the shared global exception handler ([STY-57](code-style.md#20-errorcode-numbering)); each service adds a thin `@RestControllerAdvice` subclass of that handler. ErrorCode numbering: [STY-55](code-style.md#20-errorcode-numbering).

The default shape; a project may already have its own equivalent — use that:

```kotlin
interface ErrorCode { val type: String; val statusCode: Int; val message: String }

open class BusinessException(val errorCode: ErrorCode, override val message: String, cause: Throwable? = null) :
    RuntimeException(message, cause)
```

**SVC-15** — The failure decides the form:

| Failure | Form |
|---|---|
| Input from a caller (client, Command field, request) is missing or invalid | Named domain exception (SVC-14) |
| An internal invariant no caller input can reach (a loaded relation that must exist) | `requireNotNull(x) { "<context>" }` |
| Configuration or wiring validated while the context boots (a cookie generator's `init`, deriving a public key from configured key material) | `check`/`error` allowed — the failure stops startup, so no `ErrorCode` or HTTP status reaches a client |
| Anything else in a Service or Command | Forbidden: `require`, `check`, `checkNotNull`, `error`, throwing `IllegalArgumentException`/`IllegalStateException`/`UnsupportedOperationException`, and constructing `BusinessException`/`InvalidValueException` directly |

A utility class may `require` its programmer preconditions.

**SVC-16** — A 4xx is logged as one line without its stack trace: `logger.warn { … }`, never `logger.warn(e) { … }`, with the message built inside the lambda (`{ summaryOf(e, request) }`, not a pre-built `val`). A 5xx keeps the trace. A reactive gateway's global error handler follows the same split.

Example: [SVC-14 · SVC-15](examples/service.md#svc-14--svc-15--exception-declaration).

---

## 6. Cross-domain access

A *deployable* is one application that is built, deployed and run on its own (`app-service`, `auth-service`); a *domain* is one `<domain>` package inside a deployable (`user`, `group`, `board`).

**SVC-38** — The boundary decides the means of communication, and between deployables the caller's wait decides the transport:

| Boundary | The need | Means |
|---|---|---|
| Domain ↔ domain, same deployable | A state change that affects the other domain | In-process `*Event` (SVC-39) |
| Domain ↔ domain, same deployable | The other domain's answer | The other domain's Service (SVC-39) |
| Deployable ↔ deployable | The caller waits on the outcome — a read, or a command whose result the caller returns or whose failure must reach the caller | HTTP client `*Client` ([CTL-25](controller.md#11-feign-clients)) |
| Deployable ↔ deployable | The caller tells the other deployable to act and neither its response nor its own commit waits for it | `*Message` over the message broker ([STY-52](code-style.md#18-transport-dto-suffix)) |

Between deployables the test in one line: **would the caller's own result be wrong, or have to roll back, if the other side has not finished yet?** Yes → HTTP: a guard check, a lookup, a copy, move or delete whose result the end user receives, an upload that returns ids, an all-or-nothing sync. No → a broker message the other deployable consumes idempotently ([SVC-26](#8-writes-duplicates-and-idempotency)) and redelivers on failure ([SVC-37](#12-message-consumers)): best-effort cleanup, a computation whose result comes back later, a follow-up resource created after the caller's own commit. A state-changing HTTP call whose result the caller discards, or whose failure it swallows, is telling in HTTP clothes — it fails when the other side is down and leaves the two sides inconsistent, so send it as a message. A third-party system outside the organization (a payment gateway, a mail provider) is not a deployable of the system: call its API as it requires, under [TX-2](transactions.md#3-external-calls-and-compensation).

**SVC-39** — Between domains of one deployable, take the first row that fits:

| # | The need | Form |
|---|---|---|
| 1 | Several domains' data gathered into one output (a response, a Command) | The inbound adapter calls each domain's Service and composes the Results ([CTL-28](controller.md#13-thin-controller), [CTL-24](controller.md#10-non-http-inbound-adapters)); each Service reads only its own domain |
| 2 | A Service's own logic uses another domain's answer — a lookup, a precondition check, a generated id | Inject that domain's Service and call it (never its Repository, SVC-17) |
| 3 | A state change in one domain (create, update, delete, transition) affects another domain — its data, or a side effect such as a notification, an external call or a cache eviction — and the changing domain does not use the outcome | The changing domain publishes an `*Event`; the affected domain handles it in its own listener ([§11](#11-spring-events)). The publisher never injects the affected domain's Service for this |

The test in one line: **asking** another domain → inject; **telling** it → event; **decorating** an output → adapter. The caller's outcome decides which one a call is, not the return type. A call made *after* the Service changed its own state, whose result the Service discards, is telling (row 3). A call made *before* the Service's own writes, whose exception stops the Service — a precondition check, a one-time-use gate — is asking (row 2) even when it returns `Unit`; an event there would move the gate after the writes. An effect the request promised and that must stay out of the transaction, such as deleting stored files after commit, is the direct post-commit call of [TX-3](transactions.md#3-external-calls-and-compensation) option 3, not a row 3 violation. Following these rows keeps most bean cycles from forming ([SVC-20](#63-breaking-bean-cycles-without-lazy)).

```kotlin
// ✅ row 2 — creating a group needs the owner's answer: is the user active?
val owner = userService.getActiveEntity(command.ownerId)
// ✅ row 3 — the board domain reacts to the new group; GroupService never injects BoardService
applicationEventPublisher.publishEvent(GroupCreatedEvent(groupId = group.id, ownerId = owner.id, name = group.name))
// ❌ row 3 written as an injection — the return value is unused, so this is telling, not asking
boardService.createDefaultBoard(CreateDefaultBoardCommand(groupId = group.id))
```

Example: [SVC-38 – SVC-41](examples/service.md#svc-38--svc-39--svc-40--svc-41--cross-domain-communication).

| Dependency | Allowed |
|---|---|
| A Service → B Service | ✅ only to use B's answer (SVC-39 row 2) |
| A Service → B Repository | ❌ (SVC-17; exceptions in [§6.2](#62-repository-access-exceptions)) |
| A Service throws B's exception | ❌ ([SVC-14](#5-exceptions-and-failure-forms)) |
| A Service → B Entity via `B.getEntity()` | ⚠️ internal only ([SVC-2](#2-method-signatures)) |

**SVC-17** — A Service never injects another domain's Repository; it calls that domain's Service. The only classes that may inject other domains' repositories are listed in [§6.2](#62-repository-access-exceptions).

**SVC-18** — A qualified entity-returning variant exists for two things only: a different fetch graph (`getEntityWithItems`, `getEntityWithPayments`) or an encapsulated extra check (`getActiveEntity`). The method name says which; a KDoc does not explain the fetch graph or the check ([STY-16](code-style.md#5-comments-and-kdoc)).

Example: [SVC-2 · SVC-17](examples/service.md#svc-2--svc-17--cross-domain-entity-returning-method).

### 6.1 Fetch strategy

**SVC-19** — Choose the fetch strategy from the caller's access pattern:

| Caller access pattern | Strategy |
|---|---|
| Base fields only | Derived query (`findBy*`) |
| Related-entity fields, inside the transaction and outside a loop (`entity.relation?.field`) | Fetch join (Custom Repository QueryDSL) |
| Traversal outside the transaction boundary, or inside a loop, `forEach` or `groupBy` | **Always** a fetch join (avoids `LazyInitializationException` and N+1) |
| Only the related entity's FK | Load the full entity and extract the FK in the Service; a projection only on explicit instruction ([REP-7](repository.md#2-query-construction)) |

```kotlin
// ✅ needs related-field access → a dedicated fetch-join method
@Transactional(readOnly = true)
fun getEntityWithItems(orderId: UUID): Order =
    orderRepository.findWithItems(id = orderId) ?: throw OrderNotFoundException(orderId)
// ❌ plain getEntity, then lazy traversal outside the transaction → LazyInitializationException / N+1
orderService.getEntity(orderId).items.size
```

### 6.2 Repository-access exceptions

Only these kinds of class may inject other domains' repositories (SVC-17). Every other class follows SVC-17 unchanged.

| Class | Why |
|---|---|
| A full-reset service (data wipe) | A full data wipe crosses every table, so no domain Service can express it |
| A sample-data seeder gated by `@Profile("local")` (or `local`/`dev`/`test`) | Fills fixtures across domains; it never runs in the `prod` profile |
| A boot seeder that writes system defaults once at `ApplicationReadyEvent` | Runs once at startup; never called from a request |

### 6.3 Breaking bean cycles without `@Lazy`

**SVC-20** — Never use `@Lazy` to break a Spring bean cycle (`A→B→A`). Of a cycle's two edges one is natural (the owner validates or references its own data) and the other is unnatural — a lower layer referencing an upper one, a domain minting another domain's token or resource, or one domain bundling another's writes. Move the unnatural edge's responsibility to where it belongs, and one natural edge remains.

| Technique | When | Example |
|---|---|---|
| (1) Move to the side-effect handler | A domain transaction needs a cross-service token or resource → the listener that owns the call mints it after commit | A `MemberEventListener` issues its own internal token for the downstream call |
| (2) Compose in the inbound adapter | A read output is *decorated* with another domain's data → the adapter calls both Services (the default of [SVC-39](#6-cross-domain-access) row 1) | `GroupController` composes the owner through `UserService` |
| (3) Publish a domain event | One domain bundles another's *writes* → publish instead of calling (the default of [SVC-39](#6-cross-domain-access) row 3; listener kind by [SVC-40](#11-spring-events)) | `GroupService.createGroup` publishes `GroupCreatedEvent`; `BoardEventListener` creates the default board in the same transaction |
| (4) Check for a fake cycle | Check whether the back-reference exists at all — with one direction only there is no cycle, so delete the `@Lazy` | A `@Lazy` whose reverse path does not exist |

Do not extract the shared read contract into a small lookup `@Component` (the read-port escape); use (1)–(3). When `@Lazy` is truly unavoidable (a boundary whose split costs too much), its KDoc states why the cycle cannot be removed and under what condition it could.

Example: [SVC-20](examples/service.md#svc-20--breaking-a-bean-cycle-without-lazy).

---

## 7. Method order

**SVC-21** — Public methods follow CRUD order: Create (`create*`/`add*`/`save*`/`copy*`/`signUp`) → Read (`get*`/`list*`/`page*`/`find*`/`exists*`/`count*`) → Update (`update*`/`upsert*`/`move*`/`rename*`) → Delete (`delete*`/`remove*`) → state transitions and other actions (`complete`, `publish`, `cancel`, `verify*`, `check*`, `can*`, `signIn`, `signOut`, …), which are always the last group — the same rule as [CTL-4](controller.md#3-method-order). A Service spanning several sub-domains applies the order within each sub-domain group. No section banner comments ([STY-6](code-style.md#2-baseline)).

**SVC-22** — Private methods follow every public method, in this order: `check*` methods, then step methods in the order the public methods call them ([STY-21](code-style.md#8-method-shape)), then conversions (entity ↔ DTO). The `companion object` is always last in the file.

---

## 8. Writes, duplicates and idempotency

**SVC-23** — Persist a collection with one `saveAll`, never `save()` in a loop. `SimpleJpaRepository.saveAll` is itself a loop over `save`, so the rule is about intent and readability: one call says the collection is persisted as a batch. JDBC batching needs `hibernate.jdbc.batch_size`, `hibernate.order_inserts`/`order_updates` and non-`IDENTITY` ids; with those unset, `saveAll` also makes N round trips. An FK parent→child batch is two `saveAll` stages. A loop is correct only when each element needs its own transaction, compensation or external call. ❌ `items.forEach { repo.save(it) }` ✅ `repo.saveAll(items)`. Example: [SVC-23](examples/service.md#svc-23--two-stage-saveall).

**SVC-24** — An insert guarded by a DB UNIQUE constraint runs inside `translateUniqueViolation` (one shared helper), which turns a violation of the named constraint into the domain's 409 exception. The constraint name is a `companion object` constant of the entity (`OrderItem.UNIQUE_ORDER_PRODUCT`; naming per [REP-33](repository.md)), and the block flushes (`saveAndFlush`, `saveAllAndFlush`, `flush()`) so the violation surfaces inside it. A pre-check (`exists*`) may run first to answer the common case with a clean message, but it never replaces the translation: concurrent requests pass the pre-check together.

The default shape; a project may already have its own equivalent — use that:

```kotlin
inline fun <T> translateUniqueViolation(constraintName: String, conflict: () -> Exception, block: () -> T): T =
    try {
        block()
    } catch (e: DataIntegrityViolationException) {
        if ((e.cause as? ConstraintViolationException)?.constraintName.equals(other = constraintName, ignoreCase = true)) throw conflict()
        throw e
    }
```

```kotlin
val created = translateUniqueViolation(
    constraintName = OrderItem.UNIQUE_ORDER_PRODUCT,
    conflict = { OrderItemAlreadyAddedException(addedProducts.map { it.id }) },
) {
    orderItemRepository.saveAllAndFlush(addedProducts.map { OrderItem(order = order, product = it, createdBy = command.memberId) })
}
```

**SVC-25** — Re-creating a link or membership that already exists succeeds without change. Removing one that does not exist is a 404 `*NotFoundException`.

**SVC-26** — An inbound packet listener, `@TransactionalEventListener` or message-consumer handler that processes externally redeliverable messages is idempotent: dedupe on a natural key or a content hash (`(orderId, payloadHash)`), skip if it exists or upsert, and back it with a DB UNIQUE constraint so a concurrent redelivery loses too. No unconditional append-only `save`. Pure in-process single-shot events are exempt. ❌ `message.items.forEach { repo.save(it) }` ✅ `if (repo.existsBy…(key)) return; repo.saveAll(…)`

---

## 9. Enum layer separation

**SVC-27** — An enum has as many layers as the boundaries it crosses (§9.1), and the mappers (§9.2) are the only conversion points. Never merge the Entity inner enum into the Service enum, or the reverse — the two layers evolve independently even when their constants are identical. The Entity inner enum (`Order.Status`) never appears in a Command, Result, Request or Response ([SVC-7](#3-command-and-result)).

### 9.1 How many layers

| Shape | Layers | When |
|---|---|---|
| **4-Layer** | Packet · Message · Service · Entity | The enum crosses an external **wire-protocol (packet)** boundary, and therefore the internal message-broker one too |
| **3-Layer** | Message · Service · Entity | The enum crosses the **message broker** between services but never reaches a packet |
| **2-Layer** | Service · Entity | The enum stays inside one service (`OrderStatus`). A shared-module enum the wire already carries is the Service layer itself: commands, results and responses use it directly, and only the Entity enum and its mapper remain |

| Layer | Location | Purpose |
|---|---|---|
| Packet | shared module `packet/type/` | External wire format: `@JsonValue`, numeric codes. Only the protocol adapter module reads this layer |
| Message | shared module `message/type/` | Message-broker transport DTO field type (name-serialized) |
| Service | `{module}/.../enumerate/` | Commands, Results, business logic |
| Entity | Nested inside the `@Entity` class | JPA: `@Enumerated(EnumType.STRING)` |

Names may differ between layers (packet `CANCELLED`, service `CANCELED`).

### 9.2 Two mappers

**SVC-28** — Two mappers split at the packet boundary:

| Mapper | Converts | Owner |
|---|---|---|
| `{module}/.../{domain}/util/{Domain}EnumMapper.kt` | message ↔ service ↔ entity | The domain's module |
| `{protocol-adapter}/.../util/{Protocol}EnumMapper.kt` | packet ↔ message | The protocol adapter module |

Methods are named `to{Layer}{Type}()` — the target layer (`Entity`, `Service`, `Message`, and `Packet` on the protocol side) followed by the converted type's name: `toEntityOrderStatus`, `toServiceOrderStatus`, `toMessageOrderStatus`, `{Protocol}EnumMapper.toPacketOrderStatus`. A new enum domain registers both directions in its own `{Domain}EnumMapper`. Every mapping `when` is exhaustive with no `else` branch, so a constant added or removed on one side is a compile error rather than a silent runtime gap.

The split is why a packet-crossing enum has four layers rather than three: no single module sees both the packet and the entity.

Example: [SVC-27 · SVC-28](examples/service.md#svc-27--svc-28--enummapper).

### 9.3 Unknown external values

**SVC-29** — When an external system or the DB hands over a code the enum does not know, skip that item and log WARN (`Unknown <type> skipped: code=…`). Never store a guessed value and never fail the whole batch. An enum does not add an `UNKNOWN` constant for this.

---

## 10. Service vs Component

**SVC-30** — `@Service` marks a transactional domain use-case entry point. Every other bean or pure function takes the annotation and suffix of its role:

| Category | Annotation | Suffix | Test |
|---|---|---|---|
| Domain use case (transaction boundary) | `@Service` | `*Service` | Entry point for a transactional use case on a domain entity |
| Spring lifecycle and event glue | `@Component` | `*Listener`/`*Handler`/`*Scheduler`/`*Filter`/`*Interceptor`/`*Initializer`/`*Verifier`/`*Runner` | Receives a framework callback (event, packet, broker message, schedule, boot, `preHandle`). A message-broker subscriber is a `*Listener` too, never `*Consumer`. `*Runner` here means a bean driven by a callback; a wrapper that runs something on request (`TransactionRunner`) belongs to the row below |
| External system or library wrapper | `@Component` | The role's own noun: `*Publisher`, `*Broadcaster`, `*Notifier`, `*Store`, `*Lookup`, `*Recorder`, `*Registry`, `*Registrar`, `*Issuer`, `*Reader`, `*Runner`, `*Throttle`, `*Auditor`; `*Template`/`*Executor` only when dropping the suffix leaves no usable name (SVC-31) | Wraps a PostgreSQL feature, Redis, a message broker, an OS API, a thread pool or an external library, or fronts a remote read another service answers (`MemberReader`) |
| External-service HTTP/SSE client | `@Component` / `@FeignClient` | `*Client` | Outbound client calling another service's HTTP or SSE |
| Cross-cutting stateless collaborator | `@Component` | `*Resolver`/`*Strategy`/`*Mapper`/`*Helper`/`*Extractor`/`*Generator` | Stateless collaborator a Service injects and uses |
| Access judgment | `@Component` | `*Policy`/`*Guard` | Answers an access question and nothing else. Never `@Service`, even though the body is domain logic: it owns no transaction and mutates nothing |
| Framework SPI implementation | `@Component` / `@Bean` / `META-INF/services` | The SPI interface's own name | Implements a framework extension point (`Converter`, `ErrorDecoder`, `FunctionContributor`, `HandlerInterceptor`) — the interface dictates the suffix |
| Pure function (no Spring) | (none) | — | A top-level or extension function in a `util/` package, or a stateless `object` there when its functions belong together (`*EmailBuilder`) |

A Strategy, Resolver or Mapper that holds domain logic is still a collaborator a Service injects, so it keeps `@Component` and its role suffix. In a module with no transactions (no `@Transactional` and no JPA) the transaction-boundary test cannot discriminate: judge by role, and treat the bean a controller enters through as the use-case entry point. A pure media-library wrapper (ffmpeg, `ImageIO`) stays `@Component` however much domain vocabulary its method names carry.

**SVC-31** — Drop the suffix and read what is left (the bean-level case of [STY-50](code-style.md#16-filler-suffixes-and-dto-casing)). If the bare noun already names the bean, the suffix was filler: ❌ `OrderCacheTemplate` → ✅ `OrderCache`; likewise `InvoiceGenerator`, `ImageResizer`. Keep `*Template`/`*Executor` only when the bare noun would name **the mechanism instead of the component that drives it** (`AdvisoryLock` reads as the lock itself, not the bean that acquires it), would **collide with a stdlib type** (`Sequence`), or would **carry no meaning alone** (`AtomicRedis`).

Example: [SVC-30 · SVC-31](examples/service.md#svc-30--svc-31--service-vs-component).

---

## 11. Spring events

An in-process event carries a state change from one domain to the domains it affects ([SVC-39](#6-cross-domain-access) row 3). Event class names follow [STY-52](code-style.md#18-transport-dto-suffix) (`*Event` in-process, `*Message` over a broker).

**SVC-40** — Choose the listener by atomicity:

| The affected domain's work | Listener | Runs | When it fails |
|---|---|---|---|
| Must commit and roll back with the publisher | Synchronous `@EventListener` | At `publishEvent`, inside the publisher's transaction | The publisher rolls back too |
| May run once the publisher's write is durable | `@TransactionalEventListener(phase = AFTER_COMMIT, fallbackExecution = true)` | After the publisher commits | The publisher stays committed; only this effect is lost |

An `AFTER_COMMIT` listener is only for an effect the publisher can do without when it fails — one that can be retried or reconciled later (a notification, a cache eviction, a message publish). Its DB writes run in `transactionRunner.inNewTx { }`: a `REQUIRED` boundary opened there joins the committed transaction and never commits ([TX-7](transactions.md#3-external-calls-and-compensation)). It still holds the publisher's pooled connection, so only a short external call with a configured client timeout runs inline; a slow or unbounded one goes to a Spring-managed executor ([TX-2](transactions.md#3-external-calls-and-compensation)).

**SVC-41** — The publishing domain owns the event class in its `<domain>/event/` package, named as a fact that already happened ([STY-53](code-style.md#18-transport-dto-suffix): ✅ `GroupCreatedEvent` ❌ `CreateBoardEvent`). The affected domain owns the listener in its own `<domain>/event/` package: a `@Component` `*Listener` ([SVC-30](#10-service-vs-component)) that turns the event into a Command and delegates to its own domain's Service, with no business logic of its own — the same thin shape as [CTL-24](controller.md#10-non-http-inbound-adapters). The dependency points one way, from the listener's domain to the event class; the publisher never learns who listens.

**SVC-33** — An event carries the publisher's ids plus the data its listeners need — value fields, the event's own inner data classes and service-layer enums — so no listener calls the publisher's Service back for the same data. It never carries a JPA entity, an `@Embeddable`, an entity-inner enum or the authenticated principal object: pass `actorId` and the fields the listener needs ([SVC-7](#3-command-and-result) holds Commands to the same rule). This holds for a synchronous listener too.

```kotlin
// ✅ ids + the data listeners need, in the event's own inner data class
data class GroupDeletedEvent(val groupId: UUID, val actorId: UUID, val members: List<Member>) {
    data class Member(val userId: UUID, val role: GroupRole)
}
// ❌ the entity ties every listener to the group domain's structure
data class GroupDeletedEvent(val group: Group)
```

**SVC-34** — An `AFTER_COMMIT` or `BEFORE_COMMIT` `@TransactionalEventListener` sets `fallbackExecution = true`. Without it, an event published outside a transaction is silently dropped: the listener never runs and nothing is logged. An `AFTER_ROLLBACK` or `AFTER_COMPLETION` listener never sets it: for an event published outside a transaction Spring runs such a listener anyway (for `AFTER_ROLLBACK` it only logs a WARN, "fallback execution on AFTER_ROLLBACK phase"), so a compensating `AFTER_ROLLBACK` listener would undo an operation that succeeded.

**SVC-35** — A listener method is named `on{EventName}` (`onOrderCanceled` for `OrderCanceledEvent`), and the field holding the publisher is `applicationEventPublisher`.

---

## 12. Message consumers

A consumer bean is a `*Listener` ([SVC-30](#10-service-vs-component)) and its handler is idempotent ([SVC-26](#8-writes-duplicates-and-idempotency)).

**SVC-37** — A message whose handling fails is redelivered with a delay up to the consumer's maximum attempts, then published to its dead-letter destination and terminated. One shared helper does this for every consumer with a dead-letter destination: the listener passes its destination and log text, and a per-listener copy of the redelivery logic is duplication to fold into that helper. A consumer that must also undo work when the attempts run out passes its own on-exhausted callback to the same helper. A consumer with nothing to quarantine to discards the message after the last attempt (its backstop being, e.g., a periodic stale-work sweep). A periodic snapshot that the next message supersedes (a node status heartbeat) may be acked and dropped on failure instead.
