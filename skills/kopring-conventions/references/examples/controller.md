# Controller — Worked Examples

Rule text, conditions and exceptions live in [controller.md](../controller.md); this file only illustrates them.

## CTL-5 — Inner data classes and duplication

```kotlin
// ✅ inner DTO inside the Request; ❌ would be a top-level `data class Item(...)` in its own file
data class CreateOrderRequest(val memo: String?, val items: List<Item>) {
    data class Item(val productId: UUID, val quantity: Int)
    fun toCommand(memberId: UUID) = CreateOrderCommand(memo, items.map { CreateOrderCommand.Item(it.productId, it.quantity) }, memberId)
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
        shippingAddress = CreateOrderCommand.ShippingAddress(shippingAddress.recipient, shippingAddress.zipCode, shippingAddress.phone),
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
            shippingAddress = ShippingAddress(order.shippingAddress.recipient, order.shippingAddress.zipCode, order.shippingAddress.phone),
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

    return GetGroupResult.from(group = group, owner = userService.getUser(GetUserCommand(userId = group.owner.id)))
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
