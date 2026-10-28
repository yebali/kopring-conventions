# Service — Worked Examples

Rule text and exceptions live in [service.md](../service.md) and [transactions.md](../transactions.md); each heading names the rule IDs it illustrates.

## SVC-9 — Validation method naming

```kotlin
private fun checkNotCanceled(order: Order) { if (order.status == Order.Status.CANCELED) throw OrderAlreadyCanceledException(order.id) }
fun verifyResetToken(token: UUID): VerifyResetTokenResult = VerifyResetTokenResult(isValid = repo.findByIdOrNull(token) != null)
fun canCancel(memberId: UUID, orderId: UUID): Boolean = ...
// ❌ validate* prefix forbidden
private fun validateNotCanceled(order: Order) { ... }
```

## SVC-10 · SVC-11 — Structural checks and every missing id

Canonical "reject unknown ids" idiom — collect **all** missing ids, then throw the domain's named exception:

```kotlin
// ✅ structural check stays in the Command
data class CreateOrderCommand(val productIds: List<UUID>) {
    init { if (productIds.isEmpty()) throw EmptyOrderItemsException() }
}
// ✅ business check is a private Service check* (in ProductService — its own domain's exception, SVC-14)
private fun checkProductsExist(ids: List<UUID>) {
    val missing = ids - productRepository.findAllById(ids).map { it.id }.toSet()
    if (missing.isNotEmpty()) throw ProductNotFoundException(missing)
}
// ❌ throws on the first miss — the client learns one bad id per round trip
ids.firstOrNull { it !in found }?.let { throw ProductNotFoundException(it) }
```

## SVC-14 · SVC-15 — Exception declaration

```kotlin
// ✅ named domain subclass + domain ErrorCode
class OrderNotFoundException(orderId: UUID, cause: Throwable? = null) : EntityNotFoundException(
    errorCode = ErrorCode.ORDER_NOT_FOUND,
    message = "Order not found: orderId=$orderId",
    cause = cause,
)
// ✅ ErrorCode entries are domain-prefixed
ORDER_NOT_FOUND("ORDER-1000", HttpStatus.NOT_FOUND.value(), "Order not found"),
ORDER_ALREADY_CANCELED("ORDER-1001", HttpStatus.CONFLICT.value(), "Order is already canceled"),

// ❌ SVC-15
throw IllegalArgumentException("invalid id")
throw BusinessException(CommonErrorCode.UNEXPECTED, "...")
require(id != null) { "id required" }
// ❌ generic code shared across domains (hypothetical entry — the number is a placeholder)
ENTITY_NOT_FOUND("COMMON-XXXX", HttpStatus.NOT_FOUND.value(), "Entity not found"),
```

## SVC-2 · SVC-17 — Cross-domain entity-returning method

Domain B exposes an entity-returning method, and domain A calls it instead of injecting B's Repository directly.

```kotlin
// ✅ the member domain exposes the entity-returning method for cross-domain use
@Service
class MemberService(private val memberRepository: MemberRepository) : Logger() {
    @Transactional(readOnly = true)
    fun getEntity(id: UUID): Member =
        memberRepository.findByIdAndDeletedAtIsNull(id) ?: throw MemberNotFoundException(id)
}
// ✅ the order domain calls it instead of injecting MemberRepository
@Service
class OrderService(private val memberService: MemberService, private val orderRepository: OrderRepository) {
    @Transactional
    fun createOrder(command: CreateOrderCommand): OrderResult {
        val member = memberService.getEntity(command.memberId)
        return OrderResult.from(orderRepository.save(Order(member = member)))
    }
}
```

## SVC-20 — Breaking a bean cycle without `@Lazy`

```kotlin
// ❌ Bad — @Lazy hides the cycle
class OrderService(@param:Lazy private val paymentService: PaymentService) { ... }
class PaymentService(private val orderService: OrderService) { ... }

// ✅ Good — technique (2): move the read-time decoration up to the controller
class OrderController(private val orderService: OrderService, private val paymentService: PaymentService) {
    fun getOrder(orderId: UUID, authUser: AuthUser): OrderResponse =
        OrderResponse.from(
            result = orderService.getOrder(GetOrderCommand(orderId = orderId, memberId = authUser.id)),   // knows nothing about payments
            payments = paymentService.listPayments(ListPaymentsCommand(orderId = orderId)),             // composed in the response
        )
}
class OrderService(private val orderRepository: OrderRepository, ...) { ... }   // no paymentService edge
```

## SVC-23 — Two-stage saveAll

Two-stage `saveAll` when the batch has an FK dependency:

```kotlin
// ❌ loop save — N elements become 2N round trips, and Hibernate's JDBC batch never engages
command.orders.forEach { row ->
    val order = orderRepository.save(newOrder(row))
    orderItemRepository.save(OrderItem(order, ...))
}
// ✅ parent saveAll, then child saveAll
val orders = orderRepository.saveAll(command.orders.map { newOrder(it) })
orderItemRepository.saveAll(command.orders.zip(orders) { row, order -> OrderItem(order, ...) })
```

## SVC-27 · SVC-28 — EnumMapper

```kotlin
// Packet — shared module packet/type/ (protocol adapter only; carries the external wire code)
enum class OrderStatus(val code: Int) { PLACED(1001), CANCELLED(1002) ; @JsonValue val value = code }
// Message — shared module message/type/ (name-serialized, message broker)
// Service — {module}/.../enumerate/
enum class OrderStatus { PLACED, CANCELED }
// Entity — nested in the @Entity class
@Entity
class Order {
    @Enumerated(EnumType.STRING) val status: Status
    enum class Status { PLACED, CANCELED }
}

object OrderEnumMapper {
    fun ServiceOrderStatus.toEntityOrderStatus(): Order.Status = when (this) {   // no `else` — drift becomes a compile error
        ServiceOrderStatus.PLACED -> Order.Status.PLACED
        ServiceOrderStatus.CANCELED -> Order.Status.CANCELED
    }
}
```

## SVC-30 · SVC-31 — Service vs Component

```kotlin
// ✅ a domain use case is a *Service
@Service
class OrderService(private val orderRepository: OrderRepository) : Logger() {
    @Transactional(readOnly = true) fun getEntity(orderId: UUID): Order = ...
}
// ✅ drop "Template" → "AdvisoryLock" names the lock, not the bean acquiring it, so the suffix stays
@Component
class AdvisoryLockTemplate(private val entityManager: EntityManager) { fun acquireLocks(exclusiveKeys: List<String>, sharedKeys: List<String> = emptyList()) { ... } }
// ✅ drop nothing — the bare noun already names the bean
@Component
class InvoiceGenerator(...) { fun generate(command: GenerateInvoiceCommand): GenerateInvoiceResult { ... } }
// ❌ naming an infrastructure wrapper *Service confuses it with a domain service
@Service class AdvisoryLockService(...)
```

## TX-1 · TX-5 — Transactional placement and the boundary API

```kotlin
@Service
class OrderService(...) : Logger() {
    @Transactional(readOnly = true) fun getOrder(command: GetOrderCommand): OrderResult = ...
    @Transactional fun createOrder(command: CreateOrderCommand): OrderResult = ...
    fun quoteShippingFee(items: List<QuoteItem>): BigDecimal = ...   // No DB access — no annotation
    fun placeOrder(command: PlaceOrderCommand): PlaceOrderResult = ... // Orchestrates DB steps + an external call — no annotation (transactions §3)
}
// ❌ class-level (silently propagates the wrong attribute to newly added methods)
@Service @Transactional(readOnly = true) class OrderService(...)
```

Boundary API — `inTx` carries the block's own type through, so no call site needs a guard:

```kotlin
// ❌ hand-rolled REQUIRES_NEW with no reason to exist
private val tx = TransactionTemplate(requireNotNull(transactionTemplate.transactionManager) { "..." })
    .apply { propagationBehavior = PROPAGATION_REQUIRES_NEW }
// ❌ readOnly hidden in a field + execute's T? defended by requireNotNull
private val readTransactionTemplate = transactionTemplate.asReadOnly()
val page = requireNotNull(readTransactionTemplate.execute { ... }) { "... returned no result" }
// ✅
transactionRunner.inTx { ... }
```

## TX-2 · TX-4 — Split and compensate

Full skeleton of the transaction-splitting + explicit-compensation pattern:

```kotlin
// ❌ Bad — the external HTTP call is inside the transaction, so the row lock is held for its whole duration
@Transactional
fun placeOrder(command: CreateOrderCommand): PlaceOrderResult {
    val order = orderService.createOrder(command)        // INSERT (lock held, before commit)
    val payment = paymentClient.charge(order.id)         // HTTP — the payment system can't touch the same row
    return PlaceOrderResult.from(order, payment)
}

// ✅ Good — each DB step commits immediately under its own @Transactional; the external call is outside the transaction
fun placeOrder(command: CreateOrderCommand): PlaceOrderResult {
    val order = orderService.createOrder(command)        // commits under its own @Transactional (lock released)
    val payment = try {
        paymentClient.charge(order.id)                   // outside the transaction — the payment system can access the row freely
    } catch (e: Throwable) {
        safeDeleteOrder(order.id, command.memberId)      // explicit compensation
        throw e
    }
    return PlaceOrderResult.from(order, payment)
}

private fun safeDeleteOrder(orderId: UUID, memberId: UUID) {
    runCatching { orderService.deleteOrder(DeleteOrderCommand(orderId, memberId)) }
        .onFailure { e -> logger.warn(e) { "Failed to compensate: orderId=$orderId" } }
}
```

## TX-8 · TX-9 — Lock selection: advisory vs Redis

*If the project uses PostgreSQL advisory locks / Redis.*

```kotlin
// ✅ startup seeding — mutual exclusion is needed all the way to the commit
@EventListener(ApplicationReadyEvent::class)
@Transactional
fun init() {
    advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY))
    seedCategories()
}
// ✅ periodic work — if it is not acquired, the next cycle recovers
distributedLockTemplate.runIfAcquired(key = LOCK_KEY, ttl = LOCK_TTL) { staleOrderService.cancelStaleOrders() }
// ❌ advisory without @Transactional — the lock is released at once and blocks nothing (no error, no log)
@EventListener(ApplicationReadyEvent::class)
fun init() { advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY)); seedCategories() }
// ❌ a fallback that waits and then runs unlocked — it reads as if the "lock" guaranteed something it does not
fun runAwaitingLock(key: String, ...) {
    while (...) { if (runIfAcquired(...)) return }
    logger.warn { "Lock wait timed out, running unguarded" }
    block()
}
```

Narrow the boundary to lock + DB work only:

```kotlin
// ❌ work that must happen after the commit is dragged inside the transaction
@EventListener(ApplicationReadyEvent::class)
@Transactional
fun initialize() {
    advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY))
    ensureDefaultCategories()
    catalogSyncExecutor.execute { syncCatalog() }   // starts in the uncommitted state
}
// ✅ boundary covers only the lock + the DB work — acquireLocks sits inside the transaction inTx opens, so the advisory requirement still holds
@EventListener(ApplicationReadyEvent::class)
fun initialize() {
    transactionRunner.inTx {
        advisoryLockTemplate.acquireLocks(exclusiveKeys = listOf(LOCK_KEY))
        ensureDefaultCategories()
    }
    catalogSyncExecutor.execute { syncCatalog() }   // after the commit
}
```

## TX-10 — Lock-key helper

*If the project uses PostgreSQL advisory locks.*

Key-building rule lives in one private helper; call sites name only the target:

```kotlin
// ✅ the rule lives in one place; the call site passes only the target
private fun lockCategoryPaths(vararg paths: String) = lockCategoryPaths(paths.toList())
private fun lockCategoryPaths(paths: List<String>) {
    advisoryLockTemplate.acquireLocks(
        exclusiveKeys = paths.distinct(),
        sharedKeys = paths.flatMap { it.strictAncestorPaths() }.distinct(),
    )
}
lockCategoryPaths(command.path)
lockCategoryPaths(command.sourcePath, command.targetPath)

// ❌ the same rule spelled differently at every call site — omitting distinct() causes nothing to happen
acquireLocks(
    exclusiveKeys = listOf(command.sourcePath, command.targetPath).distinct(),
    sharedKeys = (command.sourcePath.strictAncestorPaths() + command.targetPath.strictAncestorPaths()).distinct(),
)
```
