# Controller Conventions

**Owns:** HTTP and other inbound adapter boundaries, Request/Response mapping, REST API design, paging, Feign clients, and SSE contracts. **Read when:** editing a Controller, wire DTO, non-HTTP inbound adapter, Feign client, or SSE contract.

## 1. Hard Rules

| ID | ⚠ | Rule | Detail |
|---|---|---|---|
| CTL-1 | | The authenticated principal is a plain method parameter resolved by a `HandlerMethodArgumentResolver` (e.g. `authUser: AuthUser`); downstream tokens come from it, never from a static holder or a hand-parsed header | [§2](#2-endpoint-signatures) |
| CTL-2 | | Every endpoint is under `/api/v1` | [§2](#2-endpoint-signatures) |
| CTL-3 | | No `required = false`; an optional parameter is nullable; a `@RequestBody` has no parameter default | [§2](#2-endpoint-signatures) |
| CTL-4 | | Mapping methods in CRUD order; state transitions and other actions come last | [§3](#3-method-order) |
| CTL-5 | | DTOs a Request or Response uses are its own inner data classes; never reuse another Request/Response | [§4.1](#41-inner-data-classes) |
| CTL-6 | | `controller/rest` DTOs never import an entity package | [§4.2](#42-no-entity-imports) |
| CTL-7 | | A self-referential DTO declares its array schema explicitly | [§4.3](#43-self-referential-dtos) |
| CTL-8 | | Every Response has `from(result…)` (one Result per composed domain) and every Request has `toCommand(…)`; the controller never maps fields | [§4.4](#44-responsefrom-and-requesttocommand) |
| CTL-9 | | Every wire property and query/path parameter carries an English OpenAPI `description` | [§4.5](#45-openapi-descriptions) |
| CTL-10 | | No `@Operation` or `@Tag` | [§4.5](#45-openapi-descriptions) |
| CTL-30 | | A Response carries only the fields the frontend uses; an unused field is left out, and a new need adds it then | [§4.6](#46-response-fields) |
| CTL-31 | | A value the frontend can compute from the same Response's other fields is not sent (listed exceptions) | [§4.6](#46-response-fields) |
| CTL-11 | | Paged responses use `PaginationResponse.from`; other lists use a wrapper Response; never `Page<T>` or a raw list | [§5](#5-response-wrappers-and-json) |
| CTL-12 | | Responses serialize null fields; no `@JsonInclude(NON_NULL)` | [§5](#5-response-wrappers-and-json) |
| CTL-13 | | A count response lists every enum value, zero counts included | [§5](#5-response-wrappers-and-json) |
| CTL-14 | | No Bean Validation; validation lives in `Command.init {}` and Service `check*` | [§6](#6-validation) |
| CTL-15 | | A size or count limit is enforced by the service the bytes or the body pass through | [§6](#6-validation) |
| CTL-16 | | Controllers in `controller/`, Request/Response in `controller/rest/`, no subfolders | [§7](#7-file-layout) |
| CTL-17 | | URLs name plural resources, `/{id}` for one item, nesting at most two levels (listed exceptions) | [§8](#8-restful-api-design) |
| CTL-18 | | `@ResponseStatus` only `CREATED` for a creating POST and `NO_CONTENT` for a body-less PUT/DELETE | [§8](#8-restful-api-design) |
| CTL-19 | | No PATCH; a DELETE takes no body | [§8](#8-restful-api-design) |
| CTL-20 | | No screen- or widget-shaped endpoint; a system-administrator-only endpoint is under `/api/v1/admin` | [§8](#8-restful-api-design) |
| CTL-21 | | One read endpoint per resource: type and lookup key are filters or response fields; `/search` only for POST reads with a body | [§8](#8-restful-api-design) |
| CTL-22 | | An endpoint carries only resources its own deployable owns | [§8](#8-restful-api-design) |
| CTL-23 | | A paged endpoint defaults to `@PageableDefault(size = 20)`; no per-controller page-size constants | [§9](#9-paging) |
| CTL-24 | | Non-HTTP inbound adapters (scheduler, broker or event listener) live in their protocol directory, stay thin and compose like a controller | [§10](#10-non-http-inbound-adapters) |
| CTL-25 | | A Feign client lives in `<domain>/client/` for one using domain, `<base>/client/` for two or more; one that calls another deployable of the system only reads | [§11](#11-feign-clients) |
| CTL-26 | | Feign timeouts come from `Duration` properties; each client translates failures with its `ErrorDecoder`; no raw `FeignException` leaves a Service | [§11](#11-feign-clients) |
| CTL-27 | | An SSE endpoint declares its `@ApiResponse` schema (`oneOf` for variants) | [§12](#12-sse-endpoints) |
| CTL-28 | | A controller method converts, delegates to the Service (to each domain's Service when composing) and converts back; it never branches on a result (listed exceptions) | [§13](#13-thin-controller) |
| CTL-29 | | A wire DTO from a shared module maps through `Command.from(wireDto)` and back through `Result.toResponse()` | [§14](#14-shared-module-wire-dto-mapping) |

Shared rules apply to controllers too: imports and section banners ([STY-2, STY-6](code-style.md#2-baseline)), comments ([STY-17](code-style.md#5-comments-and-kdoc)), the plain option ([STY-27](code-style.md#10-prefer-the-plain-option)), and DTO names ([STY-50](code-style.md#16-filler-suffixes-and-dto-casing)).

## 2. Endpoint signatures

```kotlin
@RestController
@RequestMapping("/api/v1/orders")
class OrderController(private val orderService: OrderService) {

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createOrder(@RequestBody request: CreateOrderRequest, authUser: AuthUser): CreateOrderResponse =
        orderService.createOrder(request.toCommand(authUser.id)).let(CreateOrderResponse::from)

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteOrder(@PathVariable id: UUID, authUser: AuthUser) {
        orderService.deleteOrder(DeleteOrderCommand(id, authUser.id))
    }
}
```

**CTL-1** — The authenticated principal (`authUser: AuthUser`) is declared as a plain method parameter (no `@RequestHeader`); a `HandlerMethodArgumentResolver` injects it from the request. The principal already carries the access token (stored without the `Bearer ` prefix), so a downstream call takes `authUser.accessToken` / `authUser.bearerToken`. Never read the token from a static holder, and never take a separate `@RequestHeader("Authorization")` alongside the principal and hand-parse it (`removePrefix("Bearer ")`).

```kotlin
// ❌ principal + Authorization duplication + manual parsing
fun createOrder(@RequestBody req: CreateOrderRequest, @RequestHeader("Authorization") authorization: String, authUser: AuthUser) =
    orderService.createOrder(req.toCommand(authUser, authorization.removePrefix("Bearer "))).let(CreateOrderResponse::from)
// ✅ authUser.accessToken (toCommand uses authUser.accessToken / authUser.bearerToken internally)
fun createOrder(@RequestBody req: CreateOrderRequest, authUser: AuthUser) =
    orderService.createOrder(req.toCommand(authUser)).let(CreateOrderResponse::from)
```

**CTL-2** — Every endpoint is prefixed `/api/v1/...`.

**CTL-3** — `required = false` is forbidden on `@RequestParam`, `@RequestHeader` and `@RequestBody`. An optional parameter is nullable (`String?`). A `@RequestBody` is always required and has no parameter default object (`= XxxRequest()`); an empty `{}` is allowed through the DTO's field defaults.

```kotlin
// ✅ optional @RequestParam → nullable; @RequestBody → no param default (DTO field defaults handle empty {})
fun searchOrders(@RequestParam memo: String?, @RequestBody req: SearchOrdersRequest): ... = ...

// ❌ required = false (any of these), or @RequestBody param default object
fun searchOrders(
    @RequestParam(required = false) memo: String?,                   // ❌
    @RequestBody(required = false) req: SearchOrdersRequest?,        // ❌
    @RequestBody req: SearchOrdersRequest = SearchOrdersRequest(),   // ❌ duplicates DTO field defaults
)
```

## 3. Method order

**CTL-4** — Mapping methods follow CRUD order. State transitions and other action endpoints (`PUT /orders/{id}/hold`, `POST …/cancellations`, `POST`/`DELETE …/edit-lock`) are always the last group, whatever their HTTP method. A `POST` search (body required) counts as Read. It is the same rule as [SVC-21](service.md#7-method-order) for Service methods.

| Order | Category | Mapping |
|-------|----------|------|
| 1 | Create | `@PostMapping` that creates the resource |
| 2 | Read | `@GetMapping`, and a `POST` search |
| 3 | Update | `@PutMapping` on the resource |
| 4 | Delete | `@DeleteMapping` on the resource |
| 5 | Actions | state transitions and other action endpoints, any HTTP method |

`OrderController` reads in this order:

```text
POST   /orders                          createOrder
GET    /orders/{orderId}                getOrder
GET    /orders                          pageOrder
GET    /orders/counts                   countOrder
PUT    /orders/{orderId}                updateOrder
DELETE /orders/{orderId}                deleteOrder
PUT    /orders/{orderId}/hold           holdOrder
PUT    /orders/{orderId}/resume         resumeOrder
PUT    /orders/{orderId}/complete       completeOrder
POST   /orders/{orderId}/cancellations  cancelOrder
```

A controller that serves several sub-domains applies the order within each group.

## 4. Request and Response DTOs

### 4.1 Inner data classes

**CTL-5** — Every DTO a Request or Response uses is an inner data class of that Request or Response — never a top-level shared file, never another `*Request`/`*Response` (or its inner DTO) as a field or element type. The same shape in N places is declared N times.

```kotlin
data class ListOrderResponse(val orders: List<GetOrderResponse>)                          // ❌ reuses another Response
data class ListOrderResponse(val orders: List<Summary>) { data class Summary(val id: UUID) }  // ✅ own inner
data class OrderDto(...)                                                                  // ❌ top-level shared DTO file
```

A polymorphic hierarchy that several Requests or Responses each copy (a sealed root plus its `@JsonSubTypes` variants, e.g. a payment method with `Card` / `BankTransfer` variants) declares its variants as siblings of the sealed root inside the Request or Response, not nested in the root: an inner class's schema name is `<Enclosing><Simple>` ([§4.5](#45-openapi-descriptions)), so variants nested in a same-named root would share one schema name across the copies.

An inner DTO's name carries domain meaning (`ShippingAddress`) without a filler suffix; the enclosing Request or Response already names its role ([STY-50](code-style.md#16-filler-suffixes-and-dto-casing)).

Example (inner DTO + `toCommand`, duplicated shapes): [examples](examples/controller.md#ctl-5--inner-data-classes-and-duplication).

### 4.2 No entity imports

**CTL-6** — `controller/rest/*Request.kt` / `*Response.kt` never import an entity package — not as a field type, and not as a factory parameter (that allowance belongs to Command/Result only, [SVC-7](service.md#3-command-and-result)). A Response is built from a `Result` through `from(result: XxxResult)`.

| Layer | Entity / `@Embeddable` / entity-inner enum usage |
|---|---|
| `controller/rest/*Request.kt` · `*Response.kt` | **import itself forbidden** |
| `service/command/*Command.kt` · `*Result.kt` | as a `companion object { fun from(entity: Xxx) }` parameter only — never a field type ([SVC-7](service.md#3-command-and-result)) |
| `entity/` | all of it (the JPA mapping itself) |

```kotlin
data class GetOrderResponse(val shippingAddress: ShippingAddress)   // ❌ @Embeddable — jakarta.persistence leaks to the REST surface
data class GetOrderResponse(val id: UUID, val shippingAddress: ShippingAddress) {   // ✅ own inner DTO; the name stays `ShippingAddress`
    data class ShippingAddress(val recipient: String?)
    companion object { fun from(result: GetOrderResult) = GetOrderResponse(result.id, ShippingAddress(result.shippingAddress.recipient)) }
}
```

Entity-inner enums follow the same rule — use the service-layer enum (`OrderStatus`), not the entity-inner `Order.Status`.

Full three-layer mapping (Request → Command → Result → Entity): [examples](examples/controller.md#ctl-6--three-layer-mapping-without-entity-types).

### 4.3 Self-referential DTOs

**CTL-7** — springdoc cannot infer a recursive schema; without the annotation Swagger UI renders the self-referencing field as empty or broken. Declare the array schema explicitly:

```kotlin
data class CategoryTree(
    val id: UUID,
    @field:ArraySchema(schema = Schema(implementation = CategoryTree::class))
    val children: List<CategoryTree>,
)
```

The `description` for such a field goes on `arraySchema`, not `schema` (§4.5).

### 4.4 Response.from and Request.toCommand

**CTL-8** — Every `*Response` declares `companion object { fun from(result) }` and every `*Request` declares `toCommand(...)`. The controller calls `service.x(...).let(Response::from)` and never repeats the DTO's own field list (`Response(field = result.field, ...)`). A response that composes several domains (CTL-28) takes one named parameter per Result: `GetGroupResponse.from(group = groupResult, owner = ownerResult)`.

❌ `return GetOrderSummaryResponse(totalAmount = result.totalAmount, itemCount = result.itemCount, ...)` → ✅ `orderService.getOrderSummary(req.toCommand()).let(GetOrderSummaryResponse::from)`

When a non-inlinable statement (e.g. `logger.info { … }`) forces a block body, keep the block — but still build the response through `from`, never field by field. Before and after: [examples](examples/controller.md#ctl-8--responsefrom-and-requesttocommand).

### 4.5 OpenAPI descriptions

**CTL-9** — Every wire property and every query/path parameter of an externally exposed REST API carries an OpenAPI `description`, which springdoc renders into `/v3/api-docs`.

| Target | Annotation |
|--------|-----------|
| Body property — data class constructor `val` (incl. inner DTOs) | `@field:Schema(description = "...")` |
| Shared `val` declared on an **interface** (sealed hierarchy) — no backing field | `@get:Schema(description = "...")` (NOT `@field:` — it does not compile on an interface property; do NOT re-annotate the variant `override val`s) |
| `@RequestParam` / `@PathVariable` / `@RequestPart` | `@Parameter(description = "...")` |

Imports are explicit ([STY-2](code-style.md#2-baseline)): `io.swagger.v3.oas.annotations.media.Schema`, `io.swagger.v3.oas.annotations.Parameter`.

**Description text**: English, domain meaning — units, format and enum semantics where relevant (`"Total amount in minor currency units, tax included"`, `"1-based line number within the order"`, `"ISO-8601 timestamp"`). Never restate the field name (`id` → "Unique ID of the created order", NOT "id"). A `@Schema(description)` is OAS output, not a source comment, so [STY-17](code-style.md#5-comments-and-kdoc) does not govern whether it exists — its don't-translate-the-code standard still applies to the text, but the annotation is mandatory on every property.

**Do NOT annotate**:
- `@RequestBody` param → no `@Parameter` (the body DTO's own fields carry the descriptions).
- The authenticated-principal param (`authUser: AuthUser`) → no annotation — an OpenAPI customizer in the project's config hides it globally.

**CTL-10** — No `@Operation(summary/description)` and no `@Tag`. OAS descriptions live at the property and parameter level only; an SSE endpoint's description is its `@ApiResponse.description` (§12).

**Special cases**:
- Existing `@Schema(name = "X")` → merge into one `@Schema(name = "X", description = "Y")` (class level stays `@Schema`, property level `@field:Schema`) — never a second annotation. Inner-class schemas are named `<Enclosing><Simple>` by a springdoc `ModelConverter` the project registers once, so on an inner class the `name` has no effect.
- Self-referential `@field:ArraySchema` (§4.3) → put the description on `arraySchema`: `@field:ArraySchema(arraySchema = Schema(description = "..."), schema = Schema(implementation = X::class))`.
- `@field:JsonUnwrapped` wrapper (e.g. `PaginationResponse`) → leave it; describe the inner content DTO's properties.
- Enum-typed field → `@field:Schema(description = "...")` on the field; springdoc renders the allowed values.

**Scope**: the `controller/**/rest/` DTOs and controllers of every service whose API is rendered by Swagger. Not Feign `client/rest/` DTOs, not the shared `ErrorResponse` / `PaginationResponse` (a shared module does not guarantee the Swagger classpath), not a gateway without springdoc, and not internal endpoints — `springdoc.paths-to-exclude: /**/internal/**` keeps `/api/v1/internal/**` out of the document (pin it with a test).

❌ restating the field name (`"id"`) · `@Parameter` on `@RequestBody` or the principal · a new `@Operation`.
Body DTO, sealed interface and controller parameter examples: [examples](examples/controller.md#ctl-9--openapi-descriptions).

### 4.6 Response fields

**CTL-30** — A Response holds the fields the frontend actually reads, not every field its Result or entity has. A field nobody on the frontend uses is left out; when a screen later needs it, that change adds it. The rule covers every Response, new or existing: an existing field the frontend does not read is removed once the frontend side is confirmed. A smaller Response is not a licence for a screen-shaped endpoint (CTL-20): the choice is which fields an endpoint of a resource returns, not which endpoints exist.

**CTL-31** — A value the frontend can derive from the same Response's other fields is not sent: `totalPrice` from `unitPrice * quantity`, `isExpired` from `expiresAt`, `isDeleted` from `deletedAt`, `itemCount` from the list's length, `hasNext` from the page numbers. The server's entity may expose these as computed properties (REP-34); the Response does not copy them. Exceptions — the value stays in the Response when:

- the server owns the decision: a permission verdict (the frontend must not copy the permission matrix) or a value that depends on server time;
- the frontend cannot know the rule behind it: a pricing or policy calculation that lives only on the server, or one that rounds;
- the frontend lacks the value set it ranges over: the zero counts of CTL-13, because the frontend holds no copy of the backend enum.

❌ `OrderItemResponse(unitPrice, quantity, totalPrice, isExpired, expiresAt)` → ✅ `OrderItemResponse(unitPrice, quantity, expiresAt)`
Before and after: [examples](examples/controller.md#ctl-30--ctl-31--response-fields).

## 5. Response wrappers and JSON

**CTL-11** — A paged endpoint returns `PaginationResponse<T>`, built through the `PaginationResponse.from(page, ...)` factory and never constructed directly. Never return `Page<T>`. A non-paged multi-item response does not use `PaginationResponse` — it is a wrapper Response with its own inner DTO (`ListOrderResponse(val orders: List<Summary>)`), never a raw `List<*Response>`. The Service side of the same rule is [SVC-4](service.md#2-method-signatures).

| Type | Location | Fields | Use |
|---|---|---|---|
| `PaginationResponse<T>` | shared module | mirrors Spring's `Page`: `content`, `totalElements`, `totalPages`, `number`, `size`, `numberOfElements`, `sort`, `first`, `last`, `empty` | paged endpoints, through `PaginationResponse.from(page, ...)` |
| `ErrorResponse` | shared module | `type` (error code), `status`, `message`, `detail`, `url`, `timestamp` (`ZonedDateTime`, serialized with its offset — `Z` under UTC) | produced by the global `@RestControllerAdvice` only — a controller never returns it |

The default shape of `PaginationResponse`; a project may already have its own equivalent — use that:

```kotlin
class PaginationResponse<T : Any>(
    val content: List<T>,
    val totalElements: Long,
    val totalPages: Int,
    val number: Int,
    val size: Int,
    val numberOfElements: Int,
    val sort: Sort,
    val first: Boolean,
    val last: Boolean,
    val empty: Boolean,
) {
    constructor(page: Page<T>) : this(
        content = page.content,
        totalElements = page.totalElements,
        totalPages = page.totalPages,
        number = page.number,
        size = page.size,
        numberOfElements = page.numberOfElements,
        sort = page.sort,
        first = page.isFirst,
        last = page.isLast,
        empty = page.isEmpty,
    )

    companion object {
        fun <T : Any, R : Any> from(page: Page<T>, transform: (T) -> R): PaginationResponse<R> =
            PaginationResponse(page.map { transform(it) })
    }
}
```

```kotlin
@PostMapping("/search")
fun searchOrders(@RequestBody req: SearchOrdersRequest): PaginationResponse<OrderResponse> =
    orderService.searchOrders(req.toCommand()).let { PaginationResponse.from(it.page, OrderResponse::from) }
```

**CTL-12** — A Response serializes every field, `null` included; no `@JsonInclude(JsonInclude.Include.NON_NULL)` on a Response or its inner DTOs.

**CTL-13** — A count response lists every value of the counted enum, zero counts included, so its shape never depends on the data. A `GROUP BY` returns only the values that occur, so `Count*Result.from` walks the service enum and fills the rest with zero:

```kotlin
fun from(countsByStatus: Map<OrderStatus, Long>) = CountOrderResult(
    statusCounts = OrderStatus.entries.map { StatusCount(status = it, count = countsByStatus[it] ?: 0L) },
)
```

## 6. Validation

**CTL-14** — Bean Validation is forbidden: `@Valid`, `@NotBlank`, `@NotNull`, `@NotEmpty`, `@Size`, `@Positive`, `@Max`, `@Min`, `@Pattern`, `@Email` and custom `@Constraint`; never import `jakarta.validation.*`. The controller validates nothing — it routes:

| Kind | Owner |
|------|-------|
| Structural (required, length, range, format) | `Command.init {}` — Service layer |
| Business (existence, state, permissions) | Service `check*()` |

Both live in the Service layer, so their conventions do too — the validation prefixes and the not-found-ids idiom are [SVC-9 and SVC-11](service.md#4-validation).

**CTL-15** — A size or count limit is enforced by the service the bytes or the request body pass through, before anything is written. When attachments carry two limits in two services, each limit sits where its input passes: the attachment count is a property of the request body, so the order service's `CreateOrderCommand` / `UpdateOrderCommand` `init {}` checks it; the per-file size is checked by the file-storage service's upload (413), because an upload goes straight to the storage service and the bytes never pass through the order service. Never move a limit to a service the bytes or the body do not reach.

## 7. File layout

**CTL-16** — Controllers live in `controller/` and their Request/Response DTOs in `controller/rest/`, both at the root with no subfolders. An SSE emitter registry its controller streams from also stays in `controller/` (§10).

| Item | Rule |
|------|------|
| Location | `controller/` (Controllers), `controller/rest/` (Request/Response) |
| Per file | One top-level type per file ([STY-12](code-style.md#4-files-and-packages)) |
| Naming | `{Action}{Entity}Request.kt` / `{Action}{Entity}Response.kt` |

## 8. RESTful API design

Resources (nouns) go in the URL, actions (verbs) in the HTTP method. Apply first to new and modified endpoints.

**CTL-17** — A URL names a plural resource; one item is `/{id}`; a hierarchical resource is a nested path of at most two levels.

| Principle | ✅ | ❌ |
|------|----|----|
| Resource = plural noun (no verb in URL) | `/api/v1/orders` | `/api/v1/getOrder`, `/api/v1/order/create` |
| Action = HTTP method | `POST /api/v1/orders` | `POST /api/v1/orders/create` |
| Single item = `/{id}` | `GET /api/v1/orders/{id}` | `GET /api/v1/orders/get?id=...` |
| Hierarchical resource = nested path (up to two levels) | `GET /api/v1/orders/{orderId}/items` | `GET /api/v1/order-items?orderId=...` (when ownership is clear) |

A non-CRUD action (state transition, command) is an action endpoint under its resource, never a top-level verb: `PUT /api/v1/orders/{id}/hold`, `PUT /api/v1/orders/{id}/complete`, `POST /api/v1/payments/{paymentId}/refunds`. These are the last group in the controller (CTL-4).

**CTL-18** — A method states its status explicitly only when it is not 200:

| Method shape | Status |
|---|---|
| `POST` that creates a persisted resource (`create*`, `register*`, `add*`, `link*`, `issue*` of a stored session) and returns it | `@ResponseStatus(HttpStatus.CREATED)` |
| `PUT` / `DELETE` whose return type is `Unit` (no body) | `@ResponseStatus(HttpStatus.NO_CONTENT)` |
| any `GET`; a `PUT` / `DELETE` that returns a body; a `POST` that searches, verifies, signs in, calls back, or starts an asynchronous job | 200 (no annotation) |

**CTL-19** — No PATCH: a partial update also uses `PUT` (resource replacement). A `DELETE` never takes a request body — a deletion that needs one (a batch of ids, a reason) is a noun-ified `POST` (`POST /api/v1/files/deletions`, `POST /api/v1/orders/{orderId}/cancellations`), the same shape as `/files/copies` and `/files/moves`.

**CTL-20** — No screen- or widget-shaped endpoints. When a screen requirement (a dashboard widget, a view toggle) needs data, first check whether an existing resource already expresses it — `/orders` and `/orders/counts` with their filters, sort and `size`. A new endpoint is a RESTful resource of the domain that owns the data, and similar reads (three kinds of ranking; counts per member, per product and per category) are one resource, not one endpoint each. Which widgets show and how the view switches is the client's concern; the server carries only authorization per resource. An endpoint only a system administrator may call has `/api/v1/admin` in its path.

**CTL-21** — One read endpoint per resource, not per type. When one resource comes in several types or lookup keys (a payment of any method, a member looked up by ids, grade or keyword), reading or searching it is one endpoint: the type or key is a filter (`type`, `memberIds`, `grades`) or a field of the single response, never a path segment or a sibling endpoint.

| ✅ | ❌ |
|----|----|
| `GET /api/v1/payments/{id}` with an optional `card` block | `GET /api/v1/payments/{id}/card-result` |
| one `GET /api/v1/members` with `memberIds` or `grades` | a path per lookup key |
| `GET /api/v1/members/directory` with `memberIds` | `/members/directory/lookup` |
| `GET /api/v1/orders?status=PAID` | `GET /api/v1/orders/search?status=...` |

A new type adds an enum value, not an endpoint. A sub-resource read that only repeats what the parent's single read already returns is dropped (`GET /orders/{id}` carries `items[].shipments`, so there is no `GET /orders/{id}/shipments`). Filters, sort and paging are query parameters on the collection path; `/search` is reserved for `POST` reads whose filters need a body (nested arrays or maps, e.g. `POST /api/v1/admin/metrics/series/search` with `selectors[]`), and a `GET` read never ends in `/search`. The rule is about reads; a command or state transition keeps its own action endpoint (CTL-17).

**CTL-22** — An endpoint's path, request and response carry only resources its own deployable owns ([SVC-38](service.md#6-cross-domain-access)). Another deployable's data is served by that deployable's own API, and the client calls it directly (an account's sign-in history lives in `auth-service` as `GET /api/v1/accounts/{id}/sign-ins`, not on `app-service`'s user endpoint). When a decision depends on another deployable's data, read it through the HTTP client as a guard that rejects (`auth-service` refuses to delete an account while `app-service` reports groups the user still owns). Side work the change triggers in another deployable — e.g. handing over the groups a deleted user owned — travels as a broker message that deployable consumes. Never move the other deployable's data through your own endpoint.

**Accepted exceptions to CTL-17 and CTL-21** (add a project's own here, each with its reason):

- **Authentication session verbs** — `/auth/sign-in`, `/auth/sign-out`, `/auth/refresh-token`: login and logout are verbs in every client, and gateways and frontends depend on the paths.
- **Operational commands** — system initialize or reset endpoints (`/admin/system/initialize`) are not idempotent resources.
- **POST reads** — `search`, `state-counts` and batch reads take a body (CTL-21).
- **Internal snapshot reads for non-user callers** — a fixed, parameterless `GET /api/v1/internal/.../latest` polled by a machine caller may sit beside the admin `POST …/search`: the machine caller needs a snapshot, not the admin search body.
- **Existence checks** — `GET /api/v1/members/exists?email=` answers whether an address is registered; it counts soft-deleted accounts, so it cannot be a filter of the member list (CTL-21).

## 9. Paging

**CTL-23** — A paged endpoint declares its defaults with `@PageableDefault(size = 20, …)` and its default sort, written as literals on the parameter. No per-controller `DEFAULT_PAGE_SIZE` constant. The ordering's tie-breaker is [REP-12](repository.md#4-filters-and-ordering).

```kotlin
@GetMapping
fun pageOrders(
    @Parameter(description = "Filter by order status. Optional.")
    @RequestParam status: OrderStatus?,
    @ParameterObject @PageableDefault(size = 20, sort = ["createdAt"], direction = Sort.Direction.DESC) pageable: Pageable,
    authUser: AuthUser,
): PaginationResponse<OrderResponse> =
    orderService.pageOrders(PageOrderCommand(status = status, pageable = pageable, memberId = authUser.id))
        .let { PaginationResponse.from(it.page, OrderResponse::from) }
```

## 10. Non-HTTP inbound adapters

**CTL-24** — Non-HTTP inbound handlers go in a sibling directory of `controller/`, never in a Service directory. A scheduler, a broker listener and an in-process event listener are inbound adapters just as a controller is. Each stays thin — payload → Command conversion → Service delegation, no business logic — and, when a flow with no controller needs several domains' data, composes their Results the way a controller does ([CTL-28](#13-thin-controller)).

| Protocol | Directory | Example |
|---|---|---|
| HTTP | `<domain>/controller/` | `OrderController.kt` |
| Message broker | `<domain>/<broker>/` (e.g. `order/kafka/`) | `ShipOrderMessageListener.kt` |
| In-process event | `<domain>/event/` of the affected domain ([SVC-41](service.md#11-spring-events)) | `BoardEventListener.kt` |

A broker listener (`@KafkaListener`, a `MessageHandler`, …) lives in its protocol-specific directory, not `controller/`.

**Exception — an SSE emitter registry driven by a broker broadcast** stays in `controller/`. It holds the `SseEmitter`s its controller hands out and writes `controller/rest/` DTOs to them, so in the broker directory it would make that directory import web types. It still reads through the Service, never a Repository.

## 11. Feign clients

*If the project uses OpenFeign.*

**CTL-25** — A Feign client's location follows the number of domains that use it:
- used by a single domain → `<domain>/client/`;
- used across two or more domains → `<base>/client/`;
- use in bootstrap code (e.g. `system/`) does not count as a domain;
- when the using-domain count changes (1 ↔ 2+), the client moves — verified in PR review.

A Feign client interface is an outbound port, so injecting another domain's `<domain>/client/*Client.kt` directly is allowed ([SVC-17](service.md#6-cross-domain-access) does not apply).

A client that calls another deployable of the same system makes only calls the caller waits on — a read (`GET`, or a `POST …/search` read, [CTL-21](#8-restful-api-design)) or a command whose result the caller returns or whose failure must reach the caller. A state change the caller does not wait for travels over the message broker instead ([SVC-38](service.md#6-cross-domain-access)). A third-party API is outside this limit.

**CTL-26** — A Feign client's connect and read timeouts come from a properties class as `Duration`, never hard-coded. Each client registers an `ErrorDecoder` in its `config/<External>FeignConfig.kt` that maps downstream statuses to the calling domain's named exceptions (`PaymentFeignConfig` → `PaymentErrorDecoder`). A Service never lets a raw `FeignException` escape, and once the decoder exists there is no per-call-site `callXOrThrow` wrapper.

Directory structure and examples: [examples](examples/controller.md#ctl-25--ctl-26--feign-client-directory-layout).

## 12. SSE endpoints

*If the project uses Server-Sent Events.*

**CTL-27** — An SSE stream method (`produces = TEXT_EVENT_STREAM_VALUE`, returns `SseEmitter`) declares its response schema through Swagger `@ApiResponse` — springdoc cannot infer the payload from `SseEmitter`. Code skeleton: [examples](examples/controller.md#ctl-27--sse-endpoint-openapi-annotation).

Choose `schema` to match the actual wire shape:

| Wire shape | `schema` |
|---|---|
| All events share a single payload type | `Schema(implementation = OrderStreamEvent::class)` |
| Per-event variants (sealed interface + N data classes) | `Schema(oneOf = [Variant1::class, Variant2::class, ...])` |

- No `@Operation(summary/description)` (CTL-10) — method name, tag and `@ApiResponse.description` carry it.
- Keep the wire DTO (sealed interface + variants) in `controller/rest/`, separate from the service-internal domain event. `@Schema(oneOf = [...])` lists only wire variants (CTL-6).
- No `anyOf` / `allOf` — use `oneOf`.

## 13. Thin controller

**CTL-28** — A `@RestController` method body does only: ① receive the principal / `@PathVariable` / `@RequestParam` → ② `request.toCommand(...)` → ③ delegate to the Service — or, when the response composes several domains, to each domain's Service ([SVC-39](service.md#6-cross-domain-access) row 1) → ④ `Response.from(results…)` (CTL-8). Push the following out of the controller into the Service or a DTO factory:

| Leaked into controller ❌ | Belongs in |
|---|---|
| String→enum conversion (`Order.Status.valueOf(...)`) | `Command.from()` / Service (§14) |
| payload parsing and validation (split, `UUID.fromString`, required-field check) | `Command.init {}` / Service |
| branching on or computing from a Service result (`if (group.isPublic) …`, a total over two Results) | a Service method |
| `when(request.op) { … }` dispatch | a Service method |

Allowed in the controller: flowing Service results straight into `from`, extracting `authUser.id`, and passing an id from one Result into the next Service's Command (`group.ownerId`). Composition calls each domain's Service for its own data; the controller decides nothing from what comes back.

```kotlin
// ❌ parsing + enum + dispatch in the controller
fun handlePaymentCallback(@RequestBody request: PaymentCallbackRequest) {
    val (kind, paymentId) = parseCallbackContext(request.callbackContext)
    val method = runCatching { Payment.Method.valueOf(request.method) }.getOrElse { throw ... }
    when (kind) { CallbackKind.APPROVED -> ...; CallbackKind.CANCELED -> ... }
}
// ✅ controller delegates; parse/enum/dispatch live in the Service
fun handlePaymentCallback(@RequestBody request: PaymentCallbackRequest) {
    paymentCallbackService.applyCallback(request.toCommand())
}
```

This is the controller-side peer of [SVC-5](service.md#2-method-signatures) (no raw entity-field returns). More before and after (multi-way dispatch, cross-domain composition): [examples](examples/controller.md#ctl-28--thin-controller-before-and-after).

**Service ↔ Controller boundary anti-patterns**:

| ❌ | Problem |
|---|---|
| `repository.findById(...)` in a Controller | bypasses the Service layer |
| Controller calling a Service's bare `getEntity()` / `findEntityBy…()` / `listEntitiesBy…()` | those are internal service-to-service only ([SVC-2](service.md#2-method-signatures)) — an Entity never reaches the Controller |
| a Service method returning `Response` (or an Entity) to the Controller | the Service returns `Result`; the Response is built by `Response.from(result)` (CTL-8) |
| a Service method returning `List<*Result>` | wrapper Result and Response ([SVC-4](service.md#2-method-signatures), CTL-11) |
| a Service injecting another domain's Service only to decorate its Result for a response | the controller composes both Results ([SVC-39](service.md#6-cross-domain-access) row 1) |

**Exception — a post-commit external call**: a controller may take what the Service's write returns (e.g. the storage files an edit orphaned) and delete them through another Service after the edit commits, so the edit's `@Transactional` never holds the storage call ([TX-2](transactions.md#3-external-calls-and-compensation)).

**Exception — the plain-option hoist**: a controller may call one remote reader before its Service and pass the answer in the Command, so the Service stays one plain `@Transactional` instead of wrapping the remote call in an `inTx` split ([STY-27](code-style.md#10-prefer-the-plain-option)). The reader call carries no decision of its own — the Service still validates against it.

## 14. Shared-module wire DTO mapping

**CTL-29** — An inbound adapter that receives a wire DTO from a shared module cannot add `toCommand()` to it (the shared module does not see service Commands). The mapping (copying, truncating, and any raw `String`→enum resolution) goes in the service-layer `Command.from(wireDto)` factory — never in the adapter body or an adapter file-level extension. A raw `String` that names an enum resolves there too, and an invalid value throws a named domain exception ([SVC-14](service.md#5-exceptions-and-failure-forms)), not a raw `IllegalArgumentException`; a wire field typed as the shared module's enum itself is already checked by deserialization.

**Outbound mirror** — a controller that returns a shared-module wire DTO cannot call `Response.from(result)` (CTL-8) either, because the shared module does not see the service `Result`. The `Result` builds it instead with `toResponse()`, on the same service-side boundary as `Command.from(wireDto)` (`ListMemberResult.toResponse()`).

The rule applies to every inbound adapter, not just HTTP (§10). `ShipOrderCommand.from(ShipOrderMessage)` copies the message and cuts its display strings to the column lengths, called by `OrderService.shipOrder` for each message `ShipOrderMessageListener` consumes; an HTTP instance is an internal callback controller receiving a shared `PaymentCompletedNotification` → `CompletePaymentCommand.from(notification)`.

```kotlin
// ❌ mapping in the adapter body (every other adapter of the same DTO repeats it)
private fun onMessage(message: Message) {
    val payload = objectMapper.readValue(message.data, ShipOrderMessage::class.java)
    shipmentRepository.save(Shipment(carrierMemo = payload.carrierMemo?.take(Shipment.CARRIER_MEMO_LENGTH), ...))
}
// ✅ adapter delegates; the mapping lives in Command.from, which OrderService.shipOrder calls
orderService.shipOrder(objectMapper.readValue(message.data, ShipOrderMessage::class.java))
// ShipOrderCommand companion (service layer — may import the shared wire DTO; the reverse is impossible)
fun from(message: ShipOrderMessage) = ShipOrderCommand(
    orderId = message.orderId,
    carrierMemo = message.carrierMemo?.take(Shipment.CARRIER_MEMO_LENGTH), ...)   // display strings cut to the column length
```
