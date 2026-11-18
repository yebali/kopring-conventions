# Controller — Worked Examples

Rule text, conditions and exceptions live in [controller.md](../controller.md); this file only illustrates them. The KDoc summaries of [STY-16](../code-style.md#5-comments-and-kdoc) are left out so the rule shown stays in focus; production code carries them.

## CTL-5 — Inner data classes and duplication

```kotlin
// ✅ inner DTO inside the Request; ❌ would be a top-level `data class Item(...)` in its own file
data class CreateOrderRequest(val memo: String?, val items: List<Item>) {
    data class Item(val productId: UUID, val quantity: Int)
    fun toCommand(memberId: UUID) = CreateOrderCommand(
        memo = memo,
        items = items.map { CreateOrderCommand.Item(productId = it.productId, quantity = it.quantity) },
        memberId = memberId,
    )
}
```

Each Result/Response declares its own copy of the same shape:

```kotlin
// ✅ duplication allowed — each Result/Response declares its own
data class GetOrderItemResult(val id: UUID, val name: String, val options: List<Option>?) {
    data class Option(val name: String, val value: String?)
    companion object { fun from(...) = ... }
}
data class ListOrderItemsResult(val items: List<Item>) {
    data class Item(val id: UUID, val name: String)
    data class Option(val name: String, val value: String?)     // duplication OK
    companion object { fun from(...) = ... }
}

// ❌ one shared top-level DTO file consumed by both
data class OrderItemDto(...)
```

## CTL-6 — Three-layer mapping without entity types

`ShippingAddress` is an `@Embeddable` on `Order`. Each layer declares its own — the name stays `ShippingAddress` in all three (the declaring class differs, so there is no collision, and `ShippingAddressDto` would be a filler suffix, [STY-50](../code-style.md#16-filler-suffixes-and-dto-casing)). The Command and Result side is [SVC-7](../service.md#3-command-and-result).

```kotlin
// ❌ Bad — @Embeddable leaks into the HTTP contract (entity adds a column → silent breaking schema change)
data class CreateOrderRequest(val shippingAddress: ShippingAddress, ...)
data class GetOrderResponse(val shippingAddress: ShippingAddress, ...)

// ✅ Good — Request: own inner DTO, no entity import at all
data class CreateOrderRequest(val shippingAddress: ShippingAddress, ...) {
    data class ShippingAddress(val recipient: String?, val zipCode: String?, val phone: String?)
    fun toCommand(authUser: AuthUser) = CreateOrderCommand(
        shippingAddress = CreateOrderCommand.ShippingAddress(
            recipient = shippingAddress.recipient,
            zipCode = shippingAddress.zipCode,
            phone = shippingAddress.phone,
        ),
        ...
    )
}

// ✅ Good — Command: own inner DTO too
data class CreateOrderCommand(val shippingAddress: ShippingAddress, ...) {
    data class ShippingAddress(val recipient: String?, val zipCode: String?, val phone: String?)
}

// ✅ Good — Result: entity imported ONLY as the from() parameter, never as a field type
data class GetOrderResult(val shippingAddress: ShippingAddress, ...) {
    data class ShippingAddress(val recipient: String?, val zipCode: String?, val phone: String?)
    companion object {
        fun from(order: Order, ...) = GetOrderResult(
            shippingAddress = ShippingAddress(
                recipient = order.shippingAddress.recipient,
                zipCode = order.shippingAddress.zipCode,
                phone = order.shippingAddress.phone,
            ),
            ...
        )
    }
}
```

## CTL-8 — Response.from and Request.toCommand

```kotlin
// ❌ controller hand-maps every field (no from())
fun getOrderSummary(@RequestBody req: GetOrderSummaryRequest): GetOrderSummaryResponse {
    val result = orderService.getOrderSummary(GetOrderSummaryCommand(req.orderId, req.currency))
    return GetOrderSummaryResponse(totalAmount = result.totalAmount, itemCount = result.itemCount, ...)
}
// ✅ Request.toCommand + Response.from
fun getOrderSummary(@RequestBody req: GetOrderSummaryRequest): GetOrderSummaryResponse =
    orderService.getOrderSummary(req.toCommand()).let(GetOrderSummaryResponse::from)
```

## CTL-9 — OpenAPI descriptions

```kotlin
// ✅ body DTO — every val annotated, domain meaning
data class GetOrderResponse(
    @field:Schema(description = "Unique ID of the order")
    val orderId: UUID,
    @field:Schema(description = "Current order status (PENDING, PAID, SHIPPED, CANCELED)")
    val status: OrderStatus,
)
// ✅ sealed interface — shared prop on the interface (@get:), variant-only on the variant (@field:)
sealed interface GetPaymentResponse {
    @get:Schema(description = "Unique ID of the payment")
    val id: UUID

    data class Card(
        override val id: UUID,
        @field:Schema(description = "Last four digits of the card number, null if not disclosed")
        val cardLast4: String?,
    ) : GetPaymentResponse
}
// ✅ controller param (principal hidden, @RequestBody unannotated)
@GetMapping("/{orderId}")
fun getOrder(
    @Parameter(description = "ID of the order to retrieve")
    @PathVariable orderId: UUID,
    authUser: AuthUser,
): GetOrderResponse = ...
// ❌ restating the field name ("id"); @Parameter on @RequestBody or the principal; a new @Operation
```

## CTL-31 · CTL-32 — Response fields

```kotlin
// ❌ values the frontend derives without a definition, and an unread field copied from the Result
data class ListOrderItemResponse(
    val items: List<Item>,
    val itemCount: Int,              // items.size
    val totalQuantity: Int,          // items.sumOf { it.quantity }
) {
    data class Item(
        val id: UUID,
        val quantity: Int,
        val deletedAt: Instant?,
        val isDeleted: Boolean,      // deletedAt != null
        val internalMemo: String?,   // no screen reads it (CTL-32)
    )
}

// ✅ what the frontend reads; it counts, sums and checks presence itself
data class ListOrderItemResponse(
    val items: List<Item>,
) {
    data class Item(
        val id: UUID,
        val quantity: Int,
        val deletedAt: Instant?,
    )
}

// ✅ sent: deriving these needs a definition
data class GetOrderResponse(
    val id: UUID,
    val lines: List<Line>,           // nested, so lines.size is the line count
    val shippedLineCount: Int,       // a count over the lines a condition selects, and no screen lists those lines
    val fulfillmentProgress: Int,    // the zero case and rounding are the server's
    val totalPrice: Long,            // discount and tax rules live on the server
    val isExpired: Boolean,          // judged against the server's clock
    val canCancel: Boolean,          // permission and state verdict
) {
    data class Line(
        val id: UUID,
        val quantity: Int,
        val shippedAt: Instant?,
    )
}
```

## CTL-25 · CTL-26 — Feign client directory layout

Directory structure (identical for single-domain and cross-cutting clients):

```
<container>/client/
├── <External>Client.kt              ← @FeignClient interface (outbound port)
├── config/
│   ├── <External>FeignConfig.kt     ← registers the ErrorDecoder (CTL-26); a RequestInterceptor when needed
│   └── <External>ErrorDecoder.kt    ← downstream status → the calling domain's named exception
└── rest/
    ├── *Request.kt
    └── *Response.kt
```

`<container>` = `<domain>` (single-domain usage) or `<base>` (cross-cutting across 2+ domains).

| Client | Using domains | Location |
|---|---|---|
| `PaymentClient` | order (1) | `order/client/` |
| `MemberClient` | order + payment (2) | `<base>/client/` |
| `MemberClient` after payment stops using it | order (1) | moves to `order/client/` |

## CTL-27 — SSE endpoint OpenAPI annotation

```kotlin
@ApiResponse(
    responseCode = "200",
    description = "SSE event stream — <event order + termination summary>",
    content = [Content(
        mediaType = MediaType.TEXT_EVENT_STREAM_VALUE,
        schema = Schema(/* see the schema table of CTL-27 */),
    )],
)
@PostMapping(produces = [MediaType.TEXT_EVENT_STREAM_VALUE], ...)
fun streamOrderEvents(...): SseEmitter { ... }
```

## CTL-18 · CTL-19 — Status codes and PUT forms

```kotlin
// ✅ creating POST: 201 with a host-less Location built from the Result's id
@PostMapping
fun createOrder(
    @RequestBody request: CreateOrderRequest,
    authUser: AuthUser,
    httpRequest: HttpServletRequest,
): ResponseEntity<CreateOrderResponse> =
    orderService.createOrder(request.toCommand(authUser.id)).let { result ->
        ResponseEntity.created(URI.create("${httpRequest.contextPath}/api/v1/orders/${result.id}"))
            .body(CreateOrderResponse.from(result))
    }

// ✅ form ①: the complete body; If-Match becomes the Command's version (TX-16); 204 without ETag
@PutMapping("/{orderId}")
@ResponseStatus(HttpStatus.NO_CONTENT)
fun updateOrder(
    @PathVariable orderId: UUID,
    @RequestHeader(HttpHeaders.IF_MATCH) ifMatch: String?,
    @RequestBody request: UpdateOrderRequest,
) {
    orderService.updateOrder(request.toCommand(orderId = orderId, ifMatch = ifMatch))
}

data class UpdateOrderRequest(val shippingAddress: String, val memo: String? = null) {
    fun toCommand(orderId: UUID, ifMatch: String?) = UpdateOrderCommand(
        orderId = orderId,
        version = ifMatchVersion(ifMatch),
        shippingAddress = shippingAddress,
        memo = memo,
    )
}

// ✅ form ③: the target state in the body; the current state again is a 204 no-op, a forbidden transition 409
@PutMapping("/{orderId}/status")
@ResponseStatus(HttpStatus.NO_CONTENT)
fun updateOrderStatus(@PathVariable orderId: UUID, @RequestBody request: UpdateOrderStatusRequest) {
    orderService.updateOrderStatus(request.toCommand(orderId))
}

// ✅ form ④: the Service decides create versus replace; the controller maps `created` to 201 or 204
@PutMapping("/{orderId}/participants/{memberId}")
fun upsertOrderParticipant(
    @PathVariable orderId: UUID,
    @PathVariable memberId: UUID,
    @RequestBody request: UpsertOrderParticipantRequest,
): ResponseEntity<OrderParticipantResponse> =
    orderService.upsertOrderParticipant(request.toCommand(orderId = orderId, memberId = memberId)).let { result ->
        if (result.created) {
            ResponseEntity.status(HttpStatus.CREATED).body(OrderParticipantResponse.from(result))
        } else {
            ResponseEntity.noContent().build()
        }
    }
```

`memo` omitted and `"memo": null` both clear the memo. `ifMatchVersion` is the project's one shared `If-Match` parser: a missing header throws the common precondition-required exception (428), a value that is not a quoted version fails structural validation (400). `created: Boolean` is a domain outcome of the Result, never an HTTP status.

## CTL-28 — Thin controller before and after

### Multi-way dispatch + field assembly leaked into the controller

❌ Bad — operation dispatch + required-field validation + Item assembly all in the controller.
```kotlin
@PostMapping("/payment-callbacks")
fun handleCallback(@RequestBody request: PaymentCallbackRequest): PaymentCallbackResponse =
    PaymentCallbackResponse(
        event = request.event,
        results = when (request.event) {                        // dispatch in controller
            PaymentCallbackEvent.APPROVED -> handleApproved(request)
            PaymentCallbackEvent.CANCELED -> handleCanceled(request)
            // … REFUNDED
        },
    )
private fun handleApproved(request: PaymentCallbackRequest): List<PaymentCallbackResponse.Item> = listOf(
    paymentService.approvePayment(
        ApprovePaymentCommand(
            paymentId = request.paymentIds?.firstOrNull() ?: throw InvalidPaymentCallbackException(request.event, "paymentIds"), // validation
            approvalNumber = request.approvalNumber ?: throw InvalidPaymentCallbackException(request.event, "approvalNumber"),
            // …
        ),
    ).let { PaymentCallbackResponse.Item(paymentId = it.id, status = it.status, approvedAt = it.approvedAt) }, // assembly
)
// + handleCanceled / handleRefunded
```

✅ Good — dispatch + validation + assembly all in the Service; controller is one line.
```kotlin
@PostMapping("/payment-callbacks")
fun handleCallback(@RequestBody request: PaymentCallbackRequest): PaymentCallbackResponse =
    paymentCallbackService.handleCallback(request.toCommand())
        .let(PaymentCallbackResponse::from)
// PaymentCallbackService.handleCallback(command) owns when(event) + the private handleXxx + InvalidPaymentCallbackException
// PaymentCallbackResponse.from(result) owns Item assembly
```

### Cross-domain composition

✅ Good — each Service reads only its own domain; the controller passes the owner id along and composes the two Results ([SVC-39](../service.md#6-cross-domain-access) row 1).
```kotlin
@GetMapping("/{groupId}")
fun getGroup(@PathVariable groupId: UUID, authUser: AuthUser): GetGroupResponse {
    val group = groupService.getGroup(GetGroupCommand(groupId = groupId, userId = authUser.id))

    return GetGroupResponse.from(group = group, owner = userService.getUser(GetUserCommand(userId = group.ownerId)))
}
```

❌ Bad — `GroupService` injects `UserService` only to fold the owner into its Result for the response.
```kotlin
@Transactional(readOnly = true)
fun getGroup(command: GetGroupCommand): GetGroupResult {
    val group = getEntity(command.groupId)

    return GetGroupResult.from(group = group, owner = userService.getUser(GetUserCommand(userId = group.ownerId)))
}
```

❌ Bad — the controller decides from a Result; the branch belongs in a Service.
```kotlin
fun getGroup(@PathVariable groupId: UUID, authUser: AuthUser): GetGroupResponse {
    val group = groupService.getGroup(GetGroupCommand(groupId = groupId, userId = authUser.id))
    val boards = if (group.isPublic) boardService.listBoards(ListBoardsCommand(groupId = groupId)) else null   // decision in the controller

    return GetGroupResponse.from(group = group, boards = boards)
}
```
