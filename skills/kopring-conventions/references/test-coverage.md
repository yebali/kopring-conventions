# Test Coverage Conventions

**Owns:** Which tests must exist and how to judge coverage and regression value. **Read when:** Choosing cases or reviewing a suite for omissions or duplicate verification.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| COV-1 | | Every endpoint covers each parameter variation; on a permission-gated endpoint a missing permission is 403, on a row-scoped endpoint an out-of-scope row is 404 | [§2](#2-controller-coverage) |
| COV-2 | | Typed parameter binding is exercised through real HTTP; 401 only for endpoints taking the principal or guarded by the authorization interceptor; a `Unit` endpoint asserts status only | [§2](#2-controller-coverage) |
| COV-3 | | Every public Service method has a success test asserting a business effect (a pure-mapping create excepted) and one failure test per domain exception it throws | [§3](#3-service-coverage) |
| COV-4 | | Private branches are reached through public inputs; an unreachable branch is deleted | [§3](#3-service-coverage) |
| COV-5 | | The listed areas have standalone tests | [§4](#4-areas-that-must-have-a-standalone-test) |
| COV-6 | | No test that re-verifies JPA, Spring, Jackson or Kotlin behavior | [§5](#5-tests-not-to-write) |
| COV-7 | | The same logic is never tested twice in the same layer | [§6](#6-no-duplicate-verification) |
| COV-8 | | A new test must pass the three-question regression check (same-layer duplication only) | [§7](#7-regression-signal-check) |

How a test is written (support class, `@Nested`, helpers, assertions) is [testing.md](testing.md); this document decides which tests exist. Worked examples: [examples/testing.md](examples/testing.md).

## 2. Controller coverage

**COV-1** — Each endpoint tests every parameter variation below at least once, and every endpoint has at least one integration test.

| Variation | Verification |
|---|---|
| All required values filled | 200, or 201 for a creating POST, or 204 for a `Unit` PUT/DELETE ([CTL-18](controller.md#8-restful-api-design)); the response schema only when there is a body |
| Optional value omitted (Kotlin nullable or default) | 200 OK + default behavior |
| Required value missing (raw JSON body, [TST-20](testing.md#8-controller-tests)) | 400 + ErrorCode in `$.type` (`CommonErrorCode.MISSING_REQUIRED_FIELD`) |
| Format mismatch (UUID as an arbitrary string, negative page, …) | 400 + domain ErrorCode in `$.type` |
| *If the endpoint is permission-gated:* missing endpoint permission (principal without the permission) | 403 + `$.type` (with the authorization interceptor enabled, COV-2) |
| *If the endpoint is row-scoped:* row outside the caller's scope, or not permitted to the caller | 404 + `$.type` |
| Resource absent | 404 + `$.type` |

A paginated endpoint also verifies at least one sort key and at least one page-size boundary (0 / 1 / max).

**COV-2** — Three controller-only failure surfaces:

- **Typed parameter binding goes through real HTTP**, even when the repository layer already covers the filter SQL. The String-to-type conversion (`ZonedDateTime?`, `Long?`, enum, range objects, `1.0f - x`, `.toFloatArray()`) and the `toCommand` wiring fail only at the controller, and repository tests pass typed objects directly. A fixture that cannot distinguish the filtered-in row from the filtered-out row does not count as coverage: send a discriminating dataset and assert that only the in-filter rows survive.
- **401 needs the principal parameter or the authorization interceptor.** The authenticated principal is a controller method parameter (`authUser: AuthUser`) whose `HandlerMethodArgumentResolver` rejects a request without credentials. The authorization interceptor is enabled in the shared test support configuration for every test; no class turns it on or off ([TST-33](testing.md#2-test-infrastructure)). A MockMvc request without credentials therefore yields 401 when the controller method declares the principal parameter or the interceptor guards the endpoint; an endpoint with neither returns 200 without credentials, so no "missing credentials → 401" test is written for it. Confirm the method signature takes the principal, or the interceptor guards the endpoint, before adding the 401 row. An endpoint that should be authenticated but has neither is a production finding to report, not a test to force green.
- **A `Unit` endpoint asserts status only.** A `PUT`/`DELETE`/command endpoint that returns `Unit` has an empty body; its HTTP contract is the status plus request deserialization, so it never asserts `jsonPath("$.field")`. The state effect belongs to the Service test. Both layers test the same logic here by design (COV-7).

## 3. Service coverage

**COV-3** — Every `public fun` of a Service class has at least one success-path test and one failure-path test per domain exception it throws:

- every public method a Controller calls has its own `@Nested` group;
- each group covers success and each throw scenario, one per domain ErrorCode;
- every ErrorCode a private `check*` method throws is reachable through some combination of public-method inputs.

A success test asserts a business effect: a state transition, a side effect, a derived value or a persisted relation. A pure-mapping create, whose only effect is storing the Command's fields, has none; its controller test (COV-1) covers it, so it is exempt from the Service success test (COV-6). Its failure tests still apply.

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
| `Command.init {}` structural validation | Service test or Command unit test | The domain's invalid-value exception on empty list, negative value, format violation |
| Domain enum mapping (`*EnumMapper`) | Unit test | Bidirectional mapping for every enum value through `@EnumSource`, not a hand-picked subset. Every `*EnumMapper` has its own test file named after the mapper it tests; verify that the file targets that mapper (an `OrderEnumMapperTest` that asserts `PaymentEnumMapper` is a silent zero-coverage hole). Cover name-mismatch arms explicitly (`CANCELED → CANCELLED`): a one-line typo breaks exactly these |
| Transactional side-effect ordering (`@TransactionalEventListener(phase = AFTER_COMMIT)`) | Service or integration test | Both cases: (1) committed transaction → effect published, (2) rolled-back transaction → effect not published. A commit-only test stays green even when `phase` is wrong; only the rollback test pins AFTER_COMMIT. Also cover the `REQUIRES_NEW` path (effect survives the outer rollback) when the listener uses one |
| Handler idempotency (a message-broker listener or `@TransactionalEventListener` on redeliverable messages, [SVC-26](service.md#8-writes-duplicates-and-idempotency)) | Service or integration test | The same message processed twice leaves the state identical to once (no duplicate rows); the dedup key or UNIQUE constraint is enforced |
| Entity state-change methods (`assign()`, status transitions, `delete()`, `reset*()`) | Service or entity test | Success post-state, each rejection (named exception), and the [STY-34](code-style.md#12-logging) change-log line with the changed fields at their current values, captured through `captureLogs` ([TST-18](testing.md#7-helpers)). For a method STY-34 exempts (progress advance without a status transition) assert that the log is absent. Reach these methods through public calls, never by setting `var`s (COV-6) |

## 5. Tests not to write

**COV-6** — No test re-verifies behavior that `JpaRepository`, JPA, Spring, Jackson or Kotlin code generation already guarantees; its regression signal is zero.

| Anti-pattern | Reason |
|---|---|
| `repo.save(x); assertThat(repo.findById(x.id)).isPresent` | Re-verifies the `JpaRepository` contract |
| `entity.field = newValue; repo.save(entity); assertThat(repo.findById...field).isEqualTo(newValue)` | Re-verifies JPA dirty checking |
| `repo.deleteById(x.id); assertThat(repo.findById(x.id)).isEmpty` | Re-verifies `JpaRepository` delete |
| Asserting only a 1:1 field match right after `Service.create()` | When the Service has no business logic beyond Command → Entity mapping, the Controller's response verification (COV-1) is sufficient, and COV-3 exempts that create from a Service success test |
| Jackson deserialization or Spring DI behavior itself | Re-verifies framework behavior |
| `data class` generated `equals`/`hashCode`/`copy`/`toString` | Re-verifies Kotlin code generation. Exception: test `equals` only when an `Array`/`FloatArray` field forces a manual override (arrays compare by identity); two tests suffice (same content equal, different content not equal) |
| Spring singleton bean identity or `associateBy` map stability (a resolver "returns the same instance") | Re-verifies the container, not project logic |
| Setting entity `var`s and reading them back (`entity.x = v; assertThat(entity.x) == v`) | Re-verifies the language. Test the entity's named state-change method instead (COV-5) |

## 6. No duplicate verification

**COV-7** — The same logic is never tested twice in the same layer. Different layers may test the same logic; COV-2 requires it for parameter binding.

| Allowed | Not allowed |
|---|---|
| The same logic tested at different layers (Controller, Service, Repository) | Two test groups in the same class with identical assertions |
| Similar structure across different domains (`OrderServiceTest` vs `PaymentServiceTest`) | A "method-axis" and a "role-axis" test for the same permission matrix |
| Several input values in one parameterized test ([TST-32](testing.md#12-parameterization)) | A separate test per input value when the code path is identical |

Detection: when two `@Nested` groups produce the same pass/fail matrix (same methods × same permission levels), one of them is redundant.

## 7. Regression signal check

**COV-8** — Write a new test only when all three questions answer yes:

1. If this test fails, is production behavior broken?
2. Is this behavior not already verified by another test in the same layer?
3. Does this test avoid re-verifying framework behavior (`JpaRepository`, Spring DI, Jackson)?

When any answer is no, strengthen an existing test or write none.
