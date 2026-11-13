# Testing Conventions

**Owns:** How a test is written: infrastructure, structure, layer responsibilities, isolation, test data, helpers, assertions, shared mocks, time and waiting, and parameterization. **Read when:** Writing or changing a test.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| TST-1 | | Tests carry no comments except `// given`/`// when`/`// then` and tool directives | [§3](#3-test-structure) |
| TST-2 | | A Spring-backed test extends one of the module's three support classes — `WebMvcTestSupport`, `DataJpaTestSupport`, `SpringBootTestSupport`; Testcontainers through `@ServiceConnection`, per module; no in-memory DB | [§2](#2-test-infrastructure) |
| TST-3 | | Dependencies two or more test classes use are declared in their support class; mock and spy beans are declared only there | [§2](#2-test-infrastructure) |
| TST-4 | | Context-backed modules run classes serially and scale by Gradle fork; only a pure unit test class without MockK mocks opts in to in-JVM concurrency | [§2](#2-test-infrastructure) |
| TST-5 | | Group with `@Nested` per feature; `@Nested` class names are English phrases in backticks | [§3](#3-test-structure) |
| TST-6 | | Test method names are English sentences in backticks; no `@DisplayName` | [§3](#3-test-structure) |
| TST-7 | | `@BeforeEach init()`, `@AfterEach cleanup()` | [§3](#3-test-structure) |
| TST-8 | | Controller tests run in the `@WebMvcTest` slice against mocked Services, Repository tests in the `@DataJpaTest` slice and roll back, Service tests in the full context with real transactions and never `@Transactional` | [§3](#3-test-structure) |
| TST-9 | | A test verifies only its layer's responsibility | [§4](#4-layer-responsibilities) |
| TST-10 | | Plain unit tests (no Spring) for stateless utilities and for delegation, error or business-logic paths whose SUT is built directly with local `mockk()` and needs no database, transaction or wired bean | [§4.4](#44-plain-unit-tests) |
| TST-11 | | A test leaves the database as it found it: a Repository test rolls back, a Service test's rows go with the support's wipe; no test class writes its own cleanup | [§5](#5-isolation) |
| TST-12 | | The wipe is one `@AfterEach` in `SpringBootTestSupport` that truncates every table but the seed tables; a test awaits its asynchronous work before it ends | [§5](#5-isolation) |
| TST-13 | | Fixtures come from support helpers; identities and unique values are never literals; no class-level test data | [§6](#6-test-data) |
| TST-14 | | A value behind a UNIQUE column is UUID-grade | [§6](#6-test-data) |
| TST-15 | | Helpers use `save*`/`build*`/`random*`/`mock*`/`ensure*` and do one thing; `save*` goes through the Service, a Repository test persists `build*` fixtures | [§7](#7-helpers) |
| TST-16 | | A helper duplicated across test files moves to the support class | [§7](#7-helpers) |
| TST-17 | | Concurrency tests use the module support's single `runConcurrently` | [§7](#7-helpers) |
| TST-18 | | Log capture uses the support helper, which restores the appender and level in `finally` | [§7](#7-helpers) |
| TST-19 | | Controller test names read `HTTP_METHOD endpoint result`; a controller test asserts the response and the Command the mocked Service received | [§8](#8-controller-tests) |
| TST-20 | | Valid bodies use the typed `*Request`; malformed or missing-field bodies are raw JSON strings | [§8](#8-controller-tests) |
| TST-21 | | AssertJ `assertThat`, never `assert`; enum references, not strings | [§9](#9-assertions) |
| TST-22 | | An exception assertion checks the type; it checks the ErrorCode only when one type carries several; controller tests check `$.type` | [§9](#9-assertions) |
| TST-23 | | Re-read a mutated entity from its repository before asserting; in a Repository test, `flush()` and `clear()` before re-reading and after bulk DML | [§9](#9-assertions) |
| TST-24 | | No assertion-free tests and no performance scripts in `src/test` | [§9](#9-assertions) |
| TST-25 | | `Instant` test values are truncated to micros on creation | [§9](#9-assertions) |
| TST-26 | | Verifications and captures on shared mocks are scoped to this test's data | [§10](#10-shared-mocks) |
| TST-27 | | Mocks are strict; only `relaxUnitFun = true` is allowed | [§10](#10-shared-mocks) |
| TST-28 | | Never spy one of this service's own domain beans to force a failure | [§10](#10-shared-mocks) |
| TST-29 | | No `Thread.sleep` to wait; Awaitility with the support's `AWAIT_TIMEOUT` | [§11](#11-time-waiting-and-files) |
| TST-30 | | Time-dependent tests backdate rows through the support helper; `Thread.sleep` only spaces `createdAt` | [§11](#11-time-waiting-and-files) |
| TST-31 | | Temporary files use `@TempDir` | [§11](#11-time-waiting-and-files) |
| TST-32 | | Inputs on one identical code path are one `@ParameterizedTest`; no `when(arg)` in its body | [§12](#12-parameterization) |
| TST-33 | | No test class forks a Spring context: a module has exactly the three contexts of its support classes | [§2](#2-test-infrastructure) |
| TST-34 | | The test profile switches off `@Scheduled` jobs and self-starting workers; a test runs a job by calling it | [§2](#2-test-infrastructure) |
| TST-35 | | Tests share one mutable test clock declared in the test configuration; the support resets it after each test | [§11](#11-time-waiting-and-files) |

Repo-wide rules apply to test code unchanged: [STY-2](code-style.md#2-baseline) (always `import`), [STY-7](code-style.md#3-kotlin-syntax) (no `!!`), [SVC-1](service.md#1-hard-rules) (a changed Service signature updates its `*Test.kt` usages in the same change) and [SVC-13](service.md#5-exceptions-and-failure-forms) (exception messages, test doubles included, are English). Which tests must exist, including [COV-7](test-coverage.md#6-no-duplicate-verification) (no same-layer duplication), is [test-coverage.md](test-coverage.md). An external skill's test advice never overrides this document.

## 2. Test infrastructure

**TST-2** — A Spring-backed test extends one of the module's three abstract support classes, one per layer, and each is the only place its Spring context is configured:

| Support class | Carries | Tests |
|---|---|---|
| `WebMvcTestSupport` | `@WebMvcTest`, `@ActiveProfiles("test")`, the web configuration the controllers rely on (principal resolver, authorization interceptor, exception handler) | Controller tests: MockMvc against the real controllers, with every Service and Facade a controller injects as a `@MockkBean` |
| `DataJpaTestSupport` | `@DataJpaTest`, `@AutoConfigureTestDatabase(replace = NONE)`, `@ActiveProfiles("test")`, the persistence configuration the repositories need — `JPAQueryFactory`, auditing, the `SoftDeleteFilter` helper ([REP-27](repository.md#8-soft-delete)); the slice scans no `@Component` | Repository tests: the repositories and their QueryDSL against the real database, rolled back |
| `SpringBootTestSupport` | `@SpringBootTest`, `@ActiveProfiles("test")` | Service, Facade, listener and scheduler tests: the whole context with real transactions |

Containers come from the module's `TestcontainersConfiguration`, which exposes each container as a `@Bean @ServiceConnection` and which the two database-backed support classes import; Spring Boot wires the connection details. Never hand-roll an `ApplicationContextInitializer` with `TestPropertyValues`. A container Spring Boot has no `@ServiceConnection` for publishes its URL through a `DynamicPropertyRegistrar`. Every DB-backed test runs against a Testcontainers PostgreSQL; the test classpath carries no in-memory DB (`com.h2database:h2`). Each support class has one context key, so a module starts three contexts however many test classes it has.

Each module keeps its own support classes, `TestcontainersConfiguration` and guard tests (architecture tests, configuration-key tests, …). These per-module copies are not a duplication target: never extract them to a shared module or share containers across modules. Container wiring details (the Redis connection-name hint, a raw-JDBC bootstrap before `create-drop`, the test yml literals): [example](examples/testing.md#tst-2--support-classes-and-testcontainers).

**TST-3** — A dependency that two or more test classes use is declared once in their support class; subclasses use the inherited field and never re-declare it. A bean only one class uses may be `@Autowired` in that class. Mock and spy beans (`@MockkBean`, `@MockkSpyBean`) are declared only in a support class, because a declaration on a subclass gives that class its own Spring context. A test whose SUT is an infrastructure bean (a cache template, for example) and needs the real bean instead of the shared `@MockkBean` builds its own local instance or mock. The shared declarations:

| Support class | Declares |
|---|---|
| `WebMvcTestSupport` | `@Autowired` `mockMvc`, `objectMapper`; `@MockkBean` every Service and Facade a controller injects |
| `DataJpaTestSupport` | `@Autowired` `entityManager` and the repositories tests share |
| `SpringBootTestSupport` | `@Autowired` `applicationEventPublisher`, `transactionTemplate`, `entityManager`, `stringRedisTemplate` (if Redis is used), the domain services and repositories tests share; `@MockkSpyBean` only the beans some test spies on (a file uploader, a lock template); `@MockkBean` external clients and outbound adapters — Feign clients (`paymentClient`), message publishers, mail senders |

[Example](examples/testing.md#tst-3--inherited-dependencies).

**TST-33** — No test class forks a Spring context. Spring caches a context per configuration key, and a module has exactly three, one per support class (TST-2). Each of these on a test class gives it a key of its own: `@DirtiesContext`; a class-level `@TestPropertySource`; an `@ActiveProfiles` that differs from the support's; a `@MockkBean` or `@MockkSpyBean` declared on a subclass instead of the support (TST-3); a different `@Import` or `@ContextConfiguration`; a slice annotation (`@WebMvcTest`, `@DataJpaTest`) written anywhere but its support class, or narrowed to one controller (`@WebMvcTest(OrderController::class)`). Each fork starts another context with its own containers and mock singletons, and JUnit runs every one of them in the same JVM. A property or bean a class would set this way is set once in its support class for every class (the authorization interceptor, [COV-2](test-coverage.md#2-controller-coverage)). The one exception is the migration guard test of [COV-10](test-coverage.md#4-areas-that-must-have-a-standalone-test), which needs its own database and Flyway run.

**TST-4** — Parallelism has two tiers. A module whose tests build a Spring context or touch a database runs classes serially inside a JVM (`junit-platform.properties` → `junit.jupiter.execution.parallel.mode.classes.default=same_thread`); its concurrency comes from Gradle forks (`maxParallelForks`, e.g. a `-PtestForks=N` property, default 1), each of which gets its own Testcontainers set, its own `@MockkBean` singletons and its own `fork-${org.gradle.test.worker}` storage paths. Inside such a module a class opts in to in-JVM concurrency with `@Execution(ExecutionMode.CONCURRENT)` only when it is a pure unit test ([TST-10](#44-plain-unit-tests)) without MockK mocks: no Spring context, no `mockk()`, `@MockkBean`, `mockkObject` or `mockkStatic`, no database, no shared filesystem path, and no static or `object` state, so it shares nothing with another class. A local `mockk()` is excluded too: a `clearAllMocks()` anywhere in the JVM (default `currentThreadOnly = false`) clears the stubs of every mock, a concurrently running class's local stubs included. The opt-in needs `junit.jupiter.execution.parallel.enabled=true` in `junit-platform.properties`; without it `@Execution` does nothing. A module in which every class is such a pure unit test (a shared library module) sets `mode.classes.default=concurrent`. A module with a database or a mock shared across classes never sets it: inside one JVM the rows, the mock singletons and the host filesystem are shared, and springmockk's clear of the shared mock singletons after each test method ([TST-26](#10-shared-mocks)) assumes no other test class runs concurrently in the same JVM.

**TST-34** — `@Scheduled` jobs and workers that start on their own (a polling consumer, a relay loop) do not run in the test context. The scheduling configuration carries `@ConditionalOnProperty("app.scheduling.enabled", matchIfMissing = true)` (or the worker's own switch) and the shared test profile sets it to `false`; a test exercises a job by calling its method. A job firing by itself mid-test changes rows other tests own (TST-11) and calls shared mocks at arbitrary times (TST-26). A test about the scheduling itself is a plain unit test of the trigger (TST-10).

## 3. Test structure

**TST-1** — Tests carry no line comments and no KDoc. A test's intent lives in its backtick method name (TST-6) and its `@Nested` class (TST-5). The only comments allowed are the `// given` / `// when` / `// then` markers and tool directives such as `// language=json`. The full comment policy is [STY-17](code-style.md#5-comments-and-kdoc).

✅ ``fun `rejects an order without items`()`` · ❌ `/** 주문 생성 거부 케이스 */` · ❌ `@DisplayName(...)`

**TST-5** — Every test class groups its cases with `@Nested`, one inner class per domain feature (order creation, order cancellation, order retrieval). Inner class names are English phrases in backticks (``inner class `order creation` ``), never PascalCase and never Korean.

**TST-6** — Test method names are English sentences in backticks that state the behaviour: `` `returns the Order when orderId exists` ``, `` `rejects an order without items` ``, `` `canceling an order sets its status to CANCELED` ``. Identifiers inside the sentence (class and field names, enum values, HTTP verbs) keep their spelling. ❌ `shouldReturnOrderWhenOrderIdExists` · `` `주문을 취소하면 상태가 CANCELED 가 된다` ``. `@DisplayName` is not used: the backtick name already is the display name, so `@DisplayName` duplicates it and the two drift. A parameterized case label uses `@ParameterizedTest(name = "...")` (TST-32).

[Example](examples/testing.md#tst-5--tst-6--nested-grouping-and-english-names).

**TST-7** — Setup is `@BeforeEach fun init()` and teardown is `@AfterEach fun cleanup()`; `init()` sets up stubs and shared preparation but assigns no fixture field (TST-13), and `cleanup()` never deletes rows — the wipe belongs to the support class (TST-12).

**TST-8** — Each layer's test runs in its own slice (TST-2), and the slice decides its transaction:

- **Controller test** — `WebMvcTestSupport`. No database and no transaction: the Service is a mock.
- **Repository test** — `DataJpaTestSupport`. `@DataJpaTest` makes every test transactional and rolls it back. That boundary is also what a custom repository's bulk DML needs (`queryFactory.delete(...).execute()` fails with `TransactionRequiredException` without one, and `Custom*RepositoryImpl` carries no `@Transactional`, [REP-4](repository.md#2-query-construction)), and it lets `@MapsId` parents persist. One persistence context spans the test, so a re-read or an assertion after bulk DML flushes and clears it first (TST-23).
- **Service test** — `SpringBootTestSupport`. Never `@Transactional`, at class or method level: it verifies the real transaction behaviour — what commits, what rolls back, what an `AFTER_COMMIT` listener does.

[Example](examples/testing.md#tst-8--transactional-placement).

## 4. Layer responsibilities

**TST-9** — Each layer has one test responsibility, and a test verifies only that layer's responsibility.

### 4.1 Controller test: HTTP contract

| Verification target | Description | Example |
|---|---|---|
| HTTP status codes | Correct status code returned | 200, 201, 204, 400, 401, 403, 404, 409 |
| Request binding | Body, path and query values arrive in the Command the mocked Service receives | `verify { orderService.pageOrders(match { it.status == OrderStatus.PAID }) }` |
| Request validation | `Command.init {}` runs inside `toCommand`, before the Service is called | Blank strings, out-of-range values → 400 with `$.type` |
| Error response | The exception a stubbed Service throws becomes its status and its ErrorCode in `$.type` (TST-22) | `every { orderService.getOrder(any()) } throws OrderNotFoundException(orderId)` → 404, `ORDER-1000` |
| Response structure | The JSON built from a stubbed Result | `jsonPath("$.id")`, `jsonPath("$.status")` |
| Authentication and authorization | Principal resolution; the endpoint permission where the endpoint has one | 401 without credentials; 403 without the endpoint permission (permission-gated endpoint) |

Not tested here: business logic, DB state, row scope — the Service is a mock. Which endpoint cases must exist: [test-coverage.md §2](test-coverage.md#2-controller-coverage). [Example](examples/testing.md#tst-19--controller-test-against-a-mocked-service).

### 4.2 Service test: business logic

| Verification target | Description |
|---|---|
| Business rules | State transitions, calculation logic |
| Exception conditions | `assertThatThrownBy` |
| Permission validation (if the domain is permission-gated) | Permission held / not held |
| Row scope (if the operation is row-scoped) | A row outside the caller's scope raises the domain's not-found exception ([SVC-44](service.md#4-validation)) |
| Edge cases | Boundary conditions, null handling |
| State changes | Entity state mutations |

Not tested here: HTTP status codes, SQL query correctness. Which Service tests must exist: [test-coverage.md §3](test-coverage.md#3-service-coverage).

### 4.3 Repository test: data access

| Verification target | Description |
|---|---|
| Complex queries | QueryDSL and JPQL correctness |
| Pagination | Paging logic |
| JSONB queries (if the project uses PostgreSQL JSONB) | PostgreSQL-specific operations |

Not tested here: simple CRUD that `JpaRepository` provides, business rules. [Example](examples/testing.md#tst-9--repository-query-and-ordering).

### 4.4 Plain unit tests

**TST-10** — A plain JUnit test without a Spring context is the form for three cases: stateless utilities; delegation or error paths; and business logic. In the last two the SUT is built directly through its constructor and its collaborators are local `mockk()` or in-memory fakes. A test that needs a database, a transaction boundary, a Spring proxy or event listener, a real Redis, message-broker or filesystem bean, MockMvc, or reflection over the whole context stays Spring-backed. A plain unit test extends no support class, groups with `@Nested` like any other test, loads test resources from the classpath through `javaClass.classLoader.getResource()`, and needs no database. A helper it shares with a support class lives once in the module's Spring-free fixtures file (`PlainTestFixtures`, TST-16). Examples: `OrderEnumMapperTest`, a file-format parser test.

[Example](examples/testing.md#tst-10--plain-unit-test).

## 5. Isolation

**TST-11** — A test leaves the database as it found it, so no test sees another's rows:

| Layer | How its rows go away |
|---|---|
| Controller test | It writes none — the Service is a mock |
| Repository test | The slice rolls the test's transaction back (TST-8) |
| Service test | The support's wipe after each test (TST-12) |

A test class never writes its own cleanup: no `deleteAll()`, no per-class `@AfterEach` delete, and no `@Transactional` on a Service test to get a rollback (TST-8). The wipe removes exactly the rows this test created, because nothing else is in that database: classes run serially inside a JVM and every Gradle fork has its own containers (TST-4). A test may therefore assert an exact count or an empty result over a whole table.

**TST-12** — The wipe lives once, in `SpringBootTestSupport`: an `@AfterEach` that runs `TRUNCATE … CASCADE` over every table except the seed tables the application fills at startup (the support lists them), and clears the Redis keys and storage paths the module's tests write. A test that starts asynchronous work — an `AFTER_COMMIT` listener on an executor, a published message — awaits its effect before it ends (TST-29); a write that lands after the wipe would appear in the next test.

The test schema comes from `ddl-auto: create-drop` (`application-test.yml`), not from migrations. Hibernate generates FKs with no `ON DELETE CASCADE`, so the wipe is `TRUNCATE … CASCADE` and never a sequence of ordered deletes; never reason about cleanup order from migration DDL.

## 6. Test data

**TST-13** — Test data comes from the Faker-based helpers of the module's support classes (random seed, customized through named parameters with defaults; prefixes in TST-15). Identities and unique values are never literals: emails, names that must be unique, UUIDs. Input values in `@CsvSource`/`@ValueSource` and enum references are ordinary literals and are fine. No class-level or global test data: `init()` (TST-7) may set up stubs and shared preparation, but never assigns a fixture field (`lateinit var order`); each test creates its own fixtures inside the test method.

[Example](examples/testing.md#tst-13--fixtures-in-local-scope).

**TST-14** — A value backing a UNIQUE column is UUID-grade, never a bounded random range or a Faker name: a collision between two fixtures of one test, or with a seeded row, fails intermittently and far from its cause. Check the entity's `@Table(uniqueConstraints = …)` and the migrations' unique indexes ([REP-14](repository.md#6-entity-mapping), [REP-28](repository.md#8-soft-delete)) before choosing a generator.

```kotlin
// ✅ collision-free by construction
protected fun randomEmail() = "u${UUID.randomUUID()}@example.com"
protected fun randomOrderNumber() = "ORD-${UUID.randomUUID()}"
// ❌ bounded range behind a UNIQUE column
protected fun randomEmail() = faker.internet().emailAddress()
```

## 7. Helpers

**TST-15** — A helper performs one task, named by its prefix:

| Prefix | Responsibility | Example |
|---|---|---|
| `save*()` | Save a single entity through the actual Service | `saveOrder()`, `saveMember()`, `saveProduct()` |
| `build*()` | Create a single object without saving | `buildOrderItem()`, `buildAuth()` |
| `random*()` | Generate random values | `randomEmail()`, `randomPath()` |
| `mock*()` | Configure mocks | `mockPaymentApproved()` |
| `ensure*()` | Verify or set preconditions | `ensureParentDirectoriesExist()` |

A `save*` helper calls the Service so the fixture follows the production path, which requires mocking external dependencies such as `paymentClient`; it exists in `SpringBootTestSupport` only. A `build*` helper calls the constructor and saves nothing. `DataJpaTestSupport` has no Service: a Repository test persists a `build*` fixture through `entityManager`. A Controller test stores nothing — a random id and a stubbed Result are enough. An immutable relationship entity may be created together with its owner (`buildOrderWithItem()`: an `OrderItem` cannot exist without its `Order`).

```kotlin
// ✅ compose single-responsibility helpers
val member = saveMember()
val order = saveOrder(member = member)
orderItemRepository.save(buildOrderItem(order))

// ❌ one helper bundles three tasks (member + order + item)
fun saveMemberWithOrdersAndItems(...) = ...

protected fun saveOrder(member: Member): Order = orderService.create(command)
protected fun buildOrderItem(order: Order): OrderItem = OrderItem(order = order, ...)
```

**TST-16** — A helper (`save*`/`build*`/`random*`) duplicated across test files of one module moves to its support class, or to a focused per-family abstract base (a `Payment*TestSupport`), so the production-equivalent `save*` path exists once. A helper two support classes or a plain test ([TST-10](#44-plain-unit-tests)) also need is defined once in the module's Spring-free fixtures file (`PlainTestFixtures`), and the support member is a one-line forward to it, never a copy. [STY-15](code-style.md#4-files-and-packages) applies to test code; the intentional DTO duplication of [SVC-6](service.md#3-command-and-result) covers production Command/Result and Request/Response DTOs only, never test scaffolding. Copies across modules are per-module by design (TST-2).

**TST-17** — A concurrency test calls the module support's single `runConcurrently(threads, block)`; a test class never defines its own private copy.

**TST-18** — A test that asserts log output captures it through the support helper `captureLogs(OrderService::class) { … }`, which attaches a `ListAppender` to the class's logger and, in `finally`, detaches it and restores the logger level. A test never attaches an appender by hand.

## 8. Controller tests

Controller tests send real HTTP requests through MockMvc in the `@WebMvcTest` slice; every Service and Facade is a `@MockkBean` of `WebMvcTestSupport` (TST-3). The caller's principal is attached by a support helper (`buildAuth(memberId)`, a `RequestPostProcessor` that adds the auth header or Spring Security's `user(...)`, whichever the project's principal resolver reads).

**TST-19** — A controller test method name reads `HTTP_METHOD endpoint result`, with the path's `/` written as `_` because `/` is illegal in a JVM method name (`` `POST api_v1_orders returns 201` ``, `` `GET api_v1_orders_orderId returns 403 without the permission` ``). The test stubs the Service call, performs the request, and asserts two things: the response — the status and the JSON built from the stubbed Result — and the Command the Service received (`verify { orderService.createOrder(match { it.memberId == memberId && it.items.size == 1 }) }`), which is where a binding or `toCommand` mistake shows.

[Example](examples/testing.md#tst-19--controller-test-against-a-mocked-service).

**TST-20** — A valid request body is the typed `*Request`, serialized with `objectMapper`, so a renamed field breaks the test at compile time. A malformed or missing-field body (the 400 cases of [COV-1](test-coverage.md#2-controller-coverage)) is a raw JSON string, because the typed `*Request` cannot express it. Never build a body from `mapOf("field" to …)`.

```kotlin
// ✅ valid body
.content(objectMapper.writeValueAsString(CreateOrderRequest(memo = null, items = listOf(CreateOrderRequest.Item(productId = product.id, quantity = 1)))))
// ✅ missing required field
// language=json
.content("""{"memo": null}""")
// ❌ string-key map
.content(objectMapper.writeValueAsString(mapOf("memo" to null)))
```

## 9. Assertions

**TST-21** — Assertions use AssertJ `assertThat(...)`, never Kotlin `assert(...)`. An AssertJ failure shows the actual and expected values where a bare `assert` reports only `Assertion failed`, and one assertion style keeps tests uniform. Use `assertThat(x).isTrue()`, `assertThatCode { … }.doesNotThrowAnyException()` and the like. Assertions compare against enum references, not strings.

**TST-22** — An exception assertion checks the exception type (`assertThatThrownBy { … }.isInstanceOf(OrderNotFoundException::class.java)`). It also checks the ErrorCode only when one exception type carries several codes: `.extracting("errorCode").isEqualTo(ErrorCode.ORDER_ITEM_QUANTITY_INVALID)`. A controller test checks `$.type`. Exception messages are not asserted.

[Example](examples/testing.md#tst-22--exception-and-errorcode-assertions).

**TST-23** — A mutated entity is re-read through its repository (`repository.findById(...)`, `findByIdOrNull`) before its new state is asserted, never read back from a `save*`/`build*` helper's return value: that asserts the in-memory object, not the persisted row, and passes on a broken `update()`. In a Repository test (TST-8) one persistence context spans the test, so `findById` returns the same managed instance without a SELECT, and a bulk DML (`queryFactory.delete(...).execute()`, `update(...).execute()`) leaves already-loaded entities stale: call `entityManager.flush()` and `entityManager.clear()` before re-reading, and after any bulk DML before asserting.

**TST-24** — Every test asserts. A test that only `println`s timings, or runs an early-return guard with no `assertThat`, has no regression signal ([COV-8](test-coverage.md#7-regression-signal-check)): give it a real assertion or delete it. A "must not throw" body uses `assertThatCode { … }.doesNotThrowAnyException()` when the behavior is worth pinning. Performance-measurement scripts do not belong in `src/test`, not even as `@Disabled`; run such measurements ad hoc, outside the regression suite.

**TST-25** — An `Instant` is truncated with `.truncatedTo(ChronoUnit.MICROS)` when test data is created: Java keeps nanoseconds (9 digits) where PostgreSQL keeps microseconds (6 digits), so an untruncated value never equals its re-read copy.

```kotlin
// ✅ truncate on create
val baseTime = Instant.now().minus(Duration.ofDays(1)).truncatedTo(ChronoUnit.MICROS)
val order = saveOrder(orderedAt = baseTime)
assertThat(orderRepository.findByIdOrNull(order.id)?.orderedAt).isEqualTo(baseTime)

// ❌ untruncated: the re-read value lacks baseTime's nanoseconds
val baseTime = Instant.now().minus(Duration.ofDays(1))
```

## 10. Shared mocks

Each support class's Spring context is cached and shared by every test class that extends it, so a `@MockkBean` or `@MockkSpyBean` is one singleton for the whole JVM.

**TST-26** — springmockk clears every `@MockkBean` and `@MockkSpyBean` after each test method (`clear = MockkClear.AFTER` by default, applied by its `MockkClearTestExecutionListener`), so a stub or a recorded call never outlives its test and a class restores nothing itself. What still leaks is an asynchronous call an earlier test started that lands after the clear: an AFTER_COMMIT listener on an executor, a scheduler, a broker listener. `verify(exactly = n)` counts that call too, so a verification on a shared mock matches only data this test created:

```kotlin
// ❌ also counts a ShipOrderMessage an earlier test's async listener published after the clear
verify(exactly = 1) { messagePublisher.publish(any<ShipOrderMessage>()) }
// ✅ counts only the message this test's order caused
verify(exactly = 1) { messagePublisher.publish(match<ShipOrderMessage> { it.orderId == order.id }) }
```

The same holds for `exactly = 0` ("no call for my data") and for captures: capture into a `mutableListOf<T>()` and pick `single { it.myKey == … }`, never a `slot<T>()` that holds whichever call came last. Never assign to a variable inside a `match {}` predicate; mockk may evaluate a matcher repeatedly and against non-matching calls. `match` and `capture` are members of the `verify {}` lambda receiver and need no import (`import io.mockk.match` does not exist).

**TST-27** — Mocks are strict: `mockk<T>()` and `@MockkBean` without relaxation. `relaxUnitFun = true` is the only relaxation allowed; `relaxed = true` is never used, on a local `mockk()` or a `@MockkBean`. A relaxed mock answers every unstubbed call with a default value, so a call the test did not expect passes silently.

**TST-28** — In the full context, never `@MockkSpyBean` one of this service's own domain beans to force a failure: that turns a domain service into JVM-global mutable state (`WebMvcTestSupport` mocks the Services by design, TST-8). Verifying pure delegation or an error path needs no Spring; build the SUT directly with a local `mockk()` (TST-10).

## 11. Time, waiting and files

**TST-29** — No `Thread.sleep` to wait for an asynchronous or AFTER_COMMIT effect. Wait with Awaitility, `await().atMost(AWAIT_TIMEOUT).untilAsserted { … }`, using the support's single `AWAIT_TIMEOUT` constant; a test class never declares its own timeout. A negative wait ("nothing arrives") holds the assertion for the support's settle constant: `await().during(SETTLE_DURATION).atMost(AWAIT_TIMEOUT).untilAsserted { … }`.

**TST-30** — Time-dependent behavior (retention, staleness, TTL) is tested by backdating rows through a `backdate*` helper of the module support, which rewrites the timestamp column with a native `UPDATE`; a test never waits for real time to pass. `Thread.sleep` is allowed only to space out distinct `createdAt` values for an ordering assertion, where there is no condition to await.

**TST-35** — The test configuration replaces the `Clock` bean ([STY-58](code-style.md#11-time-and-durations)) with one mutable test clock — a `Clock` whose instant a test sets — and the database-backed support classes hold it like every shared double (TST-3), so no class forks the context for its own clock (TST-33). A test that depends on what "now" is (an expiry check, a date boundary, a numbering year) sets or advances that clock; it neither waits nor builds a `Clock` of its own. The support's `@AfterEach` resets the clock to the system time: the bean is one singleton for every test class in the JVM, and a clock left moved changes the next test's "now" (the clock counterpart of TST-26). The clock decides the "now" the code reads; an old stored timestamp still comes from backdating the row (TST-30).

**TST-31** — Temporary files and directories come from JUnit `@TempDir`, never from `Files.createTempDirectory` with a manual delete or `deleteOnExit`.

## 12. Parameterization

**TST-32** — Several cases that differ only by input value on an identical code path are one `@ParameterizedTest`; separate methods there duplicate one verification ([COV-7](test-coverage.md#6-no-duplicate-verification)).

| Shape | Use |
|---|---|
| Every value of an enum (mapper round-trip, per-type behavior) | `@EnumSource` (covers new enum values automatically); exclude special-cased values with `mode = EXCLUDE` |
| Boundary scalars (quantity 0/1/max, page size 0/1/max) | `@ValueSource` |
| (input → expected ErrorCode) tables, one per endpoint and failure kind: blank-field 400, UUID-format 400, missing-field 400 | `@CsvSource` (literals) or `@MethodSource` (objects or closures) |
| Type-inference and mapping matrices (cast type, error decoder) | `@CsvSource` |

One parameterized table covers one code path: one endpoint and one failure kind. Cases stay explicit, not parameterized, when each has a genuinely different setup or asserts a different invariant; a parameterized body that needs `when(arg)` branches defeats the purpose. Readable case labels come from the `@ParameterizedTest(name = "...")` template, not `@DisplayName`.

`@MethodSource` needs a reachable source. Inside a `@Nested` class either (a) annotate that nested class `@TestInstance(TestInstance.Lifecycle.PER_CLASS)` and make the source a member `fun` returning `Stream`/`List`/`Array<Arguments>`, or (b) put the source in a top-level `companion object` with `@JvmStatic` and reference it by fully qualified name (`@MethodSource("com.example.order.OrderControllerTest#cases")`); that name is a JUnit method reference inside an annotation string, so [STY-2](code-style.md#2-baseline) does not apply to it. `@EnumSource`, `@ValueSource` and `@CsvSource` need none of this; prefer them.

## 13. Debugging

- JSONB queries: enable `org.hibernate.SQL: DEBUG` and `org.hibernate.type.descriptor.sql: TRACE`.
- `LazyInitializationException` in a Service test: make the Service fetch-join what the test reads ([SVC-19](service.md#61-fetch-strategy)). A Service test never uses `@Transactional` (TST-8).
