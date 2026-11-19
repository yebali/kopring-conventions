# Test Coverage Conventions

**Owns:** Which tests must exist and how to judge coverage and regression value. **Read when:** Choosing cases or reviewing a suite for omissions or duplicate verification.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| COV-1 | | Every endpoint covers each parameter variation against a mocked Service, a missing primitive field included, and each structural failure once per kind; a missing permission is 403, and each exception the Service can throw maps to its status; a creating POST, a versioned GET and each PUT form add their header and status cases | [§2](#2-controller-coverage) |
| COV-2 | | Typed parameter binding is asserted on the Command the mocked Service receives; 401 only for endpoints taking the principal or guarded by the authorization interceptor; a `Unit` endpoint asserts status and headers, never a body field | [§2](#2-controller-coverage) |
| COV-3 | | Every public Service method has a success test asserting its effect and one failure test per domain exception it throws; a row-scoped method has an out-of-scope case; a PUT covers a stale version and a repeated request | [§3](#3-service-coverage) |
| COV-4 | | Private branches are reached through public inputs; an unreachable branch is deleted | [§3](#3-service-coverage) |
| COV-5 | | The listed areas have standalone tests | [§4](#4-areas-that-must-have-a-standalone-test) |
| COV-6 | | No test that re-verifies JPA, Spring, Jackson or Kotlin behavior | [§5](#5-tests-not-to-write) |
| COV-7 | | The same logic is never tested twice in the same layer | [§6](#6-no-duplicate-verification) |
| COV-8 | | A new test must pass the three-question regression check (same-layer duplication only) | [§7](#7-regression-signal-check) |
| COV-9 | | Every Feign client has an adapter test against a stub HTTP server covering its requests and its `ErrorDecoder` | [§4](#4-areas-that-must-have-a-standalone-test) |
| COV-10 | | Each module with migrations has one guard test that runs Flyway on a fresh database and validates the entity mapping against it | [§4](#4-areas-that-must-have-a-standalone-test) |

How a test is written (support class, `@Nested`, helpers, assertions) is [testing.md](testing.md); this document decides which tests exist. Worked examples: [examples/testing.md](examples/testing.md).

## 2. Controller coverage

**COV-1** — Each endpoint has a controller test ([TST-19](testing.md#8-controller-tests)) for every variation below. The Service is a mock, so each case checks the response and the Command the Service received.

| Variation | Verification |
|---|---|
| All required values filled | The success status of the endpoint's shape ([CTL-18](controller.md#8-restful-api-design)); the response built from the stubbed Result; the Command carries every value |
| Optional value omitted (Kotlin nullable or default) | The success status + the Command carries `null` or the default; in a PUT body an omitted nullable field reaches the Command as `null` |
| Required value missing (raw JSON body, [TST-20](testing.md#8-controller-tests)) | 400 + ErrorCode in `$.type` (`CommonErrorCode.MISSING_REQUIRED_FIELD`); the Service is not called |
| Format mismatch or a failed structural check — one representative input per failure kind (a UUID as an arbitrary string, an over-length value) | 400 + `$.type` (`CommonErrorCode.INVALID_PARAMETER`, [SVC-15](service.md#5-exceptions-and-failure-forms)); the Service is not called; the input matrix is COV-5's |
| *If the endpoint is permission-gated:* missing endpoint permission (principal without the permission) | 403 + `$.type` (with the authorization interceptor in the slice, COV-2) |
| A domain exception the Service can throw (stubbed) — not found, out of scope, conflict | Its status + `$.type`, one case per exception type the endpoint's Service method throws |

An endpoint whose shape fixes a header or a PUT form adds these cases ([CTL-18, CTL-19](controller.md#8-restful-api-design), [TX-16](transactions.md#4-lock-selection)):

| Endpoint | Cases |
|---|---|
| Creating `POST` | 201 and the exact `Location` value |
| Single `GET` of a `@Version` entity | `ETag` carries the version |
| `PUT` form ① or ② on a `@Version` entity | missing `If-Match` → 428, the Service not called; stale (stubbed modified exception) → 412; matching → 204, the version in the Command, no `ETag` on the response |
| `PUT` form ③ | the current state again → 204; a forbidden transition (stubbed) → 409 |
| `PUT` form ④ | 201 and 204 from both stubbed `created` outcomes |

Whether a row is outside the caller's scope is the Service's decision ([SVC-44](service.md#4-validation)) and is tested there (COV-3); the controller test only maps the exception to its 404.

When the body has a non-null primitive field (`Int`, `Long`, `Boolean`, `Double`), one missing-field case omits that field: whether a missing primitive is rejected or bound to `0`/`false` depends on the Jackson version and its `FAIL_ON_NULL_FOR_PRIMITIVES` setting, and the Kotlin type does not show which (Jackson 3 under Spring Boot 4's defaults rejects it with a 400; the case keeps it that way across upgrades). Bound to `0`, a missing `quantity` passes as a real zero.

A paginated endpoint also verifies that a sort key and the page size reach the Command's `Pageable`, and at least one page-size boundary (0 / 1 / max — the cap of [CTL-34](controller.md#9-paging)).

**COV-2** — Three controller-only failure surfaces:

- **Typed parameter binding is asserted on the Command.** The String-to-type conversion (`Instant?`, `Long?`, enum, range objects, `1.0f - x`, `.toFloatArray()`) and the `toCommand` wiring fail only at the controller: send the raw values over HTTP and match the typed values on the Command the mocked Service receives. Whether the filter then selects the right rows is the repository test's proposition (COV-5), not this one's.
- **401 needs the principal parameter or the authorization interceptor.** The authenticated principal is a controller method parameter (`authUser: AuthUser`) whose `HandlerMethodArgumentResolver` rejects a request without credentials. The resolver and the authorization interceptor are part of the web slice's configuration in `WebMvcTestSupport` for every test; no class turns them on or off ([TST-33](testing.md#2-test-infrastructure)). A MockMvc request without credentials therefore yields 401 when the controller method declares the principal parameter or the interceptor guards the endpoint; an endpoint with neither returns 200 without credentials, so no "missing credentials → 401" test is written for it. Confirm the method signature takes the principal, or the interceptor guards the endpoint, before adding the 401 row. An endpoint that should be authenticated but has neither is a production finding to report, not a test to force green.
- **A `Unit` endpoint asserts no body.** A `PUT`/`DELETE`/command endpoint that returns `Unit` has an empty body; its HTTP contract is the status, the headers CTL-18 fixes (no `ETag` on a PUT) and request deserialization, so it never asserts `jsonPath("$.field")`. The state effect belongs to the Service test.

## 3. Service coverage

**COV-3** — Every `public fun` of a Service class has at least one success-path test and one failure-path test per domain exception it throws:

- every public method a Controller calls has its own `@Nested` group;
- each group covers success and each throw scenario, one per domain ErrorCode;
- every ErrorCode a private `check*` method throws is reachable through some combination of public-method inputs;
- a row-scoped method has a case with a row outside the caller's scope, which raises the domain's not-found exception ([SVC-44](service.md#4-validation)).

A success test asserts a business effect — a state transition, a side effect, a derived value or a persisted relation — re-read through the repository ([TST-23](testing.md#9-assertions)). For a pure-mapping create, whose only effect is storing the Command's fields, the effect is the stored row: one test that re-reads it, without a variation per field (COV-6). The controller test cannot stand in for it, because its Service is a mock.

A PUT's Service method also covers: a version that differs from the entity's throws the domain's modified exception ([TX-16](transactions.md#4-lock-selection)); the same PUT applied twice changes the state once and publishes one event ([CTL-19](controller.md#8-restful-api-design)); a form-④ UPSERT creates on the first call and replaces on the second for one key.

Internal Service-to-Service methods such as bare `getEntity()` / `listEntitiesBy…()` may be covered indirectly by the calling domain's test when a standalone test would verify the same branches.

**COV-4** — Private methods are never called directly: reflection, `@VisibleForTesting` and package-private exposure are all prohibited, and production visibility never changes for a test. A private branch is reached by combining public-method inputs (`Command` fields, id existence, permission level, state enum) along the execution path. A private branch unreachable from the public surface is dead code; delete it instead of testing it.

[Example](examples/testing.md#cov-4--private-method-via-public-input).

## 4. Areas that must have a standalone test

**COV-5** — Every domain's critical business logic has dedicated tests:

| Area | Required coverage |
|---|---|
| CRUD operations | Create, read (single and page), update, delete |
| Permission checks (if the domain is permission-gated) | Permission held / not held, and row inside / outside the caller's scope, for each operation |
| State transitions | Status changes (Order: PENDING → PAID → SHIPPED) |
| Edge cases | Soft-delete re-access, empty results, boundary values |
| Cross-domain operations | Link and unlink, with the cross-domain permission validation where the domains are gated |
| Service public methods | COV-3 |

The following areas can fail silently on regression, so each has a standalone test:

| Area | Test location | Test points |
|---|---|---|
| QueryDSL custom repository (`Custom*RepositoryImpl`) | Repository test | One case per nullable-field branch of the Query object and the `*ByQuery` methods ([REP-9](repository.md#31-multi-condition-reads)) |
| *If the project uses PostgreSQL JSONB:* the shared JSONB query util | Repository test | Text extraction (JSONB field, nested keys), text sort (no numeric cast), sort direction, null handling |
| `Command.init {}` structural validation | The Command's plain test ([TST-10](testing.md#44-plain-unit-tests)), never a Spring-backed test | `InvalidValueException` on empty list, negative value, format violation, over-length value ([SVC-45](service.md#4-validation)), every check and boundary as a parameterized row |
| Domain enum mapping (`*EnumMapper`) | Unit test | Bidirectional mapping for every enum value through `@EnumSource`, not a hand-picked subset. Every `*EnumMapper` has its own test file named after the mapper it tests; verify that the file targets that mapper (an `OrderEnumMapperTest` that asserts `PaymentEnumMapper` is a silent zero-coverage hole). Cover name-mismatch arms explicitly (`CANCELED → CANCELLED`): a one-line typo breaks exactly these |
| Transactional side-effect ordering (`@TransactionalEventListener(phase = AFTER_COMMIT)`) | Service or integration test | Both cases: (1) committed transaction → effect published, (2) rolled-back transaction → effect not published. A commit-only test stays green even when `phase` is wrong; only the rollback test pins AFTER_COMMIT. Also cover the `REQUIRES_NEW` path (effect survives the outer rollback) when the listener uses one |
| Handler idempotency (a message-broker listener or `@TransactionalEventListener` on redeliverable messages, [SVC-26](service.md#8-writes-duplicates-and-idempotency)) | Service or integration test | The same message processed twice leaves the state identical to once (no duplicate rows); the dedup key or UNIQUE constraint is enforced |
| Facade flows ([TX-3](transactions.md#3-external-calls-and-compensation)) | Facade test in `SpringBootTestSupport`, the outbound bean mocked | Success; a definite failure of the outbound call → the compensation ran and the first step's rows are gone; an unknown outcome (a timeout) → the record stays pending ([TX-4](transactions.md#3-external-calls-and-compensation)) |
| Soft-delete filter ([REP-27](repository.md#8-soft-delete)) | Repository test, once per module | A query leaves out a deleted row; `findById` still returns it; the same query inside `includingDeleted { }` returns it |
| Entity state-change methods (`assign()`, status transitions, `delete()`, `reset*()`) | Service or entity test | Success post-state, each rejection (named exception), and the [STY-34](code-style.md#12-logging) change-log line with the changed fields at their current values, captured through `captureLogs` ([TST-18](testing.md#7-helpers)). For a method STY-34 exempts (progress advance without a status transition) assert that the log is absent. Reach these methods through public calls, never by setting `var`s (COV-6) |

**COV-9** — Service and Facade tests replace every Feign client with a `@MockkBean` (TST-3), so a client's own behavior — the request it builds (path, query, headers, body) and its `ErrorDecoder` (CTL-26), which turns a remote status into a domain exception — runs in no test. Each client gets one adapter test against a stub HTTP server (WireMock or the project's equivalent): one case per method asserting the recorded request, and one per status the `ErrorDecoder` maps, asserting the exception. The test builds the client outside the Spring context with the same contract, codec and `ErrorDecoder` (`Feign.builder()…target(OrderClient::class.java, stubUrl)`), as a plain unit test (TST-10), because the shared context holds the client as a mock.

**COV-10** — Tests build their schema from the entities (`ddl-auto: create-drop`), so a migration that does not match the mapping first fails when a deployed service boots, and a constraint that exists only in the migrations (REP-28's partial unique index) exists in no test. Each module with migrations has one guard test that starts its own PostgreSQL container (from the image constant of the module's `PostgresTestcontainersConfiguration`, TST-2), runs Flyway, and boots the persistence layer with `ddl-auto=validate` against it — the one context TST-33 lets fork. It also asserts the migration-only constraints: a duplicate active value is rejected, a soft-deleted one is not.

## 5. Tests not to write

**COV-6** — No test re-verifies behavior that `JpaRepository`, JPA, Spring, Jackson or Kotlin code generation already guarantees; its regression signal is zero.

| Anti-pattern | Reason |
|---|---|
| `repo.save(x); assertThat(repo.findById(x.id)).isPresent` | Re-verifies the `JpaRepository` contract |
| `entity.field = newValue; repo.save(entity); assertThat(repo.findById...field).isEqualTo(newValue)` | Re-verifies JPA dirty checking |
| `repo.deleteById(x.id); assertThat(repo.findById(x.id)).isEmpty` | Re-verifies `JpaRepository` delete |
| A variation per field right after `Service.create()` | When the Service has no business logic beyond Command → Entity mapping, one success test that re-reads the stored row is the whole proposition (COV-3); further cases re-verify a mapping the compiler already checks |
| Jackson deserialization or Spring DI behavior itself | Re-verifies framework behavior |
| `data class` generated `equals`/`hashCode`/`copy`/`toString` | Re-verifies Kotlin code generation. Exception: test `equals` only when an `Array`/`FloatArray` field forces a manual override (arrays compare by identity); two tests suffice (same content equal, different content not equal) |
| Spring singleton bean identity or `associateBy` map stability (a resolver "returns the same instance") | Re-verifies the container, not project logic |
| Setting entity `var`s and reading them back (`entity.x = v; assertThat(entity.x) == v`) | Re-verifies the language. Test the entity's named state-change method instead (COV-5) |

## 6. No duplicate verification

**COV-7** — The same logic is never tested twice in the same layer. Different layers test different propositions about one feature: the controller test that a filter reaches the Command (COV-2), the repository test that the filter selects the right rows.

| Allowed | Not allowed |
|---|---|
| The same logic tested at different layers (Controller, Service, Repository) | Two test groups in the same class with identical assertions |
| Similar structure across different domains (`OrderServiceTest` vs `PaymentServiceTest`) | A "method-axis" and a "role-axis" test for the same permission matrix |
| Several input values in one parameterized test ([TST-32](testing.md#12-parameterization)) | A separate test per input value when the code path is identical |
| Separate tests when success and failure leave different side effects or need a different setup | Two tests with the same setup and the same call that assert different parts of its outcome — one test asserts both (shipping an order: its status, its shipped-at time and the stock it released) |

Detection: when two `@Nested` groups produce the same pass/fail matrix (same methods × same permission levels), one of them is redundant. A change that merges or moves tests states where each case is verified now ([testing §14](testing.md#14-changing-tests-for-speed)).

## 7. Regression signal check

**COV-8** — Write a new test only when all three questions answer yes:

1. If this test fails, is production behavior broken?
2. Is this behavior not already verified by another test in the same layer?
3. Does this test avoid re-verifying framework behavior (`JpaRepository`, Spring DI, Jackson)?

When any answer is no, strengthen an existing test or write none.
