# Code Style Conventions

**Owns:** Cross-cutting Kotlin rules for every layer: baseline style, syntax, files and packages, comments, single-use intermediates, method shape, plain control flow, time, logging, failure handling, threads, files and streams, DTO naming, transport DTO suffixes, module and package layout, and ErrorCode numbering. **Read when:** Writing or reviewing any Kotlin file.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| STY-1 | ⚠ | Log through the project's single logger idiom (default: the inherited `logger` of a `Logger` base class); never call `LoggerFactory` / `KotlinLogging.logger` per class | [§2](#2-baseline) |
| STY-2 | | Always `import`; never inline a fully qualified name | [§2](#2-baseline) |
| STY-3 | | Expression body for simple functions | [§2](#2-baseline) |
| STY-4 | | Constructor injection only | [§2](#2-baseline) |
| STY-5 | | Primary keys are `UUID` except an explicitly listed generated-`Long`, composite or `String` natural key | [§2](#2-baseline) |
| STY-6 | | No section banner comments such as `// === Create ===` | [§2](#2-baseline) |
| STY-7 | | No `!!`; use `requireNotNull` where [SERVICE §5](service.md#5-exceptions-and-failure-forms) allows it, `lateinit`/`by lazy` for platform-guaranteed values | [§3](#3-kotlin-syntax) |
| STY-8 | | No `@Suppress("UNCHECKED_CAST")`; express the cast type-safely | [§3](#3-kotlin-syntax) |
| STY-9 | | A single-expression trailing lambda stays on one line (message lambdas always, others up to 120 characters) | [§3](#3-kotlin-syntax) |
| STY-10 | | One blank line before the final `return` of a block body | [§3](#3-kotlin-syntax) |
| STY-11 | | Named arguments for calls with 2+ arguments, except the listed shapes | [§3](#3-kotlin-syntax) |
| STY-12 | | One top-level type per file (five carve-outs); Command/Result and Request/Response files at their directory root | [§4](#4-files-and-packages) |
| STY-14 | | No sub-domain inside a domain that replicates the layer tree | [§4](#4-files-and-packages) |
| STY-15 | | Search the shared util locations before writing a util; place it by scope of use | [§4](#4-files-and-packages) |
| STY-16 | | Class and function KDoc summaries only when the decision table's triggers hold; one line, no tags | [§5](#5-comments-and-kdoc) |
| STY-17 | | Line comments only on genuinely complex logic, in present tense and domain vocabulary — never history, rationale or code translation | [§5](#5-comments-and-kdoc) |
| STY-18 | | A deliberate simplification may carry one `// ponytail:` comment in Korean naming its limit and how to lift it | [§5](#5-comments-and-kdoc) |
| STY-19 | | Inline every single-use intermediate unless one of the five keep conditions holds | [§6](#6-single-use-intermediates) |
| STY-20 | | No plumbing parameters on private methods (four carve-outs) | [§7](#7-plumbing-parameters) |
| STY-21 | | A simple feature stays in its public method; a composed feature lists one private step method per step | [§8](#8-method-shape) |
| STY-22 | | Inside one class, private-call depth below a public method is at most 2 | [§8](#8-method-shape) |
| STY-23 | | Control blocks nest at most 3 deep inside one function | [§8](#8-method-shape) |
| STY-24 | | A method name is a verb phrase of about 30 characters at most | [§8](#8-method-shape) |
| STY-25 | | Use the latest stable idiom of the adopted versions; no deprecated API in new code | [§9](#9-standard-library-and-readable-code) |
| STY-26 | | Standard-library functions before loops, helpers or project extensions | [§9](#9-standard-library-and-readable-code) |
| STY-27 | | Plain control flow first: one `@Transactional`, a synchronous call, assembly in the controller — extra boundaries, executors, `@Async` and AOP only when the plain form cannot work | [§10](#10-prefer-the-plain-option) |
| STY-28 | | No abstraction (interface, base class, strategy, flag, optional parameter) without a second real use | [§10](#10-prefer-the-plain-option) |
| STY-29 | | Persisted and DTO timestamps are `ZonedDateTime`; `Instant` only for framework APIs and in-memory arithmetic | [§11](#11-time-and-durations) |
| STY-30 | | Date boundaries (today, year, month) use the application time zone; never `ZoneId.systemDefault()` | [§11](#11-time-and-durations) |
| STY-31 | | A time-of-day `@Scheduled(cron)` declares `zone` as the application time zone | [§11](#11-time-and-durations) |
| STY-32 | | Compare `ZonedDateTime` with `isEqual`/`toInstant`, never `equals` | [§11](#11-time-and-durations) |
| STY-33 | | Durations in code are `java.time.Duration`, never a number with a unit suffix | [§11](#11-time-and-durations) |
| STY-34 | | An entity state-change method logs the fields it assigns at INFO, `id` first | [§12](#12-logging) |
| STY-35 | | Application logs read `{Subject} {action}: key=value, …` at the level §12 assigns; every operation leaves an INFO line with its result, and a line repeated inside one operation is DEBUG | [§12](#12-logging) |
| STY-36 | | Never log a password, token or secret, or interpolate a whole command or properties object | [§12](#12-logging) |
| STY-37 | | A service does not repeat a change its entity already logged | [§12](#12-logging) |
| STY-38 | | A data class holding a secret overrides `toString` to mask it | [§12](#12-logging) |
| STY-39 | | Absorb a failure only for a best-effort side effect, and log it at WARN with the exception | [§13](#13-failure-handling) |
| STY-40 | | Catch the narrowest type; catch `Throwable` only to clean up and rethrow | [§13](#13-failure-handling) |
| STY-41 | | No `runCatching` inside a `suspend` function | [§13](#13-failure-handling) |
| STY-42 | | A failed remote lookup degrades to empty only for display enrichment, and its KDoc says so | [§13](#13-failure-handling) |
| STY-43 | | No `Executors.new*` or unbounded thread-per-task inside a bean; run background work on a Spring-managed executor | [§14](#14-threads-retries-and-lifecycle) |
| STY-44 | | `runBlocking` only at the boundary to a blocking API | [§14](#14-threads-retries-and-lifecycle) |
| STY-45 | | Retry through one shared helper (e.g. `withRetry`), never a hand-written loop | [§14](#14-threads-retries-and-lifecycle) |
| STY-46 | | Long-running work starts on `ApplicationReadyEvent` and stops in `@PreDestroy` | [§14](#14-threads-retries-and-lifecycle) |
| STY-47 | | File system code uses `java.nio.file.Path`/`Files` and `Path.of`; `java.io.File` only where an API requires it | [§15](#15-files-and-streams) |
| STY-48 | | Whoever opens a stream closes it; no open stream inside a Command or Result | [§15](#15-files-and-streams) |
| STY-50 | | No filler suffix (`Dto`, `Data`, `Info`, …) on DTO names; `Dto` casing in the collision carve-out | [§16](#16-filler-suffixes-and-dto-casing) |
| STY-52 | | A DTO carried by a message broker is `*Message`; an in-process Spring event is `*Event` | [§18](#18-transport-dto-suffix) |
| STY-53 | | `*Message` names are verb-first; `*Event` names are past participles | [§18](#18-transport-dto-suffix) |
| STY-54 | | A new file, package or module follows the module and package layout table | [§19](#19-module-and-package-layout) |
| STY-55 | | A new ErrorCode is its prefix's highest number + 1; removed numbers are never reused or closed up | [§20](#20-errorcode-numbering) |
| STY-57 | | Each service module registers its own code for a shared concept unless `CommonErrorCode` already covers it | [§20](#20-errorcode-numbering) |

These rules apply to every layer (controller, service, repository, entity, util) alongside the layer file. Worked `❌`/`✅` pairs live in [examples/code-style.md](examples/code-style.md). §18–§20 are situational — a broker or Spring-event DTO, a new file, package or module, a new ErrorCode; read the matching section before such an edit. When an external skill says otherwise, [§17](#17-external-skill-precedence) settles it.

---

## 2. Baseline

Kotlin, Spring Boot and a Gradle (multi-module) build. `./gradlew ktlintFormat` formats and `ktlintCheck` verifies.

| ID | Item | Rule |
|---|---|---|
| **STY-1** | Logging | Log through the project's single logger idiom; never `LoggerFactory.getLogger(…)` or a per-class `KotlinLogging.logger`. The default idiom is the `Logger` base class below — a project may already have its own equivalent; use that. Sole exception: a `@RestControllerAdvice` extending Spring's `ResponseEntityExceptionHandler`, whose parent already defines a clashing `logger` property, uses a file-level `KotlinLogging.logger {}`. [Example](examples/code-style.md#sty-1--logger-base-class) |
| **STY-2** | Imports | Always `import`; never inline a fully qualified name (`com.example.…`) in code or tests |
| **STY-3** | Functions | Expression body for simple functions |
| **STY-4** | Dependency injection | Constructor injection only |
| **STY-5** | Primary keys | `UUID`. Exceptions are explicitly listed entities only, in three shapes: a generated `Long`, a `String` natural key (upserted with `ON CONFLICT`), and a composite `@IdClass` key ([REPOSITORY §6](repository.md#6-entity-mapping)) |
| **STY-6** | Section comments | No banner comments such as `// === Create ===`; method order is a convention ([SVC-21](service.md#7-method-order)), not a comment |

The default logger base class (kotlin-logging):

```kotlin
abstract class Logger {
    val logger by lazy { KotlinLogging.logger(this::class.java.name) }
}
// class OrderService(...) : Logger()      — a bean
// companion object : Logger()             — a class that already extends something else
```

Timestamps follow [§11](#11-time-and-durations). An optional `@RequestParam` follows [CTL-3](controller.md#2-endpoint-signatures).

---

## 3. Kotlin syntax

**STY-7** — No not-null assertion `!!`, in production code or tests. Unwrap with `requireNotNull(x) { "<context message>" }` where the failure-forms table of [SERVICE §5](service.md#5-exceptions-and-failure-forms) allows it: for an internal invariant inside a Service or Command, and freely outside Service and Command (`SpringBootTestSupport` and other test infrastructure, utils, repository tests). The stdlib `require`/`check`/`error` follow the same table; they are not a way around this rule, and a null branch the table does not allow becomes a named domain exception. Where the platform guarantees non-null (`@Autowired lateinit var` read after `@PostConstruct`), express it with `lateinit` or `by lazy` so nullability never arises.

✅ `requireNotNull(member) { "member not loaded: id=$id" }` — ❌ `member!!.name`. [Example](examples/code-style.md#sty-7--not-null-assertion)

**STY-8** — No `@Suppress("UNCHECKED_CAST")` in any `.kt` file — production, test or helper. Express the cast type-safely (`filterIsInstance<T>()`, a Jackson `TypeReference`, `mapNotNull`) and the suppression becomes unnecessary.

✅ `list.filterIsInstance<Order>()` · `readValue(s, object : TypeReference<Map<String, Any>>() {})` — ❌ `@Suppress("UNCHECKED_CAST") … as List<Order>`. [Example](examples/code-style.md#sty-8--unchecked-cast)

**STY-9** — A single-expression trailing lambda stays on one line. The short message lambda of `require`/`check`/`requireNotNull` always goes on one line with its receiver and arguments; this assumes ktlint's `max_line_length` is off (no `.editorconfig` sets it), so length is never a reason to wrap it. Any other single-expression trailing lambda (`let`, `map`, `runCatching`, …) goes on one line when the merged line, indentation included, is at most 120 characters; beyond that it stays on three lines. The 120-character cap limits merging — it does not require splitting an existing one-line lambda that is already longer. Exception for both: when the argument (receiver expression) is itself multi-line, leave it — the wrap comes from the argument, not the lambda.

✅ `requireNotNull(x) { "msg" }` — ❌ splitting `{` body `}` across three lines. [Example](examples/code-style.md#sty-9--single-expression-trailing-lambda)

**STY-10** — In a block-body function whose body ends with a top-level `return` preceded by at least one statement, separate that `return` from the line above with one blank line. Not applicable: an expression body (no `return`; prefer it for single-expression functions anyway, STY-3), a `return` that is the block's only or first statement (never a blank line right after `{`), and mid-function guard or early returns. ktlint cannot enforce it.

✅ `publish(event)⏎⏎ return OrderResult.from(order)` — ❌ `publish(event)⏎ return OrderResult.from(order)`. [Example](examples/code-style.md#sty-10--blank-line-before-the-final-return)

**STY-11** — A call passing 2+ arguments names them (`foo(a = x, b = y)`). Exempt:

- single-argument calls (`findById(id)`);
- operator and infix calls (`a + b`, `a to b`) — named syntax is impossible;
- Java (non-Kotlin) function calls (`passwordEncoder.matches(raw, encoded)`) — the compiler rejects named arguments there;
- trailing lambdas (`list.map { }`) — the lambda stays trailing, other arguments are still named;
- Kotlin comparison and math functions (`maxOf`, `minOf`, `min`, `max`) — the arguments are symmetric, so there is no order to mix up;
- the vararg elements of a call (`lockPaths(a, b)`) — other parameters of the same call are still named;
- QueryDSL and fluent builder chains (`.eq()`, `.and()`, `.where()`).

ktlint cannot enforce it.

✅ `createMember(name = n, email = e, active = true)` — ❌ `createMember(n, e, true)`. [Example](examples/code-style.md#sty-11--named-arguments)

---

## 4. Files and packages

**STY-12** — One top-level type per file (`class`, `object`, `interface`, `enum class`; nested and inner types do not count). Five carve-outs:

- a `sealed class` or `sealed interface` with its direct subtypes (one hierarchy, one file);
- a JPA `@Entity` with its `@IdClass` composite-key `data class`;
- a `@Configuration` with the `@ConfigurationProperties` `data class` it binds;
- a cohesive util file: one `object` with its own extension functions and a helper `enum`;
- a `@SpringBootApplication` with `fun main`.

Command, Result, Request and Response files sit at their directory root, one class per file, no subfolders: `service/command/{Action}{Entity}Command.kt` and `{Action}{Entity}Result.kt`, `controller/rest/{Action}{Entity}Request.kt` and `{Action}{Entity}Response.kt`.

✅ `sealed interface R { data class A : R; data class B : R }` in one file — ❌ unrelated `class Foo` and `class Bar` in one file, or `service/command/order/OrderCommands.kt`.

**STY-14** — No sub-domain inside a domain that replicates the layer tree. A domain's typical direct children are the layer directories (`controller` with `rest`, `entity`, `enumerate`, `event`, `exception`, `repository` with `query`, `service` with `command`, `client`, `util`, `config`). The test is only "does that child replicate the layer tree", not "is its name a layer name": a group inside one layer (`order/{controller,entity,repository,service}/archive/`), an absorbed external tool tree (`order/importer/{connection,extract,sink,…}/`) and single-purpose directories (`order/lock/`) are all legitimate. A domain is top-level rather than parent-owned unless both hold: ① its entity hangs off another domain's aggregate root through `@ManyToOne` + `@OnDelete(CASCADE)`, and ② that domain is its only external consumer. ① alone misjudges: when domain A's entity cascades from domain B's root but B also consumes A back, ② fails and A stays top-level.

✅ `order/{controller,entity,service,…}/OrderAttachment*.kt` — ❌ `order/attachment/{controller,entity,service,…}/`.

**STY-15** — Before writing a util, search the locations below and reuse what exists. Logic shared by 2+ modules is promoted to a shared module, never re-implemented inside a domain.

| Scope of use | Location |
|---|---|
| Shared by 2+ modules, pure Kotlin (no Spring) | the shared pure-Kotlin module's `util` package |
| Shared by 2+ modules, Spring-dependent | the shared Spring module |
| Shared across several domains within one module | `{module}/.../util/` |
| Internal to a single domain | `{module}/.../{domain}/util/` |

---

## 5. Comments and KDoc

Explanation is split by altitude — what a reader needs before opening a file differs from what they need mid-body:

| What | Where | Why |
|---|---|---|
| A class or object's role, when its name does not say it | a one-line KDoc (`/** … */`) directly above the declaration (STY-16) | a reader scanning the package needs it before opening the body |
| A function's role, when a trigger holds | a one-line KDoc above the function (STY-16) | skip it when the name and types predict the body |
| A genuinely complex line or block | a `//` at that line (STY-17) | only where a careful reader could still misread the logic after reading it once |
| A known limit of a deliberate simplification | one `// ponytail:` line (STY-18) | the next reader needs the ceiling before relying on the code |
| Why, background, history | commit-message body · decision records (e.g. `docs/decisions/`) · test names | in source it is never reviewed and rots with the code — a stale rationale is worse than none |

**STY-16** — A class or function gets a KDoc summary only when a trigger in the decision table ([§5.3](#53-deciding-a-comment-finding)) holds: for a class, its name and package do not state its role; for a function, it has a side effect its name does not say, absorbs a failure or returns a value with a special meaning, carries an ordering guarantee callers rely on, or expects a precondition, transaction or lock its signature does not show. A summary is one line, rarely two, states what the declaration is for — not how it is implemented and not why it exists — and carries no `@param`/`@return`/`@throws` tags; the signature already says those. Skip it when the declaration already says it: a `*NotFoundException`, a one-line expression-body function whose signature predicts the body, a data class whose name and fields are the whole story, a trivial getter or override. A summary that keeps growing past ~3 lines to state *what* is a sign the declaration needs splitting, not a longer comment.

**STY-17** — Line comments are reserved for genuinely complex logic: a branch, calculation, ordering or edge case a careful reader could still get wrong. Most executable lines get none. A self-naming call (`logger.info { }`, `eventPublisher.publishEvent(...)`, a guard clause whose condition names itself), a plain assignment or a one-line CRUD or repository call needs no comment. Tests carry none ([TST-1](testing.md#3-test-structure)).

- **Present tense, current state only.** A comment states what the code does now. It does not say why it was written this way, what it used to be, what it was renamed or moved from, or which ticket or migration changed it; the history words are listed in the *History or rationale* row of the decision table. Rationale belongs in the project's decision records and history in the commit body.
- **Domain vocabulary, never a translation of the code.** A comment — summary or line comment alike — that renders type and method names back into prose carries no information and drifts on every refactor. Write what it means in domain vocabulary. [Example](examples/code-style.md#sty-16--sty-17--summaries-and-line-comments)
- **Format.** `//` for line comments, `/** */` for summaries, written in Korean; only exception messages are English ([SVC-13](service.md#5-exceptions-and-failure-forms)). Never copy the same TODO or temporary-policy marker verbatim across files — keep one canonical location.

**STY-18** — A deliberate simplification with a known ceiling — a global lock, an O(n²) scan, a naive heuristic — may carry one `// ponytail:` line comment: one Korean sentence that states the limit of the current code and how to lift it.

```kotlin
// ponytail: 전역 락 — 처리량이 문제되면 계정별 락으로 나눈다
```

It describes the current code's ceiling, so it is current state, not rationale or history. Never `#`, never an English sentence, one comment per simplification.

### 5.1 What is never commented

**Never commented**: `package` and `import` lines · annotations · property declarations · data-class fields · closing braces · a `logger.info/warn/debug/error { }` line, an `eventPublisher.publishEvent(…)` line, a bare `return X.from(…)` — the message string, the event constructor and the target type already say in domain vocabulary what the line does, so any comment there is translation by construction · `src/test/**` ([TST-1](testing.md#3-test-structure)).

**Not comments** (governed by their own rules; keep writing them): `@field:Schema(description=…)` and `@Parameter(description=…)` ([CTL-9](controller.md#45-openapi-descriptions)) · a KDoc another rule demands as the justification for an approved exception (an `@EntityGraph` exception under [REP-2](repository.md#21-priority), an unavoidable `@Lazy` under [SVC-20](service.md#63-breaking-bean-cycles-without-lazy)).

### 5.2 ktlint traps

Four ktlint constraints apply to every `//` comment that ends up on a complex-logic line; violating them breaks `./gradlew check`:

| Rule | Constraint |
|---|---|
| `standard:no-multi-spaces` | **Never column-align comments.** Exactly one space between code and `//`. Padding several lines to a common column is a violation on every one of them, and `ktlintFormat` collapses it back |
| `standard:function-literal` · `Expected a newline after '{'` | **Three opener positions reject a trailing comment**: ① a multi-line lambda's `{` or `->` ② an expression-position `try {` or `when (x) {` (the value-assigned form) ③ a `when` branch line. Hoist the comment to its own line above. Statement-position `if (…) {`, `for` and `while` pass |
| `standard:try-catch-finally-spacing` | The opening `{` of `try`, `catch (…)` and `finally` also rejects a trailing comment (`Expected a newline after '{'`). Move the explanation onto the block's first executable line, or above the `try` |
| `standard:blank-line-between-when-conditions` | A trailing comment on a `when` branch makes that condition multi-line and then demands a blank line between every branch. Fine in a `when` whose branches are already blank-line separated; breaks a `when` of packed one-liners — for those, one comment above the `when` |

A multi-line call's `(` is unconstrained (`service.foo( // …` passes), and comments inside a named-argument list are fine (`standard:value-argument-comment` looks at a different position). [Example](examples/code-style.md#sty-17--comment-ktlint-traps)

### 5.3 Deciding a comment finding

Every comment finding has exactly one fix, so a review never leaves one for a human to judge. For an existing comment apply the first of the first five rows that matches; for a missing summary use the last two rows. When two outcomes seem possible, delete — a missing comment costs less than a stale one.

| Finding | Test | Fix |
|---|---|---|
| Limit comment | the comment starts with `// ponytail:` and states a limit of the current code (optionally how to lift it) | keep it; the *History or rationale* row does not apply to it |
| History or rationale | the text contains a history word (`기존에는` · `예전에는` · `이전에는` · `바뀌었다` · `옮겼다` · `대체했다`), names the ticket that changed it, or says why the code was written this way instead of what it does now | delete that clause; keep the current-state remainder, or delete the comment when nothing is left |
| Code-translating | remove every word that is a name in the declaration or on the line, and nothing is left | delete; when a domain fact remains, keep only that fact in domain vocabulary |
| Line comment on simple logic | the line is none of: a non-obvious ordering or boundary, an arithmetic or encoding choice, the domain meaning of a magic value, a transaction or concurrency ordering constraint, a workaround for a library or platform behavior | delete |
| Oversized summary | the summary spends more than ~3 lines on *what* | cut to the one line that says what it is for |
| Missing function summary | the function meets at least one trigger: a side effect its name does not say (event, audit row, remote call, file write) · it absorbs a failure instead of throwing, or a return value carries a special meaning (`null` / empty / `false` = X) · callers rely on an ordering or first-wins guarantee · a precondition, transaction or lock expectation is absent from the signature | add one KDoc line in domain vocabulary that states the trigger; with no trigger, add nothing |
| Missing class summary | the name and package do not state the role, and the declaration is none of the shapes STY-16 skips | add one KDoc line saying what the type is for |

---

## 6. Single-use intermediates

**STY-19** — Inline every single-use intermediate variable, in every layer, unless one of the five keep conditions below holds. A meaningful name is not by itself a reason to keep it. `src/test/**` is out of scope: a test may split a variable out for explicitness.

Three patterns are in scope — [example for all three](examples/code-style.md#sty-19--inline-single-use-intermediates):

| Pattern | Where it appears | How to inline |
|---|---|---|
| (a) **Inline the result** — a call's result received and immediately handed to the next call | just before the function ends | expression body + `.let(::from)` |
| (b) **Inline the argument** — a Command, Request or Result object built into a `val` and passed once | just before the call | construct it at the argument position (wrap *inside* the argument if long) |
| (c) **Chain the guards** — each step takes a `val`, checks it with `if (…) throw`, feeds the next | pipeline body | fold the guard into the chain with `ifEmpty {}` · `takeIf {} ?: throw` · `?:` — all stdlib, so no custom helper (STY-26) |

Keep the variable when any one of these holds:

| # | Keep condition | Example |
|---|---|---|
| 1 | It is referenced 2+ times, including once inside a loop — inlining would recompute or re-query it | an `actor` loaded once and referenced once per item inside the loop |
| 2 | Adjacent logging or events reference it, or transaction or external-call ordering depends on it | — |
| 3 | It snapshots a value before a mutation | a `previousStatus`, single-use but read before `status` is reassigned |
| 4 | It is the sole argument of a side-effecting call whose miss is a guard | `val member = repo.find(...) ?: throw …; repo.delete(member)` — `delete(find(...) ?: throw …)` nests rather than chains and hides the 404 path behind `delete(` |
| 5 | It holds a remote call's result | folding `paymentClient.getPayment(...)` into a `.let { }` makes an HTTP round trip read like a pure collection pipeline; surface the call as a statement and fold only the guards |

Inline only when none of the five holds. A variable kept only for its name is deleted, and no comment is added in its place. The goal is removing noise, not forcing everything onto one line.

---

## 7. Plumbing parameters

**STY-20** — Where STY-19 targets local variables, this rule targets the parameters themselves. When a private method's parameter satisfies both of these, remove the parameter and let the callee obtain the value itself: ① it is built at the call site solely for that call ② the callee can obtain the same value from another parameter it already receives or from its own dependencies. [Example](examples/code-style.md#sty-20--no-plumbing-parameters)

Keep the parameter if any one of these carve-outs applies:

| # | Reason to keep | Example |
|---|---|---|
| ⓐ | **An I/O result that is invariant across a loop or repeated calls** | a method called N times that re-queries every time costs N I/O round trips; one query outside the loop is loop-invariant hoisting, not plumbing. `reserveStock(item, maxRetries, warehouses)` — across N order items the setting value and the warehouse list are invariant |
| ⓑ | **An invariant only the call site can prove** | the parameter carries a fact in its type; removing it grows a `requireNotNull` in the callee (STY-7). `refund(order, paymentId: UUID)` — the call site's `?: return` guard proves non-null |
| ⓒ | A public or external contract parameter | call-site variety and testability are its reason to exist (the Command of a public Service method, etc.) |
| ⓓ | A controller's authenticated-principal parameter (e.g. `authUser: AuthUser`), even when the body never reads it | it is the 401 contract, not plumbing — its `HandlerMethodArgumentResolver` throws when the principal is absent |

Checklist: is the argument exclusive to that call? · can the callee obtain it itself? · is it not a repeated-call invariant I/O (ⓐ)? · does it not carry an invariant (ⓑ)? — all yes → remove it. Test code is out of scope.

---

## 8. Method shape

A class reads top-down: the public method says **what** a feature does, and private methods hold **how**, one step each. `src/test/**` is out of scope.

**STY-21** — A feature with one flow (load → check → save, or one transformation) stays inside its public method. A private method whose body is one or two lines delegating to a single call adds a name without hiding any work — fold it back into its caller. When a feature combines several distinct steps, the public method lists them as calls at one level of abstraction (`checkX(…)` → `buildY(…)` → `save(…)` → `publish(…)`), and each private method does exactly one step. Extract a block as a step when it has a purpose you can name **and** it runs about 5 lines or more or has its own branching. A public method needs this split when its body passes about 20 lines, or when it mixes step calls with another step's low-level code.

```kotlin
// ✅ composed feature — the public method is the table of contents
@Transactional
fun ship(command: ShipOrderCommand): ShipOrderResult {
    val order = getEntity(command.orderId)
    checkShippable(order)
    order.ship(command.shippedBy)
    notifyMember(order)

    return ShipOrderResult.from(order)
}
```

**STY-22** — Inside one class, `public → private → private` is the deepest call chain; recursion and `companion object` members do not count. A third level means the chain is a responsibility of its own: lift the middle step into the public method so the steps sit side by side, or move the chain to a collaborator class that owns it.

**STY-23** — Inside one function, `if`/`for`/`when`/lambda blocks nest at most three deep. Flatten deeper code with a guard clause or an early return, or move the inner block into a step method.

**STY-24** — A method name is a verb phrase of about 30 characters at most: `listOpenOrders` · `checkDuplicateOrder` ✅ / `listProductIdsOrderedByOtherActiveMembers` ❌. A longer name usually lists conditions — move them into a parameter or a `*Query`, or split the method.

**Exemptions**

- `Custom*RepositoryImpl` — QueryDSL predicate assembly follows [REP-5](repository.md#22-by-predicate) and [REP-10](repository.md#31-multi-condition-reads), so STY-21 and STY-22 do not apply.
- STY-24 — a name another rule or a supertype fixes: Spring Data derived queries, the qualifiers [SVC-18](service.md#6-cross-domain-access) requires (the `With…` part is not counted), `override` methods.

STY-19 folds single-use variables and STY-28 folds the abstractions [§10](#10-prefer-the-plain-option) lists; neither folds a step method STY-21 asks for, nor a chain moved to a collaborator for cohesion. Private method order: [SVC-22](service.md#7-method-order). Whether a feature is simple or composed is a review judgment.

---

## 9. Standard library and readable code

**STY-25** — Use the latest stable idiom of the adopted versions (Kotlin, Spring, Jackson, QueryDSL). New code introduces no deprecated API; an upgrade migrates to the better idiom and leaves no deprecation warning. Prefer the shorter, more readable expression (expression body, scope functions, stdlib collection operations), but when length conflicts with clarity, clarity wins — short is not a clever one-liner that hides meaning. This is a judgment principle, not a mechanical gate.

✅ `members.filter { it.active }.map { it.name }` — ❌ a hand-rolled loop building an `ArrayList`, or a deprecated API in new code. [Example](examples/code-style.md#sty-25--sty-26--latest-api-and-standard-library)

**STY-26** — Before writing a loop, a helper or a project extension function, use the Kotlin standard-library function that already expresses the operation: null and empty handling (`orEmpty` · `ifEmpty` · `ifBlank` · `takeIf` · `?:`), scope functions (`let` · `also` · `apply`), collection operations (`associateBy` · `groupBy` · `partition` · `sumOf` · `maxByOrNull` · `firstOrNull` · `chunked` · `buildList` · `buildMap`), and `use` for closing a resource. Write a new util (STY-15) or extension function only when no standard-library, Spring or Jackson function expresses the operation; replace a wrapper that renames or re-composes one standard-library call with the call itself.

✅ `items.associateBy { it.id }` · `name.ifBlank { DEFAULT_NAME }` — ❌ a `forEach` filling a `mutableMapOf()` · `fun String?.orDefault(default: String) = if (isNullOrBlank()) default else this`

STY-9, STY-10 and STY-19 are concrete forms of the same goal; where any of them collides with clarity, clarity wins.

---

## 10. Prefer the plain option

**STY-27** — An advanced framework feature is introduced only when the plain form cannot express the work. The plain form is one `@Transactional`, a synchronous call, and assembly at the call site (the inbound adapter). The advanced forms are extra transaction boundaries (`inTx`, `REQUIRES_NEW`), a dedicated `ThreadPoolTaskExecutor` `@Configuration`, AOP, `@Async` and custom propagation.

Before opening a boundary, pass the **upper gate**:

> **If the external call is pushed out of this service (to the caller or a listener), does this boundary disappear entirely?** If yes, do that and do not open the boundary.

- **Passes** when the call's arguments come from the Command or a constant: hoist the call, keep one `@Transactional`, and delete the compensation code. The controller calls one remote reader before its Service and passes the answer in the Command; the reader call carries no decision of its own, and the Service still validates against it. This hoist is an exception to [CTL-28](controller.md#13-thin-controller).
- **Does not pass** when the call is sandwiched — its input read from a row and its output written back to it. Then descend to options 1–3 of [TX-3](transactions.md#3-external-calls-and-compensation); loading the row twice is the structural price of [TX-2](transactions.md#3-external-calls-and-compensation), not a STY-27 violation.
- **Never delete an existing boundary** to satisfy the gate — that silently loses dirty-checking writes. What moves is the external call's location.
- **Executors follow the same rule**: before adding a per-domain `ThreadPoolTaskExecutor` `@Configuration`, check whether an existing executor or a synchronous call does the work (STY-43).

**Hoisted call sites.** Keep them in one canonical list of this shape; [TX-3](transactions.md#3-external-calls-and-compensation) and [CTL-28](controller.md#13-thin-controller) point here.

| Controller method | Remote reader call | Command field | Service method |
|---|---|---|---|
| `OrderController.createOrder` *(illustrative)* | `PaymentClient.listAvailableMethods` (payment methods the member may use) | `availablePaymentMethods` | `OrderService.createOrder` |

**STY-28** — Write the concrete class or function the current callers need. Introduce an interface, abstract base class, type parameter, strategy or factory, configuration flag, or optional parameter only when a second real use exists in the code or in the same change — never for an expected one. Fold an abstraction left with one use back into that use. These shapes stand without a second implementation:

- framework-required shapes — Spring Data repositories, `Custom*Repository` + `Custom*RepositoryImpl` ([REP-3](repository.md#2-query-construction)), and OpenFeign client interfaces;
- `sealed` hierarchies, which model a closed set of cases rather than an extension point;
- dependency inversion that a module boundary or a bean cycle requires — a shared module declaring a port that a service module implements, or an interface that removes a cycle instead of `@Lazy` ([SVC-20](service.md#63-breaking-bean-cycles-without-lazy)).

✅ a `private fun` in the one Service that uses it — ❌ `interface OrderExporter` + `DefaultOrderExporter` with one caller · a `mode` parameter to which every caller passes the same value

Both rules are review judgments, not machine-detectable.

---

## 11. Time and durations

**STY-29** — Persisted and DTO timestamps are `ZonedDateTime`. `ZonedDateTime.now()` is fine: with `timestamptz` columns the stored instant does not depend on the JVM zone. `Instant` appears only where a framework API takes or returns one (Spring `Trigger`) and in in-memory arithmetic.

**STY-30** — A date boundary — today, the current year or month, a code number's date part — uses the application time zone (e.g. `appProperties.timeZone`, bound from `app.time-zone`): `LocalDate.now(appProperties.timeZone)`, `Year.now(appProperties.timeZone)`. Never `ZoneId.systemDefault()`: containers run in UTC and local machines in the developer's zone (e.g. Asia/Seoul), so the same instant falls on different dates.

**STY-31** — A time-of-day cron — an `@Scheduled(cron = …)` that fires at a wall-clock time — declares the application time zone: `@Scheduled(cron = "0 0 3 * * *", zone = "\${app.time-zone}")`.

**STY-32** — Compare `ZonedDateTime` values with `isEqual` or through `toInstant()`, never `equals` or `==`: `equals` also compares the zone, so one instant in two zones is unequal.

**STY-33** — A duration in code is a `java.time.Duration`: `Duration.ofSeconds(30)`, not `const val X_SECONDS = 30L` multiplied by `1000L` at the use site.

---

## 12. Logging

**STY-34** — An entity state-change method (`update()`, a state transition, `delete()`) logs the fields it assigns, at their current value, at INFO right after mutating. It is a developer-facing application log, separate from any DB audit log and not replaceable by it.

| Topic | Rule |
|---|---|
| Inherit logger | Inherit it from the entity base class (e.g. a `BaseTimeEntity` that extends `Logger`). No `companion object : Logger()` on the entity |
| Message format | `"{Entity} {action}: id=$id, <fields this method assigns>"` — `id=$id` always first, then the assigned fields in declaration order (the leading `{Entity} {action}` is for grep) |
| List only what changed | Never reflection-dump the full state, and no exclusion patches (blocking annotations, `snapshot()` overrides) — list each assigned field explicitly |
| Sensitive fields | Log the fact only, never the value (`"Member password updated: id=$id"`) |
| Large collections and binary | Log a summary, not the contents — e.g. a `count`/`cardinality`, never a `List` that can hold tens of thousands of elements or a `ByteArray` |
| Associations | By id (`memberId=${member.id}`, `itemIds=${items.map { it.id }}`) — interpolating the entity triggers LAZY initialization and N+1 |
| Mutation in a private helper | List what the helper assigns at the call site (e.g. `Order.clearItems()`); do not move the log into the helper (the action phrase differs per caller) |
| Constant assignments | Omit fields whose value is a constant for that method — the action phrase already carries it (`Member.delete()` → `deletedAt` only; `Order.reopen()` → `id` only). Exception: the transition's primary field stays even when constant (`Order.hold()` → `status=ON_HOLD`) |
| No-op guard placement | An early return on the state-change method's first line, not an `if` at the call site — the compared value is the entity's own (`Product.update`). Exception: the service owns the guard when it must also skip event publishing or a return value |
| Rejection or failure | No duplicate logging in the entity — throw a named exception and `GlobalExceptionHandler` logs it. Guards (`throw`) come before the mutation, so only the success path is logged |
| Not covered | ① a heartbeat `touch()` ② a progress advance with no status transition (log only when `status` changes) — the row itself holds the progress value |

[Example](examples/code-style.md#sty-34--entity-change-logging)

**STY-35** — Every other application log reads `{Subject} {action}: key=value, key=value` — the same shape as STY-34; never `key: value`. Ids, email and client IP may be logged. The level follows the tables below.

✅ `logger.info { "Order shipped: id=$id, shippedBy=$memberId" }` — ❌ `logger.info { "order shipped - id: $id" }`

Prod keeps only INFO and above, so it must still show what ran and how it ended. Volume is cut by removing repetition, not by removing operations.

| Level | When | Content | Example | Not this level |
|---|---|---|---|---|
| ERROR | A failure that needs action: risk of data loss or inconsistency, a dead-letter quarantine, a failed rollback, exhausted retries, a 5xx | Pass the exception object (`logger.error(e) { … }`) | `Ship order message quarantined to dead letter`, `Refund rollback failed` | A transient failure that recovers on its own, or a client disconnect → WARN or DEBUG |
| WARN | An anomaly that was recovered or skipped: dropped or skipped input, one retry attempt, a best-effort failure (STY-39), a 4xx ([SVC-16](service.md#5-exceptions-and-failure-forms)), a security-relevant failure (sign-in failure, two-factor mismatch, permission denial) | Pass the exception object for a failure. A 4xx is one line without a stack trace | `Sign in failed - wrong password`, `Ship order failed, redelivering` | A normal branch of the flow → INFO or DEBUG |
| INFO | Every operation logs at least one INFO line with its result. An operation is a user action, an event or message received across an async boundary (an after-commit listener, a broker message), a job run, a state change (STY-34), a startup or shutdown fact, or the recovery from a failure | Name the target (id or path) and log the result: what was created, changed, deleted or skipped (ids, counts). An async receipt is logged on receipt, and its handler logs the result. A collection is listed only when its size is bounded, otherwise counted. The actor is not written into the message on a request thread, because the MDC adds it (below). A line on another thread (message listener, executor, `@Async`) names the actor itself (`actorId=`) when the message carries one | `Order canceled: id=…, memberId=…`, `Expired carts removed: count=…`, `Stock sync: productCount=…, updated=…` | A line repeated inside one operation → DEBUG |
| DEBUG | ① A line repeated inside one operation: per chunk, progress tick, loop item or scheduler tick. ② An intermediate step or a timing. ③ A synchronous "requested" line, but only when the same thread always ends in a result INFO line or a `GlobalExceptionHandler` error naming the same target (extends STY-37). ④ The repeats of a failure that was already reported | Same shape as INFO | `Chunk received`, `Export progress`, `File copy requested` | The only record of an operation or of its result → INFO |
| TRACE | Not used | | | |

DEBUG is enabled only in non-prod profiles (e.g. `local`, `dev`, `release`). Choose the level in this order, and stop at the first match:

| Order | Question | Level |
|---|---|---|
| 1 | Does the failure need someone to act? | ERROR |
| 2 | Is it an anomaly that was recovered or skipped, a 4xx, or a security-relevant failure? | WARN |
| 3 | Is it repeated inside one operation, or does an INFO line in the same thread already record the same fact and result? | DEBUG |
| 4 | Anything else that ran, was received or changed state | INFO |

Repetition:

| Situation | Rule |
|---|---|
| A timer or an unbounded loop repeats the same failure | Log WARN or ERROR when the failure starts, DEBUG while it persists, and INFO when it recovers. Use one field in the same class, not a helper class (STY-28) |
| The same input keeps arriving (an unknown code, an address collision) | Log WARN once per key and DEBUG afterwards. The key identifies the same fact, for example source id plus address |
| A bounded retry (`withRetry`, a redelivery limit) | Log WARN per attempt and ERROR when the retries run out |
| Read-only access that exposes file contents: download, preview, stream, static file access | INFO once per user action. Thumbnails, later byte ranges of the same content and cache hits are DEBUG. Plain list, detail and search queries log nothing |
| *If the project records an audit trail:* the code that writes audit rows | Failure lines only, because the audit row records the fact |

**Actor and request id.** A logging filter puts the authenticated principal's user id and the incoming `X-Request-Id` into the MDC for the request thread, and the log pattern prints them after the level as `[u=… r=…]`. Every line of a request carries its actor, including STY-34 entity lines. The request id joins the lines of one request across services.

Profiles: the base logging config sets `root: WARN` and the application's base package to `INFO` (plus `org.flywaydb: INFO` in a module that runs Flyway). `local`, `dev` and `release` raise the base package to DEBUG, and `prod` keeps the base.

**STY-36** — Never log a password, token, secret or key — log the fact only. Never interpolate a whole command, request or properties object (`command=$command`); list the fields the message needs.

**STY-37** — A Service does not log again a change its entity's state-change method already logged (STY-34).

**STY-38** — A data class that holds a secret (password, token, private key, client secret) overrides `toString` and masks or omits it (`accessToken=***`).

---

## 13. Failure handling

**STY-39** — Absorb a failure only for a best-effort side effect whose failure must not fail the caller: cleanup, notification enrichment, metrics. Log it at WARN with the exception object (`logger.warn(e) { … }`). Never a silent `runCatching {}` or an empty `catch`. Compensation after a failed external call follows [TX-4](transactions.md#3-external-calls-and-compensation).

**STY-40** — Catch the narrowest exception type. Catch `Throwable` only to clean up and rethrow. Use `runCatching` when the result is handled as a value (`getOrElse`, `onFailure`), and `try`/`catch` when rethrowing.

**STY-41** — No `runCatching` inside a `suspend` function: it also catches `CancellationException` and swallows the coroutine's cancellation. Catch the specific type with `try`/`catch`.

**STY-42** — A remote lookup may degrade to an empty result only when it enriches a display (names, avatars). Its KDoc states the absorbed failure — the "absorbs a failure" trigger of STY-16.

---

## 14. Threads, retries and lifecycle

**STY-43** — No `Executors.new*` and no thread per task inside a bean. Background work runs on a Spring-managed executor, and STY-27 limits adding new executors.

**STY-44** — `runBlocking` appears only at the bridge between blocking code and a coroutine API (e.g. gRPC stub calls).

**STY-45** — A retry goes through one shared helper, never a hand-written retry loop. The default shape is a `withRetry` util in the shared module — a project may already have its own equivalent; use that:

```kotlin
inline fun <T> withRetry(
    delays: Iterable<Duration> = DEFAULT_RETRY_DELAYS,
    isRetryable: (Exception) -> Boolean = { true },
    onRetry: (attempt: Int, cause: Exception) -> Unit = { _, _ -> },
    block: () -> T,
): T
```

**STY-46** — Long-running work — a consumer, a socket, a scheduler of its own — starts on `ApplicationReadyEvent` and stops in `@PreDestroy`.

---

## 15. Files and streams

**STY-47** — File system code uses `java.nio.file.Path`, `Files` and `Path.of`. `java.io.File` appears only where an API takes one (`MultipartFile.transferTo(File)`).

**STY-48** — Whoever opens a stream closes it (`use {}`). A Command or Result never carries an open stream; return a `Path`, or a writer the controller drives.

---

## 16. Filler suffixes and Dto casing

**STY-50** — Never attach a filler suffix such as `Payload`, `Dto`, `Data`, `Info`, `Object`, `Vo` or `Wrapper` to a DTO or inner class name. The package (`controller/rest/`, `service/command/`) and the inner class's outer context (`CreateOrderRequest.Item`) already state the role, so the suffix only restates the obvious. Since a DTO is declared as an inner class with duplication allowed ([SVC-6](service.md#3-command-and-result), [CTL-5](controller.md#41-inner-data-classes)), the outer already says it is a DTO; leave only the domain meaning on the inner. [Example](examples/code-style.md#sty-50--no-filler-suffixes)

**The test — strip the suffix and read what is left.** If the remaining noun already points at that type, the suffix is filler.

**Carve-out — an essential name collision.** When two or more identically named types must be imported into the same file or scope and avoiding the collision is the purpose, the suffix is allowed. First check whether package separation or a Kotlin rename import (`as`) avoids it (e.g. `CreateOrderRequest` imports `CreateOrderCommand.ShippingAddress as CommandShippingAddress`).

**Even in the carve-out, the casing is `Dto`**: lowercase `to` and all-caps `DTO` are forbidden, and mixing them within one scope is forbidden. ✅ `OrderDto` · `ItemDto` / ❌ `OrderDTO` · `ItemDTO`.

Bean names ending in `*Template` or `*Executor` get the same test under [SVC-31](service.md#10-service-vs-component) (❌ `ProductImageCacheTemplate` → ✅ `ProductImageCache`).

---

## 17. External skill precedence

**Precedence:** the project's own docs and `CLAUDE.md` override this skill; this skill overrides general-purpose external skills.

Globally installed skills (`ponytail`, `superpowers`, `supabase-postgres-best-practices`, and whatever is installed next) carry general-purpose advice that these conventions sometimes contradict on purpose. **When they disagree, the rule here wins.** This table is the single place that settles it: add a row when a newly installed skill introduces a conflict. A row carries no rule ID.

| External instruction | This skill wins with | How to apply |
|---|---|---|
| ponytail — "no interface with one implementation" | [REP-2](repository.md#21-priority) · [REP-3](repository.md#2-query-construction) · STY-28 | `Custom*Repository` + `Custom*RepositoryImpl` stay even with a single implementation — the Spring Data `*Impl` fragment mechanism registers the bean only in that shape |
| ponytail — "Fewest files possible" | STY-12 · STY-14 | One top-level type per file (five carve-outs). Command/Result and Request/Response sit at the directory root, one class per file, no subfolders |
| ponytail — "an `assert`-based `demo()`/`__main__` self-check or one small `test_*.py`. No frameworks, no fixtures" | [TST-2](testing.md#2-test-infrastructure) · [TST-5](testing.md#3-test-structure) · [TST-6](testing.md#3-test-structure) | Extend `SpringBootTestSupport`, group with `@Nested`, write the backtick method name in Korean. ponytail assumes Python; the instruction does not transfer |
| ponytail — "mark a deliberate simplification with a `ponytail:` comment" | STY-18 | Allowed in the STY-18 form: one `// ponytail:` line comment in Korean naming the limit and how to lift it. Never `#`, never an English sentence |
| supabase-postgres-best-practices — performance advice phrased as raw SQL | [REP-1](repository.md#2-query-construction) · [REP-2](repository.md#21-priority) | **Take the diagnosis** (index choice, query plan, lock mode) and **reject the form**: derived query → QueryDSL → composition in the Service. `@Query` and `@Modifying` stay banned |

Rows 4 and 5 are the pattern to copy: an external rule that is right in intent but wrong in form becomes a format conversion, not a ban. Reach for a ban only when the intent itself contradicts a rule here (rows 1, 2, 3).

---

## 18. Transport DTO suffix

**STY-52** — A DTO's suffix is decided by one question: **does it travel over the message broker**. Anything published to or consumed from the broker is `*Message`; a Spring event that stays inside one JVM is `*Event`.

**STY-53** — `*Message` names are verb-first with no tense; a noun or adjective phrase with no verb is left as is. `*Event` names are past participles.

| Suffix | Target | Word order and tense | Example |
|---|---|---|---|
| `*Message` | every DTO carried by the message broker — to external systems and between the project's own services | **verb-first**, no tense (a noun phrase is left as is) | `ShipOrderMessage` · `CancelOrderMessage` · `CreateNotificationsMessage` · `PaymentResultMessage` |
| `*Event` | in-process Spring `ApplicationEvent` only — never serialized onto the broker | **past participle** | `OrderCanceledEvent` · `MemberCreatedEvent` · `PaymentCompletedEvent` |

Carve-out: an argument object of a direct method call that itself converts it into the `*Message` it publishes (a `*Record` handed to a recorder) is neither an event nor sent over the broker, so it takes neither suffix.

A broker DTO is often a **command or request** (`CancelOrder`, `ShipOrder`, `RequestRefund`, `CreateNotifications`), not an event — it takes `*Message` regardless.

**Do not copy an external system's inverted names.** `OrderCancelPacket`-style noun-verb names are someone else's wire idiom; action DTOs here are verb-first without exception (`ActivateMemberCommand`, `ShipOrderCommand`, `CancelOrderCommand`). A noun or adjective phrase has nothing to invert, so leave it alone (`PaymentResultMessage`, `StockStatusMessage`, `OrderReadyMessage`).

For the same operation, the service input and the wire **share the verb-object and differ only in suffix**: `CancelOrderCommand` ↔ `CancelOrderMessage` · `ShipOrderCommand` ↔ `ShipOrderMessage`.

**Not in scope** — having `Message` or `Event` in the name is irrelevant:

| Not one of these | Owning rule |
|---|---|
| `ChatMessage` (JPA entity) · `EmailMessage` (value object) | domain nouns, not transport DTOs |
| `*Request` / `*Response` | [CTL-5](controller.md#41-inner-data-classes) · [CTL-6](controller.md#42-no-entity-imports) |
| `*Command` | [SERVICE §3](service.md#3-command-and-result) |
| `*Listener` / `*Publisher` / `*Mapper` | [SVC-30](service.md#10-service-vs-component) |

**The topic or subject is not the class suffix**: an `event`/`command` segment in a topic name is the **traffic direction** axis (a fact another system reported, a command this system issues), while the suffix says **which transport contract layer** the DTO belongs to. An `….event.payment-result` topic carrying a `PaymentResultMessage` is not a contradiction, and topics are not renamed to match suffixes.

✅ `CancelOrderMessage` (to an external system) · `OrderCanceledEvent` (in-process) · `CreateNotificationsMessage` (between own services) — ❌ `OrderCancelEvent` (inverted and not an event) · `FileUploadedEvent` (rides the broker yet `Event`)

---

## 19. Module and package layout

**STY-54** — A new file, package or module goes where the tables below place it.

**Modules**

| Module kind | Package | Role |
|---|---|---|
| a deployable service | `<root>.<service>.*` | its domains plus the module-level infrastructure packages below |
| a shared pure-Kotlin module | `<root>.<shared>.*` | domain models · message definitions · constants · the `ErrorCode` interface and `CommonErrorCode` (no Spring) |
| a shared Spring module | `<root>.<shared-spring>.*` | shared Spring configuration and web components · `GlobalExceptionHandler` · pagination · broker transport |

**Inside a service module** (`<root>.<service>`)

| Package | Holds |
|---|---|
| `<domain>.controller` | `@RestController` classes |
| `<domain>.controller.rest` | `*Request` / `*Response` ([CTL-5](controller.md#41-inner-data-classes)) |
| `<domain>.service` | `@Service` use cases and role-suffixed `@Component` beans ([SVC-30](service.md#10-service-vs-component)) |
| `<domain>.service.command` | `*Command` / `*Result` ([SERVICE §3](service.md#3-command-and-result)) |
| `<domain>.repository` | repositories, `Custom*Repository` / `Custom*RepositoryImpl` |
| `<domain>.repository.query` | `*Query` |
| `<domain>.entity` | JPA entities |
| `<domain>.enumerate` | service-layer enums |
| `<domain>.event` | the in-process `*Event` classes this domain publishes, and the listeners for events from other domains that it reacts to ([SVC-41](service.md#11-spring-events)) |
| `<domain>.exception` | the domain's named exceptions |
| `<domain>.client` | a Feign client used by that domain only ([CTL-25](controller.md#11-feign-clients)) |
| `<domain>.util` · `<domain>.config` | domain-internal utils (STY-15) and configuration |
| `client` | a Feign client used by two or more domains |
| `config` | module-wide configuration |
| `util` | utils shared by several domains; `util/exception/ErrorCode.kt` ([§20](#20-errorcode-numbering)) |

The structure inside a domain follows [STY-14](#4-files-and-packages): the direct children are layer directories, and no sub-domain replicates the layer tree. Util placement follows [STY-15](#4-files-and-packages).

---

## 20. ErrorCode numbering

`ErrorCode` is an **interface** in the shared module, and each service module holds its own implementing enum at the same path (e.g. `{module}/.../util/exception/ErrorCode.kt`). The shared module holds one concrete enum, `CommonErrorCode` (`UNEXPECTED` · `MISSING_REQUIRED_FIELD` · `INVALID_PARAMETER` · …), raised by the shared `GlobalExceptionHandler`.

**Prefixes.** Each domain has its own prefix (`ErrorCode.ORDER_NOT_FOUND` → `"ORDER-1000"`); the common prefix covers the module's shared HTTP infrastructure. Several enums can draw from the common prefix (each module's `ErrorCode` plus any shared-module enums), so check all of them before allocating a common number.

**STY-55** — A new code is the highest number of its prefix + 1. A removed number is never reused, and the remaining codes are never renumbered to close the gap — a code keeps one meaning in logs and metrics across deployments.

**Collisions across services are allowed.** The same code number in two service modules may carry different meanings; the service context separates them. Do not align numbers across services, and do not report a collision as a defect. There is exactly one deciding question: *must one client respond differently to the same `type`?* If not, the collision is harmless.

**STY-57** — When one concept appears in several services (`MISSING_REQUIRED_FIELD`, …), each service registers its own code, unless the shared `GlobalExceptionHandler` already raises it from `CommonErrorCode`. Number alignment is a bonus, not a requirement.
