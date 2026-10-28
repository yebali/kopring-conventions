# Code Style — Worked Examples

Rule text, exceptions and carve-outs live in [code-style.md](../code-style.md); this file carries only `❌ Bad` / `✅ Good` code.

## STY-1 — Logger base class

```kotlin
// ✅ Good — extend the Logger base class, log through lambda-form calls
class OrderService : Logger() {
    fun ship(id: UUID) {
        logger.info { "Order shipped: id=$id" }
    }
}

// ❌ Bad — never use LoggerFactory
private val log = LoggerFactory.getLogger(javaClass)
```

## STY-7 — Not-null assertion

```kotlin
// ❌ Bad — a thrown !! leaves only an NPE
val refreshed = orderRepository.findOrderById(order.id)!!
assertThat(saved!!.name).isEqualTo("keyboard")
val item = target.findItemByLineNo(0)!!

// ✅ Good — the message separates a missing fixture from a production regression
val refreshed = requireNotNull(orderRepository.findOrderById(order.id)) { "Order not found after refresh: ${order.id}" }
val unwrapped = requireNotNull(saved) { "Product not saved: name=$name" }
assertThat(unwrapped.name).isEqualTo("keyboard")
val item = requireNotNull(target.findItemByLineNo(0)) { "item at lineNo 0 missing" }
```

`assertThat(x!!).isXxx()` is the anti-pattern to watch for: unwrap with `requireNotNull` **before** asserting.

## STY-8 — Unchecked cast

```kotlin
// ❌ Bad — raw List covered by @Suppress
@Suppress("UNCHECKED_CAST")
val orders = entityManager.createNativeQuery(sql, Order::class.java)
    .resultList as List<Order>

// ✅ Good — filterIsInstance produces a real List<Order>
val orders = entityManager.createNativeQuery(sql, Order::class.java)
    .resultList
    .filterIsInstance<Order>()

// ❌ Bad — Jackson raw Map cast
@Suppress("UNCHECKED_CAST")
val map = objectMapper.readValue(body, Map::class.java) as Map<String, Any>

// ✅ Good — TypeReference preserves the generic type
val map = objectMapper.readValue(body, object : TypeReference<Map<String, Any>>() {})
```

## STY-9 — Single-expression trailing lambda

```kotlin
// ❌ Bad — a short message lambda split across three lines
shippingAddress = requireNotNull(request.shippingAddress) {
    "shippingAddress must be present for DELIVERY"
},

// ✅ Good — one line
shippingAddress = requireNotNull(request.shippingAddress) { "shippingAddress must be present for DELIVERY" },

// ✅ Good — unavoidable: the ARGUMENT is multi-line, not the message lambda
val imagePath = requireNotNull(
    storageClient.uploadFiles(sessionId = sessionId, files = files).files.firstOrNull(),
) { "Product image upload stored no file: sessionId=$sessionId" }.path

// ❌ Bad — any other single-expression lambda whose merged line is ≤ 120 characters
exportExecutor.execute {
    runExport(exportCommand)
}

// ✅ Good — one line
exportExecutor.execute { runExport(exportCommand) }

// ✅ Good — merged line would exceed 120 characters, so it stays on three lines
payment = result.payment?.let {
    Payment(method = it.method, amount = it.amount, approvedAt = it.approvedAt, approvedBy = it.approvedBy)
},
```

## STY-10 — Blank line before the final return

```kotlin
// ❌ Bad — the final return is glued to the statement above
fun createOrder(command: CreateOrderCommand): OrderResult {
    val order = orderRepository.save(Order.from(command))
    eventPublisher.publishEvent(OrderCreatedEvent(order.id))
    return OrderResult.from(order)
}

// ✅ Good
fun createOrder(command: CreateOrderCommand): OrderResult {
    val order = orderRepository.save(Order.from(command))
    eventPublisher.publishEvent(OrderCreatedEvent(order.id))

    return OrderResult.from(order)
}
```

## STY-11 — Named arguments

```kotlin
// ❌ Bad — positional; swapping two arguments still compiles
createMember(name, email, true, false)
order.assign(memberId, warehouseId)

// ✅ Good
createMember(name = name, email = email, active = true, admin = false)
order.assign(memberId = memberId, warehouseId = warehouseId)

// ✅ Exempt — lambda is the only argument
list.map { it.name }
// ✅ Exempt — other args named, lambda stays trailing
executor.execute(key = key) { process() }
// ✅ Exempt — QueryDSL / fluent builder chain
qOrder.status.eq(status).and(qOrder.deleted.isFalse)
// ✅ Exempt — symmetric comparison/math function and vararg call
maxOf(0, offset)
lockPaths(source, target)
```

## STY-16 · STY-17 — Summaries and line comments

```kotlin
// ❌ Bad — no class summary, every executable line commented even when self-explanatory
class Shipment(...)

enum class ShipmentStatus { READY, SHIPPED }

fun assign(warehouseId: UUID) {
    val key = ShipmentKey(orderId, lineNo) // 주문-품목 단위 배정 키 생성
    queue.push(key) // 큐에 넣는다
}

// ✅ Good — one-line class summary, self-explanatory function left bare
/** 창고에 배정된 주문 품목 단위의 출고 작업. */
@Entity
class Shipment(...)

enum class ShipmentStatus { READY, SHIPPED }

fun assign(warehouseId: UUID) {
    val key = ShipmentKey(orderId, lineNo)
    queue.push(key)
}
```

**Comment only where the logic is genuinely easy to get wrong:**

```kotlin
// ❌ trivial lines commented, the one line that actually needs it left bare
.filterNot { it == withdrawingMemberId } // 탈퇴 대상 본인 제외
val order = orderRepository.save(...) // order 행 insert
if (local.updatedAt == remote.updatedAt) return remote

// ✅ self-explanatory lines bare, the non-obvious tie-break explained
.filterNot { it == withdrawingMemberId }
val order = orderRepository.save(...)
if (local.updatedAt == remote.updatedAt) return remote // 동시 갱신 시 remote 우선(LWW), 회원 id 는 tie-break 로 쓰지 않는다
```

## STY-17 — Comment ktlint traps

```kotlin
// ❌ column-aligned (no-multi-spaces) + comment after a lambda's opening brace (function-literal)
checkMember(command.memberId)
val order = transactionRunner.inTx {                       // 주문번호 채번은 주문 저장이 실패해도 롤백하지 않는다
    orderRepository.save(...)
}

// ✅ exactly one space; the lambda's comment moves to its own line above the statement
checkMember(command.memberId)
// 주문번호 채번은 주문 저장이 실패해도 롤백하지 않는다
val order = transactionRunner.inTx {
    orderRepository.save(...)
}
```

## STY-19 — Inline single-use intermediates

**(a) Inline the result:**

```kotlin
// ❌ Bad
fun createOrder(request: CreateOrderRequest, authUser: AuthUser): OrderResponse {
    val result = orderService.createOrder(request.toCommand(authUser))
    return OrderResponse.from(result)
}

// ✅ Good — expression body + .let(::from)
fun createOrder(request: CreateOrderRequest, authUser: AuthUser): OrderResponse =
    orderService.createOrder(request.toCommand(authUser))
        .let(OrderResponse::from)
```

**(b) Inline the argument** — with ktlint `max_line_length` off, length is never a reason to extract a `val`; wrap inside the argument instead:

```kotlin
// ❌ Bad — `cmd` exists solely for the uploadProductImages call
val cmd = UploadProductImagesCommand(sessionId = sessionId, files = files)
val saved = imageUploader.uploadProductImages(cmd).files.firstOrNull()
    ?: throw ProductImageNotFoundException(productId)

// ✅ Good — built at the argument position
val saved = imageUploader.uploadProductImages(
    UploadProductImagesCommand(sessionId = sessionId, files = files),
).files.firstOrNull()
    ?: throw ProductImageNotFoundException(productId)
```

**(c) Chain the guards** — fold `if (…) throw` into the chain with stdlib (`ifEmpty {}` / `takeIf {} ?: throw` / `?:`); no custom helper (STY-26):

```kotlin
// ❌ Bad — an if-throw block breaking the flow (the unfolded form of the line below)
if (path.isEmpty()) {
    throw PathRequiredException()
}
val virtualPath = "${path.trimEnd('/')}/$fileName"

// ✅ Good — the guard folded into the expression with ifEmpty {}
val virtualPath = "${path.ifEmpty { throw PathRequiredException() }.trimEnd('/')}/$fileName"
```

## STY-20 — No plumbing parameters

```kotlin
// ❌ Bad — memberId is already reachable from the order that is also passed
if (alternativeWarehouseIds.isEmpty()) return keepPending(order = order, memberId = memberId)

private fun keepPending(order: Order, memberId: UUID): OrderReassignedEvent? {
    logger.warn { "Order reassignment skipped: id=${order.id}, memberId=$memberId" }

    return null
}

// ✅ Good — the callee reads it off order itself
if (alternativeWarehouseIds.isEmpty()) return keepPending(order)

private fun keepPending(order: Order): OrderReassignedEvent? {
    logger.warn { "Order reassignment skipped: id=${order.id}, memberId=${order.memberId}" }

    return null
}
```

## STY-25 · STY-26 — Latest API and standard library

```kotlin
// ❌ Bad — verbose boilerplate, dated API
val result = ArrayList<String>()
for (member in members) {
    if (member.active) {
        result.add(member.name)
    }
}
return result

// ✅ Good — stdlib, intent visible
return members.filter { it.active }.map { it.name }
```

## STY-34 — Entity change logging

```kotlin
// ✅ Good — guard → mutate → log only the fields this method assigns, at their current value
fun hold() {
    if (status != OrderStatus.PAID) throw OrderInvalidStatusTransitionException(orderId = id, currentStatus = status, targetStatus = OrderStatus.ON_HOLD)
    status = OrderStatus.ON_HOLD
    logger.info { "Order held: id=$id, status=$status" }
}

// ❌ Bad — separate companion logger, or a vague message with no change detail,
//          or a reflection dump of every field
fun hold() {
    status = OrderStatus.ON_HOLD
    logger.info { "order changed" }
}
```

## STY-50 — No filler suffixes

```kotlin
// ❌ Bad — the Payload suffix adds nothing
data class CreateOrderRequest(
    val items: List<ItemPayload>,
) {
    data class ItemPayload(val productId: UUID, ...)
}

data class RegisterProductRequest(
    val seller: SellerPayload? = null,
) {
    data class SellerPayload(val name: String? = null, ...)
}

// ✅ Good — the outer class is already "Request", so the inner is obviously a payload
data class CreateOrderRequest(
    val items: List<Item>,
) {
    data class Item(val productId: UUID, ...)
}

data class RegisterProductRequest(
    val seller: Seller? = null,
) {
    data class Seller(val name: String? = null, ...)
}
```

| Prefer | Avoid |
|---|---|
| `Seller` (inner of `RegisterProductRequest`) | `SellerPayload` · `SellerDto` · `SellerData` |
| `Item` (inner of `CreateOrderRequest`) | `ItemPayload` · `ItemInfo` |
| `ItemDto` (Result inner) | `ItemInfoDto` (`Info` is noise) |
| `ItemDto` (collision avoidance) | `ItemDTO` (all-caps forbidden) |
